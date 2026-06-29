// Picks spawn points that keep players away from live enemies AND spread the
// team out (so allies don't all land on the same pad). With no enemies it is a
// deterministic round-robin over the team's spawns; with enemies it ranks each
// candidate by distance-to-nearest-enemy plus distance-to-recent-ally-spawns and
// takes the best, remembering recent picks so the team fans out.

import * as THREE from "../three.ts";
import type { SpawnPoint } from "../maps/MapDefinition.ts";
import type { TeamId } from "../core/types.ts";

/** Weight of ally-spread relative to enemy-distance when ranking spawns. */
const SPREAD_WEIGHT = 0.8;

export class Spawner {
  private readonly spawns: SpawnPoint[];
  /** Per-team round-robin cursor (no-enemy case). */
  private readonly cursor = new Map<TeamId, number>();
  /** Recently-used spawn positions per team, to spread the team out. */
  private readonly recent = new Map<TeamId, THREE.Vector3[]>();

  constructor(spawns: SpawnPoint[]) {
    this.spawns = spawns;
  }

  /** Reset the rotation + spread memory (e.g. on a new round). */
  reset(): void {
    this.cursor.clear();
    this.recent.clear();
  }

  pick(team: TeamId, enemyPositions: THREE.Vector3[]): SpawnPoint {
    const teamSpawns = this.spawns.filter((s) => s.team === team);
    const candidates = teamSpawns.length > 0 ? teamSpawns : this.spawns;
    if (candidates.length === 0) {
      throw new Error("Spawner: no spawn points available");
    }

    // No enemies: deterministic round-robin over the team's spawns.
    if (enemyPositions.length === 0) {
      const i = this.cursor.get(team) ?? 0;
      this.cursor.set(team, i + 1);
      const chosen = candidates[i % candidates.length];
      this.remember(team, chosen, candidates.length);
      return chosen;
    }

    // Rank by safety (far from enemies) + spread (far from recent ally spawns).
    const recent = this.recent.get(team) ?? [];
    let best = candidates[0];
    let bestScore = -Infinity;
    for (const s of candidates) {
      const enemyDist = Math.sqrt(nearestDistanceSq(s.position, enemyPositions));
      const allyDist = recent.length > 0 ? Math.sqrt(nearestDistanceSq(s.position, recent)) : 1000;
      const score = enemyDist + SPREAD_WEIGHT * allyDist;
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    this.remember(team, best, candidates.length);
    return best;
  }

  private remember(team: TeamId, spawn: SpawnPoint, padCount: number): void {
    const recent = this.recent.get(team) ?? [];
    recent.push(spawn.position.clone());
    // Keep just under the pad count so the team cycles all pads before reusing.
    while (recent.length > Math.max(1, padCount - 1)) recent.shift();
    this.recent.set(team, recent);
  }
}

/** Squared distance from `p` to the closest position in `others`. */
function nearestDistanceSq(p: THREE.Vector3, others: THREE.Vector3[]): number {
  let min = Infinity;
  for (const o of others) {
    const d = p.distanceToSquared(o);
    if (d < min) min = d;
  }
  return min;
}
