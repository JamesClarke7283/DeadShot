// Positional sound effects via WebAudio PannerNodes, sharing the AudioManager's
// context + listener (mounted on the camera) so enemy gunfire/explosions come
// from the right direction.

import * as THREE from "../three.ts";
import type { AudioManager } from "./AudioManager.ts";
import { gunParams } from "./WeaponSFX.ts";
import { playExplosion, playFootstep, playGunshot } from "./Synth.ts";

export class SpatialSFX {
  constructor(private audio: AudioManager) {}

  private panner(pos: THREE.Vector3): PannerNode {
    const p = this.audio.ctx.createPanner();
    p.panningModel = "HRTF";
    p.distanceModel = "inverse";
    p.refDistance = 8;
    p.maxDistance = 220;
    p.rolloffFactor = 1.1;
    p.positionX.value = pos.x;
    p.positionY.value = pos.y;
    p.positionZ.value = pos.z;
    p.connect(this.audio.sfxBus);
    // Release the dangling panner after the longest tail.
    setTimeout(() => p.disconnect(), 1000);
    return p;
  }

  shotAt(weaponId: string, pos: THREE.Vector3): void {
    playGunshot(this.audio.ctx, this.panner(pos), gunParams(weaponId));
  }
  explosionAt(pos: THREE.Vector3, size = 1): void {
    playExplosion(this.audio.ctx, this.panner(pos), size);
  }
  footstepAt(pos: THREE.Vector3): void {
    playFootstep(this.audio.ctx, this.panner(pos));
  }
}
