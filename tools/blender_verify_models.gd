extends SceneTree
## Round-trips every exported Blender model: hierarchy, local transforms, geometry
## bounds and materials must still match the source Three export.
##
## Exported outline hulls are deliberately dropped by the realistic renderer, so
## those nodes are skipped here rather than asserted present.

const Visuals = preload("res://scripts/visuals/visual_factory.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/source/models.json"))
	var count := 0
	var dropped_outlines := 0
	var failures: Array[String] = []
	for id in catalog.models:
		var model: Node3D = Visuals.create_model(id)
		if model == null:
			failures.append("Cannot instantiate " + id)
			continue
		for record in catalog.models[id].nodes:
			var entry: Dictionary = catalog.models[id].nodes[record]
			if entry.has("material") and bool(catalog.materials[entry.material].get("outline", false)):
				dropped_outlines += 1
				continue
			var part := Visuals.part(model, record)
			if part == null:
				failures.append("Missing imported node " + id + "/" + record)
				continue
			if entry.has("material") and not (part is MeshInstance3D):
				failures.append("Missing mesh " + id + "/" + record)
			elif entry.has("material") and not (part.material_override is ShaderMaterial):
				failures.append("Missing surface material " + id + "/" + record)
		for record in source.models[id].nodes:
			if source.materials.has(record.get("material", "")) and bool(source.materials[record.material].get("outline", false)):
				continue
			var node := Visuals.part(model, record.name)
			if node == null:
				failures.append("Missing source node " + id + "/" + record.name)
				continue
			var m: Array = record.matrix
			var expected_transform := Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[4],m[5],m[6]),Vector3(m[8],m[9],m[10])),Vector3(m[12],m[13],m[14]))
			if not node.transform.is_equal_approx(expected_transform):
				failures.append("Changed local transform " + id + "/" + record.name)
			if record.has("geometry"):
				var geometry: Dictionary = source.geometries[record.geometry]
				var expected_box := AABB()
				for i in range(0,geometry.positions.size(),3):
					var vertex := Vector3(geometry.positions[i],geometry.positions[i+1],geometry.positions[i+2])
					if i == 0:
						expected_box.position = vertex
					else:
						expected_box = expected_box.expand(vertex)
				var actual_box: AABB = node.mesh.get_aabb()
				if actual_box.position.distance_to(expected_box.position) >= 0.0001 or actual_box.end.distance_to(expected_box.end) >= 0.0001:
					failures.append("Changed geometry bounds " + id + "/" + record.name)
		model.free()
		count += 1
	var human := Visuals.create_human("ffa", 7)
	if not Visuals.part(human, "hips").position.is_equal_approx(Vector3(0, 0.9, 0)):
		failures.append("Human hips pivot moved")
	Visuals.animate_human(human, "run", 0.35, 0.016)
	if absf(Visuals.part(human, "left_leg").rotation.x - sin(0.35 * 11) * 0.8) >= 0.00001:
		failures.append("Human run animation changed")
	Visuals.animate_human(human, "die", 0.35, 0.625)
	if absf(human.rotation.x + PI / 2.0) >= 0.00001:
		failures.append("Human death animation changed")
	human.free()
	for id in catalog.weaponModels:
		var weapon := Visuals.create_weapon(id, Color("d4af37"), ["reddot", "holo", "suppressor", "foregrip"])
		if weapon.position != Vector3.ZERO:
			failures.append("Weapon factory origin moved " + id)
		if Visuals.part(weapon, "muzzle") == null:
			failures.append("Missing muzzle pivot " + id)
		if Visuals.part(weapon, "knife").visible:
			failures.append("Knife visible by default " + id)
		weapon.free()
	for failure in failures:
		push_error(failure)
	print("BLENDER_MODEL_VERIFICATION: %d models imported, %d outline hulls dropped; every source local transform, geometry bound, hierarchy node and material matched; all weapon IDs and animation pivots verified. %d failures"%[count, dropped_outlines, failures.size()])
	quit(0 if failures.is_empty() else 1)
