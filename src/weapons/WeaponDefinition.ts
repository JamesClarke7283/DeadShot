// Typed weapon data table for the full DeadShot roster (18 weapons, 7 slots).
//
// All gameplay-relevant base stats live here; AttachmentDefinitions.ts modifies a
// copy of these to produce the final per-class stats (see computeWeaponStats).
// Damage is per-bullet body damage at point-blank, scaled by range falloff and
// the headshot multiplier at runtime.

export type WeaponCategory =
  | "assault"
  | "smg"
  | "lmg"
  | "marksman"
  | "sniper"
  | "shotgun"
  | "pistol"
  | "launcher";

export type FireMode = "auto" | "semi" | "burst" | "bolt" | "pump";

/** Damage as a function of distance: full damage <= near, minDamage >= far. */
export interface RangeFalloff {
  near: number;
  far: number;
  minDamage: number;
}

/** Per-shot recoil profile (degrees), recovered over time. */
export interface RecoilProfile {
  vertical: number;
  horizontal: number;
  recovery: number;
  firstShotMult: number;
}

/** Explosive parameters for launcher projectiles. */
export interface RocketSpec {
  speed: number;
  directDamage: number;
  splashDamage: number;
  splashRadius: number;
}

export interface WeaponDef {
  id: string;
  name: string;
  category: WeaponCategory;
  fireMode: FireMode;
  /** Rounds per trigger pull for burst weapons. */
  burstCount?: number;
  /** Base body damage at point-blank range. */
  damage: number;
  headshotMultiplier: number;
  /** Rounds per minute. */
  fireRate: number;
  magazine: number;
  reserve: number;
  /** Seconds for a tactical reload. */
  reloadTime: number;
  /** Seconds for an empty reload (defaults to reloadTime * 1.2). */
  reloadEmptyTime?: number;
  /** Seconds to fully aim down sights. */
  adsTime: number;
  /** Movement speed factor while equipped, 0..100. */
  mobility: number;
  range: RangeFalloff;
  recoil: RecoilProfile;
  /** Projectile/tracer speed (m/s); hitscan is instant, used for tracer visuals. */
  bulletVelocity: number;
  /** Pellets per shot for shotguns. */
  pellets?: number;
  /** Launcher rocket spec. */
  rocket?: RocketSpec;
}

function recoil(
  vertical: number,
  horizontal: number,
  recovery: number,
  firstShotMult = 1.2,
): RecoilProfile {
  return { vertical, horizontal, recovery, firstShotMult };
}

export const WEAPONS: readonly WeaponDef[] = [
  // ---- Assault rifles ----
  {
    id: "m4",
    name: "M4",
    category: "assault",
    fireMode: "auto",
    damage: 33,
    headshotMultiplier: 1.4,
    fireRate: 750,
    magazine: 30,
    reserve: 120,
    reloadTime: 2.1,
    adsTime: 0.25,
    mobility: 80,
    range: { near: 32, far: 62, minDamage: 22 },
    recoil: recoil(1.1, 0.5, 7),
    bulletVelocity: 720,
  },
  {
    id: "ak12",
    name: "AK-12",
    category: "assault",
    fireMode: "auto",
    damage: 38,
    headshotMultiplier: 1.45,
    fireRate: 650,
    magazine: 30,
    reserve: 120,
    reloadTime: 2.3,
    adsTime: 0.27,
    mobility: 78,
    range: { near: 34, far: 66, minDamage: 25 },
    recoil: recoil(1.5, 0.8, 6, 1.3),
    bulletVelocity: 715,
  },
  {
    id: "scarl",
    name: "SCAR-L",
    category: "assault",
    fireMode: "auto",
    damage: 40,
    headshotMultiplier: 1.45,
    fireRate: 600,
    magazine: 25,
    reserve: 125,
    reloadTime: 2.25,
    adsTime: 0.28,
    mobility: 77,
    range: { near: 36, far: 70, minDamage: 26 },
    recoil: recoil(1.6, 0.7, 6),
    bulletVelocity: 740,
  },
  {
    id: "m16a4",
    name: "M16A4",
    category: "assault",
    fireMode: "burst",
    burstCount: 3,
    damage: 31,
    headshotMultiplier: 1.5,
    fireRate: 800,
    magazine: 30,
    reserve: 120,
    reloadTime: 2.2,
    adsTime: 0.26,
    mobility: 79,
    range: { near: 40, far: 75, minDamage: 25 },
    recoil: recoil(1.3, 0.4, 9),
    bulletVelocity: 760,
  },

  // ---- SMGs ----
  {
    id: "mp5",
    name: "MP5",
    category: "smg",
    fireMode: "auto",
    damage: 28,
    headshotMultiplier: 1.4,
    fireRate: 800,
    magazine: 30,
    reserve: 120,
    reloadTime: 1.9,
    adsTime: 0.2,
    mobility: 90,
    range: { near: 14, far: 30, minDamage: 16 },
    recoil: recoil(0.9, 0.5, 8),
    bulletVelocity: 400,
  },
  {
    id: "p90",
    name: "P90",
    category: "smg",
    fireMode: "auto",
    damage: 24,
    headshotMultiplier: 1.35,
    fireRate: 900,
    magazine: 50,
    reserve: 150,
    reloadTime: 2.4,
    adsTime: 0.22,
    mobility: 88,
    range: { near: 12, far: 26, minDamage: 14 },
    recoil: recoil(0.8, 0.6, 9),
    bulletVelocity: 380,
  },
  {
    id: "uzi",
    name: "UZI",
    category: "smg",
    fireMode: "auto",
    damage: 26,
    headshotMultiplier: 1.35,
    fireRate: 950,
    magazine: 32,
    reserve: 128,
    reloadTime: 2.0,
    adsTime: 0.19,
    mobility: 91,
    range: { near: 11, far: 24, minDamage: 13 },
    recoil: recoil(1.0, 0.8, 8),
    bulletVelocity: 360,
  },
  {
    id: "vector",
    name: "Vector",
    category: "smg",
    fireMode: "auto",
    damage: 22,
    headshotMultiplier: 1.3,
    fireRate: 1100,
    magazine: 25,
    reserve: 150,
    reloadTime: 2.0,
    adsTime: 0.18,
    mobility: 92,
    range: { near: 10, far: 22, minDamage: 12 },
    recoil: recoil(0.7, 0.4, 11),
    bulletVelocity: 370,
  },

  // ---- LMGs ----
  {
    id: "m249",
    name: "M249",
    category: "lmg",
    fireMode: "auto",
    damage: 32,
    headshotMultiplier: 1.4,
    fireRate: 700,
    magazine: 100,
    reserve: 200,
    reloadTime: 6.0,
    adsTime: 0.45,
    mobility: 58,
    range: { near: 42, far: 78, minDamage: 24 },
    recoil: recoil(1.3, 1.0, 5),
    bulletVelocity: 750,
  },
  {
    id: "rpk",
    name: "RPK",
    category: "lmg",
    fireMode: "auto",
    damage: 36,
    headshotMultiplier: 1.4,
    fireRate: 600,
    magazine: 45,
    reserve: 135,
    reloadTime: 4.6,
    adsTime: 0.4,
    mobility: 62,
    range: { near: 46, far: 82, minDamage: 27 },
    recoil: recoil(1.5, 0.9, 5),
    bulletVelocity: 760,
  },

  // ---- Marksman ----
  {
    id: "mk14",
    name: "MK14",
    category: "marksman",
    fireMode: "semi",
    damage: 55,
    headshotMultiplier: 1.6,
    fireRate: 380,
    magazine: 20,
    reserve: 100,
    reloadTime: 2.6,
    adsTime: 0.32,
    mobility: 74,
    range: { near: 60, far: 100, minDamage: 45 },
    recoil: recoil(2.6, 0.6, 5),
    bulletVelocity: 800,
  },

  // ---- Snipers ----
  {
    id: "barrett",
    name: "Barrett .50",
    category: "sniper",
    fireMode: "semi",
    damage: 110,
    headshotMultiplier: 2.2,
    fireRate: 55,
    magazine: 7,
    reserve: 35,
    reloadTime: 4.0,
    adsTime: 0.5,
    mobility: 60,
    range: { near: 120, far: 220, minDamage: 95 },
    recoil: recoil(5.5, 1.0, 3),
    bulletVelocity: 900,
  },
  {
    id: "kar98",
    name: "Kar98",
    category: "sniper",
    fireMode: "bolt",
    damage: 95,
    headshotMultiplier: 2.5,
    fireRate: 45,
    magazine: 5,
    reserve: 30,
    reloadTime: 3.2,
    adsTime: 0.48,
    mobility: 66,
    range: { near: 100, far: 200, minDamage: 90 },
    recoil: recoil(5.0, 0.8, 3),
    bulletVelocity: 850,
  },

  // ---- Shotguns ----
  {
    id: "spas12",
    name: "SPAS-12",
    category: "shotgun",
    fireMode: "pump",
    damage: 26,
    headshotMultiplier: 1.2,
    fireRate: 70,
    magazine: 8,
    reserve: 32,
    reloadTime: 3.6,
    adsTime: 0.26,
    mobility: 78,
    range: { near: 6, far: 16, minDamage: 6 },
    recoil: recoil(3.0, 1.2, 6),
    bulletVelocity: 250,
    pellets: 8,
  },
  {
    id: "ksg",
    name: "KSG",
    category: "shotgun",
    fireMode: "pump",
    damage: 22,
    headshotMultiplier: 1.2,
    fireRate: 65,
    magazine: 14,
    reserve: 42,
    reloadTime: 4.0,
    adsTime: 0.28,
    mobility: 76,
    range: { near: 7, far: 18, minDamage: 6 },
    recoil: recoil(2.8, 1.0, 6),
    bulletVelocity: 250,
    pellets: 10,
  },

  // ---- Pistols ----
  {
    id: "m9",
    name: "M9",
    category: "pistol",
    fireMode: "semi",
    damage: 28,
    headshotMultiplier: 1.5,
    fireRate: 450,
    magazine: 15,
    reserve: 60,
    reloadTime: 1.6,
    adsTime: 0.16,
    mobility: 95,
    range: { near: 15, far: 35, minDamage: 18 },
    recoil: recoil(1.2, 0.6, 9),
    bulletVelocity: 360,
  },
  {
    id: "deagle",
    name: "Deagle",
    category: "pistol",
    fireMode: "semi",
    damage: 60,
    headshotMultiplier: 1.6,
    fireRate: 320,
    magazine: 7,
    reserve: 35,
    reloadTime: 2.1,
    adsTime: 0.2,
    mobility: 90,
    range: { near: 25, far: 45, minDamage: 40 },
    recoil: recoil(3.2, 1.0, 6),
    bulletVelocity: 470,
  },

  // ---- Launchers ----
  {
    id: "rpg7",
    name: "RPG-7",
    category: "launcher",
    fireMode: "semi",
    damage: 0, // direct/splash handled by rocket spec
    headshotMultiplier: 1,
    fireRate: 30,
    magazine: 1,
    reserve: 4,
    reloadTime: 3.4,
    adsTime: 0.4,
    mobility: 70,
    range: { near: 0, far: 0, minDamage: 0 },
    recoil: recoil(4.0, 1.0, 4),
    bulletVelocity: 45,
    rocket: { speed: 45, directDamage: 150, splashDamage: 120, splashRadius: 6 },
  },
] as const;

const BY_ID = new Map<string, WeaponDef>(WEAPONS.map((w) => [w.id, w]));

export function getWeapon(id: string): WeaponDef {
  const w = BY_ID.get(id);
  if (!w) throw new Error(`Unknown weapon id: ${id}`);
  return w;
}

export function maybeWeapon(id: string): WeaponDef | undefined {
  return BY_ID.get(id);
}

export function weaponsByCategory(category: WeaponCategory): WeaponDef[] {
  return WEAPONS.filter((w) => w.category === category);
}

export const WEAPON_IDS: readonly string[] = WEAPONS.map((w) => w.id);

/** Effective reload time honoring the empty-reload variant. */
export function reloadDuration(def: WeaponDef, empty: boolean): number {
  if (!empty) return def.reloadTime;
  return def.reloadEmptyTime ?? def.reloadTime * 1.2;
}

/** Seconds between rounds derived from RPM. */
export function shotInterval(fireRate: number): number {
  return 60 / fireRate;
}

/** Body damage at a given distance using the falloff curve. */
export function damageAtRange(range: RangeFalloff, baseDamage: number, distance: number): number {
  if (distance <= range.near) return baseDamage;
  if (distance >= range.far) return range.minDamage;
  const t = (distance - range.near) / (range.far - range.near);
  return baseDamage + (range.minDamage - baseDamage) * t;
}
