// MainMenu — the title screen. A full-screen centered panel with the DEADSHOT
// logo and the primary navigation buttons (Play, Create-a-Class, Options, Quit).
//
// The integrator owns screen transitions: each button just fires the matching
// callback. show()/hide() toggle visibility; dispose() tears the DOM down.

import { button, clearChildren, el } from "./dom.ts";

export interface MainMenuOptions {
  onPlay: () => void;
  onCreateClass: () => void;
  onOptions: () => void;
  onQuit: () => void;
}

export class MainMenu {
  private readonly root: HTMLElement;
  private readonly opts: MainMenuOptions;
  private readonly overlay: HTMLElement;
  private optionsPanel: HTMLElement | null = null;

  constructor(root: HTMLElement, opts: MainMenuOptions) {
    this.root = root;
    this.opts = opts;
    this.overlay = this.build();
    this.root.appendChild(this.overlay);
  }

  private build(): HTMLElement {
    const overlay = el("div", {
      style: {
        position: "absolute",
        inset: "0",
        // Hidden until show() (start() enters MainMenu, which shows it).
        display: "none",
        alignItems: "center",
        justifyContent: "center",
        background: "radial-gradient(120% 120% at 50% 10%, #1b2330 0%, #0a0c10 70%, #05070a 100%)",
        fontFamily: "'Segoe UI', system-ui, sans-serif",
        userSelect: "none",
        // Capture clicks so the menu is modal.
        pointerEvents: "auto",
      },
    });

    const panel = el("div", {
      parent: overlay,
      style: {
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: "28px",
        padding: "40px 56px",
      },
    });

    // Logo.
    el("div", {
      parent: panel,
      text: "DEADSHOT",
      style: {
        font: "900 88px/0.9 'Segoe UI', system-ui, sans-serif",
        letterSpacing: "0.06em",
        color: "#cdeb6e",
        textShadow: "6px 6px 0 #0a0c10, 0 0 24px rgba(205,235,110,0.35)",
        webkitTextStroke: "3px #0a0c10",
      },
    });

    // Subtitle.
    el("div", {
      parent: panel,
      text: "Lock in. Load out. Light 'em up.",
      style: {
        font: "600 18px/1 'Segoe UI', system-ui, sans-serif",
        letterSpacing: "0.16em",
        textTransform: "uppercase",
        color: "#9fb0c4",
      },
    });

    // Button column.
    const buttons = el("div", {
      parent: panel,
      style: {
        display: "flex",
        flexDirection: "column",
        gap: "14px",
        marginTop: "8px",
        width: "260px",
      },
    });

    const wide: Partial<CSSStyleDeclaration> = {
      width: "100%",
      padding: "14px 22px",
      fontSize: "18px",
    };
    buttons.appendChild(button("PLAY", () => this.opts.onPlay(), wide));
    buttons.appendChild(button("CREATE-A-CLASS", () => this.opts.onCreateClass(), wide));
    buttons.appendChild(button("OPTIONS", () => this.toggleOptions(), wide));
    buttons.appendChild(
      button("QUIT", () => this.opts.onQuit(), {
        ...wide,
        background: "linear-gradient(180deg,#e88,#c55)",
      }),
    );

    return overlay;
  }

  /** Notify the integrator and toggle a small inline options placeholder. */
  private toggleOptions(): void {
    this.opts.onOptions();
    if (this.optionsPanel) {
      this.optionsPanel.remove();
      this.optionsPanel = null;
      return;
    }
    this.optionsPanel = this.buildOptionsPanel();
    this.overlay.appendChild(this.optionsPanel);
  }

  private buildOptionsPanel(): HTMLElement {
    const panel = el("div", {
      style: {
        position: "absolute",
        right: "32px",
        bottom: "32px",
        width: "300px",
        display: "flex",
        flexDirection: "column",
        gap: "14px",
        padding: "20px",
        background: "rgba(16,20,28,0.95)",
        border: "2px solid #0a0c10",
        borderRadius: "12px",
        boxShadow: "4px 4px 0 #0a0c10",
        color: "#e6edf5",
        font: "600 14px/1 'Segoe UI', system-ui, sans-serif",
      },
    });

    el("div", {
      parent: panel,
      text: "OPTIONS",
      style: { fontSize: "16px", letterSpacing: "0.1em", color: "#cdeb6e" },
    });

    const slider = (label: string): void => {
      const row = el("label", {
        parent: panel,
        style: { display: "flex", flexDirection: "column", gap: "6px" },
      });
      el("span", { parent: row, text: label });
      el("input", {
        parent: row,
        attrs: { type: "range", min: "0", max: "100", value: "75" },
        style: { width: "100%", accentColor: "#9fd13e", pointerEvents: "auto" },
      });
    };
    slider("Master Volume");
    slider("Mouse Sensitivity");

    el("div", {
      parent: panel,
      text: "Full settings coming soon.",
      style: { fontSize: "12px", color: "#9fb0c4", fontWeight: "400" },
    });

    return panel;
  }

  show(): void {
    this.overlay.style.display = "flex";
  }

  hide(): void {
    this.overlay.style.display = "none";
  }

  dispose(): void {
    clearChildren(this.overlay);
    this.overlay.remove();
    this.optionsPanel = null;
  }
}
