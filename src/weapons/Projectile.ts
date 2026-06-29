// Projectile base + pool.
//
// A Projectile is a kinematic point with a mesh, gravity and segment-based
// collision (raycast from last position to the new one each step so fast movers
// don't tunnel). Subclasses (Rocket) override thrust/impact. The pool owns the
// active list, updates them and recycles spent ones.

import * as THREE from "../three.ts";
import type { RaycastHit, VFXSink, WorldQuery } from "./combat.ts";

export interface ProjectileInit {
  position: THREE.Vector3;
  velocity: THREE.Vector3;
  gravity?: number;
  maxLifetime?: number;
  maxRange?: number;
}

export class Projectile {
  active = true;
  readonly position = new THREE.Vector3();
  readonly velocity = new THREE.Vector3();
  gravity = 0;
  maxLifetime = 8;
  maxRange = 400;
  protected lifetime = 0;
  protected traveled = 0;
  mesh: THREE.Object3D | null = null;

  protected readonly prev = new THREE.Vector3();
  private readonly step = new THREE.Vector3();

  init(opts: ProjectileInit): void {
    this.active = true;
    this.lifetime = 0;
    this.traveled = 0;
    this.position.copy(opts.position);
    this.velocity.copy(opts.velocity);
    this.gravity = opts.gravity ?? 0;
    this.maxLifetime = opts.maxLifetime ?? 8;
    this.maxRange = opts.maxRange ?? 400;
    this.prev.copy(this.position);
  }

  /** Advance the projectile; returns false once it should be recycled. */
  update(dt: number, world: WorldQuery, fx: VFXSink): boolean {
    if (!this.active) return false;
    this.lifetime += dt;
    this.onPreMove(dt);

    if (this.gravity) this.velocity.y -= this.gravity * dt;
    this.prev.copy(this.position);
    this.step.copy(this.velocity).multiplyScalar(dt);
    const stepLen = this.step.length();
    this.position.add(this.step);
    this.traveled += stepLen;

    if (stepLen > 1e-5) {
      const dir = this.step.clone().multiplyScalar(1 / stepLen);
      const hit = world.raycast(this.prev, dir, stepLen, this.mesh ?? undefined);
      if (hit) {
        this.position.copy(hit.point);
        this.onImpact(hit, world, fx);
        this.active = false;
      }
    }

    if (this.mesh) this.mesh.position.copy(this.position);

    if (this.lifetime >= this.maxLifetime || this.traveled >= this.maxRange) {
      this.onExpire(world, fx);
      this.active = false;
    }
    return this.active;
  }

  protected onPreMove(_dt: number): void {}
  protected onImpact(hit: RaycastHit, _world: WorldQuery, fx: VFXSink): void {
    fx.bulletImpact(hit.point, hit.normal, !!hit.target);
  }
  protected onExpire(_world: WorldQuery, _fx: VFXSink): void {}

  dispose(): void {
    const m = this.mesh as THREE.Mesh | null;
    if (m?.isMesh) {
      m.geometry?.dispose();
      const mat = m.material;
      if (Array.isArray(mat)) mat.forEach((x) => x.dispose());
      else (mat as THREE.Material)?.dispose();
    }
  }
}

export class ProjectilePool {
  private active: Projectile[] = [];
  constructor(private root: THREE.Object3D) {}

  spawn(p: Projectile): void {
    if (p.mesh) this.root.add(p.mesh);
    this.active.push(p);
  }

  update(dt: number, world: WorldQuery, fx: VFXSink): void {
    for (let i = this.active.length - 1; i >= 0; i--) {
      const p = this.active[i];
      const alive = p.update(dt, world, fx);
      if (!alive) {
        if (p.mesh) this.root.remove(p.mesh);
        p.dispose();
        this.active.splice(i, 1);
      }
    }
  }

  get count(): number {
    return this.active.length;
  }

  clear(): void {
    for (const p of this.active) {
      if (p.mesh) this.root.remove(p.mesh);
      p.dispose();
    }
    this.active = [];
  }
}
