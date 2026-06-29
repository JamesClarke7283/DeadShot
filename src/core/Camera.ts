// First-person camera: PerspectiveCamera + PointerLockControls wrapper.
//
// Owns the look controls (mouse yaw/pitch) and exposes the perspective camera
// plus convenience movement/look helpers. Sensitivity maps to the controls'
// pointerSpeed. Pointer lock is engaged via lock() on a user gesture (canvas
// click) — never automatically — so it works inside both browsers and the
// webview.

import * as THREE from "../three.ts";
import { PointerLockControls } from "../vendor/PointerLockControls.ts";

export class Camera {
  readonly perspective: THREE.PerspectiveCamera;
  readonly controls: PointerLockControls;
  private domElement: HTMLElement;

  constructor(domElement: HTMLElement, fov = 75, sensitivity = 1.0) {
    this.domElement = domElement;
    this.perspective = new THREE.PerspectiveCamera(
      fov,
      globalThis.innerWidth / globalThis.innerHeight,
      0.05,
      2000,
    );
    this.perspective.position.set(0, 1.6, 0);
    this.controls = new PointerLockControls(this.perspective, domElement);
    this.controls.pointerSpeed = sensitivity;
  }

  /** The controlled camera object (the PointerLockControls target). */
  get object(): THREE.PerspectiveCamera {
    return this.perspective;
  }

  get isLocked(): boolean {
    return this.controls.isLocked;
  }

  lock(): void {
    if (this.controls.isLocked) return;
    // Request pointer lock ourselves (not controls.lock()) so we can swallow the
    // promise rejection browsers raise when there's no user activation. The
    // controls' pointerlockchange listener still flips isLocked on success.
    const el = this.domElement as HTMLElement & {
      requestPointerLock?: () => Promise<void> | void;
    };
    try {
      const r = el.requestPointerLock?.();
      if (r && typeof (r as Promise<void>).catch === "function") {
        (r as Promise<void>).catch(() => {});
      }
    } catch {
      // ignore — lock will be retried on the next click
    }
  }

  unlock(): void {
    if (this.controls.isLocked) this.controls.unlock();
  }

  onLock(cb: () => void): void {
    this.controls.addEventListener("lock", cb);
  }
  onUnlock(cb: () => void): void {
    this.controls.addEventListener("unlock", cb);
  }

  setSensitivity(s: number): void {
    this.controls.pointerSpeed = s;
  }

  /**
   * Apply a recoil/aim kick in radians. Composes with PointerLockControls, which
   * reads the camera quaternion afresh on each mouse move — so the player can
   * fight the climb. Positive pitch tilts the view up.
   */
  applyRecoil(pitch: number, yaw: number): void {
    const e = new THREE.Euler().setFromQuaternion(this.perspective.quaternion, "YXZ");
    e.x += pitch;
    e.y += yaw;
    const max = Math.PI / 2 - 0.01;
    e.x = Math.max(-max, Math.min(max, e.x));
    this.perspective.quaternion.setFromEuler(e);
  }

  setFov(fov: number): void {
    this.perspective.fov = fov;
    this.perspective.updateProjectionMatrix();
  }

  resize(aspect: number): void {
    this.perspective.aspect = aspect;
    this.perspective.updateProjectionMatrix();
  }

  /** Horizontal forward (XZ) and right vectors, for movement. */
  getForward(out: THREE.Vector3): THREE.Vector3 {
    this.controls.getDirection(out);
    out.y = 0;
    return out.normalize();
  }
  getRight(out: THREE.Vector3): THREE.Vector3 {
    this.getForward(out);
    out.cross(this.perspective.up).normalize();
    return out;
  }

  /** Full 3D look direction (includes pitch). */
  getLookDirection(out: THREE.Vector3): THREE.Vector3 {
    return this.controls.getDirection(out);
  }

  moveForward(distance: number): void {
    this.controls.moveForward(distance);
  }
  moveRight(distance: number): void {
    this.controls.moveRight(distance);
  }

  setPosition(x: number, y: number, z: number): void {
    this.perspective.position.set(x, y, z);
  }

  dispose(): void {
    this.controls.dispose();
  }
}
