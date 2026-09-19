extends SceneTree
const Gamepad := preload("res://scripts/input/gamepad.gd")
var failures: Array[String] = []
var observed: Dictionary = {}

class AimProbe:
	extends Node
	var pitch := 0.0
	var yaw := 0.0
	func apply_recoil(p: float, y: float) -> void:
		pitch += p
		yaw += y

class EventProbe:
	extends Node
	var events: Array = []
	func _input(event: InputEvent) -> void:
		if event is InputEventAction:
			events.append({"action": event.action, "pressed": event.pressed})

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	for action in ["forward", "back", "left", "right", "jump", "reload", "lethal", "tactical", "sprint", "streaks", "scoreboard", "pause", "ads", "fire", "crouch", "melee"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var gamepad := Gamepad.new()
	var aim := AimProbe.new()
	var probe := EventProbe.new()
	root.add_child(gamepad)
	root.add_child(aim)
	root.add_child(probe)
	await process_frame
	Input.action_press("forward")
	gamepad.poll_state(0.1, aim, [0, 0, 0, 0, 0, 0], {})
	check(Input.is_action_pressed("forward"), "Idle connected pad does not clear keyboard action")
	Input.action_release("forward")
	gamepad.poll_state(0.1, aim, [0.3, -0.3, 0.17, -0.179, 0, 0], {})
	check(not Input.is_action_pressed("right") and not Input.is_action_pressed("forward"), "Movement requires strictly greater than .3")
	check(aim.pitch == 0 and aim.yaw == 0, "Independent right-stick .18 deadzone is applied")
	gamepad.poll_state(0.25, aim, [0.31, -0.31, 0.5, -0.25, 0.6, 0.8], {JOY_BUTTON_Y: true, JOY_BUTTON_BACK: true, JOY_BUTTON_START: true, JOY_BUTTON_B: true, JOY_BUTTON_RIGHT_STICK: true})
	await process_frame
	check(Input.is_action_pressed("right") and Input.is_action_pressed("forward"), "Movement becomes digital above threshold")
	check(Input.is_action_pressed("ads") and Input.is_action_pressed("fire"), "LT/RT trigger ADS/fire")
	check(Input.is_action_pressed("streaks") and Input.is_action_pressed("scoreboard"), "Y selects streaks and Back shows scoreboard")
	check(not Input.is_action_pressed("crouch") and not Input.is_action_pressed("melee"), "B and R3 have no source mapping")
	check(is_equal_approx(aim.pitch, 0.175) and is_equal_approx(aim.yaw, -0.35), "Right stick rotates at 2.8 radians per second with source signs")
	check(probe.events.any(func(event): return event.action == "pause" and event.pressed), "Start emits a pause input event")
	var event_count := probe.events.size()
	gamepad.poll_state(0.0, aim, [0.31, -0.31, 0.5, -0.25, 0.6, 0.8], {JOY_BUTTON_Y: true, JOY_BUTTON_BACK: true, JOY_BUTTON_START: true})
	await process_frame
	check(probe.events.size() == event_count, "Held buttons do not emit duplicate press events")
	gamepad.poll_state(0.1, aim, [], {}, false)
	await process_frame
	check(gamepad.held.is_empty(), "Disconnect releases all pad-owned actions")
	for action in ["right", "forward", "ads", "fire", "streaks", "scoreboard", "pause"]:
		check(not Input.is_action_pressed(action), "Disconnect releases " + action)
	Input.action_press("reload")
	gamepad.poll_state(0.1, aim, [], {}, false)
	check(Input.is_action_pressed("reload"), "Disconnected pad does not clear keyboard action")
	Input.action_release("reload")
	gamepad.queue_free()
	aim.queue_free()
	probe.queue_free()
	await process_frame
	print("Native gamepad input verification: %s" % ("PASS" if failures.is_empty() else "%d failures" % failures.size()))
	quit(0 if failures.is_empty() else 1)
