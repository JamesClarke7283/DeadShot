// UrbanDocks — flat concrete waterfront yard: rows and stacks of shipping
// containers form cover corridors, towering cranes near the harbour edge,
// industrial warehouses anchor the corners and low planters break up the
// concrete. Tight CQB amongst the container lanes with the water on two edges.

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import { createFlatTerrain } from "./Terrain.ts";
import { createBuilding } from "./Building.ts";
import { createTrees, updateWind } from "./Foliage.ts";
import {
  createBarrel,
  createBarrier,
  createCar,
  createContainer,
  createCrate,
} from "./Obstacle.ts";
import { CollisionWorld, registerColliders } from "./Collision.ts";
import type { MapBuild, MapDefinition, Waypoint } from "./MapDefinition.ts";
import { buildGridWaypoints } from "./Waypoints.ts";
import { scatterSpawns } from "./SpawnLayout.ts";

const CONCRETE = 0x6b6f74;
const CONTAINER_COLORS = [0x2a6fb3, 0xb3202a, 0x2e7d4f, 0xd4a017, 0x8a8d91];

/** A dockside crane: vertical tower, horizontal jib arm, hanging cable + hook. */
function crane(): THREE.Group {
  const g = new THREE.Group();
  const towerMat = createToonMaterial({ color: 0xd4a017 });
  const armMat = createToonMaterial({ color: 0x8a8d91 });

  const towerH = 14;
  const tower = new THREE.Mesh(new THREE.BoxGeometry(1.4, towerH, 1.4), towerMat);
  tower.position.y = towerH / 2;
  tower.castShadow = true;
  tower.receiveShadow = true;
  tower.userData.collider = true;
  addOutline(tower, { thickness: 0.05 });
  g.add(tower);

  // Horizontal jib arm near the top.
  const armLen = 16;
  const arm = new THREE.Mesh(new THREE.BoxGeometry(armLen, 1, 1), armMat);
  arm.position.set(armLen / 2 - 2, towerH - 0.5, 0);
  arm.castShadow = true;
  addOutline(arm, { thickness: 0.05 });
  g.add(arm);

  // A short counter-jib on the other side for balance.
  const counter = new THREE.Mesh(new THREE.BoxGeometry(5, 1, 1), armMat);
  counter.position.set(-3, towerH - 0.5, 0);
  counter.castShadow = true;
  addOutline(counter, { thickness: 0.05 });
  g.add(counter);

  // Hanging cable + hook near the arm tip.
  const cable = new THREE.Mesh(
    new THREE.BoxGeometry(0.12, 5, 0.12),
    createToonMaterial({ color: 0x2a2c30 }),
  );
  cable.position.set(armLen - 3, towerH - 3.5, 0);
  cable.castShadow = true;
  g.add(cable);

  const hook = new THREE.Mesh(
    new THREE.BoxGeometry(0.6, 0.8, 0.6),
    createToonMaterial({ color: 0x16181d }),
  );
  hook.position.set(armLen - 3, towerH - 6.4, 0);
  hook.castShadow = true;
  addOutline(hook, { thickness: 0.03 });
  g.add(hook);

  g.name = "crane";
  return g;
}

/** A low concrete planter box topped with a decorative bush. */
function planter(root: THREE.Group, x: number, z: number): void {
  const box = new THREE.Mesh(
    new THREE.BoxGeometry(2.4, 0.6, 2.4),
    createToonMaterial({ color: 0x55585d }),
  );
  box.position.set(x, 0.3, z);
  box.castShadow = true;
  box.receiveShadow = true;
  addOutline(box, { thickness: 0.03 });
  root.add(box);

  const bush = createTrees([{ x, z, y: 0.6, scale: 0.7 }], "broadleaf", 0x5a4a32, 0x3f7a3a);
  root.add(bush.group);
}

export const UrbanDocks: MapDefinition = {
  id: "urban_docks",
  name: "Urban Docks",
  description: "Flat concrete waterfront — container lanes, cranes and tight CQB.",
  build(): MapBuild {
    const root = new THREE.Group();
    root.name = "UrbanDocks";
    const collision = new CollisionWorld();
    const terrain = createFlatTerrain(180, CONCRETE);
    collision.setTerrain(terrain);
    root.add(terrain.mesh);

    const place = (obj: THREE.Object3D, x: number, z: number, rotY = 0) => {
      obj.position.set(x, 0, z);
      obj.rotation.y = rotY;
      root.add(obj);
      registerColliders(obj, collision);
    };

    /**
     * A shipping container resting on the dock (or stacked on another). `stack`
     * is how many containers sit beneath it; the container body is 2.6 tall and
     * centred at y=1.3, so each stacked level adds 2.62 (a hair of clearance).
     */
    const placeContainer = (
      x: number,
      z: number,
      color: THREE.ColorRepresentation,
      stack = 0,
      rotY = 0,
    ) => {
      const c = createContainer(color);
      c.position.set(x, 1.3 + stack * 2.62, z);
      c.rotation.y = rotY;
      root.add(c);
      collision.addObjectAABB(c);
    };

    let cci = 0;
    const cColor = () => CONTAINER_COLORS[cci++ % CONTAINER_COLORS.length];

    // Two long container lanes flanking the central corridor (containers are 6
    // long, 2.44 deep). Lane A runs along the west; lane B along the east.
    for (let i = 0; i < 5; i++) {
      placeContainer(-22, -28 + i * 14, cColor(), 0, Math.PI / 2);
    }
    for (let i = 0; i < 5; i++) {
      placeContainer(22, -28 + i * 14, cColor(), 0, Math.PI / 2);
    }

    // Two-high stacks creating taller cover blocks and a few sightline breaks.
    placeContainer(-8, -14, cColor(), 0);
    placeContainer(-8, -14, cColor(), 1, 0.06);
    placeContainer(8, -16, cColor(), 0);
    placeContainer(8, -16, cColor(), 1, -0.05);
    placeContainer(-6, 16, cColor(), 0);
    placeContainer(-6, 16, cColor(), 1, 0.04);
    placeContainer(9, 18, cColor(), 0);
    placeContainer(9, 18, cColor(), 1, -0.07);

    // A short staggered cluster near the centre for CQB cover.
    placeContainer(0, 0, cColor(), 0, Math.PI / 2);
    placeContainer(-3, 6, cColor(), 0, 0.3);
    placeContainer(3, -6, cColor(), 0, -0.3);

    // Cranes near the waterfront edges.
    place(crane(), -40, 52, -Math.PI / 2);
    place(crane(), 36, 54, Math.PI);

    // Warehouses anchoring corners (industrial greys / rust).
    place(
      createBuilding({
        width: 20,
        depth: 14,
        height: 8,
        color: 0x7a5a4a,
        doorWall: "south",
        doorWidth: 4,
      }),
      -44,
      -44,
    );
    place(
      createBuilding({
        width: 18,
        depth: 14,
        height: 7,
        color: 0x6f7378,
        doorWall: "south",
        doorWidth: 4,
      }),
      44,
      -44,
    );
    place(
      createBuilding({
        width: 16,
        depth: 12,
        height: 7,
        color: 0x7a5a4a,
        doorWall: "north",
        doorWidth: 3,
      }),
      0,
      -50,
    );

    // Planters of greenery between the concrete.
    planter(root, -14, 30);
    planter(root, 14, 30);
    planter(root, 0, 36);
    planter(root, -30, 8);

    // Cover props scattered through the yard.
    place(createCar(0x3a4a6a), -16, -2, 0.4);
    place(createCar(0x6a3a2a), 17, 8, -0.5);
    for (const [x, z] of [[-12, 20], [12, -20], [-26, -8], [26, -4], [4, 24], [-4, -24]]) {
      place(createBarrel(0x9a3a2a), x, z);
    }
    for (const [x, z] of [[-18, 14], [18, -10], [-2, 12], [30, 14]]) {
      place(createCrate(1.2, 0x8a6a3a), x, z);
    }
    place(createBarrier(3), -10, 0, 0);
    place(createBarrier(3), 12, 4, Math.PI / 2);

    // Harbour water along the north and east edges (visual only, non-collidable).
    const waterMat = createToonMaterial({ color: 0x244b66, transparent: true, opacity: 0.85 });
    const northWater = new THREE.Mesh(new THREE.PlaneGeometry(180, 40), waterMat);
    northWater.rotation.x = -Math.PI / 2;
    northWater.position.set(0, -0.4, 84);
    root.add(northWater);
    const eastWater = new THREE.Mesh(new THREE.PlaneGeometry(40, 180), waterMat);
    eastWater.rotation.x = -Math.PI / 2;
    eastWater.position.set(84, -0.4, 0);
    root.add(eastWater);

    // Perimeter wall to bound the play area.
    addPerimeter(root, collision, 72);

    const spawns = scatterSpawns(collision, {
      bounds: { minX: -70, maxX: 70, minZ: -70, maxZ: 70 },
      groundAt: () => 0,
    });

    const waypoints: Waypoint[] = buildGridWaypoints(collision, {
      minX: -64,
      maxX: 64,
      minZ: -64,
      maxZ: 64,
      spacing: 5,
      groundAt: () => 0,
    });

    return {
      root,
      collision,
      spawns,
      waypoints,
      environment: {
        background: 0x9fb0bd,
        fogColor: 0xaebcc6,
        fogNear: 45,
        fogFar: 200,
        lighting: {
          skyColor: 0xcdd8e0,
          groundColor: 0x3a4046,
          sunColor: 0xf2f4f8,
          sunIntensity: 2.0,
          hemiIntensity: 1.2,
          sunDirection: new THREE.Vector3(0.4, 1, -0.3),
        },
      },
      groundAt: () => 0,
      update: (_dt, elapsed) => updateWind(elapsed),
      bounds: { minX: -70, maxX: 70, minZ: -70, maxZ: 70 },
    };
  },
};

/** A bounding wall around the play area (4 collidable slabs). */
export function addPerimeter(root: THREE.Group, collision: CollisionWorld, half: number): void {
  const mat = createToonMaterial({ color: 0x53575c });
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
