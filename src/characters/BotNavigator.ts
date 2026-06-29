// Bot navigation: A* over a map's waypoint graph with line-of-sight shortcuts.
//
// Given the Waypoint[] a map produces (see maps/Waypoints.ts), Navigator finds a
// path from a world position to a goal, returning the sequence of points to walk.
// A funnel-ish smoothing step drops intermediate waypoints when the straight
// segment between two points is unobstructed (optional collision query), so bots
// cut corners instead of marching node-to-node.

import * as THREE from "../three.ts";
import type { Waypoint } from "../maps/MapDefinition.ts";

export interface LineOfSight {
  /** True if a straight walk from a to b is unobstructed. */
  clear(a: THREE.Vector3, b: THREE.Vector3): boolean;
}

export class Navigator {
  private waypoints: Waypoint[];
  private byId = new Map<number, Waypoint>();

  constructor(waypoints: Waypoint[]) {
    this.waypoints = waypoints;
    for (const w of waypoints) this.byId.set(w.id, w);
  }

  get size(): number {
    return this.waypoints.length;
  }

  /** Nearest waypoint to a world position (null if the graph is empty). */
  nearest(pos: THREE.Vector3): Waypoint | null {
    let best: Waypoint | null = null;
    let bestD = Infinity;
    for (const w of this.waypoints) {
      const d = w.position.distanceToSquared(pos);
      if (d < bestD) {
        bestD = d;
        best = w;
      }
    }
    return best;
  }

  /**
   * A* path of world positions from `start` to `goal`. Returns [] if no path.
   * The returned array ends at `goal`. `los` (optional) enables smoothing.
   */
  findPath(start: THREE.Vector3, goal: THREE.Vector3, los?: LineOfSight): THREE.Vector3[] {
    const startNode = this.nearest(start);
    const goalNode = this.nearest(goal);
    if (!startNode || !goalNode) return [];
    if (startNode.id === goalNode.id) return [goal.clone()];

    const open = new MinHeap();
    const gScore = new Map<number, number>();
    const fScore = new Map<number, number>();
    const cameFrom = new Map<number, number>();

    gScore.set(startNode.id, 0);
    fScore.set(startNode.id, startNode.position.distanceTo(goalNode.position));
    open.push(startNode.id, fScore.get(startNode.id)!);

    const closed = new Set<number>();

    while (!open.isEmpty()) {
      const current = open.pop()!;
      if (current === goalNode.id) {
        return this.reconstruct(cameFrom, current, goal, los);
      }
      closed.add(current);
      const node = this.byId.get(current)!;
      const baseG = gScore.get(current)!;

      for (const nbId of node.neighbors) {
        if (closed.has(nbId)) continue;
        const nb = this.byId.get(nbId);
        if (!nb) continue;
        const tentative = baseG + node.position.distanceTo(nb.position);
        if (tentative < (gScore.get(nbId) ?? Infinity)) {
          cameFrom.set(nbId, current);
          gScore.set(nbId, tentative);
          const f = tentative + nb.position.distanceTo(goalNode.position);
          fScore.set(nbId, f);
          open.push(nbId, f);
        }
      }
    }
    return [];
  }

  private reconstruct(
    cameFrom: Map<number, number>,
    end: number,
    goal: THREE.Vector3,
    los?: LineOfSight,
  ): THREE.Vector3[] {
    const ids: number[] = [end];
    let cur = end;
    while (cameFrom.has(cur)) {
      cur = cameFrom.get(cur)!;
      ids.push(cur);
    }
    ids.reverse();
    let points = ids.map((id) => this.byId.get(id)!.position.clone());
    points.push(goal.clone());
    if (los) points = smooth(points, los);
    return points;
  }
}

/** Drop intermediate points whose span has clear line of sight. */
function smooth(points: THREE.Vector3[], los: LineOfSight): THREE.Vector3[] {
  if (points.length <= 2) return points;
  const out: THREE.Vector3[] = [points[0]];
  let anchor = 0;
  for (let i = 2; i < points.length; i++) {
    if (!los.clear(points[anchor], points[i])) {
      out.push(points[i - 1]);
      anchor = i - 1;
    }
  }
  out.push(points[points.length - 1]);
  return out;
}

/** Binary min-heap keyed by priority (lower = popped first). */
class MinHeap {
  private items: { id: number; p: number }[] = [];
  isEmpty(): boolean {
    return this.items.length === 0;
  }
  push(id: number, p: number): void {
    const items = this.items;
    items.push({ id, p });
    let i = items.length - 1;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (items[parent].p <= items[i].p) break;
      [items[parent], items[i]] = [items[i], items[parent]];
      i = parent;
    }
  }
  pop(): number | undefined {
    const items = this.items;
    if (items.length === 0) return undefined;
    const top = items[0];
    const last = items.pop()!;
    if (items.length > 0) {
      items[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = 2 * i + 2;
        let smallest = i;
        if (l < items.length && items[l].p < items[smallest].p) smallest = l;
        if (r < items.length && items[r].p < items[smallest].p) smallest = r;
        if (smallest === i) break;
        [items[smallest], items[i]] = [items[i], items[smallest]];
        i = smallest;
      }
    }
    return top.id;
  }
}
