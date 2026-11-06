extends SceneTree
## Spawn safety on every map: enemies appear out of the player's sight and on the
## far side of the map, and the player respawns where no enemy bot can target
## them. Sight is judged independently of the spawn code, with the bots' own
## target test (`BotBrain._visible`) and the player's eye-to-head/chest boxes.
const Session = preload("res://scripts/game/match_session.gd")
const Data = preload("res://scripts/core/game_data.gd")
const MAPS = preload("res://scripts/world/map_catalog.gd").IDS
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _player_sees(game, viewer, target) -> bool:
	for height: float in [1.6, 1.0]:
		var to: Vector3 = target.position + Vector3.UP * height
		var offset: Vector3 = to - viewer.eye_position()
		if game.map.raycast_boxes(viewer.eye_position(), offset.normalized(), offset.length()) < 0:
			return true
	return false

func _bot_targets(bot, target, game) -> bool:
	return bot.position.distance_to(target.body_position()) <= float(bot.brain.params.viewRange) and bot.brain._visible(bot, target, game)

func _enemies(game) -> Array:
	return game.actors.filter(func(actor): return actor != game.player and (game.player.team == "ffa" or actor.team != game.player.team))

func run() -> void:
	seed(9031)
	var input_setup = load("res://scripts/core/main.gd").new()
	input_setup._setup_input()
	input_setup.free()
	var defaults: Dictionary = Data.table("default_save")
	var total_ms := 0.0
	var slowest_ms := 0.0
	var spawns := 0
	var far_misses := 0
	for map_id: String in MAPS:
		for mode_id: String in ["tdm", "ffa", "ctf"]:
			var game = Session.new()
			root.add_child(game)
			check(game.start({"mapId": map_id, "mode": mode_id, "botCount": 10, "difficulty": "regular"}, defaults.classes[0], defaults.settings), "Start %s/%s" % [map_id, mode_id])
			game.state = "live"
			var player = game.player
			var label := "%s/%s" % [map_id, mode_id]
			for bot in _enemies(game):
				check(not _player_sees(game, player, bot), "%s: opening enemy spawn is in the player's sight" % label)
			var pool: Array[Dictionary] = game.map.spawn_pool()
			check(pool.size() > game.map.spawn_points.size(), "%s: open ground adds spawn candidates" % label)
			for trial in 10:
				# The player may stand anywhere a person can, including deep in enemy ground.
				player.position = pool[randi() % pool.size()].position
				player.rotation.y = randf() * TAU
				for bot in _enemies(game):
					var started := Time.get_ticks_usec()
					game._spawn(bot)
					var spent := float(Time.get_ticks_usec() - started) / 1000.0
					total_ms += spent
					slowest_ms = maxf(slowest_ms, spent)
					spawns += 1
					check(not _player_sees(game, player, bot), "%s: enemy spawned in sight at %s, player at %s" % [label, bot.position, player.position])
					check(not _bot_targets(bot, player, game), "%s: enemy can target the player on arrival at %s" % [label, bot.position])
					var farthest := 0.0
					for candidate: Dictionary in pool:
						if game._spawn_allowed(candidate, bot):
							farthest = maxf(farthest, candidate.position.distance_to(player.position))
					if bot.position.distance_to(player.position) < minf(farthest, maxf(Session.SPAWN_MIN_FAR, farthest * Session.SPAWN_FAR_FRACTION)):
						far_misses += 1
			for trial in 6:
				# Scatter the enemies, then respawn the player away from all of them.
				for bot in _enemies(game):
					bot.position = pool[randi() % pool.size()].position
				var started := Time.get_ticks_usec()
				game._spawn(player)
				var spent := float(Time.get_ticks_usec() - started) / 1000.0
				total_ms += spent
				slowest_ms = maxf(slowest_ms, spent)
				spawns += 1
				var targeted := _enemies(game).filter(func(bot): return _bot_targets(bot, player, game))
				if not targeted.is_empty():
					# Only a failure when a hidden spot existed that the search passed over.
					var threats: Array = game._spawn_threats(player)
					var avoidable := false
					for candidate: Dictionary in pool:
						if not game._spawn_allowed(candidate, player):
							continue
						if threats.all(func(threat): return not game._spawn_exposed(candidate.position, threat, 1.7)):
							avoidable = true
							break
					check(not avoidable, "%s: player respawned where %d enemies can target them (%s)" % [label, targeted.size(), game.spawn_trace])
			game.free()
			await process_frame
	var far_rate := float(far_misses) / maxf(1.0, float(spawns))
	check(far_rate <= 0.03, "Enemies spawn on the far side of the map (%d of %d short)" % [far_misses, spawns])
	check(total_ms / maxf(1.0, float(spawns)) < 12.0, "Average spawn decision stays cheap (%.2f ms)" % (total_ms / maxf(1.0, float(spawns))))
	for failure in failures.slice(0, 12):
		print("  ", failure)
	print("SPAWN SAFETY: %d checks, %d failures; %d spawns, %.2f ms average, %.2f ms slowest, %d short of the far side" % [checks, failures.size(), spawns, total_ms / maxf(1.0, float(spawns)), slowest_ms, far_misses])
	quit(0 if failures.is_empty() else 1)
