// ForestFacility — rolling green hills dotted with concrete bunkers and a radar
// installation, ringed by dense pine forest. Medium-range firefights across the
// open hill lanes between bunkers, with the trees and cover props breaking up
// sightlines. The terrain is sloped, so everything is placed on the heightmap.

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import { createHeightmapTerrain } from "./Terrain.ts";
import { createBuilding } from "./Building.ts";
import { createGrass, createTrees, updateWind } from "./Foliage.ts";
import { createBarrel, createBarrier, createCar, createCrate } from "./Obstacle.ts";
import { CollisionWorld, registerColliders } from "./Collision.ts";
import type { TreePlacement } from "./Foliage.ts";
import type { MapBuild, MapDefinition, SpawnPoint, Waypoint } from "./MapDefinition.ts";
import { buildGridWaypoints } from "./Waypoints.ts";

const GROUND = 0x5f8f4e;
const CONCRETE = [0x8a8d91, 0x6f7378];

/** A radar installation: support pylon + a tilted open parabolic dish. */
function radarDish(): THREE.Group {
  const g = new THREE.Group();

  const pylon = new THREE.Mesh(
    new THREE.CylinderGeometry(0.5, 0.7, 6, 12),
    createToonMaterial({ color: 0x6f7378 }),
  );
  pylon.position.y = 3;
  pylon.castShadow = true;
  pylon.receiveShadow = true;
  pylon.userData.collider = true;
  addOutline(pylon, { thickness: 0.04 });
  g.add(pylon);

  // Open hemisphere dish, tilted up to face the sky.
  const dish = new THREE.Mesh(
    new THREE.SphereGeometry(2.4, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2),
    createToonMaterial({ color: 0xc8ccd0, doubleSide: true }),
  );
  dish.position.y = 6.4;
  dish.rotation.x = -Math.PI / 3; // tilt the bowl up
  dish.castShadow = true;
  addOutline(dish, { thickness: 0.05 });
  g.add(dish);

  // Small receiver stub poking out of the dish.
  const stub = new THREE.Mesh(
    new THREE.CylinderGeometry(0.08, 0.08, 1.6, 8),
    createToonMaterial({ color: 0x2a2d31 }),
  );
  stub.position.set(0, 7.4, 1.0);
  stub.rotation.x = -Math.PI / 3;
  stub.castShadow = true;
  g.add(stub);

  g.name = "radar";
  return g;
}

export const ForestFacility: MapDefinition = {
  id: "forest_facility",
  name: "Forest Facility",
  description:
    "Rolling forested hills with concrete bunkers and a radar dish — medium-range lanes.",
  build(): MapBuild {
    const root = new THREE.Group();
    root.name = "ForestFacility";
    const collision = new CollisionWorld();

    const terrain = createHeightmapTerrain(180, 100, 3, GROUND);
    collision.setTerrain(terrain);
    root.add(terrain.mesh);

    const groundAt = (x: number, z: number) => terrain.sampleHeight(x, z);

    // Place an object on the sloped terrain (y follows the heightmap).
    const place = (obj: THREE.Object3D, x: number, z: number, rotY = 0) => {
      obj.position.set(x, groundAt(x, z), z);
      obj.rotation.y = rotY;
      root.add(obj);
      registerColliders(obj, collision);
    };

    // Concrete bunkers forming medium-range firefight lanes across the hills.
    let ci = 0;
    const concrete = () => CONCRETE[ci++ % CONCRETE.length];
    place(
      createBuilding({ width: 14, depth: 10, height: 4, color: concrete(), doorWall: "south" }),
      -34,
      -30,
    );
    place(
      createBuilding({ width: 12, depth: 12, height: 5, color: concrete(), doorWall: "east" }),
      28,
      -34,
    );
    place(
      createBuilding({ width: 16, depth: 9, height: 4, color: concrete(), doorWall: "north" }),
      -30,
      30,
      0.15,
    );
    place(
      createBuilding({ width: 11, depth: 11, height: 5, color: concrete(), doorWall: "west" }),
      34,
      28,
    );
    place(
      createBuilding({ width: 18, depth: 8, height: 4, color: concrete(), doorWall: "south" }),
      2,
      -6,
      Math.PI / 2,
    );
    place(
      createBuilding({ width: 10, depth: 10, height: 5, color: concrete(), doorWall: "north" }),
      0,
      40,
    );

    // Radar installation near the center, perched on a hill.
    place(radarDish(), 6, 12);

    // Cover props scattered along the lanes.
    place(createCar(0x3f5a3a), -18, -4, 0.4);
    place(createCar(0x4a4f3a), 16, 6, -0.5);
    for (const [x, z] of [[-10, -16], [-6, -14], [12, -10], [-20, 16], [22, -16], [8, 22]]) {
      place(createCrate(1.2, 0x5b4a2b), x, z);
    }
    for (const [x, z] of [[-12, 8], [-9, 9], [18, 14], [4, -22], [-24, -10]]) {
      place(createBarrel(0x6b5a2b), x, z);
    }
    place(createBarrier(3), -16, 0, Math.PI / 2);
    place(createBarrier(3), 20, -2, 0);

    // Dense pine forest scattered across the map, avoiding the building cores.
    const blocked = (x: number, z: number) => {
      for (const [bx, bz, r] of CLEARINGS) {
        if ((x - bx) * (x - bx) + (z - bz) * (z - bz) < r * r) return true;
      }
      return false;
    };

    const pines: TreePlacement[] = [];
    const broadleaf: TreePlacement[] = [];
    let seed = 0;
    while (pines.length + broadleaf.length < 46 && seed < 600) {
      const i = seed++;
      // Deterministic pseudo-random scatter in the play area.
      const x = ((i * 73.13) % 124) - 62;
      const z = ((i * 49.71 + 17) % 124) - 62;
      if (blocked(x, z)) continue;
      const pl: TreePlacement = {
        x,
        z,
        y: groundAt(x, z),
        scale: 0.9 + ((i * 7) % 5) * 0.12,
        rotation: (i * 1.3) % Math.PI,
      };
      if (i % 4 === 0) broadleaf.push(pl);
      else pines.push(pl);
    }
    const pineTrees = createTrees(pines, "pine", 0x5b4a2b, 0x2f6b3a);
    const broadTrees = createTrees(broadleaf, "broadleaf", 0x5b4a2b, 0x3f7a45);
    root.add(pineTrees.group, broadTrees.group);

    // A couple of grass patches in the open clearings.
    root.add(createGrass(-4, -4, 24, 240, 0x4f8f3f, groundAt).group);
    root.add(createGrass(10, 20, 22, 220, 0x4a833a, groundAt).group);

    // Bounding wall around the play area.
    addPerimeter(root, collision, groundAt, 72);

    const spawns: SpawnPoint[] = [];
    for (let i = 0; i < 6; i++) {
      const bx = -50 + i * 6;
      const rx = -50 + i * 6;
      const fx = 50 - i * 8;
      const fz = -10 + (i % 2) * 20;
      spawns.push({
        position: new THREE.Vector3(bx, groundAt(bx, -58), -58),
        yaw: 0,
        team: "blue",
      });
      spawns.push({
        position: new THREE.Vector3(rx, groundAt(rx, 58), 58),
        yaw: Math.PI,
        team: "red",
      });
      spawns.push({
        position: new THREE.Vector3(fx, groundAt(fx, fz), fz),
        yaw: 0,
        team: "ffa",
      });
    }

    const waypoints: Waypoint[] = buildGridWaypoints(collision, {
      minX: -64,
      maxX: 64,
      minZ: -64,
      maxZ: 64,
      spacing: 6,
      groundAt,
    });

    return {
      root,
      collision,
      spawns,
      waypoints,
      environment: {
        background: 0xa9c6b0,
        fogColor: 0x9fb6a4,
        fogNear: 40,
        fogFar: 180,
        lighting: {
          skyColor: 0xcfe0d0,
          groundColor: 0x3a4a2a,
          sunColor: 0xfff4e0,
          sunIntensity: 2.2,
          hemiIntensity: 1.0,
          sunDirection: new THREE.Vector3(0.4, 1, 0.5),
        },
      },
      groundAt,
      update: (_dt, elapsed) => updateWind(elapsed),
      bounds: { minX: -70, maxX: 70, minZ: -70, maxZ: 70 },
    };
  },
};

// Building / radar footprints to keep trees and grass out of (cx, cz, radius).
const CLEARINGS: [number, number, number][] = [
  [-34, -30, 11],
  [28, -34, 10],
  [-30, 30, 11],
  [34, 28, 9],
  [2, -6, 12],
  [0, 40, 9],
  [6, 12, 7],
  [0, -58, 8],
  [0, 58, 8],
];

/** A bounding wall around the play area (4 collidable slabs, on the terrain). */
function addPerimeter(
  root: THREE.Group,
  collision: CollisionWorld,
  groundAt: (x: number, z: number) => number,
  half: number,
): void {
  const mat = createToonMaterial({ color: 0x6f7378 });
  const h = 4;
  const t = 1;
  const make = (w: number, d: number, x: number, z: number) => {
    const wall = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    wall.position.set(x, groundAt(x, z) + h / 2, z);
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
