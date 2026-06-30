// DesertTown — flat sandy town: adobe buildings forming alleys, a central
// mosque with a dome, market stalls, palm trees, crates/cars for cover. Long
// sightlines down the main street, tight CQB in the alleys.

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import { createFlatTerrain } from "./Terrain.ts";
import { createBuilding } from "./Building.ts";
import { createTrees, updateWind } from "./Foliage.ts";
import { createBarrier, createCar, createCrate } from "./Obstacle.ts";
import { CollisionWorld, registerColliders } from "./Collision.ts";
import type { MapBuild, MapDefinition, Waypoint } from "./MapDefinition.ts";
import { buildGridWaypoints } from "./Waypoints.ts";
import { scatterSpawns } from "./SpawnLayout.ts";

const SAND = 0xd9c08a;
const ADOBE = [0xcdb38b, 0xc7a06f, 0xd8c39a, 0xb9986a];

function marketStall(): THREE.Group {
  const g = new THREE.Group();
  const postMat = createToonMaterial({ color: 0x6b4a2b });
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    const post = new THREE.Mesh(new THREE.BoxGeometry(0.12, 2, 0.12), postMat);
    post.position.set(x, 1, z);
    post.castShadow = true;
    g.add(post);
  }
  const cloth = new THREE.Mesh(
    new THREE.BoxGeometry(2.6, 0.1, 2.6),
    createToonMaterial({ color: 0xbe4b3b }),
  );
  cloth.position.y = 2.05;
  cloth.castShadow = true;
  addOutline(cloth, { thickness: 0.03 });
  g.add(cloth);
  g.name = "stall";
  return g;
}

function mosque(): THREE.Group {
  const g = new THREE.Group();
  const base = createBuilding({
    width: 14,
    depth: 14,
    height: 6,
    color: 0xe6d3a8,
    doorWall: "south",
    doorWidth: 3,
    roof: true,
  });
  g.add(base);
  const dome = new THREE.Mesh(
    new THREE.SphereGeometry(5, 18, 12, 0, Math.PI * 2, 0, Math.PI / 2),
    createToonMaterial({ color: 0x3a86ff }),
  );
  dome.position.y = 6;
  dome.castShadow = true;
  addOutline(dome, { thickness: 0.06 });
  g.add(dome);
  // Minaret
  const minaret = new THREE.Mesh(
    new THREE.CylinderGeometry(0.8, 1.0, 12, 10),
    createToonMaterial({ color: 0xe6d3a8 }),
  );
  minaret.position.set(8, 6, 8);
  minaret.castShadow = true;
  minaret.userData.collider = true;
  g.add(minaret);
  g.name = "mosque";
  return g;
}

export const DesertTown: MapDefinition = {
  id: "desert_town",
  name: "Desert Town",
  description: "Flat sandy town — long main-street sightlines and alley CQB.",
  build(): MapBuild {
    const root = new THREE.Group();
    root.name = "DesertTown";
    const collision = new CollisionWorld();
    const terrain = createFlatTerrain(180, SAND);
    collision.setTerrain(terrain);
    root.add(terrain.mesh);

    const place = (obj: THREE.Object3D, x: number, z: number, rotY = 0) => {
      obj.position.set(x, 0, z);
      obj.rotation.y = rotY;
      root.add(obj);
      registerColliders(obj, collision);
    };

    // Buildings forming two rows with a main street between them.
    let ci = 0;
    const adobe = () => ADOBE[ci++ % ADOBE.length];
    place(
      createBuilding({ width: 12, depth: 9, height: 5, color: adobe(), doorWall: "south" }),
      -28,
      -22,
    );
    place(
      createBuilding({ width: 10, depth: 9, height: 4, color: adobe(), doorWall: "south" }),
      -12,
      -24,
    );
    place(
      createBuilding({ width: 11, depth: 10, height: 6, color: adobe(), doorWall: "south" }),
      16,
      -23,
    );
    place(
      createBuilding({ width: 9, depth: 8, height: 4, color: adobe(), doorWall: "north" }),
      30,
      -22,
    );
    place(
      createBuilding({ width: 12, depth: 9, height: 5, color: adobe(), doorWall: "north" }),
      -26,
      22,
    );
    place(
      createBuilding({ width: 10, depth: 10, height: 6, color: adobe(), doorWall: "north" }),
      -8,
      24,
    );
    place(
      createBuilding({ width: 11, depth: 9, height: 4, color: adobe(), doorWall: "north" }),
      18,
      23,
    );
    place(
      createBuilding({ width: 9, depth: 8, height: 5, color: adobe(), doorWall: "south" }),
      32,
      22,
    );

    // Central mosque.
    place(mosque(), 0, 0);

    // Market stalls clustered near the center for partial cover.
    place(marketStall(), -6, -8);
    place(marketStall(), 6, -6, 0.4);
    place(marketStall(), -5, 9, -0.3);
    place(marketStall(), 7, 8);

    // Cover props.
    place(createCar(0x7a8a3a), -18, 0, 0.3);
    place(createCar(0x8a5a2a), 20, 4, -0.5);
    for (const [x, z] of [[-2, -18], [3, -16], [-22, 12], [24, -10], [12, 14]]) {
      place(createCrate(1.2, 0xb5793b), x, z);
    }
    place(createBarrier(3), -14, 10, Math.PI / 2);
    place(createBarrier(3), 14, -12, 0);

    // Palm trees along the edges.
    const palms = [];
    for (let i = 0; i < 14; i++) {
      const a = (i / 14) * Math.PI * 2;
      palms.push({ x: Math.cos(a) * 62, z: Math.sin(a) * 62, scale: 1 + (i % 3) * 0.15 });
    }
    const trees = createTrees(palms, "palm", 0x7a5a32, 0x4f8f3f);
    root.add(trees.group);

    // Perimeter wall to bound the play area.
    addPerimeter(root, collision, 72);

    const spawns = scatterSpawns(collision, {
      bounds: { minX: -70, maxX: 70, minZ: -70, maxZ: 70 },
      groundAt: (x, z) => terrain.sampleHeight(x, z),
    });

    const waypoints: Waypoint[] = buildGridWaypoints(collision, {
      minX: -64,
      maxX: 64,
      minZ: -64,
      maxZ: 64,
      spacing: 6,
      groundAt: (x, z) => terrain.sampleHeight(x, z),
    });

    return {
      root,
      collision,
      spawns,
      waypoints,
      environment: {
        background: 0xf0d8a8,
        fogColor: 0xe8d4a0,
        fogNear: 70,
        fogFar: 260,
        lighting: {
          skyColor: 0xffe6b0,
          groundColor: 0x8a7a4a,
          sunColor: 0xfff0d0,
          sunIntensity: 2.6,
          hemiIntensity: 1.1,
          sunDirection: new THREE.Vector3(0.6, 1, 0.3),
        },
      },
      groundAt: (x, z) => terrain.sampleHeight(x, z),
      update: (_dt, elapsed) => updateWind(elapsed),
      bounds: { minX: -70, maxX: 70, minZ: -70, maxZ: 70 },
    };
  },
};

/** A bounding wall around the play area (4 collidable slabs). */
export function addPerimeter(root: THREE.Group, collision: CollisionWorld, half: number): void {
  const mat = createToonMaterial({ color: 0xb8a079 });
  const h = 4;
  const t = 1;
  const make = (w: number, d: number, x: number, z: number) => {
    const wall = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    wall.position.set(x, h / 2, z);
    wall.castShadow = true;
    wall.receiveShadow = true;
    root.add(wall);
    collision.addObjectAABB(wall); // register only this wall
  };
  make(half * 2 + t, t, 0, -half);
  make(half * 2 + t, t, 0, half);
  make(t, half * 2 + t, -half, 0);
  make(t, half * 2 + t, half, 0);
}
