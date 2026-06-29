// Scene lighting for the cartoon look.
//
// A hemisphere light for soft cartoon ambient + a directional "sun" that casts
// shadows. The sun's orthographic shadow frustum follows a focus point (the
// player) so a single high-res cascade covers the active play area sharply —
// a pragmatic stand-in for full CSM that avoids per-material shader patching
// while keeping crisp shadows where the action is.

import * as THREE from "../three.ts";

export interface LightingOptions {
  skyColor?: THREE.ColorRepresentation;
  groundColor?: THREE.ColorRepresentation;
  sunColor?: THREE.ColorRepresentation;
  hemiIntensity?: number;
  sunIntensity?: number;
  /** Direction from scene toward the sun. */
  sunDirection?: THREE.Vector3;
  /** Half-size of the shadow frustum in world units. */
  shadowRadius?: number;
  shadowMapSize?: number;
}

export class Lighting {
  readonly group = new THREE.Group();
  readonly hemisphere: THREE.HemisphereLight;
  readonly sun: THREE.DirectionalLight;
  private readonly sunOffset: THREE.Vector3;
  private readonly shadowRadius: number;

  constructor(opts: LightingOptions = {}) {
    this.hemisphere = new THREE.HemisphereLight(
      opts.skyColor ?? 0xbfe3ff,
      opts.groundColor ?? 0x4a5a3a,
      opts.hemiIntensity ?? 1.0,
    );
    this.group.add(this.hemisphere);

    this.sun = new THREE.DirectionalLight(opts.sunColor ?? 0xfff4e0, opts.sunIntensity ?? 2.2);
    const dir = (opts.sunDirection ?? new THREE.Vector3(0.5, 1, 0.35)).clone().normalize();
    this.shadowRadius = opts.shadowRadius ?? 40;
    this.sunOffset = dir.multiplyScalar(this.shadowRadius * 2.2);
    this.sun.position.copy(this.sunOffset);
    this.sun.castShadow = true;

    const cam = this.sun.shadow.camera;
    cam.near = 0.5;
    cam.far = this.shadowRadius * 5;
    cam.left = -this.shadowRadius;
    cam.right = this.shadowRadius;
    cam.top = this.shadowRadius;
    cam.bottom = -this.shadowRadius;
    cam.updateProjectionMatrix();

    const size = opts.shadowMapSize ?? 2048;
    this.sun.shadow.mapSize.set(size, size);
    this.sun.shadow.bias = -0.0005;
    this.sun.shadow.normalBias = 0.04;

    this.group.add(this.sun);
    this.group.add(this.sun.target);
  }

  /** Keep the shadow frustum centred on `focus` (snapped to texel grid to
   *  avoid shimmering as it moves). */
  follow(focus: THREE.Vector3): void {
    const texelsPerUnit = this.sun.shadow.mapSize.x / (this.shadowRadius * 2);
    const snapped = focus.clone().multiplyScalar(texelsPerUnit).round().divideScalar(texelsPerUnit);
    this.sun.target.position.copy(snapped);
    this.sun.position.copy(snapped).add(this.sunOffset);
    this.sun.target.updateMatrixWorld();
  }

  addTo(scene: THREE.Scene): void {
    scene.add(this.group);
  }

  dispose(): void {
    this.sun.shadow.map?.dispose();
  }
}
