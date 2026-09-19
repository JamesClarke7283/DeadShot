class_name MapWorld
extends Node3D
## Original arenas reconstructed from exported Three geometry; no JS at runtime.
## Coordinates, colliders, spawns and waypoint graph are kept in source units.

const MATERIALS = preload("res://scripts/world/map_material.gd")
const QUALITY = preload("res://scripts/world/graphics_quality.gd")
const MAP_IDS: Array[String] = ["desert_town", "forest_facility", "urban_docks"]
var map_id: String = ""
var map_name: String = ""
var spawn_points: Array[Dictionary] = []
var nav_points: Array[Dictionary] = []
var collision_boxes: Array[AABB] = []
var bounds: Dictionary = {}
var environment_data: Dictionary = {}
var terrain_data: Dictionary = {}
var navigation := AStar3D.new()
var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var mesh_instance_count: int = 0
var _mesh_cache: Dictionary = {}
var _source_materials: Dictionary = {}
var _material_hints: Dictionary = {}
var _materials: Dictionary = {}
var _wind_materials: Array[ShaderMaterial] = []

func load_map(id: String) -> bool:
	var path := "res://data/maps/%s.json" % id
	if not FileAccess.file_exists(path):
		push_error("Unknown DeadShot map: %s" % id)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Invalid DeadShot map data: %s" % path)
		return false
	var data: Dictionary = parsed
	clear_map()
	map_id = str(data.get("id", id))
	map_name = str(data.get("name", id))
	name = "MapWorld"
	bounds = data.get("bounds", {})
	environment_data = data.get("environment", {})
	terrain_data = data.get("terrain", {})
	_build_environment()
	for key: String in data["geometries"]:
		_mesh_cache[key] = _make_mesh(data["geometries"][key])
	# Exported outline hulls are the cartoon look and are dropped entirely, so
	# they cost neither draw calls nor shadow casters.
	_source_materials = data["materials"]
	for key: String in data["materials"]:
		if bool(data["materials"][key].get("outline", false)):
			continue
		_material_hints[key] = _surface_hint(key, data)
		_materials[key] = MATERIALS.create_material(data["materials"][key], environment_data, _material_hints[key])
		if float(data["materials"][key].get("windStrength", 0.0)) > 0.0:
			_wind_materials.append(_materials[key])
	var batches: Dictionary = {}
	for record: Dictionary in data["nodes"]:
		if not bool(record.get("visible", true)) or bool(data["materials"][record["material"]].get("outline", false)):
			continue
		mesh_instance_count += 1
		if bool(record.get("instanced", false)):
			var key := "%s_%s" % [record["geometry"], record["material"]]
			if not batches.has(key):
				batches[key] = []
			batches[key].append(record)
		else:
			_add_mesh(record)
	for key: String in batches:
		_add_instances(batches[key])
	_build_bullet_geometry(data)
	var bodies := StaticBody3D.new()
	bodies.name = "OriginalCollisionBoxes"
	bodies.collision_layer = 1
	bodies.collision_mask = 0
	add_child(bodies)
	for record: Dictionary in data["collisionBoxes"]:
		var minimum := vector_from_array(record["min"])
		var maximum := vector_from_array(record["max"])
		var box := AABB(minimum, maximum - minimum)
		collision_boxes.append(box)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		collision.shape = shape
		collision.position = box.get_center()
		bodies.add_child(collision)
	for record: Dictionary in data["spawns"]:
		spawn_points.append({"position": vector_from_array(record["position"]), "yaw": float(record["yaw"]), "team": str(record["team"])})
	for record: Dictionary in data["waypoints"]:
		var point := {"id": int(record["id"]), "position": vector_from_array(record["position"]), "neighbors": record["neighbors"]}
		nav_points.append(point)
		navigation.add_point(point.id, point.position)
	for point: Dictionary in nav_points:
		for neighbor: Variant in point.neighbors:
			if not navigation.are_points_connected(point.id, int(neighbor), false):
				navigation.connect_points(point.id, int(neighbor), false)
	return true

## Rebuilds every surface material for a new quality tier and re-applies the
## lighting cost. Existing mesh instances keep their transforms, so this is safe
## to run mid-match.
func apply_quality(level: String = "") -> void:
	var resolved := QUALITY.set_current(level)
	if world_environment and world_environment.environment:
		QUALITY.apply_environment(world_environment.environment, sun, resolved)
	# Re-read the material source table so the rebuild uses the same profiles.
	if _source_materials.is_empty():
		return
	_materials.clear()
	for key: String in _source_materials:
		_materials[key] = MATERIALS.create_material(_source_materials[key], environment_data, _material_hints.get(key, ""))
	_retarget_materials(get_children())

## Walks the tree and points every instance at the rebuilt material for its key.
func _retarget_materials(nodes: Array) -> void:
	for node: Node in nodes:
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			var key: String = str(node.get_meta("material_key", ""))
			if _materials.has(key):
				node.material_override = _materials[key]
		_retarget_materials(node.get_children())

func clear_map() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	spawn_points.clear()
	nav_points.clear()
	collision_boxes.clear()
	navigation.clear()
	_mesh_cache.clear()
	_materials.clear()
	_material_hints.clear()
	_wind_materials.clear()
	mesh_instance_count = 0

func update_wind(elapsed: float) -> void:
	# The source animation clock is match elapsed time, which pauses in menus,
	# warmup and replay. Shader TIME would incorrectly keep foliage moving.
	for material: ShaderMaterial in _wind_materials:
		material.set_shader_parameter("wind_time", elapsed)

func height_at(x: float, z: float) -> float:
	if terrain_data.get("kind", "flat") == "flat":
		return 0.0
	var h := sin(x * 0.05) * cos(z * 0.045) + 0.5 * sin(x * 0.11 + 1.3) * cos(z * 0.1 - 0.7) + 0.25 * sin(x * 0.21 - 0.4) * cos(z * 0.19 + 0.9)
	return h / 1.75 * float(terrain_data.get("amplitude", 3.0))

func spawns_for_team(team: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point: Dictionary in spawn_points:
		if point.team == team:
			result.append(point)
	return result if not result.is_empty() else spawn_points

func path_between(from: Vector3, to: Vector3) -> PackedVector3Array:
	if navigation.get_point_count() == 0:
		return PackedVector3Array()
	return navigation.get_point_path(navigation.get_closest_point(from), navigation.get_closest_point(to))

func point_free(x: float, z: float, clearance: float = 0.5) -> bool:
	var y := height_at(x, z)
	for box: AABB in collision_boxes:
		if box.end.y <= y + 0.3 or box.position.y >= y + 1.7:
			continue
		if x >= box.position.x - clearance and x <= box.end.x + clearance and z >= box.position.z - clearance and z <= box.end.z + clearance:
			return false
	return true

func resolve_position(pos: Vector3, radius: float, height: float) -> Vector3:
	pos.y = maxf(pos.y, height_at(pos.x, pos.z))
	var feet_y := pos.y
	var head_y := pos.y + height
	for iteration in range(2):
		for box: AABB in collision_boxes:
			if box.end.y <= feet_y + 0.25 or box.position.y >= head_y:
				continue
			var closest_x := clampf(pos.x, box.position.x, box.end.x)
			var closest_z := clampf(pos.z, box.position.z, box.end.z)
			var dx := pos.x - closest_x
			var dz := pos.z - closest_z
			var distance_squared := dx * dx + dz * dz
			if distance_squared > radius * radius:
				continue
			if distance_squared > 0.00000001:
				var distance := sqrt(distance_squared)
				pos.x += dx / distance * (radius - distance)
				pos.z += dz / distance * (radius - distance)
			else:
				var edges := [pos.x - box.position.x, box.end.x - pos.x, pos.z - box.position.z, box.end.z - pos.z]
				var minimum: float = edges.min()
				if minimum == edges[0]: pos.x = box.position.x - radius
				elif minimum == edges[1]: pos.x = box.end.x + radius
				elif minimum == edges[2]: pos.z = box.position.z - radius
				else: pos.z = box.end.z + radius
	pos.y = maxf(pos.y, height_at(pos.x, pos.z))
	return pos

func raycast_boxes(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	var best := max_distance + 1.0
	for box: AABB in collision_boxes:
		var near_t := -INF
		var far_t := INF
		var missed := false
		for axis in range(3):
			if absf(direction[axis]) < 0.00000001:
				if origin[axis] < box.position[axis] or origin[axis] > box.end[axis]:
					missed = true
					break
				continue
			var first := (box.position[axis] - origin[axis]) / direction[axis]
			var second := (box.end[axis] - origin[axis]) / direction[axis]
			near_t = maxf(near_t, minf(first, second))
			far_t = minf(far_t, maxf(first, second))
			if near_t > far_t:
				missed = true
				break
		if missed or far_t < 0.0:
			continue
		var distance := near_t if near_t >= 0.0 else far_t
		if distance <= max_distance:
			best = minf(best, distance)
	return best if best <= max_distance else -1.0

static func vector_from_array(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

## The authored palettes pack colours as `0xRRGGBB` integers; the surface and sky
## code reads linear `[r, g, b]` arrays. Arrays pass through unchanged so both
## encodings work.
static func _color_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is int or value is float:
		var color := Color(int(value))
		return [color.r, color.g, color.b]
	return value

## Materials are shared by many nodes, so the surface profile is chosen from the
## most common node name that uses them rather than from materials alone.
func _surface_hint(material_key: String, data: Dictionary) -> String:
	var counts: Dictionary = {}
	for record: Dictionary in data["nodes"]:
		if str(record["material"]) != material_key:
			continue
		var name := str(record["name"])
		counts[name] = int(counts.get(name, 0)) + 1
	var best := ""
	var best_count := 0
	for name: String in counts:
		if int(counts[name]) > best_count:
			best = name
			best_count = int(counts[name])
	return best

static func transform_from_array(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[4], values[5], values[6]), Vector3(values[8], values[9], values[10])), Vector3(values[12], values[13], values[14]))

static func _make_mesh(record: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var positions: Array = record["positions"]
	var source_normals: Array = record.get("normals", [])
	var source_uvs: Array = record.get("uvs", [])
	for i in range(0, positions.size(), 3):
		vertices.append(Vector3(positions[i], positions[i + 1], positions[i + 2]))
	for i in range(0, source_normals.size(), 3):
		normals.append(Vector3(source_normals[i], source_normals[i + 1], source_normals[i + 2]))
	for i in range(0, source_uvs.size(), 2):
		uvs.append(Vector2(source_uvs[i], source_uvs[i + 1]))
	var source_indices: Array = record.get("indices", [])
	if source_indices.is_empty():
		for i in range(vertices.size()): source_indices.append(i)
	var indices := PackedInt32Array()
	# Godot front faces are clockwise; source Three indices are counterclockwise.
	for i in range(0, source_indices.size(), 3):
		indices.append(int(source_indices[i]))
		indices.append(int(source_indices[i + 2]))
		indices.append(int(source_indices[i + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	if not normals.is_empty(): arrays[Mesh.ARRAY_NORMAL] = normals
	if not uvs.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_mesh(record: Dictionary) -> void:
	var instance := MeshInstance3D.new()
	instance.name = str(record["name"]).validate_node_name()
	instance.mesh = _mesh_cache[record["geometry"]]
	instance.material_override = _materials[record["material"]]
	instance.set_meta("material_key", record["material"])
	instance.transform = transform_from_array(record["matrix"])
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(record.get("castShadow", false)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	if record["name"] == "terrain":
		var body := StaticBody3D.new()
		body.name = "TerrainCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = instance.mesh.create_trimesh_shape()
		body.add_child(collision)
		instance.add_child(body)

func _add_instances(records: Array) -> void:
	var record: Dictionary = records[0]
	var instance := MultiMeshInstance3D.new()
	instance.name = str(record["name"]).validate_node_name() + "_batch"
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = _mesh_cache[record["geometry"]]
	multi.instance_count = records.size()
	for i in range(records.size()):
		multi.set_instance_transform(i, transform_from_array(records[i]["matrix"]))
	instance.multimesh = multi
	instance.material_override = _materials[record["material"]]
	instance.set_meta("material_key", record["material"])
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(record.get("castShadow", false)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 0.3
	add_child(instance)
	# Foliage now casts its own swaying shadow: the surface shader performs the
	# same vertex displacement in the shadow pass, so no static proxy is needed.

func _build_bullet_geometry(data: Dictionary) -> void:
	# Three bullets intersect every visible mesh (including foliage, roof, glass
	# and decorations), while movement uses only the explicit source AABBs.
	# Shader-only wind never changed the original CPU raycast vertices.
	var faces := PackedVector3Array()
	var double_faces := PackedVector3Array()
	for record: Dictionary in data["nodes"]:
		var material: Dictionary = data["materials"][record["material"]]
		if bool(material.get("outline", false)) or not bool(record.get("visible", true)):
			continue
		var geometry: Dictionary = data["geometries"][record["geometry"]]
		var positions: Array = geometry["positions"]
		var indices: Array = geometry["indices"]
		if indices.is_empty():
			indices = range(positions.size() / 3)
		var transform := transform_from_array(record["matrix"])
		var mesh_faces := PackedVector3Array()
		for i in range(0, indices.size(), 3):
			for vertex_index: int in [int(indices[i]), int(indices[i + 2]), int(indices[i + 1])]:
				var offset := vertex_index * 3
				mesh_faces.append(transform * Vector3(positions[offset], positions[offset + 1], positions[offset + 2]))
		if bool(material.get("doubleSide", false)):
			double_faces.append_array(mesh_faces)
		else:
			faces.append_array(mesh_faces)
	var body := StaticBody3D.new()
	body.name = "OriginalBulletGeometry"
	body.collision_layer = 2
	body.collision_mask = 0
	for batch: PackedVector3Array in [faces, double_faces]:
		if batch.is_empty():
			continue
		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = batch == double_faces
		shape.set_faces(batch)
		collision.shape = shape
		body.add_child(collision)
	add_child(body)

func _build_environment() -> void:
	# The authored palette (packed 0xRRGGBB) is authoritative for the keys it
	# defines, and the per-map environment block (Three's linear values) supplies
	# the rest — notably `fogColor` and `background`, which the authored palette
	# does not carry. Replacing the block outright discarded that authored haze
	# and fell back to a generic cool grey fog on every map.
	var authored: Dictionary = environment_data.get("authoredLighting", {})
	if not authored.is_empty():
		var merged: Dictionary = environment_data.duplicate()
		for key in authored:
			merged[key] = _color_array(authored[key]) if key in ["skyColor", "groundColor", "sunColor"] else authored[key]
		environment_data = merged
	var background := MATERIALS.color_from_array(environment_data.get("background", [0.55, 0.66, 0.8]))
	var sky_tone := MATERIALS.color_from_array(environment_data.get("skyColor", [0.52, 0.77, 1.0]))
	var ground_tone := MATERIALS.color_from_array(environment_data.get("groundColor", [0.07, 0.1, 0.04]))
	var sun_tone := MATERIALS.color_from_array(environment_data.get("sunColor", [1.0, 0.9, 0.75]))
	# Aerial haze tends toward the sky's own radiance. Using the map's raw fog
	# colour left fully-fogged distant terrain a different tone from the sky at
	# the horizon, which read as a hard band across the map edge.
	var haze := MATERIALS.color_from_array(environment_data.get("fogColor", [0.7, 0.72, 0.75])).lerp(sky_tone, 0.55)
	environment_data["fogColor"] = [haze.r, haze.g, haze.b]

	world_environment = WorldEnvironment.new()
	world_environment.name = "MapEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ShaderMaterial.new()
	environment.sky.sky_material.shader = preload("res://scripts/world/sky.gdshader")
	environment.sky.sky_material.set_shader_parameter("zenith_color", Vector3(sky_tone.r, sky_tone.g, sky_tone.b))
	environment.sky.sky_material.set_shader_parameter("horizon_color", Vector3(haze.r, haze.g, haze.b))
	environment.sky.sky_material.set_shader_parameter("ground_color", Vector3(ground_tone.r, ground_tone.g, ground_tone.b))
	environment.sky.sky_material.set_shader_parameter("sun_color", Vector3(sun_tone.r, sun_tone.g, sun_tone.b))
	# Sky radiance supplies the specular reflection, but the Compatibility
	# renderer's sky-sourced ambient is far weaker per unit energy than a colour
	# ambient and ignores `ambient_light_energy`, which left shaded geometry
	# reading as black. An explicit ambient built from the map's own sky and
	# ground tones is predictable and keeps the map's colour cast.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ground_tone.lerp(sky_tone, 0.62).linear_to_srgb()
	environment.ambient_light_energy = 2.2
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.78 * float(environment_data.get("exposure", 1.0))
	environment.tonemap_white = 4.0
	# Depth fog supplies the aerial perspective that hides the arena edge and
	# separates near and far geometry; fog_sky_affect stays at zero so the sky
	# itself keeps its authored brightness.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = haze.linear_to_srgb()
	environment.fog_light_energy = 1.0
	environment.fog_depth_begin = 30.0
	environment.fog_depth_end = 210.0
	environment.fog_depth_curve = 1.2
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.0
	# Screen-space ambient occlusion grounds contact shadows between boxes.
	environment.ssao_enabled = true
	environment.ssao_radius = 1.1
	environment.ssao_intensity = 1.7
	environment.ssao_power = 1.6
	environment.ssao_detail = 0.6
	environment.ssao_light_affect = 0.15
	environment.ssao_horizon = 0.06
	environment.ssao_sharpness = 0.98
	# Glow keeps muzzle flashes and lamps reading as light sources.
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.4
	environment.glow_hdr_scale = 2.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Slightly desaturated and contrastier: the ported palettes are vivid, and a
	# shooter reads better with a muted, filmic grade.
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.1
	environment.adjustment_saturation = 0.94
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	# Godot treats RGB light colour as sRGB; the exported tones are linear.
	sun.light_color = sun_tone.linear_to_srgb()
	sun.light_energy = float(environment_data.get("sunIntensity", 2.4)) * 0.72
	# Real PSSM shadows replace the ported single-orthographic Three camera.
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 72.0
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.7
	sun.light_angular_distance = 0.6
	add_child(sun)
	var direction := vector_from_array(environment_data.get("sunDirection", [0.5, 1.0, 0.35])).normalized()
	sun.look_at_from_position(direction * 88.0, Vector3.ZERO, Vector3.UP)
	environment.sky.sky_material.set_shader_parameter("sun_direction", direction)
	environment.sky.sky_material.set_shader_parameter("sun_energy", 5.0 if direction.y > 0.35 else 12.0)
	environment.sky.sky_material.set_shader_parameter("ground_fade", 0.07 if direction.y > 0.35 else 0.11)
	# A slow horizon->zenith gradient reads as thick haze near eye level and
	# blends into the depth fog, instead of meeting it at a hard line.
	environment.sky.sky_material.set_shader_parameter("horizon_softness", 1.0 if direction.y > 0.35 else 1.25)
	environment.sky.sky_material.set_shader_parameter("ground_mix", 0.06)
	# The authored values above are the reference look; tiers scale from them so
	# a lower level reduces cost without re-authoring the lighting.
	QUALITY.capture_baseline(environment)
	QUALITY.apply_environment(environment, sun)
