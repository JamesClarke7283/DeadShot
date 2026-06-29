// Collision world for player/bot movement.
//
// Map geometry is mostly box-shaped (buildings, crates, containers), so colliders
// are axis-aligned boxes (Box3) plus an optional terrain height field for the
// floor. This is a pragmatic stand-in for a merged mesh BVH: cheap, robust, and
// exact for our primitive-built maps. Movers are treated as vertical cylinders
// (radius + height) and pushed out of boxes horizontally (collide-and-slide),
// with the feet clamped to the ground height.

import * as THREE from "../three.ts";

export interface HeightField {
  sampleHeight(x: number, z: number): number;
}

export class CollisionWorld {
  readonly boxes: THREE.Box3[] = [];
  terrain: HeightField | null = null;

  setTerrain(t: HeightField | null): void {
    this.terrain = t;
  }

  addBox(box: THREE.Box3): void {
    this.boxes.push(box);
  }

  /** Compute and add a world-space AABB from an object's geometry. */
  addObjectAABB(obj: THREE.Object3D): void {
    obj.updateWorldMatrix(true, false);
    const box = new THREE.Box3().setFromObject(obj);
    if (isFinite(box.min.x) && box.min.x < box.max.x) this.boxes.push(box);
  }

  clear(): void {
    this.boxes.length = 0;
    this.terrain = null;
  }

  groundHeight(x: number, z: number): number {
    return this.terrain ? this.terrain.sampleHeight(x, z) : 0;
  }

  /**
   * Resolve a mover at feet position `pos` (mutated in place). Pushes the mover
   * out of any box it overlaps in XZ (when vertically overlapping), then clamps
   * the feet onto the ground. `radius` is the mover's horizontal radius, `height`
   * its standing height.
   */
  resolve(pos: THREE.Vector3, radius: number, height: number): void {
    const groundY = this.groundHeight(pos.x, pos.z);
    if (pos.y < groundY) pos.y = groundY;

    const feetY = pos.y;
    const headY = pos.y + height;

    // Two relaxation passes for stability in corners.
    for (let pass = 0; pass < 2; pass++) {
      for (const box of this.boxes) {
        // Vertical overlap test (skip boxes entirely above the head or below
        // the feet, with a small step tolerance at the bottom).
        if (box.max.y <= feetY + 0.25 || box.min.y >= headY) continue;
        pushOutXZ(pos, radius, box);
      }
    }

    const g2 = this.groundHeight(pos.x, pos.z);
    if (pos.y < g2) pos.y = g2;
  }

  /** Simple segment raycast against the boxes; returns distance or null. */
  raycastBoxes(origin: THREE.Vector3, dir: THREE.Vector3, maxDist: number): number | null {
    let best: number | null = null;
    const ray = new THREE.Ray(origin, dir);
    const hit = new THREE.Vector3();
    for (const box of this.boxes) {
      const r = ray.intersectBox(box, hit);
      if (r) {
        const d = origin.distanceTo(hit);
        if (d <= maxDist && (best === null || d < best)) best = d;
      }
    }
    return best;
  }
}

/**
 * Walk an object tree and register a world-space AABB for every mesh tagged
 * `userData.collider === true` (set by the Building/Obstacle builders). Call
 * after the object has been positioned in the scene.
 */
export function registerColliders(root: THREE.Object3D, world: CollisionWorld): void {
  root.updateWorldMatrix(true, true);
  root.traverse((obj) => {
    if (obj.userData?.collider) {
      const box = new THREE.Box3().setFromObject(obj);
      if (isFinite(box.min.x) && box.min.x < box.max.x) world.addBox(box);
    }
  });
}

/** Push a vertical cylinder (circle in XZ) out of a box's XZ rectangle. */
function pushOutXZ(pos: THREE.Vector3, radius: number, box: THREE.Box3): void {
  const cx = THREE.MathUtils.clamp(pos.x, box.min.x, box.max.x);
  const cz = THREE.MathUtils.clamp(pos.z, box.min.z, box.max.z);
  const dx = pos.x - cx;
  const dz = pos.z - cz;
  const distSq = dx * dx + dz * dz;

  if (distSq > radius * radius) return; // not touching

  if (distSq > 1e-8) {
    // Outside the rect but within radius: push along the closest-point normal.
    const dist = Math.sqrt(distSq);
    const push = radius - dist;
    pos.x += (dx / dist) * push;
    pos.z += (dz / dist) * push;
  } else {
    // Center is inside the rect: eject along the least-penetration axis.
    const toMinX = pos.x - box.min.x;
    const toMaxX = box.max.x - pos.x;
    const toMinZ = pos.z - box.min.z;
    const toMaxZ = box.max.z - pos.z;
    const minPen = Math.min(toMinX, toMaxX, toMinZ, toMaxZ);
    if (minPen === toMinX) pos.x = box.min.x - radius;
    else if (minPen === toMaxX) pos.x = box.max.x + radius;
    else if (minPen === toMinZ) pos.z = box.min.z - radius;
    else pos.z = box.max.z + radius;
  }
}
