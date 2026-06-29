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
- **Typing three under Deno:** three ships NO `.d.ts`. Import THREE from the typed barrel
  `src/three.ts` (which has `// @ts-types="npm:@types/three@0.180.0"` above
  `export * from "three"`). Addons go through `src/vendor/<Name>.ts` barrels with
  `// @ts-types="npm:@types/three@0.180.0/examples/jsm/.../<Name>.d.ts"`. Never
  `import ... from "three"` directly in feature code, or THREE becomes `any` and every callback
  param is an implicit-any error.
- **Import map for addons:** `"three/addons/": "npm:/three@0.180.0/examples/jsm/"` — note the
  leading slash after `npm:` (the `npm:/` subpath form). Without it `deno check` fails to URL-parse
  the addon sub-path.
- PointerLockControls (r180): `controls.object` is typed `Object3D`; expose the `PerspectiveCamera`
  directly instead of casting. `moveForward/moveRight` move parallel to the XZ plane (keeps eye
  height). `pointerSpeed` = sensitivity.

## Project Operations (gotchas learned)

- **UI screens MUST start hidden.** Every `src/ui` overlay (MainMenu, PreMatchMenu, …) is created
  once and toggled via show()/hide(); the Game only show()s the active state's screen and hide()s on
  `exit`. A screen created with `display:flex` that is never _entered_ will linger on top forever
  (this caused the PreMatch lobby to cover a running match — "won't go into the map"). Overlays
  start `display:none` and set `pointerEvents:auto` so they're modal (not click-through to the
  canvas). `Game.startMatch` also defensively hides all menus.
- **Headless verification fallback:** when the t3code preview tab wedges (a runaway rAF match pegs
  it), drive a real headless Chromium with `jsr:@astral/astral` instead:
  `launch({headless:true, args:["--no-sandbox","--use-gl=swiftshader"]})`, `page.evaluate(...)` to
  read `window.deadshot` / click buttons, `page.screenshot()` to capture. Independent of the MCP
  preview.
