// Crosshair — a four-line dynamic crosshair plus a center dot. The four lines
// (top/bottom/left/right) sit a `spread` gap away from center; widening the gap
// (e.g. while moving or firing) communicates accuracy bloom. A small center dot
// stays fixed for fine aim. Purely cosmetic: pointer-events are off.

import { el } from "./dom.ts";

const COLOR = "#e6edf5";
const THICK = 2; // line thickness, px
const LEN = 7; // line length, px
const SHADOW = "0 0 2px rgba(0,0,0,0.9)";

export class Crosshair {
  private readonly wrap: HTMLElement;
  private readonly top: HTMLElement;
  private readonly bottom: HTMLElement;
  private readonly left: HTMLElement;
  private readonly right: HTMLElement;
  private readonly dot: HTMLElement;
  private spread = 4;

  constructor(root: HTMLElement) {
    this.wrap = el("div", {
      parent: root,
      style: {
        position: "absolute",
        left: "50%",
        top: "50%",
        transform: "translate(-50%,-50%)",
        pointerEvents: "none",
      },
    });

    const line = (vertical: boolean): HTMLElement =>
      el("div", {
        parent: this.wrap,
        style: {
          position: "absolute",
          left: "50%",
          top: "50%",
          width: vertical ? `${THICK}px` : `${LEN}px`,
          height: vertical ? `${LEN}px` : `${THICK}px`,
          background: COLOR,
          boxShadow: SHADOW,
        },
      });

    this.top = line(true);
    this.bottom = line(true);
    this.left = line(false);
    this.right = line(false);

    this.dot = el("div", {
      parent: this.wrap,
      style: {
        position: "absolute",
        left: "50%",
        top: "50%",
        width: `${THICK}px`,
        height: `${THICK}px`,
        background: COLOR,
        boxShadow: SHADOW,
        transform: "translate(-50%,-50%)",
      },
    });

    this.layout();
  }

  /** Set the gap (px) between center and the four lines. */
  setSpread(px: number): void {
    this.spread = Math.max(0, px);
    this.layout();
  }

  setVisible(b: boolean): void {
    this.wrap.style.display = b ? "block" : "none";
  }

  private layout(): void {
    const g = this.spread;
    // Vertical lines extend up/down from the gap.
    this.top.style.transform = `translate(-50%,-${g + LEN}px)`;
    this.bottom.style.transform = `translate(-50%,${g}px)`;
    // Horizontal lines extend left/right from the gap.
    this.left.style.transform = `translate(-${g + LEN}px,-50%)`;
    this.right.style.transform = `translate(${g}px,-50%)`;
  }
}
