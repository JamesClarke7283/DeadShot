// Terrain builders: flat ground and displaced heightmap, both toon-shaded.
//
// The heightmap is driven by a deterministic sum-of-sines field (no external
// noise lib) so the visual mesh and the collision sampleHeight() agree exactly.

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import type { HeightField } from "./Collision.ts";

export interface Terrain extends HeightField {
  mesh: THREE.Mesh;
}

/** Flat ground at y=0. */
export function createFlatTerrain(
  size = 200,
  color: THREE.ColorRepresentation = 0x6fae5a,
): Terrain {
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(size, size, 1, 1),
    createToonMaterial({ color }),
  );
  mesh.rotation.x = -Math.PI / 2;
  mesh.receiveShadow = true;
  mesh.name = "terrain";
  return { mesh, sampleHeight: () => 0 };
}

/** Deterministic rolling height field. */
function heightAt(x: number, z: number, amplitude: number): number {
  const h = Math.sin(x * 0.05) * Math.cos(z * 0.045) +
    0.5 * Math.sin(x * 0.11 + 1.3) * Math.cos(z * 0.1 - 0.7) +
    0.25 * Math.sin(x * 0.21 - 0.4) * Math.cos(z * 0.19 + 0.9);
  return (h / 1.75) * amplitude;
}

/**
 * Rolling heightmap terrain. `amplitude` controls vertical relief; keep it modest
 * so slopes stay walkable.
 */
export function createHeightmapTerrain(
  size = 200,
  segments = 100,
  amplitude = 3,
  color: THREE.ColorRepresentation = 0x5f8f4e,
): Terrain {
  const geo = new THREE.PlaneGeometry(size, size, segments, segments);
  geo.rotateX(-Math.PI / 2); // into XZ plane; vertices now in world-ish space
  const pos = geo.attributes.position as THREE.BufferAttribute;
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const z = pos.getZ(i);
    pos.setY(i, heightAt(x, z, amplitude));
  }
  pos.needsUpdate = true;
  geo.computeVertexNormals();

  const mesh = new THREE.Mesh(geo, createToonMaterial({ color }));
  mesh.receiveShadow = true;
  mesh.castShadow = false;
  mesh.name = "terrain";

  return { mesh, sampleHeight: (x, z) => heightAt(x, z, amplitude) };
}
