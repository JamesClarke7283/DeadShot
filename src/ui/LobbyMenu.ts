// LobbyMenu — the multiplayer front-end.
//
// Two phases: CONNECT (pick a server URL + name, then Host or Join a room) and
// LOBBY (roster + host-only match settings + Ready + Start). It owns a NetClient
// for its lifetime; on the server's "start" it hands that client + the agreed
// settings/roster to the Game via onStart. Mirrors the MainMenu/PreMatch screen
// pattern (constructor(root, opts) + show/hide/dispose).

import { button, clearChildren, el } from "./dom.ts";
import { NetClient } from "../net/NetClient.ts";
import type { LobbyPlayer, LobbySettings, NetMode } from "../net/protocol.ts";
import { DEFAULT_SETTINGS } from "../net/protocol.ts";

export interface LobbyStartPayload {
  net: NetClient;
  settings: LobbySettings;
  roster: LobbyPlayer[];
  selfId: number;
  isHost: boolean;
  name: string;
}

export interface LobbyMenuOptions {
  onStart: (payload: LobbyStartPayload) => void;
  onBack: () => void;
}

const MAPS = [
  { id: "desert_town", name: "Desert Town" },
  { id: "forest_facility", name: "Forest Facility" },
  { id: "urban_docks", name: "Urban Docks" },
];

function defaultUrl(): string {
  try {
    const loc = globalThis.location;
    if (loc && loc.host) {
      const proto = loc.protocol === "https:" ? "wss:" : "ws:";
      return `${proto}//${loc.host}/ws`;
    }
  } catch { /* no location (non-browser) */ }
  return "ws://127.0.0.1:8090/ws";
}

function randomRoom(): string {
  const a = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let s = "";
  for (let i = 0; i < 4; i++) s += a[Math.floor(Math.random() * a.length)];
  return s;
}

export class LobbyMenu {
  private readonly overlay: HTMLElement;
  private readonly panel: HTMLElement;
  private net: NetClient | null = null;
  private phase: "connect" | "lobby" = "connect";
  private status = "";

  private url = defaultUrl();
  private name = "Player";
  private room = "";

  private players: LobbyPlayer[] = [];
  private hostId = -1;
  private selfId = -1;
  private settings: LobbySettings = { ...DEFAULT_SETTINGS };
  private ready = false;

  constructor(root: HTMLElement, private opts: LobbyMenuOptions) {
    this.overlay = el("div", {
      parent: root,
      style: {
        position: "absolute",
        inset: "0",
        display: "none",
        alignItems: "center",
        justifyContent: "center",
        background: "radial-gradient(120% 120% at 50% 10%, #1b2330 0%, #0a0c10 70%, #05070a 100%)",
        fontFamily: "'Segoe UI', system-ui, sans-serif",
        userSelect: "none",
        pointerEvents: "auto",
      },
    });
    this.panel = el("div", {
      parent: this.overlay,
      style: {
        display: "flex",
        flexDirection: "column",
        gap: "16px",
        padding: "32px 40px",
        minWidth: "440px",
        background: "rgba(16,20,28,0.96)",
        border: "2px solid #0a0c10",
        borderRadius: "14px",
        boxShadow: "5px 5px 0 #0a0c10",
        color: "#e6edf5",
      },
    });
    this.render();
  }

  private get isHost(): boolean {
    return this.selfId >= 0 && this.selfId === this.hostId;
  }

  // ---- Rendering ----
  private render(): void {
    clearChildren(this.panel);
    el("div", {
      parent: this.panel,
      text: "MULTIPLAYER",
      style: {
        font: "900 30px/1 'Segoe UI', system-ui, sans-serif",
        letterSpacing: "0.08em",
        color: "#cdeb6e",
      },
    });
    if (this.phase === "connect") this.renderConnect();
    else this.renderLobby();
    if (this.status) {
      el("div", {
        parent: this.panel,
        text: this.status,
        style: { font: "600 13px/1.4 'Segoe UI', system-ui", color: "#ff9b6b" },
      });
    }
  }

  private field(label: string, value: string, onInput: (v: string) => void): HTMLInputElement {
    const row = el("label", {
      parent: this.panel,
      style: { display: "flex", flexDirection: "column", gap: "5px" },
    });
    el("span", {
      parent: row,
      text: label,
      style: {
        font: "700 11px/1 'Segoe UI', system-ui",
        letterSpacing: "0.08em",
        color: "#9fb0c4",
      },
    });
    const input = el("input", {
      parent: row,
      attrs: { type: "text", value },
      style: {
        padding: "9px 11px",
        borderRadius: "8px",
        border: "2px solid #0a0c10",
        background: "#0c0f14",
        color: "#e6edf5",
        font: "600 14px/1 'Segoe UI', system-ui",
        pointerEvents: "auto",
      },
    });
    input.addEventListener("input", () => onInput(input.value));
    return input;
  }

  private renderConnect(): void {
    this.field("Server URL", this.url, (v) => this.url = v.trim());
    this.field("Your Name", this.name, (v) => this.name = v.slice(0, 24));
    this.field(
      "Room Code (blank = new room)",
      this.room,
      (v) => this.room = v.trim().toUpperCase(),
    );

    const row = el("div", {
      parent: this.panel,
      style: { display: "flex", gap: "12px", marginTop: "6px" },
    });
    row.appendChild(button("HOST GAME", () => this.connect(true), { flex: "1" }));
    row.appendChild(button("JOIN GAME", () => this.connect(false), { flex: "1" }));
    this.panel.appendChild(
      button("BACK", () => this.leaveToMenu(), {
        background: "linear-gradient(180deg,#8aa,#577)",
      }),
    );
  }

  private renderLobby(): void {
    el("div", {
      parent: this.panel,
      text: `Room ${this.room}  •  ${this.isHost ? "You are the host" : "Waiting for host"}`,
      style: { font: "700 14px/1 'Segoe UI', system-ui", color: "#cdeb6e" },
    });

    // Roster.
    const list = el("div", {
      parent: this.panel,
      style: {
        display: "flex",
        flexDirection: "column",
        gap: "4px",
        padding: "10px",
        background: "#0c0f14",
        border: "2px solid #0a0c10",
        borderRadius: "8px",
        minHeight: "60px",
      },
    });
    for (const p of this.players) {
      el("div", {
        parent: list,
        style: { display: "flex", justifyContent: "space-between", font: "600 13px/1.5 system-ui" },
        children: [
          el("span", {
            text: `${p.name}${p.id === this.selfId ? " (you)" : ""}${
              p.id === this.hostId ? " ★" : ""
            }`,
            style: {
              color: p.team === "red" ? "#ff7a7a" : p.team === "blue" ? "#7ab8ff" : "#e6edf5",
            },
          }),
          el("span", {
            text: p.ready ? "READY" : "…",
            style: { color: p.ready ? "#9fd13e" : "#9fb0c4" },
          }),
        ],
      });
    }

    if (this.isHost) this.renderHostSettings();
    else this.renderSettingsReadonly();

    const row = el("div", {
      parent: this.panel,
      style: { display: "flex", gap: "12px", marginTop: "6px" },
    });
    row.appendChild(
      button(this.ready ? "UNREADY" : "READY", () => {
        this.ready = !this.ready;
        this.net?.setReady(this.ready);
      }, { flex: "1" }),
    );
    if (this.isHost) {
      row.appendChild(button("START MATCH", () => this.net?.start(), {
        flex: "1",
        background: "linear-gradient(180deg,#ffd166,#e0a92e)",
      }));
    }
    this.panel.appendChild(
      button("LEAVE", () => this.leaveToMenu(), {
        background: "linear-gradient(180deg,#e88,#c55)",
      }),
    );
  }

  private select(
    label: string,
    options: { value: string; text: string }[],
    value: string,
    onChange: (v: string) => void,
  ): void {
    const row = el("label", {
      parent: this.panel,
      style: {
        display: "flex",
        justifyContent: "space-between",
        alignItems: "center",
        gap: "12px",
      },
    });
    el("span", { parent: row, text: label, style: { font: "600 13px/1 system-ui" } });
    const sel = el("select", {
      parent: row,
      style: {
        padding: "6px 10px",
        borderRadius: "6px",
        border: "2px solid #0a0c10",
        background: "#0c0f14",
        color: "#e6edf5",
        pointerEvents: "auto",
      },
    });
    for (const o of options) {
      const opt = el("option", { parent: sel, text: o.text, attrs: { value: o.value } });
      if (o.value === value) opt.selected = true;
    }
    sel.addEventListener("change", () => onChange(sel.value));
  }

  private renderHostSettings(): void {
    this.select(
      "Map",
      MAPS.map((m) => ({ value: m.id, text: m.name })),
      this.settings.mapId,
      (v) => {
        this.settings.mapId = v;
        this.pushSettings();
      },
    );
    this.select(
      "Mode",
      [
        { value: "tdm", text: "Team Deathmatch" },
        { value: "ffa", text: "Free-for-All" },
        { value: "dom", text: "Domination" },
        { value: "ctf", text: "Capture the Flag" },
      ],
      this.settings.mode,
      (v) => {
        this.settings.mode = (["tdm", "ffa", "dom", "ctf"].includes(v) ? v : "tdm") as NetMode;
        this.pushSettings();
      },
    );
    this.select(
      "Bots",
      Array.from({ length: 17 }, (_, i) => ({ value: `${i}`, text: `${i}` })),
      `${this.settings.botCount}`,
      (v) => {
        this.settings.botCount = Math.max(0, Math.min(16, Number(v) || 0));
        this.pushSettings();
      },
    );
    this.select(
      "Difficulty",
      [
        { value: "recruit", text: "Recruit" },
        { value: "regular", text: "Regular" },
        { value: "veteran", text: "Veteran" },
      ],
      this.settings.difficulty,
      (v) => {
        this.settings.difficulty = v as LobbySettings["difficulty"];
        this.pushSettings();
      },
    );
    this.select(
      "Hardcore",
      [{ value: "off", text: "Off" }, { value: "on", text: "On" }],
      this.settings.hardcore ? "on" : "off",
      (v) => {
        this.settings.hardcore = v === "on";
        this.pushSettings();
      },
    );
  }

  private renderSettingsReadonly(): void {
    const mapName = MAPS.find((m) => m.id === this.settings.mapId)?.name ?? this.settings.mapId;
    el("div", {
      parent: this.panel,
      text:
        `${mapName} · ${this.settings.mode.toUpperCase()} · ${this.settings.botCount} bots · ${this.settings.difficulty}${
          this.settings.hardcore ? " · hardcore" : ""
        }`,
      style: { font: "600 13px/1.4 system-ui", color: "#9fb0c4" },
    });
  }

  private pushSettings(): void {
    this.net?.setSettings(this.settings);
  }

  // ---- Networking ----
  private connect(asHost: boolean): void {
    const room = this.room || (asHost ? randomRoom() : "");
    if (!room) {
      this.status = "Enter a room code to join, or use HOST GAME to make one.";
      this.render();
      return;
    }
    this.room = room;
    this.status = `Connecting to ${this.url} …`;
    this.render();

    const net = new NetClient(this.url);
    this.net = net;
    net.on({
      onWelcome: (id) => {
        this.selfId = id;
      },
      onLobby: (players, hostId, settings) => {
        this.players = players;
        this.hostId = hostId;
        this.settings = settings;
        this.status = "";
        if (this.phase !== "lobby") this.phase = "lobby";
        this.render();
      },
      onStart: (settings, _seed, roster) => {
        this.opts.onStart({
          net,
          settings,
          roster,
          selfId: this.selfId,
          isHost: this.isHost,
          name: this.name,
        });
      },
      onError: () => {
        this.status = `Could not connect to ${this.url}. Is the server running (deno task server)?`;
        this.net = null;
        this.phase = "connect";
        this.render();
      },
      onClose: () => {
        if (this.phase === "lobby") {
          this.status = "Disconnected from server.";
          this.phase = "connect";
          this.render();
        }
      },
    });
    net.connect(room, this.name).catch(() => {/* surfaced via onError */});
  }

  private leaveToMenu(): void {
    this.net?.disconnect();
    this.net = null;
    this.phase = "connect";
    this.players = [];
    this.ready = false;
    this.status = "";
    this.render();
    this.opts.onBack();
  }

  show(): void {
    this.phase = "connect";
    this.status = "";
    this.render();
    this.overlay.style.display = "flex";
  }

  hide(): void {
    this.overlay.style.display = "none";
  }

  dispose(): void {
    this.net?.disconnect();
    clearChildren(this.overlay);
    this.overlay.remove();
  }
}
