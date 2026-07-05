// MusicPlayer: dynamic combat soundtrack with crossfade, low-health ducking, and
// intensity-reactive layers.
//
// Offline-first: with no assets it synthesizes a full sequenced score — chord
// pads, a driving bass, arpeggios and percussion — with layers faded in and out
// by intensity (menu = brooding pads, in-match = bass + arps, kills/streaks
// surge the drums via pulse()). If CC0 tracks were fetched into
// /public/audio/music/ (deno task fetch-assets), those loop with crossfades
// instead, falling back to the synth score on any load failure.

import type { AudioManager } from "./AudioManager.ts";
import { noiseBuffer } from "./Synth.ts";

const TRACK_FILES = ["track1.mp3", "track2.mp3", "track3.mp3"];

// ---- Sequencer material (A minor, 112 BPM) ----

const BPM = 112;
const SIXTEENTH = 60 / BPM / 4;
const STEPS_PER_BAR = 16;
const ROOT = 110; // A2
const SCHED_AHEAD = 0.28; // seconds of audio scheduled per tick
const TICK_MS = 90;

// Chords as semitone offsets from A2. The 8-bar loop leans heroic for the
// first half (Am F C G) and tense for the second (Am F E E).
const CHORDS: number[][] = [
  [0, 3, 7], // Am
  [-4, 0, 3], // F
  [3, 7, 10], // C
  [-2, 2, 5], // G
  [-5, -1, 2], // E
];
const PROGRESSION = [0, 1, 2, 3, 0, 1, 4, 4];
// 16th-note arp cycles chord tones (indexes into the chord).
const ARP_PATTERN = [0, 1, 2, 1, 0, 2, 1, 2];

function semi(offset: number): number {
  return ROOT * Math.pow(2, offset / 12);
}

interface Layers {
  pad: GainNode;
  bass: GainNode;
  arp: GainNode;
  drums: GainNode;
}

export class MusicPlayer {
  private musicGain: GainNode;
  private filter: BiquadFilterNode;
  private trackSources: AudioBufferSourceNode[] = [];
  private buffers: AudioBuffer[] = [];
  private trackIndex = 0;
  private duck = 1;
  private intensity = 0;
  private pulseLevel = 0;
  private playing = false;
  private baseGain = 0.5;

  // Synth score state.
  private layers: Layers | null = null;
  private padOscs: OscillatorNode[] = [];
  private timer: number | undefined;
  private nextNoteTime = 0;
  private step = 0;

  constructor(private audio: AudioManager, private assetBase = "/audio/music") {
    const ctx = audio.ctx;
    this.filter = ctx.createBiquadFilter();
    this.filter.type = "lowpass";
    this.filter.frequency.value = 700;
    this.musicGain = ctx.createGain();
    this.musicGain.gain.value = this.baseGain;
    this.filter.connect(this.musicGain).connect(audio.musicBus);
  }

  async start(): Promise<void> {
    if (this.playing) return;
    this.playing = true;
    const loaded = await this.tryLoadTracks();
    if (loaded) this.playTrack(0);
    else this.startScore();
  }

  private async tryLoadTracks(): Promise<boolean> {
    for (const name of TRACK_FILES) {
      try {
        const res = await fetch(`${this.assetBase}/${name}`);
        if (!res.ok) continue;
        const data = await res.arrayBuffer();
        const buf = await this.audio.ctx.decodeAudioData(data);
        this.buffers.push(buf);
      } catch {
        // skip missing/unsupported
      }
    }
    return this.buffers.length > 0;
  }

  private playTrack(index: number): void {
    if (this.buffers.length === 0) return;
    this.trackIndex = index % this.buffers.length;
    const ctx = this.audio.ctx;
    const src = ctx.createBufferSource();
    src.buffer = this.buffers[this.trackIndex];
    src.connect(this.filter);
    src.start();
    // Crossfade to next track shortly before the end.
    const dur = src.buffer.duration;
    src.onended = () => {
      if (this.playing) this.playTrack(this.trackIndex + 1);
    };
    // Best-effort: schedule next a touch early for overlap on long tracks.
    if (dur > 6) {
      setTimeout(() => {
        if (this.playing) this.playTrack(this.trackIndex + 1);
      }, (dur - 2) * 1000);
      src.onended = null;
    }
    this.trackSources = [src];
  }

  // ---- Procedural score ----

  /** Build the layer buses + pad voices and start the step scheduler. */
  private startScore(): void {
    const ctx = this.audio.ctx;
    const mk = (): GainNode => {
      const g = ctx.createGain();
      g.gain.value = 0;
      g.connect(this.filter);
      return g;
    };
    this.layers = { pad: mk(), bass: mk(), arp: mk(), drums: mk() };

    // Persistent pad: two slightly-detuned saws per chord tone, retuned at bar
    // boundaries (cheaper + smoother than respawning voices every chord).
    const chord = CHORDS[PROGRESSION[0]];
    for (let tone = 0; tone < 3; tone++) {
      for (const cents of [-6, 6]) {
        const osc = ctx.createOscillator();
        osc.type = "sawtooth";
        osc.frequency.value = semi(chord[tone]);
        osc.detune.value = cents;
        const g = ctx.createGain();
        g.gain.value = 0.33; // per-voice trim into the pad bus
        osc.connect(g).connect(this.layers.pad);
        osc.start();
        this.padOscs.push(osc);
      }
    }

    this.step = 0;
    this.nextNoteTime = ctx.currentTime + 0.1;
    this.applyDynamics(0.1);
    this.timer = setInterval(() => this.tick(), TICK_MS);
  }

  private tick(): void {
    const ctx = this.audio.ctx;
    // Until the context is unlocked by a user gesture, don't build a backlog.
    if (ctx.state !== "running") {
      this.nextNoteTime = ctx.currentTime + 0.1;
      return;
    }
    // Kill pulses decay back to the baseline intensity.
    if (this.pulseLevel > 0.005) {
      this.pulseLevel *= 0.975;
      if (this.pulseLevel <= 0.005) this.pulseLevel = 0;
      this.applyDynamics(0.3);
    }
    const horizon = ctx.currentTime + SCHED_AHEAD;
    while (this.nextNoteTime < horizon) {
      this.scheduleStep(this.step, this.nextNoteTime);
      this.step++;
      this.nextNoteTime += SIXTEENTH;
    }
  }

  private scheduleStep(step: number, t: number): void {
    if (!this.layers) return;
    const bar = Math.floor(step / STEPS_PER_BAR);
    const s = step % STEPS_PER_BAR;
    const chord = CHORDS[PROGRESSION[bar % PROGRESSION.length]];
    const level = Math.min(1, this.intensity + this.pulseLevel);

    if (s === 0) this.tunePad(chord, t);

    // Bass: driving 8ths on the root an octave down, accented on the beat.
    if (s % 2 === 0) this.bassNote(semi(chord[0]) / 2, t, s % 4 === 0 ? 1 : 0.7);

    // Arp: 16th plucks cycling the chord tones, an octave up (two on odd bars).
    const oct = bar % 2 === 1 ? 24 : 12;
    this.pluck(semi(chord[ARP_PATTERN[s % ARP_PATTERN.length]] + oct), t, s % 2 === 0 ? 0.5 : 0.35);

    // Drums: kick on 1 & 3 (four-on-the-floor when the action peaks), snare
    // backbeat, hats on 8ths (16ths at high intensity).
    if (s === 0 || s === 8 || (level > 0.65 && (s === 4 || s === 12))) this.kick(t);
    if (s === 4 || s === 12) this.snare(t);
    if (s % 2 === 0 || level > 0.6) this.hat(t, s % 4 === 2 ? 0.5 : 0.3);
  }

  /** Glide the persistent pad voices to the bar's chord. */
  private tunePad(chord: number[], t: number): void {
    for (let tone = 0; tone < 3; tone++) {
      const freq = semi(chord[tone]);
      for (const osc of [this.padOscs[tone * 2], this.padOscs[tone * 2 + 1]]) {
        if (!osc) continue;
        osc.frequency.cancelScheduledValues(t);
        osc.frequency.setTargetAtTime(freq, t, 0.06);
      }
    }
  }

  private bassNote(freq: number, t: number, vel: number): void {
    if (!this.layers) return;
    const ctx = this.audio.ctx;
    const osc = ctx.createOscillator();
    osc.type = "sawtooth";
    osc.frequency.value = freq;
    const lp = ctx.createBiquadFilter();
    lp.type = "lowpass";
    lp.frequency.value = 260;
    const env = ctx.createGain();
    env.gain.setValueAtTime(0, t);
    env.gain.linearRampToValueAtTime(vel * 0.9, t + 0.008);
    env.gain.exponentialRampToValueAtTime(0.001, t + 0.22);
    osc.connect(lp).connect(env).connect(this.layers.bass);
    osc.start(t);
    osc.stop(t + 0.25);
  }

  private pluck(freq: number, t: number, vel: number): void {
    if (!this.layers) return;
    const ctx = this.audio.ctx;
    const osc = ctx.createOscillator();
    osc.type = "triangle";
    osc.frequency.value = freq;
    const env = ctx.createGain();
    env.gain.setValueAtTime(0, t);
    env.gain.linearRampToValueAtTime(vel, t + 0.004);
    env.gain.exponentialRampToValueAtTime(0.001, t + 0.14);
    osc.connect(env).connect(this.layers.arp);
    osc.start(t);
    osc.stop(t + 0.16);
  }

  private kick(t: number): void {
    if (!this.layers) return;
    const ctx = this.audio.ctx;
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(130, t);
    osc.frequency.exponentialRampToValueAtTime(42, t + 0.11);
    const env = ctx.createGain();
    env.gain.setValueAtTime(1, t);
    env.gain.exponentialRampToValueAtTime(0.001, t + 0.26);
    osc.connect(env).connect(this.layers.drums);
    osc.start(t);
    osc.stop(t + 0.28);
  }

  private snare(t: number): void {
    if (!this.layers) return;
    const ctx = this.audio.ctx;
    const src = ctx.createBufferSource();
    src.buffer = noiseBuffer(ctx);
    const hp = ctx.createBiquadFilter();
    hp.type = "highpass";
    hp.frequency.value = 1700;
    const env = ctx.createGain();
    env.gain.setValueAtTime(0.7, t);
    env.gain.exponentialRampToValueAtTime(0.001, t + 0.14);
    src.connect(hp).connect(env).connect(this.layers.drums);
    src.start(t);
    src.stop(t + 0.16);
  }

  private hat(t: number, vel: number): void {
    if (!this.layers) return;
    const ctx = this.audio.ctx;
    const src = ctx.createBufferSource();
    src.buffer = noiseBuffer(ctx);
    const hp = ctx.createBiquadFilter();
    hp.type = "highpass";
    hp.frequency.value = 6500;
    const env = ctx.createGain();
    env.gain.setValueAtTime(vel * 0.5, t);
    env.gain.exponentialRampToValueAtTime(0.001, t + 0.04);
    src.connect(hp).connect(env).connect(this.layers.drums);
    src.start(t);
    src.stop(t + 0.05);
  }

  // ---- Dynamics ----

  /** Low-health ducking: amount 0 (normal) .. 1 (heavily ducked). */
  setDuck(amount: number): void {
    this.duck = 1 - Math.max(0, Math.min(1, amount)) * 0.7;
    this.applyDynamics(0.4);
  }

  /** Base intensity 0..1: opens the filter, lifts volume, fades layers in. */
  setIntensity(level: number): void {
    this.intensity = Math.max(0, Math.min(1, level));
    this.applyDynamics(0.5);
  }

  /** Momentary surge (a kill, a streak earned) that decays back down. */
  pulse(amount = 0.35): void {
    this.pulseLevel = Math.min(0.7, this.pulseLevel + amount);
    this.applyDynamics(0.15);
  }

  /** Ramp filter, master gain, and layer mix to the current dynamics. */
  private applyDynamics(ramp: number): void {
    const t = this.audio.now;
    const level = Math.min(1, this.intensity + this.pulseLevel);

    const glide = (param: AudioParam, target: number): void => {
      param.cancelScheduledValues(t);
      param.setValueAtTime(param.value, t);
      param.linearRampToValueAtTime(target, t + ramp);
    };

    glide(this.filter.frequency, 700 + level * 2600);
    glide(this.musicGain.gain, this.baseGain * this.duck * (1 + level * 0.4));
    if (this.layers) {
      glide(this.layers.pad.gain, 0.34);
      glide(this.layers.bass.gain, 0.1 + level * 0.42);
      glide(this.layers.arp.gain, Math.max(0, level - 0.12) * 0.5);
      glide(this.layers.drums.gain, Math.max(0, level - 0.26) * 1.0);
    }
  }

  stop(): void {
    this.playing = false;
    if (this.timer !== undefined) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
    for (const osc of this.padOscs) {
      try {
        osc.stop();
      } catch { /* already stopped */ }
      osc.disconnect();
    }
    this.padOscs = [];
    if (this.layers) {
      for (const g of Object.values(this.layers)) g.disconnect();
      this.layers = null;
    }
    for (const s of this.trackSources) {
      try {
        s.stop();
      } catch { /* already stopped */ }
    }
    this.trackSources = [];
  }
}
