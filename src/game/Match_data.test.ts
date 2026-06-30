import { assert, assertEquals } from "@std/assert";
import * as THREE from "../three.ts";
import { Scoreboard } from "./Scoreboard.ts";
import { Spawner } from "./Spawner.ts";
import { TDM } from "./TDM.ts";
import { FFA } from "./FFA.ts";
import { SCORE } from "./Mode.ts";
import type { SpawnPoint } from "../maps/MapDefinition.ts";
import type { TeamId } from "../core/types.ts";

function spawn(x: number, z: number, team: TeamId): SpawnPoint {
  return { position: new THREE.Vector3(x, 0, z), yaw: 0, team };
}

// --- Scoreboard ---

Deno.test("Scoreboard: a kill credits killer score+kill and victim a death", () => {
  const sb = new Scoreboard();
  sb.register(1, "Killer", "blue");
  sb.register(2, "Victim", "red");

  sb.recordKill(1, 2, false);
  assertEquals(sb.get(1).kills, 1);
  assertEquals(sb.get(1).score, SCORE.kill);
  assertEquals(sb.get(2).deaths, 1);
});

Deno.test("Scoreboard: headshot adds the bonus on top of the kill", () => {
  const sb = new Scoreboard();
  sb.register(1, "Killer", "blue");
  sb.register(2, "Victim", "red");

  sb.recordKill(1, 2, true);
  assertEquals(sb.get(1).score, SCORE.kill + SCORE.headshotBonus);
});

Deno.test("Scoreboard: assist adds +50 and an assist", () => {
  const sb = new Scoreboard();
  sb.register(1, "Helper", "blue");

  sb.recordAssist(1);
  assertEquals(sb.get(1).assists, 1);
  assertEquals(sb.get(1).score, SCORE.assist);
});

Deno.test("Scoreboard: suicide adds a death without crediting a killer", () => {
  const sb = new Scoreboard();
  sb.register(1, "Solo", "ffa");

  sb.addScore(1, 250);
  sb.recordKill(1, 1, false);
  assertEquals(sb.get(1).deaths, 1);
  assertEquals(sb.get(1).kills, 0);
  // Self-kill penalizes by SCORE.kill (250 - 100).
  assertEquals(sb.get(1).score, 150);
});

Deno.test("Scoreboard: world kill (no killer) only adds a death", () => {
  const sb = new Scoreboard();
  sb.register(1, "Solo", "ffa");

  sb.recordKill(undefined, 1, false);
  assertEquals(sb.get(1).deaths, 1);
  assertEquals(sb.get(1).score, 0);
});

Deno.test("Scoreboard: suicide score never goes below zero", () => {
  const sb = new Scoreboard();
  sb.register(1, "Solo", "ffa");

  sb.recordKill(1, 1, false);
  assertEquals(sb.get(1).score, 0);
});

Deno.test("Scoreboard: team aggregates sum kills and score", () => {
  const sb = new Scoreboard();
  sb.register(1, "B1", "blue");
  sb.register(2, "B2", "blue");
  sb.register(3, "R1", "red");

  sb.recordKill(1, 3, false);
  sb.recordKill(2, 3, true);
  sb.recordKill(3, 1, false);

  assertEquals(sb.teamKills("blue"), 2);
  assertEquals(sb.teamKills("red"), 1);
  assertEquals(sb.teamScore("blue"), SCORE.kill * 2 + SCORE.headshotBonus);
  assertEquals(sb.teamScore("red"), SCORE.kill);
});

Deno.test("Scoreboard: topPlayer picks the kill leader", () => {
  const sb = new Scoreboard();
  sb.register(1, "A", "ffa");
  sb.register(2, "B", "ffa");
  sb.register(3, "C", "ffa");

  sb.recordKill(2, 1, false);
  sb.recordKill(2, 3, false);
  sb.recordKill(1, 3, false);

  const top = sb.topPlayer();
  assert(top !== null);
  assertEquals(top.id, 2);
  assertEquals(top.kills, 2);
});

Deno.test("Scoreboard: topPlayer is null when empty", () => {
  const sb = new Scoreboard();
  assertEquals(sb.topPlayer(), null);
});

Deno.test("Scoreboard: all() is sorted by score descending", () => {
  const sb = new Scoreboard();
  sb.register(1, "Low", "ffa");
  sb.register(2, "High", "ffa");
  sb.addScore(1, 50);
  sb.addScore(2, 300);

  const order = sb.all().map((p) => p.id);
  assertEquals(order, [2, 1]);
});

Deno.test("Scoreboard: get() throws on unknown id", () => {
  const sb = new Scoreboard();
  let threw = false;
  try {
    sb.get(99);
  } catch {
    threw = true;
  }
  assert(threw);
});

Deno.test("Scoreboard: register is idempotent and updates name/team", () => {
  const sb = new Scoreboard();
  sb.register(1, "Old", "blue");
  sb.addScore(1, 100);
  sb.register(1, "New", "red");

  assertEquals(sb.get(1).name, "New");
  assertEquals(sb.get(1).team, "red");
  assertEquals(sb.get(1).score, 100, "re-register keeps existing score");
});

Deno.test("Scoreboard: format() returns a non-empty string with player names", () => {
  const sb = new Scoreboard();
  sb.register(1, "Alpha", "blue");
  sb.register(2, "Bravo", "red");
  sb.recordKill(1, 2, false);

  const out = sb.format();
  assert(out.length > 0);
  assert(out.includes("Alpha"));
  assert(out.includes("Bravo"));
});

// --- Spawner ---

Deno.test("Spawner: avoids spawns near clustered enemies", () => {
  const spawns = [
    spawn(0, 0, "blue"),
    spawn(100, 0, "blue"),
    spawn(200, 0, "blue"),
  ];
  const spawner = new Spawner(spawns);
  const enemies = [new THREE.Vector3(0, 0, 0), new THREE.Vector3(2, 0, 1)];

  const picked = spawner.pick("blue", enemies);
  // The spawn at (0,0) is right on the enemy cluster, so it should be avoided.
  assert(picked.position.x !== 0, "should not pick the spawn on the cluster");
});

Deno.test("Spawner: always returns a valid SpawnPoint", () => {
  const spawns = [spawn(0, 0, "red"), spawn(10, 0, "red")];
  const spawner = new Spawner(spawns);

  for (let i = 0; i < 5; i++) {
    const p = spawner.pick("red", [new THREE.Vector3(0, 0, 0)]);
    assert(p !== undefined);
    assert(spawns.includes(p));
  }
});

Deno.test("Spawner: falls back to all spawns when team has none", () => {
  const spawns = [spawn(0, 0, "blue"), spawn(10, 0, "blue")];
  const spawner = new Spawner(spawns);

  const p = spawner.pick("red", []);
  assert(spawns.includes(p));
});

Deno.test("Spawner: spreads consecutive picks across team spawns", () => {
  const spawns = [spawn(0, 0, "blue"), spawn(40, 0, "blue"), spawn(80, 0, "blue")];
  // rng -> 0 always takes the first eligible; ally-spread should still move the
  // pick off the previous pad rather than stacking the team on one spot.
  const spawner = new Spawner(spawns, () => 0);
  const a = spawner.pick("blue", []);
  const b = spawner.pick("blue", []);
  assert(a.position.x !== b.position.x, "consecutive spawns should differ");

  spawner.reset();
  const afterReset = spawner.pick("blue", []);
  assertEquals(afterReset.position.x, a.position.x);
});

Deno.test("Spawner: randomises among the safe spawns", () => {
  // Three near-identical, equally-safe spawns far from the lone enemy: which one
  // is chosen should depend on the RNG, not always be the same pad.
  const spawns = [spawn(0, 100, "blue"), spawn(2, 100, "blue"), spawn(4, 100, "blue")];
  const enemy = [new THREE.Vector3(0, 0, 0)];
  const low = new Spawner(spawns, () => 0).pick("blue", enemy);
  const high = new Spawner(spawns, () => 0.99).pick("blue", enemy);
  assert(low.position.x !== high.position.x, "RNG should change which safe spawn is picked");
});

// --- TDM ---

Deno.test("TDM: assignTeam alternates blue/red by index parity", () => {
  assertEquals(TDM.assignTeam(0, 4), "blue");
  assertEquals(TDM.assignTeam(1, 4), "red");
  assertEquals(TDM.assignTeam(2, 4), "blue");
  assertEquals(TDM.assignTeam(3, 4), "red");
});

Deno.test("TDM: reaching the kill cap ends the match for that team", () => {
  const sb = new Scoreboard();
  sb.register(1, "B", "blue");
  sb.register(2, "R", "red");
  for (let i = 0; i < 100; i++) sb.recordKill(1, 2, false);

  const res = TDM.checkWin(sb, 10);
  assert(res.over);
  assertEquals(res.winner, "blue");
  assertEquals(res.reason, "score");
});

Deno.test("TDM: time limit ends with the higher-kill team", () => {
  const sb = new Scoreboard();
  sb.register(1, "B", "blue");
  sb.register(2, "R", "red");
  sb.recordKill(2, 1, false);
  sb.recordKill(2, 1, false);
  sb.recordKill(1, 2, false);

  const res = TDM.checkWin(sb, 600);
  assert(res.over);
  assertEquals(res.winner, "red");
  assertEquals(res.reason, "time");
});

Deno.test("TDM: time limit with equal kills is a draw", () => {
  const sb = new Scoreboard();
  sb.register(1, "B", "blue");
  sb.register(2, "R", "red");
  sb.recordKill(1, 2, false);
  sb.recordKill(2, 1, false);

  const res = TDM.checkWin(sb, 600);
  assert(res.over);
  assertEquals(res.winner, undefined);
  assertEquals(res.reason, "time");
});

Deno.test("TDM: not over before cap or time", () => {
  const sb = new Scoreboard();
  sb.register(1, "B", "blue");
  sb.register(2, "R", "red");
  sb.recordKill(1, 2, false);

  const res = TDM.checkWin(sb, 10);
  assertEquals(res.over, false);
});

// --- FFA ---

Deno.test("FFA: assignTeam is always ffa", () => {
  assertEquals(FFA.assignTeam(0, 8), "ffa");
  assertEquals(FFA.assignTeam(5, 8), "ffa");
});

Deno.test("FFA: a player reaching the kill cap wins", () => {
  const sb = new Scoreboard();
  sb.register(1, "Ace", "ffa");
  sb.register(2, "Food", "ffa");
  for (let i = 0; i < 100; i++) sb.recordKill(1, 2, false);

  const res = FFA.checkWin(sb, 10);
  assert(res.over);
  assertEquals(res.winner, 1);
  assertEquals(res.reason, "score");
});

Deno.test("FFA: time limit ends with the kill leader", () => {
  const sb = new Scoreboard();
  sb.register(1, "A", "ffa");
  sb.register(2, "B", "ffa");
  sb.recordKill(2, 1, false);

  const res = FFA.checkWin(sb, 600);
  assert(res.over);
  assertEquals(res.winner, 2);
  assertEquals(res.reason, "time");
});

Deno.test("FFA: not over before cap or time", () => {
  const sb = new Scoreboard();
  sb.register(1, "A", "ffa");
  sb.register(2, "B", "ffa");
  sb.recordKill(1, 2, false);

  const res = FFA.checkWin(sb, 10);
  assertEquals(res.over, false);
});
