import { assert, assertAlmostEquals, assertEquals } from "@std/assert";
import { type ActorSnap, ReplayRecorder, sampleAt } from "./ReplayRecorder.ts";

function snap(id: number, x: number, yaw = 0): ActorSnap {
  return {
    id,
    team: "blue",
    name: `P${id}`,
    isPlayer: id === 0,
    x,
    y: 0,
    z: 0,
    yaw,
    alive: true,
    anim: "run",
    weaponId: "m4",
  };
}

Deno.test("record throttles to the configured rate", () => {
  const r = new ReplayRecorder(10, 30); // 30 Hz => >= 1/30s between frames
  r.record(0, [snap(0, 0)]);
  r.record(0.01, [snap(0, 1)]); // too soon, ignored
  r.record(0.05, [snap(0, 2)]); // ok
  assertEquals(r.window(0, 1).length, 2);
});

Deno.test("frames older than the duration are pruned", () => {
  const r = new ReplayRecorder(1, 60); // keep ~1s
  for (let i = 0; i <= 60; i++) r.record(i / 30, [snap(0, i)]);
  const all = r.window(-100, 100);
  // newest is at t=2.0; nothing older than t=1.0 survives.
  assert(all.length > 0);
  assert(all[0].t >= 1.0 - 1e-9, `oldest kept frame ${all[0].t} should be >= 1.0`);
});

Deno.test("window returns an independent copy", () => {
  const r = new ReplayRecorder(10, 30);
  r.record(0, [snap(0, 5)]);
  const w = r.window(0, 1);
  w[0].actors[0].x = 999;
  assertEquals(r.window(0, 1)[0].actors[0].x, 5, "mutation must not leak back into the recorder");
});

Deno.test("sampleAt interpolates position + angle between frames", () => {
  const frames = [
    { t: 0, actors: [snap(0, 0, 0)] },
    { t: 1, actors: [snap(0, 10, Math.PI / 2)] },
  ];
  const mid = sampleAt(frames, 0.5).get(0)!;
  assertAlmostEquals(mid.x, 5, 1e-6);
  assertAlmostEquals(mid.yaw, Math.PI / 4, 1e-6);
  // Clamps outside the range.
  assertEquals(sampleAt(frames, -5).get(0)!.x, 0);
  assertEquals(sampleAt(frames, 5).get(0)!.x, 10);
});

Deno.test("sampleAt wraps angle the short way", () => {
  const frames = [
    { t: 0, actors: [snap(0, 0, -Math.PI + 0.1)] },
    { t: 1, actors: [snap(0, 0, Math.PI - 0.1)] },
  ];
  // Halfway should be near ±PI (wrapping), not 0.
  const mid = sampleAt(frames, 0.5).get(0)!;
  assert(Math.abs(Math.abs(mid.yaw) - Math.PI) < 0.2, `expected near ±PI, got ${mid.yaw}`);
});
