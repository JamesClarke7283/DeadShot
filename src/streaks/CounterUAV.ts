// Counter-UAV scorestreak.
//
// Suppresses the enemy team's minimap for its duration. On the first tick it
// tells the Match to jam the opposing team, then it just runs out the clock.

import { Streak, type StreakContext } from "./Streak.ts";
import type { TeamId } from "../core/types.ts";

const DURATION = 30;

/** The team a Counter-UAV jams, given its owner's team. */
function enemyTeamOf(team: TeamId): TeamId {
  if (team === "blue") return "red";
  if (team === "red") return "blue";
  return "ffa";
}

export class CounterUAV extends Streak {
  readonly id = "counter_uav";
  readonly name = "Counter-UAV";

  private elapsed = 0;
  private engaged = false;

  override update(dt: number, ctx: StreakContext): void {
    if (!this.active) return;

    if (!this.engaged) {
      this.engaged = true;
      ctx.setCounterUAV(enemyTeamOf(ctx.owner.team), DURATION);
    }

    this.elapsed += dt;
    if (this.elapsed >= DURATION) this.active = false;
  }
}
