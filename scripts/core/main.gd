extends Node
const Session = preload("res://scripts/game/match_session.gd")
var ui
var game_match
var audio
var state: String = "main_menu"
var paused: bool = false
var last_config: Dictionary = {}
var replay
var post_result: Dictionary = {}
var _streak_menu_options: Array = []
var net
var relay
var network_config: Dictionary = {}
var gamepad

func _ready() -> void:
	_setup_input()
	gamepad=preload("res://scripts/input/gamepad.gd").new()
	add_child(gamepad)
	var Interface = load("res://scripts/ui/game_ui.gd")
	ui = Interface.new()
	ui.preserve_virtual_action=func(action):return gamepad.held.get(action,false)
	add_child(ui)
	ui.start_match.connect(start_match)
	ui.resume_match.connect(resume_match)
	ui.leave_match.connect(leave_match)
	ui.quit_requested.connect(func():get_tree().quit())
	ui.settings_changed.connect(apply_settings)
	ui.console_command.connect(_console_command)
	ui.best_play_requested.connect(_begin_best_play)
	ui.streak_selected.connect(_activate_streak)
	ui.multiplayer_connect.connect(_connect_multiplayer)
	ui.multiplayer_ready.connect(func(ready):
		if is_instance_valid(net):net.set_ready(ready))
	ui.multiplayer_settings.connect(func(settings):
		if is_instance_valid(net):net.set_settings(settings))
	ui.multiplayer_start.connect(func():
		if is_instance_valid(net):net.start_match())
	ui.multiplayer_leave.connect(_leave_multiplayer)
	ui.touch_look.connect(func(delta):
		if state=="playing" and not paused and game_match and game_match.player and not is_instance_valid(replay):
			game_match.player.apply_recoil(-delta.y*0.004,-delta.x*0.004))
	if ResourceLoader.exists("res://scripts/audio/audio_manager.gd"):
		audio=load("res://scripts/audio/audio_manager.gd").new()
		add_child(audio)
		if audio.has_method("apply_settings"):
			audio.apply_settings(ui.store.get_settings())
		audio.start_music()
		audio.set_music_intensity(0.0)
	ui.show_main_menu()
	var arguments=OS.get_cmdline_user_args()
	if "--smoke-match" in arguments:
		start_match({"mapId":"desert_town","mode":"tdm","botCount":8,"difficulty":"regular","classSlot":0,"hardcore":false})

func start_match(config: Dictionary) -> void:
	_end_replay()
	ui.clear_screen_effects()
	if is_instance_valid(game_match):
		game_match.free()
	last_config=config.duplicate(true)
	game_match=Session.new()
	add_child(game_match)
	if config.get("networked",false) and is_instance_valid(net):
		game_match.network_client=net
	game_match.finished.connect(_match_finished)
	game_match.kill_event.connect(_kill_event)
	game_match.player_hit.connect(func(headshot,killed):
		ui.hit_marker(headshot)
		if audio:audio.play_hit_marker(headshot,killed))
	game_match.player_damaged.connect(func(angle,amount):
		ui.damage_from(angle)
		ui.apply_screen_effect("damage",minf(0.6,amount/60.0),0.5))
	game_match.weapon_sound.connect(_weapon_sound)
	game_match.reload_sound.connect(_reload_sound)
	game_match.screen_effect.connect(_screen_effect)
	game_match.killcam_ready.connect(_begin_killcam)
	game_match.explosion_sound.connect(func(at,radius):
		if audio:audio.play_explosion(at,minf(2.0,radius/4.0)))
	var loadout:Dictionary=ui.store.get_loadout(int(config.get("classSlot",0)))
	if not game_match.start(config,loadout,ui.store.get_settings()):
		game_match.queue_free()
		ui.show_main_menu()
		return
	state="playing"
	paused=false
	ui.show_match(bool(config.get("hardcore",false)))
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	if audio:audio.set_music_intensity(0.4)

func _connect_multiplayer(config: Dictionary) -> void:
	_leave_multiplayer()
	network_config=config.duplicate(true)
	state="multiplayer"
	# A local host can run the same room relay inside Godot; remote URLs use
	# their existing server (including the original browser/Deno relay).
	var url := str(config.get("url","ws://127.0.0.1:8090/ws"))
	var authority := url.get_slice("://",1).get_slice("/",0)
	var host := authority.get_slice(":",0)
	if not OS.has_feature("web") and config.get("asHost",false) and url.begins_with("ws://") and host in ["localhost","127.0.0.1"]:
		var port := int(authority.get_slice(":",1)) if ":" in authority else 80
		relay=preload("res://scripts/server/multiplayer_relay.gd").new()
		add_child(relay)
		var error: Error=relay.start(port)
		if error!=OK:
			relay.free()
			relay=null
			# The URL may already be served by another game instance.
	net=preload("res://scripts/net/net_client.gd").new()
	add_child(net)
	net.lobby.connect(_network_lobby)
	net.started.connect(_network_started)
	net.error.connect(_network_error)
	net.closed.connect(_network_closed)
	net.connect_room(url,str(config.get("room","")),str(config.get("name","Player")))

func _network_lobby(players: Array, host_id: int, settings: Dictionary) -> void:
	if state!="multiplayer" or not is_instance_valid(net):
		return
	var ready := false
	for person in players:
		if int(person.id)==net.self_id:
			ready=bool(person.ready)
	ui.set_lobby_state({"room":network_config.get("room",""),"isHost":net.is_host(),
		"selfId":net.self_id,"hostId":host_id,"ready":ready,"players":players,"settings":settings})

func _network_started(settings: Dictionary, _seed: int, _players: Array) -> void:
	var options := settings.duplicate(true)
	options.networked=true
	options.playerName=network_config.get("name","Player")
	options.classSlot=0
	start_match(options)

func _network_error(message: String) -> void:
	ui.set_network_status(message)
	ui.console_print(message+"\n")

func _network_closed() -> void:
	if state=="multiplayer":
		ui.lobby_state={}
		ui.set_network_status("Disconnected from the server.")
	elif state in ["playing","post_match"]:
		ui.console_print("Disconnected from the multiplayer server.\n")

func _leave_multiplayer() -> void:
	if is_instance_valid(net):
		if net.closed.is_connected(_network_closed):net.closed.disconnect(_network_closed)
		net.disconnect_room()
		net.queue_free()
		net=null
	if is_instance_valid(relay):
		relay.stop()
		relay.queue_free()
		relay=null

func _physics_process(dt: float) -> void:
	if state=="playing" and gamepad:
		gamepad.poll(dt,game_match.player if is_instance_valid(game_match) and not paused and not is_instance_valid(replay) else null)
	if state=="post_match" and is_instance_valid(replay):
		if replay.is_finished() or Input.is_action_just_pressed("jump"):
			_end_replay()
			_show_postmatch()
		else:replay.advance(dt)
		return
	if state!="playing" or paused or not is_instance_valid(game_match):
		return
	game_match.equipment_input_enabled=not ui.console_open
	game_match.tick(dt)
	# A scorestreak can synchronously finish the match during tick(). Its result
	# screen must not be replaced by the remaining live HUD/replay update.
	if state != "playing":
		return
	if is_instance_valid(replay):
		if game_match.player.alive or game_match.state=="end" or Input.is_action_just_pressed("jump"):
			game_match.respawn_player_now()
			_end_replay()
			ui.show_match(bool(last_config.get("hardcore",false)))
		else:
			game_match.set_live_visible(false)
			replay.advance(dt)
			return
	ui.update_hud(game_match.hud_state())
	_update_streak_ui()
	var show_scores=Input.is_action_pressed("scoreboard") and not bool(last_config.get("hardcore",false))
	ui.show_scoreboard(show_scores,game_match.score_rows(),game_match.team_kills("blue"),game_match.team_kills("red"),game_match.mode.id)
	if audio and game_match.player:audio.set_music_duck(0.7 if game_match.player.alive and game_match.player.health<35 else 0)

func _activate_streak(id: String) -> void:
	if state == "playing" and not paused and game_match and game_match.player and game_match.streaks:
		game_match.streaks.activate(game_match.player,id)

func _update_streak_ui() -> void:
	var held := Input.is_action_pressed("streaks")
	if not game_match.player or not game_match.streaks:
		ui.hide_streak_menu()
		return
	var options: Array = game_match.streaks.hud(game_match.player)
	options.sort_custom(func(a,b):return int(a.slot)<int(b.slot))
	if held and not bool(last_config.get("hardcore",false)):
		if not ui.streak_menu.visible or options != _streak_menu_options:
			ui.show_streak_menu(options)
			_streak_menu_options = options.duplicate(true)
	else:
		ui.hide_streak_menu()
	if held:
		var ids: Array = game_match.streaks.loadout_for(game_match.player.actor_id)
		for slot in mini(ids.size(),3):
			if Input.is_action_just_pressed("streak_slot_%d" % (slot + 1)):
				_activate_streak(str(ids[slot]))

func _notification(what:int)->void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT] and is_instance_valid(game_match):
		game_match.cancel_equipment_charges()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F11:
			var full=DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		if event.keycode==KEY_QUOTELEFT:
			ui.toggle_console()
			if is_instance_valid(game_match):
				game_match.cancel_equipment_charges()
			if not ui.console_open and state=="playing" and not paused:
				Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("pause") and state=="playing":
		if paused:
			resume_match()
		else:
			game_match.cancel_equipment_charges()
			paused=true
			ui.show_pause()
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if state=="playing" and not paused and game_match and game_match.player:
		game_match.equipment_input_enabled=not ui.console_open
		# Capture short keyboard taps even when press and release both arrive
		# between physics frames. Controller/touch actions are also polled.
		if not ui.console_open:
			for action in ["lethal","tactical"]:
				if event.is_action_pressed(action):game_match.begin_charged_throw(action)
				elif event.is_action_released(action):game_match.release_charged_throw(action)
		if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and not is_instance_valid(replay):
			game_match.player.look_motion(event.screen_relative)
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not ui.console_open:
			Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func resume_match() -> void:
	if not is_instance_valid(game_match):
		return
	game_match.cancel_equipment_charges()
	paused=false
	ui.show_match(bool(last_config.get("hardcore",false)))
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func leave_match() -> void:
	_end_replay()
	ui.clear_screen_effects()
	if gamepad:gamepad.release_all()
	state="main_menu"
	paused=false
	if is_instance_valid(game_match):
		game_match.queue_free()
		game_match=null
	_leave_multiplayer()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	ui.show_main_menu()
	if audio:
		audio.set_music_intensity(0.2)
		audio.set_music_duck(0)

func _match_finished(result: Dictionary) -> void:
	_end_replay()
	ui.clear_screen_effects()
	_leave_multiplayer()
	state="post_match"
	post_result=result
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if audio:
		audio.set_music_intensity(0.2)
		audio.set_music_duck(0)
	_show_postmatch()

func _show_postmatch()->void:
	game_match.set_live_visible(false)
	var result=post_result
	var winner_text="Draw"
	if result.winner is String:
		winner_text=str(result.winner).to_upper()+" team wins"
	elif result.winner!=null and game_match.scores.has(result.winner):
		winner_text=game_match.scores[result.winner].name+" wins"
	ui.show_postmatch(result.rows,result.blue,result.red,result.mode,winner_text,int(result.get("bestPlay",{}).get("kills",0)))

func _kill_event(event:Dictionary)->void:
	if bool(last_config.get("hardcore",false)):return
	ui.add_kill(event)
	if audio and game_match.player and event.killer==game_match.player.display_name and event.victim!=event.killer:
		audio.pulse_music()

func _begin_killcam(data:Dictionary)->void:
	if not ui.store.get_settings().get("killcam",true) or is_instance_valid(replay):return
	_begin_replay(data,"killcam")
	ui.show_replay("KILLED BY "+str(data.killerName).to_upper(),"Hold SPACE to skip",Color("ff6b6b"))

func _begin_best_play()->void:
	var data:Dictionary=post_result.get("bestPlay",{})
	if data.is_empty():return
	_begin_replay(data,"best_play")
	ui.show_replay("BEST PLAY — %d KILLS" % data.kills,"Hold SPACE to exit",Color("ffd166"))

func _begin_replay(data:Dictionary,kind:String)->void:
	_end_replay()
	game_match.set_live_visible(false)
	replay=load("res://scripts/game/replay_player.gd").new()
	add_child(replay)
	replay.setup(data,kind,game_match.player.camera if game_match.player else null)

func _end_replay()->void:
	if is_instance_valid(replay):
		replay.free()
		replay=null
	if is_instance_valid(game_match):
		game_match.set_live_visible(true)
		if game_match.player:game_match.player.camera.make_current()
	if ui:ui.hide_replay()

func apply_settings(settings: Dictionary) -> void:
	if is_instance_valid(game_match) and game_match.player:
		game_match.player.apply_settings(settings)
	if audio and audio.has_method("apply_settings"):
		audio.apply_settings(settings)

func _weapon_sound(id:String,at:Vector3,local:bool) -> void:
	if not local:
		var listener=get_viewport().get_camera_3d()
		if listener and listener.global_position.distance_to(at)>=90:return
	if audio and audio.has_method("play_weapon"):
		audio.play_weapon(id,at,local)

func _reload_sound() -> void:
	if audio and audio.has_method("play_reload"):
		audio.play_reload()

func _screen_effect(kind:String,intensity:float,duration:float) -> void:
	if ui.has_method("apply_screen_effect"):
		ui.apply_screen_effect(kind,intensity,duration)

func _setup_input() -> void:
	var keys={"forward":[KEY_W,KEY_UP],"back":[KEY_S,KEY_DOWN],"left":[KEY_A,KEY_LEFT],"right":[KEY_D,KEY_RIGHT],"jump":[KEY_SPACE],"crouch":[KEY_CTRL,KEY_C],"sprint":[KEY_SHIFT],"reload":[KEY_R],"lethal":[KEY_G],"tactical":[KEY_Q],"melee":[KEY_K],"interact":[KEY_E],"weapon_primary":[KEY_1],"weapon_secondary":[KEY_2],"fire_mode":[KEY_B],"scoreboard":[KEY_TAB],"streaks":[KEY_Z],"pause":[KEY_ESCAPE]}
	keys["streak_slot_1"] = [KEY_1,KEY_KP_1]
	keys["streak_slot_2"] = [KEY_2,KEY_KP_2]
	keys["streak_slot_3"] = [KEY_3,KEY_KP_3]
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event=InputEventKey.new()
			event.physical_keycode=key
			InputMap.action_add_event(action,event)
	for pair in [["fire",MOUSE_BUTTON_LEFT],["ads",MOUSE_BUTTON_RIGHT],["weapon_next",MOUSE_BUTTON_WHEEL_DOWN],["weapon_next",MOUSE_BUTTON_WHEEL_UP]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var event=InputEventMouseButton.new()
		event.button_index=pair[1]
		InputMap.action_add_event(pair[0],event)

func _console_command(text:String) -> void:
	ui.console_print(_run_dev_command(text) + "\n")

func _run_dev_command(text: String) -> String:
	var words=text.strip_edges().split(" ",false)
	if words.is_empty():
		return ""
	match words[0]:
		"help":
			return "commands: map <id>, give <streakId>, nuke, kill, heal, bots, state"
		"state":
			return "state=%s match=%s" % [state,game_match.state if is_instance_valid(game_match) else "none"]
		"map", "give", "nuke":
			if not is_instance_valid(game_match) or not game_match.player:
				return "no active match"
			var id: String = "uav" if words[0] == "map" else ("nuke" if words[0] == "nuke" else (words[1] if words.size()>1 else "undefined"))
			if not game_match.streaks.definitions.has(id):
				return "Unknown streak: " + id
			game_match.streaks.force_activate(game_match.player,id)
			if words[0] == "map":
				return "(map switching only in pre-match; gave UAV instead)"
			return "nuke incoming" if words[0] == "nuke" else "gave " + id
		"heal":
			if is_instance_valid(game_match) and game_match.player:
				game_match.player.health=game_match.player.max_health
			return "healed"
		"kill":
			if is_instance_valid(game_match) and game_match.player:
				game_match.player.apply_damage(999,null,"world")
			return "ouch"
		"bots":
			if not is_instance_valid(game_match):
				return "no match"
			return "%d bots" % game_match.actors.filter(func(actor):return actor != game_match.player and actor.brain != null).size()
	return "unknown: " + str(words[0])
