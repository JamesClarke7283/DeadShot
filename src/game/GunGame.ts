// Gun Game rules: free-for-all where every combatant starts on a pistol and
// advances one weapon tier per kill. The final tier is a throwing knife; landing
// a knife kill wins the match. Being knifed (melee) drops the victim down a tier.
// Bots cap at the second-to-last tier (Barrett) so only the human player can win
// with the knife — keeps the win condition player-centric and avoids needing a
// bot throwing-knife AI. The per-match kill-driven state (tier indices + win
// flag) lives in GunGameTracker, owned by the Match; these ModeRules just declare
// the FFA framing and the time-limit fallback used by checkWin.

import type { TeamId } from "../core/types.ts";
import type { ModeRules, ScoreboardApi, WinResult } from "./Mode.ts";

const TIME_LIMIT = 600;

/**
 * Ordered weapon tiers. The last id ("knife") is a sentinel: the Match equips
 * the throwing-knife lethal instead of swapping the gun, and a knife kill wins.
 */
export const GUN_GAME_TIERS = [
  "m9",
  "mp5",
  "spas12",
  "m4",
  "ak12",
  "mk14",
  "barrett",
  "knife",
] as const;

/** Highest tier a bot may reach (index of "barrett"); the player alone gets the knife. */
export const BOT_TIER_CAP = GUN_GAME_TIERS.length - 2;

export const GUNGAME: ModeRules = {
  id: "gungame",
  name: "Gun Game",
  friendlyFire: true,
  scoreCap: GUN_GAME_TIERS.length,
  timeLimit: TIME_LIMIT,
  teams: ["ffa"],

  assignTeam(): TeamId {
    return "ffa";
  },

  checkWin(sb: ScoreboardApi, elapsed: number): WinResult {
    if (elapsed >= TIME_LIMIT) {
      const top = sb.topPlayer();
      return { over: true, winner: top?.id, reason: "time" };
    }
    return { over: false };
  },
};

export interface TierChange {
  /** Actor whose weapon should change. */
  id: number;
  /** New weapon id to equip (a GUN_GAME_TIERS entry). */
  weaponId: string;
}

/**
 * Per-match Gun Game state: tracks each actor's tier index, advances on kills,
 * downgrades on melee deaths, and flags a win when a player lands a knife kill.
 * The Match owns one instance (when modeId === "gungame") and drives it from
 * onDeath / onRemoteDeath.
 */
export class GunGameTracker {
  private tiers = new Map<number, number>();
  private winnerId: number | undefined;

  /** Register an actor at tier 0 (the pistol). */
  register(id: number): void {
    this.tiers.set(id, 0);
  }

  tierOf(id: number): number {
    return this.tiers.get(id) ?? 0;
  }

  weaponIdOf(id: number): string {
    return GUN_GAME_TIERS[this.tierOf(id)] ?? GUN_GAME_TIERS[0];
  }

  /** Did someone win (by landing a knife kill)? */
  get winner(): number | undefined {
    return this.winnerId;
  }

  /**
   * Apply a kill. Returns the tier change for the killer (if their weapon should
   * change), or null. The Match performs the actual weapon swap.
   *
   * - A gun kill on the killer's current tier advances them one tier.
   * - A knife kill on the knife tier wins the match (player only — bots can't
   *   reach the knife tier; see BOT_TIER_CAP).
   * - Kills with any other weapon id (e.g. a stray explosive) don't advance.
   *
   * `isBot` caps the killer at BOT_TIER_CAP so bots never reach the knife tier.
   */
  onKill(
    killerId: number | undefined,
    victimId: number,
    weaponId: string | undefined,
    isBot = false,
  ): TierChange | null {
    if (killerId === undefined || killerId === victimId) return null;
    const tier = this.tierOf(killerId);
    const tierWeapon = GUN_GAME_TIERS[tier];

    // Knife kill wins (only the player can be on the knife tier).
    if (weaponId === "knife" && tierWeapon === "knife") {
      this.winnerId = killerId;
      return null;
    }

    // Only advance if the kill was made with the killer's current-tier weapon.
    if (weaponId !== tierWeapon) return null;

    // Bots cap at BOT_TIER_CAP (Barrett); they can't reach the knife tier.
    if (isBot && tier >= BOT_TIER_CAP) return null;

    const next = Math.min(GUN_GAME_TIERS.length - 1, tier + 1);
    this.tiers.set(killerId, next);
    return { id: killerId, weaponId: GUN_GAME_TIERS[next] };
  }

  /**
   * The victim was killed by a melee knife swing (weaponId "melee"): drop them
   * one tier. Returns the tier change (downgrade) or null if already at tier 0.
   */
  onMeleeDeath(victimId: number): TierChange | null {
    const tier = this.tierOf(victimId);
    if (tier <= 0) return null;
    const next = tier - 1;
    this.tiers.set(victimId, next);
    return { id: victimId, weaponId: GUN_GAME_TIERS[next] };
  }
}
