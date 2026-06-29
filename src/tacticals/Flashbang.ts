// Flashbang: a cooked grenade that, on detonation, blinds + deafens the local
// player if they are close enough and have line of sight to the blast. Intensity
// scales with proximity. No lethal damage. A bright flash sphere is spawned via
// the explosion VFX for the world-visible pop.

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import type { EquipmentContext } from "./Equipment.ts";

const BLIND_RANGE = 18; // metres
const MAX_BLIND = 3.2; // seconds at point-blank
const MAX_DEAFEN = 4.0;

export class Flashbang extends Throwable {
  constructor() {
    super({ fuseSec: 1.6, throwSpeed: 22, bounce: 0.45, detonateOnImpact: false, radius: 2 });
  }

  protected onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    // Bright world pop.
    ctx.vfx.explosion(point, 2);

    const player = ctx.getPlayerPosition(new THREE.Vector3());
    const toPlayer = player.clone().sub(point);
    const dist = toPlayer.length();
    if (dist > BLIND_RANGE) return;

    // Line of sight: ray from blast toward the player; if a solid surface is hit
    // noticeably closer than the player, the blast is occluded (approximate).
    if (dist > 1e-3) {
      const dir = toPlayer.clone().multiplyScalar(1 / dist);
      const hit = ctx.world.raycast(point, dir, dist, this.mesh ?? undefined);
      if (hit && hit.distance < dist - 0.5) return; // wall in the way
    }

    const proximity = 1 - dist / BLIND_RANGE; // 0..1
    ctx.screen.flash(0.5 + 0.5 * proximity, MAX_BLIND * proximity);
    ctx.screen.deafen(MAX_DEAFEN * proximity);
  }
}
