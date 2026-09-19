extends SceneTree

const Visuals = preload("res://scripts/visuals/visual_factory.gd")

func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/source/models.json"))
	var count := 0
	for id in catalog.models:
		var model: Node3D = Visuals.create_model(id)
		assert(model != null, "Cannot instantiate " + id)
		for record in catalog.models[id].nodes:
			var part := Visuals.part(model, record)
			assert(part != null, "Missing imported node " + id + "/" + record)
			if catalog.models[id].nodes[record].has("material"):
				assert(part is MeshInstance3D, "Missing mesh " + id + "/" + record)
				assert(part.material_override is ShaderMaterial, "Missing toon material")
		for record in source.models[id].nodes:
			var node := Visuals.part(model, record.name)
			var m: Array = record.matrix
			var expected_transform := Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[4],m[5],m[6]),Vector3(m[8],m[9],m[10])),Vector3(m[12],m[13],m[14]))
			assert(node.transform.is_equal_approx(expected_transform), "Changed local transform " + id + "/" + record.name)
			if record.has("geometry"):
				var geometry: Dictionary = source.geometries[record.geometry]
				var material: Dictionary = source.materials[record.material]
				var expected_box := AABB()
				for i in range(0,geometry.positions.size(),3):
					var vertex := Vector3(geometry.positions[i],geometry.positions[i+1],geometry.positions[i+2])
					if material.outline:
						vertex += Vector3(geometry.normals[i],geometry.normals[i+1],geometry.normals[i+2]).normalized() * float(material.thickness)
					if i == 0:
						expected_box.position = vertex
					else:
						expected_box = expected_box.expand(vertex)
				var actual_box: AABB = node.mesh.get_aabb()
				assert(actual_box.position.distance_to(expected_box.position) < 0.0001 and actual_box.end.distance_to(expected_box.end) < 0.0001, "Changed geometry bounds " + id + "/" + record.name)
		model.free()
		count += 1
	var human := Visuals.create_human("ffa", 7)
	assert(Visuals.part(human, "hips").position.is_equal_approx(Vector3(0, 0.9, 0)))
	Visuals.animate_human(human, "run", 0.35, 0.016)
	assert(absf(Visuals.part(human, "left_leg").rotation.x - sin(0.35 * 11) * 0.8) < 0.00001)
	Visuals.animate_human(human, "die", 0.35, 0.625)
	assert(absf(human.rotation.x + PI / 2.0) < 0.00001)
	human.free()
	for id in catalog.weaponModels:
		var weapon := Visuals.create_weapon(id, Color("d4af37"), ["reddot", "holo", "suppressor", "foregrip"])
		assert(weapon.position == Vector3.ZERO)
		assert(Visuals.part(weapon, "muzzle") != null)
		assert(not Visuals.part(weapon, "knife").visible)
		weapon.free()
	print("BLENDER_MODEL_VERIFICATION: ", count, " models imported; every source local transform, geometry bound, hierarchy node and material matched; all weapon IDs and animation pivots verified.")
	quit()
