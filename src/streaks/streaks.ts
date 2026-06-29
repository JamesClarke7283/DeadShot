// Scorestreak registry.
//
// Central catalog of every scorestreak: its id, display name, score cost, and a
// factory. The ScorestreakManager / HUD read costs from here and call create()
// to instantiate a fresh streak when one is activated.

import type { StreakDef } from "./Streak.ts";
import { UAV } from "./UAV.ts";
import { CounterUAV } from "./CounterUAV.ts";
import { CarePackage } from "./CarePackage.ts";
import { SentryGun } from "./SentryGun.ts";
import { RCXD } from "./RCXD.ts";
import { PredatorMissile } from "./PredatorMissile.ts";
import { AttackHelicopter } from "./AttackHelicopter.ts";
import { StrafeRun } from "./StrafeRun.ts";
import { Gunship } from "./Gunship.ts";
import { ChopperGunner } from "./ChopperGunner.ts";
import { Juggernaut } from "./Juggernaut.ts";
import { Nuke } from "./Nuke.ts";

export const STREAKS: StreakDef[] = [
  { id: "uav", name: "UAV", cost: 500, create: () => new UAV() },
  { id: "counter_uav", name: "Counter-UAV", cost: 600, create: () => new CounterUAV() },
  { id: "care_package", name: "Care Package", cost: 700, create: () => new CarePackage() },
  { id: "sentry", name: "Sentry Gun", cost: 800, create: () => new SentryGun() },
  { id: "rcxd", name: "RC-XD", cost: 900, create: () => new RCXD() },
  { id: "predator", name: "Predator Missile", cost: 1000, create: () => new PredatorMissile() },
  {
    id: "attack_heli",
    name: "Attack Helicopter",
    cost: 1200,
    create: () => new AttackHelicopter(),
  },
  { id: "strafe_run", name: "Strafe Run", cost: 1400, create: () => new StrafeRun() },
  { id: "gunship", name: "Gunship", cost: 1600, create: () => new Gunship() },
  { id: "chopper_gunner", name: "Chopper Gunner", cost: 1800, create: () => new ChopperGunner() },
  { id: "juggernaut", name: "Juggernaut", cost: 2000, create: () => new Juggernaut() },
  { id: "nuke", name: "Tactical Nuke", cost: 3000, create: () => new Nuke() },
];

export function getStreak(id: string): StreakDef {
  const s = STREAKS.find((x) => x.id === id);
  if (!s) throw new Error(`Unknown streak: ${id}`);
  return s;
}
