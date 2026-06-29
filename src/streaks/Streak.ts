// Scorestreak contracts.
//
// A Streak is an activatable ability (UAV, sentry, helicopter, nuke, ...). Once
// activated it lives in the Match's active-streak list and ticks each frame via
// update() until it sets active=false. StreakContext is everything a streak can
// do to the world (find/damage enemies, ping the minimap, spawn a care package,
// end the match for a nuke). Match implements StreakContext.

import type * as THREE from "../three.ts";
import type { TeamId } from "../core/types.ts";
import type { Actor } from "../characters/Bot.ts";
import type { DamageInfo, VFXSink, WorldQuery } from "../weapons/combat.ts";

export interface StreakOwner {
  id: number;
  team: TeamId;
}

export interface StreakContext {
  world: WorldQuery;
  vfx: VFXSink;
  /** Scene node streak meshes attach to (scene.dynamicRoot). */
  root: THREE.Object3D;
  owner: StreakOwner;
  allActors(): Actor[];
  /** Alive enemies of `team` (everyone else in FFA). */
  enemiesOf(team: TeamId): Actor[];
  groundAt(x: number, z: number): number;
  bounds: { minX: number; maxX: number; minZ: number; maxZ: number };

  /** Reveal positions on `team`'s minimap for a duration (UAV). */
  ping(team: TeamId, positions: THREE.Vector3[], durationSec: number): void;
  /** Suppress `againstTeam`'s minimap for a duration (Counter-UAV). */
  setCounterUAV(againstTeam: TeamId, durationSec: number): void;
  /** Drop a capturable care package. */
  spawnCarePackage(position: THREE.Vector3, owner: StreakOwner): void;
  /** Register a landed care-package crate (persists; collect with E / proximity). */
  armCarePackage(position: THREE.Vector3): void;
  /** Grant a random streak to an owner (care package payload); returns its id. */
  grantRandomStreak(owner: StreakOwner): string;
  /** End the match immediately (Nuke). */
  endMatch(winner: TeamId | number): void;
  /** Local player id, or null in a headless / spectated match. */
  localPlayerId: number | null;
}

export abstract class Streak {
  active = true;
  abstract readonly id: string;
  abstract readonly name: string;
  protected mesh: THREE.Object3D | null = null;

  /** Advance one frame; set active=false when finished. */
  abstract update(dt: number, ctx: StreakContext): void;

  dispose(ctx: StreakContext): void {
    if (this.mesh) {
      ctx.root.remove(this.mesh);
      this.mesh = null;
    }
  }
}

export interface StreakDef {
  id: string;
  name: string;
  /** Streak score required to earn it. */
  cost: number;
  create(): Streak;
}

/** Helper: deal damage from a streak's owner to an actor. */
export function streakDamage(
  target: Actor,
  amount: number,
  ctx: StreakContext,
  explosive = false,
): void {
  if (!target.alive) return;
  if (ctx.owner.team !== "ffa" && target.team === ctx.owner.team) return;
  const info: DamageInfo = {
    amount,
    headshot: false,
    sourceTeam: ctx.owner.team,
    sourceId: ctx.owner.id,
    explosive,
    weaponId: "streak",
  };
  target.applyDamage(info);
}
