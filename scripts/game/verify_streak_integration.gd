extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scripts/core/main.gd").new()
	main.set_physics_process(false)
	root.add_child(main)
	await process_frame
	main.start_match({"mapId":"desert_town","mode":"tdm","botCount":1,"difficulty":"recruit","classSlot":0,"hardcore":false})
	var game = main.game_match
	game.state = "live"
	game.player.health = 10000.0
	game.player.max_health = 10000.0
	game.streaks.set_loadout(game.player.actor_id,["uav","care_package","nuke"])
	game.streaks.add_score(game.player.actor_id,500)
	assert(game.hud_state().nextStreakName == "Care Package")
	Input.action_press("streaks")
	Input.action_press("streak_slot_1")
	main._physics_process(0.01)
	Input.action_release("streak_slot_1")
	Input.action_release("streaks")
	assert(game.streaks.active.size() == 1 and game.streaks.active[0].id == "uav")
	main._physics_process(0.01)
	assert(not game.hud_state().streaks[0].available)
	assert(not game.hud_state().minimap.blips.is_empty())
	game.streaks.force_activate(game.actors[1],"counter_uav")
	main._physics_process(0.01)
	assert(game.hud_state().minimap.jammed)
	assert(game.hud_state().minimap.blips.is_empty())
	assert(main._run_dev_command("bots") == "1 bots")
	assert(main._run_dev_command("give unknown") == "Unknown streak: unknown")
	assert(main._run_dev_command("map forest_facility").contains("gave UAV"))
	assert(main._run_dev_command("nuke") == "nuke incoming")
	main._physics_process(6.1)
	assert(main.state == "post_match", "Nuke completion must synchronously end live update")
	assert(main.ui.screen == "postmatch", "Remaining physics tick must preserve postmatch UI")
	assert(not main.ui.hud.visible)
	main.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("STREAK_INTEGRATION_VERIFICATION: Z+slot activation, HUD progress, UAV intel, Counter-UAV jamming, console grants and nuke postmatch transition passed.")
	quit()
