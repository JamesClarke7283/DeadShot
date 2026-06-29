// On-screen touch controls for mobile browsers: a left movement joystick, a
// right-side look pad (drag to aim), and action buttons (fire / ADS / reload /
// jump / lethal / tactical). Movement maps to the virtual WASD codes; look feeds
// the camera directly. Shown only on touch-capable devices.

import { el } from "./dom.ts";
import type { Input } from "../core/Input.ts";
import type { Camera } from "../core/Camera.ts";

export function isTouchDevice(): boolean {
  return typeof globalThis !== "undefined" &&
    ("ontouchstart" in globalThis || (navigator?.maxTouchPoints ?? 0) > 0);
}

export class TouchControls {
  private root: HTMLDivElement;
  private knob: HTMLDivElement;
  private movePointer: number | null = null;
  private moveCenter = { x: 0, y: 0 };
  private moveVec = { x: 0, y: 0 };
  private lookPointer: number | null = null;
  private lookLast = { x: 0, y: 0 };

  constructor(parent: HTMLElement, private input: Input, private camera: Camera) {
    this.root = el("div", {
      parent,
      style: {
        position: "fixed",
        inset: "0",
        zIndex: "60",
        pointerEvents: "none",
        display: "none",
      },
    });

    // Look pad (right ~55%).
    const lookPad = el("div", {
      parent: this.root,
      style: {
        position: "absolute",
        right: "0",
        top: "0",
        width: "55%",
        height: "100%",
        pointerEvents: "auto",
      },
    });
    lookPad.addEventListener("pointerdown", (e) => {
      this.lookPointer = e.pointerId;
      this.lookLast = { x: e.clientX, y: e.clientY };
      lookPad.setPointerCapture(e.pointerId);
    });
    lookPad.addEventListener("pointermove", (e) => {
      if (e.pointerId !== this.lookPointer) return;
      const dx = e.clientX - this.lookLast.x;
      const dy = e.clientY - this.lookLast.y;
      this.lookLast = { x: e.clientX, y: e.clientY };
      this.camera.applyRecoil(-dy * 0.004, -dx * 0.004);
    });
    const endLook = (e: PointerEvent) => {
      if (e.pointerId === this.lookPointer) this.lookPointer = null;
    };
    lookPad.addEventListener("pointerup", endLook);
    lookPad.addEventListener("pointercancel", endLook);

    // Movement joystick (bottom-left).
    const base = el("div", {
      parent: this.root,
      style: {
        position: "absolute",
        left: "30px",
        bottom: "30px",
        width: "120px",
        height: "120px",
        borderRadius: "50%",
        background: "rgba(255,255,255,0.12)",
        border: "2px solid rgba(182,255,94,0.5)",
        pointerEvents: "auto",
        touchAction: "none",
      },
    });
    this.knob = el("div", {
      parent: base,
      style: {
        position: "absolute",
        left: "35px",
        top: "35px",
        width: "50px",
        height: "50px",
        borderRadius: "50%",
        background: "rgba(182,255,94,0.7)",
      },
    });
    base.addEventListener("pointerdown", (e) => {
      const r = base.getBoundingClientRect();
      this.moveCenter = { x: r.left + r.width / 2, y: r.top + r.height / 2 };
      this.movePointer = e.pointerId;
      base.setPointerCapture(e.pointerId);
      this.onMove(e);
    });
    base.addEventListener("pointermove", (e) => {
      if (e.pointerId === this.movePointer) this.onMove(e);
    });
    const endMove = (e: PointerEvent) => {
      if (e.pointerId !== this.movePointer) return;
      this.movePointer = null;
      this.moveVec = { x: 0, y: 0 };
      this.knob.style.left = "35px";
      this.knob.style.top = "35px";
    };
    base.addEventListener("pointerup", endMove);
    base.addEventListener("pointercancel", endMove);

    // Action buttons (bottom-right cluster).
    this.actionButton("FIRE", "Mouse0", "right:30px;bottom:120px;width:90px;height:90px");
    this.actionButton("ADS", "Mouse2", "right:130px;bottom:150px;width:64px;height:64px");
    this.actionButton("R", "KeyR", "right:140px;bottom:60px;width:56px;height:56px");
    this.actionButton("JMP", "Space", "right:30px;bottom:30px;width:64px;height:64px");
    this.actionButton("LETH", "KeyG", "right:210px;bottom:120px;width:56px;height:56px");
    this.actionButton("TAC", "KeyQ", "right:210px;bottom:50px;width:56px;height:56px");
  }

  private actionButton(label: string, code: string, cssPos: string): void {
    const b = el("div", {
      parent: this.root,
      text: label,
      style: {
        position: "absolute",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        borderRadius: "50%",
        background: "rgba(255,255,255,0.14)",
        border: "2px solid rgba(255,255,255,0.4)",
        color: "#fff",
        font: "700 14px system-ui",
        pointerEvents: "auto",
        touchAction: "none",
        userSelect: "none",
      },
    });
    b.style.cssText += ";" + cssPos;
    b.addEventListener("pointerdown", (e) => {
      this.input.setVirtual(code, true);
      b.setPointerCapture(e.pointerId);
      b.style.background = "rgba(182,255,94,0.5)";
    });
    const up = () => {
      this.input.setVirtual(code, false);
      b.style.background = "rgba(255,255,255,0.14)";
    };
    b.addEventListener("pointerup", up);
    b.addEventListener("pointercancel", up);
  }

  private onMove(e: PointerEvent): void {
    const dx = e.clientX - this.moveCenter.x;
    const dy = e.clientY - this.moveCenter.y;
    const max = 45;
    const len = Math.hypot(dx, dy) || 1;
    const cl = Math.min(1, len / max);
    const nx = (dx / len) * cl;
    const ny = (dy / len) * cl;
    this.moveVec = { x: nx, y: ny };
    this.knob.style.left = `${35 + nx * max}px`;
    this.knob.style.top = `${35 + ny * max}px`;
  }

  /** Apply the joystick to virtual movement keys. Call each frame while visible. */
  update(): void {
    this.input.setVirtual("KeyW", this.moveVec.y < -0.3);
    this.input.setVirtual("KeyS", this.moveVec.y > 0.3);
    this.input.setVirtual("KeyA", this.moveVec.x < -0.3);
    this.input.setVirtual("KeyD", this.moveVec.x > 0.3);
  }

  setVisible(b: boolean): void {
    this.root.style.display = b ? "block" : "none";
    if (!b) {
      for (const c of ["KeyW", "KeyS", "KeyA", "KeyD"]) this.input.setVirtual(c, false);
    }
  }

  dispose(): void {
    this.root.remove();
  }
}
