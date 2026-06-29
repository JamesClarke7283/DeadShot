// Free-for-All rules: everyone fights everyone (friendly fire on, one shared
// "ffa" team). First to the kill cap wins; on the timer, the kill leader wins.

import type { TeamId } from "../core/types.ts";
import type { ModeRules, ScoreboardApi, WinResult } from "./Mode.ts";

const SCORE_CAP = 100;
const TIME_LIMIT = 600;

export const FFA: ModeRules = {
  id: "ffa",
  name: "Free-for-All",
  friendlyFire: true,
  scoreCap: SCORE_CAP,
  timeLimit: TIME_LIMIT,
  teams: ["ffa"],

  assignTeam(): TeamId {
    return "ffa";
  },

  checkWin(sb: ScoreboardApi, elapsed: number): WinResult {
    const top = sb.topPlayer();

    if (top && top.kills >= SCORE_CAP) {
      return { over: true, winner: top.id, reason: "score" };
    }

    if (elapsed >= TIME_LIMIT) {
      return { over: true, winner: top?.id, reason: "time" };
    }

    return { over: false };
  },
};
