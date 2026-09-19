extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func until(condition: Callable, message: String) -> void:
	var end := Time.get_ticks_msec()+3000
	while not condition.call() and Time.get_ticks_msec()<end:await process_frame
	check(condition.call(),message)

func run() -> void:
	var main=load("res://scripts/core/main.gd").new()
	root.add_child(main)
	main.set_physics_process(false)
	main.ui.show_multiplayer()
	var url="ws://127.0.0.1:%d/ws" % (24000+OS.get_process_id()%1000)
	main.ui.multiplayer_connect.emit({"url":url,"name":"Host","room":"LOBBY","asHost":true})
	await until(func():return not main.ui.lobby_state.is_empty(),"Host button opens native room")
	check(main.relay.running and main.ui.lobby_state.isHost,"Host owns relay and receives host controls")
	var guest=load("res://scripts/net/net_client.gd").new()
	root.add_child(guest)
	guest.connect_room(url,"LOBBY","Guest")
	await until(func():return main.ui.lobby_state.players.size()==2,"Lobby displays joining player")
	main.ui.multiplayer_ready.emit(true)
	await until(func():return main.ui.lobby_state.ready,"Ready button reaches relay")
	main.ui.multiplayer_settings.emit({"mapId":"urban_docks","mode":"ctf","botCount":0,"difficulty":"veteran","hardcore":true})
	await until(func():return guest.settings.mode=="ctf","Host settings reach guest")
	main.ui.multiplayer_start.emit()
	await until(func():return main.state=="playing","Start button creates live match")
	check(main.game_match.network!=null and main.game_match.mode.id=="ctf","Match retains network and selected mode")
	check(main.game_match.player.max_health==30,"Lobby hardcore setting reaches combatant")
	check(main.ui.screen=="match" and not main.ui.menu.visible,"Lobby hides when match begins")
	main.ui.leave_match.emit()
	check(main.state=="main_menu" and main.net==null and main.relay==null,"Leave match disconnects client and embedded relay")
	guest.disconnect_room()
	for frame in 12:await process_frame
	guest.free()
	main.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Network lobby integration: %s" % ("PASS" if failures.is_empty() else "%d failures"%failures.size()))
	quit(0 if failures.is_empty() else 1)
