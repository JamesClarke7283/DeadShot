extends "res://scripts/game/combatant.gd"
## Mirrors the source RemoteActor: only its owner changes health or simulates it.
var network
var target_position := Vector3.ZERO
var has_snapshot := false
var remote_animation := "idle"

func setup_remote(id_value: int, team_value: String, player_name: String, accent: int, owner_match, client) -> void:
	network = client
	setup(id_value, team_value, false, {"primary":{"weaponId":"m4","attachments":[]}}, owner_match)
	brain = null
	display_name = player_name
	human.free()
	human = Visuals.create_human(team, accent % 6)
	add_child(human)

func apply_state(value: Dictionary) -> void:
	target_position = Vector3(float(value.get("x",0)),float(value.get("y",0)),float(value.get("z",0)))
	if not has_snapshot:
		position = target_position
	has_snapshot = true
	rotation.y = float(value.get("yaw",0))
	aim_dir = Vector3(sin(rotation.y),0,cos(rotation.y))
	alive = bool(value.get("alive",true))
	var weapon_id := str(value.get("weaponId",""))
	if not weapon_id.is_empty() and weapon.definition.id != weapon_id:
		set_weapon(weapon_id)
	remote_animation = str(value.get("anim","idle"))
	moving = remote_animation == "run"
	firing = remote_animation == "shoot"

func mark_dead() -> void:
	alive = false
	remote_animation = "die"

func apply_damage(amount: float, _source, weapon_id: String, headshot: bool = false) -> void:
	if alive and is_instance_valid(network):
		network.send_hit(actor_id, amount, headshot, weapon_id)

func tick(dt: float) -> void:
	if has_snapshot:
		position = position.lerp(target_position,minf(1,dt*12))
	animation_time += dt
	if human:
		human.position = Vector3.ZERO
		Visuals.animate_human(human,remote_animation,animation_time,dt)
	visible = alive
