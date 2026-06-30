// Scatters team spawn points across the map instead of lining them up in one
// predictable row. Blue gets the south band, red the north band (opposite ends,
// as before) and FFA fills the whole arena. Candidates that fall inside a
// collider are skipped so nobody spawns inside a wall, and same-team pads are
// kept apart so a team never clumps in one corner.
//
// The layout is deterministic (no RNG) so every client builds the same pads;
// the per-spawn unpredictability comes from Spawner.pick at runtime.

import * as THREE from "../three.ts";
import type { CollisionWorld } from "./Collision.ts";
import type { SpawnPoint } from "./MapDefinition.ts";
import type { TeamId } from "../core/types.ts";
import { pointFree } from "./Waypoints.ts";

export interface SpawnLayoutOptions {
  bounds: { minX: number; maxX: number; minZ: number; maxZ: number };
  groundAt: (x: number, z: number) => number;
  /** Mover clearance radius used to reject blocked candidate spots. */
  clearance?: number;
  /** Target spawns per team (best-effort; obstacle-blocked spots are skipped). */
  perTeam?: number;
  /** Minimum gap between two pads of the same team. */
  minSeparation?: number;
}

// Golden-ratio low-discrepancy fractions: deterministic, evenly spread and
// non-linear, so the pads scatter in 2D rather than forming a straight line.
const PHI = 0.6180339887498949;
const PHI2 = 0.7548776662466927;

function tooClose(spawns: SpawnPoint[], team: TeamId, x: number, z: number, min: number): boolean {
  const min2 = min * min;
  for (const s of spawns) {
    if (s.team !== team) continue;
    const dx = s.position.x - x;
    const dz = s.position.z - z;
    if (dx * dx + dz * dz < min2) return true;
  }
  return false;
}

/**
 * Build scattered, obstacle-free spawn pads: blue across the south band, red
 * across the north band (opposite ends), FFA across the whole arena.
 */
export function scatterSpawns(collision: CollisionWorld, opts: SpawnLayoutOptions): SpawnPoint[] {
  const { bounds, groundAt } = opts;
  const clearance = opts.clearance ?? 0.9;
  const perTeam = opts.perTeam ?? 9;
  const minSep = opts.minSeparation ?? 7;
  const inset = 8;
  const minX = bounds.minX + inset;
  const maxX = bounds.maxX - inset;
  const depth = bounds.maxZ - bounds.minZ;

  const spawns: SpawnPoint[] = [];

  const addBand = (team: TeamId, zLo: number, zHi: number, yaw: number) => {
    let placed = 0;
    // Oversample so obstacle-blocked candidates don't starve the band.
    for (let i = 0; i < perTeam * 4 && placed < perTeam; i++) {
      const x = minX + ((i * PHI) % 1) * (maxX - minX);
      const z = zLo + ((i * PHI2) % 1) * (zHi - zLo);
      const gy = groundAt(x, z);
      if (!pointFree(collision, x, z, gy, clearance)) continue;
      if (tooClose(spawns, team, x, z, minSep)) continue;
      spawns.push({ position: new THREE.Vector3(x, gy, z), yaw, team });
      placed++;
    }
  };

  // Blue = south band, red = north band (opposite ends, with an empty no-man's
  // strip down the middle). FFA scatters across the whole play area.
  addBand("blue", bounds.minZ + inset, bounds.minZ + depth * 0.42, 0);
  addBand("red", bounds.maxZ - depth * 0.42, bounds.maxZ - inset, Math.PI);
  addBand("ffa", bounds.minZ + inset, bounds.maxZ - inset, 0);

  return spawns;
}
