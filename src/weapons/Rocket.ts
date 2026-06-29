// Launcher rocket: a Projectile with forward thrust, splash damage on impact and
// an explosion effect. Used by the RPG-7 and the Predator Missile streak.

import * as THREE from "../three.ts";
import { Projectile } from "./Projectile.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import type { RaycastHit, ShooterTag, VFXSink, WorldQuery } from "./combat.ts";
import type { RocketSpec } from "./WeaponDefinition.ts";
import type { TeamId } from "../core/types.ts";

export class Rocket extends Projectile {
  private spec: RocketSpec;
  private owner: ShooterTag;
  private maxSpeed: number;
  private exploded = false;

  constructor(spec: RocketSpec, owner: ShooterTag) {
    super();
    this.spec = spec;
    this.owner = owner;
    this.maxSpeed = spec.speed * 2.2;
    this.mesh = this.buildMesh();
  }

  private buildMesh(): THREE.Group {
    const g = new THREE.Group();
    const body = new THREE.Mesh(
      new THREE.CylinderGeometry(0.08, 0.08, 0.5, 8),
      createToonMaterial({ color: 0x3a3f47 }),
    );
    body.rotation.x = Math.PI / 2; // align +Z
    const tip = new THREE.Mesh(
      new THREE.ConeGeometry(0.1, 0.22, 8),
      createToonMaterial({ color: 0xb3202a }),
    );
    tip.rotation.x = Math.PI / 2;
    tip.position.z = 0.32;
    const glow = new THREE.PointLight(0xffa040, 2, 6, 2);
    glow.position.z = -0.3;
    g.add(body, tip, glow);
    return g;
  }

  protected override onPreMove(dt: number): void {
    // Thrust: accelerate along current heading up to max speed; orient the mesh.
    const speed = this.velocity.length();
    if (speed < this.maxSpeed && speed > 1e-4) {
      this.velocity.multiplyScalar(1 + 1.5 * dt);
    }
    if (this.mesh && speed > 1e-4) {
      this.mesh.quaternion.setFromUnitVectors(
        new THREE.Vector3(0, 0, 1),
        this.velocity.clone().normalize(),
      );
    }
  }

  protected override onImpact(hit: RaycastHit, world: WorldQuery, fx: VFXSink): void {
    this.detonate(hit.point, world, fx, hit.target?.team);
  }

  protected override onExpire(world: WorldQuery, fx: VFXSink): void {
    this.detonate(this.position, world, fx);
  }

  private detonate(
    center: THREE.Vector3,
    world: WorldQuery,
    fx: VFXSink,
    directTeam?: TeamId,
  ): void {
    if (this.exploded) return;
    this.exploded = true;
    fx.explosion(center, this.spec.splashRadius);

    const targets = world.radiusTargets(center, this.spec.splashRadius);
    const pos = new THREE.Vector3();
    for (const t of targets) {
      if (!t.alive) continue;
      if (this.owner.team !== "ffa" && t.team === this.owner.team) continue; // no FF
      const dist = t.position(pos).distanceTo(center);
      const falloff = Math.max(0, 1 - dist / this.spec.splashRadius);
      const splash = this.spec.splashDamage * falloff;
      const direct = directTeam !== undefined && dist < 0.6 ? this.spec.directDamage : 0;
      const amount = Math.max(splash, direct);
      if (amount > 0) {
        t.applyDamage({
          amount,
          headshot: false,
          sourceTeam: this.owner.team,
          explosive: true,
          weaponId: this.owner.weaponId,
          sourceId: this.owner.id,
        });
      }
    }
  }
}
