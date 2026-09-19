extends SceneTree

const Audio = preload("res://scripts/audio/audio_manager.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var audio := Audio.new()
	root.add_child(audio)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	for id in catalog.sounds:
		var stream: AudioStreamWAV = audio._stream(id)
		assert(stream != null)
		assert(stream.mix_rate == 44100)
		assert(stream.data.size() > 100)
		assert(absf(stream.get_length() - float(catalog.sounds[id].frames) / 44100.0) < 0.001)
		if catalog.sounds[id].loop:
			assert(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
			assert(stream.loop_end == 756000)
	for id in catalog.weapons:
		audio.play_weapon(id)
	var before:=audio.get_child_count()
	audio.play_weapon("knife")
	assert(audio.get_child_count()==before+1,"Source knife fire plays pistol category sound")
	audio.play_weapon("m4", Vector3(5, 1, -3), false)
	audio.play_explosion(Vector3.ZERO, 1.5)
	audio.play_reload()
	audio.play_hit_marker(true, true)
	assert(audio._pulse==0.0,"Hit marker cannot double-count the killfeed music pulse")
	assert(Audio.explosion_sound_id(0.8/4.0)=="explosion_0.2")
	assert(Audio.explosion_sound_id(1.5/4.0)=="explosion_0.375")
	assert(Audio.explosion_sound_id(5.5/4.0)=="explosion_1.375")
	assert(is_equal_approx(Audio.spatial_gain(4),1.0))
	assert(is_equal_approx(Audio.spatial_gain(16),8.0/(8.0+1.1*8.0)))
	assert(is_equal_approx(Audio.spatial_gain(500),8.0/(8.0+1.1*212.0)))
	audio.play_footstep(Vector3.ZERO)
	audio.play_ui_click()
	audio.play_beep()
	audio.apply_settings({"masterVolume": 0.4, "sfxVolume": 0.7, "musicVolume": 0.3})
	assert(absf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Audio.BUS_MASTER))) - 0.4) < 0.001)
	audio.start_music()
	assert(audio._music_players.size() == 6)
	audio._music_tween.pause()
	audio._music_tween.custom_step(0.05)
	assert(is_equal_approx(float(audio._layer_gains.pad),0.17),"Source layer gains ramp independently from silence")
	assert(is_equal_approx(float(audio._layer_gains.bass),0.05))
	audio._music_tween.custom_step(0.05)
	audio.set_music_intensity(0.4)
	audio._music_tween.pause()
	audio._music_tween.custom_step(0.25)
	assert(is_equal_approx(float(audio._layer_gains.arp),0.07),"Source arp gain ramps directly, without threshold delay")
	assert(is_equal_approx(audio._mix_master,0.54))
	audio.set_music_intensity(0.9)
	audio.set_music_duck(0.7)
	audio.deafen(0.1)
	await create_timer(0.6).timeout
	audio.stop_music()
	assert(audio._music_players.is_empty())
	audio.queue_free()
	await process_frame
	# The audio mixer releases its last playback references asynchronously.
	await create_timer(0.15).timeout
	print("NATIVE_AUDIO_VERIFICATION: ", catalog.sounds.size(), " source-rendered WAV assets, all weapon IDs, 3D effects, volume buses, synchronized music layers, ducking and cleanup passed.")
	quit()
