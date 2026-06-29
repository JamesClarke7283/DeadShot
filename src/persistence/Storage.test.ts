import { assert, assertEquals } from "@std/assert";
import { CLASS_SLOTS, defaultClass, migrate, SCHEMA_VERSION, Storage } from "./Storage.ts";

class MemoryStore {
  m = new Map<string, string>();
  getItem(k: string) {
    return this.m.has(k) ? this.m.get(k)! : null;
  }
  setItem(k: string, v: string) {
    this.m.set(k, v);
  }
  removeItem(k: string) {
    this.m.delete(k);
  }
}

Deno.test("fresh storage has 10 default classes + settings", () => {
  const s = new Storage(new MemoryStore());
  assertEquals(s.getClasses().length, CLASS_SLOTS);
  assert(s.getSettings().sensitivity > 0);
  assertEquals(s.getMatchConfig().mode, "tdm");
});

Deno.test("a class round-trips through save/load", () => {
  const backend = new MemoryStore();
  const s = new Storage(backend);
  const custom = defaultClass(0);
  custom.name = "Sniper Elite";
  custom.primary = { weaponId: "barrett", attachments: ["acog", "suppressor"] };
  custom.streaks = ["uav", "predator", "nuke"];
  s.setClass(3, custom);

  // New Storage over the same backend reads it back.
  const s2 = new Storage(backend);
  const loaded = s2.getClass(3);
  assertEquals(loaded.name, "Sniper Elite");
  assertEquals(loaded.primary.weaponId, "barrett");
  assertEquals(loaded.primary.attachments, ["acog", "suppressor"]);
  assertEquals(loaded.streaks, ["uav", "predator", "nuke"]);
});

Deno.test("settings + match config persist", () => {
  const backend = new MemoryStore();
  const s = new Storage(backend);
  s.updateSettings({ sensitivity: 2.5, fov: 95 });
  s.setMatchConfig({
    mapId: "urban_docks",
    mode: "ffa",
    botCount: 11,
    difficulty: "veteran",
    hardcore: true,
  });
  const s2 = new Storage(backend);
  assertEquals(s2.getSettings().sensitivity, 2.5);
  assertEquals(s2.getSettings().fov, 95);
  assertEquals(s2.getMatchConfig().mapId, "urban_docks");
  assertEquals(s2.getMatchConfig().botCount, 11);
});

Deno.test("migration fills missing fields from an older/partial save", () => {
  const backend = new MemoryStore();
  // Simulate a v0 save missing settings + most classes.
  backend.setItem(
    "deadshot.save",
    JSON.stringify({ classes: [{ name: "Old Class" }] }),
  );
  const s = new Storage(backend);
  assertEquals(s.getClasses().length, CLASS_SLOTS, "padded to full slot count");
  assertEquals(s.getClass(0).name, "Old Class", "kept the old name");
  assert(s.getClass(0).primary.weaponId, "filled missing primary");
  assert(s.getSettings().fov > 0, "filled missing settings");
});

Deno.test("migrate stamps the current schema version", () => {
  const out = migrate({ version: 0 } as never);
  assertEquals(out.version, SCHEMA_VERSION);
});
