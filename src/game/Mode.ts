// Shared match contracts: scoreboard API, score values, and game-mode rules.
// Scoreboard.ts implements ScoreboardApi; TDM.ts / FFA.ts implement ModeRules;
// Match.ts consumes all of them.

import type { TeamId } from "../core/types.ts";

export type ModeId = "tdm" | "ffa";

/** Score-per-action (streaks are scored separately by the streak manager). */
export const SCORE = {
  kill: 100,
  headshotBonus: 25,
  assist: 50,
} as const;

export interface PlayerScore {
  id: number;
  name: string;
  team: TeamId;
  kills: number;
  deaths: number;
  assists: number;
  score: number;
  isPlayer: boolean;
}

export interface WinResult {
  over: boolean;
  /** Winning team (TDM) or winning player id (FFA); undefined on a draw. */
  winner?: TeamId | number;
  reason?: "score" | "time";
}

export interface ScoreboardApi {
  register(id: number, name: string, team: TeamId, isPlayer?: boolean): void;
  /** Credit a kill (+100, +25 headshot) and a death. killerId undefined = suicide/world. */
  recordKill(killerId: number | undefined, victimId: number, headshot: boolean): void;
  recordAssist(id: number): void;
  /** Add raw score (streaks, objectives). */
  addScore(id: number, amount: number): void;
  get(id: number): PlayerScore;
  all(): PlayerScore[];
  /** Total score for a team. */
  teamScore(team: TeamId): number;
  /** Total kills for a team (TDM win condition). */
  teamKills(team: TeamId): number;
  /** Highest single-player kill count + that player's id (FFA win). */
  topPlayer(): { id: number; kills: number } | null;
  format(): string;
}

export interface ModeRules {
  id: ModeId;
  name: string;
  friendlyFire: boolean;
  /** Kills to win (team total for TDM, single player for FFA). */
  scoreCap: number;
  /** Time limit in seconds. */
  timeLimit: number;
  /** Teams this mode uses (FFA => ["ffa"]). */
  teams: TeamId[];
  /** Assign a team to combatant slot `index` of `total`. */
  assignTeam(index: number, total: number): TeamId;
  /** Decide whether the match is over given the scoreboard + elapsed seconds. */
  checkWin(sb: ScoreboardApi, elapsed: number): WinResult;
}
