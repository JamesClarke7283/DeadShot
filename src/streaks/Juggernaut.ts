// Juggernaut scorestreak.
//
// Buffs the owner into an armored tank for a duration: boosts their health and
// max health (and bulks them up visually). When the timer runs out the owner is
// restored to normal max health (clamped) if still alive.

import type * as THREE from "../three.ts";
import { Streak, type StreakContext } from "./Streak.ts";

const DURATION = 30;
const ARMOR_HEALTH = 300;
const BASE_HEALTH = 100;
const SCALE = 1.2;

/** The mutable health/visual fields a Juggernaut needs on the owner actor. */
interface Buffable {
  health: number;
  maxHealth?: number;
  object3d?: THREE.Object3D;
  alive: boolean;
}

export class Juggernaut extends Streak {
  readonly id = "juggernaut";
  readonly name = "Juggernaut";

  private elapsed = 0;
  private buffed = false;
  private ownerRef: Buffable | null = null;
  private originalScale = 1;

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;

    if (!this.buffed) {
      this.buffed = true;
      const actor = ctx.allActors().find((a) => a.id === ctx.owner.id);
      if (actor) {
        const b = actor as unknown as Buffable;
        this.ownerRef = b;
        if (b.maxHealth !== undefined) b.maxHealth = ARMOR_HEALTH;
        b.health = ARMOR_HEALTH;
        if (b.object3d) {
          this.originalScale = b.object3d.scale.x;
          b.object3d.scale.setScalar(this.originalScale * SCALE);
        }
      }
    }

    this.elapsed += dt;
    if (this.elapsed >= DURATION) {
      this.restore();
      this.active = false;
    }
  }

  override dispose(ctx: StreakContext): void {
    this.restore();
    super.dispose(ctx);
  }

  private restore(): void {
    const b = this.ownerRef;
    if (!b) return;
    if (b.object3d) b.object3d.scale.setScalar(this.originalScale);
    if (b.alive) {
      if (b.maxHealth !== undefined) b.maxHealth = BASE_HEALTH;
      if (b.health > BASE_HEALTH) b.health = BASE_HEALTH;
    }
    this.ownerRef = null;
  }
}
