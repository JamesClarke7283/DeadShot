// C4: a thrown/placed charge. On impact it sticks where it lands and then stays
// active indefinitely (a slow pulsing light) until remote-detonated. The
// EquipmentManager calls detonate() (e.g. on the player's detonator press),
// which produces a large explosion + radial damage and deactivates the charge.

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import type { EquipmentContext } from "./Equipment.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { DamageTarget } from "../weapons/combat.ts";
import type { TeamId } from "../core/types.ts";

const RADIUS = 7;
const DAMAGE = 140;

export class C4 extends Throwable {
  private lightMat: THREE.MeshToonMaterial | null = null;
  private pulse = 0;
  private placed = false;

  constructor() {
    super({
      fuseSec: 0,
      throwSpeed: 18,
      gravity: 20,
      bounce: 0.15,
      detonateOnImpact: false,
      radius: RADIUS,
    });
  }

  protected override buildMesh(_team: TeamId): THREE.Object3D {
    const g = new THREE.Group();
    const brick = new THREE.Mesh(
      new THREE.BoxGeometry(0.22, 0.08, 0.14),
      createToonMaterial({ color: 0xb59a5a }),
    );
    addOutline(brick, { thickness: 0.02 });
    const light = createToonMaterial({ color: 0xff2222, emissive: 0x440000 });
    this.lightMat = light;
    const led = new THREE.Mesh(new THREE.SphereGeometry(0.02, 6, 6), light);
    led.position.set(0, 0.06, 0);
    g.add(brick, led);
    return g;
  }

  protected override onWorldHit(
    point: THREE.Vector3,
    _normal: THREE.Vector3,
    _target: DamageTarget | undefined,
    _ctx: EquipmentContext,
  ): void {
    if (this.placed) return;
    this.placed = true;
    this.stuck = true;
    this.velocity.set(0, 0, 0);
    this.position.copy(point);
    if (this.mesh) this.mesh.position.copy(point);
  }

  override update(dt: number, ctx: EquipmentContext): void {
    super.update(dt, ctx); // arcs until it sticks; fuse is 0 so it never times out
    // Slow LED pulse once placed.
    if (this.placed && this.lightMat && this.active) {
      this.pulse += dt;
      const on = Math.sin(this.pulse * 3) > 0;
      this.lightMat.emissive.setHex(on ? 0x660000 : 0x220000);
    }
  }

  /** Remote detonation (called by EquipmentManager.detonateC4). */
  detonate(ctx: EquipmentContext): void {
    if (this.detonated) return;
    this.detonated = true;
    this.explode(this.position, RADIUS, DAMAGE, ctx, "c4");
    this.active = false;
  }

  /** True once stuck and awaiting remote detonation. */
  get isPlaced(): boolean {
    return this.placed && this.active && !this.detonated;
  }

  protected onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    // C4 only blows on remote command; route the base path to the same effect.
    this.explode(point, RADIUS, DAMAGE, ctx, "c4");
  }
}
