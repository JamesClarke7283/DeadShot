class_name MatchObjectives
extends Node3D
## Exact Domination / CTF state machines from the original Objectives.ts.

const MATERIALS = preload("res://scripts/world/map_material.gd")
const DOM_RADIUS := 6.0
const DOM_CAPTURE_RATE := 0.5
const DOM_CAP := 200
const CTF_RADIUS := 2.2
const CTF_CAP := 3
const BLUE := 0x3b82f6ff
const RED := 0xef4444ff
const NEUTRAL := 0x9aa0a8ff
var kind := ""
var game_match
var points: Array[Dictionary] = []
var flags: Array[Dictionary] = []
var blue := 0
var red := 0
var tick_accumulator := 0.0

func setup(objective_kind: String, match_instance) -> void:
	kind = objective_kind
	game_match = match_instance
	blue = 0
	red = 0
	tick_accumulator = 0.0
	points.clear()
	flags.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if kind == "dom":
		_build_domination()
	elif kind == "ctf":
		_build_flags()

func tick(dt: float) -> void:
	if kind == "dom":
		_tick_domination(dt)
	elif kind == "ctf":
		_tick_flags()

func _tick_domination(dt: float) -> void:
	for point: Dictionary in points:
		var present := _count_in_radius(point.x, point.z, DOM_RADIUS)
		if present.blue > 0 and present.red == 0:
			point.progress = minf(1.0, point.progress + DOM_CAPTURE_RATE * dt)
		elif present.red > 0 and present.blue == 0:
			point.progress = maxf(-1.0, point.progress - DOM_CAPTURE_RATE * dt)
		var owner := "blue" if point.progress >= 1.0 else "red" if point.progress <= -1.0 else "neutral"
		if owner != point.owner:
			point.owner = owner
			var color := Color.hex(BLUE if owner == "blue" else RED if owner == "red" else NEUTRAL).srgb_to_linear()
			# Retint the disc's own material; the realistic shader reads its base
			# tone from `albedo_color`, and the disc keeps its concrete response.
			MATERIALS.retint(point.disc.material_override, color)
	tick_accumulator += dt
	while tick_accumulator >= 1.0:
		tick_accumulator -= 1.0
		for point: Dictionary in points:
			if point.owner == "blue": blue += 1
			elif point.owner == "red": red += 1

func _tick_flags() -> void:
	for flag: Dictionary in flags:
		var enemy_team := "red" if flag.team == "blue" else "blue"
		if flag.status == "carried":
			var carrier = _find_actor(flag.carrier)
			if carrier == null or not carrier.alive:
				if carrier != null: flag.pos = carrier.body_position()
				flag.status = "dropped"
				flag.carrier = -1
			else:
				flag.pos = carrier.body_position()
				flag.pos.y = game_match.map.height_at(flag.pos.x, flag.pos.z)
				var own := _flag_for(carrier.team)
				if not own.is_empty() and own.status == "home" and flag.pos.distance_to(own.home) < CTF_RADIUS:
					if carrier.team == "blue": blue += 1
					else: red += 1
					_return_home(flag)
		else:
			for actor in game_match.actors:
				if not actor.alive or actor.body_position().distance_to(flag.pos) > CTF_RADIUS:
					continue
				if actor.team == enemy_team:
					flag.status = "carried"
					flag.carrier = actor.actor_id
					break
				elif actor.team == flag.team and flag.status == "dropped":
					_return_home(flag)
					break
		flag.group.position = flag.pos

func hud() -> Dictionary:
	var state := {"kind": kind, "blue": blue, "red": red, "cap": CTF_CAP if kind == "ctf" else DOM_CAP}
	if kind == "dom":
		var values: Array[Dictionary] = []
		for point: Dictionary in points:
			values.append({"label": point.label, "owner": point.owner, "progress": (point.progress + 1.0) / 2.0})
		state.points = values
	elif kind == "ctf":
		var values: Array[Dictionary] = []
		for flag: Dictionary in flags:
			values.append({"team": flag.team, "status": flag.status})
		state.flags = values
	return state

func check_win(elapsed: float, time_limit: float) -> Dictionary:
	var cap := CTF_CAP if kind == "ctf" else DOM_CAP
	if blue >= cap or red >= cap:
		return {"over": true, "winner": "blue" if blue >= red else "red", "reason": "score"}
	if elapsed >= time_limit:
		var result := {"over": true, "reason": "time"}
		if blue != red: result.winner = "blue" if blue > red else "red"
		return result
	return {"over": false}

func goal_for(actor) -> Dictionary:
	if actor.team not in ["blue", "red"]:
		return {}
	var rank := int(floor(absf(actor.actor_id) / 2.0))
	if kind == "dom":
		var owned: Array[Dictionary] = []
		var wanted: Array[Dictionary] = []
		for point: Dictionary in points:
			if point.owner == actor.team: owned.append(point)
			else: wanted.append(point)
		if wanted.is_empty() or (not owned.is_empty() and rank % 3 == 0):
			if owned.is_empty(): return {}
			var point: Dictionary = owned[rank % owned.size()]
			return {"x": point.x, "z": point.z, "radius": DOM_RADIUS * 0.8, "kind": "defend"}
		var point: Dictionary = wanted[rank % wanted.size()]
		return {"x": point.x, "z": point.z, "radius": DOM_RADIUS * 0.6, "kind": "attack"}
	if kind == "ctf":
		var own := _flag_for(actor.team)
		var enemy := _flag_for("red" if actor.team == "blue" else "blue")
		if own.is_empty() or enemy.is_empty(): return {}
		if enemy.status == "carried" and enemy.carrier == actor.actor_id:
			return _goal(own.home, 1.2, "carry")
		if rank % 3 == 0:
			if own.status == "dropped": return _goal(own.pos, 1.2, "return")
			if own.status == "carried": return _goal(own.pos, 2.5, "chase")
			return _goal(own.home, 7.0, "defend")
		return _goal(enemy.pos, 4.0 if enemy.status == "carried" else 1.2, "attack")
	return {}

func _goal(position: Vector3, radius: float, goal_kind: String) -> Dictionary:
	return {"x": position.x, "z": position.z, "radius": radius, "kind": goal_kind}

func _find_actor(id: int):
	for actor in game_match.actors:
		if actor.actor_id == id:
			return actor
	return null

func _flag_for(team: String) -> Dictionary:
	for flag: Dictionary in flags:
		if flag.team == team: return flag
	return {}

func _return_home(flag: Dictionary) -> void:
	flag.status = "home"
	flag.carrier = -1
	flag.pos = flag.home

func _count_in_radius(x: float, z: float, radius: float) -> Dictionary:
	var result := {"blue": 0, "red": 0}
	for actor in game_match.actors:
		if not actor.alive: continue
		var dx: float = actor.position.x - x
		var dz: float = actor.position.z - z
		if dx * dx + dz * dz <= radius * radius and actor.team in ["blue", "red"]:
			result[actor.team] += 1
	return result

func _build_domination() -> void:
	var bounds: Dictionary = game_match.map.bounds
	var center_x: float = (bounds.minX + bounds.maxX) / 2.0
	var span_z: float = bounds.maxZ - bounds.minZ
	for index in range(3):
		var z: float = bounds.minZ + span_z * [0.28, 0.5, 0.72][index]
		var y: float = game_match.map.height_at(center_x, z)
		var disc := _cylinder(DOM_RADIUS, 0.2, 24, NEUTRAL, 0x1a1d22ff, "concrete")
		disc.position = Vector3(center_x, y + 0.1, z)
		add_child(disc)
		var pole := _cylinder(0.12, 3.0, 8, 0x20242bff)
		pole.position = Vector3(center_x, y + 1.6, z)
		add_child(pole)
		points.append({"label": ["A", "B", "C"][index], "x": center_x, "z": z, "progress": 0.0, "owner": "neutral", "disc": disc})

func _build_flags() -> void:
	var bounds: Dictionary = game_match.map.bounds
	var center_x: float = (bounds.minX + bounds.maxX) / 2.0
	for team in ["blue", "red"]:
		var z: float = bounds.minZ + 8.0 if team == "blue" else bounds.maxZ - 8.0
		var home := Vector3(center_x, game_match.map.height_at(center_x, z), z)
		var group := Node3D.new()
		group.name = team + "Flag"
		group.position = home
		var pole := _cylinder(0.08, 3.0, 8, 0x20242bff)
		pole.position.y = 1.5
		group.add_child(pole)
		var cloth := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.1, 0.7, 0.06)
		cloth.mesh = box
		cloth.material_override = _material(BLUE if team == "blue" else RED, 0x101418ff, "fabric")
		cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloth.position = Vector3(0.6, 2.4, 0.0)
		group.add_child(cloth)
		add_child(group)
		flags.append({"team": team, "home": home, "pos": home, "status": "home", "carrier": -1, "group": group})

func _cylinder(radius: float, height: float, segments: int, color: int, emissive: int = 0x000000ff, surface: String = "painted_metal") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color, emissive, surface)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func _material(color: int, emissive: int = 0x000000ff, surface: String = "painted_metal") -> ShaderMaterial:
	var base := Color.hex(color).srgb_to_linear()
	var glow := Color.hex(emissive).srgb_to_linear()
	return MATERIALS.create_material({"color": [base.r, base.g, base.b], "emissive": [glow.r, glow.g, glow.b], "surface": surface}, game_match.map.environment_data)
