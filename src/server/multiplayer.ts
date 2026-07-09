// Multiplayer relay server.
//
// A RoomManager owns named rooms; each WebSocket that joins a room is assigned a
// stable id and a team. The server relays in-match traffic (player/bot state,
// hits, deaths) to the rest of the room and keeps a lobby roster in sync. It does
// NOT simulate the game — the clients are authoritative (the host owns the bots).
// See ../net/protocol.ts for the message shapes.

import {
  type ClientMsg,
  decodeClient,
  DEFAULT_SETTINGS,
  encode,
  type LobbyPlayer,
  type LobbySettings,
  type ServerMsg,
} from "../net/protocol.ts";
import type { TeamId } from "../core/types.ts";

interface Conn {
  id: number;
  ws: WebSocket;
  name: string;
  team: TeamId;
  ready: boolean;
  roomId: string;
}

interface Room {
  id: string;
  conns: Map<number, Conn>;
  hostId: number;
  settings: LobbySettings;
}

export class RoomManager {
  private rooms = new Map<string, Room>();
  private nextId = 1;

  /** Wire up a freshly-upgraded socket. */
  accept(ws: WebSocket): void {
    let conn: Conn | null = null;
    ws.onmessage = (ev: MessageEvent) => {
      const msg = decodeClient(typeof ev.data === "string" ? ev.data : "");
      if (!msg) return;
      if (msg.t === "join") {
        if (!conn) conn = this.join(ws, msg.room, msg.name);
        return;
      }
      if (conn) this.handle(conn, msg);
    };
    const close = () => {
      if (conn) {
        this.leave(conn);
        conn = null;
      }
    };
    ws.onclose = close;
    ws.onerror = close;
  }

  /** Diagnostics: number of live rooms. */
  get roomCount(): number {
    return this.rooms.size;
  }

  private join(ws: WebSocket, roomId: string, name: string): Conn {
    let room = this.rooms.get(roomId);
    if (!room) {
      room = { id: roomId, conns: new Map(), hostId: -1, settings: { ...DEFAULT_SETTINGS } };
      this.rooms.set(roomId, room);
    }
    const id = this.nextId++;
    const conn: Conn = {
      id,
      ws,
      name: name?.slice(0, 24) || `Player ${id}`,
      team: "blue",
      ready: false,
      roomId,
    };
    room.conns.set(id, conn);
    if (room.hostId < 0) room.hostId = id;
    this.recomputeTeams(room);
    this.send(ws, { t: "welcome", id });
    this.broadcastLobby(room);
    return conn;
  }

  private handle(conn: Conn, msg: ClientMsg): void {
    const room = this.rooms.get(conn.roomId);
    if (!room) return;
    switch (msg.t) {
      case "ready":
        conn.ready = msg.ready;
        this.broadcastLobby(room);
        break;
      case "settings":
        if (conn.id === room.hostId) {
          room.settings = sanitizeSettings(msg.settings);
          this.recomputeTeams(room);
          this.broadcastLobby(room);
        }
        break;
      case "start":
        if (conn.id === room.hostId) {
          this.broadcast(room, {
            t: "start",
            settings: room.settings,
            seed: (Math.random() * 1e9) | 0,
            players: this.roster(room),
          });
        }
        break;
      case "state":
        this.relay(room, conn.id, { t: "state", from: conn.id, s: msg.s });
        break;
      case "event":
        this.relay(room, conn.id, { t: "event", from: conn.id, kind: msg.kind, data: msg.data });
        break;
      case "hit":
        this.relay(room, conn.id, {
          t: "hit",
          from: conn.id,
          target: msg.target,
          dmg: msg.dmg,
          headshot: msg.headshot,
          weaponId: msg.weaponId,
        });
        break;
      case "death":
        this.relay(room, conn.id, {
          t: "death",
          from: conn.id,
          victim: msg.victim,
          killer: msg.killer,
          weaponId: msg.weaponId,
          headshot: msg.headshot,
        });
        break;
      case "bots":
        // Only the host owns bots; ignore from anyone else.
        if (conn.id === room.hostId) {
          this.relay(room, conn.id, { t: "bots", from: conn.id, b: msg.b });
        }
        break;
    }
  }

  private leave(conn: Conn): void {
    const room = this.rooms.get(conn.roomId);
    if (!room) return;
    room.conns.delete(conn.id);
    if (room.conns.size === 0) {
      this.rooms.delete(room.id);
      return;
    }
    if (room.hostId === conn.id) {
      room.hostId = room.conns.keys().next().value ?? -1;
    }
    this.recomputeTeams(room);
    this.broadcast(room, { t: "peerLeft", id: conn.id });
    this.broadcastLobby(room);
  }

  private recomputeTeams(room: Room): void {
    let i = 0;
    for (const c of room.conns.values()) {
      c.team = room.settings.mode === "ffa" ? "ffa" : (i % 2 === 0 ? "blue" : "red");
      i++;
    }
  }

  private roster(room: Room): LobbyPlayer[] {
    return [...room.conns.values()].map((c) => ({
      id: c.id,
      name: c.name,
      team: c.team,
      ready: c.ready,
    }));
  }

  private broadcastLobby(room: Room): void {
    this.broadcast(room, {
      t: "lobby",
      players: this.roster(room),
      hostId: room.hostId,
      settings: room.settings,
    });
  }

  private broadcast(room: Room, msg: ServerMsg): void {
    const s = encode(msg);
    for (const c of room.conns.values()) this.rawSend(c.ws, s);
  }

  private relay(room: Room, fromId: number, msg: ServerMsg): void {
    const s = encode(msg);
    for (const c of room.conns.values()) {
      if (c.id !== fromId) this.rawSend(c.ws, s);
    }
  }

  private send(ws: WebSocket, msg: ServerMsg): void {
    this.rawSend(ws, encode(msg));
  }

  private rawSend(ws: WebSocket, s: string): void {
    if (ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(s);
      } catch {
        // dropped frame; the close handler will clean up
      }
    }
  }
}

function sanitizeSettings(s: LobbySettings): LobbySettings {
  return {
    mapId: String(s.mapId ?? DEFAULT_SETTINGS.mapId),
    mode: (["tdm", "ffa", "dom", "ctf", "gungame"] as const).includes(s.mode) ? s.mode : "tdm",
    botCount: Math.max(0, Math.min(16, Math.floor(s.botCount ?? 0))),
    difficulty: ["recruit", "regular", "veteran"].includes(s.difficulty) ? s.difficulty : "regular",
    hardcore: !!s.hardcore,
  };
}
