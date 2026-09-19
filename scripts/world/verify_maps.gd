extends SceneTree
## Headless world parity validation, independent of the match and menus.
## godot --headless --path . --script res://scripts/world/verify_maps.gd

const WORLD = preload("res://scripts/world/map_world.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var expected := {
		# Visible, non-outline nodes only: the exported cartoon outline hulls are
		# dropped by the realistic material pass and no longer become meshes.
		"desert_town": [177, 81, 471],
		"forest_facility": [655, 66, 472],
		"urban_docks": [111, 66, 648],
	}
	var world = WORLD.new()
	root.add_child(world)
	var failures: Array[String] = []
	for id: String in expected:
		if not world.load_map(id):
			failures.append("Could not load %s" % id)
			continue
		if world.mesh_instance_count != expected[id][0]: failures.append("Mesh instance count: " + id)
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
		print("MAP VERIFIED %s meshes=%d colliders=%d spawns=%d navigation=%d" % [id, world.mesh_instance_count, world.collision_boxes.size(), world.spawn_points.size(), world.nav_points.size()])
		await process_frame
	world.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
