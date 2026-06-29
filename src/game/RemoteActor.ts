// A networked actor mirrored from another client.
//
// Used for remote players and (on non-host clients) the host's bots. Its
// transform/animation come from the network via applyState(); it implements the
// Actor + DamageTarget contract so MatchWorld.raycast hits it like any other
// combatant. Crucially applyDamage() does NOT mutate local health — it forwards
// the hit to the owner over the network, who applies the authoritative damage.

import * as THREE from "../three.ts";
import type { Actor } from "../characters/Bot.ts";
import { ProceduralHuman } from "../characters/ProceduralHuman.ts";
import type { AnimName } from "../characters/Character.ts";
import type { DamageInfo } from "../weapons/combat.ts";
import type { TeamId } from "../core/types.ts";
import type { PlayerStateMsg } from "../net/protocol.ts";

const EYE = 1.6;

export class RemoteActor implements Actor {
  readonly isPlayer = false;
  readonly object3d = new THREE.Object3D();
  readonly feet = new THREE.Vector3();
  readonly character: ProceduralHuman;
  alive = true;
  yaw = 0;
  weaponId = "m4";

  private readonly target = new THREE.Vector3();
  private has = false;

  constructor(
    readonly id: number,
    public team: TeamId,
    public name: string,
    /** Forward a local hit to this actor's owner (relay). */
    private readonly emitHit: (target: number, info: DamageInfo) => void,
    accentIndex = 0,
  ) {
    this.character = new ProceduralHuman({ team, accentIndex });
    this.object3d.add(this.character.root);
  }

  // ---- Actor / DamageTarget ----
  position(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.feet).setY(this.feet.y + 1.0);
  }
  eyePosition(out: THREE.Vector3): THREE.Vector3 {
    return out.copy(this.feet).setY(this.feet.y + EYE);
  }
  isHead(): boolean {
    return false; // MatchWorld resolves headshots analytically
  }

  applyDamage(info: DamageInfo): void {
    if (!this.alive) return;
    // Not authoritative here: the owner applies the real damage.
    this.emitHit(this.id, info);
  }

  /** Apply a network transform/state snapshot. */
  applyState(s: PlayerStateMsg): void {
    this.target.set(s.x, s.y, s.z);
    if (!this.has) this.feet.copy(this.target); // snap on first packet
    this.has = true;
    this.yaw = s.yaw;
    this.alive = s.alive;
    if (s.weaponId) this.weaponId = s.weaponId;
    this.character.play((s.anim ?? "idle") as AnimName);
  }

  markDead(): void {
    this.alive = false;
    this.character.play("die");
  }

  update(dt: number): void {
    if (this.has) this.feet.lerp(this.target, Math.min(1, dt * 12)); // smooth toward latest
    this.object3d.position.copy(this.feet);
    this.character.root.position.set(0, 0, 0);
    this.character.root.rotation.y = this.yaw;
    this.character.update(dt);
    this.object3d.visible = this.alive;
  }

  dispose(): void {
    this.character.dispose();
  }
}
