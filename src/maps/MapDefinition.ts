// Map contract shared by every map (DesertTown, ForestFacility, UrbanDocks).
//
// A MapDefinition is a factory: build() assembles a fresh visual root, a
// CollisionWorld, spawn points per team, a bot-nav waypoint graph and the
// environment (sky/fog/lighting). Game/Match swaps maps by calling build().

import type * as THREE from "../three.ts";
import type { CollisionWorld } from "./Collision.ts";
import type { EnvironmentOptions } from "../core/Scene.ts";
import type { TeamId } from "../core/types.ts";

export interface SpawnPoint {
  position: THREE.Vector3;
  /** Facing yaw in radians (look direction). */
  yaw: number;
  team: TeamId;
}

export interface Waypoint {
  id: number;
  position: THREE.Vector3;
  neighbors: number[];
}

export interface MapBuild {
  /** Visual + collidable geometry to add under the scene's map root. */
  root: THREE.Group;
  collision: CollisionWorld;
  spawns: SpawnPoint[];
  waypoints: Waypoint[];
  environment: EnvironmentOptions;
  /** Ground height query (terrain-aware). */
  groundAt(x: number, z: number): number;
  /** Per-frame hook (e.g. foliage wind). */
  update?(dt: number, elapsed: number): void;
  bounds: { minX: number; maxX: number; minZ: number; maxZ: number };
}

export interface MapDefinition {
  id: string;
  name: string;
  description: string;
  build(): MapBuild;
}

export function spawnsForTeam(build: MapBuild, team: TeamId): SpawnPoint[] {
  const matching = build.spawns.filter((s) => s.team === team);
  return matching.length > 0 ? matching : build.spawns;
}
