// Match: the live game orchestrator.
//
// Builds a map, spawns the player (optional) + bots split by the mode's team
// rules, runs the per-frame simulation (player control, bot AI, projectiles,
// VFX), attributes kills to the scoreboard, respawns the dead after a delay, and
// ends when the mode's win condition (score cap or time limit) is met. Works
// headless with no player for pure bot-vs-bot matches / tests.

import * as THREE from "../three.ts";
import type { Scene } from "../core/Scene.ts";
import type { Camera } from "../core/Camera.ts";
import type { Input } from "../core/Input.ts";
import { VFX } from "../render/VFX.ts";
import { ScreenEffects, type ScreenEffectsApi } from "../render/ScreenEffects.ts";
import { getMap } from "../maps/maps.ts";
import type { MapBuild } from "../maps/MapDefinition.ts";
import { Navigator } from "../characters/BotNavigator.ts";
import { type Actor, Bot, type BotContext } from "../characters/Bot.ts";
import type { Difficulty } from "../characters/BotAI.ts";
import { ProceduralHuman } from "../characters/ProceduralHuman.ts";
import { ProjectilePool } from "../weapons/Projectile.ts";
import { getWeapon, type WeaponDef } from "../weapons/WeaponDefinition.ts";
import { MatchWorld } from "./MatchWorld.ts";
import { Player } from "./Player.ts";
import { Scoreboard } from "./Scoreboard.ts";
import { Spawner } from "./Spawner.ts";
import type { ModeRules } from "./Mode.ts";
import { SCORE } from "./Mode.ts";
import type { TeamId } from "../core/types.ts";
import { ScorestreakManager } from "../streaks/ScorestreakManager.ts";
import { getStreak, STREAKS } from "../streaks/streaks.ts";
import type { Streak, StreakContext, StreakOwner } from "../streaks/Streak.ts";
import { EquipmentManager, type LethalId, type TacticalId } from "../tacticals/EquipmentManager.ts";
import type { EquipmentContext } from "../tacticals/Equipment.ts";

export type MatchState = "warmup" | "live" | "end";

export interface KillEvent {
  killer?: string;
  killerTeam?: TeamId;
  weaponId?: string;
  victim: string;
  victimTeam: TeamId;
  headshot: boolean;
  time: number;
}

export interface MatchAudio {
  playerShot(weaponId: string): void;
  playerReload(): void;
  hitMarker(headshot: boolean, killed: boolean): void;
  enemyShot(weaponId: string, pos: THREE.Vector3): void;
  explosion(pos: THREE.Vector3, radius: number): void;
}

export interface MatchOptions {
  mapId: string;
  mode: ModeRules;
  botCount: number;
  difficulty: Difficulty;
  hasPlayer: boolean;
  playerWeaponDef?: WeaponDef;
  playerName?: string;
  playerAttachments?: string[];
  playerCamo?: number;
  playerStreaks?: string[];
  playerTactical?: string;
  playerLethal?: string;
  respawnDelay?: number;
  warmup?: number;
  audio?: MatchAudio;
}

const BOT_WEAPONS = ["m4", "ak12", "mp5", "scarl", "p90", "mk14", "uzi", "m16a4"];

export class Match {
  state: MatchState = "warmup";
  elapsed = 0;
  winner?: TeamId | number;
  winReason?: "score" | "time";
  readonly modeId: "tdm" | "ffa";
  readonly scoreboard = new Scoreboard();
  readonly streaks = new ScorestreakManager(STREAKS);
  readonly killfeed: KillEvent[] = [];
  player: Player | null = null;
  bots: Bot[] = [];

  // Active streaks + their owner; minimap intel state.
  private activeStreaks: { streak: Streak; owner: StreakOwner }[] = [];
  private pings: { team: TeamId; positions: THREE.Vector3[]; expire: number }[] = [];
  private counterUAV = new Map<TeamId, number>();
  private streakCtx!: StreakContext;
  private botStreakTimer = 0;
  private equipment!: EquipmentManager;
  private lastThrowG = -1;

  private actorList: Actor[] = [];
  private map!: MapBuild;
  private world!: MatchWorld;
  private pool!: ProjectilePool;
  private navigator!: Navigator;
  private spawner!: Spawner;
  private vfx!: VFX;
  private readonly screen: ScreenEffectsApi;
  private readonly mode: ModeRules;
  private respawnDelay: number;
  private warmupTimer: number;
  private prevAlive = new Map<number, boolean>();

  constructor(
    private scene: Scene,
    private camera: Camera | null,
    private input: Input | null,
    private opts: MatchOptions,
    screen?: ScreenEffectsApi,
  ) {
    this.mode = opts.mode;
    this.modeId = opts.mode.id;
    this.respawnDelay = opts.respawnDelay ?? 4;
    this.warmupTimer = opts.warmup ?? 2;
    this.screen = screen ?? new ScreenEffects();
  }

  build(): void {
    const map = getMap(this.opts.mapId).build();
    this.map = map;
    this.scene.setEnvironment(map.environment);
    this.scene.clearMap();
    this.scene.addToMap(map.root);

    this.pool = new ProjectilePool(this.scene.dynamicRoot);
    this.vfx = new VFX(this.scene.three);
    const audio = this.opts.audio;
    if (audio) this.vfx.onExplosion = (c, r) => audio.explosion(c, r);
    this.world = new MatchWorld(this.scene.mapRoot, () => this.actorList, this.pool, this.vfx);
    this.navigator = new Navigator(map.waypoints);
    this.spawner = new Spawner(map.spawns);
    this.streakCtx = this.buildStreakContext();

    const total = this.opts.botCount + (this.opts.hasPlayer ? 1 : 0);
    let slot = 0;

    if (this.opts.hasPlayer && this.camera && this.input) {
      const team = this.mode.assignTeam(slot++, total);
      this.player = new Player(this.camera, this.input, this.screen, {
        id: 0,
        team,
        weaponDef: this.opts.playerWeaponDef ?? getWeapon("m4"),
        attachments: this.opts.playerAttachments ?? [],
        camoColor: this.opts.playerCamo,
      });
      if (this.opts.playerStreaks) this.streaks.setLoadout(0, this.opts.playerStreaks);
      if (audio) {
        this.player.events = {
          onShot: (id) => audio.playerShot(id),
          onReload: () => audio.playerReload(),
          onHit: (hs, killed) => audio.hitMarker(hs, killed),
        };
      }
      this.scoreboard.register(0, this.opts.playerName ?? "You", team, true);
      this.actorList.push(this.player);
    }

    for (let i = 0; i < this.opts.botCount; i++) {
      const team = this.mode.assignTeam(slot++, total);
      const id = 1 + i;
      const def = getWeapon(BOT_WEAPONS[i % BOT_WEAPONS.length]);
      const bot = new Bot({
        id,
        team,
        difficulty: this.opts.difficulty,
        character: new ProceduralHuman({ team, accentIndex: i }),
        weaponDef: def,
        spawn: new THREE.Vector3(),
        onShot: audio ? (wid, pos) => audio.enemyShot(wid, pos) : undefined,
      });
      this.scoreboard.register(id, `Bot ${id}`, team);
      this.scene.add(bot.character.root);
      this.bots.push(bot);
      this.actorList.push(bot);
    }

    // Initial spawns (no enemies yet -> round-robin).
    for (const a of this.actorList) {
      const sp = this.spawner.pick(a.team, []);
      this.placeActor(a, sp.position, sp.yaw);
      this.prevAlive.set(a.id, true);
    }

    // Player throwables.
    const eqCtx: EquipmentContext = {
      world: this.world,
      vfx: this.vfx,
      root: this.scene.dynamicRoot,
      screen: this.screen,
      getPlayerPosition: (out) => this.player ? this.player.position(out) : out.set(0, 1, 0),
      getPlayerTeam: () => this.player ? this.player.team : "ffa",
      onSnapshot: (positions) => {
        if (this.player) {
          this.pings.push({ team: this.player.team, positions, expire: this.elapsed + 5 });
        }
      },
    };
    this.equipment = new EquipmentManager(eqCtx);
  }

  playerThrowTactical(): void {
    if (!this.player?.alive || !this.camera) return;
    const origin = this.player.eyePosition(new THREE.Vector3());
    const dir = this.camera.getLookDirection(new THREE.Vector3());
    this.equipment.throwTactical(
      (this.opts.playerTactical ?? "flashbang") as TacticalId,
      { origin, direction: dir, team: this.player.team },
    );
  }

  playerThrowLethal(): void {
    if (!this.player?.alive || !this.camera) return;
    const lethal = (this.opts.playerLethal ?? "frag") as LethalId;
    if (lethal === "c4" && this.elapsed - this.lastThrowG < 0.35) {
      this.equipment.detonateC4();
      this.lastThrowG = this.elapsed;
      return;
    }
    const origin = this.player.eyePosition(new THREE.Vector3());
    const dir = this.camera.getLookDirection(new THREE.Vector3());
    this.equipment.throwLethal(lethal, { origin, direction: dir, team: this.player.team });
    this.lastThrowG = this.elapsed;
  }

  private placeActor(a: Actor, pos: THREE.Vector3, yaw: number): void {
    const ground = this.map.groundAt(pos.x, pos.z);
    const p = pos.clone();
    p.y = ground;
    if (a === (this.player as unknown)) {
      this.player!.spawnAt(p, yaw);
    } else {
      (a as Bot).respawn(p, yaw);
    }
  }

  get timeLeft(): number {
    return Math.max(0, this.mode.timeLimit - this.elapsed);
  }

  get bounds(): { minX: number; maxX: number; minZ: number; maxZ: number } {
    return this.map.bounds;
  }

  update(dt: number): void {
    this.vfx.update(dt);
    this.world.update(dt);
    this.screen.update(dt);
    this.equipment.update(dt);
    this.map.update?.(dt, this.elapsed);

    if (this.state === "warmup") {
      this.warmupTimer -= dt;
      if (this.warmupTimer <= 0) this.state = "live";
    }

    // Simulate actors.
    if (this.player) {
      this.player.update(dt, {
        world: this.world,
        vfx: this.vfx,
        collision: this.map.collision,
        groundAt: (x, z) => this.map.groundAt(x, z),
      });
    }
    const ctx: BotContext = {
      world: this.world,
      collision: this.map.collision,
      navigator: this.navigator,
      vfx: this.vfx,
      actors: this.actorList,
      groundAt: (x, z) => this.map.groundAt(x, z),
      bounds: this.map.bounds,
    };
    for (const bot of this.bots) bot.update(dt, ctx);

    if (this.state !== "live") return;
    this.elapsed += dt;

    // Deaths -> scoreboard + killfeed.
    for (const a of this.actorList) {
      const was = this.prevAlive.get(a.id) ?? true;
      if (was && !a.alive) this.onDeath(a);
      this.prevAlive.set(a.id, a.alive);
    }

    // Respawns.
    for (const a of this.actorList) {
      if (!a.alive && this.timeDead(a) >= this.respawnDelay) {
        const enemies = this.enemyPositions(a.team);
        const sp = this.spawner.pick(a.team, enemies);
        this.placeActor(a, sp.position, sp.yaw);
        this.prevAlive.set(a.id, true);
      }
    }

    this.updateStreaks(dt);

    // Win check (a nuke streak may have already ended the match above).
    if (this.state !== "live") return;
    const win = this.mode.checkWin(this.scoreboard, this.elapsed);
    if (win.over) {
      this.state = "end";
      this.winner = win.winner;
      this.winReason = win.reason;
      console.info("[match] over —", this.formatWinner());
      console.info(this.scoreboard.format());
    }
  }

  private timeDead(a: Actor): number {
    return (a as Bot).timeDead ?? (a === (this.player as unknown) ? this.player!.timeDead : 0);
  }

  private enemyPositions(team: TeamId): THREE.Vector3[] {
    const out: THREE.Vector3[] = [];
    const p = new THREE.Vector3();
    for (const a of this.actorList) {
      if (!a.alive) continue;
      if (team !== "ffa" && a.team === team) continue;
      out.push(a.position(p).clone());
    }
    return out;
  }

  private onDeath(victim: Actor): void {
    const info = (victim as Bot | Player).lastDamage;
    const killerId = info?.sourceId;
    const headshot = info?.headshot ?? false;
    this.scoreboard.recordKill(killerId, victim.id, headshot);
    if (killerId !== undefined && killerId !== victim.id) {
      this.streaks.addScore(killerId, SCORE.kill + (headshot ? SCORE.headshotBonus : 0));
    }
    const killer = killerId !== undefined && killerId !== victim.id
      ? this.scoreboard.get(killerId)
      : undefined;
    const v = this.scoreboard.get(victim.id);
    this.killfeed.push({
      killer: killer?.name,
      killerTeam: killer?.team,
      weaponId: info?.weaponId,
      victim: v.name,
      victimTeam: v.team,
      headshot,
      time: this.elapsed,
    });
    if (this.killfeed.length > 8) this.killfeed.shift();
  }

  formatWinner(): string {
    if (this.winner === undefined) return "Draw";
    if (typeof this.winner === "string") return `${this.winner.toUpperCase()} team wins`;
    return `${this.scoreboard.get(this.winner).name} wins`;
  }

  // ---- Scorestreaks ----
  private buildStreakContext(): StreakContext {
    return {
      world: this.world,
      vfx: this.vfx,
      root: this.scene.dynamicRoot,
      owner: { id: -1, team: "ffa" }, // mutated per-streak before each update
      allActors: () => this.actorList,
      enemiesOf: (team) =>
        this.actorList.filter((a) =>
          a.alive && a.id !== this.streakCtx.owner.id && (team === "ffa" || a.team !== team)
        ),
      groundAt: (x, z) => this.map.groundAt(x, z),
      bounds: this.map.bounds,
      ping: (team, positions, dur) =>
        this.pings.push({ team, positions, expire: this.elapsed + dur }),
      setCounterUAV: (against, dur) => this.counterUAV.set(against, this.elapsed + dur),
      spawnCarePackage: (_pos, owner) => this.activateStreak(owner, "care_package"),
      grantRandomStreak: (owner) => this.grantRandomStreak(owner),
      endMatch: (winner) => this.endByStreak(winner),
      localPlayerId: this.player ? this.player.id : null,
    };
  }

  /** Activate a streak for an owner (player UI or bot AI). */
  activateStreak(owner: StreakOwner, streakId: string): void {
    const streak = getStreak(streakId).create();
    this.activeStreaks.push({ streak, owner });
    this.streaks.markActive(owner.id, streakId);
  }

  /** Player-side activation: only if currently available. Returns success. */
  activatePlayerStreak(streakId: string): boolean {
    if (!this.player || !this.streaks.isAvailable(this.player.id, streakId)) return false;
    this.activateStreak({ id: this.player.id, team: this.player.team }, streakId);
    return true;
  }

  private grantRandomStreak(owner: StreakOwner): string {
    const pick = STREAKS[Math.floor(Math.random() * (STREAKS.length - 1))]; // exclude nuke (last)
    this.activateStreak(owner, pick.id);
    return pick.id;
  }

  private endByStreak(winner: TeamId | number): void {
    this.state = "end";
    this.winner = winner;
    this.winReason = "score";
    console.info("[match] nuke —", this.formatWinner());
    console.info(this.scoreboard.format());
  }

  private updateStreaks(dt: number): void {
    // Tick active streaks (set owner so context queries resolve correctly).
    for (let i = this.activeStreaks.length - 1; i >= 0; i--) {
      const entry = this.activeStreaks[i];
      this.streakCtx.owner = entry.owner;
      entry.streak.update(dt, this.streakCtx);
      if (!entry.streak.active) {
        entry.streak.dispose(this.streakCtx);
        this.streaks.markEnded(entry.owner.id, entry.streak.id);
        this.activeStreaks.splice(i, 1);
      }
    }
    // Expire minimap pings.
    if (this.pings.length) this.pings = this.pings.filter((p) => p.expire > this.elapsed);

    // Bots auto-use their best available streak periodically.
    this.botStreakTimer -= dt;
    if (this.botStreakTimer <= 0) {
      this.botStreakTimer = 2;
      for (const bot of this.bots) {
        if (!bot.alive) continue;
        const best = this.streaks.bestAvailable(bot.id);
        if (best) this.activateStreak({ id: bot.id, team: bot.team }, best.id);
      }
    }
  }

  /** Enemy positions currently revealed to `team` (UAV), respecting Counter-UAV. */
  activePings(team: TeamId): THREE.Vector3[] {
    const blockedUntil = this.counterUAV.get(team) ?? 0;
    if (blockedUntil > this.elapsed) return [];
    const out: THREE.Vector3[] = [];
    for (const p of this.pings) {
      if (p.team === team) out.push(...p.positions);
    }
    return out;
  }

  isCounterUAV(team: TeamId): boolean {
    return (this.counterUAV.get(team) ?? 0) > this.elapsed;
  }

  dispose(): void {
    this.equipment?.clear();
    for (const e of this.activeStreaks) e.streak.dispose(this.streakCtx);
    this.activeStreaks = [];
    this.player?.dispose();
    for (const b of this.bots) {
      this.scene.dynamicRoot.remove(b.character.root);
      b.character.dispose();
    }
    this.bots = [];
    this.actorList = [];
    this.pool?.clear();
    this.vfx?.clear();
    this.screen.clear();
  }
}
