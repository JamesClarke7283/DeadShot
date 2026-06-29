// Local-player screen-effects overlay.
//
// Drives a few absolutely-positioned, pointer-events:none DOM divs over the
// canvas to render flashbang blinds, stun blur, colored damage/effect vignettes
// and an audio-muffle (deafen) timer. Each effect decays linearly in update(dt).
// All DOM access is guarded so this is safe to construct in a headless/test
// environment (it simply becomes a no-op).

export interface ScreenEffectsApi {
  /** White flashbang blind. intensity 0..1, decays over durationSec. */
  flash(intensity: number, durationSec: number): void;
  /** Stun blur in CSS pixels, decays over durationSec. */
  blur(amount: number, durationSec: number): void;
  /** Audio muffle hook (state only for now). */
  deafen(durationSec: number): void;
  /** Generic colored vignette (CSS color string), intensity 0..1. */
  tint(color: string, intensity: number, durationSec: number): void;
  /** Decay all active effects by dt seconds. */
  update(dt: number): void;
  isDeafened(): boolean;
  clear(): void;
}

interface Decaying {
  remaining: number;
  duration: number;
}

interface FlashState extends Decaying {
  intensity: number;
}
interface BlurState extends Decaying {
  amount: number;
}
interface TintState extends Decaying {
  color: string;
  intensity: number;
}

const BASE_STYLE = "position:fixed;inset:0;pointer-events:none;opacity:0;";

export class ScreenEffects implements ScreenEffectsApi {
  private flashEl: HTMLDivElement | null = null;
  private blurEl: HTMLDivElement | null = null;
  private tintEl: HTMLDivElement | null = null;

  private flashState: FlashState | null = null;
  private blurState: BlurState | null = null;
  private tintState: TintState | null = null;
  private deafenTimer = 0;

  constructor() {
    if (typeof document === "undefined") return;
    const host = document.getElementById("ui-root") ?? document.body;
    if (!host) return;

    this.flashEl = this.makeLayer(host, BASE_STYLE + "background:#ffffff;z-index:9000;");
    // Blur layer uses backdrop-filter so it blurs whatever is behind it.
    this.blurEl = this.makeLayer(host, BASE_STYLE + "z-index:8990;");
    // Tint is a radial vignette: transparent centre, colored edges.
    this.tintEl = this.makeLayer(host, BASE_STYLE + "z-index:8980;");
  }

  private makeLayer(host: HTMLElement, style: string): HTMLDivElement {
    const el = document.createElement("div");
    el.style.cssText = style;
    host.appendChild(el);
    return el;
  }

  flash(intensity: number, durationSec: number): void {
    const i = Math.max(0, Math.min(1, intensity));
    if (durationSec <= 0) return;
    this.flashState = { intensity: i, remaining: durationSec, duration: durationSec };
    this.applyFlash();
  }

  blur(amount: number, durationSec: number): void {
    if (durationSec <= 0 || amount <= 0) return;
    this.blurState = { amount, remaining: durationSec, duration: durationSec };
    this.applyBlur();
  }

  deafen(durationSec: number): void {
    this.deafenTimer = Math.max(this.deafenTimer, durationSec);
  }

  tint(color: string, intensity: number, durationSec: number): void {
    const i = Math.max(0, Math.min(1, intensity));
    if (durationSec <= 0) return;
    this.tintState = { color, intensity: i, remaining: durationSec, duration: durationSec };
    this.applyTint();
  }

  update(dt: number): void {
    if (this.deafenTimer > 0) this.deafenTimer = Math.max(0, this.deafenTimer - dt);

    if (this.flashState) {
      this.flashState.remaining -= dt;
      if (this.flashState.remaining <= 0) this.flashState = null;
      this.applyFlash();
    }
    if (this.blurState) {
      this.blurState.remaining -= dt;
      if (this.blurState.remaining <= 0) this.blurState = null;
      this.applyBlur();
    }
    if (this.tintState) {
      this.tintState.remaining -= dt;
      if (this.tintState.remaining <= 0) this.tintState = null;
      this.applyTint();
    }
  }

  isDeafened(): boolean {
    return this.deafenTimer > 0;
  }

  clear(): void {
    this.flashState = null;
    this.blurState = null;
    this.tintState = null;
    this.deafenTimer = 0;
    this.applyFlash();
    this.applyBlur();
    this.applyTint();
  }

  private frac(s: Decaying): number {
    return s.duration > 0 ? Math.max(0, s.remaining / s.duration) : 0;
  }

  private applyFlash(): void {
    if (!this.flashEl) return;
    const o = this.flashState ? this.frac(this.flashState) * this.flashState.intensity : 0;
    this.flashEl.style.opacity = String(o);
  }

  private applyBlur(): void {
    if (!this.blurEl) return;
    if (!this.blurState) {
      this.blurEl.style.opacity = "0";
      this.blurEl.style.backdropFilter = "";
      this.blurEl.style.setProperty("-webkit-backdrop-filter", "");
      return;
    }
    const px = (this.blurState.amount * this.frac(this.blurState)).toFixed(2) + "px";
    const filter = `blur(${px})`;
    this.blurEl.style.opacity = "1";
    this.blurEl.style.backdropFilter = filter;
    this.blurEl.style.setProperty("-webkit-backdrop-filter", filter);
  }

  private applyTint(): void {
    if (!this.tintEl) return;
    if (!this.tintState) {
      this.tintEl.style.opacity = "0";
      return;
    }
    const o = this.frac(this.tintState) * this.tintState.intensity;
    // Radial gradient vignette: clear centre fading to the tint color at edges.
    this.tintEl.style.background =
      `radial-gradient(ellipse at center, transparent 40%, ${this.tintState.color} 130%)`;
    this.tintEl.style.opacity = String(o);
  }
}
