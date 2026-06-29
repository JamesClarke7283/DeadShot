import { assert, assertGreater } from "@std/assert";
import { MAPS } from "./maps.ts";

Deno.test("every map builds without error and is well-formed", () => {
  for (const def of MAPS) {
    const b = def.build();
    assert(b.root.children.length > 0, `${def.id} has geometry`);
    assertGreater(b.waypoints.length, 10, `${def.id} has a nav graph`);
    assert(b.spawns.some((s) => s.team === "blue"), `${def.id} has blue spawns`);
    assert(b.spawns.some((s) => s.team === "red"), `${def.id} has red spawns`);
    assert(b.collision.boxes.length > 0, `${def.id} has colliders`);
    assert(Number.isFinite(b.groundAt(0, 0)), `${def.id} groundAt finite`);
    assert(b.environment.background !== undefined, `${def.id} environment set`);
  }
});

Deno.test("waypoint neighbors are bidirectional and in-range", () => {
  for (const def of MAPS) {
    const b = def.build();
    const ids = new Set(b.waypoints.map((w) => w.id));
    for (const w of b.waypoints) {
      for (const n of w.neighbors) {
        assert(ids.has(n), `${def.id} waypoint ${w.id} -> unknown ${n}`);
      }
    }
  }
});
