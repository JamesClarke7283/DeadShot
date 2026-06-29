// Gunship scorestreak.
//
// A tougher, longer-lasting AI gunship that circles slower and hits harder than
// the Attack Helicopter. Player camera control is out of scope; it flies itself.

import { CirclingGunship, type GunshipConfig } from "./AttackHelicopter.ts";

export class Gunship extends CirclingGunship {
  readonly id = "gunship";
  readonly name = "Gunship";

  protected config(): GunshipConfig {
    return {
      lifetime: 35,
      altitude: 30,
      radius: 22,
      angularSpeed: 0.35,
      fireInterval: 0.4,
      damage: 40,
      targetsPerCycle: 1,
      tint: 0x2a2a3a,
    };
  }
}
