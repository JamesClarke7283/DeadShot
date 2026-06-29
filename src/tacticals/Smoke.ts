// Smoke grenade: on detonation spawns an expanding, slowly-rising cloud built
// from several large semi-transparent toon spheres. The cloud grows in, holds,
// then fades out and removes itself (~9s total). Purely visual here; the
// blocksLineOfSight() note documents the future AI/vision hookup.
//
// AI hookup (later): a cloud blocks line of sight between two points a,b when
// the segment a->b passes within ~cloud radius of the cloud centre while the
// cloud is at/near full opacity. Not used yet (visual-only).

import * as THREE from "../three.ts";
import { Throwable } from "./Throwable.ts";
import { type EquipmentContext } from "./Equipment.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";

const LIFETIME = 9; // seconds
const GROW = 1.5; // ramp-in time
const FADE = 2.5; // fade-out time
const RADIUS = 4;
const PUFFS = 7;
const RISE = 0.35; // metres/sec upward drift
const MAX_OPACITY = 0.55;

interface Puff {
  mesh: THREE.Mesh;
  mat: THREE.MeshToonMaterial;
  baseScale: number;
}

export class Smoke extends Throwable {
  private cloud: THREE.Group | null = null;
  private puffs: Puff[] = [];
  private age = 0;
  private settled = false;

  constructor() {
    super({ fuseSec: 1.4, throwSpeed: 20, bounce: 0.3, detonateOnImpact: false, radius: RADIUS });
  }

  protected onDetonate(point: THREE.Vector3, ctx: EquipmentContext): void {
    // The detonate() in Throwable will set active=false; re-arm so the cloud can
    // continue to live and tick after the canister "pops".
    this.settled = true;
    this.active = true;

    const cloud = new THREE.Group();
    cloud.position.copy(point).add(new THREE.Vector3(0, 0.5, 0));
    for (let i = 0; i < PUFFS; i++) {
      const baseScale = 1.4 + Math.random() * 1.4;
      const mat = createToonMaterial({
        color: 0xcdd2d8,
        transparent: true,
        opacity: 0,
        doubleSide: true,
      });
      const m = new THREE.Mesh(new THREE.SphereGeometry(1, 10, 10), mat);
      m.position.set(
        (Math.random() - 0.5) * RADIUS,
        Math.random() * 1.2,
        (Math.random() - 0.5) * RADIUS,
      );
      m.scale.setScalar(0.1);
      cloud.add(m);
      this.puffs.push({ mesh: m, mat, baseScale });
    }
    ctx.root.add(cloud);
    this.cloud = cloud;

    // Replace the in-flight canister mesh with the cloud for disposal tracking.
    if (this.mesh) {
      ctx.root.remove(this.mesh);
      this.mesh = null;
    }
  }

  override update(dt: number, ctx: EquipmentContext): void {
    if (!this.settled) {
      super.update(dt, ctx);
      return;
    }
    if (!this.cloud) {
      this.active = false;
      return;
    }
    this.age += dt;
    this.cloud.position.y += RISE * dt;

    const grow = Math.min(1, this.age / GROW);
    const fade = this.age > LIFETIME - FADE ? Math.max(0, (LIFETIME - this.age) / FADE) : 1;
    for (const p of this.puffs) {
      p.mesh.scale.setScalar(p.baseScale * grow);
      p.mat.opacity = MAX_OPACITY * grow * fade;
    }
    if (this.age >= LIFETIME) this.active = false;
  }

  override dispose(ctx: EquipmentContext): void {
    if (this.cloud) {
      ctx.root.remove(this.cloud);
      for (const p of this.puffs) {
        p.mesh.geometry.dispose();
        p.mat.dispose();
      }
      this.cloud = null;
      this.puffs = [];
    }
    super.dispose(ctx);
  }
}
