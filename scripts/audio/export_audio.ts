/** Generate native WAV assets by offline-rendering the unchanged source WebAudio.
 * deno run -A --config ../DeadShot/deno.json scripts/audio/export_audio.ts
 */
import { launch } from "jsr:@astral/astral@0.5.6";
import * as esbuild from "npm:esbuild@0.24.2";
import { denoPlugins } from "jsr:@luca/esbuild-deno-loader@0.11.1";
import { WEAPONS } from "../../../DeadShot/src/weapons/WeaponDefinition.ts";

const root = new URL("../../", import.meta.url);
const output = new URL("assets/audio/", root);
await Deno.mkdir(output, { recursive: true });
const onlyIndex = Deno.args.indexOf("--only");
const only = onlyIndex < 0 ? null : new Set(Deno.args.slice(onlyIndex + 1));
const build = await esbuild.build({
  entryPoints: [new URL("./capture_source.ts", import.meta.url).pathname],
  bundle: true,
  format: "iife",
  platform: "browser",
  write: false,
  plugins: denoPlugins({
    configPath: new URL("../DeadShot/deno.json", root).pathname,
  }),
});
esbuild.stop();
await using browser = await launch({
  headless: true,
  path: "/usr/bin/chromium",
  args: ["--no-sandbox"],
});
const page = await browser.newPage();
await page.evaluate(build.outputFiles[0].text);
const representatives = Object.fromEntries(
  WEAPONS.filter((w) => w.id !== "knife").map((w) => [w.category, w.id]),
);
const manifest: Record<string, unknown> = {
  source:
    "Original DeadShot Synth.ts, WeaponSFX.ts, MusicPlayer.ts rendered in Chromium OfflineAudioContext; no third-party audio",
  sampleRate: 44100,
  musicBpm: 112,
  musicLoopSeconds: 60 / 112 * 4 * 8,
  weapons: Object.fromEntries(WEAPONS.map((w) => [w.id, w.category])),
  sounds: {},
};
if (only) {
  Object.assign(
    manifest,
    JSON.parse(await Deno.readTextFile(new URL("manifest.json", output))),
  );
}
const sounds = manifest.sounds as Record<
  string,
  { file: string; restoreGain: number; frames: number; loop: boolean }
>;

function wav(samples: number[], rate: number): Uint8Array {
  const buffer = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  const ascii = (offset: number, value: string) =>
    bytes.set(new TextEncoder().encode(value), offset);
  ascii(0, "RIFF");
  view.setUint32(4, 36 + samples.length * 2, true);
  ascii(8, "WAVEfmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, rate, true);
  view.setUint32(28, rate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  ascii(36, "data");
  view.setUint32(40, samples.length * 2, true);
  samples.forEach((sample, i) =>
    view.setInt16(
      44 + i * 2,
      Math.round(Math.max(-1, Math.min(1, sample)) * 32767),
      true,
    )
  );
  return bytes;
}

async function capture(
  name: string,
  source: string,
  variant = 0,
): Promise<void> {
  if (only && !only.has(name)) return;
  const result = await page.evaluate(
    `captureDeadshotAudio(${JSON.stringify(source)},${variant})`,
  ) as { samples: number[]; rate: number; restoreGain: number };
  if (
    !result.samples.length || result.samples.every((sample) => sample === 0)
  ) {
    throw new Error(`Silent generated sound: ${name}`);
  }
  await Deno.writeFile(
    new URL(`${name}.wav`, output),
    wav(result.samples, result.rate),
  );
  sounds[name] = {
    file: `res://assets/audio/${name}.wav`,
    restoreGain: result.restoreGain,
    frames: result.samples.length,
    loop: name.startsWith("music_"),
  };
  console.log(`Rendered ${name}: ${result.samples.length} samples`);
}

for (const [category, id] of Object.entries(representatives)) {
  for (let variant = 0; variant < 4; variant++) {
    await capture(`gun_${category}_${variant}`, `gun_${id}`, variant);
  }
}
for (
  const id of [
    "reload",
    "hit",
    "headshot",
    "click",
    "footstep",
    "beep",
    "explosion_0.2",
    "explosion_0.25",
    "explosion_0.375",
    "explosion_0.5",
    "explosion_0.75",
    "explosion_1",
    "explosion_1.25",
    "explosion_1.375",
    "explosion_1.5",
    "explosion_1.75",
    "explosion_2",
    "music_pad",
    "music_bass",
    "music_arp",
    "music_drums",
    "music_drums_hats",
    "music_drums_kicks",
  ]
) await capture(id, id);
await Deno.writeTextFile(
  new URL("manifest.json", output),
  JSON.stringify(manifest, null, 2),
);
console.log(`Generated ${Object.keys(sounds).length} native audio assets.`);
