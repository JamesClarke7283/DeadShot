// MusicPlayer: dramatic background music with crossfade, low-health ducking, and
// streak intensification.
//
// Offline-first: it always has a synthesized ambient bed (detuned pads + slow
// filter sweep) so music plays with zero assets. If CC0 tracks were fetched into
// /public/audio/music/ (deno task fetch-assets), it loads + loops them with
// crossfades on top instead, falling back to the bed on any load failure.

import type { AudioManager } from "./AudioManager.ts";

const TRACK_FILES = ["track1.mp3", "track2.mp3", "track3.mp3"];

export class MusicPlayer {
  private musicGain: GainNode;
  private filter: BiquadFilterNode;
  private bedNodes: AudioNode[] = [];
  private trackSources: AudioBufferSourceNode[] = [];
  private buffers: AudioBuffer[] = [];
  private trackIndex = 0;
  private duck = 1;
  private intensity = 0;
  private playing = false;
  private baseGain = 0.5;

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
    else this.startBed();
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

  /** Procedural ambient bed (detuned triangle pads + slow filter LFO). */
  private startBed(): void {
    const ctx = this.audio.ctx;
    const root = 110; // A2
    const freqs = [root, root * 1.5, root * 2]; // root, fifth, octave
    for (const f of freqs) {
      const osc = ctx.createOscillator();
      osc.type = "triangle";
      osc.frequency.value = f;
      osc.detune.value = (Math.random() - 0.5) * 8;
      const g = ctx.createGain();
      g.gain.value = 0.18;
      osc.connect(g).connect(this.filter);
      osc.start();
      this.bedNodes.push(osc, g);
    }
    // Slow LFO on the filter cutoff for movement.
    const lfo = ctx.createOscillator();
    lfo.frequency.value = 0.05;
    const lfoGain = ctx.createGain();
    lfoGain.gain.value = 300;
    lfo.connect(lfoGain).connect(this.filter.frequency);
    lfo.start();
    this.bedNodes.push(lfo, lfoGain);
  }

  /** Low-health ducking: amount 0 (normal) .. 1 (heavily ducked). */
  setDuck(amount: number): void {
    this.duck = 1 - Math.max(0, Math.min(1, amount)) * 0.7;
    this.applyGain();
  }

  /** Streak intensity 0..1 opens the filter + lifts the volume. */
  setIntensity(level: number): void {
    this.intensity = Math.max(0, Math.min(1, level));
    const t = this.audio.now;
    this.filter.frequency.cancelScheduledValues(t);
    this.filter.frequency.linearRampToValueAtTime(700 + this.intensity * 2500, t + 0.5);
    this.applyGain();
  }

  private applyGain(): void {
    const target = this.baseGain * this.duck * (1 + this.intensity * 0.4);
    const t = this.audio.now;
    this.musicGain.gain.cancelScheduledValues(t);
    this.musicGain.gain.linearRampToValueAtTime(target, t + 0.4);
  }

  stop(): void {
    this.playing = false;
    for (const n of this.bedNodes) {
      try {
        (n as OscillatorNode).stop?.();
      } catch { /* gain nodes have no stop */ }
      n.disconnect();
    }
    this.bedNodes = [];
    for (const s of this.trackSources) {
      try {
        s.stop();
      } catch { /* already stopped */ }
    }
    this.trackSources = [];
  }
}
