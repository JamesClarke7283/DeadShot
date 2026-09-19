class_name MapWorld
extends Node3D
## Original arenas reconstructed from exported Three geometry; no JS at runtime.
## Coordinates, colliders, spawns and waypoint graph are kept in source units.

const MATERIALS = preload("res://scripts/world/map_material.gd")
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
	for key: String in data["materials"]:
		_materials[key] = MATERIALS.create_material(data["materials"][key], environment_data)
		if float(data["materials"][key].get("windStrength", 0.0)) > 0.0:
			_wind_materials.append(_materials[key])
	var batches: Dictionary = {}
	for record: Dictionary in data["nodes"]:
		if not bool(record.get("visible", true)):
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
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(record.get("castShadow", false)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 0.3
	add_child(instance)
	if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and _wind_materials.has(instance.material_override):
		# Source onBeforeCompile wind only patches the color shader; its default
		# depth material casts the original unswayed canopy's shadow.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shadow := MultiMeshInstance3D.new()
		shadow.name = instance.name + "_source_shadow"
		shadow.multimesh = multi
		shadow.material_override = instance.material_override.duplicate()
		shadow.material_override.set_shader_parameter("wind_strength", 0.0)
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(shadow)

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
	world_environment = WorldEnvironment.new()
	world_environment.name = "MapEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = MATERIALS.color_from_array(environment_data.get("background", [0.5, 0.7, 1])).linear_to_srgb()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# The shared shader applies Three r180's exact ACES transform and fog order.
	# The source background bypasses tone mapping, so the environment stays linear.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = MATERIALS.color_from_array(environment_data.get("sunColor", [1, 1, 1])).linear_to_srgb()
	# Godot includes PI in LIGHT_COLOR; Three's toon BRDF divides by PI.
	sun.light_energy = float(environment_data.get("sunIntensity", 2.2)) / PI
	sun.shadow_enabled = true
	# Source uses one orthographic 2048px map with a 40m half-frustum.
	# This native camera-relative coverage best matches source wall snapshots.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 64.0
	# Three renders opposite material faces into its PCF shadow map.
	sun.shadow_reverse_cull_face = true
	sun.shadow_bias = 0.05
	# Godot normal bias is expressed in shadow texels, unlike Three world units.
	sun.shadow_normal_bias = 0.8
	add_child(sun)
	var direction := vector_from_array(environment_data.get("sunDirection", [0.5, 1.0, 0.35])).normalized()
	sun.look_at_from_position(direction * 88.0, Vector3.ZERO, Vector3.UP)
	if DisplayServer.get_name()!="headless":
		var source_shadow=preload("res://scripts/world/source_shadow.gd").new()
		source_shadow.direction=direction
		add_child(source_shadow)
		sun.shadow_enabled=false
