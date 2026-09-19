/** Preserve the original transient-effect mesh topology for native rendering. */
import * as THREE from "../../DeadShot/src/three.ts";
import { VFX } from "../../DeadShot/src/render/VFX.ts";
const source = new VFX(new THREE.Scene()) as unknown as Record<string, unknown>;
const output: Record<string, unknown> = {};
for (
  const name of ["sparkGeo", "holeGeo", "flashGeo", "explosionGeo", "tracerGeo"]
) {
  const geometry = source[name] as THREE.BufferGeometry;
  output[name] = {
    positions: Array.from(geometry.getAttribute("position").array),
    normals: Array.from(geometry.getAttribute("normal").array),
    uvs: Array.from(geometry.getAttribute("uv").array),
    indices: geometry.index ? Array.from(geometry.index.array) : [],
  };
}
for (
  const [name, geometry] of Object.entries({
    smokeGeo: new THREE.SphereGeometry(1, 10, 10),
    molotovGeo: new THREE.ConeGeometry(0.25, 0.7, 6),
    thermiteGeo: new THREE.SphereGeometry(0.07, 6, 6),
  })
) {
  output[name] = {
    positions: Array.from(geometry.getAttribute("position").array),
    normals: Array.from(geometry.getAttribute("normal").array),
    uvs: Array.from(geometry.getAttribute("uv").array),
    indices: geometry.index ? Array.from(geometry.index.array) : [],
  };
}
await Deno.writeTextFile(
  new URL("../data/vfx.json", import.meta.url),
  JSON.stringify(output),
);
