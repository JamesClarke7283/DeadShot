// DeadShot asset fetcher.
//
// Downloads optional CC0 asset packs into /public with a procedural fallback
// guarantee: every download is best-effort, and the game runs fully (procedural
// characters/props + synthesized SFX + a procedural music bed) if nothing is
// fetched or the network is unavailable.
//
//   deno task fetch-assets

import { ensureDir } from "@std/fs";
import { join, resolve } from "@std/path";

const REPO_ROOT = resolve(new URL("../../", import.meta.url).pathname);
const PUBLIC = join(REPO_ROOT, "public");

const MODEL_DIRS = [
  join(PUBLIC, "models", "quaternius"),
  join(PUBLIC, "models", "kenney"),
];
const MUSIC_DIR = join(PUBLIC, "audio", "music");

// CC0 / public-domain dramatic tracks. Saved as track1/2/3.mp3 (the order
// MusicPlayer probes). Replace/extend with verified CC0 sources as desired —
// any that fail to download are skipped (procedural bed covers the gap).
const MUSIC: { url: string; file: string }[] = [
  // Pixabay & similar host royalty-free/CC0 cinematic loops; verify the license
  // of any track you ship. These are placeholders that are skipped if offline.
  { url: "https://cdn.pixabay.com/download/audio/2022/03/15/audio_1c3f.mp3", file: "track1.mp3" },
  { url: "https://cdn.pixabay.com/download/audio/2021/11/25/audio_2a3b.mp3", file: "track2.mp3" },
  { url: "https://cdn.pixabay.com/download/audio/2022/08/02/audio_3d4e.mp3", file: "track3.mp3" },
];

async function tryDownload(url: string, dest: string): Promise<boolean> {
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
    if (!res.ok) return false;
    const bytes = new Uint8Array(await res.arrayBuffer());
    if (bytes.length < 1024) return false; // too small to be real audio
    await Deno.writeFile(dest, bytes);
    return true;
  } catch {
    return false;
  }
}

async function main(): Promise<void> {
  for (const dir of [...MODEL_DIRS, MUSIC_DIR]) {
    await ensureDir(dir);
    console.info(`[fetch-assets] ensured ${dir}`);
  }

  console.info("[fetch-assets] models: procedural characters/props are the default;");
  console.info("  drop a Quaternius GLTF in /public/models/quaternius/ to use it.");

  let music = 0;
  for (const t of MUSIC) {
    const dest = join(MUSIC_DIR, t.file);
    const ok = await tryDownload(t.url, dest);
    if (ok) {
      music++;
      console.info(`[fetch-assets] downloaded ${t.file}`);
    } else {
      console.info(`[fetch-assets] skipped ${t.file} (unreachable / not CC0 mirror)`);
    }
  }

  console.info(
    `[fetch-assets] done. ${music}/${MUSIC.length} music tracks fetched; ` +
      `the procedural music bed plays when none are present.`,
  );
}

if (import.meta.main) {
  await main();
}
