// UAV scorestreak.
//
// A passive recon streak: for its lifetime it periodically pings the positions
// of all enemies onto the owning team's minimap. No real mesh is needed, but we
// drop a tiny high-altitude marker so something exists in the world.

import * as THREE from "../three.ts";
import { Streak, type StreakContext } from "./Streak.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";

const DURATION = 25;
const PING_INTERVAL = 0.5;
const PING_HOLD = 0.7;
const ALTITUDE = 60;

export class UAV extends Streak {
  readonly id = "uav";
  readonly name = "UAV";

  private elapsed = 0;
  private pingTimer = 0;

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;

    if (!this.mesh) {
      const dot = new THREE.Mesh(
        new THREE.SphereGeometry(0.6, 8, 6),
        createToonMaterial({ color: 0x9ad1ff, emissive: 0x2a4a66 }),
      );
      const center = new THREE.Vector3(
        (ctx.bounds.minX + ctx.bounds.maxX) / 2,
        ALTITUDE,
        (ctx.bounds.minZ + ctx.bounds.maxZ) / 2,
      );
      dot.position.copy(center);
      this.mesh = dot;
      ctx.root.add(dot);
    }

    // Slowly orbit the marker so it reads as a drone in flight.
    if (this.mesh) {
      const cx = (ctx.bounds.minX + ctx.bounds.maxX) / 2;
      const cz = (ctx.bounds.minZ + ctx.bounds.maxZ) / 2;
      const r = Math.max(4, (ctx.bounds.maxX - ctx.bounds.minX) * 0.3);
      this.mesh.position.set(
        cx + Math.cos(this.elapsed * 0.5) * r,
        ALTITUDE,
        cz + Math.sin(this.elapsed * 0.5) * r,
      );
    }

    this.elapsed += dt;
    this.pingTimer -= dt;
    if (this.pingTimer <= 0) {
      this.pingTimer = PING_INTERVAL;
      const enemies = ctx.enemiesOf(ctx.owner.team);
      const positions = enemies.map((e) => e.position(new THREE.Vector3()));
      ctx.ping(ctx.owner.team, positions, PING_HOLD);
    }

    if (this.elapsed >= DURATION) this.active = false;
  }
}
