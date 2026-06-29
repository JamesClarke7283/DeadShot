# DeadShot — Agent Notes

A Call-of-Duty-style cartoon FPS built with Deno 2.x + Three.js (r180 via `npm:` specifier),
playable in the browser and as a native desktop window.

## Project Operations

- Runtime / package manager: **Deno 2.x** (not npm/node). Deps via `npm:` and `jsr:` specifiers
  mapped in `deno.json`.
- Run in browser: `deno task run-browser` (HTTP server on `127.0.0.1:8080`, override with
  `DEADSHOT_PORT`, opens system browser).
- Run native window: `deno task run-client` (webview_deno / WebKitGTK).
- Download CC0 assets: `deno task fetch-assets` (procedural fallback if offline).
- Tests: `deno task test` (= `deno test -A`).
- Lint: `deno task lint`. Format: `deno task fmt` (check: `deno task fmt:check`).
- Type-check: `deno task check` (or `deno check <file>`).
- **Before each commit:** `deno fmt`, `deno lint`, and `deno check` must be clean.
- The browser never loads TypeScript directly: `src/server/server.ts` bundles `src/main.ts` (+ all
  `three` imports) with esbuild and serves `/bundle.js`. The bundle auto-rebuilds when any
  `src/**/*.ts` changes (mtime check).

## Architecture (high level)

- `src/core/` — engine: Game state machine, Renderer, Scene, Camera, Clock, Input, AssetLoader.
- `src/render/` — cartoon pipeline: ToonMaterial, OutlinePass, Lighting.
- `src/characters/` — CharacterFactory/ProceduralHuman/Face, Bot, BotAI, BotNavigator.
- `src/weapons/`, `src/tacticals/`, `src/maps/`, `src/game/`, `src/streaks/`, `src/ui/`,
  `src/audio/`, `src/persistence/` — feature modules.
- `src/server/` — HTTP server + desktop (webview) launcher.

## Research

Check these before web searching (load with the Read tool as needed):

- @docs/deno-three-setup.md — import-map + `npm:three` approach, esbuild bundling server, the two
  run targets, webview_deno on first run, pointer lock notes.

### Library quirks learned

- `@webview/webview` (jsr:@webview/webview@0.9.0): set window size via the
  `webview.size = { width, height, hint }` **setter** (there is no `set_size` method). `SizeHint` is
  a const object: `NONE|MIN|MAX|FIXED`. `webview.run()` blocks until the window closes, then
  auto-destroys. Needs `--unstable-ffi`.
- esbuild on Deno: use `npm:esbuild` + `jsr:@luca/esbuild-deno-loader`'s
  `denoPlugins({ configPath })` (absolute path to `deno.json`) to resolve the import map + npm
  cache. esbuild keeps a service process alive; call `esbuild.stop()` on shutdown (the long-running
  server just leaves it up).
- `three` REVISION is `180` for `three@0.180.0`.
