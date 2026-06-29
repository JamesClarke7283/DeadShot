// Map registry: the three hand-built maps, looked up by id by the pre-match menu
// and Match.

import type { MapDefinition } from "./MapDefinition.ts";
import { DesertTown } from "./DesertTown.ts";
import { ForestFacility } from "./ForestFacility.ts";
import { UrbanDocks } from "./UrbanDocks.ts";

export const MAPS: readonly MapDefinition[] = [DesertTown, ForestFacility, UrbanDocks];

export function getMap(id: string): MapDefinition {
  const m = MAPS.find((x) => x.id === id);
  if (!m) throw new Error(`Unknown map id: ${id}`);
  return m;
}

export { DesertTown, ForestFacility, UrbanDocks };
