// Modular building builder: four walls (with a doorway gap and window insets) and
// an optional flat roof, assembled from boxes. Collidable meshes are tagged
// `userData.collider = true` so the map can register them with the CollisionWorld
// after positioning (see registerColliders in Collision-adjacent helpers).

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";

export type WallSide = "north" | "south" | "east" | "west";

export interface BuildingOptions {
  width?: number;
  depth?: number;
  height?: number;
  wallThickness?: number;
  color?: THREE.ColorRepresentation;
  doorWall?: WallSide;
  doorWidth?: number;
  windows?: boolean;
  roof?: boolean;
}

function wall(
  w: number,
  h: number,
  d: number,
  x: number,
  y: number,
  z: number,
  mat: THREE.Material,
): THREE.Mesh {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
  m.position.set(x, y, z);
  m.castShadow = true;
  m.receiveShadow = true;
  m.userData.collider = true;
  addOutline(m, { thickness: 0.04 });
  return m;
}

export function createBuilding(opts: BuildingOptions = {}): THREE.Group {
  const width = opts.width ?? 10;
  const depth = opts.depth ?? 8;
  const height = opts.height ?? 4;
  const t = opts.wallThickness ?? 0.4;
  const doorWall = opts.doorWall ?? "south";
  const doorW = opts.doorWidth ?? 2;
  const mat = createToonMaterial({ color: opts.color ?? 0xcdb38b });

  const g = new THREE.Group();
  g.name = "building";

  const hw = width / 2;
  const hd = depth / 2;
  const yc = height / 2;

  // Build each of the 4 walls; the door wall is split around a gap.
  const sides: { side: WallSide; len: number; horizontal: boolean; cx: number; cz: number }[] = [
    { side: "north", len: width, horizontal: true, cx: 0, cz: -hd },
    { side: "south", len: width, horizontal: true, cx: 0, cz: hd },
    { side: "west", len: depth, horizontal: false, cx: -hw, cz: 0 },
    { side: "east", len: depth, horizontal: false, cx: hw, cz: 0 },
  ];

  for (const s of sides) {
    if (s.side === doorWall) {
      // Two segments flanking the door + a lintel above it.
      const segLen = (s.len - doorW) / 2;
      const lintelH = height - 2.2;
      const off = doorW / 2 + segLen / 2;
      if (s.horizontal) {
        g.add(wall(segLen, height, t, -off, yc, s.cz, mat));
        g.add(wall(segLen, height, t, off, yc, s.cz, mat));
        if (lintelH > 0) g.add(wall(doorW, lintelH, t, 0, height - lintelH / 2, s.cz, mat));
      } else {
        g.add(wall(t, height, segLen, s.cx, yc, -off, mat));
        g.add(wall(t, height, segLen, s.cx, yc, off, mat));
        if (lintelH > 0) g.add(wall(t, lintelH, doorW, s.cx, height - lintelH / 2, 0, mat));
      }
    } else if (s.horizontal) {
      g.add(wall(s.len, height, t, s.cx, yc, s.cz, mat));
    } else {
      g.add(wall(t, height, s.len, s.cx, yc, s.cz, mat));
    }
  }

  // Window insets (visual only).
  if (opts.windows !== false) {
    const glass = createToonMaterial({ color: 0x223344, emissive: 0x111a22 });
    const winGeo = new THREE.PlaneGeometry(1.1, 1.0);
    const place = (x: number, y: number, z: number, ry: number) => {
      const w = new THREE.Mesh(winGeo, glass);
      w.position.set(x, y, z);
      w.rotation.y = ry;
      g.add(w);
    };
    place(-hw + 2, height * 0.6, -hd - 0.01, 0);
    place(hw - 2, height * 0.6, -hd - 0.01, 0);
    place(-hw - 0.01, height * 0.6, -hd + 2, Math.PI / 2);
    place(-hw - 0.01, height * 0.6, hd - 2, Math.PI / 2);
  }

  if (opts.roof !== false) {
    g.add(wall(width + t, t, depth + t, 0, height, 0, mat));
  }

  return g;
}
