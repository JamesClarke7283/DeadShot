import { assert, assertEquals, assertGreater } from "@std/assert";
import {
  damageAtRange,
  getWeapon,
  shotInterval,
  WEAPON_IDS,
  WEAPONS,
  weaponsByCategory,
} from "./WeaponDefinition.ts";

const REQUIRED_CATEGORIES = [
  "assault",
  "smg",
  "lmg",
  "marksman",
  "sniper",
  "shotgun",
  "pistol",
  "launcher",
];

Deno.test("roster has all 18 weapons with unique ids", () => {
  assertEquals(WEAPONS.length, 18);
  const ids = new Set(WEAPON_IDS);
  assertEquals(ids.size, 18, "weapon ids must be unique");
});

Deno.test("every named weapon is present", () => {
  const expected = [
    "m4",
    "ak12",
    "scarl",
    "mp5",
    "p90",
    "uzi",
    "m249",
    "rpk",
    "mk14",
    "barrett",
    "kar98",
    "spas12",
    "ksg",
    "m9",
    "deagle",
    "rpg7",
  ];
  for (const id of expected) {
    const w = getWeapon(id);
    assert(w, `expected weapon ${id}`);
  }
});

Deno.test("each category is represented", () => {
  for (const cat of REQUIRED_CATEGORIES) {
    assertGreater(
      weaponsByCategory(cat as never).length,
      0,
      `category ${cat} must have at least one weapon`,
    );
  }
});

Deno.test("every weapon has valid required stats", () => {
  for (const w of WEAPONS) {
    assertGreater(w.fireRate, 0, `${w.id} fireRate`);
    assertGreater(w.magazine, 0, `${w.id} magazine`);
    assertGreater(w.reserve, -1, `${w.id} reserve`);
    assertGreater(w.reloadTime, 0, `${w.id} reloadTime`);
    assertGreater(w.adsTime, 0, `${w.id} adsTime`);
    assert(w.mobility > 0 && w.mobility <= 100, `${w.id} mobility in (0,100]`);
    assertGreater(w.headshotMultiplier, 0, `${w.id} headshotMultiplier`);
    assertGreater(w.bulletVelocity, 0, `${w.id} bulletVelocity`);
    assert(w.recoil, `${w.id} recoil profile`);
    assert(w.range, `${w.id} range falloff`);

    if (w.category === "launcher") {
      assert(w.rocket, `${w.id} launcher must have a rocket spec`);
      assertGreater(w.rocket!.splashRadius, 0, `${w.id} splashRadius`);
      assertGreater(w.rocket!.directDamage, 0, `${w.id} directDamage`);
    } else {
      // Non-launchers do bullet damage.
      assertGreater(w.damage, 0, `${w.id} damage`);
    }

    if (w.category === "shotgun") {
      assertGreater(w.pellets ?? 0, 1, `${w.id} shotgun pellets`);
    }
    if (w.fireMode === "burst") {
      assertGreater(w.burstCount ?? 0, 1, `${w.id} burstCount`);
    }
  }
});

Deno.test("range falloff is monotonic and clamps", () => {
  const w = getWeapon("m4");
  assertEquals(damageAtRange(w.range, w.damage, 0), w.damage);
  assertEquals(damageAtRange(w.range, w.damage, w.range.near), w.damage);
  assertEquals(damageAtRange(w.range, w.damage, 1000), w.range.minDamage);
  const mid = damageAtRange(w.range, w.damage, (w.range.near + w.range.far) / 2);
  assert(mid < w.damage && mid > w.range.minDamage, "midrange between bounds");
});

Deno.test("shotInterval derives from RPM", () => {
  assertEquals(shotInterval(600), 0.1);
});
