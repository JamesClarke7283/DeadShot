class_name WeaponRuntime
extends RefCounted
signal reload_started(empty:bool,duration:float)
## Original Weapon FSM: trigger edges, burst continuation, reload/swap timers, recoil.
const Data = preload("res://scripts/core/game_data.gd")
var definition: Dictionary
var stats: Dictionary
var attachments: Array
var magazine: int
var reserve: int
var state: String = "ready"
var ads_factor: float = 0.0
var trigger: bool = false
var last_trigger: bool = false
var cooldown: float = 0.0
var reload_timer: float = 0.0
var reload_duration: float = 0.0
var swap_timer: float = 0.0
var burst_remaining: int = 0
var recoil_pitch: float = 0.0
var shot_index: int = 0
var shots_fired: int = 0
var shot_muzzle := Vector3.ZERO
var shot_direction := Vector3.FORWARD
var _aim_origin := Vector3.ZERO
var _aim_direction := Vector3.FORWARD

func _init(weapon_id: String = "m4", selected: Array = []) -> void:
	definition = Data.weapon(weapon_id)
	attachments = selected.duplicate()
	stats = Data.stats(definition, attachments)
	magazine = int(stats.magazine)
	reserve = int(stats.reserve)

func reset_for_life() -> void:
	magazine=int(stats.magazine)
	reserve=int(stats.reserve)
	state="ready" if magazine>0 else "empty"
	ads_factor=0.0
	trigger=false
	last_trigger=false
	cooldown=0.0
	reload_timer=0.0
	reload_duration=0.0
	swap_timer=0.0
	burst_remaining=0
	recoil_pitch=0.0
	shot_index=0

func swap_in() -> void:
	state = "swapping"
	swap_timer = 0.4

func reload() -> bool:
	if state in ["reloading", "swapping"] or magazine >= stats.magazine or reserve <= 0:
		return false
	state = "reloading"
	reload_duration = float(stats.reloadTime)
	if magazine == 0:
		reload_duration = float(definition.get("reloadEmptyTime", reload_duration * 1.2))
	reload_timer = reload_duration
	reload_started.emit(magazine==0,reload_duration)
	return true

func tick(dt: float, actor, world) -> void:
	# Source Player caches Aim before Weapon.update, including recoil recovery.
	_aim_origin=actor.eye_position()
	_aim_direction=actor.aim_direction()
	if recoil_pitch > 0:
		var recovery = minf(recoil_pitch, deg_to_rad(float(stats.recoil.recovery)) * dt)
		recoil_pitch -= recovery
		actor.apply_recoil(-recovery, 0.0)
	cooldown = maxf(0.0, cooldown - dt)
	if state == "reloading":
		reload_timer -= dt
		if reload_timer <= 0:
			var take = mini(int(stats.magazine) - magazine, reserve)
			magazine += take
			reserve -= take
			state = "ready" if magazine > 0 else "empty"
		last_trigger = trigger
		return
	if state == "swapping":
		swap_timer -= dt
		if swap_timer <= 0:
			state = "ready" if magazine > 0 else "empty"
		last_trigger = trigger
		return
	var rising = trigger and not last_trigger
	if burst_remaining > 0:
		if cooldown <= 0 and magazine > 0:
			_fire(actor, world)
			burst_remaining -= 1
			cooldown = 60.0 / stats.fireRate
	elif (trigger if definition.fireMode == "auto" else rising) and cooldown <= 0:
		if magazine <= 0:
			if reserve > 0:
				reload()
			cooldown = 0.3
		else:
			if definition.fireMode == "burst":
				burst_remaining = int(definition.get("burstCount", 3)) - 1
			_fire(actor, world)
			cooldown = 60.0 / stats.fireRate
	if not trigger and burst_remaining == 0:
		shot_index = 0
	last_trigger = trigger

func _fire(actor, world) -> void:
	magazine -= 1
	shots_fired += 1
	shot_direction=_aim_direction
	shot_muzzle=_aim_origin+_aim_direction*0.4
	actor.on_shot()
	var multiplier = float(stats.recoil.firstShotMult) if shot_index == 0 else 1.0
	var pitch = deg_to_rad(float(stats.recoil.vertical)) * multiplier
	recoil_pitch += pitch
	shot_index += 1
	var origin: Vector3 = _aim_origin
	var direction: Vector3 = _aim_direction
	actor.apply_recoil(pitch, randf_range(-1.0, 1.0) * deg_to_rad(float(stats.recoil.horizontal)) * multiplier)
	if definition.has("rocket"):
		world.spawn_rocket(origin + direction * 0.4, direction, actor, definition.rocket)
	else:
		var spread = (0.06 if definition.category == "shotgun" else 0.012) * float(stats.spreadMult) * (1.0 - ads_factor * 0.85)
		for pellet in range(int(stats.get("pellets", 1))):
			world.fire_hitscan(actor, self, origin, perturb(direction, spread))
	if magazine <= 0:
		state = "empty"

static func perturb(direction: Vector3, spread: float) -> Vector3:
	if spread<=0.0:return direction
	var u = direction.cross(Vector3.UP)
	if u.length_squared() < 0.000001:
		u = Vector3.RIGHT
	u = u.normalized()
	var v = direction.cross(u).normalized()
	var angle = randf() * TAU
	var radius = tan(spread) * sqrt(randf())
	return (direction + u * cos(angle) * radius + v * sin(angle) * radius).normalized()
