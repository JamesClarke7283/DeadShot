extends SceneTree
## Source parity regressions for player view, movement, ADS, and bot decisions.

const ACTOR = preload("res://scripts/game/combatant.gd")
const BRAIN = preload("res://scripts/game/bot_brain.gd")
const WEAPON = preload("res://scripts/game/weapon_runtime.gd")
var failures: Array[String] = []
var checks := 0

class FlatWorld extends RefCounted:
	var bounds := {"minX": -70.0, "maxX": 70.0, "minZ": -70.0, "maxZ": 70.0}
	func height_at(_x: float, _z: float) -> float: return 0.0
	func resolve_position(value: Vector3, _radius: float, _height: float) -> Vector3: return value
	func raycast_boxes(_origin: Vector3, _direction: Vector3, _distance: float) -> float: return -1.0

class CaptureNavigator extends RefCounted:
	var destination := Vector3.ZERO
	func path(_from: Vector3, to: Vector3) -> Array[Vector3]:
		destination = to
		return [to]

class TestMatch extends RefCounted:
	var map := FlatWorld.new()
	var actors: Array = []
	var navigator := CaptureNavigator.new()
	var goal: Dictionary = {}
	var shots := 0
	func objective_goal(_actor) -> Dictionary: return goal
	func shot_fired(_actor) -> void: shots += 1
	func fire_hitscan(_actor, _gun, _origin, _direction) -> void: pass
	func reload_started(_actor) -> void: pass
	func actor_damaged(_actor, _source, _amount) -> void: pass
	func actor_killed(_actor, _source, _weapon, _headshot) -> void: pass

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	for action in ["streaks", "weapon_primary", "weapon_secondary", "weapon_next", "ads", "fire", "reload", "back", "forward", "left", "right", "sprint", "crouch", "jump"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var game_match := TestMatch.new()
	var actor = ACTOR.new()
	actor.is_player = true
	actor.game_match = game_match
	actor.weapons = [WEAPON.new("m4")]
	actor.camera = Camera3D.new()
	actor.add_child(actor.camera)
	root.add_child(actor)
	actor.rotation.y = 1.25
	actor.camera.rotation.x = 0.23
	actor.camera.position.y = 0.45
	actor.spawn_at(Vector3(4, 0, 8), PI)
	_expect(is_equal_approx(actor.rotation.y, 1.25) and is_equal_approx(actor.camera.rotation.x, 0.23), "Respawn preserves player yaw and pitch")
	_expect(is_equal_approx(actor.camera.position.y, 1.7), "Respawn immediately restores standing eye height")
	actor.is_player = false
	actor.spawn_at(Vector3.ZERO, 0.7)
	_expect(is_equal_approx(actor.rotation.y, 0.7), "Bots use spawn pad yaw")
	actor.is_player = true
	actor.spawn_at(Vector3.ZERO)
	actor.rotation.y = 0.0
	actor.camera.rotation.x = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.action_press("fire")
	var before: int = actor.weapon.magazine
	actor._player_tick(1.0 / 60.0)
	_expect(actor.weapon.magazine == before - 1, "Player firing does not depend on pointer capture (controller parity)")
	Input.action_release("fire")
	actor.ads_factor = 0.0
	Input.action_press("ads")
	actor._player_tick(1.0 / 60.0)
	_expect(actor.weapon.ads_factor == 0.0 and actor.ads_factor > 0.0, "Weapon uses preceding viewmodel ADS fraction")
	Input.action_release("ads")
	actor.weapons = [WEAPON.new("knife")]
	actor.ads_factor = 0.8
	actor._player_tick(1.0 / 60.0)
	_expect(actor.ads_factor == 0.0, "Knife has no ADS transition")
	actor.weapons = [WEAPON.new("m4")]
	actor.position = Vector3.ZERO
	actor.rotation.y = 0.0
	actor.camera.rotation.x = 0.0
	Input.action_press("forward")
	actor._player_tick(1.0)
	var speed: float = 5.0 * actor.weapon.stats.mobility / 80.0
	_expect(is_equal_approx(actor.position.z, -speed), "Standing movement speed follows source weapon mobility")
	Input.action_release("forward")
	actor.stance = 0
	actor.position = Vector3.ZERO
	Input.action_press("right")
	actor._player_tick(1.0)
	_expect(is_equal_approx(actor.position.x, speed * 0.22), "Prone movement retains 22 percent standing speed")
	Input.action_release("right")
	var forward := Vector3(0.3, 0.4, -0.8).normalized()
	var noise := Vector2(0.2, -0.1)
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var expected := (forward + right * tan(noise.x) + up * tan(noise.y)).normalized()
	_expect(BRAIN.apply_aim_error(forward, noise).is_equal_approx(expected), "Bot aim error uses source tangent basis")
	_expect(BRAIN.apply_aim_error(Vector3.UP, Vector2.ZERO).is_equal_approx(Vector3.UP), "Near-vertical aim avoids a degenerate basis")
	var bot = ACTOR.new()
	bot.game_match = game_match
	bot.weapons = [WEAPON.new("m4")]
	root.add_child(bot)
	game_match.goal = {"x": 0.0, "z": 0.0, "radius": 6.0, "kind": "defend"}
	var brain = BRAIN.new("regular")
	seed(4097)
	var greatest_radius := 0.0
	for repetition in range(60):
		bot.position = Vector3.ZERO
		bot.path.clear()
		brain._patrol(bot, 0.0, game_match)
		greatest_radius = maxf(greatest_radius, game_match.navigator.destination.length())
	_expect(greatest_radius > 3.0 and greatest_radius <= 6.0, "On-station bots loiter across full objective radius")
	var greatest_approach_radius := 0.0
	for repetition in range(60):
		bot.position = Vector3(20, 0, 20)
		bot.path.clear()
		brain._patrol(bot, 0.0, game_match)
		greatest_approach_radius = maxf(greatest_approach_radius, game_match.navigator.destination.length())
	_expect(greatest_approach_radius <= 3.0, "Approaching bots select destinations inside half objective radius")
	bot.position = Vector3(7, 0, 9)
	bot.path.clear()
	brain._sidestep(bot, Vector3.FORWARD)
	_expect(bot.path.size() == 1 and bot.path.is_typed(), "Blocked bots retain a typed navigation path when sidestepping")
	if not bot.path.is_empty():
		_expect(is_equal_approx(bot.position.distance_to(bot.path[0]), 3.0), "Blocked bots sidestep three metres")
	actor.free()
	bot.free()
	for failure: String in failures: push_error(failure)
	print("ACTOR PARITY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
