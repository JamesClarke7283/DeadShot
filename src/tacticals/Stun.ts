// Stun grenade: like a flashbang but disorients rather than blinds. On
// detonation, if the local player is within a (smaller) radius with line of
// sight, it applies a screen blur plus a slow blue tint instead of a white
// flash. No lethal damage.

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import type { EquipmentContext } from "./Equipment.ts";

const STUN_RANGE = 12; // metres (smaller than flashbang)
const MAX_BLUR = 12; // px at point-blank
const MAX_TINT = 2.5; // seconds
const MAX_DEAFEN = 2.0;

export class Stun extends Throwable {
  constructor() {
    super({ fuseSec: 1.6, throwSpeed: 22, bounce: 0.45, detonateOnImpact: false, radius: 2 });
  }

  protected onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    ctx.vfx.explosion(point, 1.5);

    const player = ctx.getPlayerPosition(new THREE.Vector3());
    const toPlayer = player.clone().sub(point);
    const dist = toPlayer.length();
    if (dist > STUN_RANGE) return;

    if (dist > 1e-3) {
      const dir = toPlayer.clone().multiplyScalar(1 / dist);
      const hit = ctx.world.raycast(point, dir, dist, this.mesh ?? undefined);
      if (hit && hit.distance < dist - 0.5) return; // occluded
    }

    const proximity = 1 - dist / STUN_RANGE; // 0..1
    ctx.screen.blur(MAX_BLUR * proximity, MAX_TINT * proximity + 0.3);
    ctx.screen.tint("rgba(120,160,255,0.9)", 0.6 * proximity, MAX_TINT * proximity + 0.3);
    ctx.screen.deafen(MAX_DEAFEN * proximity);
  }
}
