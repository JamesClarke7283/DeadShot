# DeadShot — Architecture

A Call-of-Duty-style cartoon FPS in Deno + Three.js (r180), playable in the
browser and as a native desktop window, with a procedural-first asset policy.

## Layering (engine → features → orchestration)

```
src/
  main.ts            Bootstraps Game.
  three.ts           Typed barrel re-export of three (@types/three via @ts-types).
  vendor/*.ts        Typed barrels for three addons (PointerLockControls, GLTFLoader, SkeletonUtils).

  core/              Engine: Game (state machine + fixed-step loop), Renderer,
                     Scene, Camera (PointerLockControls), Input (action bindings),
                     Clock, AssetLoader, types (TeamId / colors).
  render/            Cartoon pipeline: ToonMaterial (gradient ramp), OutlinePass
                     (inverted-hull), Lighting (hemi + shadow sun), VFX
                     (impacts/tracers/explosions), ScreenEffects (flash/blur/tint).

  characters/        Character (interface), ProceduralHuman + Face (fallback),
                     CharacterFactory (GLTF probe -> procedural), Bot (actor),
                     BotAI (brain), BotNavigator (A*).
  weapons/           WeaponDefinition (18-gun table), AttachmentDefinitions
                     (+ computeWeaponStats), Weapon (runtime FSM), Recoil,
                     WeaponViewmodel, Projectile + Rocket, combat.ts (contracts).
  tacticals/         Equipment + Throwable base, 11 tacticals/lethals,
                     EquipmentManager.
  maps/              Terrain/Building/Foliage/Obstacle builders, Collision
                     (AABB + heightfield), Waypoints (nav graph), MapDefinition,
                     DesertTown/ForestFacility/UrbanDocks, maps registry.
  streaks/           Streak + StreakContext, ScorestreakManager, 12 streaks,
                     registry.
  game/              Mode (TDM/FFA rules), Scoreboard, Team, Spawner, MatchWorld
                     (WorldQuery), Player (human actor), Match (orchestrator),
                     Perks.
  persistence/       Storage (localStorage classes/settings/match config + migration).
  ui/                dom helper, MainMenu, PreMatchMenu, ClassEditor, HUD +
                     widgets (Crosshair/HitMarker/DamageIndicator/Killfeed/
                     ScoreboardUI/StreakMenu), DevConsole.
  audio/             AudioManager, Synth, WeaponSFX, SpatialSFX, MusicPlayer.
  server/            server.ts (HTTP + esbuild bundling), desktop.ts (webview).
  tools/             fetch_assets.ts.
```

## "ECS-ish" actor model

There is no formal ECS; instead a thin **Actor** interface (`characters/Bot.ts`)
unifies the player and bots:

```ts
interface Actor extends DamageTarget {
  id; team; isPlayer; alive;
  position(out); eyePosition(out); isHead(obj); applyDamage(info);
}
```

`DamageTarget` (`weapons/combat.ts`) is the damage contract; `WorldQuery` is the
spatial contract (raycast + radiusTargets + rocket spawn). Weapons, projectiles,
streaks and grenades all operate through these interfaces, so they don't care
whether they hit a bot, the player, or a destructible — and the same Weapon code
runs for the player and every bot.

## The Match loop (`game/Match.ts`)

`Match` is the live-game orchestrator and the implementation of `MatchWorld`'s
data source, `StreakContext`, and the equipment context. Each frame it:

1. ticks VFX, the projectile pool, screen effects, the player's equipment;
2. updates the player (input-driven) and every bot (BotAI);
3. detects deaths (alive→dead edge) and attributes kills to the `Scoreboard`
   (+ killfeed) via `DamageInfo.sourceId`;
4. respawns the dead through the `Spawner` (enemy-proximity avoidance);
5. ticks active scorestreaks (UAV pings, sentries, nuke…) and lets bots auto-use
   their best available streak;
6. checks the mode's win condition (score cap / time limit).

It runs **headless with no player** for pure bot-vs-bot matches (and tests).

## Hit detection

- `MatchWorld.raycast` tests **map geometry** with a `THREE.Raycaster` and
  **actors analytically** as a body sphere + a head sphere (headshots), skipping
  hits within ~0.6 m of the muzzle (self-fire protection).
- Bot line-of-sight uses the cheap `CollisionWorld.raycastBoxes` (solid cover),
  not full mesh raycasts, and is throttled — so 16 bots stay cheap.

## Rendering / cartoon look

Low-poly primitive geometry + `MeshToonMaterial` with a shared 3-step gradient
ramp + inverted-hull back-face outlines + a hemisphere/sun rig with a
texel-snapped follow shadow. VFX and the HUD are unlit/DOM so they pop.

## Persistence

`persistence/Storage.ts` is a typed `localStorage` wrapper (10 classes, settings,
last match config) with a schema version + forward migration and a pluggable
backend (in-memory for headless tests).

## run-browser vs run-client

Both targets share `server/server.ts`, which **bundles the TypeScript client with
esbuild** (`@luca/esbuild-deno-loader`, resolving the `three` import map + npm
cache) and serves it at `/bundle.js`; the browser only ever loads plain JS and
the app runs offline once deps are cached.

- **`deno task run-browser`** → server + opens the system browser.
- **`deno task run-client`** → server + a `webview_deno` (WebKitGTK) native
  window via `server/desktop.ts` (title "DeadShot", 1280×720, F11 fullscreen).

See `docs/deno-three-setup.md` for the bundling/typing details and
`docs/bot-ai.md` for the AI internals.

## Testing

`deno test -A` — 90+ unit tests: weapon/attachment data + stat math, Weapon FSM,
projectile/rocket splash, throwable behavior, scorestreak manager + entities,
BotNavigator A*, bot-vs-bot kills, map integrity + nav graphs, scoreboard/modes,
full Match runs (TDM to a winner, FFA single winner, respawns, streaks/nuke),
and Storage round-trip + migration.
