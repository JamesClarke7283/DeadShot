// WebGLRenderer wrapper: shadow maps, ACES tone mapping, DPR + resize handling.

import * as THREE from "../three.ts";

export class Renderer {
  readonly three: THREE.WebGLRenderer;
  readonly canvas: HTMLCanvasElement;
  private maxPixelRatio: number;
  private onResize?: (w: number, h: number) => void;

  constructor(canvas: HTMLCanvasElement, maxPixelRatio = 2) {
    this.canvas = canvas;
    this.maxPixelRatio = maxPixelRatio;
    this.three = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      powerPreference: "high-performance",
      stencil: false,
    });
    this.three.setPixelRatio(Math.min(globalThis.devicePixelRatio, maxPixelRatio));
    this.three.shadowMap.enabled = true;
    this.three.shadowMap.type = THREE.PCFSoftShadowMap;
    this.three.toneMapping = THREE.ACESFilmicToneMapping;
    this.three.toneMappingExposure = 1.05;
    this.three.outputColorSpace = THREE.SRGBColorSpace;
    this.resize();
    globalThis.addEventListener("resize", this.handleResize);
  }

  private handleResize = (): void => this.resize();

  resize(): void {
    const w = globalThis.innerWidth;
    const h = globalThis.innerHeight;
    this.three.setPixelRatio(Math.min(globalThis.devicePixelRatio, this.maxPixelRatio));
    this.three.setSize(w, h, false);
    this.onResize?.(w, h);
  }

  setResizeCallback(cb: (w: number, h: number) => void): void {
    this.onResize = cb;
    cb(globalThis.innerWidth, globalThis.innerHeight);
  }

  get aspect(): number {
    return globalThis.innerWidth / globalThis.innerHeight;
  }

  render(scene: THREE.Scene, camera: THREE.Camera): void {
    this.three.render(scene, camera);
  }

  dispose(): void {
    globalThis.removeEventListener("resize", this.handleResize);
    this.three.dispose();
  }
}
