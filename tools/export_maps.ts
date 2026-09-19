/**
 * Preserve the original playable arenas without redrawing their geometry.
 * Run: deno run -A --config ../DeadShot/deno.json tools/export_maps.ts
 * The sibling Three project is an authoring input only; Godot consumes JSON.
 */
import * as THREE from "../../DeadShot/src/three.ts";
import { MAPS } from "../../DeadShot/src/maps/maps.ts";

const output = new URL("../data/maps/", import.meta.url);
await Deno.mkdir(output, { recursive: true });

function linear(color: THREE.ColorRepresentation): number[] {
  return new THREE.Color(color).toArray();
}

for (const definition of MAPS) {
  const build = definition.build();
  build.root.updateMatrixWorld(true);
  const geometries: Record<string, unknown> = {};
  const materials: Record<string, unknown> = {};
  const nodes: Record<string, unknown>[] = [];
  const geometryIds = new Map<THREE.BufferGeometry, string>();
  const materialIds = new Map<THREE.Material, string>();

  const geometryId = (geometry: THREE.BufferGeometry): string => {
    const cached = geometryIds.get(geometry);
    if (cached) return cached;
    const id = String(geometryIds.size);
    geometryIds.set(geometry, id);
    geometries[id] = {
      positions: Array.from(geometry.getAttribute("position").array),
      normals: geometry.hasAttribute("normal")
        ? Array.from(geometry.getAttribute("normal").array)
        : [],
      uvs: geometry.hasAttribute("uv")
        ? Array.from(geometry.getAttribute("uv").array)
        : [],
      indices: geometry.index ? Array.from(geometry.index.array) : [],
    };
    return id;
  };

  const materialId = (material: THREE.Material, node: THREE.Mesh): string => {
    const cached = materialIds.get(material);
    if (cached) return cached;
    const id = String(materialIds.size);
    materialIds.set(material, id);
    const toon = material as THREE.MeshToonMaterial;
    const hull = material as THREE.ShaderMaterial;
    const outline = node.name === "__outline";
    const windStrength = node.parent?.name === "grass"
      ? 0.08
      : node.parent?.name === "trees" && node.parent.children[1] === node
      ? 0.18
      : 0;
    materials[id] = {
      name: material.name || (outline ? "outline" : "toon"),
      color: outline
        ? hull.uniforms.uColor.value.toArray()
        : toon.color.toArray(),
      emissive: toon.emissive?.toArray() ?? [0, 0, 0],
      opacity: material.opacity,
      transparent: material.transparent,
      doubleSide: material.side === THREE.DoubleSide,
      unlit: outline ||
        (material as THREE.MeshBasicMaterial).isMeshBasicMaterial === true,
      outline,
      thickness: outline ? hull.uniforms.uThickness.value : 0,
      depthTest: material.depthTest,
      receiveShadows: node.receiveShadow,
      steps: toon.gradientMap?.image?.width ?? 3,
      windStrength,
    };
    return id;
  };

  build.root.traverse((object) => {
    const mesh = object as THREE.Mesh;
    if (!mesh.isMesh) return;
    if (Array.isArray(mesh.material)) {
      throw new Error(
        `Map ${definition.id} contains an unhandled multimaterial mesh`,
      );
    }
    const geo = geometryId(mesh.geometry);
    const mat = materialId(mesh.material, mesh);
    const make = (matrix: THREE.Matrix4, suffix = "", instanced = false) => {
      nodes.push({
        name: (mesh.name || mesh.parent?.name || "mesh") + suffix,
        parent: -1,
        matrix: matrix.toArray(),
        geometry: geo,
        material: mat,
        visible: mesh.visible,
        castShadow: mesh.castShadow,
        receiveShadow: mesh.receiveShadow,
        instanced,
      });
    };
    const instances = mesh as THREE.InstancedMesh;
    if (instances.isInstancedMesh) {
      const instanceMatrix = new THREE.Matrix4();
      for (let i = 0; i < instances.count; i++) {
        instances.getMatrixAt(i, instanceMatrix);
        make(
          new THREE.Matrix4().multiplyMatrices(
            mesh.matrixWorld,
            instanceMatrix,
          ),
          `_${i}`,
          true,
        );
      }
    } else {
      make(mesh.matrixWorld);
    }
  });

  const env = build.environment;
  // Actual Game creates Scene() once; Match.build only changes background/fog.
  // It never applies MapDefinition.environment.lighting. Preserve the authored
  // metadata separately, but match the lights players actually saw in Three.
  const light: NonNullable<typeof env.lighting> = {};
  const data = {
    schema: "deadshot.geometry.v1",
    id: definition.id,
    name: definition.name,
    description: definition.description,
    source:
      "Original Three.js MapDefinition.build(), unmodified local geometry and world matrices",
    coordinateSystem:
      "right-handed, Y-up, negative-Z forward; indices are Three CCW",
    geometries,
    materials,
    nodes,
    collisionBoxes: build.collision.boxes.map((box) => ({
      min: box.min.toArray(),
      max: box.max.toArray(),
    })),
    spawns: build.spawns.map((spawn) => ({
      position: spawn.position.toArray(),
      yaw: spawn.yaw,
      team: spawn.team,
    })),
    waypoints: build.waypoints.map((point) => ({
      id: point.id,
      position: point.position.toArray(),
      neighbors: point.neighbors,
    })),
    bounds: build.bounds,
    terrain: {
      kind: definition.id === "forest_facility" ? "heightmap" : "flat",
      size: 180,
      segments: definition.id === "forest_facility" ? 100 : 1,
      amplitude: definition.id === "forest_facility" ? 3 : 0,
    },
    environment: {
      background: linear(env.background ?? 0x9fd3ff),
      fogColor: linear(env.fogColor ?? 0x9fd3ff),
      fogNear: env.fogNear ?? 40,
      fogFar: env.fogFar ?? 300,
      skyColor: linear(light.skyColor ?? 0xbfe3ff),
      groundColor: linear(light.groundColor ?? 0x4a5a3a),
      sunColor: linear(light.sunColor ?? 0xfff4e0),
      sunIntensity: light.sunIntensity ?? 2.2,
      hemiIntensity: light.hemiIntensity ?? 1,
      sunDirection: (light.sunDirection ?? new THREE.Vector3(0.5, 1, 0.35))
        .toArray(),
      exposure: 1.05,
    },
    authoredLighting: env.lighting,
  };
  await Deno.writeTextFile(
    new URL(`${definition.id}.json`, output),
    JSON.stringify(data),
  );
  console.log(
    `${definition.id}: ${nodes.length} mesh instances, ${geometryIds.size} geometries, ${build.collision.boxes.length} colliders, ${build.spawns.length} spawns, ${build.waypoints.length} waypoints`,
  );
}
