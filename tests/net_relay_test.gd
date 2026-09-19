extends SceneTree
## Real TCP/WebSocket integration test, including room isolation and authority.
const Client := preload("res://scripts/net/net_client.gd")
const Relay := preload("res://scripts/server/multiplayer_relay.gd")
const Protocol := preload("res://scripts/net/protocol.gd")
var failures: Array[String] = []
var clients: Array = []
var packets: Array = [{}, {}, {}]
var relay: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func until(condition: Callable, message: String, seconds: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var success: bool = condition.call()
	check(success, message)
	return success

func settle() -> void:
	for frame in 8:
		await process_frame

func run() -> void:
	check(Protocol.decode("bad JSON").is_empty(), "Invalid JSON is ignored")
	check(Protocol.decode('{"hello":"world"}').is_empty(), "Untagged JSON is ignored")
	relay = Relay.new()
	root.add_child(relay)
	var port := 19000 + OS.get_process_id() % 1000
	var error: Error = relay.start(port, "127.0.0.1")
	check(error == OK, "Isolated local relay starts")
	if error != OK:
		quit(1)
		return
	for i in 3:
		var client := Client.new()
		root.add_child(client)
		clients.append(client)
		client.error.connect(func(text): check(false, "Unexpected network error: " + text))
		client.started.connect(func(settings, seed, players): packets[i].start = {"settings": settings, "seed": seed, "players": players})
		client.state_received.connect(func(from, state): packets[i].state = {"from": from, "s": state})
		client.bots_received.connect(func(from, bots): packets[i].bots = {"from": from, "b": bots})
		client.hit_received.connect(func(from, target, damage, headshot, weapon): packets[i].hit = [from, target, damage, headshot, weapon])
		client.death_received.connect(func(from, victim, killer, weapon, headshot): packets[i].death = [from, victim, killer, weapon, headshot])
		client.event_received.connect(func(from, kind, data): packets[i].event = [from, kind, data])
		client.peer_left.connect(func(id): packets[i].left = id)
		client.closed.connect(func(): packets[i].closed = true)
		client.connect_room("ws://127.0.0.1:%d/ws" % port, "ALPHA" if i < 2 else "BRAVO", "Host" if i == 0 else "Second player with long name trimmed" if i == 1 else "Other room")
		await until(func(): return client.self_id >= 0, "Client %d receives welcome" % i)
	await until(func(): return clients[0].players.size() == 2 and clients[1].players.size() == 2 and clients[2].players.size() == 1, "Room rosters isolate clients")
	check(relay.room_count == 2, "Two separate rooms exist")
	check(clients[0].is_host() and not clients[1].is_host() and clients[2].is_host(), "First room member becomes host")
	check(clients[0].players[0].team == "blue" and clients[0].players[1].team == "red", "TDM assigns alternating teams")
	check(clients[0].players[1].name.length() == 24, "Names truncate to 24 characters")
	check(clients[0].settings.botCount == 4, "Network defaults retain four bots")
	clients[1].set_ready(true)
	await until(func(): return clients[0].players[1].ready, "Ready status broadcasts")
	clients[1].set_settings({"mapId": "urban_docks", "mode": "ffa", "botCount": 16})
	clients[1].start_match()
	clients[1].send_bots([{"id": 999}])
	await settle()
	check(clients[0].settings.mapId == "desert_town", "Non-host settings are ignored")
	check(not packets[0].has("start") and not packets[0].has("bots"), "Only the host can start and send bot state")
	clients[0].set_settings({"mapId": "forest_facility", "mode": "ffa", "botCount": 99, "difficulty": "invalid", "hardcore": true})
	await until(func(): return clients[1].settings.mode == "ffa", "Host settings broadcast")
	check(clients[1].settings.botCount == 16 and clients[1].settings.difficulty == "regular", "Settings sanitize bot count and difficulty")
	check(clients[1].players.all(func(player): return player.team == "ffa"), "FFA recomputes all teams")
	clients[0].start_match()
	await until(func(): return packets[0].has("start") and packets[1].has("start"), "Match start reaches every room member")
	check(packets[0].start == packets[1].start, "All peers receive identical seed, settings and roster")
	var player_state := {"x": 1.5, "y": 2.0, "z": -4.0, "yaw": 0.25, "anim": "shoot", "alive": true, "weaponId": "m4"}
	clients[1].send_state(player_state)
	await until(func(): return packets[0].has("state"), "Player state relays")
	check(packets[0].state.s == player_state and packets[0].state.from == clients[1].self_id, "Player state retains data and sender")
	check(not packets[1].has("state"), "Relay does not echo sender state")
	var bots := [{"id": 100, "x": 4, "y": 0, "z": 8, "yaw": 1.2, "anim": "run", "alive": true, "team": "ffa", "weaponId": "ak47"}]
	clients[0].send_bots(bots)
	clients[0].send_hit(clients[1].self_id, 42.5, true, "m4")
	clients[1].send_death(clients[1].self_id, clients[0].self_id, "m4", true)
	clients[0].send_event("explosion", {"x": 5, "z": 6})
	await until(func(): return packets[1].has("bots") and packets[1].has("hit") and packets[0].has("death") and packets[1].has("event"), "Bots, hit, death and event all relay")
	# JSON has one numeric type; Godot parses wire numbers as float, so compare
	# against the same serialized representation rather than native int Variants.
	check(packets[1].bots.b == JSON.parse_string(JSON.stringify(bots)), "Bot state preserves original wire fields")
	check(packets[1].hit == [clients[0].self_id, clients[1].self_id, 42.5, true, "m4"], "Hit fields retain source order")
	check(packets[0].death == [clients[1].self_id, clients[1].self_id, clients[0].self_id, "m4", true], "Death fields retain source order")
	check(packets[1].event == [clients[0].self_id, "explosion", {"x": 5.0, "z": 6.0}], "Event data relays unchanged")
	check(packets[2].is_empty(), "Other rooms receive no match traffic")
	var old_host: int = clients[0].self_id
	clients[0].disconnect_room()
	await until(func(): return clients[1].is_host() and clients[1].players.size() == 1 and packets[1].get("left", -1) == old_host, "Host departure promotes remaining player")
	clients[1].set_settings({"mapId": "urban_docks", "mode": "gungame", "botCount": 3.9, "difficulty": "veteran", "hardcore": false})
	await until(func(): return clients[1].settings.mode == "gungame", "Promoted host can change settings")
	check(clients[1].settings.botCount == 3, "Bot count floors fractional values")
	clients[1].disconnect_room()
	clients[2].disconnect_room()
	await until(func(): return relay.room_count == 0, "Empty rooms are removed")
	await until(func(): return packets.all(func(packet): return packet.get("closed", false)), "All clients complete closing handshakes")
	relay.stop()
	for client in clients:
		client.queue_free()
	relay.queue_free()
	await process_frame
	print("Native WebSocket integration: %s" % ("PASS" if failures.is_empty() else "%d failures" % failures.size()))
	quit(0 if failures.is_empty() else 1)
