import { assert, assertAlmostEquals, assertEquals } from "@std/assert";
import { getWeapon } from "./WeaponDefinition.ts";
import {
  ATTACHMENTS,
  attachmentsForSlot,
  CAMO_PALETTE,
  computeWeaponStats,
  getAttachment,
} from "./AttachmentDefinitions.ts";

Deno.test("every slot has at least one attachment", () => {
  const slots = ["optic", "barrel", "magazine", "stock", "grip", "perk", "fieldUpgrade"] as const;
  for (const s of slots) {
    assert(attachmentsForSlot(s).length > 0, `slot ${s} empty`);
  }
});

Deno.test("attachment ids are unique", () => {
  const ids = new Set(ATTACHMENTS.map((a) => a.id));
  assertEquals(ids.size, ATTACHMENTS.length);
});

Deno.test("fully-kitted class produces deterministic final stats", () => {
  const m4 = getWeapon("m4");
  const kit = ["reddot", "compensator", "extmag", "angledgrip"];

  const a = computeWeaponStats(m4, kit);
  const b = computeWeaponStats(m4, kit);
  assertEquals(a, b, "same inputs must produce identical output");

  // Known expected deltas:
  // magazine 30 + 15 = 45
  assertEquals(a.magazine, 45);
  // mobility 80 - 5 (extmag) = 75
  assertEquals(a.mobility, 75);
  // reloadTime 2.1 * 1.1 (extmag) = 2.31
  assertAlmostEquals(a.reloadTime, 2.31, 1e-9);
  // recoil.vertical 1.1 * 0.8 (compensator) = 0.88
  assertAlmostEquals(a.recoil.vertical, 0.88, 1e-9);
  // range.near 32 * 0.9 = 28.8 ; far 62 * 0.9 = 55.8
  assertAlmostEquals(a.range.near, 28.8, 1e-9);
  assertAlmostEquals(a.range.far, 55.8, 1e-9);
  // adsTime 0.25 * 0.95 (reddot) * 0.85 (angledgrip) = 0.201875
  assertAlmostEquals(a.adsTime, 0.201875, 1e-9);
});

Deno.test("computeWeaponStats does not mutate the base def", () => {
  const m4 = getWeapon("m4");
  const beforeMag = m4.magazine;
  const beforeNear = m4.range.near;
  computeWeaponStats(m4, ["extmag", "compensator"]);
  assertEquals(m4.magazine, beforeMag);
  assertEquals(m4.range.near, beforeNear);
});

Deno.test("effect tags accumulate from perks/field upgrades", () => {
  const m4 = getWeapon("m4");
  const stats = computeWeaponStats(m4, ["suppressor", "sleightofhand", "deadsilence"]);
  assert(stats.effects.includes("silenced"));
  assert(stats.effects.includes("sleight_of_hand"));
  assert(stats.effects.includes("dead_silence"));
});

Deno.test("launcher keeps its rocket spec through compute", () => {
  const rpg = getWeapon("rpg7");
  const stats = computeWeaponStats(rpg, []);
  assert(stats.rocket, "rocket spec preserved");
  assertEquals(stats.rocket!.splashRadius, rpg.rocket!.splashRadius);
});

Deno.test("camo palette is non-empty and lookups fall back", () => {
  assert(CAMO_PALETTE.length >= 8);
  assertEquals(getAttachment("reddot").slot, "optic");
});
