extends Node
## WebSocket relay preserving src/server/multiplayer.ts rooms and wire format.
const Protocol := preload("res://scripts/net/protocol.gd")
var _server := TCPServer.new()
var _peers: Dictionary = {}
var _rooms: Dictionary = {}
var _next_socket := 1
var _next_player := 1
var port := 8090
var bind_address := "0.0.0.0"
var running: bool:
	get: return _server.is_listening()
var room_count: int:
	get: return _rooms.size()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start(listen_port: int = 8090, listen_address: String = "0.0.0.0") -> Error:
	if running:
		return ERR_ALREADY_IN_USE
	port = listen_port
	bind_address = listen_address
	return _server.listen(port, bind_address)

func stop() -> void:
	_server.stop()
	for record in _peers.values():
		record.socket.close(1001, "Server shutting down")
	_peers.clear()
	_rooms.clear()

func _process(_delta: float) -> void:
	if not running:
		return
	while _server.is_connection_available():
		var socket := WebSocketPeer.new()
		socket.inbound_buffer_size = 1024 * 1024
		socket.outbound_buffer_size = 1024 * 1024
		var result := socket.accept_stream(_server.take_connection())
		if result == OK:
			_peers[_next_socket] = {"socket": socket, "id": -1, "room": "", "name": "", "team": "blue", "teamChoice": "auto", "assignedTeam": "", "ready": false, "openedAt": Time.get_ticks_msec()}
			_next_socket += 1
	for socket_id in _peers.keys():
		var record: Dictionary = _peers[socket_id]
		var socket: WebSocketPeer = record.socket
		socket.poll()
		match socket.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while socket.get_available_packet_count() > 0:
					var packet := socket.get_packet()
					if socket.was_string_packet():
						_handle_packet(record, packet.get_string_from_utf8())
			WebSocketPeer.STATE_CLOSED:
				_leave(record)
				_peers.erase(socket_id)
			WebSocketPeer.STATE_CONNECTING:
				if Time.get_ticks_msec() - int(record.openedAt) > 10000:
					socket.close()
					_peers.erase(socket_id)

func _handle_packet(record: Dictionary, raw: String) -> void:
	var message := Protocol.decode(raw)
	if message.is_empty():
		return
	if message.t == "join":
		if record.id < 0 and message.get("room") is String:
			_join(record, message.room, str(message.get("name", "")), str(message.get("team", "auto")))
		return
	if record.id < 0 or not _rooms.has(record.room):
		return
	var room: Dictionary = _rooms[record.room]
	match message.t:
		"team":
			var choice := str(message.get("team", ""))
			if not room.started and choice in ["auto", "blue", "red"]:
				record.teamChoice = choice
				record.assignedTeam = "" if choice == "auto" else choice
				record.ready = false
				_recompute_teams(room)
				_broadcast_lobby(room)
		"ready":
			record.ready = bool(message.get("ready", false))
			_broadcast_lobby(room)
		"settings":
			if record.id == room.hostId and message.get("settings") is Dictionary:
				room.settings = Protocol.sanitize_settings(message.settings)
				_recompute_teams(room)
				_broadcast_lobby(room)
		"start":
			if record.id == room.hostId:
				room.started = true
				room.matchSettings = room.settings.duplicate(true)
				_recompute_teams(room)
				room.seed = randi_range(0, 999999999)
				room.matchState = {}
				room.states = {}
				room.bots = []
				_broadcast(room, _start_packet(room))
		"state":
			if message.get("s") is Dictionary:
				room.states[str(record.id)] = message.s
				_broadcast(room, {"t": "state", "from": record.id, "s": message.s}, record.id)
		"bots":
			if record.id == room.hostId and message.get("b") is Array:
				room.bots = message.b
				_broadcast(room, {"t": "bots", "from": record.id, "b": message.b}, record.id)
		"match":
			if record.id == room.hostId and message.get("s") is Dictionary:
				room.matchState = message.s
				_broadcast(room, {"t": "match", "s": message.s}, record.id)
		"hit", "death", "event":
			var relayed := {"t": message.t, "from": record.id}
			var fields: Array = {"hit": ["target", "dmg", "headshot", "weaponId"], "death": ["victim", "killer", "weaponId", "headshot"], "event": ["kind", "data"]}[message.t]
			for key in fields:
				if message.has(key): relayed[key] = message[key]
			_broadcast(room, relayed, record.id)

func _join(record: Dictionary, room_id: String, player_name: String, preferred_team: String = "auto") -> void:
	if not _rooms.has(room_id):
		_rooms[room_id] = {"id": room_id, "players": {}, "hostId": -1, "started": false, "seed": 0,
			"matchState": {}, "states": {}, "bots": [], "matchSettings": {}, "settings": Protocol.DEFAULT_SETTINGS.duplicate(true)}
	var room: Dictionary = _rooms[room_id]
	record.id = _next_player
	_next_player += 1
	record.room = room_id
	record.name = player_name.left(24) if not player_name.is_empty() else "Player %d" % record.id
	record.teamChoice = preferred_team if preferred_team in ["auto", "blue", "red"] else "auto"
	room.players[record.id] = record
	if room.hostId < 0:
		room.hostId = record.id
	_recompute_teams(room)
	_send(record.socket, {"t": "welcome", "id": record.id})
	_broadcast_lobby(room)
	if room.started:
		# Only the newcomer receives start; existing players keep their round.
		_send(record.socket, _start_packet(room))

func _start_packet(room: Dictionary) -> Dictionary:
	return {"t": "start", "settings": room.matchSettings, "seed": room.seed, "players": _roster(room),
		"matchState": room.matchState, "states": room.states, "bots": room.bots}

func _leave(record: Dictionary) -> void:
	if record.id < 0 or not _rooms.has(record.room):
		return
	var room: Dictionary = _rooms[record.room]
	room.players.erase(record.id)
	room.states.erase(str(record.id))
	if room.players.is_empty():
		_rooms.erase(record.room)
		return
	if room.hostId == record.id:
		room.hostId = room.players.keys()[0]
	_recompute_teams(room)
	_broadcast(room, {"t": "peerLeft", "id": record.id})
	_broadcast_lobby(room)

func _recompute_teams(room: Dictionary) -> void:
	var counts := {"blue": 0, "red": 0}
	var mode: String = str(room.matchSettings.get("mode", room.settings.mode)) if room.started else str(room.settings.mode)
	# Preserve prior assignments, including across FFA mode changes and leaves.
	# Only a new player or an explicit Auto selection needs a balanced choice.
	for record in room.players.values():
		if record.teamChoice in ["blue", "red"]:
			record.assignedTeam = record.teamChoice
		if record.assignedTeam in ["blue", "red"]:
			counts[record.assignedTeam] += 1
	for record in room.players.values():
		if record.assignedTeam not in ["blue", "red"]:
			record.assignedTeam = "blue" if counts.blue <= counts.red else "red"
			counts[record.assignedTeam] += 1
		record.team = "ffa" if mode in ["ffa", "gungame"] else record.assignedTeam

func _roster(room: Dictionary) -> Array:
	var roster: Array = []
	for record in room.players.values():
		roster.append({"id": record.id, "name": record.name, "team": record.team, "teamChoice": record.teamChoice, "ready": record.ready})
	return roster

func _broadcast_lobby(room: Dictionary) -> void:
	_broadcast(room, {"t": "lobby", "players": _roster(room), "hostId": room.hostId, "settings": room.settings})

func _broadcast(room: Dictionary, message: Dictionary, except_id: int = -1) -> void:
	var raw := Protocol.encode(message)
	for record in room.players.values():
		if record.id != except_id and record.socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			record.socket.send_text(raw)

func _send(socket: WebSocketPeer, message: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(Protocol.encode(message))

func _exit_tree() -> void:
	stop()
