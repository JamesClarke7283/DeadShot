# DeadShot — Bot AI

The bot AI is three cooperating pieces in `src/characters/`: **Bot** (the actor), **BotAI** (the
per-frame brain), and **BotNavigator** (pathfinding). Bots fully simulate against each other and the
player, sharing the exact same `Weapon`, `MatchWorld`, and `DamageTarget` machinery as the human.

## Bot (`Bot.ts`)

A damageable `Actor`: health (100), a `Weapon` loadout, a `Character` for visuals/animation, a feet
position, a nav path, and kill/death tallies.

- `applyDamage` reduces health and, at ≤0, flips `alive=false`, plays the death animation, and
  records `lastDamage` (carrying `sourceId` for kill attribution).
- `stepToward(target, speed, dt, ctx)` moves the feet with collide-and-slide against the map
  (`CollisionWorld`) and clamps to ground height.
- `update` delegates thinking + actuation to `BotAI`, then selects the animation state (shoot / run
  / idle / die) and syncs the mesh transform + facing yaw.
- Move speed scales with the equipped weapon's mobility.
- `respawn(pos, yaw)` resets the bot for the Match's wave respawns.

## BotAI (`BotAI.ts`)

Difficulty tuning:

| Difficulty | Aim error | Reaction | View range |
| ---------- | --------- | -------- | ---------- |
| Recruit    | 18°       | 0.55 s   | 45 m       |
| Regular    | 9°        | 0.32 s   | 65 m       |
| Veteran    | 3°        | 0.16 s   | 85 m       |

Each frame:

1. **Target selection** (throttled to ~5×/s): pick the nearest _visible_ enemy within view range
   (threat = proximity). A new target resets the reaction timer.
2. **Visibility / LOS**: a cheap segment test against the **collision boxes**
   (`CollisionWorld.raycastBoxes`) — solid cover blocks sight. Much cheaper than mesh raycasting the
   whole map every frame, which keeps 16 bots affordable.
3. **Engage** (has target):
   - Face the enemy; build an aim direction = ideal direction perturbed by a difficulty-scaled error
     cone, re-jittered ~8×/s (this _is_ the bot's spread, so Recruits miss and Veterans don't).
   - Fire once the reaction delay has elapsed and the target is in effective range (weapon
     `range.far`), pulling the trigger so the real `Weapon` does hitscan through `MatchWorld` — bots
     therefore damage enemies (and the player) exactly as the player does, including range falloff +
     headshots.
   - **Move**: close the gap when out of range; **retreat** away from the threat when health ≤ 30;
     otherwise hold.
   - **Melee** at point-blank (≤2.2 m) on a short cooldown.
4. **Patrol** (no target): pick a random in-bounds goal, `findPath` to it via the Navigator, and
   walk the path; repath every few seconds.
5. Auto-reload when the magazine is dry.

Recoil is ignored for bots (the aim-error cone models their inaccuracy instead).

## BotNavigator (`BotNavigator.ts`)

`Navigator` runs **A\*** over the map's waypoint graph (built by `maps/Waypoints.ts`: a grid
filtered against colliders, 8-neighbour-connected where the segment is clear). It uses a binary
min-heap and a Euclidean heuristic.

- `nearest(pos)` snaps a world position to the closest waypoint.
- `findPath(start, goal, los?)` returns the world points to walk, ending at the goal; with an
  optional line-of-sight predicate it **smooths** the path, dropping intermediate nodes whose span
  is unobstructed so bots cut corners instead of marching node-to-node.

## Kill attribution

`DamageInfo` and `ShooterTag` carry a `sourceId`; `Weapon`/`Rocket`/streaks stamp it, and the victim
stores `lastDamage`. The `Match` reads `lastDamage.sourceId` on the alive→dead edge to credit the
killer on the `Scoreboard` (and the killfeed), with headshot bonuses.

## Spectated / pure bot matches

Because the player is optional, `Match` can run entirely on bots (used by the test suite to drive an
8-bot TDM to 100 kills and an FFA to a single winner). Scorestreaks auto-activate for bots via the
greedy `ScorestreakManager`, so a spectated match still produces UAVs, sentries, choppers and the
occasional nuke.

## Tuning knobs

- Difficulty table at the top of `BotAI.ts` (aim error, reaction, view range).
- `RETREAT_HEALTH`, `MELEE_RANGE`, target-reselect throttle in `BotAI.ts`.
- Waypoint `spacing` per map (`maps/*.ts`) trades nav cost vs. granularity.
