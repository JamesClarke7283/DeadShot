extends SceneTree
## Export transparent weapon thumbnails for the Armory's gallery cards.
const Factory = preload("res://scripts/visuals/visual_factory.gd")
const OUTPUT := "res://assets/armory/weapons"
const WEAPONS := ["m4", "mp5", "m249", "mk14", "barrett", "spas12", "m9", "rpg7"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 240)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0, 0, 0, 0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b8c9df")
	environment.environment.ambient_light_energy = 0.85
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment.tonemap_exposure = 0.9
	viewport.add_child(environment)
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff1d8")
	key.light_energy = 1.8
	viewport.add_child(key)
	key.look_at_from_position(Vector3(1.2, 2.0, 1.5), Vector3.ZERO)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("9fc4ff")
	rim.light_energy = 1.25
	viewport.add_child(rim)
	rim.look_at_from_position(Vector3(-1.8, 0.8, 0.5), Vector3.ZERO)
	var camera := Camera3D.new()
	camera.fov = 48
	camera.near = 0.02
	viewport.add_child(camera)
	camera.make_current()
	for weapon_id in WEAPONS:
		var previous: Dictionary = Factory.environment
		Factory.environment = {}
		var weapon: Node3D = Factory.create_weapon(weapon_id, Color("66717c"), ["reddot", "foregrip"])
		Factory.environment = previous
		viewport.add_child(weapon)
		weapon.rotation.y = PI * 0.5
		var bounds := model_bounds(weapon)
		var centre := bounds.get_center()
		var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		weapon.position = -centre - Vector3(0, 0, maxf(0.35, extent * 0.92))
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var used := image.get_used_rect()
		if used.has_area():
			var cropped := image.get_region(used)
			cropped.save_png(OUTPUT.path_join(weapon_id + ".png"))
		else:
			image.save_png(OUTPUT.path_join(weapon_id + ".png"))
		weapon.queue_free()
		await process_frame
	print("ARMORY THUMBNAILS: exported %d transparent weapon renders" % WEAPONS.size())
	quit()

func model_bounds(model: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for child in model.get_children():
		if child is MeshInstance3D and child.visible:
			var box: AABB = child.transform * child.mesh.get_aabb()
			bounds = box if not found else bounds.merge(box)
			found = true
		elif child is Node3D:
			var nested := model_bounds(child)
			if nested.size != Vector3.ZERO or nested.position != Vector3.ZERO:
				bounds = nested if not found else bounds.merge(nested)
				found = true
	return bounds
