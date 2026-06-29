// Asset loading via a shared THREE.LoadingManager.
//
// Caches GLTF models, textures and audio buffers by URL and reports aggregate
// progress (0..1) through a callback wired to the boot loading bar. All loads
// resolve to a result or reject; callers (e.g. CharacterFactory) decide whether
// to fall back procedurally on failure.

import * as THREE from "../three.ts";
import { GLTFLoader } from "../vendor/GLTFLoader.ts";
import type { GLTF } from "../vendor/GLTFLoader.ts";

export type ProgressCallback = (fraction: number, url: string) => void;

export class AssetLoader {
  readonly manager = new THREE.LoadingManager();
  private readonly gltfLoader: GLTFLoader;
  private readonly textureLoader: THREE.TextureLoader;
  private readonly audioLoader: THREE.AudioLoader;

  private readonly gltfCache = new Map<string, Promise<GLTF>>();
  private readonly textureCache = new Map<string, Promise<THREE.Texture>>();
  private readonly audioCache = new Map<string, Promise<AudioBuffer>>();

  constructor(onProgress?: ProgressCallback) {
    this.gltfLoader = new GLTFLoader(this.manager);
    this.textureLoader = new THREE.TextureLoader(this.manager);
    this.audioLoader = new THREE.AudioLoader(this.manager);
    if (onProgress) {
      this.manager.onProgress = (url, loaded, total) => {
        onProgress(total > 0 ? loaded / total : 1, url);
      };
    }
  }

  loadGLTF(url: string): Promise<GLTF> {
    const cached = this.gltfCache.get(url);
    if (cached) return cached;
    const p = this.gltfLoader.loadAsync(url);
    this.gltfCache.set(url, p);
    return p;
  }

  loadTexture(url: string, srgb = true): Promise<THREE.Texture> {
    const cached = this.textureCache.get(url);
    if (cached) return cached;
    const p = this.textureLoader.loadAsync(url).then((tex) => {
      tex.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
      return tex;
    });
    this.textureCache.set(url, p);
    return p;
  }

  loadAudio(url: string): Promise<AudioBuffer> {
    const cached = this.audioCache.get(url);
    if (cached) return cached;
    const p = this.audioLoader.loadAsync(url);
    this.audioCache.set(url, p);
    return p;
  }

  /** True if `url` is reachable (HEAD/GET ok), for probing optional assets. */
  async exists(url: string): Promise<boolean> {
    try {
      const res = await fetch(url, { method: "GET" });
      return res.ok;
    } catch {
      return false;
    }
  }
}
