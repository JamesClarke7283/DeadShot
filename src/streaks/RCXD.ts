// RC-XD scorestreak.
//
// A remote-control car packed with explosives. It drives along the ground toward
// the nearest enemy and detonates on contact (or on a fuse timeout), dealing
// heavy splash damage with falloff.

import * as THREE from "../three.ts";
import { Streak, type StreakContext, streakDamage } from "./Streak.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { Actor } from "../characters/Bot.ts";
import type { DamageTarget } from "../weapons/combat.ts";

const SPEED = 9;
const FUSE = 12;
const TRIGGER_RANGE = 3;
const BLAST_RADIUS = 6;
const BLAST_DAMAGE = 150;

export class RCXD extends Streak {
  readonly id = "rcxd";
  readonly name = "RC-XD";

  private elapsed = 0;
  private readonly pos = new THREE.Vector3();

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;
    if (!this.mesh) this.spawn(ctx);

    this.elapsed += dt;

    const target = this.nearestEnemy(ctx);
    if (target) {
      const tpos = target.position(new THREE.Vector3());
      const dx = tpos.x - this.pos.x;
      const dz = tpos.z - this.pos.z;
      const flat = Math.hypot(dx, dz);
      if (flat <= TRIGGER_RANGE) {
        this.detonate(ctx);
        return;
      }
      const inv = 1 / Math.max(flat, 1e-4);
      this.pos.x += dx * inv * SPEED * dt;
      this.pos.z += dz * inv * SPEED * dt;
      this.pos.y = ctx.groundAt(this.pos.x, this.pos.z) + 0.2;
      if (this.mesh) {
        this.mesh.position.copy(this.pos);
        this.mesh.rotation.y = Math.atan2(dx, dz);
      }
    }

    if (this.elapsed >= FUSE) this.detonate(ctx);
  }

  private detonate(ctx: StreakContext): void {
    ctx.vfx.explosion(this.pos, BLAST_RADIUS);
    const targets = ctx.world.radiusTargets(this.pos, BLAST_RADIUS);
    const c = new THREE.Vector3();
    for (const t of targets) {
      t.position(c);
      const d = c.distanceTo(this.pos);
      const falloff = Math.max(0, 1 - d / BLAST_RADIUS);
      streakDamage(t as unknown as Actor, BLAST_DAMAGE * falloff, ctx, true);
    }
    this.active = false;
  }

  private nearestEnemy(ctx: StreakContext): DamageTarget | null {
    let best: DamageTarget | null = null;
    let bestDist = Infinity;
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
    this.pos.y = ctx.groundAt(this.pos.x, this.pos.z) + 0.2;

    const car = new THREE.Group();
    const body = new THREE.Mesh(
      new THREE.BoxGeometry(0.5, 0.25, 0.8),
      createToonMaterial({ color: 0xcc3333 }),
    );
    addOutline(body);
    car.add(body);
    const mat = createToonMaterial({ color: 0x111111 });
    for (const x of [-0.28, 0.28]) {
      for (const z of [-0.28, 0.28]) {
        const wheel = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.13, 0.1, 8), mat);
        wheel.rotation.z = Math.PI / 2;
        wheel.position.set(x, -0.12, z);
        car.add(wheel);
      }
    }
    car.position.copy(this.pos);
    this.mesh = car;
    ctx.root.add(car);
  }
}
