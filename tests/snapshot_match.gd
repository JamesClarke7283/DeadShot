extends SceneTree
## Static full-match comparison using the real session/HUD with no input grab.
##
## Default: one wide shot per map, as before. User arguments add a tier and an
## explicit camera, so the same instrument can review a specific viewpoint at a
## specific quality level while iterating on the look:
##
##   --script res://tests/snapshot_match.gd -- --map=urban_docks --tier=ultra \
##       --pos=6,0,26 --yaw=180 --pitch=-4 --out=/tmp/shot.png
const SESSION = preload("res://scripts/game/match_session.gd")
const UI = preload("res://scripts/ui/game_ui.gd")
const QUALITY = preload("res://scripts/world/graphics_quality.gd")

var _options: Dictionary = {}

func _initialize() -> void:
	_options = _parse(OS.get_cmdline_user_args())
	call_deferred("_capture")

func _parse(arguments: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for argument in arguments:
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var key := argument.substr(2).get_slice("=", 0)
		parsed[key] = argument.substr(argument.find("=") + 1)
	return parsed

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	# The saved tier is applied by Main; a direct SceneTree run restores it here.
	QUALITY.set_current(str(_options.get("tier", QUALITY.DEFAULT_LEVEL)))
	QUALITY.apply_viewport(root)
	var ui = UI.new()
	root.add_child(ui)
	var game_match
	var maps: Array = [_options.get("map")] if _options.has("map") else ["desert_town", "forest_facility", "urban_docks"]
	for id in maps:
		if is_instance_valid(game_match):
			game_match.free()
		game_match = SESSION.new()
		root.add_child(game_match)
		game_match.start({"mapId": id, "mode": "tdm", "botCount": int(_options.get("bots", 0)), "difficulty": "regular", "hardcore": false}, ui.store.get_loadout(0), ui.store.get_settings())
		game_match.state = "live"
		game_match.elapsed = 0.0
		var actor = game_match.player
		var position := _vector(str(_options.get("pos", "-40,0,0")))
		actor.position = Vector3(position.x, game_match.map.height_at(position.x, position.z), position.z)
		actor.rotation.y = deg_to_rad(float(_options.get("yaw", -90.0)))
		actor.camera.rotation = Vector3(deg_to_rad(float(_options.get("pitch", 0.0))), 0, 0)
		actor.camera.position.y = float(_options.get("eye", 1.7))
		ui.screen = "match"
		ui.menu.hide()
		ui.scoreboard.hide()
		ui.streak_menu.hide()
		ui.hud.show()
		if _options.has("nohud"):
			ui.hud.hide()
		ui.update_hud(game_match.hud_state())
		for _frame in range(60):
			game_match.tick(1.0 / 60.0)
			await process_frame
		ui.update_hud(game_match.hud_state())
		await RenderingServer.frame_post_draw
		var path := str(_options.get("out", "res://assets/maps/previews/match_%s.png" % id))
		root.get_texture().get_image().save_png(path)
		print("MATCH RENDERED %s -> %s" % [id, path])
	game_match.free()
	ui.free()
	quit()

func _vector(value: String) -> Vector3:
	var parts := value.split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
