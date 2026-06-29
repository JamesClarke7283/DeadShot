# DeadShot

A Call-of-Duty-style **cartoon FPS** built with **Deno + Three.js (r180)**, playable in the browser
and as a native desktop window. Procedural-first: it runs fully with zero downloaded assets
(low-poly toon characters, synthesized weapon SFX, a procedural music bed).

![cartoon low-poly FPS]

## Features

- 18 weapons across 8 categories with a full **Create-a-Class** editor (optics, barrels, mags,
  stocks, grips, perks, field upgrades, camo, tacticals, lethals, scorestreaks) + live stat bars and
  a 3D camo preview.
- CoD-style **tacticals & lethals** (flashbang, smoke, stun, snapshot, frag, semtex, throwing knife,
  C4, molotov, thermite, claymore).
- **12 scorestreaks** incl. UAV, care package, sentry, RC-XD, predator, attack heli, gunship,
  chopper gunner, strafe run, juggernaut, and a match-ending Nuke.
- 3 hand-built maps (Desert Town, Forest Facility, Urban Docks) with terrain, buildings, foliage and
  cover; **TDM** and **FFA** modes; 0–16 bots across Recruit / Regular / Veteran AI.
- 100 HP + regen, wave respawns, scoreboard, killfeed, minimap, HUD; mouse + keyboard, **gamepad**,
  and **touch** controls; a **hardcore** mode.

## Run

```sh
deno task run-browser   # HTTP server + opens the browser  (127.0.0.1:8080)
deno task run-client    # same server in a native webview_deno window
deno task fetch-assets  # optional CC0 model/music packs (procedural fallback otherwise)
```

Dev: `deno task test` · `deno task lint` · `deno task fmt` · `deno task check`.

## How it works

The Deno server bundles the TypeScript client (and `three`) with esbuild and serves `/bundle.js`;
the browser only ever loads plain JS and the game runs offline once dependencies are cached. See:

- `docs/architecture.md` — module layout, the actor model, the Match loop.
- `docs/bot-ai.md` — AI internals (target selection, difficulty, A* nav).
- `docs/deno-three-setup.md` — the bundling + typing approach.
- `docs/assets-attribution.md`, `docs/balance-notes.md`.

## Controls (default)

WASD move · mouse look · LMB fire · RMB ADS · R reload · **mouse-wheel swap weapon** · **E pick up /
collect** (dropped weapons, care packages) · G lethal (double-tap for C4) · Q tactical · Z streak
wheel (hold Z + 1–3 to call one in) · Tab scoreboard · Esc pause · `` ` `` dev console.
