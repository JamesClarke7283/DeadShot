// Procedural cartoon face built from primitives, attached to a head of radius r.
//
// Returns a Group whose origin is the head centre and which faces +Z (the
// character's forward). Includes white eyes with black pupils, a small nose, a
// curved smile, eyebrows, and a team-tinted headband. Face details are kept
// outline-free (they're small and read better clean).

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";

export interface FaceOptions {
  headRadius: number;
  skin?: THREE.ColorRepresentation;
  headbandColor?: THREE.ColorRepresentation;
}

export interface FaceParts {
  group: THREE.Group;
  headband: THREE.Mesh;
}

export function buildFace(opts: FaceOptions): FaceParts {
  const r = opts.headRadius;
  const group = new THREE.Group();
  group.name = "face";

  const white = createToonMaterial({ color: 0xffffff });
  const black = createToonMaterial({ color: 0x111111 });
  const skin = createToonMaterial({ color: opts.skin ?? 0xf2c79a });

  const eyeR = r * 0.3;
  const eyeOffX = r * 0.42;
  const eyeY = r * 0.18;
  const eyeZ = r * 0.86;

  for (const sign of [-1, 1]) {
    const eye = new THREE.Mesh(new THREE.SphereGeometry(eyeR, 12, 12), white);
    eye.position.set(sign * eyeOffX, eyeY, eyeZ);
    eye.scale.z = 0.6;
    group.add(eye);

    const pupil = new THREE.Mesh(new THREE.SphereGeometry(eyeR * 0.45, 8, 8), black);
    pupil.position.set(sign * eyeOffX, eyeY, eyeZ + eyeR * 0.5);
    group.add(pupil);

    // Eyebrow: a small angled bar above the eye.
    const brow = new THREE.Mesh(
      new THREE.BoxGeometry(eyeR * 1.3, eyeR * 0.28, eyeR * 0.3),
      black,
    );
    brow.position.set(sign * eyeOffX, eyeY + eyeR * 0.95, eyeZ + eyeR * 0.2);
    brow.rotation.z = sign * 0.18;
    group.add(brow);
  }

  // Nose: a little wedge.
  const nose = new THREE.Mesh(new THREE.ConeGeometry(r * 0.12, r * 0.25, 6), skin);
  nose.rotation.x = Math.PI / 2;
  nose.position.set(0, -r * 0.02, r * 1.0);
  group.add(nose);

  // Smile: lower half of a thin torus ring.
  const smile = new THREE.Mesh(
    new THREE.TorusGeometry(r * 0.34, r * 0.05, 8, 16, Math.PI),
    black,
  );
  smile.rotation.z = Math.PI; // flip the half-ring into a U
  smile.position.set(0, -r * 0.32, r * 0.88);
  group.add(smile);

  // Team-tinted headband around the head.
  const headband = new THREE.Mesh(
    new THREE.TorusGeometry(r * 1.0, r * 0.14, 8, 20),
    createToonMaterial({ color: opts.headbandColor ?? 0x3a86ff }),
  );
  headband.rotation.x = Math.PI / 2;
  headband.position.set(0, r * 0.5, 0);
  headband.name = "headband";
  group.add(headband);

  return { group, headband };
}
