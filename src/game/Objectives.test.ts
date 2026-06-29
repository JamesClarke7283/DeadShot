import { assert, assertEquals } from "@std/assert";
import * as THREE from "../three.ts";
import { CaptureTheFlagObjective, DominationObjective, type ObjectiveCtx } from "./Objectives.ts";
import type { Actor } from "../characters/Bot.ts";
import type { TeamId } from "../core/types.ts";

class MockActor implements Actor {
  readonly isPlayer = false;
  readonly object3d = new THREE.Object3D();
  alive = true;
  constructor(readonly id: number, public team: TeamId, public x: number, public z: number) {}
  at(x: number, z: number): this {
    this.x = x;
    this.z = z;
    return this;
  }
  position(out: THREE.Vector3): THREE.Vector3 {
    return out.set(this.x, 1, this.z);
  }
  eyePosition(out: THREE.Vector3): THREE.Vector3 {
    return out.set(this.x, 1.6, this.z);
  }
  isHead(): boolean {
    return false;
  }
  applyDamage(): void {}
}

// Roomy bounds so CTF bases (minZ+8 / maxZ-8) are far apart, like a real map.
const BOUNDS = { minX: -40, maxX: 40, minZ: -40, maxZ: 40 };
const ground = () => 0;
function ctx(actors: Actor[]): ObjectiveCtx {
  return { actors, groundAt: ground, bounds: BOUNDS };
}

Deno.test("Domination: a lone team captures a point and scores while holding it", () => {
  const obj = new DominationObjective(BOUNDS, ground);
  const blue = new MockActor(1, "blue", 0, 0); // standing on point B (map center)
  const c = ctx([blue]);
  for (let i = 0; i < 60; i++) obj.update(0.1, c); // ~6s
  const h = obj.hud();
  assertEquals(h.kind, "dom");
  assertEquals(h.points![1].owner, "blue", "centre point captured by blue");
  assert(h.blue >= 3, `blue should accrue score while holding (got ${h.blue})`);
  assertEquals(h.red, 0);
  obj.dispose();
});

Deno.test("Domination: a contested point does not progress", () => {
  const obj = new DominationObjective(BOUNDS, ground);
  const blue = new MockActor(1, "blue", 0, 0);
  const red = new MockActor(2, "red", 0, 0);
  const c = ctx([blue, red]);
  for (let i = 0; i < 40; i++) obj.update(0.1, c);
  assertEquals(obj.hud().points![1].owner, "neutral", "contested point stays neutral");
});

Deno.test("CTF: grab the enemy flag, return it home to score", () => {
  const obj = new CaptureTheFlagObjective(BOUNDS, ground);
  // blue flag home z = -40+8 = -32 ; red flag home z = 40-8 = 32.
  const blue = new MockActor(1, "blue", 0, 32); // on the red flag
  const c = ctx([blue]);
  obj.update(0.1, c);
  const grabbed = obj.hud().flags!.find((f) => f.team === "red")!;
  assertEquals(grabbed.status, "carried", "red flag is taken by the blue player");

  // Carry it to the blue base (blue flag is home).
  blue.at(0, -32);
  obj.update(0.1, c);
  const h = obj.hud();
  assertEquals(h.blue, 1, "blue captured");
  assertEquals(h.flags!.find((f) => f.team === "red")!.status, "home", "red flag returns home");
  obj.dispose();
});

Deno.test("CTF: a downed carrier drops the flag; the owner can return it", () => {
  const obj = new CaptureTheFlagObjective(BOUNDS, ground);
  const blue = new MockActor(1, "blue", 0, 32); // grab red flag
  obj.update(0.1, ctx([blue]));
  blue.at(0, 0); // carry toward midfield (far from both bases)
  obj.update(0.1, ctx([blue]));
  blue.alive = false; // carrier down -> flag drops
  obj.update(0.1, ctx([blue]));
  assertEquals(obj.hud().flags!.find((f) => f.team === "red")!.status, "dropped");

  // A red player touches the dropped flag to return it.
  const red = new MockActor(2, "red", 0, 0);
  obj.update(0.1, ctx([blue, red]));
  assertEquals(obj.hud().flags!.find((f) => f.team === "red")!.status, "home");
  obj.dispose();
});
