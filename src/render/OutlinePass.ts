// Inverted-hull cartoon outlines.
//
// Rather than a screen-space post pass, each outlined mesh gets a back-face
// "hull" child that shares its geometry and pushes vertices outward along their
// normals. Only back faces render (THREE.BackSide), so the hull peeks out behind
// the silhouette as a solid border. Cheap, works per-object, and composes with
// the toon materials. Skinned meshes are skipped (the static hull would not
// follow the skeleton) — characters get their outline via team-tinted geometry.

import * as THREE from "../three.ts";

const OUTLINE_NAME = "__outline";

function makeHullMaterial(
  color: THREE.ColorRepresentation,
  thickness: number,
): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    uniforms: {
      uThickness: { value: thickness },
      uColor: { value: new THREE.Color(color) },
    },
    vertexShader: /* glsl */ `
      uniform float uThickness;
      void main() {
        vec3 displaced = position + normalize(normal) * uThickness;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(displaced, 1.0);
      }
    `,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor;
      void main() { gl_FragColor = vec4(uColor, 1.0); }
    `,
    side: THREE.BackSide,
  });
}

export interface OutlineOptions {
  color?: THREE.ColorRepresentation;
  /** Hull extrusion in local units (default 0.03). */
  thickness?: number;
}

/**
 * Add a back-face outline hull as a child of `mesh`. No-op (returns null) for
 * skinned meshes or meshes lacking vertex normals. Returns the hull mesh.
 */
export function addOutline(mesh: THREE.Mesh, opts: OutlineOptions = {}): THREE.Mesh | null {
  if ((mesh as THREE.SkinnedMesh).isSkinnedMesh) return null;
  const geom = mesh.geometry;
  if (!geom || !geom.getAttribute("normal")) return null;
  // Avoid double-adding.
  if (mesh.children.some((c) => c.name === OUTLINE_NAME)) return null;

  const hull = new THREE.Mesh(
    geom,
    makeHullMaterial(opts.color ?? 0x0a0a0a, opts.thickness ?? 0.03),
  );
  hull.name = OUTLINE_NAME;
  hull.castShadow = false;
  hull.receiveShadow = false;
  // Render the hull first so the lit mesh overdraws its interior.
  hull.renderOrder = (mesh.renderOrder ?? 0) - 1;
  mesh.add(hull);
  return hull;
}

/** Recursively outline every eligible mesh under `root`. */
export function outlineHierarchy(root: THREE.Object3D, opts: OutlineOptions = {}): void {
  root.traverse((obj) => {
    const mesh = obj as THREE.Mesh;
    if (mesh.isMesh && mesh.name !== OUTLINE_NAME) addOutline(mesh, opts);
  });
}

/** Remove any outline hull children from a mesh. */
export function removeOutline(mesh: THREE.Object3D): void {
  const hulls = mesh.children.filter((c) => c.name === OUTLINE_NAME);
  for (const h of hulls) {
    mesh.remove(h);
    const m = h as THREE.Mesh;
    (m.material as THREE.Material).dispose();
  }
}
