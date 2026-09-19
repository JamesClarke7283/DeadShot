extends Control
## Native multi-touch counterpart of src/ui/TouchControls.ts.
## Action names match the Godot InputMap; look_delta preserves source pixel deltas.
signal look_delta(delta: Vector2)
const UI := preload("res://scripts/ui/ui_theme.gd")
const BUTTONS := [
	{"label": "FIRE", "action": "fire", "offset": Vector2(-75, -165), "radius": 45.0},
	{"label": "ADS", "action": "ads", "offset": Vector2(-162, -182), "radius": 32.0},
	{"label": "R", "action": "reload", "offset": Vector2(-168, -88), "radius": 28.0},
	{"label": "JMP", "action": "jump", "offset": Vector2(-62, -62), "radius": 32.0},
	{"label": "LETH", "action": "lethal", "offset": Vector2(-238, -148), "radius": 28.0},
	{"label": "TAC", "action": "tactical", "offset": Vector2(-238, -78), "radius": 28.0},
]
var touches: Dictionary = {}
var held: Dictionary = {}
var movement := Vector2.ZERO
var move_pointer := -1
var look_pointer := -1
var blocked_top := 0.0
var face := UI.font(700)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func():
		if not visible:
			release_all())

func _draw() -> void:
	var center := Vector2(90, size.y - 90)
	draw_circle(center, 60, Color(1, 1, 1, 0.12))
	draw_arc(center, 59, 0, TAU, 64, Color(182.0 / 255, 1, 94.0 / 255, 0.5), 2, true)
	draw_circle(center + movement * 45, 25, Color(182.0 / 255, 1, 94.0 / 255, 0.7))
	for button in BUTTONS:
		var position: Vector2 = size + button.offset
		var pressed: bool = held.get(button.action, false)
		draw_circle(position, button.radius, Color(182.0 / 255, 1, 94.0 / 255, 0.5) if pressed else Color(1, 1, 1, 0.14))
		draw_arc(position, button.radius - 1, 0, TAU, 48, Color(1, 1, 1, 0.4), 2, true)
		var text_width := face.get_string_size(button.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(face, position + Vector2(-text_width * 0.5, 5), button.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.y < size.y * blocked_top:
				return
			_begin_touch(event.index, event.position)
		else:
			_end_touch(event.index)
		if touches.has(event.index) or not event.pressed:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and touches.has(event.index):
		if event.index == move_pointer:
			_move(event.position)
		elif event.index == look_pointer:
			look_delta.emit(event.relative)
		get_viewport().set_input_as_handled()

func _begin_touch(index: int, position: Vector2) -> void:
	for button in BUTTONS:
		if position.distance_to(size + button.offset) <= button.radius:
			touches[index] = button.action
			_set_action(button.action, true)
			return
	if move_pointer < 0 and position.distance_to(Vector2(90, size.y - 90)) <= 60:
		move_pointer = index
		touches[index] = "move"
		_move(position)
	elif look_pointer < 0 and position.x >= size.x * 0.45:
		look_pointer = index
		touches[index] = "look"

func _end_touch(index: int) -> void:
	if not touches.has(index):
		return
	var action: String = touches[index]
	touches.erase(index)
	if index == move_pointer:
		move_pointer = -1
		movement = Vector2.ZERO
		_apply_movement()
	elif index == look_pointer:
		look_pointer = -1
	elif not action in touches.values():
		_set_action(action, false)
	queue_redraw()

func _move(position: Vector2) -> void:
	movement = ((position - Vector2(90, size.y - 90)) / 45.0).limit_length(1)
	_apply_movement()
	queue_redraw()

func _apply_movement() -> void:
	_set_action("forward", movement.y < -0.3)
	_set_action("back", movement.y > 0.3)
	_set_action("left", movement.x < -0.3)
	_set_action("right", movement.x > 0.3)

func _set_action(action: String, pressed: bool) -> void:
	# Only release actions this overlay pressed, preserving idle keyboard input.
	if pressed and not held.get(action, false):
		held[action] = true
		if InputMap.has_action(action): Input.action_press(action)
	elif not pressed and held.get(action, false):
		held.erase(action)
		if InputMap.has_action(action): Input.action_release(action)
	queue_redraw()

func release_all() -> void:
	for action in held.keys():
		_set_action(action, false)
	touches.clear()
	move_pointer = -1
	look_pointer = -1
	movement = Vector2.ZERO
	queue_redraw()

func _exit_tree() -> void:
	release_all()
