// Builds the visible geometry for equipped attachments (optics, barrel devices,
// underbarrel grips/lasers, magazines) and returns a group in the gun's local
// space. Shared by the first-person WeaponViewmodel and the Create-a-Class 3D
// preview so what you see in the editor is what you get in-game.
//
// Coordinates match WeaponViewmodel.buildGun: the barrel runs down -Z to ~-len,
// the receiver sits around the origin (top at y≈0.06), the muzzle is at ~-len.

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import { type Attachment, getAttachment } from "./AttachmentDefinitions.ts";
import type { WeaponCategory } from "./WeaponDefinition.ts";
import { barrelLength } from "./WeaponViewmodel.ts";

function idsBySlot(
  attachments: ReadonlyArray<Attachment | string>,
): Partial<Record<string, string>> {
  const out: Partial<Record<string, string>> = {};
  for (const a of attachments) {
    const id = typeof a === "string" ? a : a.id;
    try {
      out[getAttachment(id).slot] = id;
    } catch {
      // unknown id — ignore
    }
  }
  return out;
}

/** Build the attachment meshes for a weapon, in the gun's local space. */
export function buildAttachmentMeshes(
  cat: WeaponCategory,
  attachments: ReadonlyArray<Attachment | string>,
): THREE.Group {
  const g = new THREE.Group();
  const len = barrelLength(cat);
  const dark = createToonMaterial({ color: 0x16181d });
  const metal = createToonMaterial({ color: 0x30343c });
  const glass = createToonMaterial({ color: 0x213244, emissive: 0x0a1622 });
  const redDot = () => new THREE.MeshBasicMaterial({ color: 0xff3b3b });

  const slot = idsBySlot(attachments);
  const topZ = -len * 0.32; // over the receiver
  const topY = 0.085;

  // ---- Optic ----
  const optic = slot.optic;
  if (optic && optic !== "iron") {
    const mount = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.03, 0.07), dark);
    mount.position.set(0, topY, topZ);
    g.add(mount);

    if (optic === "reddot") {
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.022, 0.006, 8, 16), dark);
      ring.position.set(0, topY + 0.04, topZ);
      g.add(ring);
      const dot = new THREE.Mesh(new THREE.SphereGeometry(0.006, 8, 8), redDot());
      dot.position.set(0, topY + 0.04, topZ);
      g.add(dot);
    } else if (optic === "holo") {
      const frame = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.012, 0.05), dark);
      frame.position.set(0, topY + 0.018, topZ);
      g.add(frame);
      const pane = new THREE.Mesh(new THREE.BoxGeometry(0.055, 0.05, 0.006), glass);
      pane.position.set(0, topY + 0.05, topZ + 0.01);
      pane.rotation.x = -0.25;
      g.add(pane);
      const reticle = new THREE.Mesh(new THREE.SphereGeometry(0.006, 8, 8), redDot());
      reticle.position.set(0, topY + 0.05, topZ + 0.012);
      g.add(reticle);
    } else if (optic === "acog") {
      const tube = new THREE.Mesh(new THREE.CylinderGeometry(0.028, 0.028, 0.18, 12), metal);
      tube.rotation.x = Math.PI / 2;
      tube.position.set(0, topY + 0.045, topZ);
      addOutline(tube, { thickness: 0.01 });
      g.add(tube);
      const lens = new THREE.Mesh(new THREE.CylinderGeometry(0.026, 0.026, 0.01, 12), glass);
      lens.rotation.x = Math.PI / 2;
      lens.position.set(0, topY + 0.045, topZ + 0.085);
      g.add(lens);
      const reticle = new THREE.Mesh(new THREE.SphereGeometry(0.005, 8, 8), redDot());
      reticle.position.set(0, topY + 0.045, topZ + 0.082);
      g.add(reticle);
    }
  }

  // ---- Barrel device (at the muzzle) ----
  const barrel = slot.barrel;
  const muzzleZ = -len - 0.02;
  if (barrel === "suppressor") {
    const sup = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 0.2, 12), dark);
    sup.rotation.x = Math.PI / 2;
    sup.position.set(0, 0.02, muzzleZ - 0.08);
    addOutline(sup, { thickness: 0.012 });
    g.add(sup);
  } else if (barrel === "compensator" || barrel === "muzzlebrake") {
    const dev = new THREE.Mesh(new THREE.CylinderGeometry(0.034, 0.03, 0.07, 10), metal);
    dev.rotation.x = Math.PI / 2;
    dev.position.set(0, 0.02, muzzleZ - 0.02);
    g.add(dev);
  } else if (barrel === "longbarrel") {
    const ext = new THREE.Mesh(new THREE.CylinderGeometry(0.022, 0.022, 0.2, 10), dark);
    ext.rotation.x = Math.PI / 2;
    ext.position.set(0, 0.02, muzzleZ - 0.08);
    g.add(ext);
  }

  // ---- Underbarrel grip / laser ----
  const grip = slot.grip;
  const gripZ = -len * 0.62;
  if (grip === "foregrip") {
    const vg = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.11, 0.03), dark);
    vg.position.set(0, -0.11, gripZ);
    g.add(vg);
  } else if (grip === "angledgrip") {
    const ag = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.1, 0.05), dark);
    ag.position.set(0, -0.1, gripZ + 0.01);
    ag.rotation.x = 0.6;
    g.add(ag);
  } else if (grip === "laser") {
    const box = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.03, 0.05), dark);
    box.position.set(0.05, -0.04, gripZ);
    g.add(box);
    const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.004, 0.004, 0.5, 6), redDot());
    beam.rotation.x = Math.PI / 2;
    beam.position.set(0.05, -0.04, gripZ - 0.27);
    g.add(beam);
  }

  // ---- Magazine upgrades ----
  const mag = slot.magazine;
  if (cat !== "launcher" && cat !== "pistol") {
    const magZ = -len * 0.3;
    if (mag === "extmag") {
      const ext = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.1, 0.08), dark);
      ext.position.set(0, -0.24, magZ);
      ext.rotation.x = 0.15;
      g.add(ext);
    } else if (mag === "drum") {
      const drum = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.09, 0.07, 14), dark);
      drum.position.set(0, -0.2, magZ);
      addOutline(drum, { thickness: 0.012 });
      g.add(drum);
    }
  }

  // ---- Stock ----
  if (slot.stock === "heavystock" && cat !== "pistol") {
    const hs = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.13, 0.16), metal);
    hs.position.set(0, -0.02, 0.16);
    g.add(hs);
  }

  g.traverse((o) => {
    o.castShadow = false;
    o.receiveShadow = false;
  });
  return g;
}
