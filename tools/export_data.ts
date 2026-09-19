// Run: deno run -A --config ../DeadShot/deno.json tools/export_data.ts
// Source tables remain the migration's authoritative balance definitions.
import { WEAPONS } from "../../DeadShot/src/weapons/WeaponDefinition.ts";
import { ATTACHMENTS, CAMO_PALETTE, computeWeaponStats } from "../../DeadShot/src/weapons/AttachmentDefinitions.ts";
import { PERKS } from "../../DeadShot/src/game/Perks.ts";
import { STREAKS } from "../../DeadShot/src/streaks/streaks.ts";
import { GUN_GAME_TIERS } from "../../DeadShot/src/game/GunGame.ts";
import { defaultSave } from "../../DeadShot/src/persistence/Storage.ts";
import { TDM } from "../../DeadShot/src/game/TDM.ts";
import { FFA } from "../../DeadShot/src/game/FFA.ts";
import { DOMINATION } from "../../DeadShot/src/game/Domination.ts";
import { CTF } from "../../DeadShot/src/game/CaptureTheFlag.ts";
import { GUNGAME } from "../../DeadShot/src/game/GunGame.ts";
const out = new URL("../data/", import.meta.url);
await Deno.mkdir(out, { recursive: true });
const equipment = [
  ["flashbang", "Flashbang", "tactical"], ["smoke", "Smoke", "tactical"],
  ["stun", "Stun", "tactical"], ["snapshot", "Snapshot", "tactical"],
  ["frag", "Frag", "lethal"], ["semtex", "Semtex", "lethal"],
  ["knife", "Throwing Knife", "lethal"], ["c4", "C4", "lethal"],
  ["molotov", "Molotov", "lethal"], ["thermite", "Thermite", "lethal"],
  ["claymore", "Claymore", "lethal"],
].map(([id,name,category]) => ({id,name,category}));
const tables: Record<string, unknown> = {
  weapons: WEAPONS, attachments: ATTACHMENTS, camos: CAMO_PALETTE, perks: PERKS,
  streaks: STREAKS, equipment, default_save: defaultSave(),
  modes: [TDM, FFA, DOMINATION, CTF, GUNGAME], gun_game_tiers: GUN_GAME_TIERS,
  stat_fixtures: WEAPONS.flatMap(w => [[], ["reddot", "compensator"]].map(a => ({
    weapon: w.id, attachments: a, expected: computeWeaponStats(w, a),
  }))),
};
for (const [name, value] of Object.entries(tables)) {
  await Deno.writeTextFile(new URL(`${name}.json`, out), JSON.stringify(value, null, 2) + "\n");
  console.log(name);
}
