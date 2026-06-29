// Picks spawn points that keep players away from live enemies. Filters spawns
// to the requesting team, ranks the candidates by distance to the nearest
// enemy (safest first), then round-robins among the safest few so respawns
// don't always land on the same pad.

import * as THREE from "../three.ts";
import type { SpawnPoint } from "../maps/MapDefinition.ts";
import type { TeamId } from "../core/types.ts";

/** How many of the safest candidates to rotate among. */
const SAFE_POOL = 3;

export class Spawner {
  private readonly spawns: SpawnPoint[];
  /** Per-team round-robin cursor. */
  private readonly cursor = new Map<TeamId, number>();

  constructor(spawns: SpawnPoint[]) {
    this.spawns = spawns;
  }

  /** Reset the round-robin rotation (e.g. on a new round). */
  reset(): void {
    this.cursor.clear();
  }

  pick(team: TeamId, enemyPositions: THREE.Vector3[]): SpawnPoint {
    const teamSpawns = this.spawns.filter((s) => s.team === team);
    const candidates = teamSpawns.length > 0 ? teamSpawns : this.spawns;
    if (candidates.length === 0) {
      throw new Error("Spawner: no spawn points available");
    }

    const i = this.cursor.get(team) ?? 0;
    this.cursor.set(team, i + 1);

    // No enemies: plain round-robin over the team's spawns.
    if (enemyPositions.length === 0) {
      return candidates[i % candidates.length];
    }

    // Rank by distance to the nearest enemy (descending => safest first).
    const ranked = candidates
      .map((spawn) => ({
        spawn,
        safety: nearestDistanceSq(spawn.position, enemyPositions),
      }))
      .sort((a, b) => b.safety - a.safety);

    // Only consider spawns that are genuinely far from enemies (within ~84% of
    // the farthest spawn's distance), so enemies always respawn away from allies
    // — then rotate among those few to avoid predictable spawn-camping.
    const best = ranked[0].safety;
    const safe = ranked.filter((r) => r.safety >= best * 0.7);
    const pool = (safe.length > 0 ? safe : ranked).slice(0, Math.max(SAFE_POOL, 1));
    return pool[i % pool.length].spawn;
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
