// Instanced foliage with a vertex-shader wind sway.
//
// Trees (trunk + canopy) and grass blades are drawn as InstancedMesh for cheap
// density. Canopies/grass use a toon material patched (onBeforeCompile) to add a
// height-weighted sway driven by a shared uTime uniform; call updateWind(time)
// each frame. Foliage is non-collidable (players brush through it).

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";

// Shared, updated once per frame; every wind material references this object.
const windUniform = { value: 0 };

export function updateWind(time: number): void {
  windUniform.value = time;
}

/** A toon material whose upper vertices sway with the wind uniform. */
function makeWindMaterial(
  color: THREE.ColorRepresentation,
  strength = 0.15,
): THREE.MeshToonMaterial {
  const mat = createToonMaterial({ color });
  mat.onBeforeCompile = (shader) => {
    shader.uniforms.uTime = windUniform;
    shader.uniforms.uWind = { value: strength };
    shader.vertexShader = "uniform float uTime;\nuniform float uWind;\n" + shader.vertexShader;
    shader.vertexShader = shader.vertexShader.replace(
      "#include <begin_vertex>",
      `#include <begin_vertex>
       #ifdef USE_INSTANCING
         vec3 instPos = vec3(instanceMatrix[3][0], instanceMatrix[3][1], instanceMatrix[3][2]);
       #else
         vec3 instPos = vec3(0.0);
       #endif
       float sway = sin(uTime * 1.6 + instPos.x * 0.7 + instPos.z * 0.5) * uWind;
       float h = smoothstep(0.0, 2.0, position.y);
       transformed.x += sway * h;
       transformed.z += sway * 0.5 * h;`,
    );
  };
  return mat;
}

export type TreeType = "pine" | "broadleaf" | "palm";

export interface TreePlacement {
  x: number;
  z: number;
  y?: number;
  scale?: number;
  rotation?: number;
}

export interface Foliage {
  group: THREE.Group;
}

/** Build instanced trees of one type at the given placements. */
export function createTrees(
  placements: TreePlacement[],
  type: TreeType = "pine",
  trunkColor: THREE.ColorRepresentation = 0x6b4a2b,
  leafColor: THREE.ColorRepresentation = 0x356b35,
): Foliage {
  const group = new THREE.Group();
  group.name = "trees";
  const n = placements.length;
  if (n === 0) return { group };

  const trunkH = type === "palm" ? 3.2 : 1.6;
  const trunkGeo = new THREE.CylinderGeometry(0.18, 0.26, trunkH, 6);
  trunkGeo.translate(0, trunkH / 2, 0);

  let canopyGeo: THREE.BufferGeometry;
  if (type === "pine") {
    canopyGeo = new THREE.ConeGeometry(1.4, 3.0, 8);
    canopyGeo.translate(0, trunkH + 1.5, 0);
  } else if (type === "palm") {
    canopyGeo = new THREE.SphereGeometry(1.3, 7, 5);
    canopyGeo.scale(1.4, 0.5, 1.4);
    canopyGeo.translate(0, trunkH + 0.4, 0);
  } else {
    canopyGeo = new THREE.SphereGeometry(1.7, 8, 6);
    canopyGeo.translate(0, trunkH + 1.2, 0);
  }

  const trunks = new THREE.InstancedMesh(trunkGeo, createToonMaterial({ color: trunkColor }), n);
  const canopies = new THREE.InstancedMesh(canopyGeo, makeWindMaterial(leafColor, 0.18), n);
  trunks.castShadow = true;
  canopies.castShadow = true;

  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const s = new THREE.Vector3();
  const p = new THREE.Vector3();
  for (let i = 0; i < n; i++) {
    const pl = placements[i];
    const scale = pl.scale ?? 0.9 + ((i * 13) % 5) * 0.06;
    p.set(pl.x, pl.y ?? 0, pl.z);
    q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), pl.rotation ?? (i * 1.7) % Math.PI);
    s.setScalar(scale);
    m.compose(p, q, s);
    trunks.setMatrixAt(i, m);
    canopies.setMatrixAt(i, m);
  }
  trunks.instanceMatrix.needsUpdate = true;
  canopies.instanceMatrix.needsUpdate = true;
  group.add(trunks, canopies);
  return { group };
}

/** Build a patch of instanced grass blades that sway. */
export function createGrass(
  centerX: number,
  centerZ: number,
  area: number,
  count: number,
  color: THREE.ColorRepresentation = 0x4f8f3f,
  groundAt?: (x: number, z: number) => number,
): Foliage {
  const group = new THREE.Group();
  group.name = "grass";
  if (count <= 0) return { group };

  const blade = new THREE.ConeGeometry(0.06, 0.5, 3);
  blade.translate(0, 0.25, 0);
  const mesh = new THREE.InstancedMesh(blade, makeWindMaterial(color, 0.08), count);
  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const s = new THREE.Vector3();
  const p = new THREE.Vector3();
  for (let i = 0; i < count; i++) {
    // Deterministic scatter.
    const a = (i * 12.9898) % 1;
    const b = (i * 78.233) % 1;
    const x = centerX + (a - 0.5) * area;
    const z = centerZ + (b - 0.5) * area;
    p.set(x, groundAt ? groundAt(x, z) : 0, z);
    q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), (i * 2.3) % Math.PI);
    s.setScalar(0.7 + ((i * 7) % 4) * 0.15);
    m.compose(p, q, s);
    mesh.setMatrixAt(i, m);
  }
  mesh.instanceMatrix.needsUpdate = true;
  group.add(mesh);
  return { group };
}
