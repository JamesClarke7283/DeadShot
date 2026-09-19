extends SceneTree
const EFFECTS := preload("res://scripts/ui/screen_effects.gd")
var effects: Control

func _initialize() -> void: call_deferred("capture")

func rectangle(position: Vector2, dimensions: Vector2, color: Color) -> void:
	var rect := ColorRect.new()
	root.add_child(rect)
	rect.position = position
	rect.size = dimensions
	rect.color = color

func capture() -> void:
	root.size = Vector2i(1280, 720)
	rectangle(Vector2.ZERO, Vector2(1280, 720), Color("203040"))
	rectangle(Vector2(256, 192), Vector2(256, 192), Color.WHITE)
	rectangle(Vector2(800, 0), Vector2(16, 720), Color.BLACK)
	rectangle(Vector2(20, 678), Vector2(240, 20), Color("1ce012"))
	effects = EFFECTS.new()
	root.add_child(effects)
	for kind in ["none", "stun", "damage", "scavenger", "flash"]:
		effects.clear()
		match kind:
			"stun": effects.apply_effect(kind, 0.6, 2.8)
			"damage": effects.apply_effect(kind, 0.6, 0.5)
			"scavenger": effects.apply_effect(kind, 0.25, 0.4)
			"flash":
				effects.apply_effect("stun", 0.6, 2.8)
				effects.apply_effect(kind, 0.8, 2)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/deadshot-effect-native-%s.png" % kind)
		print("Effect rendered: " + kind)
	quit()
