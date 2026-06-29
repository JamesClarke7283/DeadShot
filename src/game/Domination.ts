// Domination: two teams fight over three capture points (A/B/C). Holding points
// ticks team score; first team to the score cap (or the leader at time) wins.
// The point-control + scoring logic lives in DominationObjective (Objectives.ts);
// this just declares the rules and asks the Match to run that objective.

import type { TeamId } from "../core/types.ts";
import type { ModeRules, ScoreboardApi, WinResult } from "./Mode.ts";

const TIME_LIMIT = 600;

export const DOMINATION: ModeRules = {
  id: "dom",
  name: "Domination",
  friendlyFire: false,
  scoreCap: 200,
  timeLimit: TIME_LIMIT,
  teams: ["blue", "red"],
  objective: "dom",

  assignTeam(index: number): TeamId {
    return index % 2 === 0 ? "blue" : "red";
  },

  // Win is decided by the objective (DominationObjective.isOver); never by kills.
  checkWin(_sb: ScoreboardApi, _elapsed: number): WinResult {
    return { over: false };
  },
};
