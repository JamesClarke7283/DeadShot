// Claymore: placed on the ground facing the throw direction. After a short arm
// delay it watches a frontal trip volume; the first enemy that steps within
// range AND inside the forward cone (~60° half-angle) triggers a directional
// detonation that damages targets in front of the mine. A faint red laser line
// is drawn ahead while armed.

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import { type EquipmentContext } from "./Equipment.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { DamageTarget } from "../weapons/combat.ts";
import type { TeamId } from "../core/types.ts";

const ARM_DELAY = 1.0;
const TRIP_RANGE = 5;
const CONE_COS = Math.cos((60 * Math.PI) / 180); // 60° half-angle
const DAMAGE = 150;
const LASER_LEN = 5;

export class Claymore extends Throwable {
  private placed = false;
  private armTimer = ARM_DELAY;
  /** Horizontal facing direction (set from the throw aim). */
  private readonly facing = new THREE.Vector3(0, 0, 1);
  private laser: THREE.Line | null = null;
  private laserMat: THREE.LineBasicMaterial | null = null;

  constructor() {
    super({
      fuseSec: 0,
      throwSpeed: 14,
      gravity: 20,
      bounce: 0.1,
      detonateOnImpact: false,
      radius: TRIP_RANGE,
    });
  }

  override throw(
    origin: THREE.Vector3,
    direction: THREE.Vector3,
    team: TeamId,
    ctx: EquipmentContext,
  ): void {
    super.throw(origin, direction, team, ctx);
    // Face the (horizontal) aim direction.
    this.facing.set(direction.x, 0, direction.z);
    if (this.facing.lengthSq() < 1e-6) this.facing.set(0, 0, 1);
    this.facing.normalize();
  }

  protected override buildMesh(team: TeamId): THREE.Object3D {
    const g = new THREE.Group();
    const body = new THREE.Mesh(
      new THREE.BoxGeometry(0.3, 0.18, 0.06),
      createToonMaterial({ color: 0x4a5a3a }),
    );
    body.position.y = 0.09;
    addOutline(body, { thickness: 0.02 });
    // Little legs.
    const legMat = createToonMaterial({ color: 0x2a2f25 });
    const legGeo = new THREE.CylinderGeometry(0.01, 0.01, 0.12, 4);
    const l1 = new THREE.Mesh(legGeo, legMat);
    l1.position.set(-0.1, 0, 0);
    const l2 = new THREE.Mesh(legGeo, legMat);
    l2.position.set(0.1, 0, 0);
    g.add(body, l1, l2);
    // Orient +Z face toward the throw direction once placed.
    g.userData.team = team;
    return g;
  }

  protected override onWorldHit(
    point: THREE.Vector3,
    _normal: THREE.Vector3,
    _target: DamageTarget | undefined,
    ctx: EquipmentContext,
  ): void {
    if (this.placed) return;
    this.placed = true;
    this.stuck = true;
    this.velocity.set(0, 0, 0);
    this.position.copy(point);
    if (this.mesh) {
      this.mesh.position.copy(point);
      this.mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), this.facing);
    }
    this.spawnLaser(ctx);
  }

  private spawnLaser(ctx: EquipmentContext): void {
    const start = this.position.clone().add(new THREE.Vector3(0, 0.12, 0));
    const end = start.clone().addScaledVector(this.facing, LASER_LEN);
    const geo = new THREE.BufferGeometry().setFromPoints([start, end]);
    const mat = new THREE.LineBasicMaterial({ color: 0xff2a2a, transparent: true, opacity: 0.0 });
    this.laserMat = mat;
    this.laser = new THREE.Line(geo, mat);
    ctx.root.add(this.laser);
  }

  override update(dt: number, ctx: EquipmentContext): void {
    if (!this.placed) {
      super.update(dt, ctx);
      return;
    }
    if (this.detonated) return;

    if (this.armTimer > 0) {
      this.armTimer -= dt;
      return; // not yet armed: no laser, no trip
    }
    if (this.laserMat) this.laserMat.opacity = 0.35; // armed: show beam

    // Scan for the first enemy inside the forward cone.
    const pos = new THREE.Vector3();
    const toTarget = new THREE.Vector3();
    for (const t of ctx.world.radiusTargets(this.position, TRIP_RANGE)) {
      if (!t.alive) continue;
      if (this.team !== "ffa" && t.team === this.team) continue;
      toTarget.copy(t.position(pos)).sub(this.position);
      const dist = toTarget.length();
      if (dist < 1e-3) continue;
      toTarget.multiplyScalar(1 / dist);
      if (toTarget.dot(this.facing) >= CONE_COS) {
        this.triggerDetonate(ctx);
        return;
      }
    }
  }

  private triggerDetonate(ctx: EquipmentContext): void {
    if (this.detonated) return;
    this.detonated = true;
    ctx.vfx.explosion(this.position, 3);

    // Directional damage: only targets inside the forward cone are hit.
    const pos = new THREE.Vector3();
    const toTarget = new THREE.Vector3();
    for (const t of ctx.world.radiusTargets(this.position, TRIP_RANGE)) {
      if (!t.alive) continue;
      if (this.team !== "ffa" && t.team === this.team) continue;
      toTarget.copy(t.position(pos)).sub(this.position);
      const dist = toTarget.length();
      if (dist < 1e-3) continue;
      const dir = toTarget.clone().multiplyScalar(1 / dist);
      if (dir.dot(this.facing) < CONE_COS) continue; // behind/side: safe
      const amount = DAMAGE * Math.max(0, 1 - dist / TRIP_RANGE);
      if (amount <= 0) continue;
      t.applyDamage({
        amount,
        headshot: false,
        sourceTeam: this.team,
        explosive: true,
        weaponId: "claymore",
      });
    }
    this.active = false;
  }

  protected onDetonate(_point: THREE.Vector3, ctx: EquipmentContext): void {
    this.triggerDetonate(ctx);
  }

  override dispose(ctx: EquipmentContext): void {
    if (this.laser) {
      ctx.root.remove(this.laser);
      this.laser.geometry.dispose();
      this.laserMat?.dispose();
      this.laser = null;
    }
    super.dispose(ctx);
  }
}
