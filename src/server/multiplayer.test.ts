import { assert, assertEquals } from "@std/assert";
import { RoomManager } from "./multiplayer.ts";
import type { ServerMsg } from "../net/protocol.ts";

/** Minimal in-memory stand-in for a server-side WebSocket. */
class FakeSocket {
  readyState: number = WebSocket.OPEN;
  sent: string[] = [];
  onmessage: ((ev: MessageEvent) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;

  send(s: string): void {
    this.sent.push(s);
  }
  close(): void {
    this.readyState = WebSocket.CLOSED;
    this.onclose?.();
  }

  recv(msg: unknown): void {
    this.onmessage?.({ data: JSON.stringify(msg) } as MessageEvent);
  }
  msgs(): ServerMsg[] {
    return this.sent.map((s) => JSON.parse(s) as ServerMsg);
  }
  ofType<T extends ServerMsg["t"]>(t: T): Extract<ServerMsg, { t: T }>[] {
    return this.msgs().filter((m) => m.t === t) as Extract<ServerMsg, { t: T }>[];
  }
  last(): ServerMsg {
    return JSON.parse(this.sent[this.sent.length - 1]) as ServerMsg;
  }
}

function accept(mgr: RoomManager): FakeSocket {
  const s = new FakeSocket();
  mgr.accept(s as unknown as WebSocket);
  return s;
}

Deno.test("two players join a room and both see a 2-player lobby; first is host", () => {
  const mgr = new RoomManager();
  const a = accept(mgr);
  const b = accept(mgr);
  a.recv({ t: "join", room: "R1", name: "Alice" });
  b.recv({ t: "join", room: "R1", name: "Bob" });

  const aLobby = a.ofType("lobby").at(-1)!;
  const bLobby = b.ofType("lobby").at(-1)!;
  assertEquals(aLobby.players.length, 2);
  assertEquals(bLobby.players.length, 2);
  // First joiner is host; teams alternate in TDM.
  assertEquals(aLobby.hostId, aLobby.players[0].id);
  assertEquals(aLobby.players[0].team, "blue");
  assertEquals(aLobby.players[1].team, "red");
  const welcome = a.ofType("welcome")[0];
  assertEquals(welcome.id, aLobby.players[0].id);
});

Deno.test("host settings update reaches both clients and FFA flattens teams", () => {
  const mgr = new RoomManager();
  const a = accept(mgr);
  const b = accept(mgr);
  a.recv({ t: "join", room: "R2", name: "A" });
  b.recv({ t: "join", room: "R2", name: "B" });

  a.recv({
    t: "settings",
    settings: {
      mapId: "urban_docks",
      mode: "ffa",
      botCount: 6,
      difficulty: "veteran",
      hardcore: true,
    },
  });
  const bLobby = b.ofType("lobby").at(-1)!;
  assertEquals(bLobby.settings.mode, "ffa");
  assertEquals(bLobby.settings.botCount, 6);
  assertEquals(bLobby.players.every((p) => p.team === "ffa"), true);

  // A non-host settings change is ignored.
  b.recv({
    t: "settings",
    settings: {
      mapId: "desert_town",
      mode: "tdm",
      botCount: 0,
      difficulty: "recruit",
      hardcore: false,
    },
  });
  assertEquals(a.ofType("lobby").at(-1)!.settings.mode, "ffa");
});

Deno.test("host start reaches everyone; in-match traffic is relayed to peers only", () => {
  const mgr = new RoomManager();
  const a = accept(mgr);
  const b = accept(mgr);
  a.recv({ t: "join", room: "R3", name: "A" });
  b.recv({ t: "join", room: "R3", name: "B" });
  const aId = a.ofType("welcome")[0].id;

  a.recv({ t: "start" });
  assert(a.ofType("start").length === 1);
  assert(b.ofType("start").length === 1);

  // A's state should reach B (tagged with A's id) but not echo back to A.
  const aStateBefore = a.ofType("state").length;
  a.recv({
    t: "state",
    s: { x: 5, y: 0, z: 0, yaw: 0, anim: "idle", alive: true, weaponId: "m4" },
  });
  assertEquals(a.ofType("state").length, aStateBefore, "sender does not receive own state");
  const bState = b.ofType("state").at(-1)!;
  assertEquals(bState.from, aId);
  assertEquals(bState.s.x, 5);

  // Hit + death relay to the other client.
  b.recv({ t: "hit", target: aId, dmg: 50, headshot: true, weaponId: "ak12" });
  const aHit = a.ofType("hit").at(-1)!;
  assertEquals(aHit.target, aId);
  assertEquals(aHit.dmg, 50);
});

Deno.test("only the host may broadcast bot state", () => {
  const mgr = new RoomManager();
  const a = accept(mgr); // host
  const b = accept(mgr);
  a.recv({ t: "join", room: "R4", name: "A" });
  b.recv({ t: "join", room: "R4", name: "B" });

  const bots = [{
    id: 10000,
    x: 0,
    y: 0,
    z: 0,
    yaw: 0,
    anim: "idle" as const,
    alive: true,
    team: "red" as const,
    weaponId: "m4",
  }];
  a.recv({ t: "bots", b: bots });
  assertEquals(b.ofType("bots").length, 1, "host bot state relayed");

  const before = a.ofType("bots").length;
  b.recv({ t: "bots", b: bots }); // non-host -> ignored
  assertEquals(a.ofType("bots").length, before, "non-host bot state ignored");
});

Deno.test("host reassigns when the host leaves; peers are notified", () => {
  const mgr = new RoomManager();
  const a = accept(mgr);
  const b = accept(mgr);
  a.recv({ t: "join", room: "R5", name: "A" });
  b.recv({ t: "join", room: "R5", name: "B" });
  const bId = b.ofType("welcome")[0].id;

  a.close();
  assert(b.ofType("peerLeft").length === 1);
  const bLobby = b.ofType("lobby").at(-1)!;
  assertEquals(bLobby.hostId, bId, "remaining player becomes host");
  assertEquals(bLobby.players.length, 1);
});

Deno.test("empty room is cleaned up after everyone leaves", () => {
  const mgr = new RoomManager();
  const a = accept(mgr);
  a.recv({ t: "join", room: "Solo", name: "A" });
  assertEquals(mgr.roomCount, 1);
  a.close();
  assertEquals(mgr.roomCount, 0);
});
