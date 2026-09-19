extends SceneTree
## Reproducible visual review using the actual renderer.
## godot --path . --script res://scripts/world/snapshot_maps.gd

const WORLD = preload("res://scripts/world/map_world.gd")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var world = WORLD.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.05
	camera.far = 500.0
	root.add_child(camera)
	camera.make_current()
	DirAccess.make_dir_recursive_absolute("res://assets/maps/previews")
	for id in WORLD.MAP_IDS:
		world.load_map(id)
		camera.position = Vector3(0, 20, 50)
		camera.look_at(Vector3(0, 0, 0))
		for frame in range(10):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("res://assets/maps/previews/%s.png" % id)
		print("MAP RENDERED %s" % id)
	world.queue_free()
	camera.queue_free()
	await process_frame
	quit()
