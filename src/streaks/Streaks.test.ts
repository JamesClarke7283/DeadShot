import { assert, assertEquals } from "@std/assert";
import * as THREE from "../three.ts";
import type { Actor } from "../characters/Bot.ts";
import type {
  DamageInfo,
  DamageTarget,
  RaycastHit,
  VFXSink,
  WorldQuery,
} from "../weapons/combat.ts";
import type { TeamId } from "../core/types.ts";
import { type StreakContext, type StreakOwner } from "./Streak.ts";
import { getStreak, STREAKS } from "./streaks.ts";
import { UAV } from "./UAV.ts";
import { Nuke } from "./Nuke.ts";
import { SentryGun } from "./SentryGun.ts";
import { PredatorMissile } from "./PredatorMissile.ts";
import { RCXD } from "./RCXD.ts";
import { CarePackage } from "./CarePackage.ts";
import { Juggernaut } from "./Juggernaut.ts";

// ---- Mocks ----

class MockActor implements Actor {
  readonly object3d = new THREE.Object3D();
  alive = true;
  health = 100;
  maxHealth = 100;
  taken = 0;
  readonly hits: DamageInfo[] = [];

  constructor(
    readonly id: number,
    public team: TeamId,
    readonly isPlayer: boolean,
    private readonly pos: THREE.Vector3,
  ) {}

  position(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.pos).setY(this.pos.y + 1);
  }
  eyePosition(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.pos).setY(this.pos.y + 1.6);
  }
  isHead(): boolean {
    return false;
  }
  applyDamage(info: DamageInfo): void {
    if (!this.alive) return;
    this.hits.push(info);
    this.taken += info.amount;
    this.health -= info.amount;
    if (this.health <= 0) {
      this.health = 0;
      this.alive = false;
    }
  }
  setPos(x: number, y: number, z: number): void {
    this.pos.set(x, y, z);
  }
}

const noopFX: VFXSink = {
  bulletImpact() {},
  tracer() {},
  muzzleFlash() {},
  explosion() {},
};

class MockWorld implements WorldQuery {
  constructor(private readonly actors: MockActor[]) {}
  raycast(): RaycastHit | null {
    return null; // clear LOS
  }
  radiusTargets(center: THREE.Vector3, radius: number): DamageTarget[] {
    const out: DamageTarget[] = [];
    const tmp = new THREE.Vector3();
    for (const a of this.actors) {
      if (!a.alive) continue;
      a.position(tmp);
      if (tmp.distanceTo(center) <= radius) out.push(a);
    }
    return out;
  }
}

interface MockCtx extends StreakContext {
  pings: { team: TeamId; count: number }[];
  counterUAV: { team: TeamId; dur: number } | null;
  granted: StreakOwner[];
  matchWinner: TeamId | number | null;
  fxExplosions: number;
}

function makeCtx(owner: StreakOwner, actors: MockActor[]): MockCtx {
  const root = new THREE.Object3D();
  const world = new MockWorld(actors);
  const fx: VFXSink = {
    ...noopFX,
    explosion() {
      ctx.fxExplosions++;
    },
  };
  const ctx: MockCtx = {
    world,
    vfx: fx,
    root,
    owner,
    bounds: { minX: -25, maxX: 25, minZ: -25, maxZ: 25 },
    pings: [],
    counterUAV: null,
    granted: [],
    matchWinner: null,
    fxExplosions: 0,
    localPlayerId: null,
    allActors: () => actors,
    enemiesOf(team: TeamId) {
      return actors.filter((a) => a.alive && (team === "ffa" || a.team !== team));
    },
    groundAt: () => 0,
    ping(team, positions) {
      ctx.pings.push({ team, count: positions.length });
    },
    setCounterUAV(team, dur) {
      ctx.counterUAV = { team, dur };
    },
    spawnCarePackage() {},
    grantRandomStreak(o) {
      ctx.granted.push(o);
      return "uav";
    },
    endMatch(winner) {
      ctx.matchWinner = winner;
    },
  };
  return ctx;
}

function step(
  s: { active: boolean; update(dt: number, ctx: StreakContext): void },
  ctx: MockCtx,
  dt: number,
  steps: number,
): void {
  for (let i = 0; i < steps && s.active; i++) s.update(dt, ctx);
}

// ---- Registry ----

Deno.test("registry exposes all 12 streaks and getStreak resolves them", () => {
  assertEquals(STREAKS.length, 12);
  for (const def of STREAKS) {
    assertEquals(getStreak(def.id).id, def.id);
    const inst = def.create();
    assertEquals(inst.id, def.id);
    assert(inst.active);
  }
});

Deno.test("getStreak throws on unknown id", () => {
  let threw = false;
  try {
    getStreak("nope");
  } catch {
    threw = true;
  }
  assert(threw);
});

// ---- UAV ----

Deno.test("UAV pings team and eventually expires", () => {
  const owner: StreakOwner = { id: 1, team: "blue" };
  const me = new MockActor(1, "blue", true, new THREE.Vector3(0, 0, 0));
  const enemy = new MockActor(2, "red", false, new THREE.Vector3(5, 0, 5));
  const ctx = makeCtx(owner, [me, enemy]);
  const uav = new UAV();
  // Run a couple seconds: should ping at least a few times.
  step(uav, ctx, 0.1, 30);
  assert(ctx.pings.length >= 1, "UAV pinged at least once");
  assertEquals(ctx.pings[0].team, "blue");
  assertEquals(ctx.pings[0].count, 1, "one enemy revealed");
  // Run past its 25s lifetime.
  step(uav, ctx, 0.5, 60);
  assertEquals(uav.active, false);
});

// ---- Nuke ----

Deno.test("Nuke ends match for owner team after countdown", () => {
  const owner: StreakOwner = { id: 1, team: "red" };
  const ctx = makeCtx(owner, []);
  const nuke = new Nuke();
  step(nuke, ctx, 0.25, 3); // < 6s
  assertEquals(ctx.matchWinner, null, "no end before countdown");
  step(nuke, ctx, 0.5, 20); // well past 6s
  assertEquals(ctx.matchWinner, "red");
  assertEquals(nuke.active, false);
});

// ---- SentryGun ----

Deno.test("SentryGun damages an in-range enemy within a couple seconds", () => {
  const owner: StreakOwner = { id: 1, team: "blue" };
  const me = new MockActor(1, "blue", true, new THREE.Vector3(0, 0, 0));
  const enemy = new MockActor(2, "red", false, new THREE.Vector3(6, 0, 0));
  const ctx = makeCtx(owner, [me, enemy]);
  const sentry = new SentryGun();
  step(sentry, ctx, 0.1, 30); // 3 seconds
  assert(enemy.taken > 0, "sentry dealt damage");
  assert(enemy.hits.length >= 2, "fired multiple bursts");
});

Deno.test("SentryGun ignores out-of-range enemies", () => {
  const owner: StreakOwner = { id: 1, team: "blue" };
  const me = new MockActor(1, "blue", true, new THREE.Vector3(0, 0, 0));
  const far = new MockActor(2, "red", false, new THREE.Vector3(200, 0, 0));
  const ctx = makeCtx(owner, [me, far]);
  const sentry = new SentryGun();
  step(sentry, ctx, 0.1, 20);
  assertEquals(far.taken, 0);
});

// ---- PredatorMissile ----

Deno.test("PredatorMissile explodes and damages an enemy in splash", () => {
  const owner: StreakOwner = { id: 1, team: "blue" };
  const me = new MockActor(1, "blue", true, new THREE.Vector3(0, 0, 0));
  const enemy = new MockActor(2, "red", false, new THREE.Vector3(2, 0, 2));
  const ctx = makeCtx(owner, [me, enemy]);
  const missile = new PredatorMissile();
  step(missile, ctx, 0.1, 100); // dives and detonates
  assertEquals(missile.active, false);
  assert(ctx.fxExplosions >= 1, "explosion VFX fired");
  assert(enemy.taken > 0, "splash damaged the enemy");
});

// ---- RCXD ----

Deno.test("RCXD drives to an enemy and detonates with splash", () => {
  const owner: StreakOwner = { id: 1, team: "blue" };
  const me = new MockActor(1, "blue", true, new THREE.Vector3(0, 0, 0));
  const enemy = new MockActor(2, "red", false, new THREE.Vector3(10, 0, 0));
  const ctx = makeCtx(owner, [me, enemy]);
  const rc = new RCXD();
  step(rc, ctx, 0.1, 100);
  assertEquals(rc.active, false);
  assert(ctx.fxExplosions >= 1);
  assert(enemy.taken > 0, "RC-XD splash damaged the enemy");
});

// ---- CarePackage ----

Deno.test("CarePackage grants a random streak to a nearby actor after it lands", () => {
  const owner: StreakOwner = { id: 1, team: "blue" };
  const me = new MockActor(1, "blue", true, new THREE.Vector3(0, 0, 0));
  const ctx = makeCtx(owner, [me]);
  const pkg = new CarePackage();
  // Let it fall and be captured by the owner standing under it.
  step(pkg, ctx, 0.1, 100);
  assertEquals(ctx.granted.length, 1, "one grant issued");
  assertEquals(ctx.granted[0].id, 1);
  assertEquals(pkg.active, false);
});

Deno.test("CarePackage times out if no live actor captures it", () => {
  const owner: StreakOwner = { id: 1, team: "blue" };
  const me = new MockActor(1, "blue", true, new THREE.Vector3(0, 0, 0));
  // The only actor is dead, so it cannot capture the package.
  me.alive = false;
  const ctx = makeCtx(owner, [me]);
  const pkg = new CarePackage();
  step(pkg, ctx, 0.5, 70); // > 30s
  assertEquals(ctx.granted.length, 0);
  assertEquals(pkg.active, false);
});

// ---- Juggernaut ----

Deno.test("Juggernaut sets owner health to 300 while active", () => {
  const owner: StreakOwner = { id: 1, team: "blue" };
  const me = new MockActor(1, "blue", true, new THREE.Vector3(0, 0, 0));
  const ctx = makeCtx(owner, [me]);
  const jug = new Juggernaut();
  jug.update(0.1, ctx);
  assertEquals(me.health, 300);
  assertEquals(me.maxHealth, 300);
  assert(jug.active);
  // Run past the 30s duration: restored to base.
  step(jug, ctx, 0.5, 70);
  assertEquals(jug.active, false);
  assertEquals(me.maxHealth, 100);
  assert(me.health <= 100);
});
