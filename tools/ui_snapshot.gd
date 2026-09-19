extends SceneTree
## Capture native UI at the original browser reference resolution.
## godot --path . --rendering-method gl_compatibility --script tools/ui_snapshot.gd -- --output-dir=/tmp/deadshot-ui
var ui: CanvasLayer
var output_directory := "/tmp/deadshot-ui"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_directory = argument.trim_prefix("--output-dir=")
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_directory.path_join(name + ".png"))

func run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(output_directory)
	ui = load("res://scripts/ui/game_ui.gd").new()
	root.add_child(ui)
	await process_frame
	ui.show_main_menu()
	await capture("main")
	ui.show_prematch()
	await capture("prematch")
	ui.show_class_editor()
	await capture("class")
	ui.show_options()
	await capture("options")
	ui.show_multiplayer()
	await capture("multiplayer")
	ui.show_match()
	ui.update_hud({"health": 75, "streaks": [{"name": "UAV", "cost": 500, "score": 250, "available": false}, {"name": "CARE PACKAGE", "cost": 700, "score": 250, "available": false}, {"name": "ATTACK HELICOPTER", "cost": 1200, "score": 250, "available": false}], "minimap": {"player": {"x": 10, "z": 10, "yaw": 1.0}, "bounds": {"minX": -50, "maxX": 50, "minZ": -50, "maxZ": 50}, "blips": [{"x": 15, "z": 15, "enemy": true}]}})
	ui.add_kill({"killer": "Player", "victim": "Enemy", "weaponId": "m4", "killerTeam": "blue", "victimTeam": "red", "headshot": true})
	await capture("hud")
	ui.set_touch_enabled(true)
	await capture("touch")
	ui.set_touch_enabled(false)
	ui.apply_screen_effect("stun", 0.5, 3)
	ui.apply_screen_effect("flash", 0.4, 3)
	await capture("screen_effects")
	ui.clear_screen_effects()
	ui.show_pause()
	await capture("pause")
	ui.show_controls()
	await capture("controls")
	ui.show_replay("BEST PLAY", "Press SPACE to skip", Color("ffcc33"))
	await capture("replay")
	ui.show_postmatch([{"name": "Player", "kills": 20, "deaths": 4, "assists": 2, "score": 2125, "team": "blue", "isPlayer": true}], 75, 43, "tdm", "BLUE team wins", 4)
	await capture("postmatch")
	print("Native UI snapshots saved: " + output_directory)
	quit()
