import { assert, assertEquals } from "@std/assert";
import * as THREE from "../three.ts";
import { Navigator } from "./BotNavigator.ts";
import type { Waypoint } from "../maps/MapDefinition.ts";

// Synthetic graph shaped like a wall with a detour. Direct A->B is impossible;
// the only route goes "down" through nodes 2 and 3.
//
//   0(0,0)        1(10,0)      <- goal row (no direct 0-1 link: wall between)
//   |                |
//   2(0,10) ------ 3(10,10)    <- detour row
function wallGraph(): Waypoint[] {
  const wp = (id: number, x: number, z: number, neighbors: number[]): Waypoint => ({
    id,
    position: new THREE.Vector3(x, 0, z),
    neighbors,
  });
  return [
    wp(0, 0, 0, [2]),
    wp(1, 10, 0, [3]),
    wp(2, 0, 10, [0, 3]),
    wp(3, 10, 10, [2, 1]),
  ];
}

Deno.test("nearest returns the closest waypoint", () => {
  const nav = new Navigator(wallGraph());
  const n = nav.nearest(new THREE.Vector3(0.4, 0, 0.4));
  assertEquals(n?.id, 0);
});

Deno.test("A* routes around a wall via the detour", () => {
  const nav = new Navigator(wallGraph());
  const path = nav.findPath(new THREE.Vector3(0, 0, 0), new THREE.Vector3(10, 0, 0));
  assert(path.length >= 3, "path should detour, not go straight");
  // The path must pass through the detour row (z ~ 10).
  const usesDetour = path.some((p) => Math.abs(p.z - 10) < 0.01);
  assert(usesDetour, "path must traverse the detour waypoints at z=10");
  // Ends at the goal.
  const last = path[path.length - 1];
  assertEquals([last.x, last.z], [10, 0]);
});

Deno.test("disconnected goal yields no path", () => {
  const graph = wallGraph();
  graph.push({ id: 4, position: new THREE.Vector3(100, 0, 100), neighbors: [] });
  const nav = new Navigator(graph);
  // Start near 0, goal near the isolated node 4 — node 4 has no inbound edges,
  // so from the connected component there is no route.
  const path = nav.findPath(new THREE.Vector3(0, 0, 0), new THREE.Vector3(100, 0, 100));
  assertEquals(path.length, 0);
});

Deno.test("line-of-sight smoothing collapses a clear straight run", () => {
  // A straight chain 0-1-2-3 with all clear LOS should smooth to endpoints.
  const wp = (id: number, x: number, neighbors: number[]): Waypoint => ({
    id,
    position: new THREE.Vector3(x, 0, 0),
    neighbors,
  });
  const nav = new Navigator([
    wp(0, 0, [1]),
    wp(1, 5, [0, 2]),
    wp(2, 10, [1, 3]),
    wp(3, 15, [2]),
  ]);
  const path = nav.findPath(
    new THREE.Vector3(0, 0, 0),
    new THREE.Vector3(15, 0, 0),
    { clear: () => true },
  );
  assert(path.length <= 3, `expected smoothed path, got ${path.length} points`);
});
