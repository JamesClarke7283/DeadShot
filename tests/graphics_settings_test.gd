extends SceneTree
## The graphics tier must round-trip through the save file, migrate onto an older
## save that predates the setting, and fall back safely when given junk.

const Store = preload("res://scripts/persistence/save_store.gd")
const Quality = preload("res://scripts/world/graphics_quality.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _run() -> void:
	var path := "user://deadshot-graphics-test.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var store = Store.new(path)
	check(store.get_settings().graphics == "high", "Default tier is high")
	store.update_settings({"graphics": "ultra"})
	# A fresh store reads what was written.
	var reopened = Store.new(path)
	check(reopened.get_settings().graphics == "ultra", "Chosen tier survives a reload")

	# An older save without the key must migrate to the default, not to junk.
	var legacy := {
		"version": 1,
		"classes": store.get_classes(),
		"settings": {"sensitivity": 2.0, "fov": 90, "masterVolume": 0.5, "sfxVolume": 0.5, "musicVolume": 0.5, "invertY": true, "killcam": false},
		"lastMatch": store.get_match_config(),
	}
	check(not legacy.settings.has("graphics"), "Legacy settings really predate the tier")
	var migrated = Store.migrate(legacy)
	check(migrated.settings.graphics == "high", "A pre-tier save migrates to the default tier")
	check(is_equal_approx(float(migrated.settings.sensitivity), 2.0), "Migration keeps the other settings")

	# A non-string value must not be adopted.
	var corrupt = legacy.duplicate(true)
	corrupt.settings = legacy.settings.duplicate(true)
	corrupt.settings.graphics = 7
	check(Store.migrate(corrupt).settings.graphics == "high", "A non-string tier is rejected")

	# The browser save format carries the same key.
	check(store.import_browser_save(JSON.stringify({"settings": {"graphics": "low"}})), "Browser save imports")
	check(store.get_settings().graphics == "low", "Browser save carries the tier")

	# The shipped control is the continuous detail slider. It must round-trip, be
	# rejected when it is not a number, and default onto the anchor of the band a
	# save without it names.
	store.update_settings({"graphicsDetail": 42.0})
	check(is_equal_approx(float(Store.new(path).get_settings().graphicsDetail), 42.0), "Detail level survives a reload")
	var legacy_detail := legacy.duplicate(true)
	legacy_detail.settings = legacy.settings.duplicate(true)
	check(is_equal_approx(float(Store.migrate(legacy_detail).settings.graphicsDetail), 66.0), "A pre-slider save migrates to the default detail anchor")
	var corrupt_detail := legacy.duplicate(true)
	corrupt_detail.settings = legacy.settings.duplicate(true)
	corrupt_detail.settings.graphicsDetail = "lots"
	check(is_equal_approx(float(Store.migrate(corrupt_detail).settings.graphicsDetail), 66.0), "A non-numeric detail level is rejected")

	# A slider position must resolve to the band whose anchor it has reached, and
	# every band must be reachable from its own anchor.
	check(Quality.level_for_detail(0.0) == "low", "Detail 0 resolves to the low band")
	check(Quality.level_for_detail(33.0) == "medium", "Detail 33 resolves to the medium band")
	check(Quality.level_for_detail(66.0) == "high", "Detail 66 resolves to the high band")
	check(Quality.level_for_detail(100.0) == "ultra", "Detail 100 resolves to the ultra band")
	check(Quality.level_for_detail(20.0) == "low", "A position below an anchor stays on the lower band")
	for level in Quality.LEVELS:
		check(Quality.detail_for_level(level) == float(Quality.LEVEL_DETAIL[level]), "Level %s detail anchor is its own" % level)

	# Intermediate positions must interpolate the continuous values rather than
	# snapping, and the discrete features must hold at the lower anchor.
	var low := Quality.preset_for_detail(0.0)
	var mid := Quality.preset_for_detail(50.0)
	var ultra := Quality.preset_for_detail(100.0)
	check(mid.shadow_distance > low.shadow_distance and mid.shadow_distance < ultra.shadow_distance, "Shadow distance interpolates between anchors")
	check(mid.render_scale > low.render_scale and mid.render_scale <= ultra.render_scale, "Render scale interpolates between anchors")
	check(not low.ssil and not mid.ssil and ultra.ssil, "SSIL steps on at the band that owns it")
	check(not low.sdfgi and not mid.sdfgi and ultra.sdfgi, "SDFGI steps on at the band that owns it")
	check(int(mid.shadow_cascades) == 1, "An integer budget holds at the lower anchor")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("GRAPHICS SETTINGS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
