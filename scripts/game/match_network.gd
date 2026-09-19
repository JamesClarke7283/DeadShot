extends Node
## The same ownership model as Match.ts: each peer owns its player; the host
## owns bots. Snapshots are cosmetic; hits go to the victim's owner to resolve.
const Remote = preload("res://scripts/game/remote_combatant.gd")
var game_match
var client
var is_host := false
var remotes: Dictionary = {}
var send_timer := 0.0

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

func snapshot(actor) -> Dictionary:
	var direction: Vector3 = actor.aim_direction()
	return {"x":actor.position.x,"y":actor.position.y,"z":actor.position.z,
		"yaw":atan2(direction.x,direction.z) if actor.is_player else actor.rotation.y,
		"anim":"die" if not actor.alive else ("shoot" if actor.firing else ("run" if actor.moving else "idle")),
		"alive":actor.alive,"weaponId":actor.weapon.definition.id}

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
	game_match.actors.erase(actor)
	remotes.erase(id)
	actor.queue_free()

func _exit_tree() -> void:
	if not is_instance_valid(client):
		return
	for binding in [[client.state_received,_state_received],[client.bots_received,_bots_received],
		[client.hit_received,_hit_received],[client.death_received,_death_received],[client.peer_left,_peer_left]]:
		if binding[0].is_connected(binding[1]):
			binding[0].disconnect(binding[1])
