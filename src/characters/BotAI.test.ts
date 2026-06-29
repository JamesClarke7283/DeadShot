import { assert } from "@std/assert";
import * as THREE from "../three.ts";
import { type Actor, Bot, type BotContext } from "./Bot.ts";
import { ProceduralHuman } from "./ProceduralHuman.ts";
import { Navigator } from "./BotNavigator.ts";
import { CollisionWorld } from "../maps/Collision.ts";
import { buildGridWaypoints } from "../maps/Waypoints.ts";
import { getWeapon } from "../weapons/WeaponDefinition.ts";
import type { RaycastHit, VFXSink, WorldQuery } from "../weapons/combat.ts";

const noopFX: VFXSink = {
  bulletImpact() {},
  tracer() {},
  muzzleFlash() {},
  explosion() {},
};

// Analytic arena: hitscan resolves against bot capsules (no GL / mesh raycast),
// skipping the shooter's own body (very-near hits).
class Arena implements WorldQuery {
  bots: Bot[] = [];
  private c = new THREE.Vector3();
  raycast(origin: THREE.Vector3, dir: THREE.Vector3, maxDist: number): RaycastHit | null {
    let best: RaycastHit | null = null;
    let bestT = Infinity;
    for (const b of this.bots) {
      if (!b.alive) continue;
      b.position(this.c);
      const tox = this.c.x - origin.x, toy = this.c.y - origin.y, toz = this.c.z - origin.z;
      const t = tox * dir.x + toy * dir.y + toz * dir.z;
      if (t < 0.8 || t > maxDist) continue; // skip self / behind
      const px = origin.x + dir.x * t, py = origin.y + dir.y * t, pz = origin.z + dir.z * t;
      const d = Math.hypot(px - this.c.x, py - this.c.y, pz - this.c.z);
      if (d <= 0.6 && t < bestT) {
        bestT = t;
        best = {
          point: new THREE.Vector3(px, py, pz),
          normal: new THREE.Vector3(0, 0, 1),
          distance: t,
          object: b.object3d,
          target: b,
        };
      }
    }
    return best;
  }
  radiusTargets(center: THREE.Vector3, radius: number) {
    const p = new THREE.Vector3();
    return this.bots.filter((b) => b.alive && b.position(p).distanceTo(center) <= radius);
  }
}

function makeBot(id: number, team: "blue" | "red", x: number, z: number): Bot {
  return new Bot({
    id,
    team,
    difficulty: "veteran",
    character: new ProceduralHuman({ team }),
    weaponDef: getWeapon("m4"),
    spawn: new THREE.Vector3(x, 0, z),
    yaw: team === "blue" ? 0 : Math.PI,
  });
}

Deno.test("bots fight each other and produce kills", () => {
  const collision = new CollisionWorld();
  const waypoints = buildGridWaypoints(collision, {
    minX: -20,
    maxX: 20,
    minZ: -20,
    maxZ: 20,
    spacing: 5,
    groundAt: () => 0,
  });
  const navigator = new Navigator(waypoints);
  const arena = new Arena();

  const bots: Bot[] = [];
  for (let i = 0; i < 3; i++) {
    bots.push(makeBot(i, "blue", -6 + i * 4, -8));
    bots.push(makeBot(10 + i, "red", -6 + i * 4, 8));
  }
  arena.bots = bots;

  const ctx: BotContext = {
    world: arena,
    collision,
    navigator,
    vfx: noopFX,
    actors: bots as unknown as Actor[],
    groundAt: () => 0,
    bounds: { minX: -20, maxX: 20, minZ: -20, maxZ: 20 },
  };

  // Run ~12 simulated seconds at 30 Hz, attributing kills via lastDamage.
  const dead = new Set<number>();
  let totalKills = 0;
  const step = 1 / 30;
  for (let frame = 0; frame < 360; frame++) {
    for (const b of bots) b.update(step, ctx);
    for (const b of bots) {
      if (!b.alive && !dead.has(b.id)) {
        dead.add(b.id);
        totalKills++;
        const killerId = b.lastDamage?.sourceId;
        const killer = bots.find((x) => x.id === killerId);
        if (killer) killer.kills++;
      }
    }
    if (dead.size === bots.length) break;
  }

  assert(totalKills > 0, `expected kills, got ${totalKills}`);
  // At least one bot should have scored a kill on the "scoreboard".
  assert(bots.some((b) => b.kills > 0), "no bot recorded a kill");
});

Deno.test("a bot dies after taking enough damage and is attributed", () => {
  const victim = makeBot(1, "red", 0, 0);
  victim.applyDamage({ amount: 50, headshot: false, sourceTeam: "blue", sourceId: 99 });
  assert(victim.alive);
  victim.applyDamage({ amount: 60, headshot: false, sourceTeam: "blue", sourceId: 99 });
  assert(!victim.alive);
  assert(victim.lastDamage?.sourceId === 99);
});
