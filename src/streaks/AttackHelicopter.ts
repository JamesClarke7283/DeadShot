// Attack Helicopter scorestreak.
//
// An AI gunship that circles the map center at altitude and strafes the nearest
// enemy on a fire cadence. The shared circling/firing behavior lives in
// CirclingGunship; the concrete streaks just tune the numbers and mesh tint.

import * as THREE from "../three.ts";
import { Streak, type StreakContext, streakDamage } from "./Streak.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { Actor } from "../characters/Bot.ts";

export interface GunshipConfig {
  lifetime: number;
  altitude: number;
  radius: number;
  angularSpeed: number;
  fireInterval: number;
  damage: number;
  /** How many distinct enemies to hit per fire cycle. */
  targetsPerCycle: number;
  tint: number;
}

/** Base class for AI helicopter/gunship streaks. */
export abstract class CirclingGunship extends Streak {
  protected elapsed = 0;
  private fireTimer = 0;
  private angle = 0;
  private rotor: THREE.Object3D | null = null;
  private readonly pos = new THREE.Vector3();
  private readonly center = new THREE.Vector3();

  protected abstract config(): GunshipConfig;

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;
    const cfg = this.config();
    if (!this.mesh) this.spawn(ctx, cfg);

    this.elapsed += dt;
    this.angle += cfg.angularSpeed * dt;
    this.fireTimer -= dt;

    this.pos.set(
      this.center.x + Math.cos(this.angle) * cfg.radius,
      cfg.altitude,
      this.center.z + Math.sin(this.angle) * cfg.radius,
    );
    if (this.mesh) {
      this.mesh.position.copy(this.pos);
      // Face along the tangent of the circle.
      this.mesh.rotation.y = -this.angle + Math.PI / 2;
    }
    if (this.rotor) this.rotor.rotation.y += dt * 30;

    if (this.fireTimer <= 0) {
      this.fireTimer = cfg.fireInterval;
      this.fire(ctx, cfg);
    }

    if (this.elapsed >= cfg.lifetime) this.active = false;
  }

  private fire(ctx: StreakContext, cfg: GunshipConfig): void {
    const enemies = ctx.enemiesOf(ctx.owner.team).filter((e) => e.alive);
    if (enemies.length === 0) return;
    const tmp = new THREE.Vector3();
    enemies.sort((a, b) =>
      a.position(tmp).distanceToSquared(this.pos) -
      b.position(new THREE.Vector3()).distanceToSquared(this.pos)
    );
    const n = Math.min(cfg.targetsPerCycle, enemies.length);
    for (let i = 0; i < n; i++) {
      const target: Actor = enemies[i];
      const tpos = target.position(new THREE.Vector3());
      streakDamage(target, cfg.damage, ctx);
      ctx.vfx.tracer(this.pos, tpos);
    }
  }

  private spawn(ctx: StreakContext, cfg: GunshipConfig): void {
    this.center.set(
      (ctx.bounds.minX + ctx.bounds.maxX) / 2,
      cfg.altitude,
      (ctx.bounds.minZ + ctx.bounds.maxZ) / 2,
    );

    const heli = new THREE.Group();
    const body = new THREE.Mesh(
      new THREE.BoxGeometry(2.2, 1.2, 1.2),
      createToonMaterial({ color: cfg.tint }),
    );
    addOutline(body);
    heli.add(body);

    const tail = new THREE.Mesh(
      new THREE.BoxGeometry(2.4, 0.25, 0.25),
      createToonMaterial({ color: cfg.tint }),
    );
    tail.position.set(-2.0, 0.2, 0);
    heli.add(tail);

    const rotor = new THREE.Group();
    rotor.position.y = 0.8;
    for (let i = 0; i < 2; i++) {
      const blade = new THREE.Mesh(
        new THREE.BoxGeometry(5, 0.08, 0.3),
        createToonMaterial({ color: 0x222222 }),
      );
      blade.rotation.y = (i * Math.PI) / 2;
      rotor.add(blade);
    }
    heli.add(rotor);
    this.rotor = rotor;

    this.pos.set(this.center.x + cfg.radius, cfg.altitude, this.center.z);
    heli.position.copy(this.pos);
    this.mesh = heli;
    ctx.root.add(heli);
  }
}

export class AttackHelicopter extends CirclingGunship {
  readonly id = "attack_heli";
  readonly name = "Attack Helicopter";

  protected config(): GunshipConfig {
    return {
      lifetime: 30,
      altitude: 25,
      radius: 18,
      angularSpeed: 0.5,
      fireInterval: 0.4,
      damage: 25,
      targetsPerCycle: 1,
      tint: 0x3a4a2a,
    };
  }
}
