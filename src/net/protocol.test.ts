import { assert, assertEquals } from "@std/assert";
import {
  type ClientMsg,
  decodeClient,
  decodeServer,
  DEFAULT_SETTINGS,
  encode,
  type ServerMsg,
} from "./protocol.ts";

Deno.test("client messages round-trip through encode/decodeClient", () => {
  const msgs: ClientMsg[] = [
    { t: "join", room: "ABCD", name: "Neo" },
    { t: "ready", ready: true },
    { t: "settings", settings: { ...DEFAULT_SETTINGS, mode: "ffa", botCount: 8 } },
    { t: "start" },
    {
      t: "state",
      s: { x: 1, y: 2, z: 3, yaw: 0.5, anim: "run", alive: true, weaponId: "m4" },
    },
    { t: "hit", target: 7, dmg: 33, headshot: true, weaponId: "ak12" },
    { t: "death", victim: 7, killer: 1, weaponId: "ak12", headshot: false },
  ];
  for (const m of msgs) {
    const back = decodeClient(encode(m));
    assertEquals(back, m);
  }
});

Deno.test("server messages round-trip through encode/decodeServer", () => {
  const msgs: ServerMsg[] = [
    { t: "welcome", id: 3 },
    {
      t: "lobby",
      players: [{ id: 1, name: "A", team: "blue", ready: false }],
      hostId: 1,
      settings: DEFAULT_SETTINGS,
    },
    { t: "start", settings: DEFAULT_SETTINGS, seed: 42, players: [] },
    { t: "peerLeft", id: 9 },
  ];
  for (const m of msgs) {
    assertEquals(decodeServer(encode(m)), m);
  }
});

Deno.test("decoders return null on malformed input", () => {
  assertEquals(decodeClient("not json"), null);
  assertEquals(decodeClient("123"), null); // valid JSON, but no .t
  assertEquals(decodeServer("{}"), null);
  assert(decodeClient('{"t":"start"}') !== null);
});
