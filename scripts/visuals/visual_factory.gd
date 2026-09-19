class_name VisualFactory
extends RefCounted
## Exact Three.js geometry rebuilt and exported by Blender. Units remain meters,
## characters face +Z, and viewmodel barrels face -Z, as in the source game.

const Materials = preload("res://scripts/world/map_material.gd")
const FFA_COLORS := [0x9b5de5ff, 0xf15bb5ff, 0x00bbf9ff, 0x00f5d4ff, 0xfee440ff, 0xff7b00ff, 0x06d6a0ff, 0xef476fff, 0x118ab2ff, 0xffd166ff, 0x8338ecff, 0x3a86ffff, 0xfb5607ff, 0x2ec4b6ff, 0xe71d36ff, 0x8ac926ff]
const HIP_POSITION := Vector3(0.22, -0.2, -0.55)
const ADS_POSITION := Vector3(0, -0.13, -0.4)

## Surfaces for Blender models. Every model is built from generic `part_N`,
## `outline_N` and named pivot nodes, so the material's tint plus the owning
## asset decide the response: weapons are blued steel and polymer, characters are
## cloth, skin and webbing, and props read as painted metal or timber.
const MODEL_SURFACES := {
	"weapon": "gun_metal",
	"attachment": "gun_metal",
	"human": "cloth",
	"equipment": "painted_metal",
	"care_crate": "wood",
	"streak": "painted_metal",
}

## The exported weapon palette is mostly near-black (receiver, magazine, sights)
## with a few brighter warm parts (wooden furniture, grip panels) and one bright
## neutral part (optic glass/rail). Each maps to a different real material.
static func _weapon_surface(base: Color) -> String:
	var brightest := maxf(base.r, maxf(base.g, base.b))
	if brightest > 0.4:
		return "wood" if base.r > base.b * 1.3 else "metal"
	return "polymer" if brightest > 0.03 else "gun_metal"

static func _character_surface(node_name: String, base: Color) -> String:
	if node_name.contains("head") or node_name.contains("face"):
		return "skin"
	if base.r > base.b * 1.6 and base.r > 0.2:
		# The exported skin tone is the only warm, mid-bright part tone.
		return "skin"
	return "cloth"

static var environment: Dictionary = {}
static var _manifest: Dictionary = {}
static var _scenes: Dictionary = {}

static func _catalog() -> Dictionary:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))
	return _manifest

static func create_model(id: String) -> Node3D:
	var catalog := _catalog()
	if not catalog.models.has(id):
		push_error("Unknown Blender model: " + id)
		return Node3D.new()
	var record: Dictionary = catalog.models[id]
	if not _scenes.has(id):
		if ResourceLoader.exists(record.file):
			_scenes[id] = load(record.file)
		else:
			# An editor rescan is unnecessary for freshly rebuilt assets.
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			var error := document.append_from_file(record.file, state)
			if error != OK:
				push_error("Cannot import Blender model: " + id)
				return Node3D.new()
			var imported := document.generate_scene(state)
			var packed := PackedScene.new()
			packed.pack(imported)
			imported.free()
			_scenes[id] = packed
	var scene: PackedScene = _scenes[id]
	var result := scene.instantiate() as Node3D
	var parts: Dictionary = {}
	_configure_tree(result, id, record.nodes, parts)
	result.set_meta("visual_parts", parts)
	result.set_meta("model_id", id)
	if id == "rocket":
		# A real light plus an emissive plume, so the rocket actually reads as lit.
		var glow := OmniLight3D.new()
		glow.name = "EngineGlow"
		glow.position.z = -0.3
		glow.light_color = Color("ffa040")
		glow.light_energy = 3.0
		glow.omni_range = 7.0
		glow.omni_attenuation = 2.0
		glow.shadow_enabled = false
		result.add_child(glow)
		var plume := MeshInstance3D.new()
		plume.name = "EnginePlume"
		var plume_mesh := SphereMesh.new()
		plume_mesh.radius = 0.12
		plume_mesh.height = 0.3
		plume.mesh = plume_mesh
		plume.position.z = -0.34
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plume.material_override = Materials.create_unlit(Color("ffc070"), 8.0, 1.0, true)
		result.add_child(plume)
	return result

static func _configure_tree(node: Node, model_id: String, records: Dictionary, parts: Dictionary) -> void:
	var original := String(node.name).trim_prefix(model_id + "__")
	# Blender's names are prefixed per asset so the complete .blend library can
	# retain named pivots without any automatic .001 suffixes.
	node.name = original
	if node is MeshInstance3D and original.begins_with("outline"):
		# Baked cartoon outline hulls are dropped with the rest of the toon look.
		node.visible = false
		node.queue_free()
		return
	parts[original] = node
	var record: Dictionary = records.get(original, {})
	if node is Node3D:
		node.visible = record.get("visible", true)
	if node is MeshInstance3D and record.has("material"):
		var source: Dictionary = _catalog().materials[record.material].duplicate(true)
		var role: String = source.get("role", "")
		var surface := _surface_for(model_id, original, source)
		source.surface = surface
		node.set_meta("material_source", source.duplicate(true))
		node.set_meta("material_role", role)
		node.material_override = Materials.create_material(source, environment)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if record.get("castShadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_configure_tree(child, model_id, records, parts)

static func _surface_for(model_id: String, node_name: String, source: Dictionary) -> String:
	var base := Materials.color_from_array(source.get("color", []), Color(0.5, 0.5, 0.5))
	var family := model_id.get_slice("_", 0)
	match family:
		"weapon", "attachment":
			return _weapon_surface(base)
		"human":
			return _character_surface(node_name, base)
		"equipment", "streak", "care":
			return "painted_metal"
	return str(MODEL_SURFACES.get(family, "generic"))

static func create_human(team: String = "ffa", accent_index: int = 0) -> Node3D:
	var result := create_model("human_" + (team if team in ["blue", "red", "ffa"] else "ffa"))
	set_team(result, team, accent_index)
	return result

static func team_color(team: String, accent_index: int = 0) -> Color:
	if team == "blue":
		return Color.hex(0x3a86ffff)
	if team == "red":
		return Color.hex(0xff4d4dff)
	return Color.hex(FFA_COLORS[posmod(accent_index, FFA_COLORS.size())])

static func set_team(root: Node3D, team: String, accent_index: int = 0) -> void:
	_tint_role(root, "team", team_color(team, accent_index))

static func set_camo(root: Node3D, camo: Color) -> void:
	_tint_role(root, "camo", camo)

static func _tint_role(node: Node, role: String, color: Color) -> void:
	if node is MeshInstance3D and node.get_meta("material_role", "") == role:
		var source: Dictionary = node.get_meta("material_source")
		var linear := color.srgb_to_linear()
		source.color = [linear.r, linear.g, linear.b]
		# Rebuild at full opacity: these parts are solid team/camo surfaces.
		source.transparent = false
		source.opacity = 1.0
		node.material_override = Materials.create_material(source, environment)
	for child in node.get_children():
		_tint_role(child, role, color)

static func create_weapon(category_or_id: String = "assault", camo: Color = Color("2b2f36"), attachments: Array = []) -> Node3D:
	var catalog := _catalog()
	var model_id: String = catalog.weaponModels.get(category_or_id, "weapon_" + category_or_id)
	var root := create_model(model_id)
	var category := model_id.trim_prefix("weapon_")
	var gun := part(root, "gun")
	var slots: Dictionary = {}
	for attachment in attachments:
		var id: String = str(attachment.get("id", "")) if attachment is Dictionary else str(attachment)
		if catalog.get("attachmentSlots", {}).has(id):
			slots[catalog.attachmentSlots[id]] = id
	for id in slots.values():
		var attachment_id: String = "attachment_" + category + "_" + str(id)
		if catalog.models.has(attachment_id):
			gun.add_child(create_model(attachment_id))
	set_camo(root, camo)
	# Factory origin is neutral; the owning camera applies HIP_POSITION/ADS_POSITION.
	root.position = Vector3.ZERO
	return root

static func create_equipment(id: String, team: String = "blue") -> Node3D:
	var normalized: String = {"knife": "throwing_knife", "flash": "flashbang"}.get(id, id)
	var result := create_model("equipment_" + str(normalized))
	set_team(result, team)
	return result

static func create_streak(id: String) -> Node3D:
	return create_model("care_crate" if id == "care_crate" else "streak_" + id)

static func part(root: Node3D, name: String) -> Node3D:
	return root.get_meta("visual_parts", {}).get(name) as Node3D

static func animate_human(root: Node3D, animation: String, time: float, dt: float) -> void:
	var hips := part(root, "hips")
	if hips == null:
		return
	var left_arm := part(root, "left_arm")
	var right_arm := part(root, "right_arm")
	var left_leg := part(root, "left_leg")
	var right_leg := part(root, "right_leg")
	for limb in [left_arm, right_arm, left_leg, right_leg]:
		limb.rotation = Vector3.ZERO
	hips.position.y = 0.9
	hips.rotation = Vector3.ZERO
	if root.get_meta("animation", "idle") != animation:
		root.set_meta("die_time", 0.0)
		root.set_meta("animation", animation)
	if animation != "die":
		root.rotation.x = 0.0
	match animation:
		"idle":
			var b := sin(time * 2.0)
			hips.position.y += b * 0.01
			left_arm.rotation = Vector3(b * 0.04, 0, 0.08)
			right_arm.rotation = Vector3(-b * 0.04, 0, -0.08)
		"run":
			var s := sin(time * 11.0)
			left_leg.rotation.x = s * 0.8
			right_leg.rotation.x = -s * 0.8
			left_arm.rotation.x = -s * 0.7
			right_arm.rotation.x = s * 0.7
			hips.position.y += abs(sin(time * 22.0)) * 0.04
			hips.rotation.x = 0.12
		"shoot":
			var recoil := sin(time * 45.0) * 0.03
			left_arm.rotation = Vector3(-PI / 2.0 + 0.15 + recoil, 0, 0.2)
			right_arm.rotation = Vector3(-PI / 2.0 + 0.1 + recoil, 0, -0.2)
		"die":
			var progress: float = minf(1.0, float(root.get_meta("die_time", 0.0)) + dt * 1.6)
			root.set_meta("die_time", progress)
			root.rotation.x = -progress * PI / 2.0
			hips.position.y = 0.9 * (1.0 - progress * 0.4)
