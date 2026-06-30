// Picks spawn points that keep players away from live enemies AND spread the
// team out, then randomises among the safest few so the exact pad is not
// predictable. Each candidate is scored by distance-to-nearest-enemy (safety)
// plus distance-to-recent-ally-spawns (spread); we then pick at random among the
// candidates scoring within SCORE_BAND of the best. Recent picks are remembered
// so the team keeps fanning out instead of stacking on one pad.

import * as THREE from "../three.ts";
import type { SpawnPoint } from "../maps/MapDefinition.ts";
import type { TeamId } from "../core/types.ts";

/** Weight of ally-spread relative to enemy-distance when ranking spawns. */
const SPREAD_WEIGHT = 0.8;
/** Spawns scoring within this many units of the best are all fair game. */
const SCORE_BAND = 14;

export class Spawner {
  private readonly spawns: SpawnPoint[];
  private readonly rng: () => number;
  /** Recently-used spawn positions per team, to spread the team out. */
  private readonly recent = new Map<TeamId, THREE.Vector3[]>();

  constructor(spawns: SpawnPoint[], rng: () => number = Math.random) {
    this.spawns = spawns;
    this.rng = rng;
  }

  /** Reset the spread memory (e.g. on a new round). */
  reset(): void {
    this.recent.clear();
  }

  pick(team: TeamId, enemyPositions: THREE.Vector3[]): SpawnPoint {
    const teamSpawns = this.spawns.filter((s) => s.team === team);
    const candidates = teamSpawns.length > 0 ? teamSpawns : this.spawns;
    if (candidates.length === 0) {
      throw new Error("Spawner: no spawn points available");
    }

    // Score every candidate: far from enemies (safety) + far from recent ally
    // spawns (spread). With no enemies present the safety term is simply zero.
    const recent = this.recent.get(team) ?? [];
    let bestScore = -Infinity;
    const scored = candidates.map((s) => {
      const enemyDist = enemyPositions.length > 0
        ? Math.sqrt(nearestDistanceSq(s.position, enemyPositions))
        : 0;
      const allyDist = recent.length > 0 ? Math.sqrt(nearestDistanceSq(s.position, recent)) : 0;
      const score = enemyDist + SPREAD_WEIGHT * allyDist;
      if (score > bestScore) bestScore = score;
      return { spawn: s, score };
    });

    // Randomise among the spawns nearly as good as the best, so the spot stays
    // safe + spread but is not perfectly predictable.
    const eligible = scored.filter((c) => c.score >= bestScore - SCORE_BAND);
    const idx = Math.min(eligible.length - 1, Math.floor(this.rng() * eligible.length));
    const chosen = eligible[idx].spawn;
    this.remember(team, chosen, candidates.length);
    return chosen;
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
