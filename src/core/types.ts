// Cross-cutting shared types and constants used across subsystems.

/** Faction a player/bot belongs to. FFA = everyone is their own team. */
export type TeamId = "blue" | "red" | "ffa";

/** Primary team accent colors (used for uniforms, HUD, headbands). */
export const TEAM_COLORS: Record<TeamId, number> = {
  blue: 0x3a86ff,
  red: 0xff4d4d,
  ffa: 0x9b5de5,
};

/** A palette of distinct accents for FFA players. */
export const FFA_PALETTE: number[] = [
  0x9b5de5,
  0xf15bb5,
  0x00bbf9,
  0x00f5d4,
  0xfee440,
  0xff7b00,
  0x06d6a0,
  0xef476f,
  0x118ab2,
  0xffd166,
  0x8338ec,
  0x3a86ff,
  0xfb5607,
  0x2ec4b6,
  0xe71d36,
  0x8ac926,
];

export function teamColor(team: TeamId, index = 0): number {
  if (team === "ffa") return FFA_PALETTE[index % FFA_PALETTE.length];
  return TEAM_COLORS[team];
}
