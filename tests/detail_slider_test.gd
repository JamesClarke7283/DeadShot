extends SceneTree
## End-to-end check that the graphics detail slider drives the live render path:
## Main.apply_settings must move the quality module, re-apply the viewport and,
## after the debounce, rebuild the live world materials against the new band.
const MAIN = preload("res://scripts/core/main.gd")
const QUALITY = preload("res://scripts/world/graphics_quality.gd")
const STORE = preload("res://scripts/persistence/save_store.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _run() -> void:
	var store = STORE.new()
	var main = MAIN.new()
	root.add_child(main)
	await process_frame
	main._setup_input()
	main.start_match({"mapId": "urban_docks", "mode": "tdm", "botCount": 2, "difficulty": "regular", "classSlot": 0, "hardcore": false})
	await process_frame
	check(is_instance_valid(main.game_match), "A match started")
	var material_before: ShaderMaterial = _first_material(main.game_match.map)
	var code_before := material_before.shader.code
	check(code_before.contains("triplanar_field"), "The default starts on a band with triplanar sampling")

	# Drag the slider to the bottom: this is what OPTIONS emits on every step.
	main.apply_settings({"graphicsDetail": 0.0})
	check(QUALITY.detail() == 0.0, "The slider position reaches the quality module")
	check(QUALITY.current() == "low", "The slider position resolves to the low band")
	# The viewport half is immediate; the material half waits for the debounce.
	var pending: bool = main._quality_dirty
	check(pending, "The material rebuild is deferred so a drag does not recompile per step")
	for _frame in range(20):
		main._tick_quality(0.05)
	var material_after: ShaderMaterial = _first_material(main.game_match.map)
	check(material_after != material_before, "Reaching the debounce rebuilds the live material")
	check(not material_after.shader.code.contains("triplanar_field"), "The rebuilt material is the low band's variant")
	check(material_after.shader.code.length() < code_before.length(), "The rebuilt material is cheaper than the previous one")
	check(main.game_match.map.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "The band re-applied the shadow cascade count")
	check(not main.game_match.map.world_environment.environment.ssao_enabled, "AO is off on the low band")

	# A saved band without a slider position must still resolve (older saves and
	# the browser import format carry `graphics` only).
	main.apply_settings({"graphics": "ultra"})
	for _frame in range(20):
		main._tick_quality(0.05)
	check(QUALITY.detail() >= 100.0, "A band-only save moves the slider to that band's anchor")
	check(QUALITY.current() == "ultra", "The band-only save resolves to ultra")
	check(main.game_match.map.world_environment.environment.ssao_enabled, "Ultra turns AO back on")

	# Touching an unrelated setting must not snap an explicitly chosen slider
	# position back to a named anchor. OPTIONS commits each change to the store
	# and then emits the whole settings dict, so the test mirrors that flow.
	store.update_settings({"graphicsDetail": 47.0})
	main.apply_settings(store.get_settings())
	for _frame in range(20):
		main._tick_quality(0.05)
	check(QUALITY.detail() == 47.0, "A mid-slider position is honoured")
	store.update_settings({"sensitivity": 1.5})
	main.apply_settings(store.get_settings())
	check(QUALITY.detail() == 47.0, "An unrelated setting change leaves the slider where it was put")

	var live: bool = main.game_match.state == "live" or main.game_match.state == "warmup"
	check(live, "The match survives every detail change")

	main.free()
	for failure in failures:
		push_error(failure)
	print("DETAIL SLIDER: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _first_material(node: Node) -> ShaderMaterial:
	if node is MeshInstance3D and node.material_override is ShaderMaterial:
		var material: ShaderMaterial = node.material_override
		if material.shader != null and material.shader.code.contains("fragment()"):
			return material
	for child in node.get_children():
		var found := _first_material(child)
		if found != null:
			return found
	return null
