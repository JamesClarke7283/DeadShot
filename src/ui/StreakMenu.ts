// StreakMenu — the hold-to-show scorestreak selector. While held open it lists
// the player's streaks; available ones are bright and clickable, locked ones are
// dimmed. Picking an available entry fires the onSelect callback with its id.
// Keyboard wiring (which key shows it, etc.) is the integrator's responsibility;
// this widget only exposes setVisible / setOptions / onSelect.

import { clearChildren, el } from "./dom.ts";

export interface StreakOption {
  id: string;
  name: string;
  available: boolean;
}

export class StreakMenu {
  private readonly wrap: HTMLElement;
  private readonly list: HTMLElement;
  private options: StreakOption[] = [];
  private cb: (id: string) => void = () => {};

  constructor(root: HTMLElement) {
    this.wrap = el("div", {
      parent: root,
      style: {
        position: "absolute",
        left: "50%",
        bottom: "120px",
        transform: "translateX(-50%)",
        display: "none",
        flexDirection: "column",
        gap: "8px",
        padding: "16px 18px",
        background: "rgba(16,20,28,0.94)",
        border: "2px solid #0a0c10",
        borderRadius: "12px",
        boxShadow: "4px 4px 0 #0a0c10",
        pointerEvents: "auto",
        fontFamily: "'Segoe UI', system-ui, sans-serif",
        userSelect: "none",
      },
    });

    el("div", {
      parent: this.wrap,
      text: "SCORESTREAKS",
      style: {
        font: "800 13px/1 'Segoe UI', system-ui, sans-serif",
        letterSpacing: "0.12em",
        color: "#cdeb6e",
        textAlign: "center",
      },
    });
    el("div", {
      parent: this.wrap,
      text: "Hold Z, press 1 – 3",
      style: {
        font: "600 11px/1 'Segoe UI', system-ui, sans-serif",
        color: "#9fb0c4",
        textAlign: "center",
        marginTop: "-2px",
      },
    });

    this.list = el("div", {
      parent: this.wrap,
      style: { display: "flex", flexDirection: "column", gap: "6px", minWidth: "200px" },
    });
  }

  setVisible(b: boolean): void {
    this.wrap.style.display = b ? "flex" : "none";
  }

  setOptions(items: StreakOption[]): void {
    this.options = items;
    this.render();
  }

  onSelect(cb: (id: string) => void): void {
    this.cb = cb;
  }

  private render(): void {
    clearChildren(this.list);

    if (this.options.length === 0) {
      el("div", {
        parent: this.list,
        text: "No streaks earned yet",
        style: {
          font: "600 13px/1 'Segoe UI', system-ui, sans-serif",
          color: "#9fb0c4",
          textAlign: "center",
        },
      });
      return;
    }

    this.options.forEach((opt, i) => {
      const row = el("div", {
        parent: this.list,
        style: {
          display: "flex",
          alignItems: "center",
          gap: "10px",
          padding: "8px 12px",
          borderRadius: "7px",
          border: "2px solid #0a0c10",
          background: opt.available
            ? "linear-gradient(180deg,#cdeb6e,#9fd13e)"
            : "rgba(40,48,60,0.8)",
          color: opt.available ? "#0a0c10" : "#7f8aa0",
          cursor: opt.available ? "pointer" : "default",
          font: "700 14px/1 'Segoe UI', system-ui, sans-serif",
          opacity: opt.available ? "1" : "0.55",
        },
      });

      el("span", {
        parent: row,
        text: `${i + 1}`,
        style: {
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
          width: "20px",
          height: "20px",
          borderRadius: "4px",
          background: "rgba(10,12,16,0.25)",
          fontSize: "12px",
        },
      });
      el("span", { parent: row, text: opt.name, style: { flex: "1" } });
      if (!opt.available) {
        el("span", { parent: row, text: "🔒", style: { fontSize: "13px" } });
      }

      if (opt.available) {
        row.addEventListener("click", () => this.cb(opt.id));
      }
    });
  }
}
