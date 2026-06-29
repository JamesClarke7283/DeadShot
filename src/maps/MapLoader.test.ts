import { assert } from "@std/assert";
import { mapFromJSON, type MapJSON } from "./MapLoader.ts";
import { getMap, MAPS, registerMap } from "./maps.ts";

const SAMPLE: MapJSON = {
  id: "test_arena",
  name: "Test Arena",
  terrain: { kind: "flat" },
  buildings: [{ x: 0, z: 0, width: 8, depth: 8, height: 4, doorWall: "south" }],
  obstacles: [{ type: "crate", x: 6, z: 6 }, { type: "container", x: -8, z: 4 }],
  trees: [{ x: 20, z: 20, type: "pine" }],
  spawns: [
    { x: -12, z: -12, team: "blue" },
    { x: 12, z: 12, team: "red" },
  ],
  bounds: { minX: -30, maxX: 30, minZ: -30, maxZ: 30 },
};

Deno.test("mapFromJSON builds a valid, well-formed map", () => {
  const def = mapFromJSON(SAMPLE);
  const b = def.build();
  assert(b.root.children.length > 0, "has geometry");
  assert(b.collision.boxes.length > 0, "has colliders");
  assert(b.spawns.some((s) => s.team === "blue"));
  assert(b.spawns.some((s) => s.team === "red"));
  assert(b.waypoints.length > 5, "has a nav graph");
  assert(Number.isFinite(b.groundAt(0, 0)));
});

Deno.test("registerMap adds a loaded map to the registry", () => {
  const before = MAPS.length;
  registerMap(mapFromJSON({ ...SAMPLE, id: "registered_test" }));
  assert(MAPS.length === before + 1);
  assert(getMap("registered_test").name === "Test Arena");
  // Re-registering the same id replaces, not duplicates.
  registerMap(mapFromJSON({ ...SAMPLE, id: "registered_test", name: "Renamed" }));
  assert(MAPS.length === before + 1);
  assert(getMap("registered_test").name === "Renamed");
});

Deno.test("missing spawns get sensible defaults", () => {
  const def = mapFromJSON({ id: "no_spawns", name: "No Spawns", terrain: { kind: "flat" } });
  const b = def.build();
  assert(b.spawns.some((s) => s.team === "blue"));
  assert(b.spawns.some((s) => s.team === "red"));
});
