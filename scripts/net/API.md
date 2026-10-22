# Native multiplayer transport

`net_client.gd` extends Node, uses WebSocketPeer and accepts the source relay
protocol. Add it to the scene before `connect_room(url, room, name, team = "auto")`, which
returns a Godot Error. `connected` and `is_host()` expose connection state;
`self_id`, `host_id`, `players` and `settings` track lobby state.

Signals match the original callback arguments:

- `welcome(id)`
- `lobby(players, host_id, settings)`
- `started(settings, seed, players)`
- `state_received(from, state)`
- `bots_received(from, bots)`
- `match_state_received(state)`
- `hit_received(from, target, damage, headshot, weapon_id)`
- `death_received(from, victim, killer, weapon_id, headshot)`
- `event_received(from, kind, data)`
- `peer_left(id)`, `closed()`, `error(message)`

Optional missing killer IDs use `-1`; missing weapon IDs use an empty string.
Senders are `set_ready(bool)`, `set_team("auto" | "blue" | "red")`, `set_settings(settings)`, `start_match()`,
`send_state(state)`, `send_bots(bots)`, `send_match_state(state)`, `send_hit(target,damage,headshot,weapon_id)`,
`send_death(victim,killer,weapon_id,headshot)`, `send_event(kind,data)` and
`disconnect_room()`. Disconnect polls the WebSocket closing handshake.

Player and bot snapshots optionally carry `shotSerial`, `shotAge` (seconds),
and `shotX`, `shotY`, `shotZ`. The monotonically increasing serial records shots
that finish between snapshots. The shot event retains its firing position and
remaining pulse time, so repeated snapshots do not extend the pulse. Live enemy
markers follow the actor's current position independently. Peers without these
fields fall back to `anim: "shoot"`.

`scripts/server/multiplayer_relay.gd` extends Node. Add it to a scene and call
`start(port = 8090, listen_address = "0.0.0.0") -> Error`. Any WebSocket HTTP path is
accepted, including the original `/ws`. `stop()`, `running`, `room_count` and
`port` and `bind_address` are available. Rooms, host transfer, team choices, ready flags,
sanitized settings, random match seeds and client-authoritative traffic preserve
the source server behavior. Only hosts may update settings, start games or send
bot and match states. Match traffic never leaves its room and is not echoed to its sender.

The host sends `{"t":"match","s":state}` every 250 ms and immediately at
match end. State includes `elapsed`, `warmup`, `state`, `winner`, scoreboard
`scores`, Gun Game `tiers` and `objective` (Domination progress/owners, or CTF
flag positions/status/carriers and team scores). Only the host advances objective
rules and declares the winner; clients apply the snapshot. External legacy
relays that do not forward these snapshots retain local rule simulation.

The relay caches the latest match, player and bot snapshots. Joining a started
room sends `start` only to the newcomer, using the original seed and match
settings plus `matchState`, `states` and `bots`. `NetClient.join_state` exposes
these fields before emitting `started`; `MatchNetwork.restore_join_state()`
applies them after scene construction. Lobby updates also add newcomers to
existing matches without resetting the scene. The relay remains alive on the
results screen until its host leaves, allowing the final snapshot to reach peers.

Join messages optionally carry `team`; later `{"t":"team","team":"red"}`
messages update the sender's choice before match start and clear their ready
flag. Roster entries include `teamChoice` as well as effective `team`. Auto
assign balances new players, including late arrivals, while preserving existing assignments. FFA and
Gun Game expose `team: "ffa"` without discarding the stored choice.

`network_address.gd` normalizes pasted `IP:port` values, dials loopback when the
host form contains a wildcard, and lists shareable interface addresses with LAN
interfaces first. Wildcards are never offered as addresses to copy.

Run a dedicated server without a browser or Deno:

```
godot --headless --path . --script scripts/server/relay_main.gd -- --port=8090
```

`tests/net_relay_test.gd` launches real local TCP/WebSocket peers, validates all
message types and room/host behavior, and closes all connections afterward.
