// DeadShot HTTP server.
//
// Serves the static /public directory and bundles the TypeScript client
// (src/main.ts + all npm:three imports) on the fly with esbuild, exposing the
// result at /bundle.js. Because everything is bundled server-side the browser
// only ever loads plain JavaScript and never needs an import map.
//
// Used by both run targets:
//   deno task run-browser  -> startServer({ open: true })
//   deno task run-client   -> desktop.ts calls startServer({ open: false })

import * as esbuild from "esbuild";
import { denoPlugins } from "@luca/esbuild-deno-loader";
import { contentType } from "@std/media-types";
import { extname, join, normalize, resolve } from "@std/path";
import { walk } from "@std/fs";

const REPO_ROOT = resolve(new URL("../../", import.meta.url).pathname);
const PUBLIC_DIR = join(REPO_ROOT, "public");
const ENTRY = join(REPO_ROOT, "src", "main.ts");
const SRC_DIR = join(REPO_ROOT, "src");
const CONFIG = join(REPO_ROOT, "deno.json");

export interface ServerOptions {
  /** TCP port to bind. Defaults to env DEADSHOT_PORT or 8080. */
  port?: number;
  /** Open the system browser at the served URL once listening. */
  open?: boolean;
  /** Hostname to bind. Defaults to 127.0.0.1. */
  hostname?: string;
}

interface BundleCache {
  js: string;
  builtAtMaxMtime: number;
}

let bundleCache: BundleCache | null = null;
let buildInFlight: Promise<string> | null = null;

/** Latest mtime (ms) across the TypeScript sources, so we rebuild on change. */
async function latestSourceMtime(): Promise<number> {
  let max = 0;
  for await (
    const entry of walk(SRC_DIR, {
      exts: [".ts"],
      includeDirs: false,
      skip: [/\.test\.ts$/, /[/\\]tools[/\\]/, /[/\\]server[/\\]/],
    })
  ) {
    try {
      const info = await Deno.stat(entry.path);
      if (info.mtime) max = Math.max(max, info.mtime.getTime());
    } catch {
      // ignore transient stat failures
    }
  }
  return max;
}

async function buildBundle(): Promise<string> {
  const result = await esbuild.build({
    plugins: [...denoPlugins({ configPath: CONFIG })],
    entryPoints: [ENTRY],
    bundle: true,
    format: "esm",
    platform: "browser",
    target: ["chrome120", "firefox120"],
    sourcemap: "inline",
    write: false,
    logLevel: "silent",
    legalComments: "none",
  });
  if (!result.outputFiles?.length) throw new Error("esbuild produced no output");
  return result.outputFiles[0].text;
}

/** Build (or return cached) client bundle, rebuilding when sources change. */
async function getBundle(): Promise<string> {
  const mtime = await latestSourceMtime();
  if (bundleCache && bundleCache.builtAtMaxMtime >= mtime) {
    return bundleCache.js;
  }
  if (buildInFlight) return buildInFlight;
  buildInFlight = (async () => {
    const started = performance.now();
    const js = await buildBundle();
    bundleCache = { js, builtAtMaxMtime: mtime };
    console.info(
      `[server] bundled client in ${(performance.now() - started).toFixed(0)}ms ` +
        `(${(js.length / 1024).toFixed(0)} KiB)`,
    );
    return js;
  })();
  try {
    return await buildInFlight;
  } finally {
    buildInFlight = null;
  }
}

function notFound(): Response {
  return new Response("404 Not Found", { status: 404 });
}

/** Resolve a request path to a file inside /public, blocking traversal. */
function resolvePublicPath(pathname: string): string | null {
  const clean = normalize(decodeURIComponent(pathname)).replace(/^(\.\.[/\\])+/, "");
  const full = join(PUBLIC_DIR, clean);
  if (!full.startsWith(PUBLIC_DIR)) return null;
  return full;
}

async function serveStatic(pathname: string): Promise<Response> {
  let rel = pathname === "/" ? "/index.html" : pathname;
  const full = resolvePublicPath(rel);
  if (!full) return notFound();
  try {
    const stat = await Deno.stat(full);
    if (stat.isDirectory) {
      rel = join(rel, "index.html");
      return serveStatic(rel);
    }
    const body = await Deno.readFile(full);
    const mime = contentType(extname(full)) ?? "application/octet-stream";
    return new Response(body, {
      headers: { "content-type": mime, "cache-control": "no-cache" },
    });
  } catch {
    return notFound();
  }
}

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);

  if (url.pathname === "/bundle.js") {
    try {
      const js = await getBundle();
      return new Response(js, {
        headers: {
          "content-type": "text/javascript; charset=utf-8",
          "cache-control": "no-cache",
        },
      });
    } catch (err) {
      console.error("[server] bundle build failed:", err);
      const msg = err instanceof Error ? err.message : String(err);
      // Surface the build error in the browser console.
      return new Response(
        `console.error(${JSON.stringify("DeadShot build error:\n" + msg)});`,
        { status: 200, headers: { "content-type": "text/javascript" } },
      );
    }
  }

  if (url.pathname === "/healthz") {
    return new Response("ok", { status: 200 });
  }

  return serveStatic(url.pathname);
}

function openBrowser(target: string): void {
  const cmd = Deno.build.os === "darwin"
    ? "open"
    : Deno.build.os === "windows"
    ? "explorer"
    : "xdg-open";
  try {
    new Deno.Command(cmd, { args: [target], stdout: "null", stderr: "null" }).spawn();
  } catch (err) {
    console.warn(`[server] could not open browser (${cmd}):`, err);
  }
}

export interface RunningServer {
  port: number;
  url: string;
  shutdown: () => Promise<void>;
}

/** Start the HTTP server. Resolves once it is listening. */
export function startServer(opts: ServerOptions = {}): Promise<RunningServer> {
  const port = opts.port ?? Number(Deno.env.get("DEADSHOT_PORT") ?? 8080);
  const hostname = opts.hostname ?? "127.0.0.1";

  return new Promise((resolvePromise) => {
    const ac = new AbortController();
    const server = Deno.serve(
      {
        port,
        hostname,
        signal: ac.signal,
        onListen: ({ port: boundPort, hostname: boundHost }) => {
          const url = `http://${boundHost}:${boundPort}/`;
          console.info(`[server] DeadShot listening at ${url}`);
          // Warm the bundle so the first page load is instant.
          getBundle().catch((e) => console.error("[server] warm build failed:", e));
          if (opts.open) openBrowser(url);
          resolvePromise({
            port: boundPort,
            url,
            shutdown: async () => {
              ac.abort();
              await server.finished;
              await esbuild.stop();
            },
          });
        },
      },
      handler,
    );
  });
}

if (import.meta.main) {
  await startServer({ open: true });
}
