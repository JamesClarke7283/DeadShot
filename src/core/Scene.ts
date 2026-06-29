// Active scene wrapper: owns the THREE.Scene, fog, lighting and map-swap roots.
//
// `mapRoot` holds the current map's static geometry (cleared/disposed on swap);
// `dynamicRoot` holds transient actors (players, bots, projectiles, VFX). The
// lighting's shadow frustum is told to follow a focus point each frame.

import * as THREE from "../three.ts";
import { Lighting, type LightingOptions } from "../render/Lighting.ts";

export interface EnvironmentOptions {
  background?: THREE.ColorRepresentation;
  fogColor?: THREE.ColorRepresentation;
  fogNear?: number;
  fogFar?: number;
  lighting?: LightingOptions;
}

function disposeObject(obj: THREE.Object3D): void {
  obj.traverse((node) => {
    const mesh = node as THREE.Mesh;
    if (mesh.isMesh) {
      mesh.geometry?.dispose();
      const mat = mesh.material;
      if (Array.isArray(mat)) mat.forEach((m) => m.dispose());
      else mat?.dispose();
    }
  });
}

export class Scene {
  readonly three = new THREE.Scene();
  readonly mapRoot = new THREE.Group();
  readonly dynamicRoot = new THREE.Group();
  lighting: Lighting;

  constructor(env: EnvironmentOptions = {}) {
    this.mapRoot.name = "mapRoot";
    this.dynamicRoot.name = "dynamicRoot";
    this.three.add(this.mapRoot);
    this.three.add(this.dynamicRoot);
    this.lighting = new Lighting(env.lighting);
    this.lighting.addTo(this.three);
    this.setEnvironment(env);
  }

  setEnvironment(env: EnvironmentOptions): void {
    this.three.background = new THREE.Color(env.background ?? 0x9fd3ff);
    if (env.fogColor !== undefined || env.fogNear !== undefined || env.fogFar !== undefined) {
      this.three.fog = new THREE.Fog(
        env.fogColor ?? env.background ?? 0x9fd3ff,
        env.fogNear ?? 40,
        env.fogFar ?? 300,
      );
    } else {
      this.three.fog = null;
    }
  }

  /** Replace the lighting rig (used when a map defines its own mood). */
  setLighting(opts: LightingOptions): void {
    this.three.remove(this.lighting.group);
    this.lighting.dispose();
    this.lighting = new Lighting(opts);
    this.lighting.addTo(this.three);
  }

  add(obj: THREE.Object3D): void {
    this.dynamicRoot.add(obj);
  }

  addToMap(obj: THREE.Object3D): void {
    this.mapRoot.add(obj);
  }

  clearMap(): void {
    for (const child of [...this.mapRoot.children]) {
      this.mapRoot.remove(child);
      disposeObject(child);
    }
  }

  clearDynamic(): void {
    for (const child of [...this.dynamicRoot.children]) {
      this.dynamicRoot.remove(child);
      disposeObject(child);
    }
  }

  /** Per-frame: keep shadows centred on the focus point (usually the player). */
  update(focus: THREE.Vector3): void {
    this.lighting.follow(focus);
  }
}
