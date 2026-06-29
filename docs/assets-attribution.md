# Asset attribution

DeadShot is designed to run entirely with **procedurally generated** content, so it has **no
required third-party assets**. Optional CC0 packs can be downloaded with `deno task fetch-assets` to
upgrade the visuals/audio; if they are absent (offline, or never fetched) the game falls back to
procedural equivalents with no loss of functionality.

All optional assets below are **CC0 / public domain** (no attribution legally required); they are
credited here as good practice.

## Procedural fallback guarantee

| System        | Optional asset                                | Procedural fallback                                                                                                                                     |
| ------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Characters    | Quaternius "Ultimate Animated Character" GLTF | `ProceduralHuman` — low-poly humanoid + cartoon face, assembled from primitives with sine-driven idle/run/shoot/die animation. **This is the default.** |
| Props / cover | Kenney prop packs (crates, barrels, vehicles) | Primitive-built obstacles in `src/maps/Obstacle.ts`.                                                                                                    |
| Weapon SFX    | — (always synthesized)                        | `src/audio/Synth.ts` WebAudio synthesis (no samples used).                                                                                              |
| Music         | CC0 dramatic tracks (Incompetech / FMA)       | Silence, or a light synthesized ambient bed.                                                                                                            |

The character loader (`src/characters/CharacterFactory.ts`) probes `/public/models/quaternius/` for
a model file and, on any miss or load error, constructs a `ProceduralHuman`. The probe failing
(HTTP 404) is expected and handled, not an error condition.

## Optional CC0 packs

### Characters — Quaternius (CC0)

- **Source:** <https://quaternius.com/> — "Ultimate Animated Character Pack".
- **License:** CC0 1.0 Universal (public domain dedication).
- **Install:** `deno task fetch-assets` downloads to `/public/models/quaternius/`.
- **Used as:** team-recolored, cel-shaded GLTF characters with mixer-driven idle/run/shoot/death
  animations (see `GLTFCharacter`).

### Props — Kenney (CC0)

- **Source:** <https://kenney.nl/assets> — e.g. "Survival Kit", "City Kit".
- **License:** CC0 1.0 Universal.
- **Install:** `/public/models/kenney/` via `deno task fetch-assets`.

### Music — CC0 dramatic tracks

- **Sources:** <https://incompetech.com/> (filter to CC0/Public Domain),
  <https://freemusicarchive.org/> (CC0 tracks only).
- **License:** CC0 1.0 Universal (only CC0 tracks are bundled; verify per-track).
- **Install:** `/public/audio/music/` via `deno task fetch-assets`.
- **Used by:** `src/audio/MusicPlayer.ts` (crossfade, low-health ducking).

## Libraries

- **Three.js** (MIT) — <https://threejs.org/>.
- **esbuild** (MIT), **@luca/esbuild-deno-loader** (MIT), **@webview/webview** (MIT).
