// Shared character abstraction.
//
// Both the procedural humanoid and the (optional) Quaternius GLTF character
// implement this so the rest of the game (Bot, player viewmodel preview, class
// editor) is agnostic to which one is in use.

import type * as THREE from "../three.ts";
import type { TeamId } from "../core/types.ts";

export type AnimName = "idle" | "run" | "shoot" | "die";

export interface Character {
  /** Root object placed in the scene; origin at the feet, facing +Z. */
  readonly root: THREE.Group;
  /** Approximate standing height in metres. */
  readonly height: number;
  /** Recolor the uniform / headband for a team (accent picks an FFA color). */
  setTeam(team: TeamId, accentIndex?: number): void;
  /** Switch the active animation state. */
  play(anim: AnimName): void;
  /** Advance animation by `dt` seconds. */
  update(dt: number): void;
  dispose(): void;
}
