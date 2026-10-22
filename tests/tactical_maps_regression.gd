extends SceneTree
const World = preload("res://scripts/world/map_world.gd")
const Session = preload("res://scripts/game/match_session.gd")
const Data = preload("res://scripts/core/game_data.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var world = World.new()
	root.add_child(world)
	for id in ["freight_yard", "snow_outpost"]:
		check(id in World.MAP_IDS, "New map is in the shared catalogue")
		check(world.load_map(id), "Load " + id)
		check(world.spawn_points.size() == 27, "All team and FFA spawns exist: " + id)
		check(world.nav_points.size() > 300, "Navigation covers the arena: " + id)
		check(world.radar_layout.size() > 15, "Radar exposes arena cover: " + id)
		for spawn in world.spawn_points:
			check(world.point_free(spawn.position.x, spawn.position.z, 0.9), "Spawn has player clearance: " + id)
			check(world.path_between(spawn.position, Vector3.ZERO).size() >= 1, "Spawn connects to the centre: " + id)
		for point in world.nav_points:
			check(world.point_free(point.position.x, point.position.z, 0.7), "Waypoint is walkable: " + id)
			for neighbor in point.neighbors:
				var target: Vector3 = world.navigation.get_point_position(int(neighbor))
				var offset: Vector3 = target - point.position
				check(world.raycast_boxes(point.position + Vector3.UP, offset.normalized(), offset.length()) < 0, "Navigation edge does not cross a wall: " + id)
		for node in world.get_children():
			if node is MeshInstance3D:
				var arrays: Array = node.mesh.surface_get_arrays(0)
				check(not arrays[Mesh.ARRAY_NORMAL].is_empty(), "Mesh has shading normals: " + id)
		print("MAP ROUTES VERIFIED ", id)
	world.free()
	# Missing normals on old architectural meshes are rebuilt as finite normals.
	var mesh := World._make_mesh({"positions": [0, 0, 0, 1, 0, 0, 0, 0, 1], "indices": [0, 2, 1]})
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	check(normals.size() == 3, "Loader generates omitted normals")
	for normal in normals:
		check(normal.is_finite() and normal.length() > 0.99, "Generated normals are normalized and finite")
	var save: Dictionary = Data.table("default_save")
	for id in ["freight_yard", "snow_outpost"]:
		for mode in ["tdm", "ffa", "dom", "ctf", "gungame"]:
			var session = Session.new()
			root.add_child(session)
			check(session.start({"mapId": id, "mode": mode, "botCount": 2}, save.classes[0], save.settings), "Start %s on %s" % [mode, id])
			if session.objective:
				for point in session.objective.points:
					check(session.map.point_free(point.x, point.z, 0.6), "Domination point is accessible: " + id)
				for flag in session.objective.flags:
					check(session.map.point_free(flag.home.x, flag.home.z, 0.6), "Flag is accessible: " + id)
			session.free()
			await process_frame
	print("TACTICAL MAPS: %s" % ("PASS" if failures.is_empty() else str(failures.size()) + " failures"))
	quit(0 if failures.is_empty() else 1)
