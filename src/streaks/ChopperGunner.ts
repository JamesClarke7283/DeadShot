// Chopper Gunner scorestreak.
//
// The top-tier AI gunship: very high damage and it engages several enemies per
// fire cycle. Player gunner control is out of scope; it flies and fires itself.

import { CirclingGunship, type GunshipConfig } from "./AttackHelicopter.ts";

export class ChopperGunner extends CirclingGunship {
  readonly id = "chopper_gunner";
  readonly name = "Chopper Gunner";

  protected config(): GunshipConfig {
    return {
      lifetime: 35,
      altitude: 28,
      radius: 20,
      angularSpeed: 0.4,
      fireInterval: 0.35,
      damage: 50,
      targetsPerCycle: 3,
      tint: 0x101015,
    };
  }
}
