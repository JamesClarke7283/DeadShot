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
  constructor(private input: Input, private camera: Camera) {}

  connected(): boolean {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const p of pads) if (p) return true;
    return false;
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
    if (!gp) return;

    const lx = dz(gp.axes[0] ?? 0);
    const ly = dz(gp.axes[1] ?? 0);
    const rx = dz(gp.axes[2] ?? 0);
    const ry = dz(gp.axes[3] ?? 0);

    this.input.setVirtual("KeyW", ly < -0.3);
    this.input.setVirtual("KeyS", ly > 0.3);
    this.input.setVirtual("KeyA", lx < -0.3);
    this.input.setVirtual("KeyD", lx > 0.3);

    const rate = 2.8 * dt;
    if (rx !== 0 || ry !== 0) this.camera.applyRecoil(-ry * rate, -rx * rate);

    const b = (i: number) => !!gp!.buttons[i]?.pressed;
    this.input.setVirtual("Mouse0", b(7)); // RT  fire
    this.input.setVirtual("Mouse2", b(6)); // LT  ADS
    this.input.setVirtual("Space", b(0)); // A   jump
    this.input.setVirtual("KeyR", b(2)); // X   reload
    this.input.setVirtual("KeyG", b(5)); // RB  lethal
    this.input.setVirtual("KeyQ", b(4)); // LB  tactical
    this.input.setVirtual("ShiftLeft", b(10)); // L3 sprint
    this.input.setVirtual("KeyZ", b(3)); // Y   streaks
    this.input.setVirtual("Tab", b(8)); // Back scoreboard
    this.input.setVirtual("Escape", b(9)); // Start pause
  }
}
