// Cartoon toon-material factory.
//
// Wraps THREE.MeshToonMaterial with a shared N-step gradient ramp texture so all
// surfaces get the same banded "cel" shading. The ramp is a 1-D DataTexture read
// by the toon shader along N·L; NearestFilter gives hard steps between bands.

import * as THREE from "../three.ts";

export interface ToonOptions {
  color?: THREE.ColorRepresentation;
  /** Number of shading bands (default 3). */
  steps?: number;
  map?: THREE.Texture | null;
  transparent?: boolean;
  opacity?: number;
  emissive?: THREE.ColorRepresentation;
  /** Render both sides (used for thin/flat geometry like leaves). */
  doubleSide?: boolean;
}

const gradientCache = new Map<number, THREE.Texture>();

/** Build (and cache) a hard-stepped grayscale ramp texture with `steps` bands. */
export function gradientRamp(steps = 3): THREE.Texture {
  const clamped = Math.max(2, Math.min(8, Math.floor(steps)));
  const cached = gradientCache.get(clamped);
  if (cached) return cached;

  const data = new Uint8Array(clamped);
  for (let i = 0; i < clamped; i++) {
    // Bias the ramp brighter so cartoon surfaces stay punchy, not muddy.
    const t = i / (clamped - 1);
    data[i] = Math.round(Math.pow(t, 0.8) * 255);
  }
  const tex = new THREE.DataTexture(data, clamped, 1, THREE.RedFormat);
  tex.magFilter = THREE.NearestFilter;
  tex.minFilter = THREE.NearestFilter;
  tex.generateMipmaps = false;
  tex.needsUpdate = true;
  gradientCache.set(clamped, tex);
  return tex;
}

/** Create a cel-shaded MeshToonMaterial. */
export function createToonMaterial(opts: ToonOptions = {}): THREE.MeshToonMaterial {
  const mat = new THREE.MeshToonMaterial({
    color: opts.color ?? 0xffffff,
    gradientMap: gradientRamp(opts.steps ?? 3),
    map: opts.map ?? null,
    transparent: opts.transparent ?? false,
    opacity: opts.opacity ?? 1,
    emissive: opts.emissive ?? 0x000000,
    side: opts.doubleSide ? THREE.DoubleSide : THREE.FrontSide,
  });
  return mat;
}

/** Dispose the shared gradient ramp(s) (called on full teardown). */
export function disposeGradientCache(): void {
  for (const tex of gradientCache.values()) tex.dispose();
  gradientCache.clear();
}
