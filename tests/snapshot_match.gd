extends SceneTree
## Static full-match comparison using the real session/HUD with no input grab.
const SESSION=preload("res://scripts/game/match_session.gd")
const UI=preload("res://scripts/ui/game_ui.gd")
func _initialize()->void:call_deferred("_capture")
func _capture()->void:
	root.size=Vector2i(1280,720)
	var ui=UI.new()
	root.add_child(ui)
	var game_match
	for id in ["desert_town","forest_facility","urban_docks"]:
		if is_instance_valid(game_match):game_match.free()
		game_match=SESSION.new()
		root.add_child(game_match)
		game_match.start({"mapId":id,"mode":"tdm","botCount":0,"difficulty":"regular","hardcore":false},ui.store.get_loadout(0),ui.store.get_settings())
		game_match.state="live"
		game_match.elapsed=0.0
		var actor=game_match.player
		actor.position=Vector3(-40,game_match.map.height_at(-40,0),0)
		actor.rotation.y=-PI/2.0
		actor.camera.rotation=Vector3.ZERO
		actor.camera.position.y=1.7
		ui.screen="match"
		ui.menu.hide()
		ui.scoreboard.hide()
		ui.streak_menu.hide()
		ui.hud.show()
		ui.update_hud(game_match.hud_state())
		for _frame in range(60):await process_frame
		ui.update_hud(game_match.hud_state())
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://assets/maps/previews/match_%s.png"%id)
		print("MATCH RENDERED %s"%id)
	game_match.free()
	ui.free()
	quit()
