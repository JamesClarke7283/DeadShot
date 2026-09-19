extends Node
## Exact Xbox-style mapping from src/core/Gamepad.ts. The first connected pad
## drives digital movement (>0.3), independent 0.18 look deadzones and 2.8rad/s.
## InputEventAction transitions reach both Input polling and main's pause event.
const BUTTON_ACTIONS := {
	JOY_BUTTON_A: "jump", JOY_BUTTON_X: "reload",
	JOY_BUTTON_RIGHT_SHOULDER: "lethal", JOY_BUTTON_LEFT_SHOULDER: "tactical",
	JOY_BUTTON_LEFT_STICK: "sprint", JOY_BUTTON_Y: "streaks",
	JOY_BUTTON_BACK: "scoreboard", JOY_BUTTON_START: "pause",
}
var held: Dictionary = {}
var current_device := -1

func connected() -> bool:
	return not Input.get_connected_joypads().is_empty()

func poll(delta: float, player: Node = null) -> void:
	var devices := Input.get_connected_joypads()
	if devices.is_empty():
		current_device = -1
		release_all()
		return
	var device: int = devices[0]
	if current_device >= 0 and current_device != device:
		release_all()
	current_device = device
	var axes := [Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y), Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y), Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT), Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)]
	var buttons: Dictionary = {}
	for button in BUTTON_ACTIONS:
		buttons[button] = Input.is_joy_button_pressed(device, button)
	poll_state(delta, player, axes, buttons)

## Separate state entry point enables deterministic tests without physical pads.
func poll_state(delta: float, player: Node, axes: Array, buttons: Dictionary, present: bool = true) -> void:
	if not present:
		release_all()
		return
	var left_x := _deadzone(float(axes[0]) if axes.size() > 0 else 0.0)
	var left_y := _deadzone(float(axes[1]) if axes.size() > 1 else 0.0)
	var right_x := _deadzone(float(axes[2]) if axes.size() > 2 else 0.0)
	var right_y := _deadzone(float(axes[3]) if axes.size() > 3 else 0.0)
	_apply("forward", left_y < -0.3)
	_apply("back", left_y > 0.3)
	_apply("left", left_x < -0.3)
	_apply("right", left_x > 0.3)
	if is_instance_valid(player) and (right_x != 0 or right_y != 0):
		player.apply_recoil(-right_y * 2.8 * delta, -right_x * 2.8 * delta)
	_apply("ads", axes.size() > 4 and float(axes[4]) > 0.5)
	_apply("fire", axes.size() > 5 and float(axes[5]) > 0.5)
	for button in BUTTON_ACTIONS:
		_apply(BUTTON_ACTIONS[button], bool(buttons.get(button, false)))

func _deadzone(value: float) -> float:
	return 0.0 if absf(value) < 0.18 else value

func _apply(action: String, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	if pressed and not held.get(action, false):
		held[action] = true
		_emit_action(action, true)
	elif not pressed and held.get(action, false):
		held.erase(action)
		# Native InputMap keyboard events remain authoritative when a keyboard
		# key is still physically held as a controller button is released.
		if not _physical_binding_held(action):
			_emit_action(action, false)
	elif pressed and not Input.is_action_pressed(action):
		# A simultaneous keyboard release can clear Godot's synthetic action;
		# restore the still-held pad action without emitting duplicate presses.
		Input.action_press(action)

func _physical_binding_held(action: String) -> bool:
	for binding in InputMap.action_get_events(action):
		if binding is InputEventKey:
			if binding.physical_keycode != 0 and Input.is_physical_key_pressed(binding.physical_keycode):
				return true
			if binding.keycode != 0 and Input.is_key_pressed(binding.keycode):
				return true
		elif binding is InputEventMouseButton and Input.is_mouse_button_pressed(binding.button_index):
			return true
	return false

func _emit_action(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)

func release_all() -> void:
	for action in held.keys():
		_apply(action, false)

func _exit_tree() -> void:
	release_all()
