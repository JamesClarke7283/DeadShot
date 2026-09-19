extends SceneTree
## Headless world parity validation, independent of the match and menus.
## godot --headless --path . --script res://scripts/world/verify_maps.gd

const WORLD = preload("res://scripts/world/map_world.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var expected := {
		# Visible, non-outline authored nodes that become their own mesh instance.
		# Instanced batches (the tree canopies) collapse into one
		# MultiMeshInstance3D each, so this is below the raw node count.
		# The architectural detail nodes `tools/deadshot_enrich_maps.py` adds are
		# counted separately so a regression in either is distinguishable: six
		# structural slots (parapet, plinth, frames, glazing, doors, trim) plus
		# prop slots (body, glazing, trim, rubber, lamps), of which only the ones
		# that produced geometry emit a node. `expected_detail` is the floor all
		# three maps reach, and the structural slots are asserted by name.
		"desert_town": [149, 81, 471, 6],
		"forest_facility": [103, 66, 472, 6],
		"urban_docks": [103, 66, 648, 6],
	}
	var expected_detail := 9
	var required_slots := ["ds_map_parapet", "ds_map_plinth", "ds_map_frame",
			"ds_map_glass_dark", "ds_map_door", "ds_map_metal_trim", "prop_body",
			"prop_trim", "prop_rubber"]
	var world = WORLD.new()
	root.add_child(world)
	var failures: Array[String] = []
	for id: String in expected:
		if not world.load_map(id):
			failures.append("Could not load %s" % id)
			continue
		var authored := 0
		var detail := 0
		var slot_names: Array[String] = []
		for node in _mesh_instances(world):
			if str(node.name).begins_with("detail_"):
				detail += 1
				slot_names.append(str(node.name))
			else:
				authored += 1
		if authored != expected[id][0]: failures.append("Authored mesh count: " + id)
		if detail < expected_detail: failures.append("Detail node count: " + id)
		for slot: String in required_slots:
			var found := false
			for name: String in slot_names:
				if name.ends_with(slot):
					found = true
					break
			if not found: failures.append("Missing detail slot %s: %s" % [slot, id])
		if world.collision_boxes.size() != expected[id][1]: failures.append("Collision count: " + id)
		if world.nav_points.size() != expected[id][2]: failures.append("Navigation count: " + id)
		if world.spawn_points.size() != 27: failures.append("Spawn count: " + id)
		if float(world.bounds.minX) != -70.0 or float(world.bounds.maxX) != 70.0 or float(world.bounds.minZ) != -70.0 or float(world.bounds.maxZ) != 70.0: failures.append("Bounds: " + id)
		for spawn: Dictionary in world.spawn_points:
			var position: Vector3 = spawn.position
			if absf(position.y - world.height_at(position.x, position.z)) > 0.00001: failures.append("Spawn terrain height: " + id)
			if not world.point_free(position.x, position.z, 0.9): failures.append("Spawn clearance: " + id)
		for team in ["red", "blue", "ffa"]:
			if world.spawns_for_team(team).size() != 9: failures.append("Team spawn count: " + id)
		for point: Dictionary in world.nav_points:
			for adjacent: Variant in point.neighbors:
				if not world.navigation.are_points_connected(point.id, int(adjacent), false): failures.append("Missing navigation edge: " + id)
		var wall_distance: float = world.raycast_boxes(Vector3(-65, 2, -65), Vector3(-1, 0, 0), 20)
		if absf(wall_distance - 6.5) > 0.0001 and id != "forest_facility": failures.append("Perimeter raycast: " + id)
		var resolved: Vector3 = world.resolve_position(Vector3(-71.7, world.height_at(-71.7, 0), 0), 0.45, 1.75)
		if resolved.x < -71.051: failures.append("Perimeter mover collision: " + id)
		print("MAP VERIFIED %s authored=%d detail=%d colliders=%d spawns=%d navigation=%d" % [id, authored, detail, world.collision_boxes.size(), world.spawn_points.size(), world.nav_points.size()])
		await process_frame
	world.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _mesh_instances(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_mesh_instances(child))
	return found
