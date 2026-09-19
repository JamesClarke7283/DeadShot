extends SceneTree

class PassiveBrain extends RefCounted:
	func tick(_actor,_dt,_match)->void:pass

func _initialize()->void:
	call_deferred("run")

func seed_capture(game,time:float)->void:
	game.elapsed=time
	game.recorder.clear()
	game.recorder.record(time-2.0,game.snapshot_actors())
	game.recorder.record(time-1.0,game.snapshot_actors())
	game.recorder.record(time,game.snapshot_actors())

func run()->void:
	var main=load("res://scripts/core/main.gd").new()
	main.set_physics_process(false)
	root.add_child(main)
	await process_frame
	# Memory-only settings prevent the test from changing the user's save.
	main.ui.store.data.settings.killcam=true
	main.ui.store.data.settings.fov=103
	main.start_match({"mapId":"desert_town","mode":"tdm","botCount":1,"difficulty":"recruit","classSlot":0,"hardcore":false})
	var game=main.game_match
	game.state="live"
	var player=game.player
	var enemy=game.actors[1]
	enemy.brain=PassiveBrain.new()
	assert(game.recorder.duration==10.0)
	seed_capture(game,3.0)
	player.apply_damage(1000,enemy,"m4")
	assert(is_instance_valid(main.replay) and main.ui.replay_overlay.visible)
	assert(not player.visible and not enemy.visible and game.map.visible)
	assert(main.replay.camera.fov==103.0)
	main._physics_process(0.1)
	assert(is_equal_approx(main.replay.elapsed,0.055))
	assert(not main.ui.hud.visible)
	main.replay.advance(10.0)
	main._physics_process(0.01)
	assert(main.replay.is_finished() and not player.alive, "Finished killcam waits for respawn or skip")
	Input.action_press("jump")
	main._physics_process(0.01)
	Input.action_release("jump")
	assert(not is_instance_valid(main.replay) and player.alive)
	assert(player.camera.is_current() and player.visible and enemy.visible and main.ui.hud.visible)
	await process_frame
	seed_capture(game,7.0)
	player.apply_damage(1000,enemy,"m4")
	assert(is_instance_valid(main.replay))
	main._physics_process(4.01)
	assert(player.alive and not is_instance_valid(main.replay), "Natural respawn returns control to the live camera")
	main.ui.store.data.settings.killcam=false
	seed_capture(game,12.0)
	player.apply_damage(1000,enemy,"m4")
	assert(not is_instance_valid(main.replay), "Disabled killcam consumes the death without starting playback")
	game.respawn_player_now()
	main.ui.store.data.settings.killcam=true
	seed_capture(game,15.0)
	enemy.apply_damage(1000,player,"m4")
	game._spawn(enemy)
	game.elapsed=15.5
	game.recorder.record(game.elapsed,game.snapshot_actors())
	enemy.apply_damage(1000,player,"m4")
	game.end_match("blue")
	assert(main.state=="post_match" and main.post_result.bestPlay.kills==2)
	assert(not player.visible and not enemy.visible, "Source disposes live actors on entry to postmatch")
	main._begin_best_play()
	assert(is_instance_valid(main.replay) and main.replay.kind=="best_play")
	assert(main.ui.replay_overlay.visible and not main.ui.menu.visible)
	main._physics_process(0.2)
	assert(is_equal_approx(main.replay.elapsed,0.17))
	main.replay.advance(100.0)
	main._physics_process(0.01)
	assert(not is_instance_valid(main.replay) and main.ui.screen=="postmatch")
	assert(main.ui.menu.visible and not main.ui.replay_overlay.visible and not player.visible)
	main._begin_best_play()
	Input.action_press("jump")
	main._physics_process(0.01)
	Input.action_release("jump")
	assert(not is_instance_valid(main.replay) and main.ui.menu.visible)
	main.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("REPLAY_INTEGRATION_VERIFICATION: real Main/Match death capture, settings FOV, hidden live actors, held final frame, SPACE skip, timed respawn, disabled killcam, two-kill best play, playback completion/skip and postmatch visibility passed.")
	quit()
