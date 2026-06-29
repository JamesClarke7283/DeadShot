// Sentry Gun scorestreak.
//
// An automated turret placed by the owner. It acquires the nearest enemy in
// range, rotates its gun to face it, and fires bursts of hitscan damage with
// tracers/muzzle flashes until its lifetime expires.

import * as THREE from "../three.ts";
import { Streak, type StreakContext, streakDamage } from "./Streak.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { Actor } from "../characters/Bot.ts";

const LIFETIME = 40;
const RANGE = 35;
const FIRE_INTERVAL = 0.2;
const DAMAGE = 18;
const PLACE_OFFSET = 1.5;

export class SentryGun extends Streak {
  readonly id = "sentry";
  readonly name = "Sentry Gun";

  private elapsed = 0;
  private fireTimer = 0;
  private gun: THREE.Object3D | null = null;
  private readonly pos = new THREE.Vector3();
  private readonly muzzle = new THREE.Vector3();

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;
    if (!this.mesh) this.spawn(ctx);

    this.elapsed += dt;
    this.fireTimer -= dt;

    const target = this.nearestEnemy(ctx);
    if (target) {
      const tpos = target.position(new THREE.Vector3());
      // Aim the gun yaw at the target.
      if (this.gun) {
        const dx = tpos.x - this.pos.x;
        const dz = tpos.z - this.pos.z;
        this.gun.rotation.y = Math.atan2(dx, dz);
      }
      if (this.fireTimer <= 0) {
        this.fireTimer = FIRE_INTERVAL;
        streakDamage(target, DAMAGE, ctx);
        ctx.vfx.tracer(this.muzzle, tpos);
        const dir = tpos.clone().sub(this.muzzle).normalize();
        ctx.vfx.muzzleFlash(this.muzzle, dir);
      }
    }

    if (this.elapsed >= LIFETIME) this.active = false;
  }

  private nearestEnemy(ctx: StreakContext): Actor | null {
    let best: Actor | null = null;
    let bestDist = RANGE * RANGE;
    const tmp = new THREE.Vector3();
    for (const e of ctx.enemiesOf(ctx.owner.team)) {
      if (!e.alive) continue;
      e.position(tmp);
      const d = tmp.distanceToSquared(this.pos);
      if (d < bestDist) {
        bestDist = d;
        best = e;
      }
    }
    return best;
  }

  private spawn(ctx: StreakContext): void {
    const owner = ctx.allActors().find((a) => a.id === ctx.owner.id);
    if (owner) owner.position(this.pos);
    else {
      this.pos.set(
        (ctx.bounds.minX + ctx.bounds.maxX) / 2,
        0,
        (ctx.bounds.minZ + ctx.bounds.maxZ) / 2,
      );
    }
    this.pos.x += PLACE_OFFSET;
    this.pos.y = ctx.groundAt(this.pos.x, this.pos.z);

    const root = new THREE.Group();
    root.position.copy(this.pos);

    const base = new THREE.Mesh(
      new THREE.CylinderGeometry(0.4, 0.5, 0.4, 8),
      createToonMaterial({ color: 0x3a3a3a }),
    );
    base.position.y = 0.2;
    addOutline(base);
    root.add(base);

    const gun = new THREE.Group();
    gun.position.y = 0.55;
    const body = new THREE.Mesh(
      new THREE.BoxGeometry(0.35, 0.3, 0.5),
      createToonMaterial({ color: 0x555555 }),
    );
    addOutline(body);
    gun.add(body);
    const barrel = new THREE.Mesh(
      new THREE.CylinderGeometry(0.05, 0.05, 0.7, 6),
      createToonMaterial({ color: 0x222222 }),
    );
    barrel.rotation.x = Math.PI / 2;
    barrel.position.set(0, 0, 0.45);
    gun.add(barrel);
    root.add(gun);
    this.gun = gun;

    // Muzzle world position (recomputed from placement; gun yaw aim is cosmetic).
    this.muzzle.copy(this.pos).setY(this.pos.y + 0.55);

    this.mesh = root;
    ctx.root.add(root);
  }
}
