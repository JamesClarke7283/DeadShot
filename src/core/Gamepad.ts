// Gamepad support (Xbox-style mapping) via the Gamepad API.
//
// Polled each frame: left stick -> movement (mapped to the virtual WASD codes so
// the existing action bindings apply), right stick -> look (camera kick), buttons
// -> fire/ADS/jump/reload/lethal/tactical/sprint/scoreboard/pause/streaks.

import type { Input } from "./Input.ts";
import type { Camera } from "./Camera.ts";

function dz(v: number, t = 0.18): number {
  return Math.abs(v) < t ? 0 : v;
}

export class GamepadController {
  // Codes this pad currently holds, so we only write on changes — an idle
  // connected pad must never clobber keyboard/mouse input.
  private held = new Set<string>();

  constructor(private input: Input, private camera: Camera) {}

  connected(): boolean {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const p of pads) if (p) return true;
    return false;
  }

  private apply(code: string, on: boolean): void {
    if (on) {
      if (!this.held.has(code)) {
        this.held.add(code);
        this.input.setVirtual(code, true);
      }
    } else if (this.held.has(code)) {
      this.held.delete(code);
      this.input.setVirtual(code, false);
    }
  }

  private clearAll(): void {
    for (const c of this.held) this.input.setVirtual(c, false);
    this.held.clear();
  }

  update(dt: number): void {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    let gp: Gamepad | null = null;
    for (const p of pads) {
      if (p) {
        gp = p;
        break;
      }
    }
    if (!gp) {
      if (this.held.size) this.clearAll();
      return;
    }

    const lx = dz(gp.axes[0] ?? 0);
    const ly = dz(gp.axes[1] ?? 0);
    const rx = dz(gp.axes[2] ?? 0);
    const ry = dz(gp.axes[3] ?? 0);

    this.apply("KeyW", ly < -0.3);
    this.apply("KeyS", ly > 0.3);
    this.apply("KeyA", lx < -0.3);
    this.apply("KeyD", lx > 0.3);

    const rate = 2.8 * dt;
    if (rx !== 0 || ry !== 0) this.camera.applyRecoil(-ry * rate, -rx * rate);

    const b = (i: number) => !!gp!.buttons[i]?.pressed;
    this.apply("Mouse0", b(7)); // RT  fire
    this.apply("Mouse2", b(6)); // LT  ADS
    this.apply("Space", b(0)); // A   jump
    this.apply("KeyR", b(2)); // X   reload
    this.apply("KeyG", b(5)); // RB  lethal
    this.apply("KeyQ", b(4)); // LB  tactical
    this.apply("ShiftLeft", b(10)); // L3 sprint
    this.apply("KeyZ", b(3)); // Y   streaks
    this.apply("Tab", b(8)); // Back scoreboard
    this.apply("Escape", b(9)); // Start pause
  }
}
