// Killfeed — the running list of recent kills in the top-right corner. Each
// entry reads "Killer ▸ weapon ▸ Victim" with names tinted by team color and a
// red skull marker for headshots. Newest lines slide in on top; we keep the
// last ~5 and auto-expire each after ~6s.

import { el, hexColor } from "./dom.ts";
import { teamColor } from "../core/types.ts";
import type { KillEvent } from "../game/Match.ts";

const MAX_LINES = 5;
const LIFETIME = 6000; // ms

interface Line {
  node: HTMLElement;
  timer: number;
}

export class Killfeed {
  private readonly wrap: HTMLElement;
  private readonly lines: Line[] = [];

  constructor(root: HTMLElement) {
    this.wrap = el("div", {
      parent: root,
      style: {
        position: "absolute",
        right: "16px",
        top: "120px",
        display: "flex",
        flexDirection: "column",
        alignItems: "flex-end",
        gap: "5px",
        pointerEvents: "none",
        fontFamily: "'Segoe UI', system-ui, sans-serif",
      },
    });
  }

  /** Push a new kill line. */
  add(e: KillEvent): void {
    const node = el("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: "6px",
        padding: "4px 8px",
        background: "rgba(10,12,16,0.7)",
        border: "1px solid rgba(255,255,255,0.12)",
        borderRadius: "5px",
        font: "700 13px/1 'Segoe UI', system-ui, sans-serif",
        whiteSpace: "nowrap",
        opacity: "1",
        transition: "opacity 0.4s ease-out",
      },
    });

    if (e.killer) {
      el("span", {
        parent: node,
        text: e.killer,
        style: { color: hexColor(teamColor(e.killerTeam ?? "ffa")) },
      });
    } else {
      // No killer (suicide / world): just show a skull before the victim.
      el("span", { parent: node, text: "☠", style: { color: "#9fb0c4" } });
    }

    const weapon = formatWeapon(e.weaponId);
    el("span", {
      parent: node,
      text: e.headshot ? `▸ ${weapon} 💀 ▸` : `▸ ${weapon} ▸`,
      style: { color: e.headshot ? "#ff4d4d" : "#9fb0c4", fontWeight: "600" },
    });

    el("span", {
      parent: node,
      text: e.victim,
      style: { color: hexColor(teamColor(e.victimTeam)) },
    });

    this.wrap.insertBefore(node, this.wrap.firstChild);

    const line: Line = {
      node,
      timer: setTimeout(() => this.expire(line), LIFETIME),
    };
    this.lines.push(line);

    // Trim oldest beyond the cap.
    while (this.lines.length > MAX_LINES) {
      const old = this.lines.shift();
      if (old) {
        clearTimeout(old.timer);
        old.node.remove();
      }
    }
  }

  private expire(line: Line): void {
    line.node.style.opacity = "0";
    setTimeout(() => {
      line.node.remove();
      const i = this.lines.indexOf(line);
      if (i >= 0) this.lines.splice(i, 1);
    }, 400);
  }
}

/** Turn a weapon id like "scarl" into a tidy display label. */
function formatWeapon(id: string | undefined): string {
  if (!id) return "—";
  return id.toUpperCase();
}
