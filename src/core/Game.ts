// Top-level game orchestrator.
//
// Owns the engine subsystems (Renderer, Scene, Camera, Input, Clock,
// AssetLoader), runs the requestAnimationFrame loop with a fixed-step
// accumulator for simulation, and drives a simple state machine
// (Boot / MainMenu / ClassEditor / PreMatch / Playing / PostMatch). Later phases
// register handlers for these states (menus, match). Phase 1 ships a built-in
// "sandbox" used when Playing has no registered handler: a lit, toon-shaded
// cube + capsule with outlines that you can walk around (pointer lock + WASD)
// to verify the engine end-to-end.

import * as THREE from "../three.ts";
import { Renderer } from "./Renderer.ts";
import { Scene } from "./Scene.ts";
import { Camera } from "./Camera.ts";
import { Input } from "./Input.ts";
import { Clock } from "./Clock.ts";
import { AssetLoader } from "./AssetLoader.ts";
import { createToonMaterial } from "../render/ToonMaterial.ts";
import { outlineHierarchy } from "../render/OutlinePass.ts";

export enum GameState {
  Boot = "Boot",
  MainMenu = "MainMenu",
  ClassEditor = "ClassEditor",
  PreMatch = "PreMatch",
  Playing = "Playing",
  PostMatch = "PostMatch",
}

export interface GameStateHandler {
  enter?(prev: GameState | null): void;
  exit?(next: GameState): void;
  fixedUpdate?(step: number): void;
  update?(dt: number): void;
}

const FIXED_STEP = 1 / 60;
const MAX_SUBSTEPS = 5;

export class Game {
  readonly renderer: Renderer;
  readonly scene: Scene;
  readonly camera: Camera;
  readonly input: Input;
  readonly clock: Clock;
  readonly assets: AssetLoader;

  state: GameState = GameState.Boot;
  private handlers = new Map<GameState, GameStateHandler>();
  private accumulator = 0;
  private running = false;
  private rafId = 0;

  // FPS counter
  private fpsEl: HTMLElement;
  private fpsAccum = 0;
  private fpsFrames = 0;

  constructor(canvas: HTMLCanvasElement) {
    this.clock = new Clock();
    this.renderer = new Renderer(canvas);
    this.camera = new Camera(canvas);
    this.scene = new Scene();
    this.input = new Input(canvas);
    this.assets = new AssetLoader((frac, url) => this.onLoadProgress(frac, url));

    this.renderer.setResizeCallback((_w, _h) => this.camera.resize(this.renderer.aspect));

    // Engage pointer lock on click while playing.
    canvas.addEventListener("click", () => {
      if (this.state === GameState.Playing) this.camera.lock();
    });

    this.fpsEl = document.createElement("div");
    this.fpsEl.className = "fps-counter";
    document.getElementById("ui-root")?.appendChild(this.fpsEl);

    this.installSandboxState();
  }

  registerState(state: GameState, handler: GameStateHandler): void {
    this.handlers.set(state, handler);
  }

  setState(next: GameState): void {
    if (next === this.state && this.running) return;
    const prev = this.state;
    this.handlers.get(prev)?.exit?.(next);
    this.state = next;
    this.handlers.get(next)?.enter?.(prev);
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.clock.reset();
    // Phase 1: boot straight into the sandbox. Phase 10 will route Boot ->
    // MainMenu instead by registering a Boot handler.
    if (this.handlers.has(GameState.Boot)) this.setState(GameState.Boot);
    else this.setState(GameState.Playing);
    this.hideLoading();
    this.rafId = requestAnimationFrame(this.loop);
  }

  stop(): void {
    this.running = false;
    cancelAnimationFrame(this.rafId);
  }

  private loop = (): void => {
    if (!this.running) return;
    const dt = this.clock.getDelta();
    const handler = this.handlers.get(this.state);

    this.accumulator += dt;
    let substeps = 0;
    while (this.accumulator >= FIXED_STEP && substeps < MAX_SUBSTEPS) {
      handler?.fixedUpdate?.(FIXED_STEP);
      this.accumulator -= FIXED_STEP;
      substeps++;
    }
    if (substeps === MAX_SUBSTEPS) this.accumulator = 0; // avoid spiral of death

    handler?.update?.(dt);
    this.scene.update(this.camera.perspective.position);
    this.renderer.render(this.scene.three, this.camera.perspective);

    this.input.endFrame();
    this.updateFps(dt);
    this.rafId = requestAnimationFrame(this.loop);
  };

  private updateFps(dt: number): void {
    this.fpsAccum += dt;
    this.fpsFrames++;
    if (this.fpsAccum >= 0.5) {
      const fps = this.fpsFrames / this.fpsAccum;
      this.fpsEl.textContent = `${fps.toFixed(0)} FPS`;
      this.fpsAccum = 0;
      this.fpsFrames = 0;
    }
  }

  private onLoadProgress(frac: number, _url: string): void {
    const fill = document.getElementById("loading-fill");
    const status = document.getElementById("loading-status");
    if (fill) fill.style.width = `${Math.round(frac * 100)}%`;
    if (status) status.textContent = `Loading… ${Math.round(frac * 100)}%`;
  }

  private hideLoading(): void {
    document.getElementById("loading")?.classList.add("hidden");
  }

  // ---- Built-in Phase 1 sandbox (replaced by the match in later phases) ----
  private installSandboxState(): void {
    const move = new THREE.Vector3();
    const forward = new THREE.Vector3();
    const right = new THREE.Vector3();

    this.registerState(GameState.Playing, {
      enter: () => {
        this.scene.setEnvironment({
          background: 0x9fd3ff,
          fogColor: 0xbfe3ff,
          fogNear: 60,
          fogFar: 400,
        });
        this.buildSandbox();
        this.camera.setPosition(0, 1.6, 8);
      },
      update: (dt) => {
        if (!this.camera.isLocked) return;
        const speed = (this.input.isDown("sprint") ? 9 : 5.5) * dt;
        const fb = this.input.axis("back", "forward");
        const lr = this.input.axis("left", "right");
        if (fb !== 0 || lr !== 0) {
          this.camera.getForward(forward);
          this.camera.getRight(right);
          move.set(0, 0, 0)
            .addScaledVector(forward, fb)
            .addScaledVector(right, lr)
            .normalize()
            .multiplyScalar(speed);
          this.camera.perspective.position.add(move);
          this.camera.perspective.position.y = 1.6; // stay grounded in sandbox
        }
      },
    });
  }

  private buildSandbox(): void {
    this.scene.clearMap();

    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(120, 120),
      createToonMaterial({ color: 0x6fae5a }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    this.scene.addToMap(ground);

    const cube = new THREE.Mesh(
      new THREE.BoxGeometry(2, 2, 2),
      createToonMaterial({ color: 0xff6b35 }),
    );
    cube.position.set(-2.5, 1, 0);
    cube.castShadow = true;
    this.scene.addToMap(cube);

    const capsule = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.8, 1.6, 8, 16),
      createToonMaterial({ color: 0x3a86ff }),
    );
    capsule.position.set(2.5, 1.6, 0);
    capsule.castShadow = true;
    this.scene.addToMap(capsule);

    // Cartoon black outlines on the demo props.
    outlineHierarchy(cube, { thickness: 0.04 });
    outlineHierarchy(capsule, { thickness: 0.04 });
  }
}
