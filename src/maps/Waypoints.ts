// Bot-navigation waypoint graph generation.
//
// Lays a grid over the play area, drops nodes that fall inside collider boxes,
// places the rest on the ground, and connects 8-neighbours whose connecting
// segment is unobstructed. BotNavigator (Phase 6) runs A* over the result.

import * as THREE from "../three.ts";
import type { CollisionWorld } from "./Collision.ts";
import type { Waypoint } from "./MapDefinition.ts";

export interface GridOptions {
  minX: number;
  maxX: number;
  minZ: number;
  maxZ: number;
  spacing?: number;
  /** Mover radius used for clearance tests. */
  radius?: number;
  groundAt: (x: number, z: number) => number;
}

/** True if a point is clear of all collider boxes at body height. */
function pointFree(
  collision: CollisionWorld,
  x: number,
  z: number,
  groundY: number,
  margin: number,
): boolean {
  const bodyLo = groundY + 0.3;
  const bodyHi = groundY + 1.7;
  for (const box of collision.boxes) {
    if (box.max.y <= bodyLo || box.min.y >= bodyHi) continue;
    if (
      x >= box.min.x - margin && x <= box.max.x + margin &&
      z >= box.min.z - margin && z <= box.max.z + margin
    ) {
      return false;
    }
  }
  return true;
}

function segmentClear(
  collision: CollisionWorld,
  ax: number,
  az: number,
  bx: number,
  bz: number,
  groundY: number,
): boolean {
  const a = new THREE.Vector3(ax, groundY + 1.0, az);
  const b = new THREE.Vector3(bx, groundY + 1.0, bz);
  const dir = b.clone().sub(a);
  const dist = dir.length();
  if (dist < 1e-3) return true;
  dir.multiplyScalar(1 / dist);
  const hit = collision.raycastBoxes(a, dir, dist);
  return hit === null;
}

export function buildGridWaypoints(collision: CollisionWorld, opts: GridOptions): Waypoint[] {
  const spacing = opts.spacing ?? 6;
  const radius = opts.radius ?? 0.5;
  const cols = Math.max(1, Math.floor((opts.maxX - opts.minX) / spacing));
  const rows = Math.max(1, Math.floor((opts.maxZ - opts.minZ) / spacing));

  const grid: (Waypoint | null)[][] = [];
  const waypoints: Waypoint[] = [];
  let id = 0;

  for (let r = 0; r <= rows; r++) {
    grid[r] = [];
    for (let c = 0; c <= cols; c++) {
      const x = opts.minX + c * spacing;
      const z = opts.minZ + r * spacing;
      const gy = opts.groundAt(x, z);
      if (pointFree(collision, x, z, gy, radius)) {
        const wp: Waypoint = { id: id++, position: new THREE.Vector3(x, gy, z), neighbors: [] };
        grid[r][c] = wp;
        waypoints.push(wp);
      } else {
        grid[r][c] = null;
      }
    }
  }

  const dirs = [
    [-1, 0],
    [1, 0],
    [0, -1],
    [0, 1],
    [-1, -1],
    [-1, 1],
    [1, -1],
    [1, 1],
  ];
  for (let r = 0; r <= rows; r++) {
    for (let c = 0; c <= cols; c++) {
      const wp = grid[r][c];
      if (!wp) continue;
      for (const [dr, dc] of dirs) {
        const nr = r + dr;
        const nc = c + dc;
        if (nr < 0 || nc < 0 || nr > rows || nc > cols) continue;
        const nb = grid[nr][nc];
        if (!nb) continue;
        if (
          segmentClear(
            collision,
            wp.position.x,
            wp.position.z,
            nb.position.x,
            nb.position.z,
            wp.position.y,
          )
        ) {
          wp.neighbors.push(nb.id);
        }
      }
    }
  }

  return waypoints;
}
