// HitMarker — the little "X" that flashes at screen center when your shots land.
// White for a body hit, red and a touch bigger for a headshot. It pops in then
// fades over ~150ms via a CSS transition. Re-firing show() restarts the flash.

import { el } from "./dom.ts";

const DURATION = 150; // ms
const ARM = 8; // half-length of each diagonal arm, px
const THICK = 2; // arm thickness, px

export class HitMarker {
  private readonly wrap: HTMLElement;
  private readonly arms: HTMLElement[] = [];
  private timer = 0;

  constructor(root: HTMLElement) {
    this.wrap = el("div", {
      parent: root,
      style: {
        position: "absolute",
        left: "50%",
        top: "50%",
        transform: "translate(-50%,-50%)",
        pointerEvents: "none",
        opacity: "0",
        transition: `opacity ${DURATION}ms ease-out, transform ${DURATION}ms ease-out`,
      },
    });

    // Four short diagonal arms forming an X (gap left in the middle).
    for (const rot of [45, 135, 225, 315]) {
      const arm = el("div", {
        parent: this.wrap,
        style: {
          position: "absolute",
          left: "50%",
          top: "50%",
          width: `${THICK}px`,
          height: `${ARM}px`,
          background: "#fff",
          boxShadow: "0 0 3px rgba(0,0,0,0.9)",
          transformOrigin: "top center",
          transform: `rotate(${rot}deg) translate(-50%,4px)`,
        },
      });
      this.arms.push(arm);
    }
  }

  /** Flash the marker. `headshot` => red + slightly larger. */
  show(headshot: boolean): void {
    const color = headshot ? "#ff4d4d" : "#fff";
    for (const arm of this.arms) arm.style.background = color;

    // Restart the animation: force a reflow so the transition replays.
    this.wrap.style.transition = "none";
    this.wrap.style.opacity = "1";
    this.wrap.style.transform = `translate(-50%,-50%) scale(${headshot ? 1.5 : 1.1})`;
    void this.wrap.offsetWidth; // reflow
    this.wrap.style.transition = `opacity ${DURATION}ms ease-out, transform ${DURATION}ms ease-out`;
    this.wrap.style.opacity = "0";
    this.wrap.style.transform = `translate(-50%,-50%) scale(${headshot ? 1.2 : 0.9})`;

    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.wrap.style.opacity = "0";
      this.timer = 0;
    }, DURATION);
  }
}
