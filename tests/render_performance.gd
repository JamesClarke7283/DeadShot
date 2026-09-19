extends SceneTree
## Same GPU/scene comparison of native fallback and exact source shadow path.
const SESSION=preload("res://scripts/game/match_session.gd")
const STORE=preload("res://scripts/persistence/save_store.gd")
const MAIN=preload("res://scripts/core/main.gd")
const MATERIALS=preload("res://scripts/world/map_material.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
	root.size=Vector2i(1280,720)
	var bootstrap=MAIN.new()
	bootstrap._setup_input()
	bootstrap.free()
	var store=STORE.new()
	for kind in ["source","native"]:
		seed(41)
		var session=SESSION.new()
		root.add_child(session)
		session.start({"mapId":"desert_town","mode":"tdm","botCount":8,"difficulty":"regular"},store.get_loadout(0),store.get_settings())
		session.state="live"
		session.player.position=Vector3(-40,0,0)
		session.player.rotation.y=-PI/2
		var source_shadow=session.map.get_node("SourceShadow")
		if kind=="native":
			source_shadow.set_process(false)
			source_shadow.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
			MATERIALS.clear_source_shadow(source_shadow.get_instance_id())
			session.map.sun.shadow_enabled=true
		for i in range(30):
			session.tick(1.0/60.0)
			await process_frame
		var start=Time.get_ticks_usec()
		for i in range(120):
			session.tick(1.0/60.0)
			await process_frame
		var seconds=(Time.get_ticks_usec()-start)/1000000.0
		print("RENDER PERFORMANCE %s: %.1f fps, %.1f ms/frame, %d drawcalls, %d proxies"%[kind,120.0/seconds,seconds/120.0*1000,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),source_shadow.proxies.size()])
		session.free()
		await process_frame
	quit()
