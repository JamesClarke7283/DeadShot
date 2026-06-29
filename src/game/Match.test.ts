import { assert } from "@std/assert";
import { Scene } from "../core/Scene.ts";
import { Match } from "./Match.ts";
import { TDM } from "./TDM.ts";
import { FFA } from "./FFA.ts";
import type { ModeRules } from "./Mode.ts";
import type { ScoreboardApi } from "./Mode.ts";

// A reduced-cap clone of a mode so the all-bot run reaches a winner quickly while
// exercising the exact same Match win/score/respawn path as the real 100-kill cap.
function fastMode(base: ModeRules, cap: number): ModeRules {
  return {
    ...base,
    scoreCap: cap,
    checkWin(sb: ScoreboardApi, elapsed: number) {
      if (base.id === "tdm") {
        const b = sb.teamKills("blue");
        const r = sb.teamKills("red");
        if (b >= cap || r >= cap) {
          return { over: true, winner: b >= r ? "blue" : "red", reason: "score" };
        }
      } else {
        const top = sb.topPlayer();
        if (top && top.kills >= cap) return { over: true, winner: top.id, reason: "score" };
      }
      if (elapsed >= base.timeLimit) return { over: true, reason: "time" };
      return { over: false };
    },
  };
}

Deno.test("all-bot TDM runs to a winner and prints a scoreboard", () => {
  const scene = new Scene();
  const match = new Match(scene, null, null, {
    mapId: "desert_town",
    mode: fastMode(TDM, 8),
    botCount: 8,
    difficulty: "veteran",
    hasPlayer: false,
    respawnDelay: 2,
    warmup: 0,
  });
  match.build();
  assert(match.bots.length === 8);

  const dt = 1 / 20;
  let frames = 0;
  while (match.state !== "end" && frames < 8000) {
    match.update(dt);
    frames++;
  }
  assert(match.state === "end", `match did not end (frames=${frames})`);
  assert(match.winner !== undefined, "a winner was decided");
  const total = match.scoreboard.all().reduce((s, p) => s + p.kills, 0);
  assert(total >= 8, `expected >=8 kills, got ${total}`);
  assert(match.scoreboard.format().length > 0);
  assert(match.killfeed.length > 0, "killfeed populated");
  match.dispose();
});

Deno.test("FFA all-bot match produces a single winner", () => {
  const scene = new Scene();
  const match = new Match(scene, null, null, {
    mapId: "urban_docks",
    mode: fastMode(FFA, 5),
    botCount: 8,
    difficulty: "veteran",
    hasPlayer: false,
    respawnDelay: 2,
    warmup: 0,
  });
  match.build();
  const dt = 1 / 20;
  let frames = 0;
  while (match.state !== "end" && frames < 8000) {
    match.update(dt);
    frames++;
  }
  assert(match.state === "end", `FFA did not end (frames=${frames})`);
  assert(typeof match.winner === "number", "FFA winner is a single player id");
  match.dispose();
});

Deno.test("a killed bot respawns after the delay", () => {
  const scene = new Scene();
  const match = new Match(scene, null, null, {
    mapId: "desert_town",
    mode: TDM,
    botCount: 4,
    difficulty: "recruit",
    hasPlayer: false,
    respawnDelay: 3,
    warmup: 0,
  });
  match.build();
  match.update(1 / 20); // enter live
  const victim = match.bots[0];
  victim.applyDamage({
    amount: 999,
    headshot: false,
    sourceTeam: "red",
    sourceId: match.bots[1].id,
  });
  assert(!victim.alive);
  // Advance past the respawn delay.
  for (let i = 0; i < 80; i++) match.update(0.1);
  assert(victim.alive, "bot should have respawned");
  match.dispose();
});
