// HUD — the in-match heads-up display. Composes every combat widget (crosshair,
// hit marker, damage indicators, killfeed, scoreboard, streak menu) and owns the
// always-on readouts: health (bottom-left), ammo (bottom-right), the top-center
// scoreline + timer, streak progress, and a top-right radar minimap.
//
// Everything is pointer-events:none so the game keeps mouse focus, except the
// scoreboard table and the streak menu which need clicks. The integrator drives
// it via the setters below each frame; widgets are exposed where it must wire
// callbacks (streakMenu).

import { clearChildren, el } from "./dom.ts";
import { Crosshair } from "./Crosshair.ts";
import { HitMarker } from "./HitMarker.ts";
import { DamageIndicator } from "./DamageIndicator.ts";
import { Killfeed } from "./Killfeed.ts";
import { ScoreboardUI } from "./ScoreboardUI.ts";
import { StreakMenu } from "./StreakMenu.ts";
import type { KillEvent } from "../game/Match.ts";
import type { ModeId, PlayerScore } from "../game/Mode.ts";
import type { ObjectiveHud } from "../game/Objectives.ts";

export interface MinimapBlip {
  x: number;
  z: number;
  enemy: boolean;
}

const MINIMAP_SIZE = 160;
const MINIMAP_RADIUS_M = 60; // world meters mapped to the radar edge

export class HUD {
  readonly streakMenu: StreakMenu;

  private readonly layer: HTMLElement;
  private readonly crosshair: Crosshair;
  private readonly hit: HitMarker;
  private readonly damage: DamageIndicator;
  private readonly killfeed: Killfeed;
  private readonly scoreboard: ScoreboardUI;

  // Always-on readouts.
  private readonly healthFill: HTMLElement;
  private readonly healthText: HTMLElement;
  private readonly ammoMag: HTMLElement;
  private readonly ammoReserve: HTMLElement;
  private readonly weaponName: HTMLElement;
  private readonly scoreline: HTMLElement;
  private readonly timer: HTMLElement;
  private readonly streakLabel: HTMLElement;
  private readonly streakFill: HTMLElement;

  // Contextual interaction prompt ("Press E — …").
  private readonly prompt: HTMLElement;

  // Right-side scorestreak tracker (one bar per loadout streak).
  private readonly streakPanel: HTMLElement;
  private streakRows: { wrap: HTMLElement; fill: HTMLElement; label: HTMLElement }[] = [];
  private streakSig = "";

  // Objective panel (Domination points / CTF flags).
  private readonly objectivePanel: HTMLElement;
  private readonly objChipRow: HTMLElement;
  private readonly objScore: HTMLElement;
  private objChips: HTMLElement[] = [];
  private objKind: "dom" | "ctf" | null = null;

  // Minimap.
  private readonly canvas: HTMLCanvasElement;
  private readonly ctx: CanvasRenderingContext2D;

  constructor(root: HTMLElement) {
    // The HUD lives in one absolute layer so show/hide/dispose are one-liners.
    this.layer = el("div", {
      parent: root,
      style: {
        position: "absolute",
        inset: "0",
        pointerEvents: "none",
        fontFamily: "'Segoe UI', system-ui, sans-serif",
        userSelect: "none",
      },
    });

    this.crosshair = new Crosshair(this.layer);
    this.hit = new HitMarker(this.layer);
    this.damage = new DamageIndicator(this.layer);
    this.killfeed = new Killfeed(this.layer);
    this.scoreboard = new ScoreboardUI(this.layer);
    this.streakMenu = new StreakMenu(this.layer);

    // ---- Top-center: scoreline + timer ----
    const top = el("div", {
      parent: this.layer,
      style: {
        position: "absolute",
        top: "14px",
        left: "50%",
        transform: "translateX(-50%)",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: "2px",
        padding: "8px 18px",
        background: "rgba(10,12,16,0.6)",
        border: "2px solid #0a0c10",
        borderRadius: "10px",
      },
    });
    this.scoreline = el("div", {
      parent: top,
      text: "BLUE  0  —  0  RED",
      style: {
        font: "800 20px/1 'Segoe UI', system-ui, sans-serif",
        color: "#e6edf5",
        letterSpacing: "0.04em",
      },
    });
    this.timer = el("div", {
      parent: top,
      text: "0:00",
      style: {
        font: "700 14px/1 'Segoe UI', system-ui, sans-serif",
        color: "#cdeb6e",
        letterSpacing: "0.08em",
      },
    });

    // Objective row (Domination points / CTF flags), hidden in non-objective modes.
    this.objectivePanel = el("div", {
      parent: top,
      style: {
        display: "none",
        flexDirection: "column",
        alignItems: "center",
        gap: "3px",
        marginTop: "4px",
      },
    });
    this.objChipRow = el("div", {
      parent: this.objectivePanel,
      style: { display: "flex", gap: "6px" },
    });
    this.objScore = el("div", {
      parent: this.objectivePanel,
      text: "",
      style: { font: "700 12px/1 'Segoe UI', system-ui, sans-serif", color: "#9fb0c4" },
    });

    // ---- Bottom-left: health bar ----
    const hpWrap = el("div", {
      parent: this.layer,
      style: {
        position: "absolute",
        left: "20px",
        bottom: "22px",
        width: "240px",
        display: "flex",
        flexDirection: "column",
        gap: "4px",
      },
    });
    el("div", {
      parent: hpWrap,
      text: "HEALTH",
      style: {
        font: "700 11px/1 'Segoe UI', system-ui, sans-serif",
        color: "#9fb0c4",
        letterSpacing: "0.1em",
      },
    });
    const hpTrack = el("div", {
      parent: hpWrap,
      style: {
        position: "relative",
        height: "20px",
        background: "rgba(10,12,16,0.7)",
        border: "2px solid #0a0c10",
        borderRadius: "6px",
        overflow: "hidden",
      },
    });
    this.healthFill = el("div", {
      parent: hpTrack,
      style: {
        position: "absolute",
        inset: "0",
        width: "100%",
        background: "#7ed957",
        transition: "width 0.12s ease-out, background 0.12s linear",
      },
    });
    this.healthText = el("div", {
      parent: hpTrack,
      text: "100",
      style: {
        position: "absolute",
        inset: "0",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        font: "800 13px/1 'Segoe UI', system-ui, sans-serif",
        color: "#0a0c10",
        textShadow: "0 1px 0 rgba(255,255,255,0.3)",
      },
    });

    // ---- Bottom-right: ammo + weapon ----
    const ammoWrap = el("div", {
      parent: this.layer,
      style: {
        position: "absolute",
        right: "24px",
        bottom: "22px",
        display: "flex",
        flexDirection: "column",
        alignItems: "flex-end",
        gap: "2px",
      },
    });
    this.weaponName = el("div", {
      parent: ammoWrap,
      text: "",
      style: {
        font: "700 13px/1 'Segoe UI', system-ui, sans-serif",
        color: "#9fb0c4",
        letterSpacing: "0.08em",
      },
    });
    const ammoLine = el("div", {
      parent: ammoWrap,
      style: { display: "flex", alignItems: "baseline", gap: "6px" },
    });
    this.ammoMag = el("span", {
      parent: ammoLine,
      text: "30",
      style: {
        font: "900 40px/0.9 'Segoe UI', system-ui, sans-serif",
        color: "#e6edf5",
        textShadow: "2px 2px 0 #0a0c10",
      },
    });
    this.ammoReserve = el("span", {
      parent: ammoLine,
      text: "/ 90",
      style: { font: "700 18px/1 'Segoe UI', system-ui, sans-serif", color: "#9fb0c4" },
    });

    // ---- Above health: streak progress ----
    const streakWrap = el("div", {
      parent: this.layer,
      style: {
        position: "absolute",
        left: "20px",
        bottom: "70px",
        width: "240px",
        display: "flex",
        flexDirection: "column",
        gap: "3px",
      },
    });
    this.streakLabel = el("div", {
      parent: streakWrap,
      text: "",
      style: {
        font: "700 11px/1 'Segoe UI', system-ui, sans-serif",
        color: "#cdeb6e",
        letterSpacing: "0.06em",
      },
    });
    const streakTrack = el("div", {
      parent: streakWrap,
      style: {
        height: "8px",
        background: "rgba(10,12,16,0.7)",
        border: "2px solid #0a0c10",
        borderRadius: "5px",
        overflow: "hidden",
      },
    });
    this.streakFill = el("div", {
      parent: streakTrack,
      style: {
        width: "0%",
        height: "100%",
        background: "linear-gradient(90deg,#9fd13e,#cdeb6e)",
        transition: "width 0.2s ease-out",
      },
    });

    // ---- Center: interaction prompt ----
    // Parented to the root (not the hideable HUD layer) so pickups still prompt
    // in hardcore mode, where the rest of the HUD is hidden.
    this.prompt = el("div", {
      parent: root,
      text: "",
      style: {
        position: "absolute",
        left: "50%",
        top: "58%",
        transform: "translateX(-50%)",
        display: "none",
        padding: "8px 16px",
        background: "rgba(10,12,16,0.78)",
        border: "2px solid #cdeb6e",
        borderRadius: "10px",
        boxShadow: "3px 3px 0 #0a0c10",
        font: "800 15px/1 'Segoe UI', system-ui, sans-serif",
        color: "#e6edf5",
        letterSpacing: "0.04em",
        whiteSpace: "nowrap",
        pointerEvents: "none",
      },
    });

    // ---- Top-right: minimap ----
    this.canvas = el("canvas", {
      parent: this.layer,
      attrs: { width: `${MINIMAP_SIZE}`, height: `${MINIMAP_SIZE}` },
      style: {
        position: "absolute",
        top: "14px",
        right: "16px",
        width: `${MINIMAP_SIZE}px`,
        height: `${MINIMAP_SIZE}px`,
        border: "2px solid #0a0c10",
        borderRadius: "50%",
        background: "rgba(10,18,16,0.7)",
        boxShadow: "3px 3px 0 #0a0c10",
      },
    });
    this.ctx = this.canvas.getContext("2d")!;
    this.drawMinimapBase(false);

    // Inject the shine keyframes once (the HUD otherwise uses inline styles).
    if (!document.getElementById("deadshot-hud-style")) {
      const style = el("style", { parent: document.head });
      style.id = "deadshot-hud-style";
      style.textContent =
        "@keyframes ds-streak-shine{0%,100%{box-shadow:0 0 4px 1px rgba(205,235,110,0.5)}50%{box-shadow:0 0 14px 4px rgba(205,235,110,0.95)}}";
    }

    // ---- Right side: scorestreak tracker (below the minimap) ----
    this.streakPanel = el("div", {
      parent: this.layer,
      style: {
        position: "absolute",
        top: `${MINIMAP_SIZE + 28}px`,
        right: "16px",
        width: "176px",
        display: "flex",
        flexDirection: "column",
        gap: "6px",
      },
    });
  }

  /** Update the right-side scorestreak bars. earned ones shine. */
  setStreaks(
    entries: { name: string; cost: number; score: number; available: boolean }[],
  ): void {
    const sig = entries.map((e) => `${e.name}:${e.cost}`).join("|");
    if (sig !== this.streakSig) {
      this.streakSig = sig;
      this.rebuildStreakRows(entries.length);
    }
    entries.forEach((e, i) => {
      const row = this.streakRows[i];
      if (!row) return;
      const ratio = e.cost > 0 ? Math.max(0, Math.min(1, e.score / e.cost)) : 1;
      row.label.textContent = e.available
        ? `${e.name.toUpperCase()} ✓`
        : `${e.name.toUpperCase()}  ${Math.min(e.score, e.cost)}/${e.cost}`;
      row.fill.style.width = `${ratio * 100}%`;
      row.fill.style.background = e.available
        ? "linear-gradient(90deg,#ffe27a,#cdeb6e)"
        : "linear-gradient(90deg,#9fd13e,#cdeb6e)";
      row.wrap.style.animation = e.available ? "ds-streak-shine 1.2s ease-in-out infinite" : "none";
      row.wrap.style.borderColor = e.available ? "#cdeb6e" : "#0a0c10";
    });
  }

  private rebuildStreakRows(n: number): void {
    clearChildren(this.streakPanel);
    this.streakRows = [];
    for (let i = 0; i < n; i++) {
      const wrap = el("div", {
        parent: this.streakPanel,
        style: {
          padding: "5px 7px",
          background: "rgba(10,12,16,0.6)",
          border: "2px solid #0a0c10",
          borderRadius: "7px",
        },
      });
      const label = el("div", {
        parent: wrap,
        style: {
          font: "800 10px/1.2 'Segoe UI', system-ui, sans-serif",
          letterSpacing: "0.04em",
          color: "#e6edf5",
          marginBottom: "3px",
          whiteSpace: "nowrap",
          overflow: "hidden",
          textOverflow: "ellipsis",
        },
      });
      const track = el("div", {
        parent: wrap,
        style: {
          height: "6px",
          background: "rgba(10,12,16,0.8)",
          borderRadius: "4px",
          overflow: "hidden",
        },
      });
      const fill = el("div", {
        parent: track,
        style: {
          width: "0%",
          height: "100%",
          background: "linear-gradient(90deg,#9fd13e,#cdeb6e)",
          transition: "width 0.2s ease-out",
        },
      });
      this.streakRows.push({ wrap, fill, label });
    }
  }

  // ---- Readouts ----

  setHealth(hp: number, max: number): void {
    const ratio = max > 0 ? Math.max(0, Math.min(1, hp / max)) : 0;
    this.healthFill.style.width = `${ratio * 100}%`;
    this.healthFill.style.background = healthColor(ratio);
    this.healthText.textContent = `${Math.max(0, Math.round(hp))}`;
  }

  setAmmo(mag: number, reserve: number): void {
    this.ammoMag.textContent = `${mag}`;
    this.ammoReserve.textContent = `/ ${reserve}`;
    this.ammoMag.style.color = mag === 0 ? "#ff4d4d" : "#e6edf5";
  }

  setWeaponName(name: string): void {
    this.weaponName.textContent = name.toUpperCase();
  }

  setScoreline(blue: number, red: number, mode: ModeId): void {
    if (mode === "ffa") {
      this.scoreline.textContent = `FFA   LEADER: ${blue}`;
    } else {
      this.scoreline.textContent = `BLUE  ${blue}  —  ${red}  RED`;
    }
  }

  /** Domination/CTF objective panel; pass null to hide it. */
  setObjective(state: ObjectiveHud | null): void {
    if (!state) {
      this.objectivePanel.style.display = "none";
      return;
    }
    this.objectivePanel.style.display = "flex";
    const n = state.points?.length ?? state.flags?.length ?? 0;
    if (state.kind !== this.objKind || this.objChips.length !== n) {
      this.objKind = state.kind;
      clearChildren(this.objChipRow);
      this.objChips = [];
      for (let i = 0; i < n; i++) {
        this.objChips.push(el("span", {
          parent: this.objChipRow,
          style: {
            display: "inline-flex",
            alignItems: "center",
            justifyContent: "center",
            minWidth: "56px",
            padding: "3px 8px",
            borderRadius: "6px",
            border: "2px solid #0a0c10",
            font: "800 11px/1 'Segoe UI', system-ui, sans-serif",
            color: "#0a0c10",
          },
        }));
      }
    }
    if (state.points) {
      state.points.forEach((p, i) => {
        const c = this.objChips[i];
        if (!c) return;
        c.textContent = p.label;
        c.style.background = objColor(p.owner);
        c.style.opacity = String(0.55 + 0.45 * p.progress);
      });
    } else if (state.flags) {
      state.flags.forEach((f, i) => {
        const c = this.objChips[i];
        if (!c) return;
        c.textContent = `${f.team.toUpperCase()} ${f.status}`;
        c.style.background = objColor(f.team);
        c.style.opacity = "1";
      });
    }
    this.objScore.textContent = `${state.blue} — ${state.red}  ·  first to ${state.cap}`;
  }

  setTimer(secondsLeft: number): void {
    const s = Math.max(0, Math.floor(secondsLeft));
    const m = Math.floor(s / 60);
    const ss = (s % 60).toString().padStart(2, "0");
    this.timer.textContent = `${m}:${ss}`;
  }

  setStreakProgress(score: number, nextName: string | null, nextCost: number | null): void {
    if (!nextName || nextCost === null) {
      this.streakLabel.textContent = "MAX STREAK READY";
      this.streakFill.style.width = "100%";
      return;
    }
    const ratio = nextCost > 0 ? Math.max(0, Math.min(1, score / nextCost)) : 0;
    this.streakLabel.textContent = `NEXT: ${nextName.toUpperCase()} (${score}/${nextCost})`;
    this.streakFill.style.width = `${ratio * 100}%`;
  }

  /** Show/hide the centered interaction prompt. Pass null to hide. */
  setPrompt(text: string | null): void {
    if (text) {
      this.prompt.textContent = text;
      this.prompt.style.display = "block";
    } else {
      this.prompt.style.display = "none";
    }
  }

  // ---- Widget passthroughs ----

  setSpread(px: number): void {
    this.crosshair.setSpread(px);
  }

  hitMarker(headshot: boolean): void {
    this.hit.show(headshot);
  }

  damageFrom(angleRad: number): void {
    this.damage.show(angleRad);
  }

  addKill(e: KillEvent): void {
    this.killfeed.add(e);
  }

  showScoreboard(visible: boolean): void {
    this.scoreboard.setVisible(visible);
  }

  updateScoreboard(rows: PlayerScore[], blue: number, red: number, mode: ModeId): void {
    // The scoreboard table only distinguishes FFA from team layouts.
    this.scoreboard.update(rows, blue, red, mode === "ffa" ? "ffa" : "tdm");
  }

  // ---- Minimap ----

  setMinimap(
    player: { x: number; z: number; yaw: number },
    blips: MinimapBlip[],
    bounds: { minX: number; maxX: number; minZ: number; maxZ: number },
    jammed: boolean,
  ): void {
    const ctx = this.ctx;
    const c = MINIMAP_SIZE / 2;
    this.drawMinimapBase(jammed);

    // Clip to the radar circle so blips never spill past the edge.
    ctx.save();
    ctx.beginPath();
    ctx.arc(c, c, c - 4, 0, Math.PI * 2);
    ctx.clip();

    if (!jammed) {
      // Map the world so the radar's "up" is north (-Z) and rotates with yaw so
      // it stays player-relative ("up" = where the player faces).
      const scale = (c - 8) / MINIMAP_RADIUS_M;
      const cosY = Math.cos(-player.yaw);
      const sinY = Math.sin(-player.yaw);

      drawMapOutline(ctx, c, scale, cosY, sinY, player, bounds);

      for (const b of blips) {
        if (!b.enemy) continue;
        const dx = b.x - player.x;
        const dz = b.z - player.z;
        // Rotate into player-facing frame, then to screen (screen y grows down).
        const rx = dx * cosY - dz * sinY;
        const rz = dx * sinY + dz * cosY;
        const px = c + rx * scale;
        const py = c - rz * scale;
        if (Math.hypot(px - c, py - c) > c - 6) continue; // outside radius
        ctx.fillStyle = "#ff4d4d";
        ctx.beginPath();
        ctx.arc(px, py, 3.5, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    ctx.restore();

    // Player arrow at center, pointing "up" (the radar is player-relative).
    ctx.save();
    ctx.translate(c, c);
    ctx.fillStyle = "#cdeb6e";
    ctx.strokeStyle = "#0a0c10";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(0, -7);
    ctx.lineTo(5, 6);
    ctx.lineTo(0, 3);
    ctx.lineTo(-5, 6);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();

    if (jammed) this.drawJammed();
  }

  private drawMinimapBase(jammed: boolean): void {
    const ctx = this.ctx;
    const c = MINIMAP_SIZE / 2;
    ctx.clearRect(0, 0, MINIMAP_SIZE, MINIMAP_SIZE);

    // Background disc.
    ctx.beginPath();
    ctx.arc(c, c, c - 2, 0, Math.PI * 2);
    ctx.fillStyle = jammed ? "rgba(30,12,12,0.85)" : "rgba(10,22,18,0.8)";
    ctx.fill();

    // Radar rings + crosshair grid (skip when jammed for the static look).
    if (!jammed) {
      ctx.strokeStyle = "rgba(120,200,140,0.25)";
      ctx.lineWidth = 1;
      for (const r of [c - 6, (c - 6) * 0.66, (c - 6) * 0.33]) {
        ctx.beginPath();
        ctx.arc(c, c, r, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.beginPath();
      ctx.moveTo(c, 6);
      ctx.lineTo(c, MINIMAP_SIZE - 6);
      ctx.moveTo(6, c);
      ctx.lineTo(MINIMAP_SIZE - 6, c);
      ctx.stroke();
    }
  }

  private drawJammed(): void {
    const ctx = this.ctx;
    const c = MINIMAP_SIZE / 2;
    ctx.save();
    ctx.beginPath();
    ctx.arc(c, c, c - 4, 0, Math.PI * 2);
    ctx.clip();

    // Static noise speckle.
    for (let i = 0; i < 240; i++) {
      const x = Math.random() * MINIMAP_SIZE;
      const y = Math.random() * MINIMAP_SIZE;
      ctx.fillStyle = `rgba(255,255,255,${Math.random() * 0.25})`;
      ctx.fillRect(x, y, 2, 2);
    }

    ctx.fillStyle = "#ff4d4d";
    ctx.font = "800 14px 'Segoe UI', system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText("NO SIGNAL", c, c);
    ctx.restore();
  }

  // ---- Lifecycle ----

  show(): void {
    this.layer.style.display = "block";
  }

  hide(): void {
    this.setPrompt(null);
    this.layer.style.display = "none";
  }

  dispose(): void {
    this.prompt.remove();
    this.layer.remove();
  }
}

/** Team/owner color for the objective chips. */
function objColor(owner: string): string {
  return owner === "blue" ? "#7ab8ff" : owner === "red" ? "#ff7a7a" : "#9aa0a8";
}

/** Green at full health, ramping through yellow to red as it drops. */
function healthColor(ratio: number): string {
  // Hue 120 (green) -> 0 (red).
  const hue = Math.round(120 * ratio);
  return `hsl(${hue}, 75%, 52%)`;
}

/** Draw the static map boundary as a faint rotated rectangle for orientation. */
function drawMapOutline(
  ctx: CanvasRenderingContext2D,
  c: number,
  scale: number,
  cosY: number,
  sinY: number,
  player: { x: number; z: number },
  bounds: { minX: number; maxX: number; minZ: number; maxZ: number },
): void {
  const corners = [
    [bounds.minX, bounds.minZ],
    [bounds.maxX, bounds.minZ],
    [bounds.maxX, bounds.maxZ],
    [bounds.minX, bounds.maxZ],
  ];
  ctx.strokeStyle = "rgba(120,200,140,0.4)";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  corners.forEach(([wx, wz], i) => {
    const dx = wx - player.x;
    const dz = wz - player.z;
    const rx = dx * cosY - dz * sinY;
    const rz = dx * sinY + dz * cosY;
    const px = c + rx * scale;
    const py = c - rz * scale;
    if (i === 0) ctx.moveTo(px, py);
    else ctx.lineTo(px, py);
  });
  ctx.closePath();
  ctx.stroke();
}
