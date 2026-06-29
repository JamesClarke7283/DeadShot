// Per-weapon recoil controller.
//
// On each shot kick() pushes the holder's view up (and randomly sideways) per the
// weapon's RecoilProfile, with a stronger first shot. update() recovers the
// accumulated upward kick over time so the view drifts back down — the player
// fights the climb, CoD-style. Recoil is applied through a callback (the holder's
// applyRecoil), so it composes with the player camera or a bot's aim.

import type { RecoilProfile } from "./WeaponDefinition.ts";

const DEG2RAD = Math.PI / 180;

export type ApplyRecoil = (pitch: number, yaw: number) => void;

export class Recoil {
  /** Un-recovered upward kick (radians) eligible for recovery. */
  private accumPitch = 0;
  private shotIndex = 0;

  /** Call when the trigger is released / fire stops, to reset first-shot bonus. */
  resetBurst(): void {
    this.shotIndex = 0;
  }

  /** Apply one shot's kick via `apply` and remember it for recovery. */
  kick(profile: RecoilProfile, apply: ApplyRecoil): void {
    const fs = this.shotIndex === 0 ? profile.firstShotMult : 1;
    const pitch = profile.vertical * fs * DEG2RAD;
    const yaw = (Math.random() * 2 - 1) * profile.horizontal * fs * DEG2RAD;
    this.accumPitch += pitch;
    this.shotIndex++;
    apply(pitch, yaw);
  }

  /** Recover accumulated upward kick toward zero. */
  update(dt: number, profile: RecoilProfile, apply: ApplyRecoil): void {
    if (this.accumPitch <= 0) return;
    const rec = Math.min(this.accumPitch, profile.recovery * DEG2RAD * dt);
    this.accumPitch -= rec;
    apply(-rec, 0);
  }
}
