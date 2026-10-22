extends SceneTree
const Main = preload("res://scripts/core/main.gd")
var failures: Array[String] = []
var peers: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func until(condition: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(condition.call(), message)

func new_peer():
	var peer = Main.new()
	root.add_child(peer)
	peer.set_physics_process(false)
	peers.append(peer)
	return peer

func run() -> void:
	var host = new_peer()
	var url := "ws://127.0.0.1:%d/ws" % (27000 + OS.get_process_id() % 1000)
	host._connect_multiplayer({"url": url, "room": "LATE", "name": "Host", "team": "blue", "asHost": true})
	await until(func(): return host.ui.lobby_state.get("isHost", false), "Host opens a room")
	host.net.set_settings({"mapId": "freight_yard", "mode": "dom", "botCount": 2, "difficulty": "regular", "hardcore": false})
	await until(func(): return host.net.settings.mode == "dom", "Host selects the match")
	host.net.start_match()
	await until(func(): return host.state == "playing", "Host starts alone")
	var session = host.game_match
	var original_instance: int = session.get_instance_id()
	session.state = "live"
	session.warmup = 0
	session.elapsed = 87.0
	session.player.position = Vector3(-40, 0, 0)
	session.scores[session.player.actor_id].kills = 4
	session.scores[session.player.actor_id].score = 400
	session.objective.blue = 35
	session.objective.red = 21
	session.objective.points[0].owner = "blue"
	session.objective.points[0].progress = 1.0
	session.network.tick(0.3)
	for frame in 8:
		await process_frame
	var guest = new_peer()
	guest._connect_multiplayer({"url": url, "room": "LATE", "name": "Late Red", "team": "red", "asHost": false})
	await until(func(): return guest.state == "playing", "Late joiner enters the running match automatically")
	check(session.get_instance_id() == original_instance and session.elapsed == 87.0, "Joining does not restart the host")
	check(guest.game_match.config.mapId == "freight_yard" and guest.game_match.mode.id == "dom", "Late joiner loads the current map and mode")
	check(guest.game_match.player.team == "red", "Late joiner keeps the chosen team")
	check(guest.game_match.state == "live" and guest.game_match.elapsed == 87.0, "Late joiner restores the running clock without a new warmup")
	check(guest.game_match.scores[session.player.actor_id].kills == 4, "Existing scores survive joining")
	check(guest.game_match.objective.blue == 35 and guest.game_match.objective.red == 21, "Objective score is synchronized")
	check(guest.game_match.objective.points[0].owner == "blue", "Captured points retain ownership")
	check(guest.game_match.network.remotes.has(1000000), "Existing host-owned bots are restored")
	check(guest.game_match.network.remotes[session.player.actor_id].position == session.player.position, "Existing player positions are available immediately")
	guest.game_match.player.position = Vector3(guest.game_match.objective.points[1].x, 0, guest.game_match.objective.points[1].z)
	guest.game_match.tick(0.1)
	check(guest.game_match.objective.points[1].progress == 0, "Guests do not advance objective rules independently of the host")
	await until(func(): return session.network.remotes.has(guest.net.self_id), "Host sees the new player without restarting")
	guest.game_match.player.position = Vector3(-10, 0, 0)
	guest.game_match.network.tick(0.05)
	await until(func(): return session.network.remotes[guest.net.self_id].has_snapshot, "Late player movement reaches existing players")
	guest.game_match.network.remotes[session.player.actor_id].apply_damage(25, guest.game_match.player, "m4")
	await until(func(): return session.player.health == 75, "Late player participates in combat")
	var third = new_peer()
	third._connect_multiplayer({"url": url, "room": "LATE", "name": "Late Blue", "team": "blue", "asHost": false})
	await until(func(): return third.state == "playing", "A second late join also succeeds")
	check(third.game_match.player.team == "blue", "Second late joiner chooses blue")
	await until(func(): return guest.game_match.network.remotes.has(third.net.self_id), "Earlier late joiner sees subsequent joins")
	session.end_match("blue")
	await until(func(): return guest.state == "post_match" and third.state == "post_match", "Host match completion reaches late joiners")
	for peer in peers:
		peer.free()
	await process_frame
	print("JOIN IN PROGRESS: %s" % ("PASS" if failures.is_empty() else str(failures.size()) + " failures"))
	quit(0 if failures.is_empty() else 1)
