// Predator Missile scorestreak.
//
// Spawns high above the densest enemy cluster and dives straight down. It
// detonates on impact with the ground (or after a max flight time) with a large
// explosive splash.

import * as THREE from "../three.ts";
import { Streak, type StreakContext, streakDamage } from "./Streak.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { Actor } from "../characters/Bot.ts";

const SPAWN_HEIGHT = 80;
const SPEED = 45;
const MAX_FLIGHT = 5;
const BLAST_RADIUS = 8;
const BLAST_DAMAGE = 200;

export class PredatorMissile extends Streak {
  readonly id = "predator";
  readonly name = "Predator Missile";

  private elapsed = 0;
  private readonly pos = new THREE.Vector3();
  private groundY = 0;

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;
    if (!this.mesh) this.spawn(ctx);

    this.elapsed += dt;
    this.pos.y -= SPEED * dt;
    if (this.mesh) this.mesh.position.copy(this.pos);

    if (this.pos.y <= this.groundY || this.elapsed >= MAX_FLIGHT) {
      this.pos.y = this.groundY;
      this.detonate(ctx);
    }
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

  /** Centroid of the enemy cluster, or the map center if no enemies exist. */
  private targetPoint(ctx: StreakContext): THREE.Vector3 {
    const enemies = ctx.enemiesOf(ctx.owner.team).filter((e) => e.alive);
    const out = new THREE.Vector3();
    if (enemies.length === 0) {
      return out.set(
        (ctx.bounds.minX + ctx.bounds.maxX) / 2,
        0,
        (ctx.bounds.minZ + ctx.bounds.maxZ) / 2,
      );
    }
    const tmp = new THREE.Vector3();
    for (const e of enemies) out.add(e.position(tmp));
    out.divideScalar(enemies.length);
    return out;
  }

  private spawn(ctx: StreakContext): void {
    const aim = this.targetPoint(ctx);
    this.groundY = ctx.groundAt(aim.x, aim.z);
    this.pos.set(aim.x, this.groundY + SPAWN_HEIGHT, aim.z);

    const missile = new THREE.Group();
    const body = new THREE.Mesh(
      new THREE.CylinderGeometry(0.18, 0.18, 1.6, 8),
      createToonMaterial({ color: 0xdddddd }),
    );
    addOutline(body);
    missile.add(body);
    const nose = new THREE.Mesh(
      new THREE.ConeGeometry(0.18, 0.5, 8),
      createToonMaterial({ color: 0x990000 }),
    );
    nose.position.y = -1.05;
    nose.rotation.x = Math.PI;
    missile.add(nose);
    // Point nose-down.
    missile.position.copy(this.pos);
    this.mesh = missile;
    ctx.root.add(missile);
  }
}
