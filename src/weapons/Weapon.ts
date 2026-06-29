// Runtime weapon instance.
//
// Owns ammo, the fire-control state machine (ready / firing / reloading /
// swapping / empty), trigger semantics per fire mode (auto / semi / burst /
// bolt / pump), hitscan resolution (with shotgun pellets + range falloff +
// headshots), launcher rocket spawning, recoil and FX. The holder feeds it aim +
// trigger each frame; hooks notify the viewmodel/SFX of shots and reloads.

import * as THREE from "../three.ts";
import {
  damageAtRange,
  type FireMode,
  reloadDuration,
  shotInterval,
  type WeaponDef,
} from "./WeaponDefinition.ts";
import {
  type Attachment,
  type ComputedStats,
  computeWeaponStats,
} from "./AttachmentDefinitions.ts";
import { Recoil } from "./Recoil.ts";
import type { Aim, ShooterTag, VFXSink, WorldQuery } from "./combat.ts";

export type WeaponState = "ready" | "firing" | "reloading" | "swapping" | "empty";

export interface WeaponHooks {
  onShot?(weapon: Weapon): void;
  onReloadStart?(empty: boolean, duration: number): void;
  onReloadEnd?(): void;
  onEmptyClick?(): void;
  onSwapIn?(): void;
}

const HITSCAN_RANGE = 500;
// Base hipfire spread half-angle (radians) per category feel.
const HIP_SPREAD = 0.012;
const SHOTGUN_SPREAD = 0.06;

export class Weapon {
  readonly def: WeaponDef;
  stats: ComputedStats;
  state: WeaponState = "ready";
  magazine: number;
  reserve: number;
  readonly shooter: ShooterTag;

  private recoil = new Recoil();
  private cooldown = 0;
  private reloadTimer = 0;
  private swapTimer = 0;
  private triggerHeld = false;
  private lastTrigger = false;
  private burstRemaining = 0;
  private hooks: WeaponHooks;
  /** Hipfire-to-ADS factor [0..1]; 1 = full ADS (tighter spread). Set by holder. */
  adsFactor = 0;

  constructor(
    def: WeaponDef,
    attachments: ReadonlyArray<Attachment | string>,
    shooter: ShooterTag,
    hooks: WeaponHooks = {},
  ) {
    this.def = def;
    this.stats = computeWeaponStats(def, attachments);
    this.magazine = this.stats.magazine;
    this.reserve = this.stats.reserve;
    this.shooter = shooter;
    this.hooks = hooks;
  }

  recompute(attachments: ReadonlyArray<Attachment | string>): void {
    const ratio = this.magazine / this.stats.magazine;
    this.stats = computeWeaponStats(this.def, attachments);
    this.magazine = Math.round(this.stats.magazine * ratio);
  }

  get fireMode(): FireMode {
    return this.def.fireMode;
  }

  setTrigger(held: boolean): void {
    this.triggerHeld = held;
  }

  ammoString(): string {
    return `${this.magazine} / ${this.reserve}`;
  }

  swapIn(): void {
    this.state = "swapping";
    this.swapTimer = 0.4;
    this.hooks.onSwapIn?.();
  }

  reload(): void {
    if (this.state === "reloading" || this.state === "swapping") return;
    if (this.magazine >= this.stats.magazine || this.reserve <= 0) return;
    const empty = this.magazine === 0;
    this.state = "reloading";
    this.reloadTimer = reloadDuration({ ...this.def, reloadTime: this.stats.reloadTime }, empty);
    this.hooks.onReloadStart?.(empty, this.reloadTimer);
  }

  private finishReload(): void {
    const need = this.stats.magazine - this.magazine;
    const take = Math.min(need, this.reserve);
    this.magazine += take;
    this.reserve -= take;
    this.state = this.magazine > 0 ? "ready" : "empty";
    this.hooks.onReloadEnd?.();
  }

  update(dt: number, aim: Aim, world: WorldQuery, fx: VFXSink): void {
    this.recoil.update(dt, this.stats.recoil, aim.applyRecoil);
    if (this.cooldown > 0) this.cooldown -= dt;

    if (this.state === "reloading") {
      this.reloadTimer -= dt;
      if (this.reloadTimer <= 0) this.finishReload();
      this.lastTrigger = this.triggerHeld;
      return;
    }
    if (this.state === "swapping") {
      this.swapTimer -= dt;
      if (this.swapTimer <= 0) this.state = this.magazine > 0 ? "ready" : "empty";
      this.lastTrigger = this.triggerHeld;
      return;
    }

    const rising = this.triggerHeld && !this.lastTrigger;

    if (this.burstRemaining > 0) {
      if (this.cooldown <= 0 && this.magazine > 0) {
        this.fireOnce(aim, world, fx);
        this.burstRemaining--;
        this.cooldown = shotInterval(this.stats.fireRate);
      }
    } else {
      const wantFire = this.fireMode === "auto" ? this.triggerHeld : rising;
      if (wantFire && this.cooldown <= 0) {
        if (this.magazine <= 0) {
          this.hooks.onEmptyClick?.();
          if (this.reserve > 0) this.reload();
          this.cooldown = 0.3;
        } else if (this.fireMode === "burst") {
          this.burstRemaining = (this.def.burstCount ?? 3) - 1;
          this.fireOnce(aim, world, fx);
          this.cooldown = shotInterval(this.stats.fireRate);
        } else {
          this.fireOnce(aim, world, fx);
          this.cooldown = shotInterval(this.stats.fireRate);
        }
      }
    }

    if (!this.triggerHeld && this.burstRemaining === 0) this.recoil.resetBurst();
    this.lastTrigger = this.triggerHeld;
  }

  private fireOnce(aim: Aim, world: WorldQuery, fx: VFXSink): void {
    this.magazine--;
    this.hooks.onShot?.(this);
    this.recoil.kick(this.stats.recoil, aim.applyRecoil);

    const muzzle = aim.origin.clone().addScaledVector(aim.direction, 0.4);
    fx.muzzleFlash(muzzle, aim.direction);

    if (this.def.rocket && world.spawnRocket) {
      world.spawnRocket(muzzle, aim.direction.clone(), this.shooter);
    } else {
      const pellets = this.stats.pellets ?? 1;
      for (let i = 0; i < pellets; i++) this.fireHitscan(aim, world, fx, muzzle);
    }

    if (this.magazine <= 0) this.state = "empty";
  }

  private fireHitscan(aim: Aim, world: WorldQuery, fx: VFXSink, muzzle: THREE.Vector3): void {
    const baseSpread = this.def.category === "shotgun" ? SHOTGUN_SPREAD : HIP_SPREAD;
    const adsScale = 1 - this.adsFactor * 0.85; // ADS tightens spread
    const spread = baseSpread * this.stats.spreadMult * adsScale;
    const dir = perturb(aim.direction, spread);

    const hit = world.raycast(aim.origin, dir, HITSCAN_RANGE);
    if (hit) {
      fx.tracer(muzzle, hit.point);
      fx.bulletImpact(hit.point, hit.normal, !!hit.target);
      const target = hit.target;
      if (
        target && target.alive && (this.shooter.team === "ffa" || target.team !== this.shooter.team)
      ) {
        const headshot = target.isHead(hit.object);
        let dmg = damageAtRange(this.stats.range, this.stats.damage, hit.distance);
        if (headshot) dmg *= this.stats.headshotMultiplier;
        target.applyDamage({
          amount: dmg,
          headshot,
          sourceTeam: this.shooter.team,
          weaponId: this.def.id,
          sourceId: this.shooter.id,
        });
      }
    } else {
      fx.tracer(muzzle, aim.origin.clone().addScaledVector(dir, HITSCAN_RANGE));
    }
  }
}

const _u = new THREE.Vector3();
const _v = new THREE.Vector3();
const UP = new THREE.Vector3(0, 1, 0);

/** Perturb a direction within a cone of half-angle `spread` (radians). */
function perturb(dir: THREE.Vector3, spread: number): THREE.Vector3 {
  if (spread <= 0) return dir.clone();
  // Build an orthonormal basis around dir.
  _u.copy(dir).cross(UP);
  if (_u.lengthSq() < 1e-6) _u.set(1, 0, 0);
  _u.normalize();
  _v.copy(dir).cross(_u).normalize();
  const a = Math.random() * Math.PI * 2;
  const r = Math.tan(spread) * Math.sqrt(Math.random());
  return dir.clone().addScaledVector(_u, Math.cos(a) * r).addScaledVector(_v, Math.sin(a) * r)
    .normalize();
}
