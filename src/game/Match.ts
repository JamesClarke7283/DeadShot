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
import type { Attachment } from "../weapons/AttachmentDefinitions.ts";
import { MatchWorld } from "./MatchWorld.ts";
import { Player } from "./Player.ts";
import { Scoreboard } from "./Scoreboard.ts";
import { Spawner } from "./Spawner.ts";
import type { ModeId, ModeRules, WinResult } from "./Mode.ts";
import { SCORE } from "./Mode.ts";
import { GUN_GAME_TIERS, GunGameTracker } from "./GunGame.ts";
import type { TeamId } from "../core/types.ts";
import { ScorestreakManager } from "../streaks/ScorestreakManager.ts";
import { getStreak, STREAKS } from "../streaks/streaks.ts";
import type { Streak, StreakContext, StreakOwner } from "../streaks/Streak.ts";
import { EquipmentManager, type LethalId, type TacticalId } from "../tacticals/EquipmentManager.ts";
import type { EquipmentContext } from "../tacticals/Equipment.ts";
import type { NetClient } from "../net/NetClient.ts";
import { RemoteActor } from "./RemoteActor.ts";
import type { BotStateMsg, LobbyPlayer, PlayerStateMsg } from "../net/protocol.ts";
import { type ActorSnap, type ReplayFrame, ReplayRecorder } from "./ReplayRecorder.ts";
import type { AnimName } from "../characters/Character.ts";
import { buildObjective, type Objective, type ObjectiveHud } from "./Objectives.ts";

/** A captured death replay (last seconds before the player died). */
export interface KillcamData {
  frames: ReplayFrame[];
  killerId: number | undefined;
  victimId: number;
  killerName: string;
}

/** A captured "best play" (the player's longest killstreak window). */
export interface BestPlayData {
  frames: ReplayFrame[];
  kills: number;
  playerId: number;
}

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
  // ---- Networked (relay) mode ----
  net?: NetClient;
  isHost?: boolean;
  selfId?: number;
  roster?: LobbyPlayer[];
}

// A wide spread across every category (interleaved so cycling gives a varied
// mix of enemy weapons each match). Launchers are left out of the bot pool.
const MELEE_RANGE = 2.5;
const MELEE_DAMAGE = 55;
const BOT_WEAPONS = [
  "m4",
  "mp5",
  "rpk",
  "kar98",
  "scarl",
  "vector",
  "mk14",
  "spas12",
  "ak12",
  "p90",
  "m249",
  "barrett",
  "m16a4",
  "uzi",
  "ksg",
  "deagle",
];

export class Match {
  state: MatchState = "warmup";
  elapsed = 0;
  winner?: TeamId | number;
  winReason?: "score" | "time";
  readonly modeId: ModeId;
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

  // ---- Networked (relay) mode ----
  private net: NetClient | null = null;
  private isHost = false;
  private remotes = new Map<number, RemoteActor>();
  private netSendTimer = 0;

  // ---- Objective modes (Domination / CTF) ----
  private objective: Objective | null = null;

  // ---- Gun Game ----
  private gunGame: GunGameTracker | null = null;
  private meleeCooldown = 0;

  // ---- Replay (killcam + best play) ----
  private readonly recorder = new ReplayRecorder(10, 30);
  private playerStreak = 0;
  private streakStartT = 0;
  killcam: KillcamData | null = null;
  bestPlay: BestPlayData | null = null;
  // Host bot ids start far above any plausible server-assigned connection id so
  // they never collide with player ids over a long-lived relay server.
  private static readonly BOT_BASE = 1_000_000;

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
    this.net = this.opts.net ?? null;
    this.isHost = !!this.opts.isHost;
    const net = this.net;

    const total = this.opts.botCount + (this.opts.hasPlayer ? 1 : 0);
    let slot = 0;
    const playerId = net ? (this.opts.selfId ?? 0) : 0;

    if (this.opts.hasPlayer && this.camera && this.input) {
      const team = net ? this.rosterTeam(playerId) : this.mode.assignTeam(slot++, total);
      this.player = new Player(this.camera, this.input, this.screen, {
        id: playerId,
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
      if (this.opts.playerStreaks) this.streaks.setLoadout(playerId, this.opts.playerStreaks);
      this.playerHasScavenger = !!this.opts.playerPerks?.includes("scavenger");
      if (audio) {
        this.player.events = {
          onShot: (id) => audio.playerShot(id),
          onReload: () => audio.playerReload(),
          onHit: (hs, killed) => audio.hitMarker(hs, killed),
        };
      }
      this.scoreboard.register(playerId, this.opts.playerName ?? "You", team, true);
      this.actorList.push(this.player);
    }

    // Bots: simulated locally only single-player or by the room host.
    if (!net || this.isHost) {
      const gunGame = this.modeId === "gungame";
      for (let i = 0; i < this.opts.botCount; i++) {
        const team = net ? this.netTeamForIndex(i) : this.mode.assignTeam(slot++, total);
        const id = net ? Match.BOT_BASE + i : 1 + i;
        // Gun Game: everyone starts on the pistol (tier 0).
        const def = gunGame
          ? getWeapon(GUN_GAME_TIERS[0])
          : getWeapon(BOT_WEAPONS[i % BOT_WEAPONS.length]);
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
    }

    // Remote players (mirrored from peers) + network message handlers.
    if (net) {
      const roster = this.opts.roster ?? [];
      let accent = 0;
      for (const pl of roster) {
        if (pl.id === playerId) continue;
        this.addRemote(pl.id, pl.team, pl.name, accent++);
      }
      this.registerNetHandlers();
    }

    // Hardcore: 30 HP, no regen, applied before spawns set health = maxHealth.
    if (this.opts.hardcore) {
      this.player?.setHardcore();
      for (const b of this.bots) {
        b.maxHealth = 30;
        b.health = 30;
      }
    }

    // Initial spawns. Place actors one at a time, each avoiding the enemies
    // already placed, so teams start apart (enemies far from allies).
    const placed: { team: TeamId; pos: THREE.Vector3 }[] = [];
    for (const a of this.ownedActors()) {
      const enemies = placed
        .filter((p) => a.team === "ffa" || p.team !== a.team)
        .map((p) => p.pos);
      const sp = this.spawner.pick(a.team, enemies);
      this.placeActor(a, sp.position, sp.yaw);
      placed.push({ team: a.team, pos: sp.position.clone() });
      this.prevAlive.set(a.id, true);
    }
    for (const ra of this.remotes.values()) this.prevAlive.set(ra.id, true);

    // Objective mode (Domination / CTF): build + show its world meshes.
    if (this.mode.objective) {
      this.objective = buildObjective(
        this.mode.objective,
        this.map.bounds,
        (x, z) => this.map.groundAt(x, z),
      );
      this.scene.add(this.objective.root);
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

    // Gun Game: register every owned actor in the tracker at tier 0, force the
    // player onto the pistol, and arm the throwing knife as the lethal so the
    // final tier (a knife kill) is achievable.
    if (this.modeId === "gungame") {
      this.gunGame = new GunGameTracker();
      if (this.player) {
        this.gunGame.register(this.player.id);
        this.player.setWeapon(getWeapon(GUN_GAME_TIERS[0]));
      }
      for (const b of this.bots) this.gunGame.register(b.id);
      this.opts.playerLethal = "knife";
    }
  }

  playerThrowTactical(): void {
    if (!this.player?.alive || !this.camera) return;
    const origin = this.player.eyePosition(new THREE.Vector3());
    const dir = this.camera.getLookDirection(new THREE.Vector3());
    this.equipment.throwTactical(
      (this.opts.playerTactical ?? "flashbang") as TacticalId,
      { origin, direction: dir, team: this.player.team, sourceId: this.player.id },
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
    this.equipment.throwLethal(lethal, {
      origin,
      direction: dir,
      team: this.player.team,
      sourceId: this.player.id,
    });
    this.lastThrowG = this.elapsed;
  }

  /**
   * Player melee knife (KeyK): a short-range forward hitscan that deals lethal
   * damage to the first enemy hit. Usable in every mode. Cooldown ~0.8s. In Gun
   * Game, a melee kill drops the victim one weapon tier (see applyGunGameDeath).
   */
  playerMelee(): void {
    if (!this.player?.alive || !this.camera) return;
    if (this.meleeCooldown > 0) return;
    this.meleeCooldown = 0.8;
    const origin = this.player.eyePosition(new THREE.Vector3());
    const dir = this.camera.getLookDirection(new THREE.Vector3());
    const hit = this.world.raycast(origin, dir, MELEE_RANGE);
    if (hit) {
      const target = hit.target;
      if (
        target && target.alive && (this.player.team === "ffa" || target.team !== this.player.team)
      ) {
        target.applyDamage({
          amount: MELEE_DAMAGE,
          headshot: false,
          sourceTeam: this.player.team,
          weaponId: "melee",
          sourceId: this.player.id,
        });
      }
      this.vfx.bulletImpact(hit.point, hit.normal, !!target);
    }
  }

  /** Gun Game HUD state for the local player, or null outside Gun Game. */
  gunGameHud(): { tier: number; maxTier: number; weaponName: string } | null {
    const gg = this.gunGame;
    if (!gg || !this.player) return null;
    const tier = gg.tierOf(this.player.id);
    const weaponId = gg.weaponIdOf(this.player.id);
    const name = weaponId === "knife" ? "Throwing Knife" : getWeapon(weaponId).name;
    return { tier, maxTier: GUN_GAME_TIERS.length, weaponName: name };
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

  /** Immediately respawn the local player (used when the killcam is skipped). */
  respawnPlayerNow(): void {
    if (!this.player || this.player.alive) return;
    const sp = this.spawner.pick(this.player.team, this.enemyPositions(this.player.team));
    this.placeActor(this.player, sp.position, sp.yaw);
    this.prevAlive.set(this.player.id, true);
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
    if (this.meleeCooldown > 0) this.meleeCooldown -= dt;

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
      objectiveGoal: (a) => this.objective?.goalFor(a) ?? null,
    };
    for (const bot of this.bots) bot.update(dt, ctx);
    // Remote players/bots are driven by the network, not simulated locally.
    for (const ra of this.remotes.values()) ra.update(dt);
    // Sync our transform to peers every frame (including warmup, so players see
    // each other before the match goes live).
    if (this.net) this.netSync(dt);

    if (this.state !== "live") return;
    this.elapsed += dt;

    // Deaths -> scoreboard + killfeed. Only watch actors WE own; remote deaths
    // arrive over the network (see onRemoteDeath).
    for (const a of this.ownedActors()) {
      const was = this.prevAlive.get(a.id) ?? true;
      if (was && !a.alive) this.onDeath(a);
      this.prevAlive.set(a.id, a.alive);
    }

    // Respawns (owned actors only; remotes respawn on their owner).
    for (const a of this.ownedActors()) {
      if (!a.alive && this.timeDead(a) >= this.respawnDelay) {
        const enemies = this.enemyPositions(a.team);
        const sp = this.spawner.pick(a.team, enemies);
        this.placeActor(a, sp.position, sp.yaw);
        this.prevAlive.set(a.id, true);
      }
    }

    this.updateAmmoPickups(dt);
    this.updateInteractables(dt);
    this.objective?.update(dt, {
      actors: this.actorList,
      groundAt: (x, z) => this.map.groundAt(x, z),
      bounds: this.map.bounds,
    });
    if (this.modeId !== "gungame") this.updateStreaks(dt);
    this.recorder.record(this.elapsed, this.snapshotActors());

    // Win check (a nuke streak may have already ended the match above).
    if (this.state !== "live") return;
    let win: WinResult;
    if (this.gunGame) {
      // Gun Game: a knife kill on the final tier flags the winner in the tracker.
      const winnerId = this.gunGame.winner;
      win = winnerId !== undefined
        ? { over: true, winner: winnerId, reason: "score" }
        : this.mode.checkWin(this.scoreboard, this.elapsed);
    } else {
      win = this.objective
        ? this.objective.isOver(this.elapsed, this.mode.timeLimit)
        : this.mode.checkWin(this.scoreboard, this.elapsed);
    }
    if (win.over) {
      this.finalizeBestPlay(); // capture a streak the player was still on
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

  /** A locally-owned actor died: score it, drop loot, and broadcast (networked). */
  private onDeath(victim: Actor): void {
    const info = (victim as Bot | Player).lastDamage;
    const killerId = info?.sourceId;
    const headshot = info?.headshot ?? false;
    this.scoreboard.recordKill(killerId, victim.id, headshot);
    if (killerId !== undefined && killerId !== victim.id && this.modeId !== "gungame") {
      this.streaks.addScore(killerId, SCORE.kill + (headshot ? SCORE.headshotBonus : 0));
    }
    this.addKillfeed(killerId, victim, info?.weaponId, headshot);
    this.applyGunGameDeath(killerId, victim, info?.weaponId);
    if (this.modeId !== "gungame") this.dropVictimWeapon(victim);
    this.maybeScavenger(victim);
    this.trackPlayerKD(killerId, victim.id);
    if (this.net) this.net.sendDeath(victim.id, killerId, info?.weaponId, headshot);
  }

  /** A remote-owned actor died (relayed): mirror score + loot, no re-broadcast. */
  private onRemoteDeath(
    victimId: number,
    killerId: number | undefined,
    weaponId: string | undefined,
    headshot: boolean,
  ): void {
    this.scoreboard.recordKill(killerId, victimId, headshot);
    // Credit the killer's streak score locally too, so the killer's own client
    // (which only ever sees this kill as a relayed death) fills its streak meter.
    if (killerId !== undefined && killerId !== victimId && this.modeId !== "gungame") {
      this.streaks.addScore(killerId, SCORE.kill + (headshot ? SCORE.headshotBonus : 0));
    }
    const victim = this.actorList.find((a) => a.id === victimId);
    if (!victim) return;
    this.addKillfeed(killerId, victim, weaponId, headshot);
    this.applyGunGameDeath(killerId, victim, weaponId);
    if (this.modeId !== "gungame") this.dropVictimWeapon(victim);
    this.maybeScavenger(victim);
    this.trackPlayerKD(killerId, victimId);
    const ra = this.remotes.get(victimId);
    if (ra) ra.markDead();
    this.prevAlive.set(victimId, false);
  }

  /**
   * Gun Game tier progression: a gun kill with the killer's current-tier weapon
   * advances them one tier (and swaps their weapon); a melee ("melee") death
   * drops the victim a tier. A knife kill on the knife tier wins the match.
   * No-op outside Gun Game.
   */
  private applyGunGameDeath(
    killerId: number | undefined,
    victim: Actor,
    weaponId: string | undefined,
  ): void {
    const gg = this.gunGame;
    if (!gg) return;

    // Knifed (melee swing) -> victim drops a tier.
    if (weaponId === "melee") {
      const down = gg.onMeleeDeath(victim.id);
      if (down) this.equipTier(down.id, down.weaponId);
      return;
    }

    // A kill -> killer advances a tier (if made with their current-tier weapon).
    if (killerId === undefined || killerId === victim.id) return;
    const killerIsBot = killerId !== this.player?.id;
    const up = gg.onKill(killerId, victim.id, weaponId, killerIsBot);
    if (up) this.equipTier(up.id, up.weaponId);
  }

  /** Swap an actor's weapon to a Gun Game tier. "knife" arms the throwing-knife
   * lethal for the player (and keeps their gun as-is, since the win is a throw). */
  private equipTier(actorId: number, weaponId: string): void {
    if (weaponId === "knife") {
      // Player-only final tier: re-arm the throwing knife lethal (full ammo).
      if (this.player && actorId === this.player.id) {
        this.opts.playerLethal = "knife";
      }
      return;
    }
    const def = getWeapon(weaponId);
    if (this.player && actorId === this.player.id) {
      this.player.setWeapon(def);
    } else {
      const bot = this.bots.find((b) => b.id === actorId);
      if (bot) bot.setWeapon(def);
    }
  }

  private addKillfeed(
    killerId: number | undefined,
    victim: Actor,
    weaponId: string | undefined,
    headshot: boolean,
  ): void {
    const killer = killerId !== undefined && killerId !== victim.id
      ? this.scoreboard.get(killerId)
      : undefined;
    const v = this.scoreboard.get(victim.id);
    this.killfeed.push({
      killer: killer?.name,
      killerTeam: killer?.team,
      weaponId,
      victim: v.name,
      victimTeam: v.team,
      headshot,
      time: this.elapsed,
    });
    if (this.killfeed.length > 8) this.killfeed.shift();
  }

  /** Drop the victim's weapon (with leftover ammo + attachments) to pick up. */
  private dropVictimWeapon(victim: Actor): void {
    const pos = victim.position(new THREE.Vector3());
    if (victim instanceof RemoteActor) {
      const def = getWeapon(victim.weaponId);
      this.addWeaponDrop(def, def.magazine, def.reserve, pos);
    } else if (victim instanceof Player) {
      const w = victim.weapon;
      if (w) this.addWeaponDrop(w.def, w.magazine, w.reserve, pos, victim.currentAttachments);
    } else {
      const w = (victim as Bot).weapon;
      if (w) this.addWeaponDrop(w.def, w.magazine, w.reserve, pos);
    }
  }

  /** Scavenger perk: enemies drop ammo the local player can collect. */
  private maybeScavenger(victim: Actor): void {
    if (
      this.playerHasScavenger && this.player &&
      victim.id !== this.player.id &&
      (this.player.team === "ffa" || victim.team !== this.player.team)
    ) {
      this.spawnAmmoPickup(victim);
    }
  }

  // ---- Replay (killcam + best play) ----

  /** Track the local player's killstreak; on their death capture the killcam. */
  private trackPlayerKD(killerId: number | undefined, victimId: number): void {
    const p = this.player;
    if (!p) return;
    if (killerId === p.id && killerId !== victimId) {
      if (this.playerStreak === 0) this.streakStartT = Math.max(0, this.elapsed - 1);
      this.playerStreak++;
    }
    if (victimId === p.id) {
      this.finalizeBestPlay();
      this.captureKillcam(victimId, killerId);
      this.playerStreak = 0;
    }
  }

  private finalizeBestPlay(): void {
    if (!this.player) return;
    if (this.playerStreak >= 2 && (!this.bestPlay || this.playerStreak > this.bestPlay.kills)) {
      const frames = this.recorder.window(this.streakStartT, this.elapsed);
      if (frames.length >= 2) {
        this.bestPlay = { frames, kills: this.playerStreak, playerId: this.player.id };
      }
    }
  }

  private captureKillcam(victimId: number, killerId: number | undefined): void {
    const frames = this.recorder.recent(this.elapsed, 4);
    if (frames.length < 2) return;
    let killerName = "the enemy";
    if (killerId !== undefined && killerId !== victimId) killerName = this.scoreName(killerId);
    this.killcam = { frames, killerId, victimId, killerName };
  }

  private snapshotActors(): ActorSnap[] {
    const out: ActorSnap[] = [];
    for (const a of this.actorList) out.push(this.snapOf(a));
    return out;
  }

  private snapOf(a: Actor): ActorSnap {
    const feet = (a as Player | Bot | RemoteActor).feet;
    let yaw = 0;
    let anim: AnimName = "idle";
    let weaponId = "m4";
    if (a instanceof Player) {
      if (this.camera) {
        const d = this.camera.getLookDirection(_snapDir);
        yaw = Math.atan2(d.x, d.z);
      }
      const moving = !!this.input &&
        (this.input.axis("back", "forward") !== 0 || this.input.axis("left", "right") !== 0);
      const firing = !!this.input && this.input.isDown("fire");
      anim = !a.alive ? "die" : firing ? "shoot" : moving ? "run" : "idle";
      weaponId = a.weapon.def.id;
    } else if (a instanceof RemoteActor) {
      yaw = a.yaw;
      anim = a.anim;
      weaponId = a.weaponId;
    } else {
      const b = a as Bot;
      yaw = b.yaw;
      anim = !b.alive ? "die" : b.firing ? "shoot" : b.moving ? "run" : "idle";
      weaponId = b.weapon.def.id;
    }
    return {
      id: a.id,
      team: a.team,
      name: this.scoreName(a.id),
      isPlayer: a === (this.player as unknown),
      x: feet.x,
      y: feet.y,
      z: feet.z,
      yaw,
      alive: a.alive,
      anim,
      weaponId,
    };
  }

  private scoreName(id: number): string {
    try {
      return this.scoreboard.get(id).name;
    } catch {
      return "?";
    }
  }

  /** Read + clear the pending killcam (Game consumes it once on death). */
  takeKillcam(): KillcamData | null {
    const k = this.killcam;
    this.killcam = null;
    return k;
  }

  /** Current objective state (Domination / CTF) for the HUD, or null. */
  objectiveHud(): ObjectiveHud | null {
    return this.objective?.hud() ?? null;
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
    attachments: ReadonlyArray<Attachment | string> = [],
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
      expire: this.elapsed + 120, // persist so a dropped weapon stays re-pickable
      use: (collectorId) => {
        if (this.player && collectorId === this.player.id) {
          // Drop the gun we're holding (with ITS attachments) so the swap is
          // reversible — picking the old one back up restores its optics.
          const held = this.player.weapon;
          const prevDef = held.def;
          const prevMag = held.magazine;
          const prevReserve = held.reserve;
          const prevAttachments = [...this.player.currentAttachments];
          this.player.equipDropped(def, magazine, reserve, attachments);
          this.addWeaponDrop(
            prevDef,
            prevMag,
            prevReserve,
            this.player.position(new THREE.Vector3()),
            prevAttachments,
          );
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

  // ---- Networking (relay) ----

  private rosterTeam(id: number): TeamId {
    return this.opts.roster?.find((p) => p.id === id)?.team ?? "blue";
  }

  private netTeamForIndex(i: number): TeamId {
    return this.modeId === "ffa" ? "ffa" : (i % 2 === 0 ? "blue" : "red");
  }

  /** Actors this client simulates + owns authoritatively. */
  private ownedActors(): Actor[] {
    if (!this.net) return this.actorList;
    const out: Actor[] = [];
    if (this.player) out.push(this.player);
    if (this.isHost) { for (const b of this.bots) out.push(b); }
    return out;
  }

  private ownedById(id: number): Actor | null {
    if (this.player && this.player.id === id) return this.player;
    if (this.isHost) {
      const b = this.bots.find((x) => x.id === id);
      if (b) return b;
    }
    return null;
  }

  private addRemote(id: number, team: TeamId, name: string, accent: number): RemoteActor {
    const ra = new RemoteActor(
      id,
      team,
      name,
      (target, info) => this.net?.sendHit(target, info.amount, info.headshot, info.weaponId),
      accent % 6,
    );
    this.remotes.set(id, ra);
    this.scene.add(ra.object3d);
    this.actorList.push(ra);
    this.scoreboard.register(id, name, team, false);
    this.prevAlive.set(id, true);
    return ra;
  }

  private removeRemote(id: number): void {
    const ra = this.remotes.get(id);
    if (!ra) return;
    this.scene.dynamicRoot.remove(ra.object3d);
    ra.dispose();
    this.remotes.delete(id);
    this.prevAlive.delete(id);
    const i = this.actorList.indexOf(ra);
    if (i >= 0) this.actorList.splice(i, 1);
  }

  private applyBotState(bs: BotStateMsg): void {
    let ra = this.remotes.get(bs.id);
    if (!ra) ra = this.addRemote(bs.id, bs.team, `Bot ${bs.id}`, this.remotes.size);
    ra.team = bs.team;
    ra.applyState({
      x: bs.x,
      y: bs.y,
      z: bs.z,
      yaw: bs.yaw,
      anim: bs.anim,
      alive: bs.alive,
      weaponId: bs.weaponId,
    });
  }

  private registerNetHandlers(): void {
    this.net!.on({
      onState: (from, s) => this.remotes.get(from)?.applyState(s),
      onBots: (_from, b) => {
        for (const bs of b) this.applyBotState(bs);
      },
      onHit: (from, target, dmg, headshot, weaponId) => {
        const owned = this.ownedById(target);
        if (owned && owned.alive) {
          owned.applyDamage({
            amount: dmg,
            headshot,
            sourceTeam: this.teamOf(from),
            sourceId: from,
            weaponId,
          });
        }
      },
      onDeath: (_from, victim, killer, weaponId, headshot) =>
        this.onRemoteDeath(victim, killer, weaponId, headshot),
      onPeerLeft: (id) => this.removeRemote(id),
    });
  }

  private netSync(dt: number): void {
    this.netSendTimer -= dt;
    if (this.netSendTimer > 0) return;
    this.netSendTimer = 0.05; // ~20 Hz
    if (this.player) this.net!.sendState(this.playerStateMsg());
    if (this.isHost && this.bots.length) {
      this.net!.sendBots(this.bots.map((b) => this.botStateMsg(b)));
    }
  }

  private playerStateMsg(): PlayerStateMsg {
    const p = this.player!;
    let yaw = 0;
    if (this.camera) {
      const d = this.camera.getLookDirection(new THREE.Vector3());
      yaw = Math.atan2(d.x, d.z);
    }
    const moving = !!this.input &&
      (this.input.axis("back", "forward") !== 0 || this.input.axis("left", "right") !== 0);
    const firing = !!this.input && this.input.isDown("fire");
    const anim = !p.alive ? "die" : firing ? "shoot" : moving ? "run" : "idle";
    return {
      x: p.feet.x,
      y: p.feet.y,
      z: p.feet.z,
      yaw,
      anim,
      alive: p.alive,
      weaponId: p.weapon.def.id,
    };
  }

  private botStateMsg(bot: Bot): BotStateMsg {
    const anim = !bot.alive ? "die" : bot.firing ? "shoot" : bot.moving ? "run" : "idle";
    return {
      id: bot.id,
      x: bot.feet.x,
      y: bot.feet.y,
      z: bot.feet.z,
      yaw: bot.yaw,
      anim,
      alive: bot.alive,
      team: bot.team,
      weaponId: bot.weapon.def.id,
    };
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

  private isStreakActive(id: string): boolean {
    return this.activeStreaks.some((e) => e.streak.id === id);
  }

  /** Activate a streak for an owner (player UI or bot AI). */
  activateStreak(owner: StreakOwner, streakId: string): void {
    // Only one attack helicopter may be in the air at a time (leaves it
    // available so the owner can call it in once the current one leaves).
    if (streakId === "attack_heli" && this.isStreakActive("attack_heli")) return;
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
    // Care-package payload pool: never another care package (would recurse into
    // endless heli drops) and never the match-ending nuke.
    const pool = STREAKS.filter((s) => s.id !== "care_package" && s.id !== "nuke");
    const pick = pool[Math.floor(Math.random() * pool.length)];
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
    for (const ra of this.remotes.values()) {
      this.scene.dynamicRoot.remove(ra.object3d);
      ra.dispose();
    }
    this.remotes.clear();
    if (this.objective) {
      this.scene.dynamicRoot.remove(this.objective.root);
      this.objective.dispose();
      this.objective = null;
    }
    this.net?.clearHandlers();
    this.recorder.clear();
    this.killcam = null;
    this.actorList = [];
    this.pool?.clear();
    this.vfx?.clear();
    this.screen.clear();
  }
}

const _snapDir = new THREE.Vector3();

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
