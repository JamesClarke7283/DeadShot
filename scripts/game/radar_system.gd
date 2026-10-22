extends RefCounted
## Team intelligence stores last-known positions, never tracks hidden enemies.
const SHOT_LIFETIME := 2.5
const SPOT_LIFETIME := 1.2
const SCAN_INTERVAL := 0.15
const SPOT_RANGE := 100.0
var contacts: Dictionary = {}
var scan_timer := 0.0

func record_shot(actor, at: Vector3, now: float) -> void:
	if actor.alive:
		contacts[actor.actor_id] = {"position": at, "expire": now + SHOT_LIFETIME, "source": "shot"}

func forget(actor_id: int) -> void:
	contacts.erase(actor_id)

func tick(dt: float, game_match) -> void:
	var viewer = game_match.player
	if not viewer or not viewer.alive:
		return
	scan_timer -= dt
	if scan_timer > 0.0:
		return
	scan_timer = SCAN_INTERVAL
	for target in game_match.actors:
		if not target.alive or target == viewer or (viewer.team != "ffa" and target.team == viewer.team):
			continue
		for observer in game_match.actors:
			if not observer.alive or (observer != viewer and (viewer.team == "ffa" or observer.team != viewer.team)):
				continue
			if can_spot(observer, target, game_match):
				var previous: Dictionary = contacts.get(target.actor_id, {})
				contacts[target.actor_id] = {"position": target.position, "expire": maxf(game_match.ui_time + SPOT_LIFETIME, previous.get("expire", 0.0)), "source": "spotted"}
				break

func can_spot(observer, target, game_match) -> bool:
	var start: Vector3 = observer.eye_position()
	var end: Vector3 = target.eye_position()
	var offset := end - start
	var distance := offset.length()
	if distance > SPOT_RANGE or distance < 0.001:
		return false
	if observer.aim_direction().dot(offset / distance) < 0.65:
		return false
	if game_match.map.raycast_boxes(start, offset / distance, distance - 0.4) >= 0.0:
		return false
	# Include visible prop geometry as well as movement walls.
	var query := PhysicsRayQueryParameters3D.create(start, end, 2)
	if not game_match.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	if game_match.equipment:
		for item in game_match.equipment.items:
			if item.id == "smoke" and item.active and item.get("detonated", false):
				var closest := Geometry3D.get_closest_point_to_segment(item.effect_point + Vector3.UP, start, end)
				if closest.distance_to(item.effect_point + Vector3.UP) < 3.5:
					return false
	return true

func blips(game_match) -> Array:
	var result: Array = []
	var viewer = game_match.player
	for actor in game_match.actors:
		if actor == viewer:
			continue
		if not actor.alive:
			forget(actor.actor_id)
			continue
		var friendly: bool = viewer.team != "ffa" and actor.team == viewer.team
		if friendly:
			result.append({"id": actor.actor_id, "x": actor.position.x, "z": actor.position.z, "enemy": false, "source": "ally", "alpha": 1.0})
		elif contacts.has(actor.actor_id):
			var contact: Dictionary = contacts[actor.actor_id]
			if contact.expire <= game_match.ui_time:
				forget(actor.actor_id)
				continue
			result.append({"id": actor.actor_id, "x": contact.position.x, "z": contact.position.z, "enemy": true, "source": contact.source, "alpha": clampf((contact.expire - game_match.ui_time) / 0.7, 0.25, 1.0)})
	return result
