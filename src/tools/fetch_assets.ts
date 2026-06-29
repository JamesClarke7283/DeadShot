// DeadShot asset fetcher.
//
// Downloads CC0 asset packs (Quaternius characters, Kenney props) and CC0 music
// into /public, with a procedural fallback guarantee: if any download fails the
// game still runs using procedurally generated characters/props/audio.
//
// Phase 0 stub — the real download lists are populated in Phase 2.2 (models) and
// Phase 11.2 (music). For now it just ensures the target directories exist so
// the game's loaders can probe them and gracefully fall back.
//
//   deno task fetch-assets

import { ensureDir } from "@std/fs";
import { join, resolve } from "@std/path";

const REPO_ROOT = resolve(new URL("../../", import.meta.url).pathname);
const PUBLIC = join(REPO_ROOT, "public");

const TARGET_DIRS = [
  join(PUBLIC, "models", "quaternius"),
  join(PUBLIC, "models", "kenney"),
  join(PUBLIC, "audio", "music"),
];

async function main(): Promise<void> {
  for (const dir of TARGET_DIRS) {
    await ensureDir(dir);
    console.info(`[fetch-assets] ensured ${dir}`);
  }
  console.info(
    "[fetch-assets] stub complete. Download manifests are added in Phase 2.2 " +
      "(models) and Phase 11.2 (music). The game runs with procedural fallbacks " +
      "if assets are absent.",
  );
}

if (import.meta.main) {
  await main();
}
