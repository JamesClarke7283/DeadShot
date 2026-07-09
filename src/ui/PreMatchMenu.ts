// PreMatchMenu — the lobby screen shown after pressing Play. The player picks a
// map, mode, bot count, difficulty, class slot and hardcore toggle, then starts.
//
// Selections initialize from storage.getMatchConfig() (last-used settings) and
// the relevant parts are persisted back via storage.setMatchConfig() on Start.

import { button, clearChildren, el } from "./dom.ts";
import type { Storage } from "../persistence/Storage.ts";
import { MAPS } from "../maps/maps.ts";

export interface PreMatchConfig {
  mapId: string;
  mode: "tdm" | "ffa" | "dom" | "ctf" | "gungame";
  botCount: number;
  difficulty: "recruit" | "regular" | "veteran";
  classSlot: number;
  hardcore: boolean;
}

export interface PreMatchMenuOptions {
  onStart: (cfg: PreMatchConfig) => void;
  onBack: () => void;
}

const DIFFICULTIES: ReadonlyArray<PreMatchConfig["difficulty"]> = ["recruit", "regular", "veteran"];

export class PreMatchMenu {
  private readonly root: HTMLElement;
  private readonly storage: Storage;
  private readonly opts: PreMatchMenuOptions;
  private readonly overlay: HTMLElement;

  // Live selection state.
  private mapId: string;
  private mode: PreMatchConfig["mode"];
  private botCount: number;
  private difficulty: PreMatchConfig["difficulty"];
  private classSlot = 0;
  private hardcore: boolean;

  // Elements whose appearance reflects state.
  private mapCards: HTMLElement[] = [];
  private modeButtons: HTMLButtonElement[] = [];
  private classSelect?: HTMLSelectElement;

  constructor(root: HTMLElement, storage: Storage, opts: PreMatchMenuOptions) {
    this.root = root;
    this.storage = storage;
    this.opts = opts;

    const last = storage.getMatchConfig();
    this.mapId = MAPS.some((m) => m.id === last.mapId) ? last.mapId : MAPS[0].id;
    this.mode = last.mode;
    this.botCount = last.botCount;
    this.difficulty = last.difficulty;
    this.hardcore = last.hardcore;

    this.overlay = this.build();
    this.root.appendChild(this.overlay);
  }

  private build(): HTMLElement {
    const overlay = el("div", {
      style: {
        position: "absolute",
        inset: "0",
        // Hidden until show(); a screen that was never entered must not linger.
        display: "none",
        alignItems: "center",
        justifyContent: "center",
        background: "radial-gradient(120% 120% at 50% 10%, #1b2330 0%, #0a0c10 70%, #05070a 100%)",
        fontFamily: "'Segoe UI', system-ui, sans-serif",
        color: "#e6edf5",
        userSelect: "none",
        overflow: "auto",
        // Capture clicks so the menu is modal (no firing through to the canvas).
        pointerEvents: "auto",
      },
    });

    const panel = el("div", {
      parent: overlay,
      style: {
        display: "flex",
        flexDirection: "column",
        gap: "22px",
        width: "min(820px, 92vw)",
        padding: "32px 36px",
        background: "rgba(16,20,28,0.92)",
        border: "3px solid #0a0c10",
        borderRadius: "16px",
        boxShadow: "6px 6px 0 #0a0c10",
        margin: "40px 0",
      },
    });

    el("div", {
      parent: panel,
      text: "PRE-MATCH LOBBY",
      style: {
        font: "900 34px/1 'Segoe UI', system-ui, sans-serif",
        letterSpacing: "0.06em",
        color: "#cdeb6e",
        textShadow: "3px 3px 0 #0a0c10",
      },
    });

    this.buildMapPicker(panel);
    this.buildModePicker(panel);
    this.buildBotSlider(panel);
    this.buildDifficulty(panel);
    this.buildClassSlot(panel);
    this.buildHardcore(panel);
    this.buildKillcamToggle(panel);
    this.buildFooter(panel);

    return overlay;
  }

  private buildKillcamToggle(parent: HTMLElement): void {
    const sec = this.section(parent);
    const label = el("label", {
      parent: sec,
      style: {
        display: "flex",
        alignItems: "center",
        gap: "10px",
        cursor: "pointer",
        pointerEvents: "auto",
        font: "700 15px/1 'Segoe UI', system-ui, sans-serif",
      },
    });
    const enabled = this.storage.getSettings().killcam !== false;
    const check = el("input", {
      parent: label,
      attrs: { type: "checkbox" },
      style: { width: "18px", height: "18px", accentColor: "#9fd13e", pointerEvents: "auto" },
    });
    check.checked = enabled;
    el("span", {
      parent: label,
      text: "KILLCAM",
      style: { letterSpacing: "0.1em", color: "#e6edf5" },
    });
    check.addEventListener("change", () => {
      this.storage.updateSettings({ killcam: check.checked });
    });
  }

  private sectionLabel(parent: HTMLElement, text: string): void {
    el("div", {
      parent,
      text,
      style: {
        font: "700 13px/1 'Segoe UI', system-ui, sans-serif",
        letterSpacing: "0.14em",
        textTransform: "uppercase",
        color: "#9fb0c4",
        marginBottom: "8px",
      },
    });
  }

  private section(parent: HTMLElement): HTMLElement {
    return el("div", { parent, style: { display: "flex", flexDirection: "column" } });
  }

  // ---- Map picker ----
  private buildMapPicker(parent: HTMLElement): void {
    const sec = this.section(parent);
    this.sectionLabel(sec, "Map");
    const grid = el("div", {
      parent: sec,
      style: {
        display: "grid",
        gridTemplateColumns: "repeat(3, 1fr)",
        gap: "12px",
      },
    });

    this.mapCards = [];
    for (const map of MAPS) {
      const card = el("div", {
        parent: grid,
        onClick: () => {
          this.mapId = map.id;
          this.refreshMapCards();
        },
        style: {
          cursor: "pointer",
          pointerEvents: "auto",
          padding: "14px",
          borderRadius: "10px",
          border: "2px solid #0a0c10",
          background: "rgba(10,12,16,0.6)",
          transition: "transform 0.08s ease",
        },
      });
      card.dataset.mapId = map.id;
      el("div", {
        parent: card,
        text: map.name,
        style: { font: "800 17px/1.1 'Segoe UI', system-ui, sans-serif", marginBottom: "6px" },
      });
      el("div", {
        parent: card,
        text: map.description,
        style: { font: "400 12px/1.4 'Segoe UI', system-ui, sans-serif", color: "#9fb0c4" },
      });
      this.mapCards.push(card);
    }
    this.refreshMapCards();
  }

  private refreshMapCards(): void {
    for (const card of this.mapCards) {
      const selected = card.dataset.mapId === this.mapId;
      card.style.background = selected ? "rgba(159,209,62,0.18)" : "rgba(10,12,16,0.6)";
      card.style.borderColor = selected ? "#cdeb6e" : "#0a0c10";
      card.style.boxShadow = selected ? "0 0 0 2px #cdeb6e inset" : "none";
    }
  }

  // ---- Mode picker ----
  private buildModePicker(parent: HTMLElement): void {
    const sec = this.section(parent);
    this.sectionLabel(sec, "Mode");
    const row = el("div", { parent: sec, style: { display: "flex", gap: "10px" } });

    this.modeButtons = [];
    const modes: Array<{ id: PreMatchConfig["mode"]; label: string }> = [
      { id: "tdm", label: "TEAM DEATHMATCH" },
      { id: "ffa", label: "FREE-FOR-ALL" },
      { id: "dom", label: "DOMINATION" },
      { id: "ctf", label: "CAPTURE THE FLAG" },
      { id: "gungame", label: "GUN GAME" },
    ];
    row.style.flexWrap = "wrap";
    for (const m of modes) {
      const b = button(m.label, () => {
        this.mode = m.id;
        this.refreshModeButtons();
      });
      b.dataset.mode = m.id;
      this.modeButtons.push(b);
      row.appendChild(b);
    }
    this.refreshModeButtons();
  }

  private refreshModeButtons(): void {
    for (const b of this.modeButtons) {
      const selected = b.dataset.mode === this.mode;
      b.style.background = selected
        ? "linear-gradient(180deg,#cdeb6e,#9fd13e)"
        : "linear-gradient(180deg,#42505f,#2c3845)";
      b.style.color = selected ? "#0a0c10" : "#e6edf5";
    }
  }

  // ---- Bot count slider ----
  private buildBotSlider(parent: HTMLElement): void {
    const sec = this.section(parent);
    this.sectionLabel(sec, "Bots");
    const row = el("div", {
      parent: sec,
      style: { display: "flex", alignItems: "center", gap: "16px" },
    });
    const input = el("input", {
      parent: row,
      attrs: {
        type: "range",
        min: "0",
        max: "16",
        step: "1",
        value: String(this.botCount),
      },
      style: { flex: "1", accentColor: "#9fd13e", pointerEvents: "auto" },
    });
    const value = el("div", {
      parent: row,
      text: String(this.botCount),
      style: {
        minWidth: "32px",
        textAlign: "center",
        font: "800 18px/1 'Segoe UI', system-ui, sans-serif",
        color: "#cdeb6e",
      },
    });
    input.addEventListener("input", () => {
      this.botCount = Number(input.value);
      value.textContent = String(this.botCount);
    });
  }

  // ---- Difficulty radios ----
  private buildDifficulty(parent: HTMLElement): void {
    const sec = this.section(parent);
    this.sectionLabel(sec, "Difficulty");
    const row = el("div", { parent: sec, style: { display: "flex", gap: "20px" } });

    for (const diff of DIFFICULTIES) {
      const label = el("label", {
        parent: row,
        style: {
          display: "flex",
          alignItems: "center",
          gap: "8px",
          cursor: "pointer",
          pointerEvents: "auto",
          textTransform: "capitalize",
          font: "600 15px/1 'Segoe UI', system-ui, sans-serif",
        },
      });
      const radio = el("input", {
        parent: label,
        attrs: { type: "radio", name: "deadshot-difficulty", value: diff },
        style: { accentColor: "#9fd13e", pointerEvents: "auto" },
      });
      radio.checked = diff === this.difficulty;
      radio.addEventListener("change", () => {
        if (radio.checked) this.difficulty = diff;
      });
      el("span", { parent: label, text: diff });
    }
  }

  // ---- Class slot selector ----
  private buildClassSlot(parent: HTMLElement): void {
    const sec = this.section(parent);
    this.sectionLabel(sec, "Class");
    const select = el("select", {
      parent: sec,
      style: {
        pointerEvents: "auto",
        cursor: "pointer",
        font: "600 15px/1 'Segoe UI', system-ui, sans-serif",
        color: "#0a0c10",
        background: "#cdeb6e",
        border: "2px solid #0a0c10",
        borderRadius: "8px",
        padding: "10px 14px",
        width: "320px",
      },
    });
    this.classSelect = select;
    select.addEventListener("change", () => {
      this.classSlot = Number(select.value);
    });
    this.refreshClasses();
  }

  /** Repopulate the class dropdown from storage (picks up edits/renames). */
  private refreshClasses(): void {
    const select = this.classSelect;
    if (!select) return;
    clearChildren(select);
    const classes = this.storage.getClasses();
    classes.forEach((cls, i) => {
      el("option", {
        parent: select,
        text: `${i + 1}. ${cls.name}`,
        attrs: { value: String(i) },
      });
    });
    this.classSlot = Math.min(this.classSlot, Math.max(0, classes.length - 1));
    select.value = String(this.classSlot);
  }

  // ---- Hardcore toggle ----
  private buildHardcore(parent: HTMLElement): void {
    const sec = this.section(parent);
    const label = el("label", {
      parent: sec,
      style: {
        display: "flex",
        alignItems: "center",
        gap: "10px",
        cursor: "pointer",
        pointerEvents: "auto",
        font: "700 15px/1 'Segoe UI', system-ui, sans-serif",
      },
    });
    const check = el("input", {
      parent: label,
      attrs: { type: "checkbox" },
      style: { width: "18px", height: "18px", accentColor: "#e88", pointerEvents: "auto" },
    });
    check.checked = this.hardcore;
    check.addEventListener("change", () => {
      this.hardcore = check.checked;
    });
    el("span", {
      parent: label,
      text: "HARDCORE",
      style: { letterSpacing: "0.1em", color: this.hardcore ? "#e88" : "#e6edf5" },
    });
    check.addEventListener("change", () => {
      (label.lastChild as HTMLElement).style.color = check.checked ? "#e88" : "#e6edf5";
    });
  }

  // ---- Footer (Back / Start) ----
  private buildFooter(parent: HTMLElement): void {
    const row = el("div", {
      parent,
      style: {
        display: "flex",
        justifyContent: "space-between",
        marginTop: "8px",
      },
    });
    row.appendChild(
      button("BACK", () => this.opts.onBack(), {
        background: "linear-gradient(180deg,#42505f,#2c3845)",
        color: "#e6edf5",
      }),
    );
    row.appendChild(
      button("START MATCH", () => this.start(), {
        padding: "14px 32px",
        fontSize: "18px",
      }),
    );
  }

  private start(): void {
    const cfg: PreMatchConfig = {
      mapId: this.mapId,
      mode: this.mode,
      botCount: this.botCount,
      difficulty: this.difficulty,
      classSlot: this.classSlot,
      hardcore: this.hardcore,
    };
    this.storage.setMatchConfig({
      mapId: cfg.mapId,
      mode: cfg.mode,
      botCount: cfg.botCount,
      difficulty: cfg.difficulty,
      hardcore: cfg.hardcore,
    });
    this.opts.onStart(cfg);
  }

  show(): void {
    this.refreshClasses(); // reflect class renames/edits made since last shown
    this.overlay.style.display = "flex";
  }

  hide(): void {
    this.overlay.style.display = "none";
  }

  dispose(): void {
    clearChildren(this.overlay);
    this.overlay.remove();
    this.mapCards = [];
    this.modeButtons = [];
  }
}
