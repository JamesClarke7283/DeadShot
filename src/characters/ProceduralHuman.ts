// Low-poly cartoon humanoid assembled from primitives, with procedural
// animation (no skeleton/mixer). Implements the Character interface so it can
// stand in for the Quaternius GLTF whenever assets are unavailable — the
// guaranteed offline fallback.
//
// Layout: root origin at the feet, +Z forward. A "hips" group carries the torso,
// head (+ face), two arms (pivoted at the shoulders) and two legs (pivoted at the
// hips). Walk/idle/shoot/die are driven by sine-based limb rotations in update().

import * as THREE from "../three.ts";
import type { AnimName, Character } from "./Character.ts";
import { buildFace } from "./Face.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import { teamColor, type TeamId } from "../core/types.ts";

const HIP_Y = 0.9;
const HEAD_R = 0.2;

export interface ProceduralOptions {
  skin?: THREE.ColorRepresentation;
  uniform?: THREE.ColorRepresentation;
  gear?: THREE.ColorRepresentation;
  team?: TeamId;
  accentIndex?: number;
}

export class ProceduralHuman implements Character {
  readonly root = new THREE.Group();
  readonly height = HIP_Y + 0.88 + HEAD_R; // ~1.98m

  private hips = new THREE.Group();
  private head = new THREE.Group();
  private leftArm = new THREE.Group();
  private rightArm = new THREE.Group();
  private leftLeg = new THREE.Group();
  private rightLeg = new THREE.Group();

  private torsoMat: THREE.MeshToonMaterial;
  private headbandMat: THREE.MeshToonMaterial;
  private accentMats: THREE.MeshToonMaterial[] = [];

  private anim: AnimName = "idle";
  private phase = 0;
  private dieT = 0;

  constructor(opts: ProceduralOptions = {}) {
    const skin = opts.skin ?? 0xf2c79a;
    const uniform = opts.uniform ?? 0x4f7942;
    const gear = opts.gear ?? 0x2b2f36;

    this.torsoMat = createToonMaterial({ color: uniform });
    this.headbandMat = createToonMaterial({ color: 0x3a86ff });
    const skinMat = createToonMaterial({ color: skin });
    const gearMat = createToonMaterial({ color: gear });
    this.accentMats.push(this.torsoMat);

    this.root.add(this.hips);
    this.hips.position.y = HIP_Y;

    // Torso
    const torso = mesh(new THREE.BoxGeometry(0.5, 0.62, 0.3), this.torsoMat, 0, 0.31, 0);
    // Chest rig accent (team-colored vest stripe)
    const vest = mesh(new THREE.BoxGeometry(0.52, 0.2, 0.32), this.headbandMat, 0, 0.34, 0);
    this.hips.add(torso, vest);
    addOutline(torso);

    // Head + face
    this.head.position.set(0, 0.88, 0);
    const headMesh = mesh(new THREE.SphereGeometry(HEAD_R, 16, 16), skinMat, 0, 0, 0);
    addOutline(headMesh);
    this.head.add(headMesh);
    // Face; reuse the shared headband material so setTeam recolors it.
    const face = buildFace({ headRadius: HEAD_R, skin });
    (face.headband.material as THREE.Material).dispose();
    face.headband.material = this.headbandMat;
    this.head.add(face.group);
    this.hips.add(this.head);

    // Arms
    for (const [grp, sign] of [[this.leftArm, -1], [this.rightArm, 1]] as const) {
      grp.position.set(sign * 0.33, 0.5, 0);
      const upper = mesh(new THREE.BoxGeometry(0.15, 0.62, 0.16), gearMat, 0, -0.31, 0);
      addOutline(upper);
      const hand = mesh(new THREE.SphereGeometry(0.1, 8, 8), skinMat, 0, -0.66, 0);
      grp.add(upper, hand);
      this.hips.add(grp);
    }

    // Legs
    for (const [grp, sign] of [[this.leftLeg, -1], [this.rightLeg, 1]] as const) {
      grp.position.set(sign * 0.13, 0, 0);
      const leg = mesh(new THREE.BoxGeometry(0.18, 0.86, 0.2), gearMat, 0, -0.46, 0);
      addOutline(leg);
      const foot = mesh(
        new THREE.BoxGeometry(0.2, 0.12, 0.34),
        createToonMaterial({ color: 0x20232a }),
        0,
        -0.9,
        0.06,
      );
      addOutline(foot);
      grp.add(leg, foot);
      this.hips.add(grp);
    }

    this.root.traverse((o) => {
      o.castShadow = true;
      o.receiveShadow = false;
    });

    if (opts.team) this.setTeam(opts.team, opts.accentIndex ?? 0);
  }

  setTeam(team: TeamId, accentIndex = 0): void {
    const color = teamColor(team, accentIndex);
    this.headbandMat.color.setHex(color);
  }

  play(anim: AnimName): void {
    if (anim === this.anim) return;
    if (anim === "die") this.dieT = 0;
    this.anim = anim;
  }

  update(dt: number): void {
    this.phase += dt;
    const t = this.phase;

    // Reset to neutral, then pose per animation.
    this.leftArm.rotation.set(0, 0, 0);
    this.rightArm.rotation.set(0, 0, 0);
    this.leftLeg.rotation.set(0, 0, 0);
    this.rightLeg.rotation.set(0, 0, 0);
    this.hips.position.y = HIP_Y;
    this.hips.rotation.set(0, 0, 0);

    switch (this.anim) {
      case "idle": {
        const b = Math.sin(t * 2);
        this.hips.position.y = HIP_Y + b * 0.01;
        this.leftArm.rotation.z = 0.08;
        this.rightArm.rotation.z = -0.08;
        this.leftArm.rotation.x = b * 0.04;
        this.rightArm.rotation.x = -b * 0.04;
        break;
      }
      case "run": {
        const s = Math.sin(t * 11);
        const c = Math.sin(t * 22);
        this.leftLeg.rotation.x = s * 0.8;
        this.rightLeg.rotation.x = -s * 0.8;
        this.leftArm.rotation.x = -s * 0.7;
        this.rightArm.rotation.x = s * 0.7;
        this.hips.position.y = HIP_Y + Math.abs(c) * 0.04;
        this.hips.rotation.x = 0.12; // forward lean
        break;
      }
      case "shoot": {
        const recoil = Math.sin(t * 45) * 0.03;
        this.leftArm.rotation.x = -Math.PI / 2 + 0.15 + recoil;
        this.rightArm.rotation.x = -Math.PI / 2 + 0.1 + recoil;
        this.leftArm.rotation.z = 0.2;
        this.rightArm.rotation.z = -0.2;
        break;
      }
      case "die": {
        this.dieT = Math.min(1, this.dieT + dt * 1.6);
        const k = this.dieT;
        this.root.rotation.x = -k * (Math.PI / 2);
        this.hips.position.y = HIP_Y * (1 - k * 0.4);
        return; // keep limbs slack
      }
    }
  }

  dispose(): void {
    this.root.traverse((o) => {
      const m = o as THREE.Mesh;
      if (m.isMesh) {
        m.geometry?.dispose();
        const mat = m.material;
        if (Array.isArray(mat)) mat.forEach((x) => x.dispose());
        else mat?.dispose();
      }
    });
  }
}

function mesh(
  geom: THREE.BufferGeometry,
  mat: THREE.Material,
  x: number,
  y: number,
  z: number,
): THREE.Mesh {
  const m = new THREE.Mesh(geom, mat);
  m.position.set(x, y, z);
  return m;
}
