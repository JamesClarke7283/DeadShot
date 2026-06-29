import { assert, assertEquals } from "@std/assert";
import { Scene } from "../core/Scene.ts";
import { Match } from "./Match.ts";
import { TDM } from "./TDM.ts";

function liveMatch(): Match {
  const scene = new Scene();
  const match = new Match(scene, null, null, {
    mapId: "desert_town",
    mode: TDM,
    botCount: 6,
    difficulty: "regular",
    hasPlayer: false,
    respawnDelay: 4,
    warmup: 0,
  });
  match.build();
  match.update(1 / 20); // enter live
  return match;
}

Deno.test("UAV reveals enemy positions on the owner team's minimap", () => {
  const match = liveMatch();
  const owner = match.bots[0]; // blue
  match.activateStreak({ id: owner.id, team: owner.team }, "uav");
  // Step a bit so the UAV pings.
  for (let i = 0; i < 20; i++) match.update(1 / 20);
  const pings = match.activePings(owner.team);
  assert(pings.length > 0, "UAV should reveal enemies to the owner team");
  match.dispose();
});

Deno.test("Counter-UAV blocks the enemy minimap", () => {
  const match = liveMatch();
  const blue = match.bots.find((b) => b.team === "blue")!;
  const red = match.bots.find((b) => b.team === "red")!;
  match.activateStreak({ id: blue.id, team: "blue" }, "uav"); // blue sees red
  match.activateStreak({ id: red.id, team: "red" }, "counter_uav"); // jams blue
  for (let i = 0; i < 10; i++) match.update(1 / 20);
  assert(match.isCounterUAV("blue"), "blue minimap jammed");
  assertEquals(match.activePings("blue").length, 0, "no pings while jammed");
  match.dispose();
});

Deno.test("Nuke ends the match for the calling team", () => {
  const match = liveMatch();
  const owner = match.bots.find((b) => b.team === "red")!;
  match.activateStreak({ id: owner.id, team: "red" }, "nuke");
  // Nuke has a ~6s countdown.
  for (let i = 0; i < 200 && match.state !== "end"; i++) match.update(1 / 20);
  assertEquals(match.state, "end");
  assertEquals(match.winner, "red");
  match.dispose();
});
