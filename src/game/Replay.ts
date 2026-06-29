// Plays back a recorded window of actor snapshots using throwaway "ghost"
// avatars, and positions the camera for the two replay flavours:
//   - killcam: from the killer's eyes, looking at the victim;
//   - chase:   behind the focused player (post-match "best play").
// The ghosts live under their own root so the live scene can be hidden while a
// killcam plays without hiding the replay.

import * as THREE from "../three.ts";
import { ProceduralHuman } from "../characters/ProceduralHuman.ts";
import { type ActorSnap, type ReplayFrame, sampleAt } from "./ReplayRecorder.ts";

export class Replay {
  private readonly root = new THREE.Group();
  private readonly ghosts = new Map<number, ProceduralHuman>();
  private elapsed = 0;
  readonly duration: number;
  private readonly startT: number;
  private snaps = new Map<number, ActorSnap>();

  constructor(private readonly parent: THREE.Object3D, private readonly frames: ReplayFrame[]) {
    this.startT = frames.length ? frames[0].t : 0;
    this.duration = frames.length ? frames[frames.length - 1].t - this.startT : 0;
    parent.add(this.root);
  }

  get finished(): boolean {
    return this.elapsed >= this.duration;
  }
  get progress(): number {
    return this.duration > 0 ? Math.min(1, this.elapsed / this.duration) : 1;
  }

  /** Advance playback by dt*speed and sync the ghost avatars. */
  advance(dt: number, speed: number): void {
    this.elapsed = Math.min(this.duration, this.elapsed + dt * speed);
    this.snaps = sampleAt(this.frames, this.startT + this.elapsed);
    for (const [id, s] of this.snaps) {
      let g = this.ghosts.get(id);
      if (!g) {
        g = new ProceduralHuman({ team: s.team, accentIndex: id % 6 });
        this.root.add(g.root);
        this.ghosts.set(id, g);
      }
      g.root.position.set(s.x, s.y, s.z);
      g.root.rotation.y = s.yaw;
      g.play(s.anim);
      g.update(dt * speed);
      g.root.visible = s.alive;
    }
  }

  current(): Map<number, ActorSnap> {
    return this.snaps;
  }

  dispose(): void {
    for (const g of this.ghosts.values()) g.dispose();
    this.ghosts.clear();
    this.parent.remove(this.root);
  }
}

const _look = new THREE.Vector3();

/** Camera at the killer's eyes, looking at the victim (falls back to an orbit). */
export function killcamView(
  cam: THREE.PerspectiveCamera,
  snaps: Map<number, ActorSnap>,
  killerId: number | undefined,
  victimId: number,
): void {
  const k = killerId !== undefined ? snaps.get(killerId) : undefined;
  const v = snaps.get(victimId);
  if (!k) {
    if (v) {
      cam.position.set(v.x + 3.5, v.y + 2.6, v.z + 3.5);
      cam.lookAt(_look.set(v.x, v.y + 1.0, v.z));
    }
    return;
  }
  cam.position.set(k.x, k.y + 1.55, k.z);
  if (v) cam.lookAt(_look.set(v.x, v.y + 1.0, v.z));
  else cam.lookAt(_look.set(k.x + Math.sin(k.yaw), k.y + 1.55, k.z + Math.cos(k.yaw)));
}

/** Chase camera behind the focused actor (best-play replay). */
export function chaseView(
  cam: THREE.PerspectiveCamera,
  snaps: Map<number, ActorSnap>,
  focusId: number,
): void {
  const f = snaps.get(focusId);
  if (!f) return;
  const fx = Math.sin(f.yaw);
  const fz = Math.cos(f.yaw);
  cam.position.set(f.x - fx * 4.5, f.y + 2.6, f.z - fz * 4.5);
  cam.lookAt(_look.set(f.x + fx * 2, f.y + 1.2, f.z + fz * 2));
}
