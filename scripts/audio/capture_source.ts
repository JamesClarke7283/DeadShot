// Build-time browser entry. Executes the original WebAudio graphs unchanged.
import * as Synth from "../../../DeadShot/src/audio/Synth.ts";
import { gunParams } from "../../../DeadShot/src/audio/WeaponSFX.ts";
import { MusicPlayer } from "../../../DeadShot/src/audio/MusicPlayer.ts";
import type { AudioManager } from "../../../DeadShot/src/audio/AudioManager.ts";

const RATE = 44100;
const STEP = 60 / 112 / 4;
const LOOP = STEP * 16 * 8;
type ScoreCapture = {
  startScore(): void;
  scheduleStep(step: number, time: number): void;
  layers: Record<string, GainNode>;
  musicGain: GainNode;
  timer: number;
  intensity: number;
};

function resetRandom(seed: number): void {
  let state = seed;
  Math.random = () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 4294967296;
  };
}

async function renderMusic(layer: string, level: number): Promise<Float32Array> {
  resetRandom(193735);
  const ctx = new OfflineAudioContext(1, Math.ceil(LOOP * 2 * RATE), RATE);
  const audio = { ctx, musicBus: ctx.destination, now: 0 } as unknown as AudioManager;
  const score = new MusicPlayer(audio) as unknown as ScoreCapture;
  score.startScore();
  clearInterval(score.timer);
  score.musicGain.disconnect();
  score.intensity = level;
  const bus = score.layers[layer];
  bus.disconnect();
  bus.gain.cancelScheduledValues(0);
  bus.gain.value = 1;
  bus.connect(ctx.destination);
  for (let step = 0; step < 256; step++) score.scheduleStep(step, step * STEP);
  const rendered = await ctx.startRendering();
  return rendered.getChannelData(0).slice(Math.round(LOOP * RATE), Math.round(LOOP * 2 * RATE));
}

async function capture(
  id: string,
  variant = 0,
): Promise<{ samples: number[]; rate: number; restoreGain: number }> {
  const random = Math.random;
  let samples: Float32Array;
  try {
    resetRandom(93145 + variant * 17471);
    if (id.startsWith("music_")) {
      const layer = id.substring(6);
      if (layer === "drums_hats" || layer === "drums_kicks") {
        const high = await renderMusic("drums", layer === "drums_hats" ? 0.625 : 1);
        const low = await renderMusic("drums", layer === "drums_hats" ? 0 : 0.625);
        samples = high.map((sample, index) => sample - low[index]);
      } else samples = await renderMusic(layer, 0);
      // Smooth only the 2ms splice at the periodic sample boundary.
      const edge = Math.round(RATE * 0.002);
      for (let i = 0; i < edge; i++) {
        samples[i] *= i / edge;
        samples[samples.length - 1 - i] *= i / edge;
      }
    } else {
      const size = id.startsWith("explosion_") ? Number(id.substring(10)) : 1;
      const duration = id.startsWith("explosion")
        ? Math.max(0.55, size * 0.85) + 0.05
        : id.startsWith("gun_")
        ? 0.55
        : 0.2;
      const ctx = new OfflineAudioContext(1, Math.ceil(duration * RATE), RATE);
      const sourceCtx = ctx as unknown as AudioContext;
      if (id.startsWith("gun_")) {
        Synth.playGunshot(sourceCtx, ctx.destination, gunParams(id.substring(4)));
      } else if (id.startsWith("explosion_")) Synth.playExplosion(sourceCtx, ctx.destination, size);
      else if (id === "reload") Synth.playReloadClick(sourceCtx, ctx.destination);
      else if (id === "hit") Synth.playHitMarker(sourceCtx, ctx.destination, false);
      else if (id === "headshot") Synth.playHitMarker(sourceCtx, ctx.destination, true);
      else if (id === "click") Synth.playUIClick(sourceCtx, ctx.destination);
      else if (id === "footstep") Synth.playFootstep(sourceCtx, ctx.destination);
      else if (id === "beep") Synth.playBeep(sourceCtx, ctx.destination);
      else throw new Error(`Unknown audio capture: ${id}`);
      samples = (await ctx.startRendering()).getChannelData(0);
    }
    let peak = 0;
    for (const sample of samples) peak = Math.max(peak, Math.abs(sample));
    const restoreGain = Math.max(1, peak / 0.98);
    return {
      samples: Array.from(samples, (sample) => sample / restoreGain),
      rate: RATE,
      restoreGain,
    };
  } finally {
    Math.random = random;
  }
}

Object.assign(globalThis, { captureDeadshotAudio: capture });
