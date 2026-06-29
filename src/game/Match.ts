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
import type { TeamId } from "../core/types.ts";

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

export interface MatchOptions {
  mapId: string;
  mode: ModeRules;
  botCount: number;
  difficulty: Difficulty;
  hasPlayer: boolean;
  playerWeaponDef?: WeaponDef;
  playerName?: string;
  respawnDelay?: number;
  warmup?: number;
}

const BOT_WEAPONS = ["m4", "ak12", "mp5", "scarl", "p90", "mk14", "uzi", "m16a4"];

export class Match {
  state: MatchState = "warmup";
  elapsed = 0;
  winner?: TeamId | number;
  winReason?: "score" | "time";
  readonly scoreboard = new Scoreboard();
  readonly killfeed: KillEvent[] = [];
  player: Player | null = null;
  bots: Bot[] = [];

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
    this.world = new MatchWorld(this.scene.mapRoot, () => this.actorList, this.pool, this.vfx);
    this.navigator = new Navigator(map.waypoints);
    this.spawner = new Spawner(map.spawns);

    const total = this.opts.botCount + (this.opts.hasPlayer ? 1 : 0);
    let slot = 0;

    if (this.opts.hasPlayer && this.camera && this.input) {
      const team = this.mode.assignTeam(slot++, total);
      this.player = new Player(this.camera, this.input, this.screen, {
        id: 0,
        team,
        weaponDef: this.opts.playerWeaponDef ?? getWeapon("m4"),
      });
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

  update(dt: number): void {
    this.vfx.update(dt);
    this.world.update(dt);
    this.screen.update(dt);
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

    // Win check.
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

  dispose(): void {
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
