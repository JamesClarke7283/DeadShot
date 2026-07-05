// Bot actor: a damageable combatant driven by BotAI.
//
// Holds health, a loadout (Weapon), a Character for visuals/animation, and a
// navigation path. Implements DamageTarget (so weapons/explosives hit it) and
// Actor (so the AI and Match can reason about it). Bot.update delegates decision
// making + actuation to its BotAI brain, then advances animation.

import * as THREE from "../three.ts";
import type { Character } from "./Character.ts";
import { BotAI, type Difficulty } from "./BotAI.ts";
import type { Navigator } from "./BotNavigator.ts";
import { Weapon } from "../weapons/Weapon.ts";
import type { WeaponDef } from "../weapons/WeaponDefinition.ts";
import type { Attachment } from "../weapons/AttachmentDefinitions.ts";
import type { DamageInfo, DamageTarget, VFXSink, WorldQuery } from "../weapons/combat.ts";
import type { CollisionWorld } from "../maps/Collision.ts";
import type { TeamId } from "../core/types.ts";

export const BOT_EYE_HEIGHT = 1.6;
const BOT_RADIUS = 0.4;
const BOT_HEIGHT = 1.8;

/** A combatant the AI/Match reasons about (bots and the player). */
export interface Actor extends DamageTarget {
  readonly id: number;
  readonly isPlayer: boolean;
  eyePosition(out: THREE.Vector3): THREE.Vector3;
}

/** An objective-mode destination for a bot (Domination point, CTF flag, …). */
export interface BotGoal {
  x: number;
  z: number;
  /** "On station" within this range — loiter inside it instead of stacking. */
  radius: number;
  /**
   * attack: take a point / grab the enemy flag (escorts a friendly carrier too)
   * defend: hold a held point or the home flag
   * return: touch our dropped flag to send it home
   * chase:  hunt the enemy carrying our flag
   * carry:  we hold the enemy flag — sprint it home, even under fire
   */
  kind: "attack" | "defend" | "return" | "chase" | "carry";
}

/** Everything a Bot needs each frame. */
export interface BotContext {
  world: WorldQuery;
  collision: CollisionWorld;
  navigator: Navigator;
  vfx: VFXSink;
  actors: Actor[];
  groundAt(x: number, z: number): number;
  /** Called when a bot kills an actor (killer, victim). */
  onKill?(killer: Actor | undefined, victim: Actor, headshot: boolean, weaponId?: string): void;
  /** Wander bounds for patrol. */
  bounds: { minX: number; maxX: number; minZ: number; maxZ: number };
  /** Objective-mode goal for this bot (Domination / CTF), if any. */
  objectiveGoal?(bot: Actor): BotGoal | null;
}

export interface BotConfig {
  id: number;
  team: TeamId;
  difficulty: Difficulty;
  character: Character;
  weaponDef: WeaponDef;
  attachments?: ReadonlyArray<Attachment | string>;
  spawn: THREE.Vector3;
  yaw?: number;
  /** Fired when this bot shoots (for positional SFX). */
  onShot?: (weaponId: string, position: THREE.Vector3) => void;
}

export class Bot implements Actor {
  readonly id: number;
  team: TeamId;
  readonly isPlayer = false;
  readonly difficulty: Difficulty;
  readonly character: Character;
  readonly weapon: Weapon;
  readonly object3d: THREE.Object3D;

  alive = true;
  health = 100;
  maxHealth = 100;
  kills = 0;
  deaths = 0;

  readonly feet = new THREE.Vector3();
  readonly aimDir = new THREE.Vector3(0, 0, -1);
  yaw = 0;
  moving = false;
  firing = false;

  /** Current navigation path (world points) + cursor. */
  path: THREE.Vector3[] = [];
  pathIndex = 0;

  private brain: BotAI;
  private deathTimer = 0;

  constructor(cfg: BotConfig) {
    this.id = cfg.id;
    this.team = cfg.team;
    this.difficulty = cfg.difficulty;
    this.character = cfg.character;
    this.object3d = cfg.character.root;
    this.feet.copy(cfg.spawn);
    this.yaw = cfg.yaw ?? 0;
    const onShot = cfg.onShot;
    this.weapon = new Weapon(cfg.weaponDef, cfg.attachments ?? [], {
      team: cfg.team,
      isPlayer: false,
      weaponId: cfg.weaponDef.id,
      id: cfg.id,
    }, onShot ? { onShot: (w) => onShot(w.def.id, this.eyePosition(new THREE.Vector3())) } : {});
    this.brain = new BotAI(cfg.difficulty);
    this.syncTransform();
  }

  // ---- Actor / DamageTarget ----
  position(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.feet).setY(this.feet.y + 1.0);
  }
  eyePosition(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.feet).setY(this.feet.y + BOT_EYE_HEIGHT);
  }
  isHead(obj: THREE.Object3D): boolean {
    return obj.getWorldPosition(new THREE.Vector3()).y > this.feet.y + 1.55;
  }
  applyDamage(info: DamageInfo): void {
    if (!this.alive) return;
    this.health -= info.amount;
    if (this.health <= 0) {
      this.health = 0;
      this.die(info);
    }
  }

  private die(info: DamageInfo): void {
    this.alive = false;
    this.deaths++;
    this.firing = false;
    this.weapon.setTrigger(false);
    this.character.play("die");
    this.lastDamage = info;
  }

  lastDamage?: DamageInfo;

  respawn(pos: THREE.Vector3, yaw = 0): void {
    this.alive = true;
    this.health = this.maxHealth;
    this.feet.copy(pos);
    this.yaw = yaw;
    this.path = [];
    this.pathIndex = 0;
    this.deathTimer = 0;
    this.character.play("idle");
    this.object3d.rotation.set(0, yaw, 0);
    this.syncTransform();
  }

  /** Seconds since death (for respawn timing by the Match). */
  get timeDead(): number {
    return this.deathTimer;
  }

  syncTransform(): void {
    this.object3d.position.set(this.feet.x, this.feet.y, this.feet.z);
    if (this.alive) this.object3d.rotation.y = this.yaw;
  }

  // ---- Simulation ----
  update(dt: number, ctx: BotContext): void {
    if (!this.alive) {
      this.deathTimer += dt;
      this.character.update(dt);
      return;
    }
    this.brain.update(this, dt, ctx);
    // Animation selection.
    if (this.firing) this.character.play("shoot");
    else if (this.moving) this.character.play("run");
    else this.character.play("idle");
    this.character.update(dt);
    this.syncTransform();
  }

  /** Move the feet toward a world point with collision; returns true if moving. */
  stepToward(target: THREE.Vector3, speed: number, dt: number, ctx: BotContext): boolean {
    const dx = target.x - this.feet.x;
    const dz = target.z - this.feet.z;
    const dist = Math.hypot(dx, dz);
    if (dist < 0.15) return false;
    const inv = 1 / dist;
    this.feet.x += dx * inv * speed * dt;
    this.feet.z += dz * inv * speed * dt;
    this.feet.y = ctx.groundAt(this.feet.x, this.feet.z);
    ctx.collision.resolve(this.feet, BOT_RADIUS, BOT_HEIGHT);
    return true;
  }

  moveSpeed(): number {
    return 5 * (this.weapon.stats.mobility / 85);
  }
}
