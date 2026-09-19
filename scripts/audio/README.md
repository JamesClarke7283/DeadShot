# Native audio

`audio_manager.gd` plays the original DeadShot procedural audio as native Godot streams.
`capture_source.ts` calls the actual Three.js project's `Synth.ts`, `WeaponSFX.ts`, and
`MusicPlayer.ts` inside Chromium's `OfflineAudioContext`. It does not approximate the WebAudio
filters or oscillators with new formulas. No external music or sound samples were present in the
source project, and no third-party audio has been downloaded.

Rebuild from the Godot project directory:

```sh
deno run -A --config ../DeadShot/deno.json scripts/audio/export_audio.ts
python tools/run_check.py --script scripts/audio/verify_audio.gd
```

The 55-asset library exposes weapon, reload, hit-marker, explosion, footstep, click, beep, and deafen
methods. Eleven explosion sizes cover every original `radius / 4` value, capped at 2, including
Thermite (0.2), Stun (0.375), and Semtex (1.375). Three volume
buses accept the original settings keys. The six music stems preserve the source 112 BPM, eight-bar
chord progression, bass/pluck/drum notes, layer gains, low-health duck, kill pulse, and percussion
intensity gates.

Audio uses 44.1-kHz 16-bit PCM with per-stream gain restoration to avoid clipping during capture.
Spatial gain uses the original inverse-distance formula: reference distance 8 m, rolloff 1.1,
and distance clamped at 220 m. Filter, master, and stem gains follow independent source linear ramps.
Four deterministic gunshot variants retain the source's randomized noise playback rate. The score
loops an eight-bar capture with a 2-ms boundary fade. Native 3D panning and native music-bus
filtering are the Godot equivalents; they are not the browser's HRTF implementation or a
bit-identical live WebAudio filter. Extra percussion stems follow the original intensity gates;
their transitions are applied to recorded loops rather than the browser's 280-ms note scheduler.
There was no voice announcer in the source. The original gameplay only records deafen state:
it never calls the audio deafen helper. Footstep/click/beep helpers are also not wired to gameplay.
