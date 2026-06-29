// Snapshot grenade: on detonation it pings the area, revealing the positions of
// all enemies within range to the thrower's team via ctx.onSnapshot (the radar
// hook). No damage. A brief expanding ping ring is shown via the explosion VFX.

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import type { EquipmentContext } from "./Equipment.ts";

const SCAN_RADIUS = 25;

export class Snapshot extends Throwable {
  constructor() {
    super({
      fuseSec: 1.4,
      throwSpeed: 22,
      bounce: 0.4,
      detonateOnImpact: false,
      radius: SCAN_RADIUS,
    });
  }

  protected onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    ctx.vfx.explosion(point, 2); // brief ping pop

    const positions: THREE.Vector3[] = [];
    const pos = new THREE.Vector3();
    for (const t of ctx.world.radiusTargets(point, SCAN_RADIUS)) {
      if (!t.alive) continue;
      if (this.team !== "ffa" && t.team === this.team) continue; // only enemies
      positions.push(t.position(pos).clone());
    }
    ctx.onSnapshot?.(positions);
  }
}
