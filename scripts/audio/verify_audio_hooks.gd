extends SceneTree

class SpyAudio extends Node:
	var events:Array=[]
	var intensity:=0.0
	var duck:=0.0
	var pulses:=0
	var deafens:=0
	func play_weapon(id,at,local):events.append(["weapon",id,at,local])
	func play_reload():events.append(["reload"])
	func play_hit_marker(headshot,killed):events.append(["hit",headshot,killed])
	func play_explosion(at,size):events.append(["explosion",at,size])
	func set_music_intensity(value):intensity=value
	func set_music_duck(value):duck=value
	func pulse_music():pulses+=1
	func deafen(_duration):deafens+=1

class PassiveBrain extends RefCounted:
	func tick(_actor,_dt,_match):pass

func _initialize():call_deferred("run")

func run():
	var main=load("res://scripts/core/main.gd").new()
	main.set_physics_process(false)
	root.add_child(main)
	await process_frame
	assert(main.audio._intensity==0.0,"First menu starts at source score intensity zero")
	main.audio.free()
	var audio:=SpyAudio.new()
	main.add_child(audio)
	main.audio=audio
	main.start_match({"mapId":"desert_town","mode":"tdm","botCount":1,"difficulty":"recruit","classSlot":0,"hardcore":false})
	var game=main.game_match
	game.state="live"
	game.actors[1].brain=PassiveBrain.new()
	assert(audio.intensity==0.4)
	game.player.weapon.trigger=true
	game.player.weapon.tick(0.1,game.player,game)
	assert(audio.events.size()==1 and audio.events[0][0]=="weapon" and audio.events[0][3])
	game.player.weapon.trigger=false
	game.player.weapon.reload()
	assert(audio.events[-1][0]=="reload")
	var count:=audio.events.size()
	game.reload_started(game.actors[1])
	assert(audio.events.size()==count,"Source does not play bot reloads")
	var listener:Vector3=main.get_viewport().get_camera_3d().global_position
	main._weapon_sound("m4",listener+Vector3.RIGHT*89.0,false)
	assert(audio.events.size()==count+1 and not audio.events[-1][3])
	main._weapon_sound("m4",listener+Vector3.RIGHT*90.0,false)
	assert(audio.events.size()==count+1,"Enemy shots at or beyond 90 m are not played")
	game.player_hit.emit(true,true)
	assert(audio.events[-1]==["hit",true,true])
	game.kill_event.emit({"killer":game.player.display_name,"victim":"Enemy","weapon":"m4","headshot":true,"killerTeam":"blue","victimTeam":"red"})
	assert(audio.pulses==1)
	game.explode(Vector3.ZERO,5.5,0,game.player,"semtex")
	assert(audio.events[-1]==["explosion",Vector3.ZERO,1.375])
	main._screen_effect("deafen",1.0,2.0)
	assert(audio.deafens==0,"Source equipment deafen is screen state only")
	game.player.health=34.0
	main._physics_process(0.01)
	assert(audio.duck==0.7)
	game.end_match("blue")
	assert(audio.intensity==0.2 and audio.duck==0.0,"Leaving Playing resets score intensity and low-health duck")
	main.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("AUDIO_HOOK_VERIFICATION: real Main/Match player fire/reload/hit, bot reload silence, 90 m enemy cutoff, single kill pulse, exact explosion size, state-only deafen, health duck and postmatch score reset passed.")
	quit()
