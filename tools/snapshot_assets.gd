extends SceneTree
## Renders the actual game assets through the real material system, so the
## geometry rebuild can be reviewed rather than assumed.
##
## godot --path . --script res://tools/snapshot_assets.gd

const VisualFactory = preload("res://scripts/visuals/visual_factory.gd")
const MapMaterial = preload("res://scripts/world/map_material.gd")
const Quality = preload("res://scripts/world/graphics_quality.gd")

const OUTPUT := "res://assets/models/previews"

func _initialize() -> void:
	call_deferred("_capture")

func _environment() -> Environment:
	var environment := Environment.new()
	# The Compatibility renderer does not honour BG_COLOR reliably here, and a
	# real sky is what the game itself renders against, so the preview uses the
	# project's own sky shader. That also supplies the reflected light.
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ShaderMaterial.new()
	environment.sky.sky_material.shader = preload("res://scripts/world/sky.gdshader")
	environment.sky.sky_material.set_shader_parameter("zenith_color", Vector3(0.11, 0.16, 0.26))
	environment.sky.sky_material.set_shader_parameter("horizon_color", Vector3(0.30, 0.34, 0.40))
	environment.sky.sky_material.set_shader_parameter("ground_color", Vector3(0.09, 0.09, 0.10))
	environment.sky.sky_material.set_shader_parameter("sun_color", Vector3(1.0, 0.94, 0.84))
	environment.sky.sky_material.set_shader_parameter("sun_direction", Vector3(0.4, 0.5, 0.6).normalized())
	environment.sky.sky_material.set_shader_parameter("sun_energy", 6.0)
	environment.sky.sky_material.set_shader_parameter("ground_fade", 0.06)
	environment.sky.sky_material.set_shader_parameter("horizon_softness", 1.1)
	environment.sky.sky_material.set_shader_parameter("ground_mix", 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("93a6bd")
	environment.ambient_light_energy = 1.8
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.9
	environment.tonemap_white = 3.0
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.3
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_hdr_threshold = 1.5
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	return environment

func _capture() -> void:
	Quality.set_current("ultra")
	root.size = Vector2i(1400, 800)
	var world := Node3D.new()
	root.add_child(world)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment()
	world.add_child(world_environment)
	# Without a camera of its own the viewport keeps Godot's default clear
	# colour, which is what the first pass rendered against.
	var camera := Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.01
	camera.far = 100.0
	camera.environment = _environment()
	world.add_child(camera)
	camera.make_current()
	for entry in [["key", Color("fff2df"), Vector3(1.6, 2.4, 1.8)],
			["fill", Color("9fc0ea"), Vector3(-2.2, 0.6, 1.4)],
			["rim", Color("ffe9c8"), Vector3(-0.4, 1.4, -2.6)]]:
		var light := DirectionalLight3D.new()
		light.name = str(entry[0])
		light.light_color = entry[1]
		light.light_energy = 1.1
		light.shadow_enabled = true
		world.add_child(light)
		light.look_at_from_position(entry[2] as Vector3, Vector3.ZERO, Vector3.UP)
	DirAccess.make_dir_recursive_absolute(OUTPUT)

	for weapon_id in ["m4", "mp5", "m249", "mk14", "barrett", "spas12", "m9", "rpg7", "knife"]:
		var holder := Node3D.new()
		world.add_child(holder)
		var weapon: Node3D = VisualFactory.create_weapon(weapon_id, Color("2b2f36"),
				["reddot", "suppressor", "foregrip"])
		holder.add_child(weapon)
		_frame(camera, weapon, Vector3(0.75, 0.35, 0.62), 1.0)
		await _settle(8)
		await _save("%s/weapon_%s.png" % [OUTPUT, weapon_id])
		holder.queue_free()
		await process_frame

	for team in ["blue", "red", "ffa"]:
		var human: Node3D = VisualFactory.create_human(team, 3)
		world.add_child(human)
		_frame(camera, human, Vector3(0.55, 0.06, 0.84), 1.0)
		await _settle(8)
		await _save("%s/human_%s.png" % [OUTPUT, team])
		human.queue_free()
		await process_frame

	# Close-ups so the facial, helmet and rifle detail is reviewable.
	var face: Node3D = VisualFactory.create_human("blue", 3)
	world.add_child(face)
	_frame(camera, face, Vector3(0.40, 0.10, 0.91), 1.0, Vector3(0, 1.76, 0), Vector3(0.14, 0.0, 0.10))
	await _settle(8)
	await _save("%s/human_face.png" % OUTPUT)
	face.queue_free()
	await process_frame

	for equipment_id in ["throwing_knife", "frag", "claymore", "c4"]:
		var item: Node3D = VisualFactory.create_equipment(equipment_id, "blue")
		world.add_child(item)
		_frame(camera, item, Vector3(0.62, 0.42, 0.66), 1.0)
		await _settle(8)
		await _save("%s/equipment_%s.png" % [OUTPUT, equipment_id])
		item.queue_free()
		await process_frame

	for streak_id in ["uav", "sentry", "predator", "care_crate"]:
		var streak: Node3D = VisualFactory.create_streak(streak_id)
		world.add_child(streak)
		_frame(camera, streak, Vector3(0.62, 0.34, 0.71), 1.0)
		await _settle(8)
		await _save("%s/streak_%s.png" % [OUTPUT, streak_id])
		streak.queue_free()
		await process_frame

	print("ASSET SNAPSHOTS: wrote previews to %s" % OUTPUT)
	quit()

## Frames the node's real world bounds, so nothing depends on guessed sizes.
## `margin` scales the exact fit distance derived from the camera's half-angle.
func _frame(camera: Camera3D, node: Node3D, direction: Vector3, margin: float,
		centre_override: Vector3 = Vector3.INF, look_override: Vector3 = Vector3.INF) -> void:
	var box := _world_bounds(node)
	var centre := box.get_center() if centre_override == Vector3.INF else centre_override
	var look := centre if look_override == Vector3.INF else centre + look_override
	var radius := maxf(box.size.length() * 0.5, 0.05)
	var half_fov := deg_to_rad(camera.fov * 0.5)
	camera.position = centre + direction.normalized() * (radius / sin(half_fov) * margin)
	camera.look_at(look)

func _world_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in _meshes(node):
		var local: AABB = child.get_aabb()
		var corners := [
			Vector3(local.position.x, local.position.y, local.position.z),
			Vector3(local.end.x, local.position.y, local.position.z),
			Vector3(local.position.x, local.end.y, local.position.z),
			Vector3(local.position.x, local.position.y, local.end.z),
			Vector3(local.end.x, local.end.y, local.position.z),
			Vector3(local.end.x, local.position.y, local.end.z),
			Vector3(local.position.x, local.end.y, local.end.z),
			Vector3(local.end.x, local.end.y, local.end.z),
		]
		for corner in corners:
			var point: Vector3 = child.global_transform * corner
			if first:
				box = AABB(point, Vector3.ZERO)
				first = false
			else:
				box = box.expand(point)
	return box

func _meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).visible:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found

func _settle(frames: int) -> void:
	for _index in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw

func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("ASSET RENDERED %s" % path)
