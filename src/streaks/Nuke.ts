// Tactical Nuke scorestreak.
//
// The game-ender. After a short countdown it ends the match in the owner's
// favor. A growing bright sphere telegraphs the detonation; the Match shows the
// victory banner once endMatch is called.

import * as THREE from "../three.ts";
import { Streak, type StreakContext } from "./Streak.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";

const COUNTDOWN = 6;

export class Nuke extends Streak {
  readonly id = "nuke";
  readonly name = "Tactical Nuke";

  private elapsed = 0;
  private detonated = false;

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;
    if (!this.mesh) this.spawn(ctx);

    this.elapsed += dt;
    const t = Math.min(1, this.elapsed / COUNTDOWN);
    if (this.mesh) {
      // Bloom up as the countdown completes.
      const s = 0.5 + t * t * 40;
      this.mesh.scale.setScalar(s);
    }

    if (!this.detonated && this.elapsed >= COUNTDOWN) {
      this.detonated = true;
      ctx.endMatch(ctx.owner.team);
      this.active = false;
    }
  }

  private spawn(ctx: StreakContext): void {
    const sphere = new THREE.Mesh(
      new THREE.SphereGeometry(1, 16, 12),
      createToonMaterial({
        color: 0xffffaa,
        emissive: 0xffaa33,
        transparent: true,
        opacity: 0.85,
      }),
    );
    sphere.position.set(
      (ctx.bounds.minX + ctx.bounds.maxX) / 2,
      ctx.groundAt(
        (ctx.bounds.minX + ctx.bounds.maxX) / 2,
        (ctx.bounds.minZ + ctx.bounds.maxZ) / 2,
      ) + 2,
      (ctx.bounds.minZ + ctx.bounds.maxZ) / 2,
    );
    this.mesh = sphere;
    ctx.root.add(sphere);
  }
}
