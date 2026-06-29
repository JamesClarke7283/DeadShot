// Team Deathmatch rules: two teams (blue/red) race to a kill cap; whoever has
// more kills when the timer runs out wins, ties draw.

import type { TeamId } from "../core/types.ts";
import type { ModeRules, ScoreboardApi, WinResult } from "./Mode.ts";

const SCORE_CAP = 100;
const TIME_LIMIT = 600;

export const TDM: ModeRules = {
  id: "tdm",
  name: "Team Deathmatch",
  friendlyFire: false,
  scoreCap: SCORE_CAP,
  timeLimit: TIME_LIMIT,
  teams: ["blue", "red"],

  assignTeam(index: number): TeamId {
    return index % 2 === 0 ? "blue" : "red";
  },

  checkWin(sb: ScoreboardApi, elapsed: number): WinResult {
    const blue = sb.teamKills("blue");
    const red = sb.teamKills("red");

    if (blue >= SCORE_CAP || red >= SCORE_CAP) {
      return {
        over: true,
        winner: blue >= red ? "blue" : "red",
        reason: "score",
      };
    }

    if (elapsed >= TIME_LIMIT) {
      let winner: TeamId | undefined;
      if (blue > red) winner = "blue";
      else if (red > blue) winner = "red";
      return { over: true, winner, reason: "time" };
    }

    return { over: false };
  },
};
