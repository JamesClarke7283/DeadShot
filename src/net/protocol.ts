// Multiplayer wire protocol (shared by the relay server + the browser client).
//
// The model is relay / client-authoritative: each client owns its own player and
// the room host additionally owns the bots. The server only routes messages
// within a room — it never simulates the game. Messages are plain JSON tagged by
// a `t` discriminator; helpers below keep (de)serialisation in one place.

import type { TeamId } from "../core/types.ts";

export type NetMode = "tdm" | "ffa" | "dom" | "ctf" | "gungame";
export type NetDifficulty = "recruit" | "regular" | "veteran";

/** Match settings chosen by the room host. */
export interface LobbySettings {
  mapId: string;
  mode: NetMode;
  botCount: number;
  difficulty: NetDifficulty;
  hardcore: boolean;
}

export interface LobbyPlayer {
  id: number;
  name: string;
  team: TeamId;
  ready: boolean;
}

/** Per-tick player transform/state broadcast to peers. */
export interface PlayerStateMsg {
  x: number;
  y: number;
  z: number;
  yaw: number;
  anim: "idle" | "run" | "shoot" | "die";
  alive: boolean;
  weaponId: string;
}

/** Per-tick host-owned bot state (one entry per bot). */
export interface BotStateMsg {
  id: number;
  x: number;
  y: number;
  z: number;
  yaw: number;
  anim: "idle" | "run" | "shoot" | "die";
  alive: boolean;
  team: TeamId;
  weaponId: string;
}

// ---- Client -> Server ----
export type ClientMsg =
  | { t: "join"; room: string; name: string }
  | { t: "ready"; ready: boolean }
  | { t: "settings"; settings: LobbySettings }
  | { t: "start" }
  | { t: "state"; s: PlayerStateMsg }
  | { t: "event"; kind: string; data?: unknown }
  | { t: "hit"; target: number; dmg: number; headshot: boolean; weaponId?: string }
  | { t: "death"; victim: number; killer?: number; weaponId?: string; headshot: boolean }
  | { t: "bots"; b: BotStateMsg[] };

// ---- Server -> Client ---- (relayed messages are tagged with the sender id)
export type ServerMsg =
  | { t: "welcome"; id: number }
  | { t: "lobby"; players: LobbyPlayer[]; hostId: number; settings: LobbySettings }
  | { t: "start"; settings: LobbySettings; seed: number; players: LobbyPlayer[] }
  | { t: "state"; from: number; s: PlayerStateMsg }
  | { t: "event"; from: number; kind: string; data?: unknown }
  | { t: "hit"; from: number; target: number; dmg: number; headshot: boolean; weaponId?: string }
  | {
    t: "death";
    from: number;
    victim: number;
    killer?: number;
    weaponId?: string;
    headshot: boolean;
  }
  | { t: "bots"; from: number; b: BotStateMsg[] }
  | { t: "peerLeft"; id: number };

export const DEFAULT_SETTINGS: LobbySettings = {
  mapId: "desert_town",
  mode: "tdm",
  botCount: 4,
  difficulty: "regular",
  hardcore: false,
};

export function encode(msg: ClientMsg | ServerMsg): string {
  return JSON.stringify(msg);
}

/** Parse a wire message; returns null on malformed input (never throws). */
export function decodeClient(raw: string): ClientMsg | null {
  try {
    const v = JSON.parse(raw);
    return v && typeof v.t === "string" ? v as ClientMsg : null;
  } catch {
    return null;
  }
}

export function decodeServer(raw: string): ServerMsg | null {
  try {
    const v = JSON.parse(raw);
    return v && typeof v.t === "string" ? v as ServerMsg : null;
  } catch {
    return null;
  }
}
