// Tests for thrown equipment: explosion falloff + friendly fire (frag), direct
// lethal hit (knife), directional cone trip (claymore), remote C4 detonation via
// the manager, and the gravity arc of a thrown frag.

import { assert, assertEquals } from "@std/assert";
import * as THREE from "../three.ts";
import { Frag } from "./Frag.ts";
import { ThrowingKnife } from "./ThrowingKnife.ts";
import { Claymore } from "./Claymore.ts";
import { EquipmentManager } from "./EquipmentManager.ts";
import type { EquipmentContext } from "./Equipment.ts";
import type { ScreenEffectsApi } from "../render/ScreenEffects.ts";
import type {
  DamageInfo,
  DamageTarget,
  RaycastHit,
  VFXSink,
  WorldQuery,
} from "../weapons/combat.ts";
import type { TeamId } from "../core/types.ts";

// ---- Mocks ----------------------------------------------------------------

const noopFX: VFXSink = {
  bulletImpact() {},
  tracer() {},
  muzzleFlash() {},
  explosion() {},
};

const noopScreen: ScreenEffectsApi = {
  flash() {},
  blur() {},
  deafen() {},
  tint() {},
  update() {},
  isDeafened() {
    return false;
  },
  clear() {},
};

class Target implements DamageTarget {
  object3d = new THREE.Object3D();
  alive = true;
  hits: DamageInfo[] = [];
  /** Test hook: when set, the target reports this position (point-blank tests). */
  atCenter: THREE.Vector3 | null = null;
  constructor(public team: TeamId, private pos: THREE.Vector3) {}
  position(out: THREE.Vector3) {
    return out.copy(this.atCenter ?? this.pos);
  }
  isHead() {
    return false;
  }
  applyDamage(info: DamageInfo) {
    this.hits.push(info);
  }
  get damage() {
    return this.hits.reduce((s, h) => s + h.amount, 0);
  }
}

class World implements WorldQuery {
  /** Optional fixed impact point; when set, raycast reports a hit there. */
  constructor(public targets: Target[], public hitAt?: THREE.Vector3, public hitTarget?: Target) {}
  raycast(origin: THREE.Vector3, dir: THREE.Vector3, maxDist: number): RaycastHit | null {
    if (!this.hitAt) return null;
    const toHit = this.hitAt.clone().sub(origin);
    const dist = toHit.dot(dir);
    if (dist >= 0 && dist <= maxDist) {
      return {
        point: this.hitAt.clone(),
        normal: new THREE.Vector3(0, 1, 0),
        distance: dist,
        object: new THREE.Object3D(),
        target: this.hitTarget,
      };
    }
    return null;
  }
  radiusTargets(center: THREE.Vector3, radius: number): DamageTarget[] {
    const p = new THREE.Vector3();
    return this.targets.filter((t) => t.position(p).distanceTo(center) <= radius);
  }
}

function makeCtx(world: World): EquipmentContext {
  return {
    world,
    vfx: noopFX,
    root: new THREE.Object3D(),
    screen: noopScreen,
    getPlayerPosition(out) {
      return out.set(1000, 0, 0); // far away by default
    },
    getPlayerTeam() {
      return "blue";
    },
  };
}

// ---- Tests ----------------------------------------------------------------

// World where every target sits at the explosion centre (point-blank). A frag
// thrown into open air arcs far away before its 3s fuse expires; rather than
// chase the exact detonation point, we co-locate targets so the falloff math
// resolves to full damage and we can assert friendly-fire behaviour directly.
class PointBlankWorld extends World {
  private last = new THREE.Vector3();
  override raycast(): RaycastHit | null {
    return null; // never impacts; frag rides its fuse
  }
  override radiusTargets(center: THREE.Vector3, _radius: number): DamageTarget[] {
    this.last.copy(center);
    for (const t of this.targets) t.atCenter = this.last;
    return this.targets.filter((t) => t.alive);
  }
}

Deno.test("frag detonates on fuse and splashes enemies but not friends", () => {
  const enemy = new Target("red", new THREE.Vector3(0, 0, 0));
  const friend = new Target("blue", new THREE.Vector3(0, 0, 0));
  const world = new PointBlankWorld([enemy, friend]);
  const ctx = makeCtx(world);
  const frag = new Frag();
  frag.throw(new THREE.Vector3(0, 1, 0), new THREE.Vector3(0, 0, -1), "blue", ctx);

  for (let i = 0; i < 80 && frag.active; i++) frag.update(0.05, ctx); // > 3s fuse

  assert(!frag.active, "frag consumed after detonation");
  assert(enemy.damage > 0, "enemy takes explosive splash");
  assert(enemy.hits[0].explosive, "marked explosive");
  assertEquals(friend.hits.length, 0, "no friendly fire");
});

Deno.test("frag in ffa damages a same-color target", () => {
  const other = new Target("ffa", new THREE.Vector3(0, 0, 0));
  const world = new PointBlankWorld([other]);
  const ctx = makeCtx(world);
  const frag = new Frag();
  frag.throw(new THREE.Vector3(0, 1, 0), new THREE.Vector3(0, 0, -1), "ffa", ctx);
  for (let i = 0; i < 80 && frag.active; i++) frag.update(0.05, ctx);
  assert(other.damage > 0, "ffa has no friendly-fire protection");
});

Deno.test("throwing knife deals lethal damage on direct hit", () => {
  const enemy = new Target("red", new THREE.Vector3(0, 0, -5));
  const world = new World([enemy], new THREE.Vector3(0, 0, -5), enemy);
  const ctx = makeCtx(world);
  const knife = new ThrowingKnife();
  knife.throw(new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, 0, -1), "blue", ctx);

  for (let i = 0; i < 20 && enemy.hits.length === 0; i++) knife.update(0.05, ctx);

  assertEquals(enemy.hits.length, 1, "one direct hit");
  assert(enemy.hits[0].amount >= 150, "lethal damage");
});

Deno.test("claymore trips on enemy in front cone, not behind", () => {
  // Place by impacting the ground straight ahead (+facing -Z).
  const front = new Target("red", new THREE.Vector3(0, 0, -3));
  const back = new Target("red", new THREE.Vector3(0, 0, 3));
  const world = new World([front, back], new THREE.Vector3(0, 0, -1));
  const ctx = makeCtx(world);
  const mine = new Claymore();
  mine.throw(new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, 0, -1), "blue", ctx);

  // First update places it (impact); subsequent updates arm then scan.
  for (let i = 0; i < 40 && mine.active; i++) mine.update(0.1, ctx);

  assert(!mine.active, "claymore detonated");
  assert(front.damage > 0, "enemy in front cone is hit");
  assertEquals(back.hits.length, 0, "enemy behind is safe");
});

Deno.test("manager throws C4, detonateC4 damages a nearby enemy and prunes it", () => {
  const enemy = new Target("red", new THREE.Vector3(0, 0, 0));
  // Ground impact at the enemy's feet so the C4 sticks near them.
  const world = new World([enemy], new THREE.Vector3(0, 0, 0));
  const ctx = makeCtx(world);
  const mgr = new EquipmentManager(ctx);
  mgr.throwLethal("c4", {
    origin: new THREE.Vector3(0, 1, 0),
    direction: new THREE.Vector3(0, 0, -1),
    team: "blue",
  });

  // Let it land + stick (stays active, never times out).
  for (let i = 0; i < 10; i++) mgr.update(0.05);
  assertEquals(mgr.count, 1, "C4 persists until detonated");
  assertEquals(enemy.hits.length, 0, "no damage before detonation");

  const any = mgr.detonateC4();
  assert(any, "detonateC4 reports it blew a charge");
  assert(enemy.damage > 0, "nearby enemy damaged");

  mgr.update(0.05); // prune the now-inactive C4
  assertEquals(mgr.count, 0, "detonated C4 pruned");
});

Deno.test("thrown frag arcs and falls under gravity before detonating", () => {
  const world = new World([]); // never impacts
  const ctx = makeCtx(world);
  const frag = new Frag();
  frag.throw(new THREE.Vector3(0, 5, 0), new THREE.Vector3(0, 0, -1), "blue", ctx);

  // Reach into the mesh added to root to observe motion.
  const mesh = ctx.root.children[0];
  assert(mesh, "frag mesh added to root");

  frag.update(0.1, ctx);
  const y1 = mesh.position.y;
  const z1 = mesh.position.z;
  frag.update(0.1, ctx);
  const y2 = mesh.position.y;
  const z2 = mesh.position.z;

  assert(z2 < z1, "advances forward (-Z)");
  assert(y2 < y1, "falls under gravity (y decreases)");
});
