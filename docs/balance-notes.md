# DeadShot — Balance Notes

Initial tuning values and rationale. These were set during implementation and should be **validated
by a human playtest** (task 13.1: 3 matches across the three maps); treat the numbers below as the
starting point to iterate from.

## Weapons (see `src/weapons/WeaponDefinition.ts`)

Approximate body-shot TTK at near range (ms) = `ceil(100 / damage) * (60000 / fireRate)`:

| Class    | Example | Dmg                          | RPM       | ~Shots to kill   | Feel                     |
| -------- | ------- | ---------------------------- | --------- | ---------------- | ------------------------ |
| Assault  | M4      | 33                           | 750       | 4                | all-round                |
| Assault  | AK-12   | 38                           | 650       | 3                | harder hits, more recoil |
| SMG      | MP5     | 28                           | 800       | 4                | fast, short range        |
| SMG      | Vector  | 22                           | 1100      | 5                | shreds up close          |
| LMG      | RPK     | 36                           | 600       | 3                | strong, low mobility     |
| Marksman | MK14    | 55                           | 380       | 2                | semi DMR                 |
| Sniper   | Barrett | 110                          | 55        | 1                | one-shot torso           |
| Sniper   | Kar98   | 95                           | 45 (bolt) | 1 head / ~1 body | classic bolt             |
| Shotgun  | SPAS-12 | 26×8                         | 70        | 1 in-face        | CQB only                 |
| Pistol   | Deagle  | 60                           | 320       | 2                | hand-cannon              |
| Launcher | RPG-7   | 150 direct / 120 splash (r6) | —         | 1                | anti-group               |

Range falloff: SMGs fall off ~12–28 m, ARs ~32–66 m, snipers effectively unlimited. Headshot
multipliers: 1.4–1.5 (auto), 1.5–1.6 (pistols/marksman), 2.2–2.5 (snipers, i.e. guaranteed one-shot
to the head).

**Watch in playtest:** Vector/UZI may over-perform in CQB maps (UrbanDocks); Barrett quickscoping;
SPAS one-shot range.

## Bot AI (see `src/characters/BotAI.ts`)

| Difficulty | Aim error | Reaction | View range |
| ---------- | --------- | -------- | ---------- |
| Recruit    | 18°       | 0.55 s   | 45 m       |
| Regular    | 9°        | 0.32 s   | 65 m       |
| Veteran    | 3°        | 0.16 s   | 85 m       |

Veteran is intentionally lethal at range; if it feels unfair, raise aim error to 4–5° or reaction to
~0.2 s. Recruit should feel forgiving for new players.

## Scorestreaks (see `src/streaks/streaks.ts`)

Costs (streak score; kill = 100, +25 headshot): UAV 500, Counter-UAV 600, Care Package 700, Sentry
800, RC-XD 900, Predator 1000, Attack Heli 1200, Strafe Run 1400, Gunship 1600, Chopper Gunner 1800,
Juggernaut 2000, Nuke 3000.

**Watch:** Nuke at 3000 (~30 kills) ends the match instantly — confirm it feels earned, not cheap;
consider 3500–4000 if it lands too often vs. Veteran bots.

## Match rules (see `src/game/`)

- 100 HP, regen after 5 s out of damage at 35 HP/s (`Player`).
- Respawn delay 4 s (wave-based, enemy-proximity-avoiding `Spawner`).
- TDM: 100-kill team cap or 10-min timer; FFA: 100-kill single-player cap.
- Hardcore (stretch): 30 HP, no regen, no HUD.

**Watch in playtest:** respawn safety on small maps (UrbanDocks); whether 35 HP/s regen is too
forgiving (drop to ~25 for a slower CoD-core feel).

## How to iterate

All values are plain data tables — edit `WeaponDefinition.ts`, `BotAI.ts` (DIFFICULTY), and
`streaks.ts` (costs), then re-run `deno task test` to confirm the data-integrity tests still pass.
