// First-person weapon viewmodel: a low-poly gun (built per category) plus simple
// arms, parented to the camera. Handles ADS lerp (hip <-> centred sights),
// per-shot kick, a reload dip animation, and exposes a muzzle point for flash/
// tracer origins. Camo color tints the gun body.
//
// The viewmodel parents to the camera, so the camera must be added to the scene
// graph for it to render (Game does this).

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { WeaponCategory, WeaponDef } from "./WeaponDefinition.ts";
import type { Attachment } from "./AttachmentDefinitions.ts";
import { buildAttachmentMeshes } from "./AttachmentVisuals.ts";

const HIP_POS = new THREE.Vector3(0.22, -0.2, -0.55);
const ADS_POS = new THREE.Vector3(0, -0.13, -0.4);

export class WeaponViewmodel {
  readonly root = new THREE.Group();
  private gun = new THREE.Group();
  private muzzle = new THREE.Object3D();
  private camoMat: THREE.MeshToonMaterial;

  private ads = 0; // 0 hip … 1 ADS
  private adsTarget = 0;
  private adsSpeed = 8;
  private kick = 0;
  private reloadT = 0;
  private reloadDur = 0;
  private reloading = false;
  private meleeT = 0;
  private meleeDur = 0.3;
  private meleeing = false;
  /** Separate knife blade shown only during the melee slash (left-to-right). */
  private knifeMesh: THREE.Group;
  /** Whether the held weapon is the knife tier (suppresses muzzle/ADS). */
  private isKnifeTier = false;

  constructor(private camera: THREE.PerspectiveCamera) {
    this.camoMat = createToonMaterial({ color: 0x2b2f36 });
    this.root.add(this.gun);
    this.gun.add(this.muzzle);
    this.root.position.copy(HIP_POS);
    this.root.renderOrder = 10;
    this.knifeMesh = buildKnifeBlade();
    this.knifeMesh.visible = false;
    this.root.add(this.knifeMesh);
    camera.add(this.root);
  }

  setWeapon(
    def: WeaponDef,
    camoColor = 0x2b2f36,
    attachments: ReadonlyArray<Attachment | string> = [],
  ): void {
    this.isKnifeTier = def.id === "knife";
    // Rebuild the gun geometry for this category. Dispose the previous meshes'
    // geometry/materials first — clear() only detaches, so without this every
    // weapon swap / attachment change / editor preview leaks GPU resources.
    disposeChildren(this.gun);
    this.gun.clear();
    this.camoMat.dispose();
    this.camoMat = createToonMaterial({ color: camoColor });
    if (this.isKnifeTier) {
      // Knife tier: show a held knife blade instead of a gun.
      this.gun.add(buildKnifeBlade());
      this.gun.visible = true;
    } else {
      buildGun(this.gun, def.category, this.camoMat);
      // Mount the equipped attachments (optics, barrel, grip, mag, stock).
      this.gun.add(buildAttachmentMeshes(def.category, attachments));
    }
    this.muzzle = new THREE.Object3D();
    this.muzzle.position.copy(gunMuzzleOffset(def.category));
    this.gun.add(this.muzzle);
    this.gun.traverse((o) => {
      o.castShadow = false;
      o.receiveShadow = false;
    });
  }

  setCamo(color: number): void {
    this.camoMat.color.setHex(color);
  }

  /** Hide/show the first-person gun (e.g. during a killcam). */
  setVisible(v: boolean): void {
    this.root.visible = v;
  }

  onShot(): void {
    this.kick = Math.min(1, this.kick + 0.5);
  }

  /** Trigger a melee knife slash animation: a blade appears from the left and
   * swipes to the right across the view. */
  meleeSlash(): void {
    this.meleeing = true;
    this.meleeT = 0;
    this.knifeMesh.visible = true;
  }

  startReload(duration: number): void {
    this.reloading = true;
    this.reloadDur = Math.max(0.1, duration);
    this.reloadT = 0;
  }

  setADS(on: boolean, adsTime: number): void {
    this.adsTarget = on ? 1 : 0;
    this.adsSpeed = 1 / Math.max(0.05, adsTime);
  }

  get adsFactor(): number {
    return this.ads;
  }

  getMuzzleWorld(out: THREE.Vector3): THREE.Vector3 {
    return this.muzzle.getWorldPosition(out);
  }

  update(dt: number): void {
    // ADS lerp (knife tier has no ADS).
    if (this.isKnifeTier) {
      this.ads = 0;
      this.root.position.copy(HIP_POS);
    } else {
      this.ads = approach(this.ads, this.adsTarget, this.adsSpeed * dt);
      this.root.position.lerpVectors(HIP_POS, ADS_POS, this.ads);
    }

    // Recoil kick recovery
    this.kick = Math.max(0, this.kick - dt * 6);
    const kz = this.kick * 0.06;
    const kpitch = this.kick * 0.12;

    // Reload dip
    let dipY = 0;
    let dipRot = 0;
    if (this.reloading) {
      this.reloadT += dt;
      const p = this.reloadT / this.reloadDur;
      const s = Math.sin(Math.min(1, p) * Math.PI); // 0..1..0
      dipY = -0.12 * s;
      dipRot = 0.5 * s;
      if (this.reloadT >= this.reloadDur) this.reloading = false;
    }

    // Melee slash: a separate knife blade sweeps left-to-right across the view.
    // The held gun is hidden during the slash so the knife reads clearly.
    if (this.meleeing) {
      this.meleeT += dt;
      const p = Math.min(1, this.meleeT / this.meleeDur);
      if (p >= 1) {
        this.meleeing = false;
        this.knifeMesh.visible = false;
        this.gun.visible = !this.isKnifeTier ? true : true; // restore gun
      } else {
        // Start at the left (-0.32), sweep right (+0.32). Blade horizontal,
        // tilted in roll, sweeping across the lower-centre of the view.
        const swipe = p; // monotonic left -> right
        const arc = Math.sin(p * Math.PI); // 0..1..0 lift
        this.knifeMesh.position.set(-0.32 + 0.64 * swipe, -0.18 - 0.06 * arc, -0.5);
        // Yaw rotates from facing-left to facing-right; roll tilts at apex.
        this.knifeMesh.rotation.set(
          -0.3 + 0.6 * arc, // pitch: dip forward then back
          -1.0 + 2.0 * swipe, // yaw: left -> right
          0.8 - 1.6 * arc, // roll: tilted at apex
        );
        this.gun.visible = false; // hide gun while the knife swipes
      }
    } else {
      this.gun.visible = true;
    }

    if (!this.meleeing) {
      this.gun.position.set(0, dipY + kz, 0);
      this.gun.rotation.set(kpitch + dipRot, 0, 0);
    }
  }

  dispose(): void {
    this.camera.remove(this.root);
    this.root.traverse((o) => {
      const m = o as THREE.Mesh;
      if (m.isMesh) {
        m.geometry?.dispose();
        (m.material as THREE.Material)?.dispose();
      }
    });
  }
}

/** Dispose every mesh geometry + material under an object (outline hulls share
 * parent geometry, so a double-dispose may occur — that is harmless). */
function disposeChildren(obj: THREE.Object3D): void {
  obj.traverse((o) => {
    const m = o as THREE.Mesh;
    if (!m.isMesh) return;
    m.geometry?.dispose();
    const mat = m.material;
    if (Array.isArray(mat)) mat.forEach((x) => x.dispose());
    else (mat as THREE.Material)?.dispose();
  });
}

function approach(cur: number, target: number, maxStep: number): number {
  if (cur < target) return Math.min(target, cur + maxStep);
  if (cur > target) return Math.max(target, cur - maxStep);
  return cur;
}

function gunMuzzleOffset(cat: WeaponCategory): THREE.Vector3 {
  const len = barrelLength(cat);
  return new THREE.Vector3(0, 0.02, -len - 0.05);
}

export function barrelLength(cat: WeaponCategory): number {
  switch (cat) {
    case "sniper":
      return 0.9;
    case "marksman":
    case "lmg":
      return 0.75;
    case "launcher":
      return 0.8;
    case "assault":
      return 0.6;
    case "shotgun":
      return 0.65;
    case "smg":
      return 0.45;
    case "pistol":
      return 0.25;
  }
}

function buildGun(group: THREE.Group, cat: WeaponCategory, camo: THREE.MeshToonMaterial): void {
  const dark = createToonMaterial({ color: 0x16181d });
  const len = barrelLength(cat);

  // Receiver / body
  const body = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.12, len * 0.7), camo);
  body.position.set(0, 0, -len * 0.35);
  addOutline(body, { thickness: 0.012 });
  group.add(body);

  // Barrel
  const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, len, 8), dark);
  barrel.rotation.x = Math.PI / 2;
  barrel.position.set(0, 0.02, -len * 0.6);
  group.add(barrel);

  // Magazine (not for launcher)
  if (cat !== "launcher" && cat !== "pistol") {
    const mag = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.18, 0.08), dark);
    mag.position.set(0, -0.14, -len * 0.3);
    mag.rotation.x = 0.15;
    group.add(mag);
  }

  // Stock for long guns
  if (cat === "assault" || cat === "lmg" || cat === "sniper" || cat === "marksman") {
    const stock = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.1, 0.22), camo);
    stock.position.set(0, -0.02, 0.12);
    group.add(stock);
  }

  // Launcher warhead
  if (cat === "launcher") {
    const head = new THREE.Mesh(
      new THREE.ConeGeometry(0.07, 0.22, 8),
      createToonMaterial({ color: 0xb3202a }),
    );
    head.rotation.x = -Math.PI / 2;
    head.position.set(0, 0.02, -len - 0.1);
    group.add(head);
  }

  // Simple hands
  const skin = createToonMaterial({ color: 0xf2c79a });
  const front = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.06, 0.1), skin);
  front.position.set(0.02, -0.06, -len * 0.6);
  const back = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.06, 0.1), skin);
  back.position.set(0.02, -0.08, -len * 0.15);
  group.add(front, back);
}

/** Build a cartoon knife blade (cone blade + cylindrical handle) with outline. */
function buildKnifeBlade(): THREE.Group {
  const g = new THREE.Group();
  const blade = new THREE.Mesh(
    new THREE.ConeGeometry(0.04, 0.34, 6),
    createToonMaterial({ color: 0xdfe5ec }),
  );
  blade.rotation.x = -Math.PI / 2; // point along +Z (forward)
  blade.position.z = 0.17;
  addOutline(blade, { thickness: 0.014 });
  const handle = new THREE.Mesh(
    new THREE.CylinderGeometry(0.03, 0.03, 0.14, 8),
    createToonMaterial({ color: 0x2a2f36 }),
  );
  handle.rotation.x = Math.PI / 2;
  handle.position.z = -0.07;
  addOutline(handle, { thickness: 0.014 });
  g.add(blade, handle);
  g.traverse((o) => {
    o.castShadow = false;
    o.receiveShadow = false;
  });
  return g;
}
