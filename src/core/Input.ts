// Keyboard + mouse input with action bindings and per-frame edge detection.
//
// Physical key codes (KeyW, ShiftLeft, …) are bound to semantic actions so the
// rest of the game asks "is `fire` down?" not "is Mouse0 down?". Mouse buttons
// are folded into the same key set as Mouse0/Mouse1/Mouse2. Pointer look is
// handled by Camera's PointerLockControls; Input also accumulates raw mouse
// deltas for systems that want them directly. Call endFrame() once per frame to
// clear the pressed/released edge sets.

export type Action =
  | "forward"
  | "back"
  | "left"
  | "right"
  | "jump"
  | "crouch"
  | "sprint"
  | "fire"
  | "ads"
  | "reload"
  | "lethal"
  | "tactical"
  | "melee"
  | "interact"
  | "switchWeapon"
  | "fireMode"
  | "scoreboard"
  | "streaks"
  | "pause"
  | "console";

export type Bindings = Record<Action, string[]>;

export const DEFAULT_BINDINGS: Bindings = {
  forward: ["KeyW", "ArrowUp"],
  back: ["KeyS", "ArrowDown"],
  left: ["KeyA", "ArrowLeft"],
  right: ["KeyD", "ArrowRight"],
  jump: ["Space"],
  crouch: ["ControlLeft", "KeyC"],
  sprint: ["ShiftLeft"],
  fire: ["Mouse0"],
  ads: ["Mouse2"],
  reload: ["KeyR"],
  lethal: ["KeyG"],
  tactical: ["KeyQ"],
  melee: ["KeyV"],
  interact: ["KeyE"],
  switchWeapon: ["Digit1", "Digit2"],
  fireMode: ["KeyB"],
  scoreboard: ["Tab"],
  streaks: ["KeyZ"],
  pause: ["Escape"],
  console: ["Backquote"],
};

export class Input {
  private readonly target: HTMLElement;
  private readonly down = new Set<string>();
  private readonly pressed = new Set<string>();
  private readonly released = new Set<string>();
  private bindings: Bindings;

  /** Raw accumulated pointer delta since last consume (when pointer locked). */
  mouseDX = 0;
  mouseDY = 0;
  /** Wheel delta accumulated since last frame. */
  wheel = 0;

  private bound: { [k: string]: (e: never) => void } = {};

  constructor(target: HTMLElement, bindings: Bindings = DEFAULT_BINDINGS) {
    this.target = target;
    this.bindings = bindings;
    this.attach();
  }

  setBindings(b: Bindings): void {
    this.bindings = b;
  }

  private attach(): void {
    const onKeyDown = (e: KeyboardEvent) => {
      // Prevent Tab from moving focus, Space/arrows from scrolling, etc.
      if (
        ["Tab", "Space", "Backquote", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"]
          .includes(e.code)
      ) e.preventDefault();
      if (e.repeat) return;
      if (!this.down.has(e.code)) this.pressed.add(e.code);
      this.down.add(e.code);
    };
    const onKeyUp = (e: KeyboardEvent) => {
      this.down.delete(e.code);
      this.released.add(e.code);
    };
    const mouseCode = (button: number) => `Mouse${button}`;
    const onMouseDown = (e: MouseEvent) => {
      const code = mouseCode(e.button);
      if (!this.down.has(code)) this.pressed.add(code);
      this.down.add(code);
    };
    const onMouseUp = (e: MouseEvent) => {
      const code = mouseCode(e.button);
      this.down.delete(code);
      this.released.add(code);
    };
    const onMouseMove = (e: MouseEvent) => {
      if (document.pointerLockElement) {
        this.mouseDX += e.movementX;
        this.mouseDY += e.movementY;
      }
    };
    const onWheel = (e: WheelEvent) => {
      this.wheel += Math.sign(e.deltaY);
    };
    const onContextMenu = (e: Event) => e.preventDefault();
    const onBlur = () => this.clearAll();

    globalThis.addEventListener("keydown", onKeyDown as EventListener);
    globalThis.addEventListener("keyup", onKeyUp as EventListener);
    this.target.addEventListener("mousedown", onMouseDown as EventListener);
    globalThis.addEventListener("mouseup", onMouseUp as EventListener);
    globalThis.addEventListener("mousemove", onMouseMove as EventListener);
    this.target.addEventListener("wheel", onWheel as EventListener, { passive: true });
    this.target.addEventListener("contextmenu", onContextMenu);
    globalThis.addEventListener("blur", onBlur);

    this.bound = {
      onKeyDown,
      onKeyUp,
      onMouseDown,
      onMouseUp,
      onMouseMove,
      onWheel,
      onContextMenu,
      onBlur,
    } as never;
  }

  private clearAll(): void {
    this.down.clear();
    this.pressed.clear();
    this.released.clear();
  }

  // ---- raw key queries ----
  isKeyDown(code: string): boolean {
    return this.down.has(code);
  }
  wasKeyPressed(code: string): boolean {
    return this.pressed.has(code);
  }
  wasKeyReleased(code: string): boolean {
    return this.released.has(code);
  }

  // ---- action queries ----
  isDown(action: Action): boolean {
    const codes = this.bindings[action];
    for (const c of codes) if (this.down.has(c)) return true;
    return false;
  }
  wasPressed(action: Action): boolean {
    const codes = this.bindings[action];
    for (const c of codes) if (this.pressed.has(c)) return true;
    return false;
  }
  wasReleased(action: Action): boolean {
    const codes = this.bindings[action];
    for (const c of codes) if (this.released.has(c)) return true;
    return false;
  }

  /** -1 / 0 / +1 from a pair of opposing actions. */
  axis(negative: Action, positive: Action): number {
    return (this.isDown(positive) ? 1 : 0) - (this.isDown(negative) ? 1 : 0);
  }

  consumeMouseDelta(): { dx: number; dy: number } {
    const d = { dx: this.mouseDX, dy: this.mouseDY };
    this.mouseDX = 0;
    this.mouseDY = 0;
    return d;
  }

  consumeWheel(): number {
    const w = this.wheel;
    this.wheel = 0;
    return w;
  }

  /**
   * Drive an input code from an external source (gamepad / touch). Maintains the
   * same down/pressed/released edges as physical input.
   */
  setVirtual(code: string, down: boolean): void {
    if (down) {
      if (!this.down.has(code)) this.pressed.add(code);
      this.down.add(code);
    } else {
      if (this.down.has(code)) this.released.add(code);
      this.down.delete(code);
    }
  }

  /** Clear per-frame edge state. Call after all systems have read input. */
  endFrame(): void {
    this.pressed.clear();
    this.released.clear();
  }

  dispose(): void {
    globalThis.removeEventListener("keydown", this.bound.onKeyDown as EventListener);
    globalThis.removeEventListener("keyup", this.bound.onKeyUp as EventListener);
    this.target.removeEventListener("mousedown", this.bound.onMouseDown as EventListener);
    globalThis.removeEventListener("mouseup", this.bound.onMouseUp as EventListener);
    globalThis.removeEventListener("mousemove", this.bound.onMouseMove as EventListener);
    this.target.removeEventListener("wheel", this.bound.onWheel as EventListener);
    this.target.removeEventListener("contextmenu", this.bound.onContextMenu as EventListener);
    globalThis.removeEventListener("blur", this.bound.onBlur as EventListener);
  }
}
