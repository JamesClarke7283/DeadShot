// DeadShot — Deno Desktop entrypoint (experimental; requires Deno >= 2.9).
//
//   deno task run-desktop        # dev: native window (WebKitGTK webview)
//   deno task run-desktop:cef    # native window with the bundled Chromium (CEF)
//   deno task build-desktop      # package a distributable (Linux AppImage)
//
// How it works: under `deno desktop`, the runtime picks a free port, exposes it
// via DENO_SERVE_ADDRESS, and `Deno.serve()` binds there automatically; the
// desktop webview then auto-navigates to that address once the server is ready.
// So we just start the SAME server the browser/`run-client` targets use — no
// browser launch, no manual window navigation. The game (Three.js/WebGL) renders
// in the webview; if WebGL misbehaves on the default WebKitGTK backend, use the
// CEF backend (run-desktop:cef / `"backend": "cef"`), which ships Chromium.
//
// See docs/architecture.md and https://docs.deno.com/runtime/desktop/.

import { startServer } from "./server.ts";

// open:false — the desktop webview is the only window. Deno.serve keeps the
// process (and thus the window) alive; the runtime overrides the bind address.
await startServer({ open: false });
