// Thermite: sticks where it lands and burns a tight area (~2.5m) for ~5s with a
// higher damage-over-time (~40/s) than a molotov. Pure area-denial: white-hot
// burning particles, sampled DoT once per second (flat within radius), friendly
// fire off unless the thrower team is "ffa".

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import { type EquipmentContext } from "./Equipment.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { TeamId } from "../core/types.ts";

const RADIUS = 2.5;
const LIFETIME = 5;
const DPS = 40;
const SPARKS = 14;

interface Spark {
  mesh: THREE.Mesh;
  mat: THREE.MeshToonMaterial;
  phase: number;
}

export class Thermite extends Throwable {
  private burnGroup: THREE.Group | null = null;
  private sparks: Spark[] = [];
  private burning = false;
  private age = 0;
  private tickAcc = 0;
  private burnPos = new THREE.Vector3();

  constructor() {
    super({ throwSpeed: 22, gravity: 20, bounce: 0, detonateOnImpact: true, radius: RADIUS });
  }

  protected override buildMesh(_team: TeamId): THREE.Object3D {
    const mesh = new THREE.Mesh(
      new THREE.CylinderGeometry(0.07, 0.07, 0.2, 8),
      createToonMaterial({ color: 0x8a8f96 }),
    );
    addOutline(mesh, { thickness: 0.02 });
    return mesh;
  }

  protected onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    this.burning = true;
    this.active = true;
    this.burnPos.copy(point);
    ctx.vfx.explosion(point, 0.8);

    const g = new THREE.Group();
    g.position.copy(point).add(new THREE.Vector3(0, 0.04, 0));
    for (let i = 0; i < SPARKS; i++) {
      const r = Math.random() * RADIUS;
      const a = Math.random() * Math.PI * 2;
      const mat = createToonMaterial({
        color: 0xffe08a,
        emissive: 0xffaa00,
        transparent: true,
        opacity: 1,
      });
      const m = new THREE.Mesh(new THREE.SphereGeometry(0.07, 6, 6), mat);
      m.position.set(Math.cos(a) * r, 0.1 + Math.random() * 0.3, Math.sin(a) * r);
      g.add(m);
      this.sparks.push({ mesh: m, mat, phase: Math.random() * Math.PI * 2 });
    }
    ctx.root.add(g);
    this.burnGroup = g;

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
    for (const s of this.sparks) {
      s.phase += dt * (10 + Math.random() * 4);
      s.mesh.scale.setScalar(0.6 + Math.abs(Math.sin(s.phase)) * 0.8);
      s.mat.opacity = fade;
    }

    this.tickAcc += dt;
    while (this.tickAcc >= 1 && this.age < LIFETIME) {
      this.tickAcc -= 1;
      this.damageRadiusFlat(this.burnPos, RADIUS, DPS, ctx, "thermite");
    }

    if (this.age >= LIFETIME) this.active = false;
  }

  override dispose(ctx: EquipmentContext): void {
    if (this.burnGroup) {
      ctx.root.remove(this.burnGroup);
      for (const s of this.sparks) {
        s.mesh.geometry.dispose();
        s.mat.dispose();
      }
      this.burnGroup = null;
      this.sparks = [];
    }
    super.dispose(ctx);
  }
}
