class_name AudioManager
extends Node
## Native playback of the unchanged source WebAudio synthesizers, captured at
## build time. Six synchronized stems retain the source's adaptive 112-BPM score.

const BUS_MASTER := "DeadShotMaster"
const BUS_SFX := "DeadShotSFX"
const BUS_MUSIC := "DeadShotMusic"
const BUS_SCORE := "DeadShotScore"
const STEMS := ["pad", "bass", "arp", "drums", "drums_hats", "drums_kicks"]
const EXPLOSION_SIZES := [0.2,0.25,0.375,0.5,0.75,1.0,1.25,1.375,1.5,1.75,2.0]
var _catalog: Dictionary = {}
var _streams: Dictionary = {}
var _music_players: Dictionary = {}
var _spatial_players:Array=[]
var _lowpass: AudioEffectLowPassFilter
var _music_tween: Tween
var _deafen_tween: Tween
var _intensity := 0.0
var _pulse := 0.0
var _duck := 1.0
var _mix_level := 0.0
var _mix_master := 0.5
var _mix_filter := 700.0
var _layer_gains:Dictionary={"pad":0.0,"bass":0.0,"arp":0.0,"drums":0.0}
var _pulse_clock := 0.0
var _sfx_volume := 0.9
var _deafen_gain := 1.0
var _playing := false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	_rng.randomize()
	_bus(BUS_MASTER, "Master")
	_bus(BUS_SFX, BUS_MASTER)
	_bus(BUS_MUSIC, BUS_MASTER)
	var score_bus := _bus(BUS_SCORE, BUS_MUSIC)
	if AudioServer.get_bus_effect_count(score_bus) == 0:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 700.0
		_lowpass.resonance = 1.0
		AudioServer.add_bus_effect(score_bus, _lowpass)
	else:
		_lowpass = AudioServer.get_bus_effect(score_bus, 0) as AudioEffectLowPassFilter
	apply_settings({})

func _bus(name_: String, send: String) -> int:
	var index := AudioServer.get_bus_index(name_)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, name_)
	AudioServer.set_bus_send(index, send)
	return index

func apply_settings(settings: Dictionary) -> void:
	_sfx_volume = float(settings.get("sfxVolume", settings.get("sfx", 0.9)))
	_set_bus_gain(BUS_MASTER, float(settings.get("masterVolume", settings.get("master", 0.8))))
	_set_bus_gain(BUS_SFX, _sfx_volume * _deafen_gain)
	_set_bus_gain(BUS_MUSIC, float(settings.get("musicVolume", settings.get("music", 0.5))))

func _set_bus_gain(bus: String, gain: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.00001, gain)))
		AudioServer.set_bus_mute(index, gain <= 0.0)

func _stream(id: String) -> AudioStreamWAV:
	if _streams.has(id):
		return _streams[id]
	if not _catalog.get("sounds", {}).has(id):
		push_warning("Unknown audio: " + id)
		return null
	var record: Dictionary = _catalog.sounds[id]
	# Imported streams resolve through .import remaps in exported games. The raw
	# fallback also works immediately after regenerating assets before a scan.
	var result: AudioStreamWAV
	if ResourceLoader.exists(record.file):
		result = load(record.file) as AudioStreamWAV
	else:
		result = AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(record.file))
	if record.loop:
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_begin = 0
		result.loop_end = int(record.frames)
	_streams[id] = result
	return result

func _play(id: String, world_position: Variant = null, gain: float = 1.0) -> Node:
	var stream := _stream(id)
	if stream == null:
		return null
	var restore: float = float(_catalog.sounds[id].restoreGain)
	if world_position is Vector3:
		var player := AudioStreamPlayer3D.new()
		player.stream = stream
		player.bus = BUS_SFX
		player.unit_size = 8.0
		# WebAudio clamps distance at 220 m; it does not fade linearly to silence
		# there as Godot max_distance does. Apply its exact inverse gain ourselves.
		player.max_distance = 0.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.attenuation_filter_cutoff_hz = 20500.0
		player.attenuation_filter_db = 0.0
		player.max_db = 6.0
		player.volume_db = linear_to_db(maxf(gain * restore, 0.00001))
		add_child(player)
		player.global_position = world_position
		_spatial_players.append({"player":player,"gain":gain*restore})
		_update_spatial_player(_spatial_players[-1])
		player.finished.connect(player.queue_free)
		player.play()
		return player
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_SFX
	player.volume_db = linear_to_db(maxf(gain * restore, 0.00001))
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player

func play_weapon(weapon_id: String, world_position: Variant = null, is_player: bool = true) -> void:
	var category: String = _catalog.get("weapons", {}).get(weapon_id, weapon_id)
	_play("gun_%s_%d" % [category, _rng.randi_range(0, 3)], null if is_player else world_position)

func play_reload() -> void:
	_play("reload")

func play_hit_marker(headshot: bool = false, _killed: bool = false) -> void:
	_play("headshot" if headshot else "hit")

func play_explosion(world_position: Vector3, size: float = 1.0) -> void:
	_play(explosion_sound_id(size),world_position)

static func explosion_sound_id(size:float)->String:
	var closest:float=EXPLOSION_SIZES[0]
	for candidate in EXPLOSION_SIZES:
		if absf(candidate-size)<absf(closest-size):closest=candidate
	var suffix := str(int(closest)) if closest == floorf(closest) else str(closest)
	return "explosion_"+suffix

func play_footstep(world_position: Variant = null, is_player: bool = false) -> void:
	_play("footstep", null if is_player else world_position)

func play_ui_click() -> void:
	_play("click")

func play_beep() -> void:
	_play("beep")

func deafen(duration: float) -> void:
	if _deafen_tween != null:
		_deafen_tween.kill()
	_deafen_gain = 0.05 / maxf(_sfx_volume, 0.00001)
	_set_bus_gain(BUS_SFX, 0.05)
	_deafen_tween = create_tween()
	_deafen_tween.tween_property(self, "_deafen_gain", 1.0, maxf(duration, 0.01))

func start_music() -> void:
	if _playing:
		return
	_playing = true
	for stem in STEMS:
		var player := AudioStreamPlayer.new()
		player.name = "Score_" + stem
		player.stream = _stream("music_" + stem)
		player.bus = BUS_SCORE
		add_child(player)
		_music_players[stem] = player
	# All stems enter the same audio mixing quantum and share exact loop length.
	_update_music_mix()
	for player in _music_players.values():
		player.play()
	_apply_dynamics(0.1)

func stop_music() -> void:
	_playing = false
	for player in _music_players.values():
		player.stop()
		player.queue_free()
	_music_players.clear()

func set_music_intensity(level: float) -> void:
	_intensity = clampf(level, 0.0, 1.0)
	_apply_dynamics(0.5)

func set_music_duck(amount: float) -> void:
	_duck = 1.0 - clampf(amount, 0.0, 1.0) * 0.7
	_apply_dynamics(0.4)

func pulse_music(amount: float = 0.35) -> void:
	_pulse = minf(0.7, _pulse + amount)
	_apply_dynamics(0.15)

func _apply_dynamics(duration: float) -> void:
	if not is_inside_tree():
		return
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_mix_level=minf(1.0,_intensity+_pulse)
	_music_tween.tween_property(self,"_mix_filter",700.0+_mix_level*2600.0,duration)
	_music_tween.tween_property(self,"_mix_master",0.5*_duck*(1.0+_mix_level*0.4),duration)
	var targets:Dictionary={"pad":0.34,"bass":0.1+_mix_level*0.42,"arp":maxf(0.0,_mix_level-0.12)*0.5,"drums":maxf(0.0,_mix_level-0.26)}
	for stem in targets:
		_music_tween.tween_method(_set_layer_gain.bind(stem),float(_layer_gains[stem]),float(targets[stem]),duration)

func _set_layer_gain(value:float,stem:String)->void:
	_layer_gains[stem]=value

func _process(dt: float) -> void:
	for index in range(_spatial_players.size()-1,-1,-1):
		if not is_instance_valid(_spatial_players[index].player):
			_spatial_players.remove_at(index)
		else:
			_update_spatial_player(_spatial_players[index])
	if _deafen_tween != null and _deafen_tween.is_running():
		_set_bus_gain(BUS_SFX, _sfx_volume * _deafen_gain)
	if not _playing:
		return
	_pulse_clock += dt
	if _pulse_clock >= 0.09:
		_pulse_clock = fmod(_pulse_clock, 0.09)
		if _pulse > 0.005:
			_pulse *= 0.975
			if _pulse <= 0.005:
				_pulse = 0.0
			_apply_dynamics(0.3)
	_update_music_mix()

static func spatial_gain(distance:float)->float:
	return 8.0/(8.0+1.1*(clampf(distance,8.0,220.0)-8.0))

func _update_spatial_player(record:Dictionary)->void:
	var listener:=get_viewport().get_camera_3d()
	var origin:Vector3=listener.global_position if listener else Vector3.ZERO
	var distance:float=record.player.global_position.distance_to(origin)
	record.player.volume_db=linear_to_db(maxf(0.00001,record.gain*spatial_gain(distance)))

func _update_music_mix() -> void:
	if _lowpass != null:
		_lowpass.cutoff_hz = _mix_filter
	var gains:Dictionary=_layer_gains.duplicate()
	gains.drums_hats=float(_layer_gains.drums) if _mix_level>0.6 else 0.0
	gains.drums_kicks=float(_layer_gains.drums) if _mix_level>0.65 else 0.0
	for stem in _music_players:
		var gain: float = float(gains[stem]) * _mix_master * float(_catalog.sounds["music_" + stem].restoreGain)
		_music_players[stem].volume_db = linear_to_db(maxf(0.00001, gain))

func _exit_tree() -> void:
	stop_music()
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	if _music_tween != null:
		_music_tween.kill()
	if _deafen_tween != null:
		_deafen_tween.kill()
	_streams.clear()
	_spatial_players.clear()
