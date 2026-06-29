// Community map loader: build a MapDefinition from a plain JSON description, so
// custom maps can be shipped/loaded without code. Uses the same primitive
// builders as the hand-built maps.

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import { createFlatTerrain, createHeightmapTerrain, type Terrain } from "./Terrain.ts";
import { createBuilding, type WallSide } from "./Building.ts";
import {
  createBarrel,
  createBarrier,
  createCar,
  createContainer,
  createCrate,
} from "./Obstacle.ts";
import { createTrees, updateWind } from "./Foliage.ts";
import { CollisionWorld, registerColliders } from "./Collision.ts";
import { buildGridWaypoints } from "./Waypoints.ts";
import { addPerimeter } from "./DesertTown.ts";
import type { MapBuild, MapDefinition, SpawnPoint, Waypoint } from "./MapDefinition.ts";

export interface MapJSON {
  id: string;
  name: string;
  description?: string;
  terrain?: { kind: "flat" | "heightmap"; size?: number; amplitude?: number; color?: number };
  buildings?: {
    x: number;
    z: number;
    width: number;
    depth: number;
    height: number;
    color?: number;
    doorWall?: WallSide;
    rotation?: number;
  }[];
  obstacles?: {
    type: "crate" | "barrel" | "barrier" | "car" | "container";
    x: number;
    z: number;
    color?: number;
    rotation?: number;
  }[];
  walls?: { x: number; z: number; w: number; d: number; h?: number; color?: number }[];
  trees?: { x: number; z: number; type?: "pine" | "broadleaf" | "palm" }[];
  spawns?: { x: number; z: number; yaw?: number; team: "blue" | "red" | "ffa" }[];
  environment?: {
    background?: number;
    fogColor?: number;
    fogNear?: number;
    fogFar?: number;
  };
  bounds?: { minX: number; maxX: number; minZ: number; maxZ: number };
  half?: number; // perimeter half-extent
}

export function mapFromJSON(json: MapJSON): MapDefinition {
  return {
    id: json.id,
    name: json.name,
    description: json.description ?? "Community map.",
    build(): MapBuild {
      const root = new THREE.Group();
      root.name = json.id;
      const collision = new CollisionWorld();

      const tk = json.terrain?.kind ?? "flat";
      const terrain: Terrain = tk === "heightmap"
        ? createHeightmapTerrain(
          json.terrain?.size ?? 180,
          100,
          json.terrain?.amplitude ?? 3,
          json.terrain?.color ?? 0x5f8f4e,
        )
        : createFlatTerrain(json.terrain?.size ?? 180, json.terrain?.color ?? 0x6fae5a);
      collision.setTerrain(terrain);
      root.add(terrain.mesh);

      const groundAt = (x: number, z: number) => terrain.sampleHeight(x, z);
      const place = (obj: THREE.Object3D, x: number, z: number, rotY = 0) => {
        obj.position.set(x, groundAt(x, z), z);
        obj.rotation.y = rotY;
        root.add(obj);
        registerColliders(obj, collision);
      };

      for (const b of json.buildings ?? []) {
        place(
          createBuilding({
            width: b.width,
            depth: b.depth,
            height: b.height,
            color: b.color,
            doorWall: b.doorWall,
          }),
          b.x,
          b.z,
          b.rotation ?? 0,
        );
      }

      for (const o of json.obstacles ?? []) {
        const obj = o.type === "crate"
          ? createCrate(1, o.color)
          : o.type === "barrel"
          ? createBarrel(o.color)
          : o.type === "barrier"
          ? createBarrier(2, o.color)
          : o.type === "car"
          ? createCar(o.color)
          : createContainer(o.color);
        place(obj, o.x, o.z, o.rotation ?? 0);
      }

      for (const w of json.walls ?? []) {
        const h = w.h ?? 4;
        const mesh = new THREE.Mesh(
          new THREE.BoxGeometry(w.w, h, w.d),
          createToonMaterial({ color: w.color ?? 0x9a9a9a }),
        );
        mesh.position.set(w.x, h / 2, w.z);
        mesh.castShadow = true;
        mesh.userData.collider = true;
        addOutline(mesh, { thickness: 0.04 });
        root.add(mesh);
        collision.addObjectAABB(mesh);
      }

      if (json.trees?.length) {
        const byType: Record<string, { x: number; z: number }[]> = {};
        for (const t of json.trees) (byType[t.type ?? "pine"] ??= []).push({ x: t.x, z: t.z });
        for (const [type, list] of Object.entries(byType)) {
          root.add(createTrees(list, type as "pine" | "broadleaf" | "palm").group);
        }
      }

      const half = json.half ?? (json.bounds ? json.bounds.maxX + 2 : 72);
      addPerimeter(root, collision, half);

      const spawns: SpawnPoint[] = (json.spawns ?? []).map((s) => ({
        position: new THREE.Vector3(s.x, groundAt(s.x, s.z), s.z),
        yaw: s.yaw ?? 0,
        team: s.team,
      }));
      if (spawns.length === 0) {
        // Guarantee at least a couple of spawns per team.
        for (const team of ["blue", "red"] as const) {
          const z = team === "blue" ? -40 : 40;
          for (let i = 0; i < 4; i++) {
            spawns.push({
              position: new THREE.Vector3(-12 + i * 8, groundAt(0, z), z),
              yaw: 0,
              team,
            });
          }
        }
      }

      const bounds = json.bounds ?? { minX: -70, maxX: 70, minZ: -70, maxZ: 70 };
      const waypoints: Waypoint[] = buildGridWaypoints(collision, {
        minX: bounds.minX + 6,
        maxX: bounds.maxX - 6,
        minZ: bounds.minZ + 6,
        maxZ: bounds.maxZ - 6,
        spacing: 6,
        groundAt,
      });

      return {
        root,
        collision,
        spawns,
        waypoints,
        environment: {
          background: json.environment?.background ?? 0x9fd3ff,
          fogColor: json.environment?.fogColor ?? 0xbfe3ff,
          fogNear: json.environment?.fogNear ?? 70,
          fogFar: json.environment?.fogFar ?? 300,
        },
        groundAt,
        update: (_dt, elapsed) => updateWind(elapsed),
        bounds,
      };
    },
  };
}

/** Fetch + parse a community map JSON and return its MapDefinition. */
export async function loadMapFromUrl(url: string): Promise<MapDefinition> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`map fetch failed: ${res.status}`);
  return mapFromJSON(await res.json() as MapJSON);
}
