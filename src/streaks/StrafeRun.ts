// Strafe Run scorestreak.
//
// Three jets fly in formation across the map along one axis. As they sweep, any
// enemy within a corridor of the flight line takes a single heavy hit. The
// streak ends when the jets clear the map bounds.

import * as THREE from "../three.ts";
import { Streak, type StreakContext, streakDamage } from "./Streak.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { Actor } from "../characters/Bot.ts";

const ALTITUDE = 35;
const SPEED = 50;
const CORRIDOR = 8;
const DAMAGE = 80;
const JET_SPACING = 6;
const MARGIN = 20;

export class StrafeRun extends Streak {
  readonly id = "strafe_run";
  readonly name = "Strafe Run";

  private jets: THREE.Object3D[] = [];
  private x = 0;
  private endX = 0;
  private centerZ = 0;
  private readonly hit = new Set<number>();

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;
    if (this.jets.length === 0) this.spawn(ctx);

    this.x += SPEED * dt;
    for (let i = 0; i < this.jets.length; i++) {
      this.jets[i].position.x = this.x;
      this.jets[i].position.z = this.centerZ + (i - 1) * JET_SPACING;
    }

    // Damage enemies within the corridor as the line passes them.
    const tmp = new THREE.Vector3();
    for (const e of ctx.enemiesOf(ctx.owner.team)) {
      if (!e.alive || this.hit.has(e.id)) continue;
      e.position(tmp);
      const dz = Math.abs(tmp.z - this.centerZ);
      const dx = Math.abs(tmp.x - this.x);
      if (dz <= CORRIDOR * 1.5 && dx <= CORRIDOR) {
        const target: Actor = e;
        streakDamage(target, DAMAGE, ctx, true);
        ctx.vfx.explosion(tmp, 3);
        this.hit.add(e.id);
      }
    }

    if (this.x >= this.endX) this.active = false;
  }

  override dispose(ctx: StreakContext): void {
    for (const jet of this.jets) ctx.root.remove(jet);
    this.jets = [];
    super.dispose(ctx);
  }

  private spawn(ctx: StreakContext): void {
    this.centerZ = (ctx.bounds.minZ + ctx.bounds.maxZ) / 2;
    this.x = ctx.bounds.minX - MARGIN;
    this.endX = ctx.bounds.maxX + MARGIN;

    const group = new THREE.Group();
    for (let i = 0; i < 3; i++) {
      const jet = new THREE.Group();
      const body = new THREE.Mesh(
        new THREE.BoxGeometry(2.5, 0.5, 0.8),
        createToonMaterial({ color: 0x4a5560 }),
      );
      addOutline(body);
      jet.add(body);
      const wing = new THREE.Mesh(
        new THREE.BoxGeometry(0.8, 0.12, 3),
        createToonMaterial({ color: 0x39424a }),
      );
      jet.add(wing);
      jet.position.set(this.x, ALTITUDE, this.centerZ + (i - 1) * JET_SPACING);
      jet.rotation.y = -Math.PI / 2;
      this.jets.push(jet);
      group.add(jet);
    }
    this.mesh = group;
    ctx.root.add(group);
  }
}
