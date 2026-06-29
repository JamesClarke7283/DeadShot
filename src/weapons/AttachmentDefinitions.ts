// Attachment data table + deterministic stat computation.
//
// Attachments live in seven slots (optic / barrel / magazine / stock / grip /
// perk / field-upgrade). Each carries a set of multiplicative/additive stat
// modifiers; computeWeaponStats folds a base WeaponDef + a kit of attachments
// into a final ComputedStats with no hidden state (pure, deterministic).
//
// Field upgrades and some perks carry no weapon stat deltas — they expose an
// `effect` tag the gameplay layer reads (e.g. Dead Silence, Trophy System).

import type { RangeFalloff, RecoilProfile, RocketSpec, WeaponDef } from "./WeaponDefinition.ts";

export type AttachmentSlot =
  | "optic"
  | "barrel"
  | "magazine"
  | "stock"
  | "grip"
  | "perk"
  | "fieldUpgrade";

export interface StatModifiers {
  damageMult?: number;
  fireRateMult?: number;
  magazineAdd?: number;
  reserveAdd?: number;
  reloadMult?: number;
  adsMult?: number; // < 1 aims faster
  mobilityAdd?: number;
  recoilMult?: number; // scales vertical + horizontal
  recoveryMult?: number;
  rangeMult?: number; // scales near + far
  bulletVelocityMult?: number;
  spreadMult?: number; // hipfire spread
}

export interface Attachment {
  id: string;
  name: string;
  slot: AttachmentSlot;
  description: string;
  modifiers: StatModifiers;
  /** Gameplay effect tag for perks/field upgrades (no direct stat change). */
  effect?: string;
}

export interface ComputedStats {
  damage: number;
  headshotMultiplier: number;
  fireRate: number;
  magazine: number;
  reserve: number;
  reloadTime: number;
  adsTime: number;
  mobility: number;
  range: RangeFalloff;
  recoil: RecoilProfile;
  bulletVelocity: number;
  spreadMult: number;
  pellets?: number;
  rocket?: RocketSpec;
  /** Effect tags accumulated from perks/field upgrades. */
  effects: string[];
}

export const ATTACHMENTS: readonly Attachment[] = [
  // ---- Optic ----
  { id: "iron", name: "Iron Sights", slot: "optic", description: "Default sights.", modifiers: {} },
  {
    id: "reddot",
    name: "Red Dot",
    slot: "optic",
    description: "Clean precision dot.",
    modifiers: { adsMult: 0.95 },
  },
  {
    id: "holo",
    name: "Holographic",
    slot: "optic",
    description: "Wide holographic reticle.",
    modifiers: { adsMult: 0.97, spreadMult: 0.97 },
  },
  {
    id: "acog",
    name: "ACOG Scope",
    slot: "optic",
    description: "4x magnification for range.",
    modifiers: { rangeMult: 1.15, adsMult: 1.12, mobilityAdd: -3 },
  },

  // ---- Barrel ----
  {
    id: "compensator",
    name: "Compensator",
    slot: "barrel",
    description: "Less recoil, slightly less range.",
    modifiers: { recoilMult: 0.8, rangeMult: 0.9 },
  },
  {
    id: "suppressor",
    name: "Suppressor",
    slot: "barrel",
    description: "Silenced; less range and bullet speed.",
    modifiers: { rangeMult: 0.85, bulletVelocityMult: 0.9, mobilityAdd: -2 },
    effect: "silenced",
  },
  {
    id: "longbarrel",
    name: "Long Barrel",
    slot: "barrel",
    description: "More range and velocity, less mobile.",
    modifiers: { rangeMult: 1.2, bulletVelocityMult: 1.15, mobilityAdd: -4, adsMult: 1.05 },
  },
  {
    id: "muzzlebrake",
    name: "Muzzle Brake",
    slot: "barrel",
    description: "Tames vertical recoil.",
    modifiers: { recoilMult: 0.85, recoveryMult: 1.1 },
  },

  // ---- Magazine ----
  {
    id: "extmag",
    name: "Extended Mag",
    slot: "magazine",
    description: "+15 rounds, slower to handle.",
    modifiers: { magazineAdd: 15, mobilityAdd: -5, reloadMult: 1.1 },
  },
  {
    id: "fastmag",
    name: "Fast Mag",
    slot: "magazine",
    description: "Quicker reloads.",
    modifiers: { reloadMult: 0.8 },
  },
  {
    id: "fmj",
    name: "FMJ",
    slot: "magazine",
    description: "Hardened rounds: more damage at range.",
    modifiers: { damageMult: 1.05, rangeMult: 1.05 },
  },
  {
    id: "drum",
    name: "Drum Mag",
    slot: "magazine",
    description: "+40 rounds, heavy.",
    modifiers: { magazineAdd: 40, mobilityAdd: -10, reloadMult: 1.25, adsMult: 1.05 },
  },

  // ---- Stock ----
  {
    id: "stock_std",
    name: "Standard Stock",
    slot: "stock",
    description: "Balanced.",
    modifiers: {},
  },
  {
    id: "nostock",
    name: "No Stock",
    slot: "stock",
    description: "Fast ADS + mobility, more recoil.",
    modifiers: { adsMult: 0.88, mobilityAdd: 5, recoilMult: 1.15 },
  },
  {
    id: "heavystock",
    name: "Heavy Stock",
    slot: "stock",
    description: "Stability at the cost of mobility.",
    modifiers: { recoilMult: 0.85, mobilityAdd: -4 },
  },

  // ---- Grip ----
  { id: "grip_none", name: "No Grip", slot: "grip", description: "None.", modifiers: {} },
  {
    id: "foregrip",
    name: "Foregrip",
    slot: "grip",
    description: "Reduces recoil.",
    modifiers: { recoilMult: 0.82 },
  },
  {
    id: "angledgrip",
    name: "Angled Grip",
    slot: "grip",
    description: "Faster ADS.",
    modifiers: { adsMult: 0.85 },
  },
  {
    id: "laser",
    name: "Laser Sight",
    slot: "grip",
    description: "Tighter hipfire.",
    modifiers: { spreadMult: 0.7 },
  },

  // ---- Perk (weapon) ----
  { id: "perk_none", name: "No Perk", slot: "perk", description: "None.", modifiers: {} },
  {
    id: "sleightofhand",
    name: "Sleight of Hand",
    slot: "perk",
    description: "Faster reloads.",
    modifiers: { reloadMult: 0.75 },
    effect: "sleight_of_hand",
  },
  {
    id: "steadyaim",
    name: "Steady Aim",
    slot: "perk",
    description: "Improved hipfire accuracy.",
    modifiers: { spreadMult: 0.75 },
    effect: "steady_aim",
  },
  {
    id: "fullyloaded",
    name: "Fully Loaded",
    slot: "perk",
    description: "Extra reserve ammo.",
    modifiers: { reserveAdd: 60 },
    effect: "fully_loaded",
  },

  // ---- Field upgrade (class-level effects) ----
  {
    id: "fu_none",
    name: "None",
    slot: "fieldUpgrade",
    description: "No field upgrade.",
    modifiers: {},
  },
  {
    id: "deadsilence",
    name: "Dead Silence",
    slot: "fieldUpgrade",
    description: "Silent footsteps for a duration.",
    modifiers: {},
    effect: "dead_silence",
  },
  {
    id: "trophy",
    name: "Trophy System",
    slot: "fieldUpgrade",
    description: "Destroys incoming explosives.",
    modifiers: {},
    effect: "trophy",
  },
  {
    id: "munitions",
    name: "Munitions Box",
    slot: "fieldUpgrade",
    description: "Resupply ammo + equipment.",
    modifiers: {},
    effect: "munitions",
  },
  {
    id: "stoppingpower",
    name: "Stopping Power",
    slot: "fieldUpgrade",
    description: "Temporary damage boost.",
    modifiers: {},
    effect: "stopping_power",
  },
] as const;

const BY_ID = new Map<string, Attachment>(ATTACHMENTS.map((a) => [a.id, a]));

export function getAttachment(id: string): Attachment {
  const a = BY_ID.get(id);
  if (!a) throw new Error(`Unknown attachment id: ${id}`);
  return a;
}

export function attachmentsForSlot(slot: AttachmentSlot): Attachment[] {
  return ATTACHMENTS.filter((a) => a.slot === slot);
}

/** Camo color palette applied to viewmodels (id + display name + hex). */
export interface Camo {
  id: string;
  name: string;
  color: number;
}

export const CAMO_PALETTE: readonly Camo[] = [
  { id: "gunmetal", name: "Gunmetal", color: 0x2b2f36 },
  { id: "desert", name: "Desert Tan", color: 0xc2a878 },
  { id: "woodland", name: "Woodland", color: 0x4f7942 },
  { id: "arctic", name: "Arctic", color: 0xdfe7ef },
  { id: "crimson", name: "Crimson", color: 0xb3202a },
  { id: "azure", name: "Azure", color: 0x2a6fb3 },
  { id: "gold", name: "Gold", color: 0xd4af37 },
  { id: "neon", name: "Neon", color: 0x39ff14 },
  { id: "violet", name: "Violet", color: 0x7b3ff2 },
  { id: "orange", name: "Hazard Orange", color: 0xff7b00 },
] as const;

export function getCamo(id: string): Camo {
  return CAMO_PALETTE.find((c) => c.id === id) ?? CAMO_PALETTE[0];
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

/**
 * Fold a base weapon + a kit of attachments into final stats. Pure and
 * deterministic: identical inputs always yield identical output.
 */
export function computeWeaponStats(
  def: WeaponDef,
  attachments: ReadonlyArray<Attachment | string>,
): ComputedStats {
  const stats: ComputedStats = {
    damage: def.damage,
    headshotMultiplier: def.headshotMultiplier,
    fireRate: def.fireRate,
    magazine: def.magazine,
    reserve: def.reserve,
    reloadTime: def.reloadTime,
    adsTime: def.adsTime,
    mobility: def.mobility,
    range: { ...def.range },
    recoil: { ...def.recoil },
    bulletVelocity: def.bulletVelocity,
    spreadMult: 1,
    pellets: def.pellets,
    rocket: def.rocket ? { ...def.rocket } : undefined,
    effects: [],
  };

  for (const ref of attachments) {
    const att = typeof ref === "string" ? getAttachment(ref) : ref;
    const m = att.modifiers;
    if (m.damageMult) stats.damage *= m.damageMult;
    if (m.fireRateMult) stats.fireRate *= m.fireRateMult;
    if (m.magazineAdd) stats.magazine += m.magazineAdd;
    if (m.reserveAdd) stats.reserve += m.reserveAdd;
    if (m.reloadMult) stats.reloadTime *= m.reloadMult;
    if (m.adsMult) stats.adsTime *= m.adsMult;
    if (m.mobilityAdd) stats.mobility += m.mobilityAdd;
    if (m.recoilMult) {
      stats.recoil.vertical *= m.recoilMult;
      stats.recoil.horizontal *= m.recoilMult;
    }
    if (m.recoveryMult) stats.recoil.recovery *= m.recoveryMult;
    if (m.rangeMult) {
      stats.range.near *= m.rangeMult;
      stats.range.far *= m.rangeMult;
    }
    if (m.bulletVelocityMult) stats.bulletVelocity *= m.bulletVelocityMult;
    if (m.spreadMult) stats.spreadMult *= m.spreadMult;
    if (att.effect) stats.effects.push(att.effect);
  }

  stats.magazine = Math.max(1, Math.round(stats.magazine));
  stats.mobility = clamp(stats.mobility, 1, 100);
  return stats;
}
