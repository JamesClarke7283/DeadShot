class_name VisualFactory
extends RefCounted
## Exact Three.js geometry rebuilt and exported by Blender. Units remain meters,
## characters face +Z, and viewmodel barrels face -Z, as in the source game.

const Materials = preload("res://scripts/world/map_material.gd")
const FFA_COLORS := [0x9b5de5ff, 0xf15bb5ff, 0x00bbf9ff, 0x00f5d4ff, 0xfee440ff, 0xff7b00ff, 0x06d6a0ff, 0xef476fff, 0x118ab2ff, 0xffd166ff, 0x8338ecff, 0x3a86ffff, 0xfb5607ff, 0x2ec4b6ff, 0xe71d36ff, 0x8ac926ff]
const HIP_POSITION := Vector3(0.22, -0.2, -0.55)
const ADS_POSITION := Vector3(0, -0.13, -0.4)
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
		var glow := preload("res://scripts/visuals/source_point_light.gd").new()
		glow.name = "EngineGlow"
		glow.position.z = -0.3
		glow.light_color = Color("ffa040")
		glow.light_energy = 2.0
		glow.omni_range = 6.0
		glow.omni_attenuation = 2.0
		result.add_child(glow)
	return result

static func _configure_tree(node: Node, model_id: String, records: Dictionary, parts: Dictionary) -> void:
	var original := String(node.name).trim_prefix(model_id + "__")
	# Blender's names are prefixed per asset so the complete .blend library can
	# retain named pivots without any automatic .001 suffixes.
	node.name = original
	parts[original] = node
	var record: Dictionary = records.get(original, {})
	if node is Node3D:
		node.visible = record.get("visible", true)
	if node is MeshInstance3D and record.has("material"):
		var source: Dictionary = _catalog().materials[record.material].duplicate(true)
		var role: String = source.get("role", "")
		node.set_meta("material_source", source.duplicate(true))
		node.set_meta("material_role", role)
		# The Blender source bakes and reverses outline hull triangles. Apply only
		# their unlit color here; extruding the hull again would thicken outlines.
		if source.get("outline", false):
			source.outline = false
			source.unlit = true
			source.rawUnlit = true
			source.thickness = 0.0
		node.material_override = Materials.create_material(source, environment)
		node.material_override.set_shader_parameter("receive_shadows", false)
		if node.get_meta("material_source").get("outline", false):
			node.material_override.set_shader_parameter("fog_near", 1.0e12)
			node.material_override.set_shader_parameter("fog_far", 2.0e12)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if record.get("castShadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_configure_tree(child, model_id, records, parts)

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
		var source: Dictionary = node.get_meta("material_source").duplicate(true)
		var linear := color.srgb_to_linear()
		source.color = [linear.r, linear.g, linear.b]
		node.material_override = Materials.create_material(source, environment)
		node.material_override.set_shader_parameter("receive_shadows", false)
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
