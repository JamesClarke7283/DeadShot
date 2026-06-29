// ScoreboardUI — the full-screen Tab overlay. For TDM it shows two tables
// (BLUE / RED) with the team scoreline; for FFA a single flat table. Rows show
// Name / K / D / A / Score and are sorted by score (desc). The local player's
// row is highlighted. setVisible toggles it; update() rebuilds the contents.

import { clearChildren, el, hexColor } from "./dom.ts";
import { teamColor } from "../core/types.ts";
import type { PlayerScore } from "../game/Mode.ts";

const HEADER = ["", "K", "D", "A", "SCORE"];

export class ScoreboardUI {
  private readonly overlay: HTMLElement;
  private readonly panel: HTMLElement;

  constructor(root: HTMLElement) {
    this.overlay = el("div", {
      parent: root,
      style: {
        position: "absolute",
        inset: "0",
        display: "none",
        alignItems: "center",
        justifyContent: "center",
        background: "rgba(5,7,10,0.55)",
        pointerEvents: "none",
        fontFamily: "'Segoe UI', system-ui, sans-serif",
      },
    });

    this.panel = el("div", {
      parent: this.overlay,
      style: {
        display: "flex",
        flexDirection: "column",
        gap: "16px",
        minWidth: "560px",
        maxWidth: "80vw",
        maxHeight: "82vh",
        overflow: "auto",
        padding: "24px 28px",
        background: "rgba(16,20,28,0.96)",
        border: "2px solid #0a0c10",
        borderRadius: "12px",
        boxShadow: "5px 5px 0 #0a0c10",
        pointerEvents: "auto",
        color: "#e6edf5",
      },
    });
  }

  setVisible(b: boolean): void {
    this.overlay.style.display = b ? "flex" : "none";
  }

  update(
    rows: PlayerScore[],
    blueScore: number,
    redScore: number,
    mode: "tdm" | "ffa",
  ): void {
    clearChildren(this.panel);

    if (mode === "ffa") {
      const sorted = [...rows].sort((a, b) => b.score - a.score);
      this.panel.appendChild(
        this.heading("FREE-FOR-ALL", "#9b5de5", `${sorted[0]?.score ?? 0} pts`),
      );
      this.panel.appendChild(this.table(sorted, true));
      return;
    }

    // TDM: split into teams, each its own block.
    const blue = rows.filter((r) => r.team === "blue").sort((a, b) => b.score - a.score);
    const red = rows.filter((r) => r.team === "red").sort((a, b) => b.score - a.score);

    this.panel.appendChild(this.heading("BLUE", hexColor(teamColor("blue")), `${blueScore}`));
    this.panel.appendChild(this.table(blue, false));
    this.panel.appendChild(this.heading("RED", hexColor(teamColor("red")), `${redScore}`));
    this.panel.appendChild(this.table(red, false));
  }

  private heading(label: string, color: string, score: string): HTMLElement {
    const row = el("div", {
      style: {
        display: "flex",
        justifyContent: "space-between",
        alignItems: "baseline",
        borderBottom: `2px solid ${color}`,
        paddingBottom: "4px",
      },
    });
    el("span", {
      parent: row,
      text: label,
      style: {
        font: "800 22px/1 'Segoe UI', system-ui, sans-serif",
        color,
        letterSpacing: "0.08em",
      },
    });
    el("span", {
      parent: row,
      text: score,
      style: { font: "800 22px/1 'Segoe UI', system-ui, sans-serif", color: "#e6edf5" },
    });
    return row;
  }

  private table(rows: PlayerScore[], ffa: boolean): HTMLElement {
    const table = el("div", {
      style: { display: "grid", gridTemplateColumns: "1fr 48px 48px 48px 72px", rowGap: "2px" },
    });

    // Header row.
    HEADER.forEach((h, i) => {
      el("div", {
        parent: table,
        text: i === 0 ? "PLAYER" : h,
        style: {
          font: "700 12px/1 'Segoe UI', system-ui, sans-serif",
          color: "#9fb0c4",
          letterSpacing: "0.06em",
          textAlign: i === 0 ? "left" : "right",
          padding: "4px 6px",
        },
      });
    });

    for (const r of rows) {
      const accent = ffa ? hexColor(teamColor("ffa", r.id)) : hexColor(teamColor(r.team));
      const bg = r.isPlayer ? "rgba(205,235,110,0.14)" : "transparent";
      const cell = (text: string, first: boolean): void => {
        el("div", {
          parent: table,
          text,
          style: {
            font: `${first ? "700" : "600"} 14px/1 'Segoe UI', system-ui, sans-serif`,
            color: first ? accent : "#e6edf5",
            textAlign: first ? "left" : "right",
            padding: "5px 6px",
            background: bg,
          },
        });
      };
      cell(r.isPlayer ? `▸ ${r.name}` : r.name, true);
      cell(`${r.kills}`, false);
      cell(`${r.deaths}`, false);
      cell(`${r.assists}`, false);
      cell(`${r.score}`, false);
    }

    return table;
  }
}
