// EquipmentManager: the game-facing entry point for tacticals + lethals.
//
// Owns the EquipmentContext, a list of active Equipment, and id->factory maps.
// throwTactical/throwLethal spawn + track an instance; update() ticks all of
// them and disposes any that went inactive; detonateC4() remote-blows every
// placed C4 the player owns.

import { Equipment, type EquipmentContext, type ThrowParams } from "./Equipment.ts";
import { Throwable } from "./Throwable.ts";
import { Flashbang } from "./Flashbang.ts";
import { Smoke } from "./Smoke.ts";
import { Stun } from "./Stun.ts";
import { Snapshot } from "./Snapshot.ts";
import { Frag } from "./Frag.ts";
import { Semtex } from "./Semtex.ts";
import { ThrowingKnife } from "./ThrowingKnife.ts";
import { C4 } from "./C4.ts";
import { Molotov } from "./Molotov.ts";
import { Thermite } from "./Thermite.ts";
import { Claymore } from "./Claymore.ts";

export const TACTICAL_IDS = ["flashbang", "smoke", "stun", "snapshot"] as const;
export const LETHAL_IDS = [
  "frag",
  "semtex",
  "knife",
  "c4",
  "molotov",
  "thermite",
  "claymore",
] as const;

export type TacticalId = typeof TACTICAL_IDS[number];
export type LethalId = typeof LETHAL_IDS[number];

const TACTICAL_FACTORY: Record<TacticalId, () => Throwable> = {
  flashbang: () => new Flashbang(),
  smoke: () => new Smoke(),
  stun: () => new Stun(),
  snapshot: () => new Snapshot(),
};

const LETHAL_FACTORY: Record<LethalId, () => Throwable> = {
  frag: () => new Frag(),
  semtex: () => new Semtex(),
  knife: () => new ThrowingKnife(),
  c4: () => new C4(),
  molotov: () => new Molotov(),
  thermite: () => new Thermite(),
  claymore: () => new Claymore(),
};

export class EquipmentManager {
  private items: Equipment[] = [];

  constructor(private ctx: EquipmentContext) {}

  throwTactical(id: TacticalId, params: ThrowParams): void {
    this.spawn(TACTICAL_FACTORY[id](), params);
  }

  throwLethal(id: LethalId, params: ThrowParams): void {
    this.spawn(LETHAL_FACTORY[id](), params);
  }

  private spawn(item: Throwable, params: ThrowParams): void {
    item.throw(params.origin, params.direction, params.team, this.ctx);
    this.items.push(item);
  }

  /** Remote-detonate every placed C4. Returns true if any were detonated. */
  detonateC4(): boolean {
    let any = false;
    for (const item of this.items) {
      if (item instanceof C4 && item.active) {
        item.detonate(this.ctx);
        any = true;
      }
    }
    return any;
  }

  update(dt: number): void {
    for (let i = this.items.length - 1; i >= 0; i--) {
      const item = this.items[i];
      item.update(dt, this.ctx);
      if (!item.active) {
        item.dispose(this.ctx);
        this.items.splice(i, 1);
      }
    }
  }

  clear(): void {
    for (const item of this.items) item.dispose(this.ctx);
    this.items = [];
  }

  get count(): number {
    return this.items.length;
  }
}
