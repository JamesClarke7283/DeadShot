// CharacterFactory: returns a Character, preferring a Quaternius CC0 GLTF (if
// `deno task fetch-assets` populated /public/models/quaternius/) and otherwise
// falling back to the procedural humanoid. The GLTF is loaded once and cloned
// per instance via SkeletonUtils so bots are cheap to spawn.
//
// The fallback is the guarantee: with no network / no assets the game still runs
// with fully-featured procedural characters.

import * as THREE from "../three.ts";
import type { AssetLoader } from "../core/AssetLoader.ts";
import type { AnimName, Character } from "./Character.ts";
import { ProceduralHuman, type ProceduralOptions } from "./ProceduralHuman.ts";
import { buildFace } from "./Face.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { clone as cloneSkeleton } from "../vendor/SkeletonUtils.ts";
import { teamColor, type TeamId } from "../core/types.ts";
import type { GLTF } from "../vendor/GLTFLoader.ts";

export interface CharacterFactoryOptions extends ProceduralOptions {
  /** Override the GLTF url to load (defaults to the Quaternius probe list). */
  modelUrl?: string;
  /** Force the procedural humanoid even if a model is available. */
  forceProcedural?: boolean;
}

// Candidate Quaternius model files, tried in order.
const QUATERNIUS_CANDIDATES = [
  "/models/quaternius/character.glb",
  "/models/quaternius/Character.glb",
  "/models/quaternius/character.gltf",
  "/models/quaternius/soldier.glb",
];

const CLIP_MATCHERS: Record<AnimName, RegExp> = {
  idle: /idle|stand/i,
  run: /run|walk|sprint|jog/i,
  shoot: /shoot|fire|attack|gun/i,
  die: /death|die|dead/i,
};

let cachedGLTF: GLTF | null | undefined; // undefined = not probed; null = none

async function probeGLTF(assets: AssetLoader, override?: string): Promise<GLTF | null> {
  if (override) {
    try {
      return await assets.loadGLTF(override);
    } catch {
      return null;
    }
  }
  if (cachedGLTF !== undefined) return cachedGLTF;
  for (const url of QUATERNIUS_CANDIDATES) {
    if (await assets.exists(url)) {
      try {
        cachedGLTF = await assets.loadGLTF(url);
        return cachedGLTF;
      } catch {
        // try next
      }
    }
  }
  cachedGLTF = null;
  return null;
}

/** Build a Character. Resolves to a GLTF-backed one if assets exist, else procedural. */
export async function createCharacter(
  assets: AssetLoader,
  opts: CharacterFactoryOptions = {},
): Promise<Character> {
  if (!opts.forceProcedural) {
    const gltf = await probeGLTF(assets, opts.modelUrl);
    if (gltf) {
      try {
        return new GLTFCharacter(gltf, opts);
      } catch (err) {
        console.warn("[CharacterFactory] GLTF instancing failed, using procedural:", err);
      }
    }
  }
  return new ProceduralHuman(opts);
}

/** Character wrapper around a cloned Quaternius GLTF with an animation mixer. */
class GLTFCharacter implements Character {
  readonly root: THREE.Group;
  readonly height: number;
  private mixer: THREE.AnimationMixer;
  private actions = new Map<AnimName, THREE.AnimationAction>();
  private current: THREE.AnimationAction | null = null;
  private teamMat: THREE.MeshToonMaterial | null = null;

  constructor(gltf: GLTF, opts: CharacterFactoryOptions) {
    const scene = cloneSkeleton(gltf.scene) as THREE.Group;
    this.root = new THREE.Group();
    this.root.add(scene);

    // Normalize to ~1.9m tall, feet at origin.
    const box = new THREE.Box3().setFromObject(scene);
    const size = new THREE.Vector3();
    box.getSize(size);
    const targetH = 1.9;
    const scale = size.y > 0 ? targetH / size.y : 1;
    scene.scale.setScalar(scale);
    scene.position.y = -box.min.y * scale;
    this.height = targetH;

    // Cel-ify materials + grab the largest one as the team tint target.
    let maxArea = 0;
    scene.traverse((o) => {
      const m = o as THREE.Mesh;
      if (!m.isMesh) return;
      m.castShadow = true;
      const toon = createToonMaterial({ color: 0xcfcfcf });
      const src = m.material as THREE.MeshStandardMaterial;
      if (src && "color" in src && src.color) toon.color.copy(src.color);
      if (src?.map) toon.map = src.map;
      m.material = toon;
      const area = (m.geometry?.boundingSphere?.radius ?? 0) || 1;
      if (area > maxArea) {
        maxArea = area;
        this.teamMat = toon;
      }
    });

    this.mixer = new THREE.AnimationMixer(scene);
    for (const clip of gltf.animations) {
      for (const name of Object.keys(CLIP_MATCHERS) as AnimName[]) {
        if (!this.actions.has(name) && CLIP_MATCHERS[name].test(clip.name)) {
          this.actions.set(name, this.mixer.clipAction(clip));
        }
      }
    }
    if (opts.team) this.setTeam(opts.team, opts.accentIndex ?? 0);
    this.play("idle");
  }

  setTeam(team: TeamId, accentIndex = 0): void {
    this.teamMat?.color.setHex(teamColor(team, accentIndex));
  }

  play(anim: AnimName): void {
    const next = this.actions.get(anim);
    if (!next || next === this.current) return;
    next.reset().fadeIn(0.2).play();
    this.current?.fadeOut(0.2);
    this.current = next;
  }

  update(dt: number): void {
    this.mixer.update(dt);
  }

  dispose(): void {
    this.mixer.stopAllAction();
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

/** Reset the GLTF probe cache (used by tests). */
export function _resetCharacterCache(): void {
  cachedGLTF = undefined;
}

// Re-export for convenience.
export { buildFace };
