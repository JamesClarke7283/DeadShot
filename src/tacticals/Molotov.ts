// Molotov: shatters on impact and creates a flat fire pool on the ground. The
// pool is a ring of flickering toon-flame meshes of ~3m radius lasting ~6s and
// deals damage-over-time (~25/s, sampled once per second) to targets within
// radius, skipping same-team unless the thrower team is "ffa".

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import { type EquipmentContext } from "./Equipment.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import type { TeamId } from "../core/types.ts";

const RADIUS = 3;
const LIFETIME = 6;
const DPS = 25;
const FLAMES = 10;

interface Flame {
  mesh: THREE.Mesh;
  mat: THREE.MeshToonMaterial;
  phase: number;
  base: number;
}

export class Molotov extends Throwable {
  private fire: THREE.Group | null = null;
  private flames: Flame[] = [];
  private burning = false;
  private age = 0;
  private tickAcc = 0;
  private firePos = new THREE.Vector3();

  constructor() {
    super({ throwSpeed: 22, gravity: 20, bounce: 0, detonateOnImpact: true, radius: RADIUS });
  }

  protected override buildMesh(_team: TeamId): THREE.Object3D {
    const mesh = new THREE.Mesh(
      new THREE.CylinderGeometry(0.06, 0.08, 0.22, 8),
      createToonMaterial({ color: 0x8a5a2a, transparent: true, opacity: 0.85 }),
    );
    return mesh;
  }

  protected onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    // Convert into a persisting fire pool; re-arm active so update keeps running.
    this.burning = true;
    this.active = true;
    this.firePos.copy(point);
    ctx.vfx.explosion(point, 1); // small splash flash

    const fire = new THREE.Group();
    fire.position.copy(point).add(new THREE.Vector3(0, 0.05, 0));
    for (let i = 0; i < FLAMES; i++) {
      const a = (i / FLAMES) * Math.PI * 2;
      const r = Math.random() * RADIUS;
      const base = 0.3 + Math.random() * 0.5;
      const mat = createToonMaterial({
        color: 0xff8a1e,
        emissive: 0xff4400,
        transparent: true,
        opacity: 0.9,
        doubleSide: true,
      });
      const m = new THREE.Mesh(new THREE.ConeGeometry(0.25, 0.7, 6), mat);
      m.position.set(Math.cos(a) * r, base * 0.5, Math.sin(a) * r);
      fire.add(m);
      this.flames.push({ mesh: m, mat, phase: Math.random() * Math.PI * 2, base });
    }
    ctx.root.add(fire);
    this.fire = fire;

    if (this.mesh) {
      ctx.root.remove(this.mesh);
      this.mesh = null;
    }
  }

  override update(dt: number, ctx: EquipmentContext): void {
    if (!this.burning) {
      super.update(dt, ctx);
      return;
    }
    this.age += dt;
    const fade = this.age > LIFETIME - 1 ? Math.max(0, LIFETIME - this.age) : 1;

    for (const f of this.flames) {
      f.phase += dt * (6 + Math.random() * 2);
      const flick = 0.7 + Math.sin(f.phase) * 0.3;
      f.mesh.scale.setScalar(flick);
      f.mat.opacity = 0.9 * fade;
    }

    // DoT sampled once per second.
    this.tickAcc += dt;
    while (this.tickAcc >= 1 && this.age < LIFETIME) {
      this.tickAcc -= 1;
      this.damageRadiusFlat(this.firePos, RADIUS, DPS, ctx, "molotov");
    }

    if (this.age >= LIFETIME) this.active = false;
  }

  override dispose(ctx: EquipmentContext): void {
    if (this.fire) {
      ctx.root.remove(this.fire);
      for (const f of this.flames) {
        f.mesh.geometry.dispose();
        f.mat.dispose();
      }
      this.fire = null;
      this.flames = [];
    }
    super.dispose(ctx);
  }
}
