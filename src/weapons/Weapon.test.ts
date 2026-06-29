import { assert, assertEquals } from "@std/assert";
import * as THREE from "../three.ts";
import { getWeapon } from "./WeaponDefinition.ts";
import { Weapon } from "./Weapon.ts";
import type {
  Aim,
  DamageInfo,
  DamageTarget,
  RaycastHit,
  ShooterTag,
  VFXSink,
  WorldQuery,
} from "./combat.ts";

const noopFX: VFXSink = {
  bulletImpact() {},
  tracer() {},
  muzzleFlash() {},
  explosion() {},
};

function makeAim(): Aim {
  return {
    origin: new THREE.Vector3(0, 0, 0),
    direction: new THREE.Vector3(0, 0, -1),
    applyRecoil() {},
  };
}

class MockTarget implements DamageTarget {
  object3d = new THREE.Object3D();
  alive = true;
  hits: DamageInfo[] = [];
  constructor(public team: "blue" | "red") {}
  position(out: THREE.Vector3) {
    return out.set(0, 0, -5);
  }
  isHead() {
    return false;
  }
  applyDamage(info: DamageInfo) {
    this.hits.push(info);
  }
}

class MockWorld implements WorldQuery {
  rockets = 0;
  constructor(public target: MockTarget) {}
  raycast(): RaycastHit | null {
    return {
      point: new THREE.Vector3(0, 0, -5),
      normal: new THREE.Vector3(0, 0, 1),
      distance: 5,
      object: this.target.object3d,
      target: this.target,
    };
  }
  radiusTargets() {
    return [this.target];
  }
  spawnRocket() {
    this.rockets++;
  }
}

const shooter: ShooterTag = { team: "blue", isPlayer: true, weaponId: "m4" };

Deno.test("auto weapon fires once per cooldown while held", () => {
  const target = new MockTarget("red");
  const world = new MockWorld(target);
  const w = new Weapon(getWeapon("m4"), [], shooter);
  const aim = makeAim();
  w.setTrigger(true);
  for (let i = 0; i < 5; i++) w.update(0.1, aim, world, noopFX); // dt > interval(0.08)
  assertEquals(w.magazine, 25);
  assertEquals(target.hits.length, 5);
});

Deno.test("semi weapon fires once per trigger press", () => {
  const target = new MockTarget("red");
  const world = new MockWorld(target);
  const w = new Weapon(getWeapon("m9"), [], { ...shooter, weaponId: "m9" });
  const aim = makeAim();
  w.setTrigger(true);
  for (let i = 0; i < 5; i++) w.update(0.2, aim, world, noopFX);
  assertEquals(target.hits.length, 1, "only one shot from a held semi trigger");
  w.setTrigger(false);
  w.update(0.2, aim, world, noopFX);
  w.setTrigger(true);
  w.update(0.2, aim, world, noopFX);
  assertEquals(target.hits.length, 2, "re-press fires again");
});

Deno.test("reload refills the magazine from reserve", () => {
  const target = new MockTarget("red");
  const world = new MockWorld(target);
  const w = new Weapon(getWeapon("m4"), [], shooter);
  const aim = makeAim();
  w.setTrigger(true);
  for (let i = 0; i < 5; i++) w.update(0.1, aim, world, noopFX);
  w.setTrigger(false);
  w.update(0.1, aim, world, noopFX);
  assertEquals(w.magazine, 25);
  const reserveBefore = w.reserve;
  w.reload();
  w.update(3.0, aim, world, noopFX); // longer than reload time
  assertEquals(w.magazine, 30);
  assertEquals(w.reserve, reserveBefore - 5);
});

Deno.test("headshot multiplier increases damage", () => {
  const target = new MockTarget("red");
  target.isHead = () => true;
  const world = new MockWorld(target);
  const w = new Weapon(getWeapon("m4"), [], shooter);
  w.setTrigger(true);
  w.update(0.1, makeAim(), world, noopFX);
  const dmg = target.hits[0].amount;
  assert(target.hits[0].headshot);
  assert(dmg > getWeapon("m4").damage, "headshot exceeds body damage");
});

Deno.test("friendly fire is ignored", () => {
  const friendly = new MockTarget("blue"); // same team as shooter
  const world = new MockWorld(friendly);
  const w = new Weapon(getWeapon("m4"), [], shooter);
  w.setTrigger(true);
  w.update(0.1, makeAim(), world, noopFX);
  assertEquals(friendly.hits.length, 0);
});

Deno.test("launcher spawns a rocket instead of hitscan", () => {
  const target = new MockTarget("red");
  const world = new MockWorld(target);
  const w = new Weapon(getWeapon("rpg7"), [], { ...shooter, weaponId: "rpg7" });
  w.setTrigger(true);
  w.update(0.1, makeAim(), world, noopFX);
  assertEquals(world.rockets, 1);
  assertEquals(w.magazine, 0);
  assertEquals(target.hits.length, 0, "no direct hitscan damage from a launcher");
});

Deno.test("shotgun fires multiple pellets per shot", () => {
  const target = new MockTarget("red");
  const world = new MockWorld(target);
  const def = getWeapon("spas12");
  const w = new Weapon(def, [], { ...shooter, weaponId: "spas12" });
  w.setTrigger(true);
  w.update(0.1, makeAim(), world, noopFX);
  assertEquals(target.hits.length, def.pellets);
});
