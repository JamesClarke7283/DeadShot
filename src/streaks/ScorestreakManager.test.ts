import { assert, assertEquals } from "@std/assert";
import { ScorestreakManager } from "./ScorestreakManager.ts";
import type { StreakDef } from "./Streak.ts";

// Lightweight defs (no real Streak instances needed for the manager logic).
const DEFS: StreakDef[] = [
  { id: "uav", name: "UAV", cost: 500, create: () => ({} as never) },
  { id: "care_package", name: "Care Package", cost: 700, create: () => ({} as never) },
  { id: "attack_heli", name: "Attack Helicopter", cost: 1200, create: () => ({} as never) },
];

Deno.test("a player reaching 500 score unlocks the UAV slot", () => {
  const m = new ScorestreakManager(DEFS);
  m.setLoadout(7, ["uav", "care_package", "attack_heli"]);
  assert(!m.isAvailable(7, "uav"));
  m.addScore(7, 100); // 1 kill-ish
  m.addScore(7, 400); // total 500
  assertEquals(m.scoreOf(7), 500);
  assert(m.isAvailable(7, "uav"), "UAV unlocked at 500");
  assert(!m.isAvailable(7, "care_package"), "care package still locked");
});

Deno.test("active streaks are not re-offered until they end", () => {
  const m = new ScorestreakManager(DEFS);
  m.setLoadout(1, ["uav"]);
  m.addScore(1, 500);
  assert(m.isAvailable(1, "uav"));
  m.markActive(1, "uav");
  assert(!m.isAvailable(1, "uav"), "UAV in progress not re-offered");
  m.markEnded(1, "uav");
  assert(m.isAvailable(1, "uav"), "UAV offered again after it ends");
});

Deno.test("bestAvailable picks the most expensive affordable streak", () => {
  const m = new ScorestreakManager(DEFS);
  m.setLoadout(2, ["uav", "care_package", "attack_heli"]);
  m.addScore(2, 800);
  assertEquals(m.bestAvailable(2)?.id, "care_package"); // 700 affordable, 1200 not
  m.addScore(2, 500); // 1300
  assertEquals(m.bestAvailable(2)?.id, "attack_heli");
});

Deno.test("score accumulates and does not reset on its own", () => {
  const m = new ScorestreakManager(DEFS);
  m.addScore(3, 100);
  m.addScore(3, 100);
  assertEquals(m.scoreOf(3), 200);
  m.reset(3);
  assertEquals(m.scoreOf(3), 0);
});

Deno.test("loadout falls back to the default when unset", () => {
  const m = new ScorestreakManager(DEFS);
  assertEquals(m.loadout(99).length > 0, true);
});
