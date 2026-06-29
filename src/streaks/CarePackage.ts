// Care Package scorestreak.
//
// A helicopter flies in from a map edge, passes over the owner, and releases a
// supply crate that falls to the ground. Once it lands it is handed to the Match
// as a persistent, collectible care-package (Press E / bot proximity). The heli
// continues on and despawns once it leaves the map.

import * as THREE from "../three.ts";
import { Streak, type StreakContext } from "./Streak.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";

const ALTITUDE = 26;
const HELI_SPEED = 22;
const FALL_SPEED = 14;
const CRATE_HALF = 0.6;
const MARGIN = 12; // how far off-map the heli spawns / despawns

export class CarePackage extends Streak {
  readonly id = "care_package";
  readonly name = "Care Package";

  private heli: THREE.Group | null = null;
  private mainRotor: THREE.Object3D | null = null;
  private tailRotor: THREE.Object3D | null = null;
  private crate: THREE.Object3D | null = null;

  private dropX = 0;
  private dropZ = 0;
  private groundY = 0;
  private heliY = 0;
  private dropped = false;

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;
    if (!this.heli) this.spawn(ctx);
    const heli = this.heli!;

    // Spin the rotors.
    if (this.mainRotor) this.mainRotor.rotation.y += dt * 30;
    if (this.tailRotor) this.tailRotor.rotation.x += dt * 34;

    // Fly across the map (nose points +X).
    heli.position.x += HELI_SPEED * dt;

    // Release the crate as it passes over the drop point.
    if (!this.dropped && heli.position.x >= this.dropX) {
      this.dropped = true;
      this.releaseCrate(ctx, heli.position.x);
    }

    // Drop the crate; once it lands, hand it to the Match as a pickup.
    if (this.crate) {
      this.crate.position.y -= FALL_SPEED * dt;
      this.crate.rotation.y += dt * 1.0;
      if (this.crate.position.y <= this.groundY + CRATE_HALF) {
        ctx.armCarePackage(
          new THREE.Vector3(this.crate.position.x, this.groundY, this.crate.position.z),
        );
        ctx.root.remove(this.crate);
        this.crate = null;
      }
    }

    // End once the heli has dropped its crate and flown off the map.
    if (this.dropped && !this.crate && heli.position.x > ctx.bounds.maxX + MARGIN) {
      this.active = false;
    }
  }

  private spawn(ctx: StreakContext): void {
    const owner = ctx.allActors().find((a) => a.id === ctx.owner.id);
    const drop = new THREE.Vector3();
    if (owner) {
      owner.position(drop);
    } else {
      drop.set(
        (ctx.bounds.minX + ctx.bounds.maxX) / 2,
        0,
        (ctx.bounds.minZ + ctx.bounds.maxZ) / 2,
      );
    }
    this.dropX = drop.x;
    this.dropZ = drop.z;
    this.groundY = ctx.groundAt(drop.x, drop.z);
    this.heliY = this.groundY + ALTITUDE;

    const heli = buildHelicopter();
    heli.position.set(ctx.bounds.minX - MARGIN, this.heliY, this.dropZ);
    this.heli = heli;
    this.mesh = heli; // Streak.dispose() removes this.mesh
    this.mainRotor = heli.getObjectByName("mainRotor") ?? null;
    this.tailRotor = heli.getObjectByName("tailRotor") ?? null;
    ctx.root.add(heli);
  }

  private releaseCrate(ctx: StreakContext, x: number): void {
    const crate = new THREE.Mesh(
      new THREE.BoxGeometry(CRATE_HALF * 2, CRATE_HALF * 2, CRATE_HALF * 2),
      createToonMaterial({ color: 0x6a7a3a }),
    );
    addOutline(crate, { thickness: 0.04 });
    const stripe = new THREE.Mesh(
      new THREE.BoxGeometry(CRATE_HALF * 2.05, 0.18, CRATE_HALF * 2.05),
      createToonMaterial({ color: 0xffd166, emissive: 0x665200 }),
    );
    stripe.position.y = CRATE_HALF * 0.3;
    crate.add(stripe);
    crate.position.set(x, this.heliY - 1.6, this.dropZ);
    this.crate = crate;
    ctx.root.add(crate);
  }

  override dispose(ctx: StreakContext): void {
    if (this.crate) {
      ctx.root.remove(this.crate);
      this.crate = null;
    }
    super.dispose(ctx);
    this.heli = null;
    this.mainRotor = null;
    this.tailRotor = null;
  }
}

/** Build a low-poly toon helicopter (nose points +X). */
function buildHelicopter(): THREE.Group {
  const g = new THREE.Group();
  const olive = createToonMaterial({ color: 0x3c4a2c });
  const dark = createToonMaterial({ color: 0x191c22 });

  const body = new THREE.Mesh(new THREE.BoxGeometry(3.0, 1.3, 1.4), olive);
  addOutline(body, { thickness: 0.05 });
  g.add(body);

  // Cockpit glass nose.
  const nose = new THREE.Mesh(
    new THREE.BoxGeometry(0.9, 0.9, 1.1),
    createToonMaterial({ color: 0x8fd0ff, emissive: 0x16384a }),
  );
  nose.position.set(1.7, 0.05, 0);
  addOutline(nose, { thickness: 0.04 });
  g.add(nose);

  // Tail boom + fin.
  const boom = new THREE.Mesh(new THREE.BoxGeometry(2.6, 0.28, 0.28), olive);
  boom.position.set(-2.4, 0.25, 0);
  addOutline(boom, { thickness: 0.03 });
  g.add(boom);
  const fin = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.8, 0.12), olive);
  fin.position.set(-3.6, 0.55, 0);
  addOutline(fin, { thickness: 0.03 });
  g.add(fin);

  // Main rotor (spins about Y) on a hub above the body.
  const mast = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.4, 0.16), dark);
  mast.position.set(0, 0.85, 0);
  g.add(mast);
  const mainRotor = new THREE.Group();
  mainRotor.name = "mainRotor";
  mainRotor.position.set(0, 1.05, 0);
  const blade = new THREE.Mesh(new THREE.BoxGeometry(7.2, 0.05, 0.34), dark);
  mainRotor.add(blade);
  const blade2 = blade.clone();
  blade2.rotation.y = Math.PI / 2;
  mainRotor.add(blade2);
  g.add(mainRotor);

  // Tail rotor (spins about X) at the boom tip.
  const tailRotor = new THREE.Group();
  tailRotor.name = "tailRotor";
  tailRotor.position.set(-3.7, 0.55, 0.18);
  const tBlade = new THREE.Mesh(new THREE.BoxGeometry(0.05, 1.2, 0.16), dark);
  tailRotor.add(tBlade);
  const tBlade2 = tBlade.clone();
  tBlade2.rotation.x = Math.PI / 2;
  tailRotor.add(tBlade2);
  g.add(tailRotor);

  // Landing skids.
  for (const z of [-0.55, 0.55]) {
    const skid = new THREE.Mesh(new THREE.BoxGeometry(2.0, 0.1, 0.1), dark);
    skid.position.set(0.2, -0.85, z);
    g.add(skid);
  }

  return g;
}
