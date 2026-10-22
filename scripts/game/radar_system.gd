extends RefCounted
## Live enemy locations remain visible through cover; shots add a timed pulse.
const SHOT_LIFETIME := 2.5
var contacts: Dictionary = {}

func record_shot(actor, at: Vector3, now: float) -> void:
	if actor.alive:
		contacts[actor.actor_id] = {"position": at, "expire": now + SHOT_LIFETIME, "source": "shot"}

func forget(actor_id: int) -> void:
	contacts.erase(actor_id)

func tick(_dt: float, game_match) -> void:
	for actor_id in contacts.keys():
		if contacts[actor_id].expire <= game_match.ui_time:
			forget(actor_id)

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
		var contact: Dictionary = contacts.get(actor.actor_id, {})
		var shot: bool = not friendly and float(contact.get("expire", 0.0)) > game_match.ui_time
		result.append({"id": actor.actor_id, "x": actor.position.x, "z": actor.position.z,
			"enemy": not friendly, "source": "ally" if friendly else ("shot" if shot else "enemy"),
			"alpha": 1.0, "shotAlpha": clampf((float(contact.get("expire", 0.0)) - game_match.ui_time) / 0.7, 0.0, 1.0)})
	return result

func indicators(game_match) -> Array:
	var result: Array = []
	var viewer = game_match.player
	if not viewer or not viewer.alive or not viewer.camera:
		return result
	var camera: Camera3D = viewer.camera
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return result
	for actor in game_match.actors:
		if actor == viewer or not actor.alive or (viewer.team != "ffa" and actor.team == viewer.team):
			continue
		var target: Vector3 = actor.global_position + Vector3.UP * (actor.eye_height + 0.35)
		var local := camera.to_local(target)
		var behind := camera.is_position_behind(target)
		var point: Vector2
		# Never project on the camera plane (division by zero), or mirror a rear
		# target onto the front of the screen. Rear contacts point toward its edge.
		if behind or absf(local.z) < 0.05:
			var bearing := Vector2(local.x, maxf(absf(local.z), 0.1)).normalized()
			point = viewport_size * 0.5 + bearing * viewport_size
			behind = true
		else:
			point = camera.unproject_position(target)
		result.append({"id": actor.actor_id, "point": point / viewport_size, "behind": behind,
			"distance": camera.global_position.distance_to(actor.global_position)})
	return result
