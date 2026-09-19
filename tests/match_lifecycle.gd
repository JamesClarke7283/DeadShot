extends SceneTree
const Session=preload("res://scripts/game/match_session.gd")
const Data=preload("res://scripts/core/game_data.gd")
var failures:Array[String]=[]
var checks:=0

func _initialize()->void:call_deferred("run")

func check(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures.append(message)
		push_error(message)

func run()->void:
	var input_setup=load("res://scripts/core/main.gd").new()
	input_setup._setup_input()
	input_setup.free()
	var defaults:Dictionary=Data.table("default_save")
	var game=Session.new()
	root.add_child(game)
	check(game.start({"mapId":"desert_town","mode":"ffa","botCount":1},defaults.classes[0],defaults.settings),"Match starts")
	await physics_frame
	await physics_frame
	game.state="live"
	var player=game.player
	var bot=game.actors[1]
	game.scores[player.actor_id].score=175
	game.streak_scores[player.actor_id]=500
	player.apply_damage(1000,player,"frag",false)
	check(game.scores[player.actor_id].score==75 and game.scores[player.actor_id].kills==0,"Suicide costs100 scoreboard points without kill credit")
	check(game.streak_scores[player.actor_id]==0,"Suicide resets scorestreak progress")
	player.spawn_at(Vector3.ZERO)
	player.apply_damage(1000,player,"frag",false)
	check(game.scores[player.actor_id].score==0,"Suicide score clamps atzero")
	player.spawn_at(Vector3.ZERO)
	game.scores[player.actor_id].score=125
	player.apply_damage(1000,null,"claymore",false)
	check(game.scores[player.actor_id].score==125,"World death carries no suicide penalty")
	game.scores[player.actor_id].score=200
	game.scores[bot.actor_id].score=200
	game.scores[player.actor_id].kills=1
	game.scores[bot.actor_id].kills=2
	check(game.score_rows()[0].id==player.actor_id,"Equal-score scoreboard retains insertion order regardlesskills")
	# Drops rotate and expire while the player is dead, using the simulation dt.
	var drop:Dictionary=game.dropped_weapons[0]
	var old_angle:float=drop.node.rotation.y
	game._update_pickups(0.2)
	check(is_equal_approx(drop.node.rotation.y-old_angle,0.3),"Dead-player drops rotate with supplieddt")
	drop.expire=game.elapsed
	game._update_pickups(0.01)
	check(not game.dropped_weapons.has(drop),"Drop expires on exact deadline whileplayerdead")
	player.spawn_at(Vector3(0,0,0))
	for item in game.dropped_weapons:item.node.free()
	game.dropped_weapons.clear()
	var first=load("res://scripts/game/weapon_runtime.gd").new("mp5",["reddot"])
	first.magazine=7
	first.reserve=13
	game._add_weapon_drop(first,player.position)
	game._add_weapon_drop(load("res://scripts/game/weapon_runtime.gd").new("deagle"),player.position)
	game._update_pickups(0)
	check(game.prompt.contains("MP5") and game.prompt.contains("7/13"),"Equal-distance pickup selects oldest drop with exactammo")
	var held=player.weapon
	await process_frame
	Input.action_press("interact")
	game._update_pickups(0)
	Input.action_release("interact")
	check(player.weapon.definition.id=="mp5" and player.weapon.magazine==7 and player.weapon.reserve==13,"Pickup preserves incoming ammo")
	check(player.weapon.attachments==["reddot"] and game.dropped_weapons[-1].attachments==held.attachments,"Pickup preserves both incoming and dropped attachments")
	player.weapon.magazine=0
	player.weapon.reserve=0
	game._spawn_ammo_pickup(player.position)
	game._update_ammo_pickups(0)
	check(player.weapon.magazine==player.weapon.stats.magazine and player.weapon.reserve==player.weapon.stats.reserve,"Scavenger tops current magazine and reserve")
	check(game.ammo_pickups.is_empty(),"Collected scavenger pickup disappears")
	player.ads_factor=0.8
	player.weapon.ads_factor=0.4
	player.firing=false
	check(is_equal_approx(game.hud_state().spread,10.8),"HUD spread uses preceding weapon ADS value")
	game.elapsed=600
	game.scores[player.actor_id].kills=2
	game.scores[bot.actor_id].kills=2
	game.scores[bot.actor_id].score=225
	game._check_win()
	check(game.winner==bot.actor_id,"FFA tiedkills chooses higherscore")
	game.state="live"
	game.scores[player.actor_id].score=225
	game._check_win()
	check(game.winner==player.actor_id,"FFA tiedkills andscore chooseslowestID")
	game.free()
	await process_frame
	print("MATCH LIFECYCLE: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
