// A team is a named bucket of combatant ids. TDM uses blue/red; FFA uses a
// single "ffa" team that every combatant nominally belongs to.

import type { TeamId } from "../core/types.ts";

/** Display names per team id. */
export const TEAM_NAMES: Record<TeamId, string> = {
  blue: "Blue",
  red: "Red",
  ffa: "Free-for-All",
};

export class Team {
  readonly id: TeamId;
  readonly name: string;
  readonly members: number[] = [];

  constructor(id: TeamId, name?: string) {
    this.id = id;
    this.name = name ?? TEAM_NAMES[id];
  }

  addMember(id: number): void {
    if (!this.members.includes(id)) this.members.push(id);
  }

  removeMember(id: number): void {
    const i = this.members.indexOf(id);
    if (i >= 0) this.members.splice(i, 1);
  }
}

/** Build one Team per id (deduplicated, order preserved). */
export function makeTeams(ids: TeamId[]): Team[] {
  const seen = new Set<TeamId>();
  const teams: Team[] = [];
  for (const id of ids) {
    if (seen.has(id)) continue;
    seen.add(id);
    teams.push(new Team(id));
  }
  return teams;
}
