// Perk packages: three tiers (blue / red / gold), one pick per tier, CoD-style.
// Perks are gameplay modifiers read by the Player/Match where relevant; the
// class editor lets the player choose one per tier.

export type PerkTier = "blue" | "red" | "gold";

export interface Perk {
  id: string;
  name: string;
  tier: PerkTier;
  description: string;
}

export const PERKS: readonly Perk[] = [
  // Blue (mobility / resupply)
  {
    id: "double_time",
    name: "Double Time",
    tier: "blue",
    description: "Longer sprint, faster crouch.",
  },
  { id: "scavenger", name: "Scavenger", tier: "blue", description: "Resupply ammo from the dead." },
  {
    id: "coldblooded",
    name: "Cold-Blooded",
    tier: "blue",
    description: "Undetected by AI targeting.",
  },
  // Red (stealth / utility)
  { id: "ghost", name: "Ghost", tier: "red", description: "Invisible to enemy UAVs while moving." },
  { id: "hardline", name: "Hardline", tier: "red", description: "Streaks cost less score." },
  { id: "overkill", name: "Overkill", tier: "red", description: "Two primary weapons." },
  // Gold (awareness / handling)
  {
    id: "amped",
    name: "Amped",
    tier: "gold",
    description: "Faster weapon swap + launcher reload.",
  },
  { id: "high_alert", name: "High Alert", tier: "gold", description: "Vision pulses when seen." },
  { id: "tracker", name: "Tracker", tier: "gold", description: "See enemy footsteps." },
] as const;

export function perksByTier(tier: PerkTier): Perk[] {
  return PERKS.filter((p) => p.tier === tier);
}

export function getPerk(id: string): Perk | undefined {
  return PERKS.find((p) => p.id === id);
}

/** Default perk per tier (first of each). */
export const DEFAULT_PERKS: string[] = ["double_time", "ghost", "amped"];
