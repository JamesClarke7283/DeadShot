// Frag grenade: a cooked lethal that detonates on its fuse (not impact),
// bouncing off surfaces until it blows. Standard explosion + radial damage with
// distance falloff and friendly-fire protection.

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import type { EquipmentContext } from "./Equipment.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { TeamId } from "../core/types.ts";

const FUSE = 3.0;
const RADIUS = 6;
const DAMAGE = 120;

export class Frag extends Throwable {
  constructor() {
    super({ fuseSec: FUSE, throwSpeed: 22, bounce: 0.4, detonateOnImpact: false, radius: RADIUS });
  }

  protected override buildMesh(_team: TeamId): THREE.Object3D {
    const mesh = new THREE.Mesh(
      new THREE.SphereGeometry(0.13, 12, 12),
      createToonMaterial({ color: 0x3c4a2e }),
    );
    addOutline(mesh, { thickness: 0.02 });
    return mesh;
  }

  protected onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    this.explode(point, RADIUS, DAMAGE, ctx, "frag");
  }
}
