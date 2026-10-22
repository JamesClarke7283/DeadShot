extends Node
## The same ownership model as Match.ts: each peer owns its player; the host
## owns bots. Snapshots are cosmetic; hits go to the victim's owner to resolve.
const Remote = preload("res://scripts/game/remote_combatant.gd")
var game_match
var client
var is_host := false
var remotes: Dictionary = {}
var send_timer := 0.0
var match_timer := 0.0
var has_match_state := false

func setup(owner_match, net_client) -> void:
	game_match = owner_match
	client = net_client
	is_host = client.is_host()

func begin() -> void:
	for person in client.players:
		if int(person.id) != client.self_id:
			add_remote(int(person.id),str(person.team),str(person.name))
	client.state_received.connect(_state_received)
	client.bots_received.connect(_bots_received)
	client.hit_received.connect(_hit_received)
	client.death_received.connect(_death_received)
	client.peer_left.connect(_peer_left)
	client.lobby.connect(_roster_received)
	client.match_state_received.connect(apply_match_state)

func restore_join_state() -> void:
	var initial: Dictionary = client.join_state
	for actor_id in initial.get("states", {}):
		_state_received(int(actor_id), initial.states[actor_id])
	_bots_received(client.host_id, initial.get("bots", []))
	apply_match_state(initial.get("matchState", {}))

func _roster_received(players: Array, host_id: int, _settings: Dictionary) -> void:
	is_host = client.self_id == host_id
	for person in players:
		if int(person.id) != client.self_id:
			add_remote(int(person.id), str(person.team), str(person.name))

func team_for_player(id: int) -> String:
	for person in client.players:
		if int(person.id) == id:
			return str(person.team)
	return "blue"

func owns(actor) -> bool:
	return not remotes.has(actor.actor_id)

func actor_by_id(id: int):
	for actor in game_match.actors:
		if actor.actor_id == id:
			return actor
	return null

func add_remote(id: int, team: String, player_name: String):
	if remotes.has(id):
		return remotes[id]
	var actor = Remote.new()
	game_match.add_child(actor)
	actor.setup_remote(id,team,player_name,remotes.size(),game_match,client)
	remotes[id] = actor
	game_match.actors.append(actor)
	game_match.scores[id] = {"id":id,"name":player_name,"team":team,"kills":0,"deaths":0,"assists":0,"score":0,"isPlayer":false}
	game_match.tiers[id] = 0
	game_match.streak_scores[id] = 0
	return actor

func tick(dt: float) -> void:
	match_timer -= dt
	if is_host and match_timer <= 0.0:
		publish_match_state()
	send_timer -= dt
	if send_timer > 0:
		return
	send_timer = 0.05
	if game_match.player:
		client.send_state(snapshot(game_match.player))
	if is_host:
		var bots: Array = []
		for actor in game_match.actors:
			if actor != game_match.player and owns(actor):
				var value = snapshot(actor)
				value.id = actor.actor_id
				value.team = actor.team
				bots.append(value)
		if not bots.is_empty():
			client.send_bots(bots)

func publish_match_state() -> void:
	if not is_host:
		return
	match_timer = 0.25
	client.send_match_state({"elapsed": game_match.elapsed, "warmup": game_match.warmup,
		"state": game_match.state, "winner": game_match.winner,
		"scores": game_match.score_rows(), "tiers": game_match.tiers,
		"objective": game_match.objective.network_state() if game_match.objective else {}})

func apply_match_state(value: Dictionary) -> void:
	if is_host or value.is_empty():
		return
	has_match_state = true
	game_match.elapsed = float(value.get("elapsed", game_match.elapsed))
	game_match.warmup = float(value.get("warmup", game_match.warmup))
	for row in value.get("scores", []):
		var id := int(row.id)
		if not game_match.scores.has(id):
			continue
		var copy: Dictionary = row.duplicate(true)
		copy.id = id
		copy.isPlayer = id == client.self_id
		game_match.scores[id] = copy
	for actor_id in value.get("tiers", {}):
		game_match.tiers[int(actor_id)] = int(value.tiers[actor_id])
	if game_match.objective:
		game_match.objective.apply_network_state(value.get("objective", {}))
	var state: String = str(value.get("state", game_match.state))
	if state == "end":
		var winner: Variant = value.get("winner")
		if winner is float:
			winner = int(winner)
		game_match.call_deferred("end_match", winner)
	elif game_match.state != "end":
		game_match.state = state

func snapshot(actor) -> Dictionary:
	var direction: Vector3 = actor.aim_direction()
	return {"x":actor.position.x,"y":actor.position.y,"z":actor.position.z,
		"yaw":atan2(direction.x,direction.z) if actor.is_player else actor.rotation.y,
		"anim":"die" if not actor.alive else ("shoot" if actor.firing else ("run" if actor.moving else "idle")),
		"alive":actor.alive,"weaponId":actor.weapon.definition.id,
		"shotSerial":actor.radar_shots,"shotAge":game_match.ui_time-actor.radar_last_shot,
		"shotX":actor.radar_shot_position.x,"shotY":actor.radar_shot_position.y,"shotZ":actor.radar_shot_position.z}

func local_death(victim, killer, weapon_id: String, headshot: bool) -> void:
	if owns(victim):
		client.send_death(victim.actor_id,killer.actor_id if killer else -1,weapon_id,headshot)

func _state_received(from: int, value: Dictionary) -> void:
	if remotes.has(from):
		remotes[from].apply_state(value)

func _bots_received(_from: int, values: Array) -> void:
	for value in values:
		var id := int(value.id)
		var actor = add_remote(id,str(value.team),"Bot %d" % id)
		actor.team = str(value.team)
		actor.apply_state(value)

func _hit_received(from: int, target: int, amount: float, headshot: bool, weapon_id: String) -> void:
	var actor = actor_by_id(target)
	if actor and owns(actor) and actor.alive:
		actor.apply_damage(amount,actor_by_id(from),weapon_id,headshot)

func _death_received(_from: int, victim_id: int, killer_id: int, weapon_id: String, headshot: bool) -> void:
	var victim = actor_by_id(victim_id)
	if victim:
		game_match.actor_killed(victim,actor_by_id(killer_id),weapon_id,headshot,true)
		if remotes.has(victim_id):
			remotes[victim_id].mark_dead()

func _peer_left(id: int) -> void:
	if not remotes.has(id):
		return
	var actor = remotes[id]
	game_match.radar.forget(id)
	game_match.actors.erase(actor)
	remotes.erase(id)
	actor.queue_free()

func _exit_tree() -> void:
	if not is_instance_valid(client):
		return
	for binding in [[client.state_received,_state_received],[client.bots_received,_bots_received],
		[client.hit_received,_hit_received],[client.death_received,_death_received],[client.peer_left,_peer_left],
		[client.lobby,_roster_received],[client.match_state_received,apply_match_state]]:
		if binding[0].is_connected(binding[1]):
			binding[0].disconnect(binding[1])
