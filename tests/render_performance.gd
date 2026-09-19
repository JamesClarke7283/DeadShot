extends SceneTree
## Frame-cost and draw-call report for the realistic renderer.
##
## The map now renders with real PSSM sun shadows, sky-driven ambient, SSAO and
## glow, so this measures the shipped configuration rather than comparing two
## shadow paths.
const SESSION=preload("res://scripts/game/match_session.gd")
const STORE=preload("res://scripts/persistence/save_store.gd")
const MAIN=preload("res://scripts/core/main.gd")
func _initialize()->void:call_deferred("_run")
func _run()->void:
	root.size=Vector2i(1280,720)
	var bootstrap=MAIN.new()
	bootstrap._setup_input()
	bootstrap.free()
	var store=STORE.new()
	seed(41)
	var session=SESSION.new()
	root.add_child(session)
	session.start({"mapId":"desert_town","mode":"tdm","botCount":8,"difficulty":"regular"},store.get_loadout(0),store.get_settings())
	session.state="live"
	session.player.position=Vector3(-40,0,0)
	session.player.rotation.y=-PI/2
	for i in range(30):
		session.tick(1.0/60.0)
		await process_frame
	var start=Time.get_ticks_usec()
	for i in range(120):
		session.tick(1.0/60.0)
		await process_frame
	var seconds=(Time.get_ticks_usec()-start)/1000000.0
	var fps: float = (120.0/seconds) if seconds > 0.0 else 0.0
	print("RENDER PERFORMANCE: %.1f fps, %.1f ms/frame, %d drawcalls, %d objects, %d primitives"%[
		fps,
		seconds/120.0*1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	session.free()
	await process_frame
	quit()
