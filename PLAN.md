# DeadShot — Implementation Plan

## Overview

**DeadShot** is a Call-of-Duty-style cartoonish FPS built with **Deno 2.9 + Three.js (r0180 via
`npm:` specifier)**, rendered in the browser via WebGL and also launchable as a native desktop
window via `webview_deno`. The game features a roster of 18 modern (21st-century) weapons with a
full Create-a-Class editor (optic / barrel / magazine / stock / grip / perk / field-upgrade + camo
color + tactical + lethal), CoD-style tacticals & lethals, a scorestreak system including care
packages and a match-ending Nuke, three hand-built maps (desert town, forest facility, urban docks)
with terrain, buildings, plants and obstacles, procedural + Quaternius-CC0 cartoon humanoid bots
with faces, a 0–16 bot slider across three AI difficulties, TDM and Free-for-All modes, CoD-core
health/respawn rules (100 HP, regen, 10-minute / 100-kill TDM), synthesized weapon SFX via WebAudio
plus local CC0 dramatic music, and localStorage persistence for classes/settings. Cartoon look =
low-poly geometry + `MeshToonMaterial` + inverted-hull outlines.

**Run targets:**

- `deno task run-browser` — starts the Deno HTTP server and opens the system browser.
- `deno task run-client` — starts the same server and opens a `webview_deno` native OS window.
- `deno task fetch-assets` — downloads Quaternius + Kenney CC0 packs + CC0 music into `/public`
  (with procedural fallback if offline).

---

## Backlog

### Phase 0 — Project Scaffolding

- [x] **0.1** Initialize Deno project + tooling — `deno.json` (tasks: `run-browser`, `run-client`,
      `fetch-assets`, `lint`, `fmt`, `test`; import map mapping `three` → `npm:three@0.180.0`,
      `three/addons/` → `npm:three@0.180.0/examples/jsm/`), `.gitignore` (`/public/models/cache`,
      `/public/audio/cache`), `tsconfig.json`.
  - Create `src/` directory
  - Create `public/index.html` (mounts `<canvas id="game">`, import-map inline)
  - Create `public/styles.css` (fullscreen canvas, no-scroll, HUD scaffolding)
  - Create `src/main.ts` entry stub that imports Three.js and renders a single test cube
  - **Verify:** `deno task run-browser` opens browser; test cube visible; `deno lint` clean.

- [x] **0.2** Create `docs/deno-three-setup.md` documenting the import-map + `npm:` specifier
      approach, the two run targets, and how `webview_deno` is fetched on first run.

### Phase 1 — Core Engine

- [x] **1.1** Build the engine core in `src/core/` — single task, all files are tightly coupled:
  - `Game.ts` — top-level orchestrator with state machine
    (`Boot / MainMenu / ClassEditor / PreMatch / Playing / PostMatch`), `requestAnimationFrame`
    loop, fixed-step accumulator for simulation.
  - `Renderer.ts` — wraps `THREE.WebGLRenderer`, enables shadow maps, ACES tone mapping, handles
    DPR + resize.
  - `Scene.ts` — owns the active `THREE.Scene`, fog, environment, map-swap logic.
  - `Camera.ts` — `PerspectiveCamera` + `PointerLockControls` wrapper, sensitivity from settings.
  - `Clock.ts` — monotonic clock + delta clamp.
  - `Input.ts` — keyboard/mouse state, key bindings (WASD, R, G, Q, Tab, Shift, Space, E, V), mouse
    button edge detection.
  - `AssetLoader.ts` — `LoadingManager` wrapper, GLTF/texture/audio preloading with progress
    callback.
  - **Verify:** boot into a lit scene with a toon-shaded cube; pointer lock engaged on click; WASD
    moves the camera; FPS counter in corner.

- [x] **1.2** Cartoon render pipeline in `src/render/` — `ToonMaterial.ts` (factory around
      `MeshToonMaterial` with a 3-step gradient ramp texture), `OutlinePass.ts` (inverted-hull
      back-face outline via `BackSide` + vertex-normal extrude), `Lighting.ts` (hemisphere +
      directional sun with cascaded shadow map). **Verify:** cube + capsule have black outlines and
      stepped shading.

### Phase 2 — Cartoon Characters (with faces)

- [x] **2.1** `src/characters/CharacterFactory.ts` — async loader that attempts to fetch Quaternius
      "Ultimate Characters" CC0 GLTF from `/public/models/quaternius/` (populated by
      `deno task fetch-assets`); on any fetch/load failure, falls back to `ProceduralHuman.build()`.
  - `ProceduralHuman.ts` — builds a humanoid from low-poly primitives (head sphere, torso/limb
    boxes, hands/feet) using `MeshToonMaterial`.
  - `Face.ts` — procedural face on the head: eyes (white sphere + black pupil), cartoon nose, mouth
    (curved torus or texture decal), eyebrows; team-tinted headband.
  - Team color material swap (Blue vs Red) on torso.
  - `SkeletonUtils.clone` for cheap bot instancing.
  - **Verify:** spawn one bot per team in the test scene; both have visible faces; reloading with no
    network falls back to procedural without errors.

- [x] **2.2** `docs/assets-attribution.md` listing Quaternius (CC0) + Kenney (CC0) packs, music
      tracks + licenses, and the procedural fallback guarantee.

### Phase 3 — Weapons

- [x] **3.1** `src/weapons/WeaponDefinition.ts` — typed data table for all 18 weapons across 7
      categories with per-weapon stats (damage, fireRate, magazine, reserve, reloadTime,
      recoilPattern, ADS time, range falloff, mobility, pellets for shotguns, rocket for RPG):
  - Assault: M4, AK-12, SCAR-L
  - SMG: MP5, P90, UZI
  - LMG: M249, RPK
  - Marksman/Sniper: MK14, Barrett .50, Kar98
  - Shotgun: SPAS-12, KSG
  - Pistol: M9, Deagle
  - Launcher: RPG-7 (Primary launcher slot)
  - **Verify:** `deno test --check` data-table unit test (every weapon has all required stats;
    magazine > 0; damage > 0).

- [x] **3.2** `src/weapons/AttachmentDefinitions.ts` — optic / barrel / magazine / stock / grip /
      perk / field-upgrade categories with per-attachment stat modifiers (e.g. Red Dot: +ADS, 0
      damage; Ext Mag: +magazine, -mobility; Compensator: -recoil, -range; Dead Silence field
      upgrade, Trophy field upgrade, etc.). Includes camo color palette. **Verify:** unit test that
      a fully-kitted class produces deterministic final stats.

- [x] **3.3** `src/weapons/Weapon.ts` + `Recoil.ts` + `WeaponViewmodel.ts` — runtime weapon
      instance:
  - `Weapon.ts` — state machine (`Ready / Firing / Reloading / Swapping / Empty`), applies
    attachments to base stats, raycast hitscan for bullets, projectile spawn for RPG.
  - `Recoil.ts` — recoil pattern (per-shot camera kick + recovery curve), attachments modify.
  - `WeaponViewmodel.ts` — first-person arms + weapon mesh (low-poly viewmodel per category), ADS
    lerp, reload animation via mixer, muzzle flash sprite, shell ejection.
  - **Verify:** equip M4, hold LMB → auto-fire raycast leaves bullet holes on test wall; press R →
    reload anim plays; equip RPG → rocket projectile travels and explodes on impact.

- [x] **3.4** `src/weapons/Projectile.ts` + `Rocket.ts` — projectile pool with gravity + collision;
      `Rocket.ts` adds thrust + splash damage radius + explosion VFX. **Verify:** RPG rocket
      destroys test cubes within splash radius.

### Phase 4 — Tacticals & Lethals

- [x] **4.1** `src/tacticals/` (one task, all grenade-like items share the throw + timer base
      class):
  - `Throwable.ts` base (arc physics, cook timer, team check).
  - Tacticals: `Flashbang.ts` (screen white + audio deafen), `Smoke.ts` (particle cloud blocker),
    `Stun.ts` (slow + blur), `Snapshot.ts` (radar ping of enemies in radius).
  - Lethals: `Frag.ts` (cook + explosion), `Semtex.ts` (sticky + beep), `ThrowingKnife.ts` (instant
    lethal on hit, recoverable), `C4.ts` (place + remote detonate), `Molotov.ts` (fire pool DoT),
    `Thermite.ts` (burns through surfaces, area denial), `Claymore.ts` (directional trip laser).
  - **Verify:** each item throws on G (lethal) / Q (tactical); frag explodes; flashbang whites the
    screen; smoke blocks vision; C4 detonates on double-tap G; claymore trips on bot walking through
    laser.

### Phase 5 — Maps

- [x] **5.1** `src/maps/Terrain.ts` + `Building.ts` + `Foliage.ts` + `Obstacle.ts` — shared geometry
      builders (heightmap terrain with toon material, modular buildings from boxes with
      windows/doors, instanced foliage for plants/grass, crates/cars/barriers as obstacles). All
      collidable via a merged BVH. **Verify:** walk a test layout; collisions stop the player;
      plants sway via vertex shader.

- [x] **5.2** `src/maps/MapDefinition.ts` interface + `DesertTown.ts` — flat sandy terrain, adobe
      buildings, market stalls, palm trees, central mosque dome, long sightlines + alley CQB.
      Includes spawn points + waypoint graph for bot nav. **Verify:** load map, traverse, no
      fall-through, sniper perches accessible.

- [x] **5.3** `src/maps/ForestFacility.ts` — rolling heightmap terrain, pine/eucalyptus instanced
      foliage, concrete bunker buildings, radar dish, fog density, medium-range firefights.
      **Verify:** heightmap walkable slopes only; bots navigate the waypoint graph.

- [x] **5.4** `src/maps/UrbanDocks.ts` — waterfront with shipping containers (stackable cover),
      cranes, warehouses, docked boat, vegetation planters, tight CQB. **Verify:** containers form
      valid cover lanes; containers stack via collision.

### Phase 6 — Bots & AI

- [x] **6.1** `src/characters/Bot.ts` + `BotNavigator.ts` — bot actor with health, loadout,
      inventory, animation mixer (idle / run / shoot / die); `BotNavigator` walks the map's waypoint
      graph using A* with line-of-sight shortcuts. **Verify:** spawn 1 bot, order it to a waypoint,
      it pathfinds around a wall.

- [x] **6.2** `src/characters/BotAI.ts` — target selection (nearest visible enemy + threat
      weighting), aim error tuned by difficulty (`Recruit` 18° / `Regular` 9° / `Veteran` 3°),
      reaction time, suppressive fire, grenade usage, retreat-on-low-health, melee on close range.
      Bots fully simulate vs. each other when player spectates or in pure bot-vs-bot mode.
      **Verify:** 6v6 bot match with player spectating produces kills on the scoreboard.

### Phase 7 — Match, Teams, Modes

- [x] **7.1** `src/game/Match.ts` + `Team.ts` + `Spawner.ts` + `Scoreboard.ts` (single task, match
      plumbing is one cohesive unit):
  - `Match.ts` — match lifecycle (warmup → live → end), 10-minute timer, score cap (100 kills TDM),
    per-mode rules injection, killfeed events, score-per-action (kill +100, headshot +25, assist
    +50, streaks scored separately).
  - `Team.ts` — team roster, score, spawn rotation.
  - `Spawner.ts` — wave-based spawn point selection with enemy-proximity avoidance.
  - `Scoreboard.ts` — per-player K/D/score, per-team score, persists to match end.
  - **Verify:** 8v8 TDM runs to either 100 kills or 10 min, awards a winner, prints final
    scoreboard.

- [x] **7.2** `src/game/TDM.ts` + `src/game/FFA.ts` — mode rules (TDM: two teams, shared team score,
      friendly fire off; FFA: everyone-vs-everyone, 100-kill cap, no teams). 100 HP, regen after 5 s
      out-of-damage, 3–5 s respawn delay. **Verify:** FFA match with 8 bots produces a single winner
      at 100 kills.

### Phase 8 — Scorestreaks

- [x] **8.1** `src/streaks/ScorestreakManager.ts` — score tracker per player, streak unlock
      thresholds, streak-selection UI hook, in-progress streak limiting. **Verify:** bot reaching
      500 score unlocks a UAV slot.

- [x] **8.2** `src/streaks/CarePackage.ts` + `UAV.ts` + `CounterUAV.ts` — care package (crate falls
      from sky at marked location, captured by walking over, grants random streak), UAV (6 s radar
      sweep of enemies on minimap), Counter-UAV (disable enemy minimap). **Verify:** call in care
      package, walk over crate, receive random streak; UAV pings enemies on HUD minimap.

- [x] **8.3** `src/streaks/AttackHelicopter.ts` + `Gunship.ts` + `ChopperGunner.ts` +
      `PredatorMissile.ts` + `StrafeRun.ts` — air streaks (AI-piloted heli that circles + shoots;
      player-controlled gunship camera; predator missile player-steers into ground; strafe run = 3
      jets across the map). **Verify:** each streak spawns, attacks enemies, expires on timer or
      ammo.

- [x] **8.4** `src/streaks/SentryGun.ts` + `RCXD.ts` + `Juggernaut.ts` + `Nuke.ts` — ground streaks:
      deployable auto-aiming sentry, RC car player-driven, Juggernaut loadout swap (heavy armor +
      LMG), Nuke (highest cost, **instant match-end + pulling team wins** per your spec).
      **Verify:** earn nuke via console cheat, call it, match ends with winning team banner.

### Phase 9 — Class Editor & Persistence

- [x] **9.1** `src/persistence/Storage.ts` — typed localStorage wrapper (10 custom classes,
      settings, last match config) with schema versioning + migration. **Verify:** round-trip a
      class through save/load; bump schema version migrates cleanly.

- [ ] **9.2** `src/ui/ClassEditor.ts` — full Create-a-Class screen:
  - 10 class slots (CoD default count).
  - Primary picker (18 weapons), Secondary picker (18 weapons).
  - Attachment slots per weapon (Optic / Barrel / Magazine / Stock / Grip / Perk) with stat deltas
    shown live.
  - Tactical picker (4), Lethal picker (7).
  - Field Upgrade picker (Dead Silence / Trophy / others).
  - Perk package picker (3 perks: blue / red / gold).
  - Camo color picker applied to viewmodel.
  - Live stat bar (mobility / range / accuracy / damage / control).
  - **Verify:** build a class, return to main menu, re-enter editor — selections persisted; camo
    color shows on viewmodel preview.

### Phase 10 — UI / HUD / Menus

- [ ] **10.1** `src/ui/MainMenu.ts` + `PreMatchMenu.ts` — main menu (Play / Create-a-Class / Options
      / Quit) + pre-match menu (map picker across 3 maps, mode picker TDM/FFA, bot count slider
      0–16, bot difficulty radio, class slot selection, start match). **Verify:** configure a 6v6
      Recruit TDM on DesertTown, click start, match loads.

- [ ] **10.2** `src/ui/HUD.ts` + `Crosshair.ts` + `HitMarker.ts` + `DamageIndicator.ts` +
      `Killfeed.ts` + `ScoreboardUI.ts` (single task, all HUD widgets share the HUD root):
  - `HUD.ts` — health bar, ammo counter, weapon name, minimap (top-down map render with player
    arrow + visible enemies + UAV pings), scoreline, timer, killstreak progress.
  - `Crosshair.ts` — dynamic spread based on movement + firing.
  - `HitMarker.ts` — X marker on hit, headshot sound + red marker.
  - `DamageIndicator.ts` — directional arcs pointing to damage source, fade out.
  - `Killfeed.ts` — scrolling `Killer ▸ weapon ▸ Victim` lines.
  - `ScoreboardUI.ts` — Tab overlay with per-player stats.
  - `StreakMenu.ts` — hold-Z to bring up streak wheel.
  - **Verify:** take damage → indicator points at attacker; kill a bot → killfeed updates; Tab shows
    scoreboard; minimap updates positions.

### Phase 11 — Audio

- [ ] **11.1** `src/audio/AudioManager.ts` + `Synth.ts` + `WeaponSFX.ts` + `SpatialSFX.ts` (single
      task, audio engine is one cohesive unit):
  - `AudioManager.ts` — single `AudioListener` on the camera, master / SFX / music volume buses from
    settings.
  - `Synth.ts` — WebAudio node graph synthesizers for per-weapon gunfire (noise burst + lowpass +
    distortion tuned per category), reload clicks, footsteps, grenade pins, explosions, hit markers,
    UI clicks.
  - `WeaponSFX.ts` — maps each weapon id → synth params.
  - `SpatialSFX.ts` — `PositionalAudio` wrapper for enemy gunfire / explosions / footsteps.
  - **Verify:** fire each weapon → distinct sound; enemy bot firing behind player → sound comes from
    behind; reload plays clicks.

- [ ] **11.2** `src/audio/MusicPlayer.ts` + `deno task fetch-assets` extension — download 2–3 CC0
      dramatic tracks (Incompetech / FMA) into `/public/audio/music/`; `MusicPlayer` crossfades
      between tracks, ducks during low-health, intensifies during streaks. **Verify:**
      `deno task fetch-assets` populates the folder; music loops in-match; low-health ducks volume.

### Phase 12 — Desktop Client

- [ ] **12.1** `src/server/server.ts` — Deno HTTP server (`Deno.serve`) on configurable port serving
      `/public` with correct MIME types + import-map-aware HTML. **Verify:** `deno task run-browser`
      starts server, opens `http://localhost:<port>` in default browser, game boots.

- [ ] **12.2** `src/server/desktop.ts` — `webview_deno` launcher: starts the HTTP server in a
      worker, opens a native OS window pointing at the same URL, sets window title `DeadShot`,
      1280×720 default, fullscreen toggle via F11. Wire `deno task run-client`. **Verify:**
      `deno task run-client` opens a native desktop window running the game identically to the
      browser.

### Phase 13 — Polish & Manual Verification

- [MANUAL] **13.1** Playtest balance pass — tune bot aim error, weapon damage falloff, streak costs,
  respawn timing across 3 matches; record findings in `docs/balance-notes.md`.

- [MANUAL] **13.2** Per-map visual QA — walk each map, verify no fall-through geometry, no
  z-fighting, foliage renders at distance, lighting stays cartoonish.

- [MANUAL] **13.3** Desktop client QA on Linux — confirm `webview_deno` window opens, pointer lock
  works inside it, audio plays.

- [ ] **13.4** `docs/bot-ai.md` + `docs/architecture.md` — write developer docs covering AI
      internals, ECS-ish layout, and the run-browser vs run-client split.

### Phase 14 — Stretch Goals (deferred; listed for visibility, not in critical path)

- [ ] **14.1** Hardcore mode toggle (30 HP, fast TTK, no HUD) in Pre-Match menu.
- [ ] **14.2** Touch controls for mobile browsers (on-screen joysticks + fire buttons).
- [ ] **14.3** Gamepad support via Gamepad API (Xbox-style mapping).
- [ ] **14.4** Additional streaks beyond the core 12 if playtest demands.
- [ ] **14.5** Additional maps / community map loader.

---

## Testing Notes

- **Unit tests (Deno test):** weapon data table integrity (`src/weapons/WeaponDefinition.test.ts`),
  attachment stat math (`AttachmentDefinitions.test.ts`), Storage round-trip + migration
  (`persistence/Storage.test.ts`), BotNavigator A* on a synthetic graph
  (`characters/BotNavigator.test.ts`).
- **Run targets:** `deno task run-browser` (server + browser), `deno task run-client` (server +
  native window), `deno task fetch-assets` (CC0 download).
- **Manual verification per phase:** each task above lists a `Verify:` step. Use the in-game
  developer console (left-tilde) added in Phase 10 to spawn bots, switch maps, and grant streaks for
  testing.
- **Lint/format:** `deno lint` + `deno fmt --check` must be clean before each commit.
- **Browser QA:** latest Chrome + Firefox; verify WebGL2 + WebAudio + Pointer Lock + localStorage.
- **Desktop QA:** Linux WebKitGTK via `webview_deno`; confirm pointer lock works inside the webview
  (workaround may be needed — document in `docs/deno-three-setup.md`).

---

## File Change Summary

| Path                                                                                                                                                             | Action  | Purpose                                                  |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | -------------------------------------------------------- |
| `deno.json`                                                                                                                                                      | Create  | Tasks, import map (`npm:three@0.180.0`), lint/fmt config |
| `tsconfig.json`                                                                                                                                                  | Create  | Strict TS config for Deno                                |
| `.gitignore`                                                                                                                                                     | Create  | Ignore asset caches, build artifacts                     |
| `public/index.html`                                                                                                                                              | Create  | Canvas mount + import map                                |
| `public/styles.css`                                                                                                                                              | Create  | Fullscreen canvas, HUD layout                            |
| `src/main.ts`                                                                                                                                                    | Create  | Entry point, bootstraps `Game`                           |
| `src/core/{Game,Renderer,Scene,Camera,Clock,Input,AssetLoader}.ts`                                                                                               | Create  | Engine core                                              |
| `src/render/{ToonMaterial,OutlinePass,Lighting}.ts`                                                                                                              | Create  | Cartoon render pipeline                                  |
| `src/characters/{CharacterFactory,ProceduralHuman,Face,Bot,BotAI,BotNavigator}.ts`                                                                               | Create  | Characters + bot AI                                      |
| `src/weapons/{WeaponDefinition,AttachmentDefinitions,Weapon,Recoil,WeaponViewmodel,Projectile,Rocket}.test.ts`                                                   | Create  | Weapons + tests                                          |
| `src/tacticals/{Throwable,Flashbang,Smoke,Stun,Snapshot,Frag,Semtex,ThrowingKnife,C4,Molotov,Thermite,Claymore}.ts`                                              | Create  | Tacticals & lethals                                      |
| `src/maps/{MapDefinition,Terrain,Building,Foliage,Obstacle,DesertTown,ForestFacility,UrbanDocks}.ts`                                                             | Create  | Maps                                                     |
| `src/game/{Match,Team,Spawner,Scoreboard,TDM,FFA}.ts`                                                                                                            | Create  | Match + modes                                            |
| `src/streaks/{ScorestreakManager,CarePackage,UAV,CounterUAV,AttackHelicopter,Gunship,ChopperGunner,PredatorMissile,StrafeRun,SentryGun,RCXD,Juggernaut,Nuke}.ts` | Create  | Scorestreaks                                             |
| `src/ui/{MainMenu,PreMatchMenu,ClassEditor,HUD,Crosshair,HitMarker,DamageIndicator,Killfeed,ScoreboardUI,StreakMenu}.ts`                                         | Create  | UI                                                       |
| `src/audio/{AudioManager,Synth,WeaponSFX,SpatialSFX,MusicPlayer}.ts`                                                                                             | Create  | Audio                                                    |
| `src/persistence/Storage.test.ts`                                                                                                                                | Create  | Storage + tests                                          |
| `src/server/{server,desktop}.ts`                                                                                                                                 | Create  | Deno HTTP server + webview_deno launcher                 |
| `public/models/quaternius/`                                                                                                                                      | Fetched | Quaternius CC0 character pack                            |
| `public/models/kenney/`                                                                                                                                          | Fetched | Kenney CC0 props                                         |
| `public/audio/music/`                                                                                                                                            | Fetched | CC0 dramatic music tracks                                |
| `docs/{deno-three-setup,assets-attribution,bot-ai,architecture,balance-notes}.md`                                                                                | Create  | Developer docs                                           |

---

**Total:** 14 phases, ~38 automatable tasks, 3 `[MANUAL]` QA tasks, 5 stretch tasks. Each
automatable task is one commit boundary.
