// Objective-mode logic for Domination (capture A/B/C points) and Capture the
// Flag (grab the enemy flag, bring it to your base). Each Objective owns its
// world meshes, advances each live frame against the actor list, tracks the two
// teams' scores, reports a HUD state, and decides when the match is over. The
// Match builds one when the chosen ModeRules requests it.

import * as THREE from "../three.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { addOutline } from "../render/OutlinePass.ts";
import type { Actor } from "../characters/Bot.ts";
import type { TeamId } from "../core/types.ts";
import type { WinResult } from "./Mode.ts";

export interface Bounds {
  minX: number;
  maxX: number;
  minZ: number;
  maxZ: number;
}

export interface ObjectiveCtx {
  actors: Actor[];
  groundAt(x: number, z: number): number;
  bounds: Bounds;
}

export interface ObjectiveHud {
  kind: "dom" | "ctf";
  blue: number;
  red: number;
  cap: number;
  points?: { label: string; owner: TeamId | "neutral"; progress: number }[];
  flags?: { team: TeamId; status: "home" | "carried" | "dropped" }[];
}

export interface Objective {
  readonly root: THREE.Object3D;
  update(dt: number, ctx: ObjectiveCtx): void;
  hud(): ObjectiveHud;
  isOver(elapsed: number, timeLimit: number): WinResult;
  dispose(): void;
}

const BLUE = 0x3b82f6;
const RED = 0xef4444;
const NEUTRAL = 0x9aa0a8;

const _p = new THREE.Vector3();

function ownerColor(owner: TeamId | "neutral"): number {
  return owner === "blue" ? BLUE : owner === "red" ? RED : NEUTRAL;
}

function countInRadius(
  actors: Actor[],
  x: number,
  z: number,
  r: number,
): { blue: number; red: number } {
  let blue = 0;
  let red = 0;
  const r2 = r * r;
  for (const a of actors) {
    if (!a.alive) continue;
    a.position(_p);
    const dx = _p.x - x;
    const dz = _p.z - z;
    if (dx * dx + dz * dz <= r2) {
      if (a.team === "blue") blue++;
      else if (a.team === "red") red++;
    }
  }
  return { blue, red };
}

function timeWinner(blue: number, red: number): TeamId | undefined {
  if (blue > red) return "blue";
  if (red > blue) return "red";
  return undefined;
}

function disposeTree(obj: THREE.Object3D): void {
  obj.traverse((o) => {
    const m = o as THREE.Mesh;
    if (!m.isMesh) return;
    m.geometry?.dispose();
    const mat = m.material;
    if (Array.isArray(mat)) mat.forEach((x) => x.dispose());
    else (mat as THREE.Material)?.dispose();
  });
}

// ---------------------------------------------------------------- Domination

const DOM_RADIUS = 6;
const DOM_CAPTURE_RATE = 0.5; // progress/sec (full capture ≈ 4s uncontested)
const DOM_SCORE_CAP = 200;
const DOM_TICK = 1; // seconds between score ticks

interface DomPoint {
  label: string;
  x: number;
  z: number;
  /** -1 = red owns, 0 = neutral, +1 = blue owns. */
  progress: number;
  owner: TeamId | "neutral";
  disc: THREE.Mesh;
}

export class DominationObjective implements Objective {
  readonly root = new THREE.Group();
  private points: DomPoint[] = [];
  private blue = 0;
  private red = 0;
  private tickAcc = 0;

  constructor(bounds: Bounds, groundAt: (x: number, z: number) => number) {
    const cx = (bounds.minX + bounds.maxX) / 2;
    const spanZ = bounds.maxZ - bounds.minZ;
    const defs = [
      { label: "A", x: cx, z: bounds.minZ + spanZ * 0.28 },
      { label: "B", x: cx, z: (bounds.minZ + bounds.maxZ) / 2 },
      { label: "C", x: cx, z: bounds.minZ + spanZ * 0.72 },
    ];
    for (const d of defs) {
      const disc = new THREE.Mesh(
        new THREE.CylinderGeometry(DOM_RADIUS, DOM_RADIUS, 0.2, 24),
        createToonMaterial({ color: NEUTRAL, emissive: 0x1a1d22 }),
      );
      disc.position.set(d.x, groundAt(d.x, d.z) + 0.1, d.z);
      const pole = new THREE.Mesh(
        new THREE.CylinderGeometry(0.12, 0.12, 3, 8),
        createToonMaterial({ color: 0x20242b }),
      );
      pole.position.set(d.x, groundAt(d.x, d.z) + 1.6, d.z);
      addOutline(pole, { thickness: 0.03 });
      this.root.add(disc, pole);
      this.points.push({ ...d, progress: 0, owner: "neutral", disc });
    }
  }

  update(dt: number, ctx: ObjectiveCtx): void {
    for (const pt of this.points) {
      const { blue, red } = countInRadius(ctx.actors, pt.x, pt.z, DOM_RADIUS);
      // Uncontested presence moves progress toward that team; contested holds.
      if (blue > 0 && red === 0) pt.progress = Math.min(1, pt.progress + DOM_CAPTURE_RATE * dt);
      else if (red > 0 && blue === 0) {
        pt.progress = Math.max(-1, pt.progress - DOM_CAPTURE_RATE * dt);
      }
      const owner: TeamId | "neutral" = pt.progress >= 1
        ? "blue"
        : pt.progress <= -1
        ? "red"
        : "neutral";
      if (owner !== pt.owner) {
        pt.owner = owner;
        (pt.disc.material as THREE.MeshToonMaterial).color.setHex(ownerColor(owner));
      }
    }
    this.tickAcc += dt;
    while (this.tickAcc >= DOM_TICK) {
      this.tickAcc -= DOM_TICK;
      for (const pt of this.points) {
        if (pt.owner === "blue") this.blue++;
        else if (pt.owner === "red") this.red++;
      }
    }
  }

  hud(): ObjectiveHud {
    return {
      kind: "dom",
      blue: this.blue,
      red: this.red,
      cap: DOM_SCORE_CAP,
      points: this.points.map((p) => ({
        label: p.label,
        owner: p.owner,
        progress: (p.progress + 1) / 2,
      })),
    };
  }

  isOver(elapsed: number, timeLimit: number): WinResult {
    if (this.blue >= DOM_SCORE_CAP || this.red >= DOM_SCORE_CAP) {
      return { over: true, winner: this.blue >= this.red ? "blue" : "red", reason: "score" };
    }
    if (elapsed >= timeLimit) {
      return { over: true, winner: timeWinner(this.blue, this.red), reason: "time" };
    }
    return { over: false };
  }

  dispose(): void {
    disposeTree(this.root);
  }
}

// ------------------------------------------------------------ Capture the Flag

const CTF_PICKUP_RADIUS = 2.2;
const CTF_CAP = 3; // captures to win

interface Flag {
  team: TeamId;
  home: THREE.Vector3;
  pos: THREE.Vector3;
  status: "home" | "carried" | "dropped";
  carrier: number | undefined;
  group: THREE.Group;
}

export class CaptureTheFlagObjective implements Objective {
  readonly root = new THREE.Group();
  private flags: Flag[] = [];
  private blue = 0;
  private red = 0;

  constructor(bounds: Bounds, groundAt: (x: number, z: number) => number) {
    const cx = (bounds.minX + bounds.maxX) / 2;
    const make = (team: TeamId, z: number): Flag => {
      const home = new THREE.Vector3(cx, groundAt(cx, z), z);
      const group = new THREE.Group();
      const pole = new THREE.Mesh(
        new THREE.CylinderGeometry(0.08, 0.08, 3, 8),
        createToonMaterial({ color: 0x20242b }),
      );
      pole.position.y = 1.5;
      const cloth = new THREE.Mesh(
        new THREE.BoxGeometry(1.1, 0.7, 0.06),
        createToonMaterial({ color: team === "blue" ? BLUE : RED, emissive: 0x101418 }),
      );
      cloth.position.set(0.6, 2.4, 0);
      addOutline(cloth, { thickness: 0.03 });
      group.add(pole, cloth);
      group.position.copy(home);
      this.root.add(group);
      return { team, home, pos: home.clone(), status: "home", carrier: undefined, group };
    };
    this.flags.push(make("blue", bounds.minZ + 8));
    this.flags.push(make("red", bounds.maxZ - 8));
  }

  update(_dt: number, ctx: ObjectiveCtx): void {
    for (const flag of this.flags) {
      const enemyTeam: TeamId = flag.team === "blue" ? "red" : "blue";
      if (flag.status === "carried") {
        const carrier = ctx.actors.find((a) => a.id === flag.carrier);
        if (!carrier || !carrier.alive) {
          // Carrier down → flag drops where they fell.
          if (carrier) carrier.position(flag.pos);
          flag.status = "dropped";
          flag.carrier = undefined;
        } else {
          carrier.position(flag.pos);
          flag.pos.y = ctx.groundAt(flag.pos.x, flag.pos.z);
          // Capture: carrier reaches their OWN flag while it is home.
          const own = this.flags.find((f) => f.team === carrier.team);
          if (own && own.status === "home" && flag.pos.distanceTo(own.home) < CTF_PICKUP_RADIUS) {
            if (carrier.team === "blue") this.blue++;
            else this.red++;
            this.returnHome(flag);
          }
        }
      } else {
        for (const a of ctx.actors) {
          if (!a.alive) continue;
          a.position(_p);
          if (_p.distanceTo(flag.pos) > CTF_PICKUP_RADIUS) continue;
          if (a.team === enemyTeam) {
            flag.status = "carried";
            flag.carrier = a.id;
            break;
          } else if (a.team === flag.team && flag.status === "dropped") {
            this.returnHome(flag);
            break;
          }
        }
      }
      flag.group.position.set(flag.pos.x, flag.pos.y, flag.pos.z);
    }
  }

  private returnHome(flag: Flag): void {
    flag.status = "home";
    flag.carrier = undefined;
    flag.pos.copy(flag.home);
  }

  hud(): ObjectiveHud {
    return {
      kind: "ctf",
      blue: this.blue,
      red: this.red,
      cap: CTF_CAP,
      flags: this.flags.map((f) => ({ team: f.team, status: f.status })),
    };
  }

  isOver(elapsed: number, timeLimit: number): WinResult {
    if (this.blue >= CTF_CAP || this.red >= CTF_CAP) {
      return { over: true, winner: this.blue >= this.red ? "blue" : "red", reason: "score" };
    }
    if (elapsed >= timeLimit) {
      return { over: true, winner: timeWinner(this.blue, this.red), reason: "time" };
    }
    return { over: false };
  }

  dispose(): void {
    disposeTree(this.root);
  }
}

export function buildObjective(
  kind: "dom" | "ctf",
  bounds: Bounds,
  groundAt: (x: number, z: number) => number,
): Objective {
  return kind === "ctf"
    ? new CaptureTheFlagObjective(bounds, groundAt)
    : new DominationObjective(bounds, groundAt);
}
