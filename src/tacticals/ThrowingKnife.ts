// Throwing knife: a fast, near-flat projectile (very low gravity). On a direct
// hit against an enemy DamageTarget it deals lethal damage. On any impact it
// stops and leaves a recoverable knife mesh stuck in the surface for a few
// seconds before removing itself.

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import type { EquipmentContext } from "./Equipment.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { DamageTarget } from "../weapons/combat.ts";
import type { TeamId } from "../core/types.ts";

const DAMAGE = 150;
const STUCK_LIFETIME = 6; // seconds the recoverable knife persists

export class ThrowingKnife extends Throwable {
  private landed = false;
  private restTimer = 0;

  constructor() {
    // Low gravity + high speed => flat trajectory. No fuse: it lands and rests.
    super({ throwSpeed: 40, gravity: 3, bounce: 0, detonateOnImpact: false, radius: 0 });
  }

  protected override buildMesh(_team: TeamId): THREE.Object3D {
    const g = new THREE.Group();
    const blade = new THREE.Mesh(
      new THREE.ConeGeometry(0.03, 0.28, 6),
      createToonMaterial({ color: 0xcfd6dd }),
    );
    blade.rotation.x = -Math.PI / 2; // point along +Z
    blade.position.z = 0.14;
    const handle = new THREE.Mesh(
      new THREE.CylinderGeometry(0.025, 0.025, 0.12, 6),
      createToonMaterial({ color: 0x2a2f36 }),
    );
    handle.rotation.x = Math.PI / 2;
    handle.position.z = -0.06;
    addOutline(blade, { thickness: 0.012 });
    addOutline(handle, { thickness: 0.012 });
    g.add(blade, handle);
    return g;
  }

  override update(dt: number, ctx: EquipmentContext): void {
    if (this.landed) {
      this.restTimer -= dt;
      if (this.restTimer <= 0) this.active = false;
      return;
    }
    super.update(dt, ctx);
    // Orient along velocity while in flight.
    if (this.mesh && !this.landed) {
      const v = this.velocity;
      if (v.lengthSq() > 1e-4) {
        this.mesh.quaternion.setFromUnitVectors(
          new THREE.Vector3(0, 0, 1),
          v.clone().normalize(),
        );
      }
    }
  }

  protected override onWorldHit(
    point: THREE.Vector3,
    _normal: THREE.Vector3,
    target: DamageTarget | undefined,
    _ctx: EquipmentContext,
  ): void {
    // Direct lethal hit on an enemy.
    if (target && target.alive && (this.team === "ffa" || target.team !== this.team)) {
      target.applyDamage({
        amount: DAMAGE,
        headshot: false,
        sourceTeam: this.team,
        weaponId: "knife",
        sourceId: this.sourceId,
      });
    }
    // Land and rest as a recoverable knife regardless of what was hit.
    this.landed = true;
    this.restTimer = STUCK_LIFETIME;
    this.velocity.set(0, 0, 0);
    this.position.copy(point);
    if (this.mesh) this.mesh.position.copy(point);
  }

  protected onDetonate(_point: THREE.Vector3, _ctx: EquipmentContext): void {
    // Knives never "detonate"; they land. Required by Throwable.
  }
}
