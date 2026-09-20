class_name StreakSystem
extends Node3D
## Earned score resets on death. Called-in streaks remain active in the world;
## available calls are still threshold-based and do not spend earned score.

const Visuals = preload("res://scripts/visuals/visual_factory.gd")
const DEFAULT_LOADOUT := ["uav", "care_package", "attack_heli"]
const AIRCRAFT := {
	"attack_heli": {"lifetime":30.0,"altitude":25.0,"radius":18.0,"angular":0.5,"interval":0.4,"damage":25.0,"targets":1},
	"gunship": {"lifetime":35.0,"altitude":30.0,"radius":22.0,"angular":0.35,"interval":0.4,"damage":40.0,"targets":1},
	"chopper_gunner": {"lifetime":35.0,"altitude":28.0,"radius":20.0,"angular":0.4,"interval":0.35,"damage":50.0,"targets":3},
}
var game_match
var definitions: Dictionary = {}
var active: Array = []
var pickups: Array = []
var pings: Array = []
var counter_uav: Dictionary = {}
var _loadouts: Dictionary = {}
var _active_owners: Dictionary = {}
var _time := 0.0
var _has_match_clock:=false
var _bot_timer := 0.0
var _rng := RandomNumberGenerator.new()

func setup(match_value) -> void:
	game_match = match_value
	for property in game_match.get_property_list():
		if property.name=="elapsed":_has_match_clock=true
	for record in JSON.parse_string(FileAccess.get_file_as_string("res://data/streaks.json")):
		definitions[str(record.id)] = record
	_rng.randomize()
	if game_match.player != null:
		set_loadout(game_match.player.actor_id, game_match.loadout.get("streaks", DEFAULT_LOADOUT))

func set_loadout(actor_id: int, streak_ids: Array) -> void:
	_loadouts[actor_id] = streak_ids.slice(0, 3)

func loadout_for(actor_id: int) -> Array:
	return _loadouts.get(actor_id, DEFAULT_LOADOUT)

func add_score(actor_id: int, amount: int) -> void:
	game_match.streak_scores[actor_id] = score_of(actor_id) + amount

func score_of(actor_id: int) -> int:
	return int(game_match.streak_scores.get(actor_id, 0))

func on_kill(killer, victim, headshot: bool) -> void:
	if killer != null and killer != victim:
		add_score(killer.actor_id, 125 if headshot else 100)

func reset(actor_id: int) -> void:
	game_match.streak_scores[actor_id]=0
	# Active ownership prevents calling the same streak twice while its prior
	# world instance is still running. Death clears earned progress only.

func is_available(actor_id: int, id: String) -> bool:
	return id in loadout_for(actor_id) and definitions.has(id) and score_of(actor_id) >= int(definitions[id].cost) and not _active_owners.get(actor_id, {}).has(id)

func best_available(actor_id: int) -> Dictionary:
	var best: Dictionary = {}
	for id in loadout_for(actor_id):
		if is_available(actor_id, id) and (best.is_empty() or int(definitions[id].cost) > int(best.cost)):
			best = definitions[id]
	return best

func hud(actor) -> Array:
	if actor == null:
		return []
	var result: Array = []
	var slot := 0
	for id in loadout_for(actor.actor_id):
		if definitions.has(id):
			result.append({"id":id,"name":definitions[id].name,"cost":definitions[id].cost,"score":score_of(actor.actor_id),"available":is_available(actor.actor_id,id),"active":_active_owners.get(actor.actor_id,{}).has(id),"slot":slot})
		slot += 1
	result.sort_custom(func(a,b): return int(a.cost) < int(b.cost))
	return result

func next_streak(actor) -> Dictionary:
	for record in hud(actor):
		if int(record.cost) > int(record.score):
			return record
	return {}

func activate(actor, id: String) -> bool:
	if actor == null or game_match.mode.id == "gungame" or not is_available(actor.actor_id, id):
		return false
	return _activate(actor, id)

func force_activate(actor, id: String) -> bool:
	## Developer console and care packages bypass score/loadout eligibility.
	return actor != null and _activate(actor, id)

func _activate(actor, id: String) -> bool:
	if not definitions.has(id):
		return false
	if id == "attack_heli":
		for entry in active:
			if entry.id == id:
				return false
	var entry := {"id":id,"owner":actor,"elapsed":0.0,"timer":0.0,"angle":0.0,"node":null,"done":false,"spawned":false}
	active.append(entry)
	if not _active_owners.has(actor.actor_id):
		_active_owners[actor.actor_id] = {}
	_active_owners[actor.actor_id][id] = true
	return true

func grant_random(actor) -> String:
	var pool: Array = []
	for id in definitions:
		if id not in ["care_package", "nuke"]:
			pool.append(id)
	var id: String = pool[_rng.randi_range(0, pool.size() - 1)]
	_activate(actor, id)
	return id

func tick(dt: float, manage_pickups: bool = true) -> void:
	if game_match == null or game_match.mode.id == "gungame":
		return
	_time = float(game_match.elapsed) if _has_match_clock else _time+dt
	if manage_pickups:
		tick_pickups(dt)
	for index in range(active.size() - 1, -1, -1):
		var entry: Dictionary = active[index]
		if not entry.spawned:
			_spawn(entry)
		_tick_entry(entry, dt)
		if entry.done:
			_finish(entry)
			active.remove_at(index)
	pings = pings.filter(func(p): return float(p.expire) > _time)
	_bot_timer -= dt
	if _bot_timer <= 0.0:
		_bot_timer = 2.0
		for actor in game_match.actors:
			if actor != game_match.player and actor.alive and actor.brain != null:
				var best := best_available(actor.actor_id)
				if not best.is_empty():
					_activate(actor, best.id)

func _center() -> Vector3:
	var bounds: Dictionary = game_match.map.bounds
	return Vector3((float(bounds.minX) + float(bounds.maxX)) / 2.0, 0.0, (float(bounds.minZ) + float(bounds.maxZ)) / 2.0)

func _ground(position_: Vector3) -> float:
	return float(game_match.map.height_at(position_.x, position_.z))

func _enemies(owner) -> Array:
	return game_match.actors.filter(func(actor): return actor.alive and actor.actor_id != owner.actor_id and (owner.team == "ffa" or owner.team != actor.team))

func _visual(id: String) -> Node3D:
	var result := Visuals.create_model(id)
	add_child(result)
	return result

func _spawn(entry: Dictionary) -> void:
	entry.spawned = true
	var id: String = entry.id
	var owner = entry.owner
	var center := _center()
	var owner_position: Vector3 = owner.body_position()
	if id == "counter_uav":
		counter_uav["red" if owner.team == "blue" else ("blue" if owner.team == "red" else "ffa")] = _time + 30.0
		return
	if id == "juggernaut":
		entry.original_scale = owner.human.scale if is_instance_valid(owner.human) else Vector3.ONE
		owner.max_health = 300.0
		owner.health = 300.0
		if is_instance_valid(owner.human):
			owner.human.scale = entry.original_scale * 1.2
		return
	if id == "strafe_run":
		entry.node = Node3D.new()
		add_child(entry.node)
		entry.jets = []
		entry.x = float(game_match.map.bounds.minX) - 20.0
		entry.hit = {}
		for i in 3:
			var jet := Visuals.create_model("strafe_jet")
			entry.node.add_child(jet)
			jet.position = Vector3(entry.x, 35.0, center.z + (i - 1) * 6.0)
			jet.rotation.y = -PI / 2.0
			entry.jets.append(jet)
		return
	entry.node = _visual("streak_" + id)
	match id:
		"uav":
			entry.node.position = Vector3(center.x, 60.0, center.z)
		"care_package":
			entry.drop = owner_position
			entry.ground = _ground(owner_position)
			entry.altitude = entry.ground + 26.0
			entry.dropped = false
			entry.crate = null
			entry.node.position = Vector3(float(game_match.map.bounds.minX) - 12.0, entry.altitude, owner_position.z)
		"sentry":
			owner_position.x += 1.5
			owner_position.y = _ground(owner_position)
			entry.node.position = owner_position
			entry.muzzle = owner_position + Vector3.UP * 0.55
		"rcxd":
			owner_position.y = _ground(owner_position) + 0.2
			entry.node.position = owner_position
		"predator":
			var enemies := _enemies(owner)
			var target := center
			if not enemies.is_empty():
				target = Vector3.ZERO
				for enemy in enemies:
					target += enemy.body_position()
				target /= float(enemies.size())
			entry.ground = _ground(target)
			entry.node.position = Vector3(target.x, entry.ground + 80.0, target.z)
		"attack_heli", "gunship", "chopper_gunner":
			entry.node.position = Vector3(center.x + AIRCRAFT[id].radius, AIRCRAFT[id].altitude, center.z)
		"nuke":
			entry.node.position = Vector3(center.x, _ground(center) + 2.0, center.z)

func _tick_entry(entry: Dictionary, dt: float) -> void:
	var id: String = entry.id
	var center := _center()
	var owner = entry.owner
	# UAV uses elapsed before increment in the original animation.
	if id == "uav":
		var radius := maxf(4.0, (float(game_match.map.bounds.maxX) - float(game_match.map.bounds.minX)) * 0.3)
		entry.node.position = Vector3(center.x + cos(entry.elapsed * 0.5) * radius, 60.0, center.z + sin(entry.elapsed * 0.5) * radius)
	entry.elapsed += dt
	entry.timer -= dt
	match id:
		"uav":
			if entry.timer <= 0.0:
				entry.timer = 0.5
				var positions: Array = []
				for enemy in _enemies(owner):
					positions.append(enemy.body_position())
				pings.append({"team":owner.team,"positions":positions,"expire":_time + 0.7})
			entry.done = entry.elapsed >= 25.0
		"counter_uav", "juggernaut":
			entry.done = entry.elapsed >= 30.0
		"care_package":
			_tick_care_package(entry, dt)
		"sentry":
			var target = _nearest(owner, entry.node.position, 35.0)
			if target != null:
				var target_position: Vector3 = target.body_position()
				var delta: Vector3 = target_position - entry.node.position
				Visuals.part(entry.node, "gun").rotation.y = atan2(delta.x, delta.z)
				if entry.timer <= 0.0:
					entry.timer = 0.2
					_damage(target, 18.0, owner)
					game_match.tracer(entry.muzzle, target_position)
					game_match.vfx.muzzle_flash(entry.muzzle,(target_position-entry.muzzle).normalized())
			entry.done = entry.elapsed >= 40.0
		"rcxd":
			var target = _nearest(owner, entry.node.position)
			if target != null:
				var delta: Vector3 = target.body_position() - entry.node.position
				delta.y = 0
				if delta.length() <= 3.0:
					_detonate(entry, 6.0, 150.0)
					return
				var step: Vector3 = delta.normalized() * 9.0 * dt
				entry.node.position += step
				entry.node.position.y = _ground(entry.node.position) + 0.2
				entry.node.rotation.y = atan2(delta.x, delta.z)
			if entry.elapsed >= 12.0:
				_detonate(entry, 6.0, 150.0)
		"predator":
			entry.node.position.y -= 45.0 * dt
			if entry.node.position.y <= entry.ground or entry.elapsed >= 5.0:
				entry.node.position.y = entry.ground
				_detonate(entry, 8.0, 200.0)
		"attack_heli", "gunship", "chopper_gunner":
			var config: Dictionary = AIRCRAFT[id]
			entry.angle += config.angular * dt
			entry.node.position = Vector3(center.x + cos(entry.angle) * config.radius, config.altitude, center.z + sin(entry.angle) * config.radius)
			entry.node.rotation.y = -entry.angle + PI / 2.0
			# The aircraft carry separate main and tail rotor pivots, matching the
			# care-package path below; the ported single `rotor` node was replaced
			# by that pair in the geometry rebuild.
			Visuals.part(entry.node, "mainRotor").rotation.y += dt * 30.0
			Visuals.part(entry.node, "tailRotor").rotation.x += dt * 34.0
			if entry.timer <= 0.0:
				entry.timer = config.interval
				var enemies := _enemies(owner)
				enemies.sort_custom(func(a,b): return a.body_position().distance_squared_to(entry.node.position) < b.body_position().distance_squared_to(entry.node.position))
				for enemy in enemies.slice(0, int(config.targets)):
					_damage(enemy, config.damage, owner)
					game_match.tracer(entry.node.position, enemy.body_position())
			entry.done = entry.elapsed >= config.lifetime
		"strafe_run":
			entry.x += 50.0 * dt
			for jet in entry.jets:
				jet.position.x = entry.x
			for enemy in _enemies(owner):
				if entry.hit.has(enemy.actor_id):
					continue
				var at: Vector3 = enemy.body_position()
				if absf(at.z - center.z) <= 12.0 and absf(at.x - entry.x) <= 8.0:
					entry.hit[enemy.actor_id] = true
					_damage(enemy, 80.0, owner)
					game_match.explode(at, 3.0, 0.0, owner, "streak")
			entry.done = entry.x >= float(game_match.map.bounds.maxX) + 20.0
		"nuke":
			var progress := minf(1.0, float(entry.elapsed) / 6.0)
			entry.node.scale = Vector3.ONE * (0.5 + progress * progress * 40.0)
			if entry.elapsed >= 6.0:
				entry.done = true
				game_match.end_match(owner.team,false)

func _nearest(owner, at: Vector3, radius: float = INF):
	var closest = null
	var best := radius * radius
	for enemy in _enemies(owner):
		var distance: float = enemy.body_position().distance_squared_to(at)
		if distance < best:
			best = distance
			closest = enemy
	return closest

func _damage(target, amount: float, owner) -> void:
	if target.alive and (owner.team == "ffa" or target.team != owner.team):
		target.apply_damage(amount, owner, "streak", false)

func _detonate(entry: Dictionary, radius: float, damage: float) -> void:
	game_match.explode(entry.node.position, radius, damage, entry.owner, "streak")
	entry.done = true

func _tick_care_package(entry: Dictionary, dt: float) -> void:
	Visuals.part(entry.node, "mainRotor").rotation.y += dt * 30.0
	Visuals.part(entry.node, "tailRotor").rotation.x += dt * 34.0
	entry.node.position.x += 22.0 * dt
	if not entry.dropped and entry.node.position.x >= entry.drop.x:
		entry.dropped = true
		entry.crate = _visual("care_crate")
		entry.crate.position = Vector3(entry.node.position.x, entry.altitude - 1.6, entry.drop.z)
	if is_instance_valid(entry.crate):
		entry.crate.position.y -= 14.0 * dt
		entry.crate.rotation.y += dt
		if entry.crate.position.y <= entry.ground + 0.6:
			arm_care_package(Vector3(entry.crate.position.x, entry.ground, entry.crate.position.z))
			entry.crate.queue_free()
			entry.crate = null
	entry.done = entry.dropped and entry.crate == null and entry.node.position.x > float(game_match.map.bounds.maxX) + 12.0

func arm_care_package(at: Vector3) -> void:
	var node := _visual("care_pickup")
	node.position = Vector3(at.x, _ground(at) + 0.6, at.z)
	pickups.append({"node":node,"expire":_clock() + 60.0})

func _clock()->float:
	return float(game_match.elapsed) if _has_match_clock else _time

func tick_pickups(dt: float) -> void:
	var player = game_match.player
	for index in range(pickups.size() - 1, -1, -1):
		var pickup: Dictionary = pickups[index]
		pickup.node.rotation.y += dt * 1.5
		var remove: bool = _clock() >= float(pickup.expire)
		if not remove:
			for actor in game_match.actors:
				if actor == player or not actor.alive or actor.brain == null:
					continue
				if _flat_distance(actor.position, pickup.node.position) < 2.5:
					grant_random(actor)
					remove = true
					break
		if remove:
			pickup.node.queue_free()
			pickups.remove_at(index)

func nearest_pickup(actor) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := 2.5
	for pickup in pickups:
		var distance := _flat_distance(actor.position, pickup.node.position)
		if distance < nearest_distance:
			nearest = pickup
			nearest_distance = distance
	return nearest

func collect_pickup(pickup: Dictionary, actor) -> void:
	if pickup.is_empty() or not pickups.has(pickup):
		return
	grant_random(actor)
	pickup.node.queue_free()
	pickups.erase(pickup)

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func active_pings(team: String) -> Array:
	if is_jammed(team):
		return []
	var result: Array = []
	for ping in pings:
		if ping.team == team and float(ping.expire) > _clock():
			result.append_array(ping.positions)
	return result

func is_jammed(team: String) -> bool:
	return float(counter_uav.get(team, 0.0)) > _clock()

func _finish(entry: Dictionary) -> void:
	if entry.id == "juggernaut":
		var owner = entry.owner
		if is_instance_valid(owner) and is_instance_valid(owner.human):
			owner.human.scale = entry.get("original_scale", Vector3.ONE)
		if is_instance_valid(owner) and owner.alive:
			owner.max_health = 100.0
			owner.health = minf(owner.health, 100.0)
	if is_instance_valid(entry.node):
		entry.node.queue_free()
	if is_instance_valid(entry.get("crate")):
		entry.crate.queue_free()
	if is_instance_valid(entry.owner):
		_active_owners.get(entry.owner.actor_id, {}).erase(entry.id)

func clear() -> void:
	for entry in active:
		_finish(entry)
	active.clear()
	for pickup in pickups:
		pickup.node.queue_free()
	pickups.clear()
	pings.clear()
	counter_uav.clear()

func _exit_tree() -> void:
	clear()
