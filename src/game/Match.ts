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
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
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

/** A world object the player can collect (Press E) and bots may auto-grab. */
interface Interactable {
  mesh: THREE.Object3D;
  pos: THREE.Vector3;
  radius: number; // player E range (world units)
  botRadius: number; // bots auto-collect within this (0 = players only)
  label: string; // HUD prompt text
  expire: number; // match-elapsed seconds after which it disappears
  use(collectorId: number): void;
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
  playerSecondaryDef?: WeaponDef;
  playerSecondaryAttachments?: string[];
  playerName?: string;
  playerAttachments?: string[];
  playerCamo?: number;
  playerStreaks?: string[];
  playerPerks?: string[];
  playerTactical?: string;
  playerLethal?: string;
  respawnDelay?: number;
  warmup?: number;
  hardcore?: boolean;
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
  private playerHasScavenger = false;
  private ammoPickups: { mesh: THREE.Object3D; pos: THREE.Vector3; expire: number }[] = [];
  private interactables: Interactable[] = [];
  /** Current "Press E — …" prompt for the local player, or null. Read by Game. */
  interactPrompt: string | null = null;

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
      if (this.opts.playerSecondaryDef) {
        this.player.setLoadout(
          this.opts.playerWeaponDef ?? getWeapon("m4"),
          this.opts.playerSecondaryDef,
          this.opts.playerAttachments ?? [],
          this.opts.playerSecondaryAttachments ?? [],
        );
      }
      if (this.opts.playerStreaks) this.streaks.setLoadout(0, this.opts.playerStreaks);
      this.playerHasScavenger = !!this.opts.playerPerks?.includes("scavenger");
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

    // Hardcore: 30 HP, no regen, applied before spawns set health = maxHealth.
    if (this.opts.hardcore) {
      this.player?.setHardcore();
      for (const b of this.bots) {
        b.maxHealth = 30;
        b.health = 30;
      }
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

    this.updateAmmoPickups(dt);
    this.updateInteractables(dt);
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

    // Drop the victim's weapon (with its leftover ammo) for anyone to pick up.
    const vw = (victim as Bot | Player).weapon;
    if (vw) {
      this.addWeaponDrop(vw.def, vw.magazine, vw.reserve, victim.position(new THREE.Vector3()));
    }

    // Scavenger perk: enemies drop ammo the player can collect.
    if (
      this.playerHasScavenger && this.player &&
      victim !== (this.player as unknown as Actor) &&
      (this.player.team === "ffa" || victim.team !== this.player.team)
    ) {
      this.spawnAmmoPickup(victim);
    }
  }

  private spawnAmmoPickup(victim: Actor): void {
    const pos = victim.position(new THREE.Vector3());
    pos.y = this.map.groundAt(pos.x, pos.z) + 0.4;
    const mesh = new THREE.Mesh(
      new THREE.BoxGeometry(0.5, 0.35, 0.5),
      createToonMaterial({ color: 0xffcc33, emissive: 0x3a2c00 }),
    );
    mesh.position.copy(pos);
    addOutline(mesh, { thickness: 0.03 });
    this.scene.dynamicRoot.add(mesh);
    this.ammoPickups.push({ mesh, pos: pos.clone(), expire: this.elapsed + 25 });
  }

  private updateAmmoPickups(dt: number): void {
    if (this.ammoPickups.length === 0) return;
    const p = this.player;
    const feet = p ? p.feet : null;
    for (let i = this.ammoPickups.length - 1; i >= 0; i--) {
      const pk = this.ammoPickups[i];
      pk.mesh.rotation.y += dt * 2;
      let collected = false;
      if (p && p.alive && feet) {
        const dx = feet.x - pk.pos.x;
        const dz = feet.z - pk.pos.z;
        if (dx * dx + dz * dz < 1.8 * 1.8) {
          // Resupply: top up the magazine + refill reserve to max.
          p.weapon.reserve = p.weapon.stats.reserve;
          p.weapon.magazine = p.weapon.stats.magazine;
          this.screen.tint("rgb(255,204,51)", 0.25, 0.4);
          collected = true;
        }
      }
      if (collected || this.elapsed >= pk.expire) {
        this.scene.dynamicRoot.remove(pk.mesh);
        (pk.mesh as THREE.Mesh).geometry.dispose();
        this.ammoPickups.splice(i, 1);
      }
    }
  }

  // ---- Interactables (weapon drops + care packages) ----

  private teamOf(id: number): TeamId {
    const a = this.actorList.find((x) => x.id === id);
    return a ? a.team : "ffa";
  }

  /** Drop a weapon on the ground that the player can swap to with E. */
  private addWeaponDrop(
    def: WeaponDef,
    magazine: number,
    reserve: number,
    pos: THREE.Vector3,
  ): void {
    const group = new THREE.Group();
    const body = new THREE.Mesh(
      new THREE.BoxGeometry(0.72, 0.13, 0.13),
      createToonMaterial({ color: 0x2b2f36 }),
    );
    addOutline(body, { thickness: 0.02 });
    group.add(body);
    const mag = new THREE.Mesh(
      new THREE.BoxGeometry(0.12, 0.22, 0.1),
      createToonMaterial({ color: 0x14171c }),
    );
    mag.position.set(-0.04, -0.16, 0);
    group.add(mag);
    group.position.set(pos.x, this.map.groundAt(pos.x, pos.z) + 0.5, pos.z);
    group.rotation.z = 0.25;
    this.scene.dynamicRoot.add(group);
    this.interactables.push({
      mesh: group,
      pos: group.position.clone(),
      radius: 1.9,
      botRadius: 0,
      label: `Press E — ${def.name} (${magazine}/${reserve})`,
      expire: this.elapsed + 30,
      use: (collectorId) => {
        if (this.player && collectorId === this.player.id) {
          this.player.equipDropped(def, magazine, reserve);
        }
      },
    });
  }

  /** Register a landed care package: persists, collectible by E (player) or bots. */
  private armCarePackage(pos: THREE.Vector3): void {
    const group = new THREE.Group();
    const crate = new THREE.Mesh(
      new THREE.BoxGeometry(1.2, 1.2, 1.2),
      createToonMaterial({ color: 0xcf9233, emissive: 0x3a2400 }),
    );
    addOutline(crate, { thickness: 0.045 });
    group.add(crate);
    const beam = new THREE.Mesh(
      new THREE.CylinderGeometry(0.18, 0.18, 9, 8, 1, true),
      new THREE.MeshBasicMaterial({ color: 0xcdeb6e, transparent: true, opacity: 0.22 }),
    );
    beam.position.y = 4.6;
    group.add(beam);
    group.position.set(pos.x, this.map.groundAt(pos.x, pos.z) + 0.6, pos.z);
    this.scene.dynamicRoot.add(group);
    this.interactables.push({
      mesh: group,
      pos: group.position.clone(),
      radius: 2.5,
      botRadius: 2.5,
      label: "Press E — Care Package",
      expire: this.elapsed + 60,
      use: (collectorId) => {
        this.grantRandomStreak({ id: collectorId, team: this.teamOf(collectorId) });
      },
    });
  }

  private updateInteractables(dt: number): void {
    this.interactPrompt = null;
    if (this.interactables.length === 0) return;
    const remove = new Set<Interactable>();

    for (const it of this.interactables) {
      it.mesh.rotation.y += dt * 1.5;
      if (this.elapsed >= it.expire) {
        remove.add(it);
        continue;
      }
      // Bots auto-collect (care packages only; weapon drops use botRadius 0).
      if (it.botRadius > 0) {
        for (const b of this.bots) {
          if (!b.alive) continue;
          const dx = b.feet.x - it.pos.x;
          const dz = b.feet.z - it.pos.z;
          if (dx * dx + dz * dz < it.botRadius * it.botRadius) {
            it.use(b.id);
            remove.add(it);
            break;
          }
        }
      }
    }

    // Nearest interactable in range of the local player -> prompt + E to use.
    const p = this.player;
    if (p && p.alive) {
      let nearest: Interactable | null = null;
      let nd = Infinity;
      for (const it of this.interactables) {
        if (remove.has(it)) continue;
        const dx = p.feet.x - it.pos.x;
        const dz = p.feet.z - it.pos.z;
        const d = dx * dx + dz * dz;
        if (d < it.radius * it.radius && d < nd) {
          nd = d;
          nearest = it;
        }
      }
      if (nearest) {
        this.interactPrompt = nearest.label;
        if (this.input?.wasPressed("interact")) {
          nearest.use(p.id);
          remove.add(nearest);
          this.interactPrompt = null;
        }
      }
    }

    if (remove.size) {
      for (const it of remove) {
        this.scene.dynamicRoot.remove(it.mesh);
        disposeObject(it.mesh);
      }
      this.interactables = this.interactables.filter((it) => !remove.has(it));
    }
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
      armCarePackage: (pos) => this.armCarePackage(pos),
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
    for (const pk of this.ammoPickups) this.scene.dynamicRoot.remove(pk.mesh);
    this.ammoPickups = [];
    for (const it of this.interactables) {
      this.scene.dynamicRoot.remove(it.mesh);
      disposeObject(it.mesh);
    }
    this.interactables = [];
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

/** Recursively dispose geometries/materials under an object (for pickups). */
function disposeObject(obj: THREE.Object3D): void {
  obj.traverse((o) => {
    const m = o as THREE.Mesh;
    if (m.geometry) m.geometry.dispose();
    const mat = (m as THREE.Mesh).material;
    if (Array.isArray(mat)) mat.forEach((x) => x.dispose());
    else if (mat) (mat as THREE.Material).dispose();
  });
}
