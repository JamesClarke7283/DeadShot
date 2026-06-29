// Typed localStorage persistence: 10 custom classes, settings, and the last
// match config, with schema versioning + migration.
//
// The backing store is abstracted (KeyValueStore) so it works in the browser
// (localStorage), the webview, and headless tests (in-memory). On load, data
// from an older schema version is migrated forward; unknown/corrupt data falls
// back to defaults.

import { DEFAULT_PERKS } from "../game/Perks.ts";

export const SCHEMA_VERSION = 1;
export const STORAGE_KEY = "deadshot.save";
export const CLASS_SLOTS = 10;

export interface KeyValueStore {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface WeaponLoadout {
  weaponId: string;
  /** Attachment ids (one per chosen slot). */
  attachments: string[];
}

export interface ClassLoadout {
  name: string;
  primary: WeaponLoadout;
  secondary: WeaponLoadout;
  tactical: string;
  lethal: string;
  fieldUpgrade: string;
  perks: string[]; // 3: blue/red/gold
  streaks: string[]; // up to 3
  camo: string;
}

export interface Settings {
  sensitivity: number;
  fov: number;
  masterVolume: number;
  sfxVolume: number;
  musicVolume: number;
  invertY: boolean;
  killcam: boolean;
}

export interface MatchConfig {
  mapId: string;
  mode: "tdm" | "ffa";
  botCount: number;
  difficulty: "recruit" | "regular" | "veteran";
  hardcore: boolean;
}

export interface SaveData {
  version: number;
  classes: ClassLoadout[];
  settings: Settings;
  lastMatch: MatchConfig;
}

export function defaultClass(index: number): ClassLoadout {
  return {
    name: `Custom ${index + 1}`,
    primary: { weaponId: "m4", attachments: ["reddot", "compensator"] },
    secondary: { weaponId: "m9", attachments: [] },
    tactical: "flashbang",
    lethal: "frag",
    fieldUpgrade: "deadsilence",
    perks: [...DEFAULT_PERKS],
    streaks: ["uav", "care_package", "attack_heli"],
    camo: "gunmetal",
  };
}

export function defaultSettings(): Settings {
  return {
    sensitivity: 1.0,
    fov: 75,
    masterVolume: 0.8,
    sfxVolume: 0.9,
    musicVolume: 0.5,
    invertY: false,
    killcam: true,
  };
}

export function defaultMatchConfig(): MatchConfig {
  return { mapId: "desert_town", mode: "tdm", botCount: 8, difficulty: "regular", hardcore: false };
}

export function defaultSave(): SaveData {
  return {
    version: SCHEMA_VERSION,
    classes: Array.from({ length: CLASS_SLOTS }, (_, i) => defaultClass(i)),
    settings: defaultSettings(),
    lastMatch: defaultMatchConfig(),
  };
}

class MemoryStore implements KeyValueStore {
  private m = new Map<string, string>();
  getItem(k: string): string | null {
    return this.m.has(k) ? this.m.get(k)! : null;
  }
  setItem(k: string, v: string): void {
    this.m.set(k, v);
  }
  removeItem(k: string): void {
    this.m.delete(k);
  }
}

function defaultBackend(): KeyValueStore {
  try {
    if (typeof localStorage !== "undefined") {
      // Touch it to ensure it's usable (some envs throw on access).
      localStorage.length;
      return localStorage as unknown as KeyValueStore;
    }
  } catch {
    // fall through to memory
  }
  return new MemoryStore();
}

export class Storage {
  private backend: KeyValueStore;
  private data: SaveData;

  constructor(backend?: KeyValueStore) {
    this.backend = backend ?? defaultBackend();
    this.data = this.load();
  }

  private load(): SaveData {
    const raw = this.backend.getItem(STORAGE_KEY);
    if (!raw) return defaultSave();
    try {
      const parsed = JSON.parse(raw) as Partial<SaveData>;
      return migrate(parsed);
    } catch {
      return defaultSave();
    }
  }

  save(): void {
    this.backend.setItem(STORAGE_KEY, JSON.stringify(this.data));
  }

  // ---- Classes ----
  getClasses(): ClassLoadout[] {
    return this.data.classes;
  }
  getClass(index: number): ClassLoadout {
    return this.data.classes[index];
  }
  setClass(index: number, loadout: ClassLoadout): void {
    this.data.classes[index] = loadout;
    this.save();
  }

  // ---- Settings ----
  getSettings(): Settings {
    return this.data.settings;
  }
  updateSettings(patch: Partial<Settings>): void {
    this.data.settings = { ...this.data.settings, ...patch };
    this.save();
  }

  // ---- Last match ----
  getMatchConfig(): MatchConfig {
    return this.data.lastMatch;
  }
  setMatchConfig(cfg: MatchConfig): void {
    this.data.lastMatch = cfg;
    this.save();
  }

  /** Wipe everything back to defaults. */
  reset(): void {
    this.data = defaultSave();
    this.save();
  }
}

/** Migrate any prior-version (or partial) save forward to the current schema. */
export function migrate(input: Partial<SaveData>): SaveData {
  const base = defaultSave();
  if (!input || typeof input !== "object") return base;

  // Future versions add cases here; v0/undefined -> v1 fills missing fields.
  const classes = Array.isArray(input.classes)
    ? base.classes.map((def, i) => ({ ...def, ...(input.classes![i] ?? {}) }))
    : base.classes;

  return {
    version: SCHEMA_VERSION,
    classes,
    settings: { ...base.settings, ...(input.settings ?? {}) },
    lastMatch: { ...base.lastMatch, ...(input.lastMatch ?? {}) },
  };
}
