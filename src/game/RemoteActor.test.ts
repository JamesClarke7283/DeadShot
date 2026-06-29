import { assert, assertEquals } from "@std/assert";
import * as THREE from "../three.ts";
import { RemoteActor } from "./RemoteActor.ts";
import type { DamageInfo } from "../weapons/combat.ts";

Deno.test("applyDamage forwards a network hit instead of mutating local health", () => {
  const hits: { target: number; info: DamageInfo }[] = [];
  const ra = new RemoteActor(5, "red", "Bob", (target, info) => hits.push({ target, info }));
  assertEquals(ra.alive, true);

  ra.applyDamage({ amount: 40, headshot: true, sourceTeam: "blue", sourceId: 1, weaponId: "m4" });

  assertEquals(hits.length, 1);
  assertEquals(hits[0].target, 5);
  assertEquals(hits[0].info.amount, 40);
  assertEquals(hits[0].info.headshot, true);
  assertEquals(ra.alive, true, "remote actor health is authoritative on its owner, not here");
});

Deno.test("dead remote actors swallow further hits", () => {
  const hits: number[] = [];
  const ra = new RemoteActor(5, "red", "Bob", (t) => hits.push(t));
  ra.markDead();
  assertEquals(ra.alive, false);
  ra.applyDamage({ amount: 10, headshot: false, sourceTeam: "blue" });
  assertEquals(hits.length, 0);
});

Deno.test("applyState snaps on the first packet then drives transform", () => {
  const ra = new RemoteActor(2, "blue", "A", () => {});
  ra.applyState({ x: 10, y: 0, z: -4, yaw: 1.2, anim: "run", alive: true, weaponId: "ak12" });
  assertEquals(ra.feet.x, 10);
  assertEquals(ra.feet.z, -4);
  assertEquals(ra.yaw, 1.2);
  assertEquals(ra.weaponId, "ak12");
  ra.update(1 / 60);
  // object3d follows the feet; head/body queries are world-space.
  assertEquals(ra.object3d.position.x, ra.feet.x);
  const body = ra.position(new THREE.Vector3());
  assert(body.y > ra.feet.y);
});
