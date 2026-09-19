extends SceneTree
const Streaks = preload("res://scripts/game/streak_system.gd")

class MockActor extends Node3D:
	var actor_id := 0
	var team := "blue"
	var alive := true
	var health := 100.0
	var max_health := 100.0
	var human := Node3D.new()
	var brain = RefCounted.new()
	var taken := 0.0
	func _init():
		add_child(human)
	func body_position() -> Vector3:
		return position + Vector3.UP
	func apply_damage(amount: float, _owner, weapon_id: String, _headshot := false):
		assert(weapon_id == "streak")
		if alive:
			taken += amount
			health = maxf(0.0, health - amount)
			alive = health > 0.0

class MockMap extends RefCounted:
	var bounds := {"minX":-25.0,"maxX":25.0,"minZ":-25.0,"maxZ":25.0}
	func height_at(_x, _z) -> float:
		return 0.0

class MockVFX extends RefCounted:
	var flashes:=0
	func muzzle_flash(_at:Vector3,direction:Vector3)->void:
		assert(is_equal_approx(direction.length(),1.0))
		flashes+=1

class MockMatch extends Node3D:
	var map = MockMap.new()
	var vfx = MockVFX.new()
	var actors: Array = []
	var player
	var loadout := {"streaks":["uav","care_package","attack_heli"]}
	var streak_scores: Dictionary = {}
	var mode := {"id":"tdm"}
	var prompt := ""
	var explosions := 0
	var tracers := 0
	var winner: Variant = null
	var finalize_play:=true
	func tracer(_from, _to):
		tracers += 1
	func _flash(_at,_size,_color,_duration):
		pass
	func explode(at:Vector3,radius:float,damage:float,owner,_weapon:String):
		explosions += 1
		for actor in actors:
			if actor.alive and (owner.team == "ffa" or actor.team != owner.team):
				var distance:float = actor.body_position().distance_to(at)
				if distance <= radius:
					actor.apply_damage(damage * maxf(0.0,1.0-distance/radius),owner,"streak")
	func end_match(value,finalize_value:bool=true):
		winner = value
		finalize_play=finalize_value

var games: Array = []

func make_case() -> Array:
	var game := MockMatch.new()
	root.add_child(game)
	for index in 3:
		var actor := MockActor.new()
		actor.actor_id = index
		actor.team = "red" if index == 1 else "blue"
		actor.position.x = float(index) * 6.0
		game.add_child(actor)
		game.actors.append(actor)
	game.player = game.actors[0]
	var streaks := Streaks.new()
	game.add_child(streaks)
	streaks.setup(game)
	games.append(game)
	return [game,streaks,game.player,game.actors[1],game.actors[2]]

func _initialize():
	call_deferred("run")

func run():
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
	var case := make_case()
	var game = case[0]
	var manager = case[1]
	var owner = case[2]
	manager.add_score(0, 499)
	assert(not manager.is_available(0,"uav"))
	manager.add_score(0,1)
	assert(manager.is_available(0,"uav"))
	assert(manager.activate(owner,"uav"))
	assert(not manager.is_available(0,"uav"))
	manager.tick(0.1)
	assert(manager.active_pings("blue").size() == 1)
	owner.alive = false
	manager.reset(owner.actor_id)
	assert(manager.score_of(0) == 0, "Death clears earned score")
	assert(manager.active.size() == 1, "Death preserves the called-in UAV")
	manager.add_score(0,500)
	assert(not manager.activate(owner,"uav"), "Existing live streak still prevents duplicate activation")
	manager.reset(owner.actor_id)
	manager.tick(25.0)
	assert(not manager.is_available(0,"uav"), "Previous-life availability cannot return when the UAV ends")
	owner.alive=true
	manager.add_score(0,500)
	assert(manager.is_available(0,"uav"), "The new life can earn streaks again")
	manager.add_score(0,800)
	assert(manager.best_available(0).id == "attack_heli")
	assert(manager.next_streak(owner).is_empty())
	manager.set_loadout(0,["nuke","uav","sentry","gunship"])
	assert(manager.loadout_for(0).size() == 3)
	assert(manager.next_streak(owner).id == "nuke")
	manager.reset(0)
	assert(manager.score_of(0) == 0)
	manager.on_kill(owner,case[3],true)
	assert(manager.score_of(0) == 125)

	case = make_case()
	manager = case[1]
	var remote = case[3]
	remote.brain = null
	manager.add_score(remote.actor_id,1300)
	manager.tick(0.01)
	assert(manager.active.is_empty(), "Remote peers must not autonomously activate bot streaks")

	for id in ["counter_uav","sentry","rcxd","predator","attack_heli","gunship","chopper_gunner","strafe_run","care_package","juggernaut","nuke"]:
		case = make_case()
		game = case[0]
		manager = case[1]
		owner = case[2]
		var enemy = case[3]
		var ally = case[4]
		if id == "chopper_gunner":
			for i in 2:
				var extra := MockActor.new()
				extra.actor_id = i + 3
				extra.team = "red"
				extra.position = Vector3(12 + i * 4, 0, 3)
				game.add_child(extra)
				game.actors.append(extra)
		assert(manager._activate(owner,id))
		manager.tick(0.01)
		match id:
			"counter_uav":
				assert(manager.is_jammed("red") and not manager.is_jammed("blue"))
				manager.tick(31.0)
				assert(not manager.is_jammed("red"))
			"sentry":
				assert(enemy.taken == 18.0 and ally.taken == 0.0)
				assert(game.vfx.flashes == 1, "Sentry uses original directed muzzle flash")
				manager.tick(0.2)
				assert(enemy.taken == 36.0)
			"rcxd":
				for i in 12:
					manager.tick(0.1)
				assert(game.explosions == 1 and enemy.taken > 0.0 and ally.taken == 0.0)
			"predator":
				assert(manager.active[0].node.position.x == enemy.position.x)
				manager.tick(2.0)
				assert(game.explosions == 1 and enemy.taken > 100.0)
			"attack_heli", "gunship", "chopper_gunner":
				assert(enemy.taken == Streaks.AIRCRAFT[id].damage)
				assert(game.tracers == (3 if id == "chopper_gunner" else 1) and ally.taken == 0.0)
				if id == "chopper_gunner":
					assert(game.actors[3].taken == 50.0 and game.actors[4].taken == 50.0)
				if id == "attack_heli":
					assert(not manager._activate(ally,id), "Only one attack heli may exist globally")
			"strafe_run":
				for i in 30:
					manager.tick(0.05)
				assert(enemy.taken == 80.0, "Strafe damages each target once")
			"care_package":
				for i in 100:
					manager.tick(0.05)
				assert(manager.pickups.size() == 1, "Helicopter must drop a persistent landed pickup")
				enemy.position = manager.pickups[0].node.position
				enemy.brain = null
				manager.tick(0.01)
				assert(manager.pickups.size() == 1, "Remote peers must not auto-collect care crates")
				enemy.brain = RefCounted.new()
				manager.tick(0.01)
				assert(manager.pickups.is_empty())
				for entry in manager.active:
					assert(entry.id not in ["care_package","nuke"])
			"juggernaut":
				assert(owner.health == 300.0 and owner.max_health == 300.0)
				assert(owner.human.scale.is_equal_approx(Vector3.ONE * 1.2))
				manager.tick(30.0)
				assert(owner.health == 100.0 and owner.max_health == 100.0)
				assert(owner.human.scale == Vector3.ONE)
			"nuke":
				assert(game.winner == null)
				manager.tick(6.0)
				assert(game.winner == "blue")
				assert(not game.finalize_play,"Nuke keeps the existing best play without finalizing the live streak")
		manager.clear()
		assert(manager.active.is_empty() and manager.pickups.is_empty())
	for entry in games:
		entry.queue_free()
	await process_frame
	print("SCORESTREAK_VERIFICATION: death resets, retained active streaks and all 12 streak behaviors passed.")
	quit()
