// Map registry: the three hand-built maps, looked up by id by the pre-match menu
// and Match.

import type { MapDefinition } from "./MapDefinition.ts";
import { DesertTown } from "./DesertTown.ts";
import { ForestFacility } from "./ForestFacility.ts";
import { UrbanDocks } from "./UrbanDocks.ts";

export const MAPS: MapDefinition[] = [DesertTown, ForestFacility, UrbanDocks];

export function getMap(id: string): MapDefinition {
  const m = MAPS.find((x) => x.id === id);
  if (!m) throw new Error(`Unknown map id: ${id}`);
  return m;
}

/** Register a (community / loaded) map at runtime; replaces an existing id. */
export function registerMap(def: MapDefinition): void {
  const i = MAPS.findIndex((m) => m.id === def.id);
  if (i >= 0) MAPS[i] = def;
  else MAPS.push(def);
}

export { DesertTown, ForestFacility, UrbanDocks };
