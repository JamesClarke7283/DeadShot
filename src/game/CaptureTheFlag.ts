// Capture the Flag: grab the enemy flag and carry it back to your own (which
// must be home) to score; a dropped flag is returned by touching it. First team
// to the capture cap (or the leader at time) wins. Flag handling lives in
// CaptureTheFlagObjective (Objectives.ts); this just declares the rules.

import type { TeamId } from "../core/types.ts";
import type { ModeRules, ScoreboardApi, WinResult } from "./Mode.ts";

const TIME_LIMIT = 600;

export const CTF: ModeRules = {
  id: "ctf",
  name: "Capture the Flag",
  friendlyFire: false,
  scoreCap: 3,
  timeLimit: TIME_LIMIT,
  teams: ["blue", "red"],
  objective: "ctf",

  assignTeam(index: number): TeamId {
    return index % 2 === 0 ? "blue" : "red";
  },

  checkWin(_sb: ScoreboardApi, _elapsed: number): WinResult {
    return { over: false };
  },
};
