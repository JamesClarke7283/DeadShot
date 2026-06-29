// DamageIndicator — directional "you got hit from over there" arcs. Each call to
// show(angleRad) spawns a red arc hugging the screen edge, rotated so it points
// toward the incoming damage (0 = dead ahead, clockwise). Arcs fade out over
// ~1.2s and several can be on screen at once (e.g. crossfire).

import { el } from "./dom.ts";

const DURATION = 1200; // ms
const ARC_DEG = 70; // angular width of the arc wedge

export class DamageIndicator {
  private readonly wrap: HTMLElement;

  constructor(root: HTMLElement) {
    // A centered, full-screen layer; arcs are rotated around this center so a
    // wedge anchored at the top edge ends up pointing in the right direction.
    this.wrap = el("div", {
      parent: root,
      style: {
        position: "absolute",
        inset: "0",
        pointerEvents: "none",
        overflow: "hidden",
      },
    });
  }

  /** Show a red arc pointing toward `angleRad` (0 = front, clockwise). */
  show(angleRad: number): void {
    const deg = (angleRad * 180) / Math.PI;

    // A rotor pinned to screen center; rotating it aims the wedge.
    const rotor = el("div", {
      parent: this.wrap,
      style: {
        position: "absolute",
        left: "50%",
        top: "50%",
        width: "0",
        height: "0",
        transform: `rotate(${deg}deg)`,
        opacity: "1",
        transition: `opacity ${DURATION}ms ease-out`,
      },
    });

    // The wedge: a curved red glow sitting above center, fading inward.
    el("div", {
      parent: rotor,
      style: {
        position: "absolute",
        left: "50%",
        top: "0",
        width: "220px",
        height: "150px",
        transform: "translate(-50%,-100%)",
        transformOrigin: "bottom center",
        background: `conic-gradient(from ${
          -ARC_DEG / 2
        }deg at 50% 100%, rgba(255,40,40,0) 0deg, rgba(255,40,40,0.85) ${
          ARC_DEG / 2
        }deg, rgba(255,40,40,0) ${ARC_DEG}deg)`,
        webkitMaskImage:
          "radial-gradient(circle at 50% 100%, transparent 55%, #000 75%, transparent 100%)",
        maskImage:
          "radial-gradient(circle at 50% 100%, transparent 55%, #000 75%, transparent 100%)",
        filter: "blur(1px)",
      },
    });

    // Trigger fade + cleanup.
    requestAnimationFrame(() => {
      rotor.style.opacity = "0";
    });
    setTimeout(() => rotor.remove(), DURATION + 60);
  }
}
