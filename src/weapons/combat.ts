// Shared combat contracts between weapons, the world, and visual effects.
//
// Keeping these interfaces in one dependency-light module lets weapons,
// projectiles and the gameplay/world layer interoperate without import cycles.

import type * as THREE from "../three.ts";
import type { TeamId } from "../core/types.ts";

export interface DamageInfo {
  amount: number;
  headshot: boolean;
  sourceTeam: TeamId;
  /** Splash/explosive damage ignores friendly-fire rules differently. */
  explosive?: boolean;
  /** Weapon id that dealt the damage (killfeed). */
  weaponId?: string;
  /** Actor id of the attacker, for kill attribution. */
  sourceId?: number;
}

/** Anything that can take damage (bots, the player, destructibles). */
export interface DamageTarget {
  readonly object3d: THREE.Object3D;
  readonly team: TeamId;
  readonly alive: boolean;
  /** World-space centre (for splash distance). */
  position(out: THREE.Vector3): THREE.Vector3;
  /** Whether a hit object3d counts as a headshot region. */
  isHead(obj: THREE.Object3D): boolean;
  applyDamage(info: DamageInfo): void;
}

export interface RaycastHit {
  point: THREE.Vector3;
  normal: THREE.Vector3;
  distance: number;
  object: THREE.Object3D;
  /** Set when the ray hit a damageable actor. */
  target?: DamageTarget;
}

/** World queries weapons/projectiles use for hit detection + splash. */
export interface WorldQuery {
  raycast(
    origin: THREE.Vector3,
    direction: THREE.Vector3,
    maxDistance: number,
    ignore?: THREE.Object3D,
  ): RaycastHit | null;
  /** Damageable targets whose centre is within `radius` of `center`. */
  radiusTargets(center: THREE.Vector3, radius: number): DamageTarget[];
  /** Spawn a launcher rocket into the world. */
  spawnRocket?(origin: THREE.Vector3, direction: THREE.Vector3, owner: ShooterTag): void;
}

/** Identifies who fired a shot, for friendly-fire + killfeed. */
export interface ShooterTag {
  team: TeamId;
  isPlayer: boolean;
  weaponId: string;
  /** Actor id of the shooter, for kill attribution. */
  id?: number;
}

/** Visual effects sink (implemented by render/VFX.ts). */
export interface VFXSink {
  bulletImpact(point: THREE.Vector3, normal: THREE.Vector3, onActor: boolean): void;
  tracer(from: THREE.Vector3, to: THREE.Vector3): void;
  muzzleFlash(position: THREE.Vector3, direction: THREE.Vector3): void;
  explosion(center: THREE.Vector3, radius: number): void;
}

/** Aim provided by the weapon holder each frame. */
export interface Aim {
  origin: THREE.Vector3;
  direction: THREE.Vector3;
  /** Apply a recoil kick (radians) to the holder's view/aim. */
  applyRecoil(pitch: number, yaw: number): void;
}
