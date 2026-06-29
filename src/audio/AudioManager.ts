// AudioManager: the audio engine root.
//
// Uses Three.js's shared AudioContext so a camera-mounted AudioListener stays in
// sync with manually-built WebAudio graphs (synth + positional panners). Exposes
// master / sfx / music gain buses driven from settings. The context starts
// suspended under browser autoplay policy; call resume() from a user gesture.

import * as THREE from "../three.ts";

export interface VolumeSettings {
  master: number;
  sfx: number;
  music: number;
}

export class AudioManager {
  readonly ctx: AudioContext;
  readonly listener: THREE.AudioListener;
  readonly master: GainNode;
  readonly sfxBus: GainNode;
  readonly musicBus: GainNode;
  private muffle = 0; // 0..1 deafen amount (flashbang)

  constructor(camera: THREE.Camera, volumes: VolumeSettings) {
    this.listener = new THREE.AudioListener();
    camera.add(this.listener);
    this.ctx = this.listener.context as AudioContext;

    this.master = this.ctx.createGain();
    this.sfxBus = this.ctx.createGain();
    this.musicBus = this.ctx.createGain();
    this.sfxBus.connect(this.master);
    this.musicBus.connect(this.master);
    this.master.connect(this.ctx.destination);
    this.setVolumes(volumes);
  }

  setVolumes(v: VolumeSettings): void {
    this.master.gain.value = v.master;
    this.sfxBus.gain.value = v.sfx;
    this.musicBus.gain.value = v.music;
  }

  /** Resume the context from a user gesture (click). */
  resume(): void {
    if (this.ctx.state === "suspended") void this.ctx.resume();
  }

  get now(): number {
    return this.ctx.currentTime;
  }

  /** Briefly muffle SFX (flashbang deafen) over `duration` seconds. */
  deafen(duration: number): void {
    this.muffle = 1;
    const t = this.now;
    this.sfxBus.gain.cancelScheduledValues(t);
    this.sfxBus.gain.setValueAtTime(0.05, t);
    this.sfxBus.gain.linearRampToValueAtTime(this.sfxBaseGain, t + duration);
    this.muffle = 0;
  }

  /** Current sfx bus target gain (used to restore after ducking). */
  sfxBaseGain = 0.9;
}
