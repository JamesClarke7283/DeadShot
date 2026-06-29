import { assert, assertEquals } from "@std/assert";
import * as THREE from "../three.ts";
import { Rocket } from "./Rocket.ts";
import { Projectile } from "./Projectile.ts";
import type {
  DamageInfo,
  DamageTarget,
  RaycastHit,
  ShooterTag,
  VFXSink,
  WorldQuery,
} from "./combat.ts";

const fx: VFXSink = {
  bulletImpact() {},
  tracer() {},
  muzzleFlash() {},
  explosion() {},
};

class Target implements DamageTarget {
  object3d = new THREE.Object3D();
  alive = true;
  hits: DamageInfo[] = [];
  constructor(public team: "blue" | "red", private pos: THREE.Vector3) {}
  position(out: THREE.Vector3) {
    return out.copy(this.pos);
  }
  isHead() {
    return false;
  }
  applyDamage(info: DamageInfo) {
    this.hits.push(info);
  }
}

class World implements WorldQuery {
  constructor(public targets: Target[], private hitAt?: THREE.Vector3) {}
  raycast(origin: THREE.Vector3, dir: THREE.Vector3, maxDist: number): RaycastHit | null {
    if (!this.hitAt) return null;
    const toHit = this.hitAt.clone().sub(origin);
    const dist = toHit.dot(dir);
    if (dist >= 0 && dist <= maxDist) {
      return {
        point: this.hitAt.clone(),
        normal: new THREE.Vector3(0, 0, 1),
        distance: dist,
        object: new THREE.Object3D(),
      };
    }
    return null;
  }
  radiusTargets(center: THREE.Vector3, radius: number): DamageTarget[] {
    const p = new THREE.Vector3();
    return this.targets.filter((t) => t.position(p).distanceTo(center) <= radius);
  }
}

const owner: ShooterTag = { team: "blue", isPlayer: true, weaponId: "rpg7" };
const spec = { speed: 45, directDamage: 150, splashDamage: 120, splashRadius: 6 };

Deno.test("rocket explodes on impact and splashes enemies, not friends", () => {
  const enemy = new Target("red", new THREE.Vector3(0, 0, -10));
  const friend = new Target("blue", new THREE.Vector3(1, 0, -10));
  const world = new World([enemy, friend], new THREE.Vector3(0, 0, -10));
  const rocket = new Rocket(spec, owner);
  rocket.init({ position: new THREE.Vector3(0, 0, 0), velocity: new THREE.Vector3(0, 0, -45) });

  // Step until it impacts (raycast hit within the step).
  let alive = true;
  for (let i = 0; i < 30 && alive; i++) alive = rocket.update(0.05, world, fx);

  assert(!alive, "rocket should be consumed by impact");
  assert(enemy.hits.length > 0, "enemy takes splash damage");
  assert(enemy.hits[0].explosive, "marked explosive");
  assertEquals(friend.hits.length, 0, "friendly not damaged");
});

Deno.test("rocket detonates on expiry if it never hits", () => {
  const enemy = new Target("red", new THREE.Vector3(0, 0, -2));
  const world = new World([enemy]); // raycast always null
  const rocket = new Rocket(spec, owner);
  rocket.init({
    position: new THREE.Vector3(0, 0, 0),
    velocity: new THREE.Vector3(0, 0, -45),
    maxLifetime: 0.1,
  });
  let alive = true;
  for (let i = 0; i < 5 && alive; i++) alive = rocket.update(0.05, world, fx);
  assert(!alive);
  assert(enemy.hits.length > 0, "expiry detonation still splashes nearby");
});

Deno.test("plain projectile recycles after max range", () => {
  const world = new World([]);
  const p = new Projectile();
  p.init({
    position: new THREE.Vector3(0, 0, 0),
    velocity: new THREE.Vector3(0, 0, -100),
    maxRange: 10,
  });
  let alive = true;
  let steps = 0;
  while (alive && steps < 100) {
    alive = p.update(0.05, world, fx);
    steps++;
  }
  assert(!alive, "projectile expires past max range");
});
