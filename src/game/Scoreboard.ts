// Tracks per-player kills/deaths/assists/score and team aggregates. Match.ts
// feeds it kills/assists; it answers win-condition queries and prints the
// final scoreboard.

import type { TeamId } from "../core/types.ts";
import { type PlayerScore, SCORE, type ScoreboardApi } from "./Mode.ts";
import { TEAM_NAMES } from "./Team.ts";

export class Scoreboard implements ScoreboardApi {
  private readonly players = new Map<number, PlayerScore>();

  register(id: number, name: string, team: TeamId, isPlayer = false): void {
    const existing = this.players.get(id);
    if (existing) {
      existing.name = name;
      existing.team = team;
      existing.isPlayer = isPlayer;
      return;
    }
    this.players.set(id, {
      id,
      name,
      team,
      kills: 0,
      deaths: 0,
      assists: 0,
      score: 0,
      isPlayer,
    });
  }

  recordKill(
    killerId: number | undefined,
    victimId: number,
    headshot: boolean,
  ): void {
    const victim = this.get(victimId);
    victim.deaths++;

    // Suicide / world kill: no killer credited.
    if (killerId === undefined || killerId === victimId) {
      // Self-kill (not world) penalizes the player's score, never below 0.
      if (killerId === victimId) {
        victim.score = Math.max(0, victim.score - SCORE.kill);
      }
      return;
    }

    const killer = this.get(killerId);
    killer.kills++;
    killer.score += SCORE.kill + (headshot ? SCORE.headshotBonus : 0);
  }

  recordAssist(id: number): void {
    const p = this.get(id);
    p.assists++;
    p.score += SCORE.assist;
  }

  addScore(id: number, amount: number): void {
    this.get(id).score += amount;
  }

  get(id: number): PlayerScore {
    const p = this.players.get(id);
    if (!p) throw new Error(`Scoreboard: unknown player id ${id}`);
    return p;
  }

  all(): PlayerScore[] {
    // Stable sort by score descending (insertion order preserved on ties).
    return [...this.players.values()]
      .map((p, i) => ({ p, i }))
      .sort((a, b) => (b.p.score - a.p.score) || (a.i - b.i))
      .map((e) => e.p);
  }

  teamScore(team: TeamId): number {
    let total = 0;
    for (const p of this.players.values()) {
      if (p.team === team) total += p.score;
    }
    return total;
  }

  teamKills(team: TeamId): number {
    let total = 0;
    for (const p of this.players.values()) {
      if (p.team === team) total += p.kills;
    }
    return total;
  }

  topPlayer(): { id: number; kills: number } | null {
    let best: PlayerScore | null = null;
    for (const p of this.players.values()) {
      if (best === null) {
        best = p;
        continue;
      }
      // Most kills; ties broken by score, then by lowest id.
      if (
        p.kills > best.kills ||
        (p.kills === best.kills && p.score > best.score) ||
        (p.kills === best.kills && p.score === best.score && p.id < best.id)
      ) {
        best = p;
      }
    }
    return best ? { id: best.id, kills: best.kills } : null;
  }

  format(): string {
    const lines: string[] = [];
    lines.push("=== SCOREBOARD ===");
    lines.push("Name                K/D/A      Score");

    const ranked = this.all();
    // Group by team in a stable order: blue, red, ffa.
    const teamOrder: TeamId[] = ["blue", "red", "ffa"];
    const present = teamOrder.filter((t) => ranked.some((p) => p.team === t));

    for (const team of present) {
      const members = ranked.filter((p) => p.team === team);
      lines.push("");
      lines.push(
        `[${TEAM_NAMES[team]}]  kills ${this.teamKills(team)}  score ${this.teamScore(team)}`,
      );
      for (const p of members) {
        const kda = `${p.kills}/${p.deaths}/${p.assists}`;
        lines.push(`  ${p.name.padEnd(18)}${kda.padEnd(11)}${p.score}`);
      }
    }

    return lines.join("\n");
  }
}
