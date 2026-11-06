extends SceneTree
## Regression checks for redundant per-frame work and simulation-rate timing.
const UI = preload("res://scripts/ui/game_ui.gd")
const RECORDER = preload("res://scripts/game/replay_recorder.gd")
const NETWORK = preload("res://scripts/game/match_network.gd")
var failures: Array[String] = []
var checks := 0

class TrackedEffects extends "res://scripts/ui/screen_effects.gd":
	var renders := 0
	func _render() -> void:
		renders += 1
		super._render()

class FakeWeapon extends RefCounted:
	var definition := {"id": "m4"}

class FakeActor extends RefCounted:
	var position := Vector3.ZERO
	var actor_id := 1
	var team := "blue"
	var is_player := true
	var alive := true
	var firing := false
	var moving := false
	var weapon := FakeWeapon.new()
	var radar_shots := 0
	var radar_last_shot := 0.0
	var radar_shot_position := Vector3.ZERO
	func aim_direction() -> Vector3: return Vector3.FORWARD

class FakeMatch extends RefCounted:
	var player := FakeActor.new()
	var actors: Array = []
	var elapsed := 0.0
	var warmup := 0.0
	var ui_time := 0.0
	var state := "live"
	var winner: Variant = null
	var scores := {}
	var tiers := {}
	var objective = null
	func _init() -> void: actors = [player]
	func score_rows() -> Array: return []

class FakeClient extends RefCounted:
	var state_count := 0
	var match_count := 0
	func is_host() -> bool: return true
	func send_state(_value: Dictionary) -> void: state_count += 1
	func send_bots(_value: Array) -> void: pass
	func send_match_state(_value: Dictionary) -> void: match_count += 1

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func network_counts(step: float) -> Vector2i:
	var game_match := FakeMatch.new()
	var client := FakeClient.new()
	var network := NETWORK.new()
	network.game_match = game_match
	network.client = client
	network.is_host = true
	for index in range(roundi(30.0 / step)):
		game_match.elapsed += step
		game_match.ui_time = game_match.elapsed
		network.tick(step)
	var result := Vector2i(client.state_count, client.match_count)
	network.free()
	return result

func run() -> void:
	for step in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]:
		var recorder := RECORDER.new(10.0, 30.0)
		var attempts := 0
		for index in range(roundi(1.0 / step)):
			var time: float = float(index) * float(step)
			if recorder.should_record(time):
				attempts += 1
				recorder.record(time, [{"id": 1}])
		check(absi(attempts - 30) <= 1, "Replay capture stays at 30 Hz with %d Hz input" % roundi(1.0 / step))
		check(recorder.frames.size() == attempts, "Replay predicate and recorder accept identical frames")

	for step in [1.0 / 30.0, 1.0 / 60.0]:
		var counts := network_counts(step)
		check(absi(counts.x - 600) <= 2, "Player snapshots retain 20 Hz at %d Hz simulation" % roundi(1.0 / step))
		check(absi(counts.y - 120) <= 1, "Match snapshots retain 4 Hz at %d Hz simulation" % roundi(1.0 / step))
	var burst_match := FakeMatch.new()
	var burst_client := FakeClient.new()
	var burst_network := NETWORK.new()
	burst_network.game_match = burst_match
	burst_network.client = burst_client
	burst_network.is_host = true
	burst_network.tick(5.0)
	check(burst_client.state_count == 1 and burst_client.match_count == 1, "A long frame emits at most one snapshot of each type")
	burst_network.tick(1.0 / 600.0)
	check(burst_client.state_count == 1 and burst_client.match_count == 1, "Discarded backlog does not cause an immediate second snapshot")
	burst_network.free()

	var effects := TrackedEffects.new()
	root.add_child(effects)
	await process_frame
	var initial_renders: int = effects.renders
	for index in range(30):
		effects.set_direct({"health": 100})
	check(effects.renders == initial_renders, "Unrelated HUD values do not render screen effects")
	effects.set_direct({"flashOpacity": 0.4})
	var active_renders: int = effects.renders
	for index in range(30):
		effects.set_direct({"flashOpacity": 0.4})
	check(effects.renders == active_renders, "Identical direct effect values are deduplicated")
	effects.set_direct({"flashOpacity": 0.0})
	check(not effects.visible, "The final zero effect still hides the compositor")
	effects.set_direct({"damageOpacity": 0.000001})
	check(effects.visible, "A small nonzero direct effect remains visible")
	effects.set_direct({"damageOpacity": 0.0})
	check(not effects.visible, "A near-zero to exact-zero transition still clears the compositor")

	var ui := UI.new()
	root.add_child(ui)
	await process_frame
	ui.show_main_menu()
	var logo := ui.menu.find_child("DeadShotLogo", true, false) as TextureRect
	check(logo != null and logo.texture != null, "Main menu uses the DeadShot vector logo")
	if logo != null and logo.texture != null:
		check(logo.texture.get_width() == 960 and logo.texture.get_height() == 200, "Logo imports at its authored vector dimensions")
	var rows: Array = [{"id": 1, "name": "Player", "kills": 5, "deaths": 1, "assists": 2, "score": 550, "team": "blue", "isPlayer": true}]
	ui.show_scoreboard(true, rows, 5, 2, "tdm")
	var first_table := ui.scoreboard.get_child(0).get_instance_id()
	for index in range(120):
		ui.show_scoreboard(true, rows, 5, 2, "tdm")
	check(ui.scoreboard.get_child(0).get_instance_id() == first_table, "Unchanged scoreboard retains its controls for 120 refreshes")
	rows[0].score = 600
	ui.show_scoreboard(true, rows, 6, 2, "tdm")
	check(ui.scoreboard.get_child(0).get_instance_id() != first_table, "Changed scores rebuild the scoreboard")
	ui.show_scoreboard(false)
	check(not ui.scoreboard.visible, "Releasing the scoreboard hides it immediately")

	effects.queue_free()
	ui.queue_free()
	await process_frame
	print("RUNTIME OPTIMIZATIONS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
