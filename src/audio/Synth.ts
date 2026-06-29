// WebAudio synthesizers — no samples, everything is generated from oscillators +
// filtered noise + envelopes. Each play* function builds a short-lived node graph
// connected to a destination node (a 2D bus or a positional panner) and cleans
// itself up when it finishes.

let _noise: { ctx: AudioContext; buf: AudioBuffer } | null = null;

/** Cached 1s white-noise buffer for the given context. */
export function noiseBuffer(ctx: AudioContext): AudioBuffer {
  if (_noise && _noise.ctx === ctx) return _noise.buf;
  const buf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
  _noise = { ctx, buf };
  return buf;
}

function distortionCurve(amount: number): Float32Array<ArrayBuffer> {
  const n = 256;
  const curve = new Float32Array(new ArrayBuffer(n * 4));
  const k = amount * 50;
  for (let i = 0; i < n; i++) {
    const x = (i / (n - 1)) * 2 - 1;
    curve[i] = ((3 + k) * x * 20 * Math.PI / 180) / (Math.PI + k * Math.abs(x));
  }
  return curve;
}

export interface GunParams {
  duration: number; // tail length (s)
  lowpass: number; // Hz
  thump: number; // low-osc punch frequency (Hz), 0 = none
  distortion: number; // 0..1
  gain: number;
}

/** A gunshot: filtered noise crack + a low oscillator thump. */
export function playGunshot(ctx: AudioContext, dest: AudioNode, p: GunParams): void {
  const t = ctx.currentTime;
  // Noise crack
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(ctx);
  src.playbackRate.value = 0.8 + Math.random() * 0.4;
  const lp = ctx.createBiquadFilter();
  lp.type = "lowpass";
  lp.frequency.value = p.lowpass;
  const shaper = ctx.createWaveShaper();
  shaper.curve = distortionCurve(p.distortion);
  const env = ctx.createGain();
  env.gain.setValueAtTime(p.gain, t);
  env.gain.exponentialRampToValueAtTime(0.001, t + p.duration);
  src.connect(lp).connect(shaper).connect(env).connect(dest);
  src.start(t);
  src.stop(t + p.duration + 0.02);

  // Thump
  if (p.thump > 0) {
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(p.thump, t);
    osc.frequency.exponentialRampToValueAtTime(p.thump * 0.5, t + 0.08);
    const g = ctx.createGain();
    g.gain.setValueAtTime(p.gain * 0.8, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.12);
    osc.connect(g).connect(dest);
    osc.start(t);
    osc.stop(t + 0.14);
  }
}

export function playExplosion(ctx: AudioContext, dest: AudioNode, size = 1): void {
  const t = ctx.currentTime;
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(ctx);
  const lp = ctx.createBiquadFilter();
  lp.type = "lowpass";
  lp.frequency.setValueAtTime(1200 * size, t);
  lp.frequency.exponentialRampToValueAtTime(120, t + 0.5 * size);
  const env = ctx.createGain();
  env.gain.setValueAtTime(1.0, t);
  env.gain.exponentialRampToValueAtTime(0.001, t + 0.8 * size);
  src.connect(lp).connect(env).connect(dest);
  src.start(t);
  src.stop(t + 0.85 * size);

  const osc = ctx.createOscillator();
  osc.type = "sine";
  osc.frequency.setValueAtTime(90, t);
  osc.frequency.exponentialRampToValueAtTime(35, t + 0.4);
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.9, t);
  g.gain.exponentialRampToValueAtTime(0.001, t + 0.5);
  osc.connect(g).connect(dest);
  osc.start(t);
  osc.stop(t + 0.55);
}

function blip(
  ctx: AudioContext,
  dest: AudioNode,
  freq: number,
  dur: number,
  type: OscillatorType,
  gain: number,
): void {
  const t = ctx.currentTime;
  const osc = ctx.createOscillator();
  osc.type = type;
  osc.frequency.value = freq;
  const g = ctx.createGain();
  g.gain.setValueAtTime(gain, t);
  g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  osc.connect(g).connect(dest);
  osc.start(t);
  osc.stop(t + dur + 0.01);
}

export function playReloadClick(ctx: AudioContext, dest: AudioNode): void {
  blip(ctx, dest, 220, 0.05, "square", 0.25);
}
export function playHitMarker(ctx: AudioContext, dest: AudioNode, headshot: boolean): void {
  blip(ctx, dest, headshot ? 1400 : 900, 0.06, "square", 0.3);
}
export function playUIClick(ctx: AudioContext, dest: AudioNode): void {
  blip(ctx, dest, 600, 0.04, "triangle", 0.2);
}
export function playFootstep(ctx: AudioContext, dest: AudioNode): void {
  const t = ctx.currentTime;
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(ctx);
  const lp = ctx.createBiquadFilter();
  lp.type = "lowpass";
  lp.frequency.value = 500;
  const env = ctx.createGain();
  env.gain.setValueAtTime(0.15, t);
  env.gain.exponentialRampToValueAtTime(0.001, t + 0.08);
  src.connect(lp).connect(env).connect(dest);
  src.start(t);
  src.stop(t + 0.1);
}
export function playBeep(ctx: AudioContext, dest: AudioNode): void {
  blip(ctx, dest, 1000, 0.05, "sine", 0.2);
}
