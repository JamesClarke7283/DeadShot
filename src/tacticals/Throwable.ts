// Thrown-equipment base: an arcing projectile with gravity, segment-raycast
// collision (so fast throws don't tunnel), bouncing, a cook/fuse timer and an
// optional detonate-on-impact mode. Mirrors the weapons/Projectile collision
// approach. Subclasses implement onDetonate() and may use the explode() helper
// for radial explosive damage with distance falloff + friendly-fire skipping.

import * as THREE from "../three.ts";
import { Equipment, type EquipmentContext } from "./Equipment.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { DamageTarget } from "../weapons/combat.ts";
import { teamColor, type TeamId } from "../core/types.ts";

export interface ThrowableConfig {
  /** Time until detonation once thrown (seconds). 0 / undefined => never. */
  fuseSec?: number;
  gravity?: number;
  throwSpeed?: number;
  /** Velocity retained after a bounce (0..1). */
  bounce?: number;
  /** Detonate on the first solid/world impact instead of waiting for the fuse. */
  detonateOnImpact?: boolean;
  /** Explosion/effect radius (subclass-defined meaning). */
  radius?: number;
}

const DEFAULTS: Required<ThrowableConfig> = {
  fuseSec: 0,
  gravity: 20,
  throwSpeed: 22,
  bounce: 0.4,
  detonateOnImpact: false,
  radius: 5,
};

export abstract class Throwable extends Equipment {
  protected readonly cfg: Required<ThrowableConfig>;
  protected readonly position = new THREE.Vector3();
  protected readonly velocity = new THREE.Vector3();
  protected team: TeamId = "ffa";
  protected sourceId: number | undefined;
  protected fuse = 0;
  protected detonated = false;
  protected stuck = false;

  private readonly prev = new THREE.Vector3();
  private readonly step = new THREE.Vector3();

  constructor(cfg: ThrowableConfig = {}) {
    super();
    this.cfg = { ...DEFAULTS, ...cfg };
    this.fuse = this.cfg.fuseSec;
  }

  /** Launch from origin along direction at throwSpeed. Builds the mesh. */
  throw(
    origin: THREE.Vector3,
    direction: THREE.Vector3,
    team: TeamId,
    ctx: EquipmentContext,
    sourceId?: number,
  ): void {
    this.team = team;
    this.sourceId = sourceId;
    this.position.copy(origin);
    this.prev.copy(origin);
    this.velocity.copy(direction).normalize().multiplyScalar(this.cfg.throwSpeed);
    this.mesh = this.buildMesh(team);
    this.mesh.position.copy(this.position);
    ctx.root.add(this.mesh);
  }

  /** A small team-tinted sphere by default; override for distinctive shapes. */
  protected buildMesh(team: TeamId): THREE.Object3D {
    const mesh = new THREE.Mesh(
      new THREE.SphereGeometry(0.14, 12, 12),
      createToonMaterial({ color: teamColor(team) }),
    );
    addOutline(mesh, { thickness: 0.02 });
    return mesh;
  }

  override update(dt: number, ctx: EquipmentContext): void {
    if (!this.active) return;

    // A stuck throwable (semtex/c4/thermite) freezes in place but still cooks.
    if (this.stuck) {
      this.tickFuse(dt, ctx);
      return;
    }

    this.velocity.y -= this.cfg.gravity * dt;
    this.prev.copy(this.position);
    this.step.copy(this.velocity).multiplyScalar(dt);
    const stepLen = this.step.length();
    this.position.add(this.step);

    if (stepLen > 1e-5) {
      const dir = this.step.clone().multiplyScalar(1 / stepLen);
      const hit = ctx.world.raycast(this.prev, dir, stepLen, null);
      if (hit) {
        this.position.copy(hit.point);
        if (this.mesh) this.mesh.position.copy(this.position);
        this.onWorldHit(hit.point, hit.normal, hit.target, ctx);
        if (!this.active) return;
      }
    }

    if (this.mesh) this.mesh.position.copy(this.position);
    this.tickFuse(dt, ctx);
  }

  private tickFuse(dt: number, ctx: EquipmentContext): void {
    if (this.cfg.fuseSec > 0) {
      this.fuse -= dt;
      if (this.fuse <= 0) this.fuseDetonate(this.position, ctx);
    }
  }

  /**
   * Default impact behaviour: detonate-on-impact types blow up here; others
   * bounce off the surface (reflect velocity, damped) and keep cooking.
   * Subclasses (semtex/thermite/knife/molotov) override to stick/stab/splat.
   */
  protected onWorldHit(
    point: THREE.Vector3,
    normal: THREE.Vector3,
    _target: DamageTarget | undefined,
    ctx: EquipmentContext,
  ): void {
    if (this.cfg.detonateOnImpact) {
      this.fuseDetonate(point, ctx);
      return;
    }
    this.bounce(normal);
  }

  /** Reflect velocity around the surface normal with bounce damping. */
  protected bounce(normal: THREE.Vector3): void {
    const n = normal.clone().normalize();
    const vn = this.velocity.dot(n);
    // v' = (v - 2(v·n)n) * bounce
    this.velocity.addScaledVector(n, -2 * vn).multiplyScalar(this.cfg.bounce);
    // Nudge off the surface so the next raycast doesn't re-hit immediately.
    this.position.addScaledVector(n, 0.05);
  }

  /**
   * Fire onDetonate exactly once. Deactivates first so a persisting item (smoke
   * cloud, molotov/thermite fire pool) can re-arm itself by setting active=true
   * inside onDetonate; one-shot items simply stay inactive and get disposed.
   */
  protected fuseDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    if (this.detonated) return;
    this.detonated = true;
    this.active = false;
    this.onDetonate(point, ctx);
  }

  protected abstract onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void;

  /**
   * Radial explosive damage: VFX + damage all radiusTargets with distance
   * falloff, skipping same-team targets unless the thrower team is "ffa".
   */
  protected explode(
    center: THREE.Vector3,
    radius: number,
    damage: number,
    ctx: EquipmentContext,
    weaponId?: string,
  ): void {
    ctx.vfx.explosion(center, radius);
    this.damageRadius(center, radius, damage, ctx, weaponId);
  }

  /** Apply falloff radial damage without the explosion VFX (for DoT ticks). */
  protected damageRadius(
    center: THREE.Vector3,
    radius: number,
    damage: number,
    ctx: EquipmentContext,
    weaponId?: string,
  ): void {
    this.applyRadial(center, radius, damage, ctx, weaponId, true);
  }

  /** Flat (no falloff) radial damage, for area-denial DoT (fire/thermite). */
  protected damageRadiusFlat(
    center: THREE.Vector3,
    radius: number,
    damage: number,
    ctx: EquipmentContext,
    weaponId?: string,
  ): void {
    this.applyRadial(center, radius, damage, ctx, weaponId, false);
  }

  private applyRadial(
    center: THREE.Vector3,
    radius: number,
    damage: number,
    ctx: EquipmentContext,
    weaponId: string | undefined,
    falloff: boolean,
  ): void {
    const pos = new THREE.Vector3();
    for (const t of ctx.world.radiusTargets(center, radius)) {
      if (!t.alive) continue;
      if (this.team !== "ffa" && t.team === this.team) continue; // friendly fire off
      const dist = t.position(pos).distanceTo(center);
      const amount = falloff ? damage * Math.max(0, 1 - dist / radius) : damage;
      if (amount <= 0) continue;
      t.applyDamage({
        amount,
        headshot: false,
        sourceTeam: this.team,
        explosive: true,
        weaponId,
        sourceId: this.sourceId,
      });
    }
  }
}
