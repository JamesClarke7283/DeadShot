// ScorestreakManager: tracks per-player streak score, unlock thresholds, and
// which streaks are currently in progress (so the same one can't be re-triggered
// until it ends). Scorestreak-style: streak score accumulates and does NOT reset
// on death. Players pick up to 3 streaks (a loadout); a streak becomes available
// once its score cost is met and it isn't already active.

import type { StreakDef } from "./Streak.ts";

export const MAX_STREAK_SLOTS = 3;
export const DEFAULT_LOADOUT = ["uav", "care_package", "attack_heli"];

export class ScorestreakManager {
  private byId = new Map<string, StreakDef>();
  private score = new Map<number, number>();
  private loadouts = new Map<number, string[]>();
  private active = new Map<number, Set<string>>();
  private fallbackLoadout: string[];

  constructor(defs: StreakDef[], fallbackLoadout: string[] = DEFAULT_LOADOUT) {
    for (const d of defs) this.byId.set(d.id, d);
    this.fallbackLoadout = fallbackLoadout.slice(0, MAX_STREAK_SLOTS);
  }

  setLoadout(playerId: number, streakIds: string[]): void {
    this.loadouts.set(playerId, streakIds.slice(0, MAX_STREAK_SLOTS));
  }

  loadout(playerId: number): string[] {
    return this.loadouts.get(playerId) ?? this.fallbackLoadout;
  }

  addScore(playerId: number, amount: number): void {
    this.score.set(playerId, (this.score.get(playerId) ?? 0) + amount);
  }

  scoreOf(playerId: number): number {
    return this.score.get(playerId) ?? 0;
  }

  costOf(streakId: string): number {
    return this.byId.get(streakId)?.cost ?? Infinity;
  }

  def(streakId: string): StreakDef | undefined {
    return this.byId.get(streakId);
  }

  private activeSet(playerId: number): Set<string> {
    let s = this.active.get(playerId);
    if (!s) {
      s = new Set();
      this.active.set(playerId, s);
    }
    return s;
  }

  /** Loadout streaks that are affordable now and not already in progress. */
  available(playerId: number): StreakDef[] {
    const score = this.scoreOf(playerId);
    const active = this.activeSet(playerId);
    const out: StreakDef[] = [];
    for (const id of this.loadout(playerId)) {
      const def = this.byId.get(id);
      if (def && def.cost <= score && !active.has(id)) out.push(def);
    }
    return out;
  }

  isAvailable(playerId: number, streakId: string): boolean {
    return this.available(playerId).some((d) => d.id === streakId);
  }

  /** The most expensive available streak (greedy auto-use for bots), or null. */
  bestAvailable(playerId: number): StreakDef | null {
    const avail = this.available(playerId);
    if (avail.length === 0) return null;
    return avail.reduce((a, b) => (b.cost > a.cost ? b : a));
  }

  markActive(playerId: number, streakId: string): void {
    this.activeSet(playerId).add(streakId);
  }

  markEnded(playerId: number, streakId: string): void {
    this.activeSet(playerId).delete(streakId);
  }

  reset(playerId: number): void {
    this.score.delete(playerId);
    this.active.delete(playerId);
  }
}
