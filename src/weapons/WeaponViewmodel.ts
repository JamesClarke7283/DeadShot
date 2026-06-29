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

  constructor(private camera: THREE.PerspectiveCamera) {
    this.camoMat = createToonMaterial({ color: 0x2b2f36 });
    this.root.add(this.gun);
    this.gun.add(this.muzzle);
    this.root.position.copy(HIP_POS);
    this.root.renderOrder = 10;
    camera.add(this.root);
  }

  setWeapon(
    def: WeaponDef,
    camoColor = 0x2b2f36,
    attachments: ReadonlyArray<Attachment | string> = [],
  ): void {
    // Rebuild the gun geometry for this category. Dispose the previous meshes'
    // geometry/materials first — clear() only detaches, so without this every
    // weapon swap / attachment change / editor preview leaks GPU resources.
    disposeChildren(this.gun);
    this.gun.clear();
    this.camoMat.dispose();
    this.camoMat = createToonMaterial({ color: camoColor });
    buildGun(this.gun, def.category, this.camoMat);
    // Mount the equipped attachments (optics, barrel, grip, mag, stock).
    this.gun.add(buildAttachmentMeshes(def.category, attachments));
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

  onShot(): void {
    this.kick = Math.min(1, this.kick + 0.5);
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
    // ADS lerp
    this.ads = approach(this.ads, this.adsTarget, this.adsSpeed * dt);
    this.root.position.lerpVectors(HIP_POS, ADS_POS, this.ads);

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

    this.gun.position.set(0, dipY, kz);
    this.gun.rotation.set(kpitch + dipRot, 0, 0);
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
