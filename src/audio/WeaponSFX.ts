// Per-weapon gunfire parameters + 2D playback for the local player's own weapon.
// Enemy/positional gunfire goes through SpatialSFX (same params, panned).

import type { WeaponCategory } from "../weapons/WeaponDefinition.ts";
import { getWeapon } from "../weapons/WeaponDefinition.ts";
import { type GunParams, playGunshot, playHitMarker, playReloadClick } from "./Synth.ts";
import type { AudioManager } from "./AudioManager.ts";

const CATEGORY: Record<WeaponCategory, GunParams> = {
  assault: { duration: 0.18, lowpass: 3500, thump: 90, distortion: 0.5, gain: 0.5 },
  smg: { duration: 0.12, lowpass: 4500, thump: 70, distortion: 0.4, gain: 0.4 },
  lmg: { duration: 0.22, lowpass: 3000, thump: 110, distortion: 0.6, gain: 0.55 },
  marksman: { duration: 0.28, lowpass: 2600, thump: 130, distortion: 0.6, gain: 0.7 },
  sniper: { duration: 0.4, lowpass: 2200, thump: 160, distortion: 0.7, gain: 0.85 },
  shotgun: { duration: 0.3, lowpass: 2000, thump: 140, distortion: 0.7, gain: 0.8 },
  pistol: { duration: 0.12, lowpass: 4000, thump: 80, distortion: 0.4, gain: 0.45 },
  launcher: { duration: 0.5, lowpass: 1500, thump: 60, distortion: 0.3, gain: 0.7 },
};

export function gunParams(weaponId: string): GunParams {
  return CATEGORY[getWeapon(weaponId).category];
}

export class WeaponSFX {
  constructor(private audio: AudioManager) {}

  shot(weaponId: string): void {
    playGunshot(this.audio.ctx, this.audio.sfxBus, gunParams(weaponId));
  }
  reload(): void {
    playReloadClick(this.audio.ctx, this.audio.sfxBus);
  }
  hitMarker(headshot: boolean): void {
    playHitMarker(this.audio.ctx, this.audio.sfxBus, headshot);
  }
}
