extends SceneTree
## The graphics tier must round-trip through the save file, migrate onto an older
## save that predates the setting, and fall back safely when given junk.

const Store = preload("res://scripts/persistence/save_store.gd")
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

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		push_error(failure)
	print("GRAPHICS SETTINGS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
