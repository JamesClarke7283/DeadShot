// Records a rolling history of every actor's transform so the game can play it
// back later — the death killcam (last few seconds from the killer's view) and
// the post-match "best play" (the player's best killstreak). It stores cheap
// per-actor snapshots at a fixed rate; the live Match feeds it each frame and
// the Replay player interpolates between frames on the way out.

import type { TeamId } from "../core/types.ts";
import type { AnimName } from "../characters/Character.ts";

export interface ActorSnap {
  id: number;
  team: TeamId;
  name: string;
  isPlayer: boolean;
  x: number;
  y: number;
  z: number;
  yaw: number;
  alive: boolean;
  anim: AnimName;
  weaponId: string;
}

export interface ReplayFrame {
  t: number; // match-elapsed seconds
  actors: ActorSnap[];
}

export class ReplayRecorder {
  private frames: ReplayFrame[] = [];

  constructor(private readonly durationSec = 8, private readonly hz = 30) {}

  /** Record a frame (throttled to ~hz); prunes anything older than durationSec. */
  record(t: number, actors: ActorSnap[]): void {
    const last = this.frames.length ? this.frames[this.frames.length - 1].t : -Infinity;
    if (t - last < 1 / this.hz) return;
    this.frames.push({ t, actors });
    const cutoff = t - this.durationSec;
    while (this.frames.length > 1 && this.frames[0].t < cutoff) this.frames.shift();
  }

  /** Copy of the frames within [tStart, tEnd] (inclusive). */
  window(tStart: number, tEnd: number): ReplayFrame[] {
    return this.frames.filter((f) => f.t >= tStart && f.t <= tEnd).map(cloneFrame);
  }

  /** The most recent `secs` seconds of frames (copied). */
  recent(now: number, secs: number): ReplayFrame[] {
    return this.window(now - secs, now);
  }

  get latest(): number {
    return this.frames.length ? this.frames[this.frames.length - 1].t : 0;
  }

  clear(): void {
    this.frames = [];
  }
}

function cloneFrame(f: ReplayFrame): ReplayFrame {
  return { t: f.t, actors: f.actors.map((a) => ({ ...a })) };
}

/** Sample a replay window at time `t`, lerping between the two bracketing frames. */
export function sampleAt(frames: ReplayFrame[], t: number): Map<number, ActorSnap> {
  const out = new Map<number, ActorSnap>();
  if (frames.length === 0) return out;
  // Find the frame pair bracketing t.
  let i = 0;
  while (i < frames.length - 1 && frames[i + 1].t <= t) i++;
  const a = frames[i];
  const b = frames[Math.min(i + 1, frames.length - 1)];
  const span = b.t - a.t;
  const u = span > 1e-6 ? Math.max(0, Math.min(1, (t - a.t) / span)) : 0;

  const bById = new Map(b.actors.map((s) => [s.id, s]));
  for (const sa of a.actors) {
    const sb = bById.get(sa.id) ?? sa;
    out.set(sa.id, {
      ...sa,
      x: lerp(sa.x, sb.x, u),
      y: lerp(sa.y, sb.y, u),
      z: lerp(sa.z, sb.z, u),
      yaw: lerpAngle(sa.yaw, sb.yaw, u),
      // Discrete fields snap to the earlier frame (anim/alive don't interpolate).
      alive: sa.alive,
      anim: sa.anim,
    });
  }
  // Actors that appear only in the later frame (e.g. spawned mid-window).
  for (const sb of b.actors) if (!out.has(sb.id)) out.set(sb.id, { ...sb });
  return out;
}

function lerp(a: number, b: number, u: number): number {
  return a + (b - a) * u;
}

function lerpAngle(a: number, b: number, u: number): number {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return a + d * u;
}
