// Obstacle props: crates, barrels, cars, barriers and shipping containers.
// Each returns a toon-shaded, outlined mesh/group tagged `userData.collider`.

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";

function collidable(mesh: THREE.Mesh, outline = 0.03): THREE.Mesh {
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  mesh.userData.collider = true;
  addOutline(mesh, { thickness: outline });
  return mesh;
}

export function createCrate(size = 1, color: THREE.ColorRepresentation = 0xb5793b): THREE.Mesh {
  const m = new THREE.Mesh(new THREE.BoxGeometry(size, size, size), createToonMaterial({ color }));
  m.position.y = size / 2;
  return collidable(m);
}

export function createBarrel(color: THREE.ColorRepresentation = 0x3b6e3b): THREE.Mesh {
  const m = new THREE.Mesh(
    new THREE.CylinderGeometry(0.4, 0.4, 1.1, 12),
    createToonMaterial({ color }),
  );
  m.position.y = 0.55;
  return collidable(m, 0.025);
}

export function createBarrier(
  length = 2,
  color: THREE.ColorRepresentation = 0xb0563a,
): THREE.Group {
  // Jersey/concrete barrier: trapezoidal slab.
  const g = new THREE.Group();
  const base = collidable(
    new THREE.Mesh(new THREE.BoxGeometry(length, 0.5, 0.7), createToonMaterial({ color })),
  );
  base.position.y = 0.25;
  const top = collidable(
    new THREE.Mesh(new THREE.BoxGeometry(length, 0.6, 0.35), createToonMaterial({ color })),
  );
  top.position.y = 0.75;
  g.add(base, top);
  g.name = "barrier";
  return g;
}

export function createCar(color: THREE.ColorRepresentation = 0x9a2b2b): THREE.Group {
  const g = new THREE.Group();
  const body = collidable(
    new THREE.Mesh(new THREE.BoxGeometry(2, 0.7, 4.2), createToonMaterial({ color })),
  );
  body.position.y = 0.7;
  const cabin = collidable(
    new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.7, 2.2), createToonMaterial({ color })),
  );
  cabin.position.set(0, 1.3, -0.2);
  const glass = createToonMaterial({ color: 0x223344, emissive: 0x10161f });
  const windshield = new THREE.Mesh(new THREE.BoxGeometry(1.7, 0.55, 0.1), glass);
  windshield.position.set(0, 1.35, 0.9);
  const wheelGeo = new THREE.CylinderGeometry(0.4, 0.4, 0.3, 10);
  const wheelMat = createToonMaterial({ color: 0x16181d });
  for (const [x, z] of [[-0.95, 1.4], [0.95, 1.4], [-0.95, -1.4], [0.95, -1.4]]) {
    const wheel = new THREE.Mesh(wheelGeo, wheelMat);
    wheel.rotation.z = Math.PI / 2;
    wheel.position.set(x, 0.4, z);
    wheel.castShadow = true;
    g.add(wheel);
  }
  g.add(body, cabin, windshield);
  g.name = "car";
  return g;
}

/** Shipping container — stackable cover for the docks map. */
export function createContainer(color: THREE.ColorRepresentation = 0x2a6fb3): THREE.Mesh {
  const m = new THREE.Mesh(
    new THREE.BoxGeometry(6, 2.6, 2.44),
    createToonMaterial({ color }),
  );
  m.position.y = 1.3;
  return collidable(m, 0.05);
}
