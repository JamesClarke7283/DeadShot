extends Node
## Native WebSocket implementation of the existing browser relay client.
## No Node/Deno process is required; can also join the original browser server.
signal welcome(id: int)
signal lobby(players: Array, host_id: int, settings: Dictionary)
signal started(settings: Dictionary, seed: int, players: Array)
signal state_received(from: int, state: Dictionary)
signal bots_received(from: int, bots: Array)
signal hit_received(from: int, target: int, damage: float, headshot: bool, weapon_id: String)
signal death_received(from: int, victim: int, killer: int, weapon_id: String, headshot: bool)
signal event_received(from: int, kind: String, data: Variant)
signal peer_left(id: int)
signal closed
signal error(message: String)

const Protocol := preload("res://scripts/net/protocol.gd")
var self_id := -1
var host_id := -1
var players: Array = []
var settings: Dictionary = Protocol.DEFAULT_SETTINGS.duplicate(true)
var url := ""
var socket: WebSocketPeer
var _room := ""
var _player_name := "Player"
var _join_sent := false
var _connect_started := 0.0
var _intentional_close := false
var connected: bool:
	get:
		return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_host() -> bool:
	return self_id >= 0 and self_id == host_id

func connect_room(server_url: String, room: String, player_name: String) -> Error:
	if socket != null:
		socket.close(1000, "Reconnecting")
	url = server_url
	_room = room
	_player_name = player_name
	self_id = -1
	host_id = -1
	players.clear()
	settings = Protocol.DEFAULT_SETTINGS.duplicate(true)
	_join_sent = false
	_intentional_close = false
	_connect_started = Time.get_ticks_msec() * 0.001
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1024 * 1024
	socket.outbound_buffer_size = 1024 * 1024
	var result := socket.connect_to_url(url)
	if result != OK:
		socket = null
		error.emit("Could not connect to %s: %s" % [url, error_string(result)])
	return result

func _process(_delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _join_sent:
			_join_sent = true
			_send({"t": "join", "room": _room, "name": _player_name})
		while socket != null and socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()
			if socket.was_string_packet():
				_dispatch(packet.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_joined := _join_sent
		var code := socket.get_close_code()
		var reason := socket.get_close_reason()
		socket = null
		if not _intentional_close and (not was_joined or code == -1):
			error.emit("Could not connect to %s." % url if not was_joined else "Connection lost: %s" % reason)
		closed.emit()
	elif state == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() * 0.001 - _connect_started > 10:
		socket.close()
		socket = null
		error.emit("Connection to %s timed out." % url)
		closed.emit()

func _dispatch(raw: String) -> void:
	var message := Protocol.decode(raw)
	if message.is_empty():
		return
	match message.t:
		"welcome":
			self_id = int(message.get("id", -1))
			welcome.emit(self_id)
		"lobby":
			players = message.get("players", [])
			host_id = int(message.get("hostId", -1))
			settings = message.get("settings", Protocol.DEFAULT_SETTINGS.duplicate(true))
			lobby.emit(players, host_id, settings)
		"start":
			settings = message.get("settings", Protocol.DEFAULT_SETTINGS.duplicate(true))
			players = message.get("players", [])
			started.emit(settings, int(message.get("seed", 0)), players)
		"state": state_received.emit(int(message.get("from", -1)), message.get("s", {}))
		"bots": bots_received.emit(int(message.get("from", -1)), message.get("b", []))
		"hit": hit_received.emit(int(message.get("from", -1)), int(message.get("target", -1)), float(message.get("dmg", 0)), bool(message.get("headshot", false)), str(message.get("weaponId", "")))
		"death": death_received.emit(int(message.get("from", -1)), int(message.get("victim", -1)), int(message.get("killer", -1)), str(message.get("weaponId", "")), bool(message.get("headshot", false)))
		"event": event_received.emit(int(message.get("from", -1)), str(message.get("kind", "")), message.get("data"))
		"peerLeft": peer_left.emit(int(message.get("id", -1)))

func _send(message: Dictionary) -> void:
	if connected:
		socket.send_text(Protocol.encode(message))

func set_ready(ready: bool) -> void:
	_send({"t": "ready", "ready": ready})

func set_settings(value: Dictionary) -> void:
	_send({"t": "settings", "settings": value})

func start_match() -> void:
	_send({"t": "start"})

func send_state(state: Dictionary) -> void:
	_send({"t": "state", "s": state})

func send_bots(bots: Array) -> void:
	_send({"t": "bots", "b": bots})

func send_hit(target: int, damage: float, headshot: bool, weapon_id: String = "") -> void:
	var message := {"t": "hit", "target": target, "dmg": damage, "headshot": headshot}
	if not weapon_id.is_empty(): message.weaponId = weapon_id
	_send(message)

func send_death(victim: int, killer: int = -1, weapon_id: String = "", headshot: bool = false) -> void:
	var message := {"t": "death", "victim": victim, "headshot": headshot}
	if killer >= 0: message.killer = killer
	if not weapon_id.is_empty(): message.weaponId = weapon_id
	_send(message)

func send_event(kind: String, data: Variant = null) -> void:
	var message := {"t": "event", "kind": kind}
	if data != null: message.data = data
	_send(message)

func disconnect_room() -> void:
	_intentional_close = true
	if socket != null:
		socket.close(1000, "Leaving room")

func _exit_tree() -> void:
	if socket != null:
		socket.close(1000, "Client closing")
