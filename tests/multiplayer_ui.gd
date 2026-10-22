extends SceneTree
const UI = preload("res://scripts/ui/game_ui.gd")
const Store = preload("res://scripts/persistence/save_store.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var ui = UI.new()
	root.add_child(ui)
	ui.show_multiplayer()
	var events := {"connect": {}, "team": "", "copy": ""}
	ui.multiplayer_connect.connect(func(config): events.connect = config)
	ui.multiplayer_team_selected.connect(func(team): events.team = team)
	ui.multiplayer_copy_address.connect(func(address): events.copy = address)
	var join_team: OptionButton = ui.menu.find_child("JoinTeam", true, false)
	check(join_team != null, "Team choice is available before joining")
	join_team.select(2)
	join_team.item_selected.emit(2)
	ui._connect_multiplayer(true)
	check(events.connect.team == "red", "Initial team choice reaches the join request")
	check(events.connect.url == "ws://0.0.0.0:8090/ws", "Host form defaults to the wildcard address")
	ui.set_lobby_state({"isHost": false, "selfId": 2, "hostId": 1, "room": "TEAM", "ready": false,
		"shareAddresses": ["192.168.1.20:9000", "10.0.0.2:9000"],
		"players": [{"id": 1, "name": "Host", "team": "blue", "teamChoice": "blue"}, {"id": 2, "name": "Guest", "team": "red", "teamChoice": "red"}],
		"settings": Store.default_match_config()})
	var lobby_team: OptionButton = ui.menu.find_child("LobbyTeam", true, false)
	check(lobby_team.get_selected_metadata() == "red", "Lobby reflects the server's team selection")
	lobby_team.select(1)
	lobby_team.item_selected.emit(1)
	check(events.team == "blue", "Lobby lets the player change their own team")
	var copy: Button = ui.menu.find_child("CopyIP", true, false)
	copy.pressed.emit()
	check(events.copy == "192.168.1.20:9000", "Copy IP emits exactly IP and port without a URL path")
	ui.show_match()
	ui.show_pause()
	copy = ui.menu.find_child("CopyIP", true, false)
	check(copy != null, "Escape menu keeps Copy IP available during a match")
	ui.copy_address = "10.0.0.2:9000"
	copy.pressed.emit()
	check(events.copy == "10.0.0.2:9000", "In-game Copy IP uses the selected interface")
	ui.set_network_status("Copied IP: 10.0.0.2:9000")
	check(ui.screen == "pause" and ui.menu.find_child("CopyIP", true, false) != null, "Copy feedback preserves the Escape menu")
	ui.lobby_state.settings.mode = "ffa"
	ui._render_multiplayer()
	check(ui.menu.find_child("LobbyTeam", true, false) == null, "FFA does not offer meaningless team choices")
	ui.lobby_state = {}
	ui.show_pause()
	check(ui.menu.find_child("CopyIP", true, false) == null, "Solo matches do not show stale multiplayer addresses")
	ui.free()
	await process_frame
	print("MULTIPLAYER UI: %s" % ("PASS" if failures.is_empty() else str(failures.size()) + " failures"))
	quit(0 if failures.is_empty() else 1)
