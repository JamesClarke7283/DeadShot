// Equipment base + shared types.
//
// "Equipment" covers thrown tacticals (flash, smoke, ...) and lethals (frag,
// c4, ...). Each instance owns an optional mesh added to ctx.root and is ticked
// each frame via update(dt, ctx); when it sets active=false the manager disposes
// it. Subclasses build their own primitive meshes (toon-shaded + outlined).

import * as THREE from "../three.ts";
import type { VFXSink, WorldQuery } from "../weapons/combat.ts";
import type { TeamId } from "../core/types.ts";
import type { ScreenEffectsApi } from "../render/ScreenEffects.ts";

/** Everything an Equipment needs to interact with the world + player. */
export interface EquipmentContext {
  world: WorldQuery;
  vfx: VFXSink;
  /** Scene node equipment meshes are parented to. */
  root: THREE.Object3D;
  /** Local-player screen effects (flash/blur/tint/deafen). */
  screen: ScreenEffectsApi;
  /** World-space position of the local player. */
  getPlayerPosition(out: THREE.Vector3): THREE.Vector3;
  /** Team of the local player (for screen-effect friendliness, etc.). */
  getPlayerTeam(): TeamId;
  /** Radar/intel hook: enemy positions revealed by a snapshot grenade. */
  onSnapshot?(enemyPositions: THREE.Vector3[]): void;
}

/** Parameters for spawning a thrown piece of equipment. */
export interface ThrowParams {
  origin: THREE.Vector3;
  /** Normalized aim direction. */
  direction: THREE.Vector3;
  /** Team of the thrower (friendly-fire rules). */
  team: TeamId;
  /** Actor id of the thrower, for kill attribution (knives, explosives). */
  sourceId?: number;
}

/** Recursively dispose geometries + materials under an object. */
export function disposeObject(obj: THREE.Object3D): void {
  obj.traverse((o) => {
    const m = o as THREE.Mesh;
    if (!m.isMesh) return;
    m.geometry?.dispose();
    const mat = m.material;
    if (Array.isArray(mat)) mat.forEach((x) => x.dispose());
    else (mat as THREE.Material | undefined)?.dispose();
  });
}

export abstract class Equipment {
  active = true;
  protected mesh: THREE.Object3D | null = null;

  /** Advance one frame. Set this.active=false when finished. */
  abstract update(dt: number, ctx: EquipmentContext): void;

  /** Remove + free the mesh. Override to clean up extra resources first. */
  dispose(ctx: EquipmentContext): void {
    if (this.mesh) {
      ctx.root.remove(this.mesh);
      disposeObject(this.mesh);
      this.mesh = null;
    }
  }
}
