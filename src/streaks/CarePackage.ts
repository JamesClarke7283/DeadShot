// Care Package scorestreak.
//
// Drops a crate from the sky above the owner. Once it lands it becomes
// capturable: any actor that walks within range grants a random streak and the
// package is consumed. Times out if nobody grabs it.

import * as THREE from "../three.ts";
import { Streak, type StreakContext } from "./Streak.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";

const DROP_HEIGHT = 40;
const FALL_SPEED = 18;
const CAPTURE_RANGE = 2.5;
const TIMEOUT = 30;
const CRATE_HALF = 0.6;

export class CarePackage extends Streak {
  readonly id = "care_package";
  readonly name = "Care Package";

  private elapsed = 0;
  private landed = false;
  private groundY = 0;
  private readonly drop = new THREE.Vector3();

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;

    if (!this.mesh) this.spawn(ctx);

    const crate = this.mesh!;
    if (!this.landed) {
      crate.position.y -= FALL_SPEED * dt;
      crate.rotation.y += dt * 1.2;
      if (crate.position.y <= this.groundY + CRATE_HALF) {
        crate.position.y = this.groundY + CRATE_HALF;
        this.landed = true;
      }
    } else {
      // Capturable: first actor in range grabs it.
      const tmp = new THREE.Vector3();
      for (const actor of ctx.allActors()) {
        if (!actor.alive) continue;
        actor.position(tmp);
        const dx = tmp.x - crate.position.x;
        const dz = tmp.z - crate.position.z;
        if (Math.hypot(dx, dz) <= CAPTURE_RANGE) {
          ctx.grantRandomStreak({ id: actor.id, team: actor.team });
          this.active = false;
          return;
        }
      }
    }

    this.elapsed += dt;
    if (this.elapsed >= TIMEOUT) this.active = false;
  }

  private spawn(ctx: StreakContext): void {
    const owner = ctx.allActors().find((a) => a.id === ctx.owner.id);
    if (owner) {
      owner.position(this.drop);
    } else {
      this.drop.set(
        (ctx.bounds.minX + ctx.bounds.maxX) / 2,
        0,
        (ctx.bounds.minZ + ctx.bounds.maxZ) / 2,
      );
    }
    this.groundY = ctx.groundAt(this.drop.x, this.drop.z);

    const crate = new THREE.Mesh(
      new THREE.BoxGeometry(CRATE_HALF * 2, CRATE_HALF * 2, CRATE_HALF * 2),
      createToonMaterial({ color: 0x6a7a3a }),
    );
    addOutline(crate, { thickness: 0.04 });

    // A bright signal stripe so it reads as a drop crate.
    const stripe = new THREE.Mesh(
      new THREE.BoxGeometry(CRATE_HALF * 2.05, 0.18, CRATE_HALF * 2.05),
      createToonMaterial({ color: 0xffd166, emissive: 0x665200 }),
    );
    stripe.position.y = CRATE_HALF * 0.3;
    crate.add(stripe);

    crate.position.set(this.drop.x, this.groundY + DROP_HEIGHT, this.drop.z);
    this.mesh = crate;
    ctx.root.add(crate);
  }
}
