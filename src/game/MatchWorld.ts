// MatchWorld: the WorldQuery used during a live match.
//
// World geometry is tested with a real raycaster against the map root; actors
// (player + bots) are tested analytically as a body sphere + a head sphere, so
// there is no dependence on per-actor hitbox meshes or their visibility, and we
// can report headshots directly. Hits closer than ~0.6m to the ray origin are
// treated as the shooter's own body and ignored (self-fire protection).

import * as THREE from "../three.ts";
import type { Actor } from "../characters/Bot.ts";
import type { RaycastHit, ShooterTag, VFXSink, WorldQuery } from "../weapons/combat.ts";
import { ProjectilePool } from "../weapons/Projectile.ts";
import { Rocket } from "../weapons/Rocket.ts";
import { getWeapon } from "../weapons/WeaponDefinition.ts";

const BODY_RADIUS = 0.6;
const HEAD_RADIUS = 0.28;
const SELF_SKIP = 0.6;

export class MatchWorld implements WorldQuery {
  private raycaster = new THREE.Raycaster();
  private _body = new THREE.Vector3();
  private _head = new THREE.Vector3();

  constructor(
    private mapRoot: THREE.Object3D,
    private getActors: () => Actor[],
    private pool: ProjectilePool,
    private vfx: VFXSink,
  ) {}

  raycast(
    origin: THREE.Vector3,
    direction: THREE.Vector3,
    maxDistance: number,
  ): RaycastHit | null {
    // World geometry.
    this.raycaster.set(origin, direction);
    this.raycaster.far = maxDistance;
    let best: RaycastHit | null = null;
    let bestDist = maxDistance;
    const geo = this.raycaster.intersectObject(this.mapRoot, true);
    for (const h of geo) {
      if (h.object.name === "__outline" || !h.face) continue;
      bestDist = h.distance;
      best = {
        point: h.point.clone(),
        normal: h.face.normal.clone().transformDirection(h.object.matrixWorld),
        distance: h.distance,
        object: h.object,
      };
      break;
    }

    // Actors (analytic spheres).
    for (const a of this.getActors()) {
      if (!a.alive) continue;
      a.position(this._body); // body centre ~ feet + 1
      a.eyePosition(this._head); // head/eye centre
      const bodyT = raySphere(origin, direction, this._body, BODY_RADIUS);
      const headT = raySphere(origin, direction, this._head, HEAD_RADIUS);

      let t = -1;
      let headshot = false;
      if (headT > SELF_SKIP && (t < 0 || headT < t)) {
        t = headT;
        headshot = true;
      }
      if (bodyT > SELF_SKIP && (t < 0 || bodyT < t)) {
        t = bodyT;
        headshot = false;
      }
      if (t > SELF_SKIP && t < bestDist) {
        bestDist = t;
        const point = origin.clone().addScaledVector(direction, t);
        const center = headshot ? this._head : this._body;
        best = {
          point,
          normal: point.clone().sub(center).normalize(),
          distance: t,
          object: a.object3d,
          target: a,
          headshot,
        };
      }
    }
    return best;
  }

  radiusTargets(center: THREE.Vector3, radius: number): Actor[] {
    const p = new THREE.Vector3();
    return this.getActors().filter((a) => a.alive && a.position(p).distanceTo(center) <= radius);
  }

  spawnRocket(origin: THREE.Vector3, direction: THREE.Vector3, owner: ShooterTag): void {
    const def = getWeapon(owner.weaponId);
    if (!def.rocket) return;
    const rocket = new Rocket(def.rocket, owner);
    rocket.init({
      position: origin.clone(),
      velocity: direction.clone().multiplyScalar(def.rocket.speed),
      gravity: 3,
      maxLifetime: 6,
      maxRange: 300,
    });
    this.pool.spawn(rocket);
  }

  update(dt: number): void {
    this.pool.update(dt, this, this.vfx);
  }
}

/** Nearest positive ray-sphere intersection distance (dir must be normalized). */
function raySphere(
  o: THREE.Vector3,
  d: THREE.Vector3,
  c: THREE.Vector3,
  r: number,
): number {
  const ox = o.x - c.x, oy = o.y - c.y, oz = o.z - c.z;
  const b = ox * d.x + oy * d.y + oz * d.z;
  const cc = ox * ox + oy * oy + oz * oz - r * r;
  const disc = b * b - cc;
  if (disc < 0) return -1;
  const sq = Math.sqrt(disc);
  const t1 = -b - sq;
  if (t1 >= 0) return t1;
  const t2 = -b + sq;
  return t2 >= 0 ? t2 : -1;
}
