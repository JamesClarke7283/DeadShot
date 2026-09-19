# Native multiplayer transport

`net_client.gd` extends Node, uses WebSocketPeer and accepts the source relay
protocol. Add it to the scene before `connect_room(url, room, name)`, which
returns a Godot Error. `connected` and `is_host()` expose connection state;
`self_id`, `host_id`, `players` and `settings` track lobby state.

Signals match the original callback arguments:

- `welcome(id)`
- `lobby(players, host_id, settings)`
- `started(settings, seed, players)`
- `state_received(from, state)`
- `bots_received(from, bots)`
- `hit_received(from, target, damage, headshot, weapon_id)`
- `death_received(from, victim, killer, weapon_id, headshot)`
- `event_received(from, kind, data)`
- `peer_left(id)`, `closed()`, `error(message)`

Optional missing killer IDs use `-1`; missing weapon IDs use an empty string.
Senders are `set_ready(bool)`, `set_settings(settings)`, `start_match()`,
`send_state(state)`, `send_bots(bots)`, `send_hit(target,damage,headshot,weapon_id)`,
`send_death(victim,killer,weapon_id,headshot)`, `send_event(kind,data)` and
`disconnect_room()`. Disconnect polls the WebSocket closing handshake.

`scripts/server/multiplayer_relay.gd` extends Node. Add it to a scene and call
`start(port = 8090, bind_address = '*') -> Error`. Any WebSocket HTTP path is
accepted, including the original `/ws`. `stop()`, `running`, `room_count` and
`port` are available. Rooms, host transfer, alternating teams, ready flags,
sanitized settings, random match seeds and client-authoritative traffic preserve
the source server behavior. Only hosts may update settings, start games or send
bot states. Match traffic never leaves its room and is not echoed to its sender.

Run a dedicated server without a browser or Deno:

```
godot --headless --path . --script scripts/server/relay_main.gd -- --port=8090
```

`tests/net_relay_test.gd` launches real local TCP/WebSocket peers, validates all
message types and room/host behavior, and closes all connections afterward.
