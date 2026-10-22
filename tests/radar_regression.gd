extends SceneTree
const Session = preload("res://scripts/game/match_session.gd")
const Data = preload("res://scripts/core/game_data.gd")
const Remote = preload("res://scripts/game/remote_combatant.gd")
const Hud = preload("res://scripts/ui/hud_painter.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func enemy_blips(session) -> Array:
	return session.hud_state().minimap.blips.filter(func(blip): return blip.enemy)

func run() -> void:
	var session = Session.new()
	root.add_child(session)
	var save: Dictionary = Data.table("default_save")
	check(session.start({"mapId": "freight_yard", "mode": "tdm", "botCount": 2}, save.classes[0], save.settings), "Radar fixture starts")
	var player = session.player
	var enemy = session.actors[1]
	var ally = session.actors[2]
	for actor in session.actors:
		actor.brain = null
	player.position = Vector3(-40, 0, 0)
	player.rotation.y = -PI / 2
	enemy.position = Vector3(-24, 0, -12)
	ally.position = Vector3(-44, 0, 32)
	ally.aim_dir = Vector3.BACK
	await physics_frame
	await physics_frame
	session.radar.tick(0.2, session)
	check(enemy_blips(session).is_empty(), "Walls hide silent enemies")
	check(session.hud_state().minimap.blips.size() == 1, "Living teammate is always marked")
	enemy.on_shot()
	var blips := enemy_blips(session)
	check(blips.size() == 1 and blips[0].source == "shot", "Enemy gunfire reveals a dot through cover")
	var shot_x: float = blips[0].x
	enemy.position.x += 4
	check(enemy_blips(session)[0].x == shot_x, "Gunfire reveals the firing location without tracking hidden movement")
	session.ui_time += 2.6
	check(enemy_blips(session).is_empty(), "Shot contact expires after 2.5 seconds")
	enemy.position = Vector3(-20, 0, 0)
	await physics_frame
	session.radar.tick(0.2, session)
	check(enemy_blips(session).size() == 1, "Enemy in view is spotted")
	session.radar.contacts.clear()
	player.rotation.y = PI / 2
	session.radar.tick(0.2, session)
	check(enemy_blips(session).is_empty(), "Enemies behind the player are not automatically spotted")
	ally.position = Vector3(-30, 0, 0)
	ally.aim_dir = Vector3.RIGHT
	session.radar.tick(0.2, session)
	check(enemy_blips(session).size() == 1, "Teammates share visual contacts")
	# Smoke interrupts otherwise clear visual spotting.
	session.radar.contacts.clear()
	session.equipment.items.append({"id": "smoke", "active": true, "detonated": true, "effect_point": Vector3(-25, 0, 0)})
	session.radar.tick(0.2, session)
	check(enemy_blips(session).is_empty(), "Smoke blocks visual spotting")
	session.equipment.items.clear()
	enemy.on_shot()
	session.streaks.counter_uav[player.team] = 100.0
	check(session.hud_state().minimap.jammed, "Counter UAV still jams the radar")
	check(session.hud_state().minimap.blips.is_empty(), "Jamming suppresses all map intelligence")
	session.streaks.counter_uav.clear()
	enemy.alive = false
	check(enemy_blips(session).is_empty(), "Dead enemies lose their contact")
	enemy.alive = true
	check(enemy_blips(session).is_empty(), "Respawn does not resurrect an old contact")
	# FFA never shares a same-team ally's vision, and every other player is hostile.
	player.team = "ffa"
	enemy.team = "ffa"
	ally.team = "ffa"
	session.radar.contacts.clear()
	session.radar.tick(0.2, session)
	check(enemy_blips(session).is_empty(), "FFA does not share spotting")
	enemy.on_shot()
	check(enemy_blips(session).size() == 1, "FFA opponent gunfire reveals normally")
	# A completed click can fall entirely between network snapshots.
	var remote = Remote.new()
	session.add_child(remote)
	remote.setup_remote(91, "red", "Remote", 0, session, null)
	session.actors.append(remote)
	remote.apply_state({"x": 30, "y": 0, "z": 10, "alive": true, "anim": "idle", "shotSerial": 1, "shotAge": 0.02})
	check(session.radar.contacts.has(91), "Network shot sequence reveals even after the fire animation ends")
	var expiry: float = session.radar.contacts[91].expire
	session.ui_time += 0.1
	remote.apply_state({"x": 35, "z": 10, "alive": true, "shotSerial": 1, "shotAge": 0.12})
	check(session.radar.contacts[91].expire == expiry and session.radar.contacts[91].position.x == 30, "Repeated snapshots do not extend or move a shot")
	remote.apply_state({"x": 40, "z": 10, "alive": true, "shotSerial": 2, "shotAge": 0.5, "shotX": 36, "shotY": 0, "shotZ": 9})
	check(session.radar.contacts[91].position == Vector3(36, 0, 9), "Remote marker uses the firing location before later movement")
	check(is_equal_approx(session.radar.contacts[91].expire, session.ui_time + 2.0), "Delayed snapshots preserve the remaining reveal time")
	remote.apply_state({"alive": false, "shotSerial": 1})
	check(not session.radar.contacts.has(91), "Remote death clears a contact")
	var rect := Rect2(10, 20, 180, 180)
	var bounds := {"minX": -50, "maxX": 50, "minZ": -50, "maxZ": 50}
	check(Hud.radar_point(Vector2.ZERO, bounds, rect) == rect.get_center(), "Radar centers the world")
	check(Hud.radar_point(Vector2(0, -50), bounds, rect).y == rect.position.y, "Radar north stays at the top")
	session.free()
	await process_frame
	print("RADAR REGRESSION: %s" % ("PASS" if failures.is_empty() else str(failures.size()) + " failures"))
	quit(0 if failures.is_empty() else 1)
