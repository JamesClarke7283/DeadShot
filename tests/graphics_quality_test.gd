extends SceneTree
## Measures the graphics detail slider across its anchor bands on the same scene,
## and verifies each band's preset and shader variant actually differ.
##
## The map is rebuilt per band because the band changes the materials, the
## shadow cascades and the viewport's shadow/scale settings.

const SESSION = preload("res://scripts/game/match_session.gd")
const STORE = preload("res://scripts/persistence/save_store.gd")
const MAIN = preload("res://scripts/core/main.gd")
const QUALITY = preload("res://scripts/world/graphics_quality.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

## A marker line is a QUALITY_* comment left in the generated shader.
func _has_markers(code: String) -> bool:
	for line in code.split("\n"):
		if line.strip_edges().begins_with("// QUALITY_"):
			return true
	return false

func _run() -> void:
	# This is an ordering and configuration check, not a throughput claim. Every
	# band renders faster than the 60 Hz present interval, so with vsync on the
	# measurement saturates at 60 fps for all four anchors and the ordering check
	# ends up testing the refresh rate instead of the band's cost. At 2560x1440
	# the bands do separate, and the separation is real — ultra pays for SDFGI,
	# four shadow cascades, MSAA, the parallax march and the full glow pyramid —
	# but on a fast GPU the absolute figures are dominated by CPU frame
	# submission, which is why they read in the hundreds of fps. Do not quote
	# them as achieved frame rates.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# The bands differ by a few percent at 1280x720, which is inside run-to-run
	# noise even after isolating render work. Measuring at 2560x1440 scales the
	# pixel-bound work each band controls by roughly four while the fixed
	# per-frame overhead stays put, so the same difference becomes a margin
	# several times the noise instead of being hidden by it.
	root.size = Vector2i(2560, 1440)
	var bootstrap = MAIN.new()
	bootstrap._setup_input()
	bootstrap.free()
	var store = STORE.new()
	seed(41)
	var results: Dictionary = {}
	for level in QUALITY.LEVELS:
		QUALITY.set_current(level)
		QUALITY.apply_viewport(root)
		var session = SESSION.new()
		root.add_child(session)
		session.start({"mapId": "desert_town", "mode": "tdm", "botCount": 8, "difficulty": "regular"}, store.get_loadout(0), store.get_settings())
		session.state = "live"
		session.player.position = Vector3(-40, 0, 0)
		session.player.rotation.y = -PI / 2
		# Warm the pipeline with real simulation so bot paths and VFX are live.
		for i in range(24):
			session.tick(1.0 / 60.0)
			await process_frame
		# Measure rendering alone: the tiers change shading work, shadow cascades,
		# MSAA and render scale, while `session.tick` drives eight bot planners on
		# the CPU regardless of tier. Ticking inside the timed loop let that
		# shared CPU cost dominate the wall clock — low measured ~2% ahead of high,
		# which is inside run-to-run noise. Presenting the same live scene without
		# ticking isolates the work each tier actually controls.
		# Best of several batches: a single batch is dominated by whatever else the
		# desktop is doing, while the tiers differ by well under a millisecond.
		var batches: Array[float] = []
		for batch in range(5):
			var start := Time.get_ticks_usec()
			for i in range(60):
				await process_frame
			batches.append((Time.get_ticks_usec() - start) / 1000000.0)
		var seconds: float = batches.min()
		var environment: Environment = session.map.world_environment.environment
		results[level] = {
			"fps": 60.0 / maxf(seconds, 0.0001),
			"drawcalls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"ssao": environment.ssao_enabled,
			"glow": environment.glow_enabled,
			"cascades": session.map.sun.directional_shadow_mode,
			"msaa": root.msaa_3d,
			"scale": root.scaling_3d_scale,
		}
		print("BAND %-7s %5.1f fps  %5.2f ms  %4d draws  ssao=%-5s glow=%-5s cascade=%d msaa=%d scale=%.2f" % [
			level, results[level].fps, seconds / 60.0 * 1000.0, results[level].drawcalls,
			results[level].ssao, results[level].glow, results[level].cascades,
			results[level].msaa, results[level].scale])
		session.free()
		await process_frame

	# The bands must be genuinely ordered, not just differently labelled.
	check(results.low.fps > results.high.fps, "Low band is faster than high")
	check(results.low.fps > results.ultra.fps, "Low band is faster than ultra")
	check(not results.low.ssao and not results.medium.ssao, "AO is off on low and medium")
	check(results.high.ssao and results.ultra.ssao, "AO is on for high and ultra")
	check(results.low.cascades == DirectionalLight3D.SHADOW_ORTHOGONAL, "Low band uses a single shadow cascade")
	check(results.ultra.cascades == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Ultra band uses four shadow cascades")
	check(results.low.msaa == Viewport.MSAA_DISABLED and results.ultra.msaa == Viewport.MSAA_4X, "MSAA follows the band")
	check(is_equal_approx(results.low.scale, 0.8) and is_equal_approx(results.ultra.scale, 1.0), "3D render scale follows the band")

	# The shader variant must actually lose work at the lower bands.
	var ultra_code := QUALITY.shader_code("ultra", 0)
	var low_code := QUALITY.shader_code("low", 0)
	check(ultra_code.contains("triplanar_field"), "Ultra samples all three projections")
	check(not low_code.contains("triplanar_field"), "Low drops the triplanar projection")
	check(ultra_code.contains("sample_x") and not low_code.contains("sample_x"), "Low drops the normal-map rebuild")
	check(ultra_code.contains("macro_noise") and not low_code.contains("macro_noise"), "Low drops the weathering map")
	check(not low_code.contains("detail_normal") and not low_code.contains("macro_noise"), "Low samples only the detail map")
	check(not _has_markers(ultra_code) and not _has_markers(low_code), "No band leaves a quality marker line behind")
	# The parallax uniform is declared outside the stripped block (the band passes
	# zero to skip the march), so the assertion has to look for the march itself.
	check(ultra_code.contains("pom_travel") and not low_code.contains("pom_travel"), "Parallax occlusion steps on at the band that owns it")

	# The slider must interpolate the continuous values between anchors rather
	# than snapping, and hold the discrete features at the lower anchor. This is
	# what makes dragging it a graded cost curve instead of four cliffs.
	var low_preset := QUALITY.preset_for_detail(0.0)
	var middle_preset := QUALITY.preset_for_detail(50.0)
	var ultra_preset := QUALITY.preset_for_detail(100.0)
	check(middle_preset.shadow_distance > low_preset.shadow_distance, "Shadow distance grows between anchors")
	check(middle_preset.render_scale > low_preset.render_scale, "Render scale grows between anchors")
	check(int(middle_preset.shadow_cascades) == 1, "An integer budget holds at the lower anchor")
	check(not middle_preset.ssil and ultra_preset.ssil, "SSIL is paid for only once the slider reaches its band")
	check(not middle_preset.sdfgi and ultra_preset.sdfgi, "SDFGI is paid for only once the slider reaches its band")
	check(QUALITY.level_for_detail(0.0) == "low" and QUALITY.level_for_detail(100.0) == "ultra", "The slider extremes resolve to the end bands")

	# Switching band mid-match must rebuild the live materials in place rather
	# than requiring a match restart.
	QUALITY.set_current("high")
	QUALITY.apply_viewport(root)
	var live = SESSION.new()
	root.add_child(live)
	live.start({"mapId": "desert_town", "mode": "tdm", "botCount": 4, "difficulty": "regular"}, store.get_loadout(0), store.get_settings())
	live.state = "live"
	for i in range(10):
		live.tick(1.0 / 60.0)
		await process_frame
	var high_material: ShaderMaterial = _first_map_material(live)
	var high_code := high_material.shader.code
	live.map.apply_quality("low")
	await process_frame
	var low_material: ShaderMaterial = _first_map_material(live)
	check(low_material != high_material, "Switching band replaces the live material")
	check(low_material.shader.code.length() < high_code.length(), "The live material compiles against the cheaper variant")
	check(low_material.shader.code.contains("detail_noise"), "The cheaper variant still shades surfaces")
	check(not low_material.shader.code.contains("triplanar_field"), "The live low-band material dropped triplanar sampling")
	check(live.map.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "Switching band re-applies the shadow cascade count")
	# The match must keep running after the rebuild.
	for i in range(10):
		live.tick(1.0 / 60.0)
		await process_frame
	check(live.state == "live" and is_instance_valid(live.player), "The match survives a live band switch")
	live.free()
	await process_frame

	QUALITY.set_current(QUALITY.DEFAULT_LEVEL)
	for failure in failures:
		push_error(failure)
	print("GRAPHICS QUALITY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

## First map surface material, used to compare shader variants across a rebuild.
func _first_map_material(session) -> ShaderMaterial:
	var found := _find_material(session.map)
	return found if found != null else ShaderMaterial.new()

func _find_material(node: Node) -> ShaderMaterial:
	if node is MeshInstance3D and node.material_override is ShaderMaterial:
		var material: ShaderMaterial = node.material_override
		if material.shader != null and material.shader.code.contains("fragment()"):
			return material
	for child in node.get_children():
		var found := _find_material(child)
		if found != null:
			return found
	return null
