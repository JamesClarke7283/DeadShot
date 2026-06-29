// ClassEditor: the Create-a-Class screen (Phase 9.2).
//
// A full-screen overlay panel that edits one of the 10 saved ClassLoadouts.
// Slot tabs switch which loadout is being edited; every change is written
// straight back to Storage (which saves), so selections persist across
// re-entry. A small self-contained Three.js preview (its own renderer, scene,
// lighting, camera + WeaponViewmodel) shows the chosen primary in the chosen
// camo, slowly rotating while the screen is visible.

import * as THREE from "../three.ts";
import { button, clearChildren, el, hexColor } from "./dom.ts";
import { CLASS_SLOTS, type ClassLoadout, type Storage } from "../persistence/Storage.ts";
import { getWeapon, WEAPONS } from "../weapons/WeaponDefinition.ts";
import type { WeaponCategory } from "../weapons/WeaponDefinition.ts";
import {
  attachmentsForSlot,
  type AttachmentSlot,
  CAMO_PALETTE,
  computeWeaponStats,
  getCamo,
  type StatModifiers,
} from "../weapons/AttachmentDefinitions.ts";
import { LETHAL_IDS, TACTICAL_IDS } from "../tacticals/EquipmentManager.ts";
import { perksByTier, type PerkTier } from "../game/Perks.ts";
import { STREAKS } from "../streaks/streaks.ts";
import { WeaponViewmodel } from "../weapons/WeaponViewmodel.ts";
import { Lighting } from "../render/Lighting.ts";

const PRIMARY_SLOTS: AttachmentSlot[] = [
  "optic",
  "barrel",
  "magazine",
  "stock",
  "grip",
  "perk",
];

const PERK_TIERS: PerkTier[] = ["blue", "red", "gold"];

// Tactical/lethal descriptions (these ids carry no metadata of their own).
const EQUIPMENT_DESC: Record<string, string> = {
  flashbang: "Blinds and deafens nearby enemies.",
  smoke: "Deploys a concealing smoke screen.",
  stun: "Slows an enemy's movement and aim.",
  snapshot: "Briefly outlines enemies through walls.",
  frag: "Cookable fragmentation grenade.",
  semtex: "Sticky timed explosive.",
  knife: "Thrown one-hit-kill blade (recoverable).",
  c4: "Remote charge — double-tap to detonate.",
  molotov: "Pool of fire that denies an area.",
  thermite: "Burning incendiary that sticks to surfaces.",
  claymore: "Proximity-triggered directional mine.",
};

const CATEGORY_LABELS: Record<WeaponCategory, string> = {
  assault: "Assault Rifles",
  smg: "SMGs",
  lmg: "LMGs",
  marksman: "Marksman",
  sniper: "Snipers",
  shotgun: "Shotguns",
  pistol: "Pistols",
  launcher: "Launchers",
};

const CATEGORY_ORDER: WeaponCategory[] = [
  "assault",
  "smg",
  "lmg",
  "marksman",
  "sniper",
  "shotgun",
  "pistol",
  "launcher",
];

function titleCase(id: string): string {
  return id
    .split(/[_\s]+/)
    .map((w) => (w.length ? w[0].toUpperCase() + w.slice(1) : w))
    .join(" ");
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

interface StatBar {
  fill: HTMLElement;
  value: HTMLElement;
}

export class ClassEditor {
  private readonly root: HTMLElement;
  private readonly storage: Storage;
  private readonly onBack: () => void;

  private panel?: HTMLElement;
  private body?: HTMLElement;
  private currentSlot = 0;
  private loadout!: ClassLoadout;

  // Live-updating regions.
  private slotTabs: HTMLButtonElement[] = [];
  private nameInput?: HTMLInputElement;
  private statBars: Record<string, StatBar> = {};
  private camoSwatches: HTMLButtonElement[] = [];
  private primaryAttachContainer?: HTMLElement;

  // Preview.
  private previewCanvas?: HTMLCanvasElement;
  private renderer?: THREE.WebGLRenderer;
  private scene?: THREE.Scene;
  private camera?: THREE.PerspectiveCamera;
  private lighting?: Lighting;
  private viewmodel?: WeaponViewmodel;
  private rafId = 0;
  private lastFrame = 0;
  private spin = 0;
  private running = false;

  constructor(root: HTMLElement, storage: Storage, opts: { onBack: () => void }) {
    this.root = root;
    this.storage = storage;
    this.onBack = opts.onBack;
  }

  show(slot?: number): void {
    if (slot !== undefined) this.currentSlot = clamp(Math.floor(slot), 0, CLASS_SLOTS - 1);
    this.loadout = this.cloneLoadout(this.storage.getClass(this.currentSlot));

    if (!this.panel) this.build();
    this.panel!.style.display = "flex";
    this.refreshAll();
    this.startLoop();
  }

  hide(): void {
    this.stopLoop();
    if (this.panel) this.panel.style.display = "none";
  }

  dispose(): void {
    this.stopLoop();
    this.viewmodel?.dispose();
    this.viewmodel = undefined;
    this.lighting?.dispose();
    this.lighting = undefined;
    this.renderer?.dispose();
    this.renderer = undefined;
    this.scene = undefined;
    this.camera = undefined;
    if (this.panel && this.panel.parentNode) this.panel.parentNode.removeChild(this.panel);
    this.panel = undefined;
  }

  // ---- Persistence ----

  private cloneLoadout(src: ClassLoadout): ClassLoadout {
    return {
      name: src.name,
      primary: { weaponId: src.primary.weaponId, attachments: [...src.primary.attachments] },
      secondary: {
        weaponId: src.secondary.weaponId,
        attachments: [...src.secondary.attachments],
      },
      tactical: src.tactical,
      lethal: src.lethal,
      fieldUpgrade: src.fieldUpgrade,
      perks: [...src.perks],
      streaks: [...src.streaks],
      camo: src.camo,
    };
  }

  /** Persist the working loadout to the active slot (Storage.setClass saves). */
  private persist(): void {
    this.storage.setClass(this.currentSlot, this.cloneLoadout(this.loadout));
  }

  // ---- DOM construction ----

  private build(): void {
    const panel = el("div", {
      parent: this.root,
      style: {
        position: "absolute",
        inset: "0",
        display: "flex",
        flexDirection: "column",
        boxSizing: "border-box",
        padding: "24px 32px",
        gap: "16px",
        overflowY: "auto",
        background: "linear-gradient(160deg,#0d1016,#171c26)",
        color: "#e8edf4",
        font: "400 14px/1.4 'Segoe UI', system-ui, sans-serif",
        pointerEvents: "auto",
        zIndex: "20",
      },
    });
    this.panel = panel;

    // Header row.
    const header = el("div", {
      parent: panel,
      style: { display: "flex", alignItems: "center", justifyContent: "space-between" },
    });
    el("h1", {
      parent: header,
      text: "CREATE A CLASS",
      style: {
        margin: "0",
        font: "800 28px/1 'Segoe UI', system-ui, sans-serif",
        letterSpacing: "0.06em",
      },
    });
    header.appendChild(button("BACK", () => {
      this.persist();
      this.hide();
      this.onBack();
    }));

    // Slot tabs.
    this.buildSlotTabs(panel);

    // Body: two columns (controls | preview). The body is rebuilt whenever the
    // active slot changes so every <select> reflects the loaded loadout, but the
    // preview canvas/renderer is created once and re-parented on each rebuild.
    const body = el("div", {
      parent: panel,
      attrs: { "data-ce-body": "1" },
      style: { display: "flex", gap: "24px", alignItems: "flex-start", flexWrap: "wrap" },
    });
    this.body = body;

    this.buildPreview(); // creates canvas + renderer once
    this.populateBody();
  }

  /** (Re)build the editable controls + aside cards, re-parenting the preview. */
  private populateBody(): void {
    const body = this.body;
    if (!body) return;
    clearChildren(body);

    const controls = el("div", {
      parent: body,
      style: { flex: "1 1 480px", display: "flex", flexDirection: "column", gap: "14px" },
    });
    const aside = el("div", {
      parent: body,
      style: { flex: "0 0 360px", display: "flex", flexDirection: "column", gap: "14px" },
    });

    this.buildNameField(controls);
    this.buildPrimarySection(controls);
    this.buildSecondarySection(controls);
    this.buildEquipmentSection(controls);
    this.buildPerksSection(controls);
    this.buildStreaksSection(controls);

    // Preview card reuses the persistent canvas.
    const previewCard = this.card(aside);
    previewCard.appendChild(this.sectionTitle("Preview"));
    if (this.previewCanvas) previewCard.appendChild(this.previewCanvas);

    this.buildCamoPicker(aside);
    this.buildStatBars(aside);

    this.refreshCamoSelection();
    this.refreshStats();
  }

  private sectionTitle(text: string): HTMLElement {
    return el("div", {
      text,
      style: {
        font: "700 13px/1 'Segoe UI', system-ui, sans-serif",
        letterSpacing: "0.08em",
        textTransform: "uppercase",
        color: "#9fd13e",
        marginBottom: "2px",
      },
    });
  }

  private card(parent: HTMLElement): HTMLElement {
    return el("div", {
      parent,
      style: {
        display: "flex",
        flexDirection: "column",
        gap: "8px",
        padding: "12px 14px",
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(255,255,255,0.08)",
        borderRadius: "10px",
      },
    });
  }

  private styleSelect(s: HTMLSelectElement): void {
    Object.assign(s.style, {
      pointerEvents: "auto",
      cursor: "pointer",
      width: "100%",
      boxSizing: "border-box",
      padding: "7px 8px",
      color: "#e8edf4",
      background: "#1c222d",
      border: "1px solid rgba(255,255,255,0.14)",
      borderRadius: "6px",
      font: "400 13px/1.2 'Segoe UI', system-ui, sans-serif",
    } as Partial<CSSStyleDeclaration>);
  }

  private labeledRow(parent: HTMLElement, label: string, control: HTMLElement): void {
    const row = el("div", {
      parent,
      style: { display: "flex", alignItems: "center", gap: "10px" },
    });
    el("label", {
      parent: row,
      text: label,
      style: { flex: "0 0 96px", color: "#aeb7c4", fontSize: "12px" },
    });
    Object.assign(control.style, { flex: "1 1 auto" } as Partial<CSSStyleDeclaration>);
    row.appendChild(control);
  }

  private buildSlotTabs(parent: HTMLElement): void {
    const row = el("div", {
      parent,
      style: { display: "flex", gap: "6px", flexWrap: "wrap" },
    });
    this.slotTabs = [];
    for (let i = 0; i < CLASS_SLOTS; i++) {
      const idx = i;
      const tab = el("button", {
        text: String(i + 1),
        style: {
          pointerEvents: "auto",
          cursor: "pointer",
          minWidth: "40px",
          padding: "8px 10px",
          borderRadius: "6px",
          border: "2px solid #0a0c10",
          font: "700 14px/1 'Segoe UI', system-ui, sans-serif",
        },
        onClick: () => this.selectSlot(idx),
      });
      this.slotTabs.push(tab);
      row.appendChild(tab);
    }
  }

  private selectSlot(slot: number): void {
    // The working copy is already persisted on each change, so just switch.
    this.currentSlot = slot;
    this.loadout = this.cloneLoadout(this.storage.getClass(slot));
    this.refreshAll();
    this.syncPreviewWeapon();
  }

  private buildNameField(parent: HTMLElement): void {
    const card = this.card(parent);
    card.appendChild(this.sectionTitle("Class Name"));
    const input = el("input", {
      attrs: { type: "text", maxlength: "24" },
      style: {
        pointerEvents: "auto",
        width: "100%",
        boxSizing: "border-box",
        padding: "9px 10px",
        color: "#e8edf4",
        background: "#1c222d",
        border: "1px solid rgba(255,255,255,0.14)",
        borderRadius: "6px",
        font: "600 15px/1.2 'Segoe UI', system-ui, sans-serif",
      },
    });
    input.value = this.loadout.name;
    input.addEventListener("input", () => {
      this.loadout.name = input.value;
      this.persist();
    });
    this.nameInput = input;
    card.appendChild(input);
  }

  private weaponSelect(selectedId: string, onChange: (id: string) => void): HTMLSelectElement {
    const sel = el("select");
    this.styleSelect(sel);
    for (const cat of CATEGORY_ORDER) {
      const group = el("optgroup");
      group.label = CATEGORY_LABELS[cat];
      for (const w of WEAPONS) {
        if (w.category !== cat) continue;
        const opt = el("option", { text: w.name });
        opt.value = w.id;
        group.appendChild(opt);
      }
      if (group.childElementCount > 0) sel.appendChild(group);
    }
    sel.value = selectedId;
    sel.addEventListener("change", () => onChange(sel.value));
    return sel;
  }

  private buildPrimarySection(parent: HTMLElement): void {
    const card = this.card(parent);
    card.appendChild(this.sectionTitle("Primary"));

    const sel = this.weaponSelect(this.loadout.primary.weaponId, (id) => {
      this.loadout.primary.weaponId = id;
      this.loadout.primary.attachments = [];
      this.persist();
      this.rebuildPrimaryAttachments();
      this.refreshStats();
      this.syncPreviewWeapon();
    });
    this.labeledRow(card, "Weapon", sel);

    const attach = el("div", {
      parent: card,
      style: { display: "flex", flexDirection: "column", gap: "6px", marginTop: "4px" },
    });
    this.primaryAttachContainer = attach;
    this.rebuildPrimaryAttachments();
  }

  private rebuildPrimaryAttachments(): void {
    const container = this.primaryAttachContainer;
    if (!container) return;
    clearChildren(container);

    for (const slot of PRIMARY_SLOTS) {
      const options = attachmentsForSlot(slot);
      const sel = el("select");
      this.styleSelect(sel);

      const none = el("option", { text: "None" });
      none.value = "";
      none.title = "Nothing equipped in this slot.";
      sel.appendChild(none);

      for (const att of options) {
        const opt = el("option", { text: this.attachmentLabel(att.name, att.modifiers) });
        opt.value = att.id;
        opt.title = att.description;
        sel.appendChild(opt);
      }

      const chosen = this.loadout.primary.attachments.find((id) =>
        options.some((a) => a.id === id)
      );
      sel.value = chosen ?? "";

      sel.addEventListener("change", () => {
        this.setPrimaryAttachment(slot, sel.value);
      });
      this.selectTitleSync(sel);

      this.labeledRow(container, titleCase(slot), sel);
    }
  }

  private attachmentLabel(name: string, modifiers: StatModifiers): string {
    const parts: string[] = [];
    for (const [k, v] of Object.entries(modifiers)) {
      if (typeof v !== "number") continue;
      parts.push(`${k} ${v}`);
    }
    return parts.length ? `${name} (${parts.join(", ")})` : name;
  }

  /** Replace whatever attachment occupied this slot with `id` ("" clears it). */
  private setPrimaryAttachment(slot: AttachmentSlot, id: string): void {
    const slotIds = new Set(attachmentsForSlot(slot).map((a) => a.id));
    const kept = this.loadout.primary.attachments.filter((a) => !slotIds.has(a));
    if (id) kept.push(id);
    this.loadout.primary.attachments = kept;
    this.persist();
    this.refreshStats();
    this.syncPreviewWeapon();
  }

  private buildSecondarySection(parent: HTMLElement): void {
    const card = this.card(parent);
    card.appendChild(this.sectionTitle("Secondary"));

    const sel = this.weaponSelect(this.loadout.secondary.weaponId, (id) => {
      this.loadout.secondary.weaponId = id;
      this.loadout.secondary.attachments = [];
      this.persist();
    });
    this.labeledRow(card, "Weapon", sel);

    // A single optic attachment select keeps the secondary lightweight.
    const optics = attachmentsForSlot("optic");
    const optSel = el("select");
    this.styleSelect(optSel);
    const none = el("option", { text: "None" });
    none.value = "";
    none.title = "Iron sights.";
    optSel.appendChild(none);
    for (const att of optics) {
      const opt = el("option", { text: att.name });
      opt.value = att.id;
      opt.title = att.description;
      optSel.appendChild(opt);
    }
    const chosen = this.loadout.secondary.attachments.find((id) => optics.some((a) => a.id === id));
    optSel.value = chosen ?? "";
    optSel.addEventListener("change", () => {
      const opticIds = new Set(optics.map((a) => a.id));
      const kept = this.loadout.secondary.attachments.filter((a) => !opticIds.has(a));
      if (optSel.value) kept.push(optSel.value);
      this.loadout.secondary.attachments = kept;
      this.persist();
    });
    this.selectTitleSync(optSel);
    this.labeledRow(card, "Optic", optSel);
  }

  /** Mirror the focused option's tooltip onto the <select> so hovering it shows
   * what the current item does. Each option carries its own `title`. */
  private selectTitleSync(sel: HTMLSelectElement): void {
    const sync = () => {
      const o = sel.selectedOptions[0];
      sel.title = (o?.title || o?.textContent) ?? "";
    };
    sel.addEventListener("change", sync);
    sync();
  }

  private idSelect(
    ids: readonly string[],
    selected: string,
    onChange: (id: string) => void,
    describe?: (id: string) => string,
  ): HTMLSelectElement {
    const sel = el("select");
    this.styleSelect(sel);
    for (const id of ids) {
      const opt = el("option", { text: titleCase(id) });
      opt.value = id;
      opt.title = describe?.(id) ?? titleCase(id);
      sel.appendChild(opt);
    }
    sel.value = selected;
    sel.addEventListener("change", () => onChange(sel.value));
    this.selectTitleSync(sel);
    return sel;
  }

  private buildEquipmentSection(parent: HTMLElement): void {
    const card = this.card(parent);
    card.appendChild(this.sectionTitle("Equipment"));

    const tac = this.idSelect(TACTICAL_IDS, this.loadout.tactical, (id) => {
      this.loadout.tactical = id;
      this.persist();
    }, (id) => EQUIPMENT_DESC[id] ?? titleCase(id));
    this.labeledRow(card, "Tactical", tac);

    const lethal = this.idSelect(LETHAL_IDS, this.loadout.lethal, (id) => {
      this.loadout.lethal = id;
      this.persist();
    }, (id) => EQUIPMENT_DESC[id] ?? titleCase(id));
    this.labeledRow(card, "Lethal", lethal);

    const fieldUpgrades = attachmentsForSlot("fieldUpgrade");
    const fuSel = el("select");
    this.styleSelect(fuSel);
    for (const att of fieldUpgrades) {
      const opt = el("option", { text: att.name });
      opt.value = att.id;
      opt.title = att.description;
      fuSel.appendChild(opt);
    }
    fuSel.value = this.loadout.fieldUpgrade;
    fuSel.addEventListener("change", () => {
      this.loadout.fieldUpgrade = fuSel.value;
      this.persist();
    });
    this.selectTitleSync(fuSel);
    this.labeledRow(card, "Field Upgrade", fuSel);
  }

  private buildPerksSection(parent: HTMLElement): void {
    const card = this.card(parent);
    card.appendChild(this.sectionTitle("Perk Package"));

    PERK_TIERS.forEach((tier, i) => {
      const perks = perksByTier(tier);
      const sel = el("select");
      this.styleSelect(sel);
      for (const p of perks) {
        const opt = el("option", { text: p.name });
        opt.value = p.id;
        opt.title = p.description;
        sel.appendChild(opt);
      }
      sel.value = this.loadout.perks[i] ?? (perks[0]?.id ?? "");
      sel.addEventListener("change", () => {
        const next = [...this.loadout.perks];
        while (next.length < PERK_TIERS.length) next.push("");
        next[i] = sel.value;
        this.loadout.perks = next;
        this.persist();
      });
      this.selectTitleSync(sel);
      this.labeledRow(card, titleCase(tier), sel);
    });
  }

  private buildStreaksSection(parent: HTMLElement): void {
    const card = this.card(parent);
    card.appendChild(this.sectionTitle("Scorestreaks (up to 3)"));

    for (let i = 0; i < 3; i++) {
      const slot = i;
      const sel = el("select");
      this.styleSelect(sel);
      const none = el("option", { text: "None" });
      none.value = "";
      none.title = "No scorestreak in this slot.";
      sel.appendChild(none);
      for (const s of STREAKS) {
        const opt = el("option", { text: `${s.name} (${s.cost})` });
        opt.value = s.id;
        opt.title = `${s.name} — earned at ${s.cost} streak score.`;
        sel.appendChild(opt);
      }
      sel.value = this.loadout.streaks[i] ?? "";
      sel.addEventListener("change", () => {
        const next = [...this.loadout.streaks];
        while (next.length < 3) next.push("");
        next[slot] = sel.value;
        this.loadout.streaks = next.filter((x) => x !== "").slice(0, 3);
        this.persist();
      });
      this.selectTitleSync(sel);
      this.labeledRow(card, `Streak ${i + 1}`, sel);
    }
  }

  private buildCamoPicker(parent: HTMLElement): void {
    const card = this.card(parent);
    card.appendChild(this.sectionTitle("Camo"));
    const grid = el("div", {
      parent: card,
      style: { display: "flex", flexWrap: "wrap", gap: "8px" },
    });
    this.camoSwatches = [];
    for (const camo of CAMO_PALETTE) {
      const sw = el("button", {
        attrs: { title: camo.name },
        style: {
          pointerEvents: "auto",
          cursor: "pointer",
          width: "40px",
          height: "40px",
          borderRadius: "8px",
          border: "2px solid #0a0c10",
          background: hexColor(camo.color),
        },
        onClick: () => {
          this.loadout.camo = camo.id;
          this.persist();
          this.refreshCamoSelection();
          this.syncPreviewCamo();
        },
      });
      (sw.dataset as DOMStringMap).camo = camo.id;
      this.camoSwatches.push(sw);
      grid.appendChild(sw);
    }
  }

  private buildStatBars(parent: HTMLElement): void {
    const card = this.card(parent);
    card.appendChild(this.sectionTitle("Primary Stats"));
    this.statBars = {};
    for (const key of ["mobility", "range", "accuracy", "damage", "control"]) {
      const row = el("div", {
        parent: card,
        style: { display: "flex", alignItems: "center", gap: "8px" },
      });
      el("label", {
        parent: row,
        text: titleCase(key),
        style: { flex: "0 0 70px", fontSize: "12px", color: "#aeb7c4" },
      });
      const track = el("div", {
        parent: row,
        style: {
          flex: "1 1 auto",
          height: "10px",
          borderRadius: "5px",
          background: "rgba(255,255,255,0.1)",
          overflow: "hidden",
        },
      });
      const fill = el("div", {
        parent: track,
        style: {
          width: "0%",
          height: "100%",
          background: "linear-gradient(90deg,#9fd13e,#cdeb6e)",
        },
      });
      const value = el("div", {
        parent: row,
        text: "0",
        style: { flex: "0 0 32px", textAlign: "right", fontSize: "12px", color: "#e8edf4" },
      });
      this.statBars[key] = { fill, value };
    }
  }

  // ---- 3D preview ----

  private buildPreview(): void {
    const canvas = el("canvas", {
      attrs: { width: "360", height: "260" },
      style: {
        width: "360px",
        height: "260px",
        maxWidth: "100%",
        borderRadius: "10px",
        background: "#0a0d12",
        display: "block",
      },
    });
    this.previewCanvas = canvas;

    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio ?? 1, 2));
    renderer.setSize(360, 260, false);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    this.renderer = renderer;

    const scene = new THREE.Scene();
    this.scene = scene;

    const camera = new THREE.PerspectiveCamera(55, 360 / 260, 0.05, 100);
    camera.position.set(0, 0, 0);
    scene.add(camera); // viewmodel parents to the camera, so add camera to scene
    this.camera = camera;

    const lighting = new Lighting({ shadowMapSize: 512, shadowRadius: 4, sunIntensity: 1.8 });
    lighting.addTo(scene);
    this.lighting = lighting;

    const viewmodel = new WeaponViewmodel(camera);
    this.viewmodel = viewmodel;

    this.syncPreviewWeapon();
  }

  private syncPreviewWeapon(): void {
    if (!this.viewmodel) return;
    const def = getWeapon(this.loadout.primary.weaponId);
    this.viewmodel.setWeapon(
      def,
      getCamo(this.loadout.camo).color,
      this.loadout.primary.attachments,
    );
  }

  private syncPreviewCamo(): void {
    this.viewmodel?.setCamo(getCamo(this.loadout.camo).color);
  }

  private startLoop(): void {
    if (this.running) return;
    this.running = true;
    this.lastFrame = typeof performance !== "undefined" ? performance.now() : Date.now();
    const tick = (now: number): void => {
      if (!this.running) return;
      const dt = Math.min(0.05, Math.max(0, (now - this.lastFrame) / 1000));
      this.lastFrame = now;
      this.spin += dt * 0.4;
      if (this.camera) {
        // Orbit the camera around the gun's hip position for a turntable look.
        this.camera.rotation.set(0, Math.sin(this.spin) * 0.5, 0);
      }
      this.viewmodel?.update(dt);
      if (this.renderer && this.scene && this.camera) {
        this.renderer.render(this.scene, this.camera);
      }
      this.rafId = requestAnimationFrame(tick);
    };
    this.rafId = requestAnimationFrame(tick);
  }

  private stopLoop(): void {
    this.running = false;
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = 0;
    }
  }

  // ---- Refresh helpers ----

  /** Reflect the active loadout across the whole panel (after a slot switch). */
  private refreshAll(): void {
    this.refreshSlotTabs();
    this.populateBody();
  }

  private refreshSlotTabs(): void {
    this.slotTabs.forEach((tab, i) => {
      const active = i === this.currentSlot;
      Object.assign(tab.style, {
        background: active ? "linear-gradient(180deg,#cdeb6e,#9fd13e)" : "rgba(255,255,255,0.06)",
        color: active ? "#0a0c10" : "#e8edf4",
        boxShadow: active ? "2px 2px 0 #0a0c10" : "none",
      } as Partial<CSSStyleDeclaration>);
    });
  }

  private refreshCamoSelection(): void {
    for (const sw of this.camoSwatches) {
      const active = (sw.dataset as DOMStringMap).camo === this.loadout.camo;
      sw.style.outline = active ? "3px solid #cdeb6e" : "none";
      sw.style.outlineOffset = "1px";
    }
  }

  private refreshStats(): void {
    const def = getWeapon(this.loadout.primary.weaponId);
    const stats = computeWeaponStats(def, this.loadout.primary.attachments);

    const mobility = clamp(stats.mobility, 0, 100);
    const range = clamp(stats.range.far, 0, 200) / 2;
    const accuracy = clamp(100 - stats.recoil.horizontal * 20, 0, 100);
    const damage = clamp(stats.damage, 0, 120) * 0.83;
    const control = clamp(100 - stats.recoil.vertical * 15, 0, 100);

    this.setBar("mobility", mobility);
    this.setBar("range", range);
    this.setBar("accuracy", accuracy);
    this.setBar("damage", damage);
    this.setBar("control", control);
  }

  private setBar(key: string, value0to100: number): void {
    const bar = this.statBars[key];
    if (!bar) return;
    const v = clamp(value0to100, 0, 100);
    bar.fill.style.width = `${v}%`;
    bar.value.textContent = String(Math.round(v));
  }
}
