// Semtex: a sticky grenade. On its first impact (world or actor) it sticks at
// the contact point (stops moving), beeps for a short fuse, then detonates with
// an explosion + radial damage. Distinguished by a bright tacky-green body.

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import type { EquipmentContext } from "./Equipment.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { DamageTarget } from "../weapons/combat.ts";
import type { TeamId } from "../core/types.ts";

const STICK_FUSE = 1.5;
const RADIUS = 5.5;
const DAMAGE = 130;

export class Semtex extends Throwable {
  private blink = 0;
  private bodyMat: THREE.MeshToonMaterial | null = null;

  constructor() {
    super({ throwSpeed: 24, gravity: 18, detonateOnImpact: false, radius: RADIUS });
  }

  protected override buildMesh(_team: TeamId): THREE.Object3D {
    const mat = createToonMaterial({ color: 0x9bd92a, emissive: 0x224400 });
    this.bodyMat = mat;
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.12, 0.26), mat);
    addOutline(mesh, { thickness: 0.02 });
    return mesh;
  }

  protected override onWorldHit(
    point: THREE.Vector3,
    _normal: THREE.Vector3,
    _target: DamageTarget | undefined,
    _ctx: EquipmentContext,
  ): void {
    if (this.stuck) return;
    // Stick: stop here and start the short fuse.
    this.stuck = true;
    this.velocity.set(0, 0, 0);
    this.position.copy(point);
    if (this.mesh) this.mesh.position.copy(point);
    this.cfg.fuseSec = STICK_FUSE;
    this.fuse = STICK_FUSE;
  }

  override update(dt: number, ctx: EquipmentContext): void {
    super.update(dt, ctx);
    // Beep: blink the emissive faster as the fuse runs down.
    if (this.stuck && this.bodyMat && !this.detonated) {
      this.blink += dt;
      const rate = 6 + (STICK_FUSE - Math.max(0, this.fuse)) * 6;
      const on = Math.sin(this.blink * rate) > 0;
      this.bodyMat.emissive.setHex(on ? 0xff3300 : 0x224400);
    }
  }

  protected onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    this.explode(point, RADIUS, DAMAGE, ctx, "semtex");
  }
}
