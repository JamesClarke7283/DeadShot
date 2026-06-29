# Deno + Three.js setup

How DeadShot runs Three.js in the browser and as a native desktop window, all
from a single Deno + TypeScript codebase.

## Import map (`npm:` specifier approach)

`deno.json` maps the bare `three` specifier to the npm package and the addons
sub-path to the examples folder:

```jsonc
{
  "imports": {
    "three": "npm:three@0.180.0",
    "three/addons/": "npm:three@0.180.0/examples/jsm/"
  }
}
```

Source files therefore use ordinary specifiers:

```ts
import * as THREE from "three";
import { PointerLockControls } from "three/addons/controls/PointerLockControls.js";
```

Deno resolves these through its npm cache. The first run downloads the package
(`deno cache` / first `deno task`); afterwards everything works **offline**.

## How the browser gets JavaScript

The browser cannot execute TypeScript, and bare specifiers like `three` need
resolution. Rather than shipping an in-browser import map that points at a CDN
(which would require network access at play time), the **server bundles the
client itself**:

- `src/server/server.ts` runs [`esbuild`](https://esbuild.github.io/) with
  [`@luca/esbuild-deno-loader`](https://jsr.io/@luca/esbuild-deno-loader). The
  loader plugin reuses Deno's module resolution (import map + npm cache), so
  `three`, `three/addons/*`, and all of our `.ts` files bundle into a single ESM
  file.
- That bundle is served at **`/bundle.js`** and `public/index.html` loads it with
  `<script type="module" src="/bundle.js">`.
- The bundle is cached in memory and rebuilt automatically when any file under
  `src/` changes (mtime check), so editing + refreshing is instant during dev.
- Source maps are inlined for debuggability.

Net effect: the browser only ever loads plain JS, no import map or CDN needed,
and the whole thing runs offline once dependencies are cached.

## Run targets

| Task | Command | What it does |
|---|---|---|
| `deno task run-browser` | `deno run -A src/server/server.ts` | Starts the HTTP server on `127.0.0.1:8080` (override with `DEADSHOT_PORT`) and opens the system browser. |
| `deno task run-client` | `deno run -A --unstable-ffi src/server/desktop.ts` | Starts the same server, then opens a native `webview_deno` window pointing at it. |
| `deno task fetch-assets` | `deno run -A src/tools/fetch_assets.ts` | Downloads CC0 model/music packs into `/public` (procedural fallback if offline). |
| `deno task test` | `deno test -A` | Runs unit tests. |
| `deno task lint` / `fmt` | `deno lint` / `deno fmt` | Lint / format. |

## `webview_deno` on first run

`run-client` imports [`@webview/webview`](https://jsr.io/@webview/webview)
lazily. On first run Deno downloads the package and the platform's prebuilt
`libwebview` shared library. On Linux this binds to **WebKitGTK**, so the system
must have `webkit2gtk` / `libwebkit2gtk-4.1` installed (most desktop distros do).
FFI is required, hence the `--unstable-ffi` flag in the task.

### Pointer lock inside the webview

WebKitGTK supports the Pointer Lock API, but some builds require a user gesture
and may show a permission prompt. DeadShot engages pointer lock on an explicit
canvas click (never automatically), which satisfies the gesture requirement. If
lock fails inside the webview, the browser target (`run-browser`) is the
fallback for development. F11 toggles the window between windowed (1280×720) and
maximized.

## Why not `deno bundle` / a build step?

`esbuild` gives us fast incremental rebuilds, tree-shaking, source maps, and
robust npm resolution via the Deno loader — all in-process, with no separate
build artifact to keep in sync. The server is the build system.
