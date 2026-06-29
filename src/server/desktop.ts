// DeadShot native desktop launcher.
//
// Starts the same HTTP server used by the browser target, then opens a
// webview_deno (WebKitGTK on Linux) window pointing at it. Fleshed out in
// Phase 12.2 (window title, default size, F11 fullscreen toggle).
//
//   deno task run-client

import { startServer } from "./server.ts";

async function main(): Promise<void> {
  const server = await startServer({ open: false });

  // Import lazily so the browser-only build path never pulls in the FFI dep.
  const { Webview, SizeHint } = await import("@webview/webview");

  const webview = new Webview(true, {
    width: 1280,
    height: 720,
    hint: SizeHint.NONE,
  });
  webview.title = "DeadShot";

  // F11 fullscreen toggle, wired from the page side via a bound function.
  let fullscreen = false;
  webview.bind("deadshotToggleFullscreen", () => {
    fullscreen = !fullscreen;
    webview.size = fullscreen
      ? { width: 1920, height: 1080, hint: SizeHint.MAX }
      : { width: 1280, height: 720, hint: SizeHint.NONE };
    return fullscreen;
  });
  webview.init(`
    window.addEventListener('keydown', (e) => {
      if (e.key === 'F11') { e.preventDefault(); window.deadshotToggleFullscreen(); }
    });
  `);

  webview.navigate(server.url);
  webview.run();

  await server.shutdown();
}

if (import.meta.main) {
  await main();
}
