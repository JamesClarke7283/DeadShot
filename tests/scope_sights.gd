extends SceneTree
## Aim-down-sight optics: every sight ends on the line of fire at full aim,
## magnifies by its rating, opens a see-through window through its housing,
## hands a scope's view to the eyepiece picture, and resets on death.
const Session = preload("res://scripts/game/match_session.gd")
const Actor = preload("res://scripts/game/combatant.gd")
const Sights = preload("res://scripts/game/sights.gd")
const Visuals = preload("res://scripts/visuals/visual_factory.gd")
const Data = preload("res://scripts/core/game_data.gd")
const QUALITY = preload("res://scripts/world/graphics_quality.gd")
const Replay = preload("res://scripts/game/replay_player.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _aim(player, amount: float) -> void:
	player.ads_factor = amount
	player._update_viewmodel(0.0)

func run() -> void:
	var input_setup = load("res://scripts/core/main.gd").new()
	input_setup._setup_input()
	input_setup.free()
	var expected := {
		"reddot": ["ak12", ["reddot", "compensator"], "reflex", 1.5], "holo": ["m4", ["holo"], "reflex", 1.4],
		"acog": ["ksg", ["acog"], "scope", 4.0], "kar98": ["kar98", [], "scope", 6.0], "barrett": ["barrett", [], "scope", 6.0],
		"mk14": ["mk14", [], "scope", 3.0], "m4": ["m4", [], "reflex", 1.35], "mp5": ["mp5", [], "reflex", 1.35],
		"m249": ["m249", [], "reflex", 1.35], "m9": ["m9", [], "iron", 1.15], "spas12": ["spas12", [], "iron", 1.15],
		"rpg7": ["rpg7", [], "iron", 1.15], "knife": ["knife", [], "none", 1.0],
	}
	for key: String in expected:
		var entry: Array = expected[key]
		var profile: Dictionary = Sights.profile(entry[0], entry[1])
		check(profile.kind == entry[2] and is_equal_approx(float(profile.zoom), float(entry[3])), "%s aims through a %s at %sx" % [key, entry[2], entry[3]])
	check(Sights.zoomed_fov(80.0, 1.0) == 80.0, "No magnification leaves the settings FOV untouched")
	check(is_equal_approx(tan(deg_to_rad(Sights.zoomed_fov(75.0, 4.0)) * 0.5) * 4.0, tan(deg_to_rad(75.0) * 0.5)), "Magnification divides the half-angle tangent")
	check(QUALITY.shader_code("high", 32).contains("uniform vec4 sight_window") and QUALITY.shader_code("low", 32).contains("discard"), "Viewmodel variant cuts the sight window")
	check(not QUALITY.shader_code("high", 0).contains("sight_window =") and not QUALITY.shader_code("high", 0).contains("discard"), "World surfaces carry no window cut")

	var fitted := Visuals.create_weapon("m4", Color("2b2f36"), ["reddot"])
	var parts: Dictionary = fitted.get_meta("visual_parts")
	check(not parts["assault__assault__optic"].visible and not parts["assault__assault__lens"].visible, "A fitted optic replaces the built-in sight")
	fitted.free()
	var plain := Visuals.create_weapon("m4", Color("2b2f36"), [])
	check(plain.get_meta("visual_parts")["assault__assault__optic"].visible, "Without a fitted optic the built-in sight stays")
	plain.free()

	var defaults: Dictionary = Data.table("default_save")
	var settings: Dictionary = defaults.settings.duplicate(true)
	settings.fov = 80
	for key: String in ["reddot", "holo", "acog", "kar98", "mk14", "m4", "m9", "spas12"]:
		var entry: Array = expected[key]
		var loadout: Dictionary = defaults.classes[0].duplicate(true)
		loadout.primary = {"weaponId": entry[0], "attachments": entry[1]}
		var game = Session.new()
		root.add_child(game)
		game.start({"mapId": "freight_yard", "mode": "tdm", "botCount": 0, "difficulty": "regular"}, loadout, settings)
		game.state = "live"
		var player = game.player
		var kind: String = entry[2]
		_aim(player, 0.0)
		check(player.camera.fov == 80.0 and player.zoom == 1.0, "%s: hip view keeps the settings FOV" % key)
		check(player.sight_window.w > 1.0, "%s: no window at the hip" % key)
		check(player.camera.get_meta("base_fov") == 80.0, "%s: replays can read the settings FOV" % key)
		_aim(player, 1.0)
		check(is_equal_approx(player.zoom, float(entry[3])) and is_equal_approx(player.camera.fov, Sights.zoomed_fov(80.0, float(entry[3]))), "%s: full aim magnifies %sx" % [key, entry[3]])
		check(is_equal_approx(player.look_scale(), 1.0 / float(entry[3])), "%s: look sensitivity follows magnification" % key)
		check(player.viewmodel.position.is_equal_approx(player.ads_position), "%s: full aim reaches the solved sight position" % key)
		var sight: Dictionary = game.hud_state().sight
		if kind in ["reflex", "scope"]:
			var lens: Vector3 = Actor._relative_transform(player._sight_lens, player.camera) * player._sight_lens_center
			check(Vector2(lens.x, lens.y).length() < 0.0005 and is_equal_approx(-lens.z, float(Actor.EYE_RELIEF[kind])), "%s: the lens sits on the line of fire at its eye relief" % key)
			if kind == "scope":
				# Just before the eyepiece picture takes over, the weapon is still drawn.
				_aim(player, 0.95)
				sight = game.hud_state().sight
			check(player.sight_window.w < 1.0 and player.sight_window.z < -0.99, "%s: the window opens straight down the line of fire" % key)
			check(not player._sight_materials.is_empty() and player._sight_materials.all(func(material): return material.get_shader_parameter("sight_window") == player.sight_window), "%s: every viewmodel surface cuts the same window" % key)
			if kind == "reflex":
				check(sight.has("window") and absf(sight.window.x - 0.5) < 0.01 and absf(sight.window.y - 0.5) < 0.01 and sight.window.z > 0.05, "%s: the HUD gets the window centred on the aim point" % key)
			else:
				check(sight.has("window") and sight.window.z >= Actor.SCOPE_APERTURE * 0.97, "%s: the window spans the eyepiece aperture" % key)
			var hidden_reticles := 0
			var stack: Array = [player.viewmodel]
			while not stack.is_empty():
				var node: Node = stack.pop_back()
				stack.append_array(node.get_children())
				if node is MeshInstance3D and String(node.name).ends_with("reticle") and not node.visible:
					hidden_reticles += 1
			check(hidden_reticles > 0, "%s: the model's front-facing reticle ring gives way to the projected one" % key)
		if kind == "scope":
			var aperture := Actor.SCOPE_APERTURE * 2.0 * tan(deg_to_rad(player.camera.fov) * 0.5)
			check(player.viewmodel.visible and player.scope_amount > 0.98 and player.sight_window.w <= cos(atan(aperture * 0.98)), "%s: the window already covers the eyepiece picture before the weapon hides" % key)
			_aim(player, 1.0)
			sight = game.hud_state().sight
			check(player.scope_amount == 1.0 and sight.scope == 1.0 and not player.viewmodel.visible, "%s: the eyepiece picture replaces the weapon" % key)
			check(player.sight_window.w > 1.0, "%s: a hidden weapon needs no window" % key)
			var replay = Replay.new()
			root.add_child(replay)
			replay.setup({"frames": []}, "best_play", player.camera)
			check(replay.camera.fov == 80.0, "%s: a replay started while scoped uses the settings FOV" % key)
			replay.free()
			player.camera.make_current()
			player.weapon.magazine = 0
			player.weapon.state = "ready"
			check(player.weapon.reload(), "%s: reload starts" % key)
			Input.action_press("ads")
			player._player_tick(0.05)
			Input.action_release("ads")
			check(player.ads_factor < 1.0, "%s: the scope comes off the eye to reload" % key)
		else:
			check(player.viewmodel.visible and player.scope_amount == 0.0, "%s: the weapon stays in view" % key)
		_aim(player, 1.0)
		player.apply_damage(1000.0, null, "test")
		check(not player.alive and player.camera.fov == 80.0 and player.zoom == 1.0, "%s: death restores the settings FOV" % key)
		check(player.sight_window.w > 1.0 and player.viewmodel.visible, "%s: death closes the window and shows the weapon" % key)
		game.free()
		await process_frame
	for failure in failures:
		print("  ", failure)
	print("SCOPE SIGHTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
