extends SceneTree
const EFFECTS := preload("res://scripts/ui/screen_effects.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.0001, message)

func run() -> void:
	var effects := EFFECTS.new()
	root.add_child(effects)
	effects.apply_effect("stun", 0.6, 2.8)
	near(effects._strength(effects.tint_state), 0.6, "Point-blank stun keeps the supplied 0.6 opacity")
	near(effects._strength(effects.blur_state), 12, "Point-blank stun has the source 12px Gaussian sigma")
	check(effects.tint_state.color == Color(120.0 / 255, 160.0 / 255, 1, 0.9), "Stun preserves the source translucent blue")
	effects.update_effects(1.4)
	near(effects._strength(effects.tint_state), 0.3, "Tint decays linearly")
	near(effects._strength(effects.blur_state), 6, "Blur decays linearly in pixels")
	effects.apply_effect("damage", 0.5, 0.5)
	check(effects.tint_state.color == Color(180.0 / 255, 0, 0), "Damage replaces the blue tint")
	near(effects._strength(effects.blur_state), 6, "Replacing tint retains the independent stun blur")
	effects.apply_effect("scavenger", 0.25, 0.4)
	check(effects.tint_state.color == Color(1, 204.0 / 255, 51.0 / 255), "Scavenger replaces damage with source gold")
	effects.apply_effect("flash", 1.7, 2)
	near(effects._strength(effects.flash_state), 1, "Flash opacity clamps to one")
	effects.apply_effect("flash", 0.2, 1)
	near(effects._strength(effects.flash_state), 0.2, "Later flashes replace stronger old flashes")
	effects.apply_effect("blur", 0, 2)
	near(effects._strength(effects.blur_state), 6, "Zero blur does not replace an active source blur")
	effects.apply_effect("deafen", 1, 2)
	effects.apply_effect("deafen", 1, 1)
	near(effects.deafen_timer, 2, "Deafen retains the longest duration")
	effects.update_effects(0.5)
	check(effects.tint_state.is_empty(), "Expired tint cannot reveal an earlier replaced tint")
	near(effects._strength(effects.flash_state), 0.1, "Flash remains independent of expired tint")
	check(effects.is_deafened(), "Deafen is exposed as state")
	effects.clear()
	check(not effects.visible and not effects.is_deafened(), "Clear removes all visuals and deafen state")
	check(effects.flash_state.is_empty() and effects.blur_state.is_empty() and effects.tint_state.is_empty(), "Clear removes all independent timers")
	effects.queue_free()
	await process_frame
	print("Screen effect source parity: %s" % ("PASS" if failures.is_empty() else "%d failures" % failures.size()))
	quit(0 if failures.is_empty() else 1)
