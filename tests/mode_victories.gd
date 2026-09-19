extends SceneTree
const Session=preload("res://scripts/game/match_session.gd")
const Data=preload("res://scripts/core/game_data.gd")
var failures:Array[String]=[]

func _initialize()->void:call_deferred("run")

func check(value:bool,message:String)->void:
	if not value:
		failures.append(message)
		push_error(message)

func build(mode_id:String):
	var defaults:Dictionary=Data.table("default_save")
	var game=Session.new()
	root.add_child(game)
	game.start({"mapId":"desert_town","mode":mode_id,"botCount":1},defaults.classes[0],defaults.settings)
	game.state="live"
	return game

func run()->void:
	for mode_id in ["tdm","ffa"]:
		var game=build(mode_id)
		var player=game.player
		game.scores[player.actor_id].kills=99
		game.actors[1].apply_damage(1000,player,"m4",false)
		game._check_win()
		check(game.state=="end" and game.winner==("blue" if mode_id=="tdm" else player.actor_id),"%s ends on actual 100th kill"%mode_id)
		game.free()
		await process_frame
	var tie=build("tdm")
	tie.elapsed=600
	tie._check_win()
	check(tie.state=="end" and tie.winner==null,"TDM time limit preserves draw")
	tie.free()
	await process_frame
	var game=build("gungame")
	var player=game.player
	var bot=game.actors[1]
	check(player.weapons.size()==1 and player.weapon.definition.id=="m9" and player.weapon.attachments.is_empty(),"Gun Game starts with one clean pistol")
	check(game.loadout.lethal=="knife","Throwing knife available at every Gun Game tier")
	bot.apply_damage(1000,player,"frag",false)
	check(game.tiers[player.actor_id]==0,"Off-tier explosive kill does not advance")
	bot.spawn_at(Vector3.ZERO)
	bot.apply_damage(1000,player,"m9",false)
	check(game.tiers[player.actor_id]==1 and player.weapon.definition.id=="mp5","Tier kill swaps to next clean weapon")
	player.apply_damage(1000,bot,"melee",false)
	check(game.tiers[player.actor_id]==0 and player.weapon.definition.id=="m9","Melee death drops a tier")
	player.spawn_at(Vector3.ZERO)
	game.tiers[bot.actor_id]=6
	bot.set_weapon("barrett")
	player.apply_damage(1000,bot,"barrett",false)
	check(game.tiers[bot.actor_id]==6 and bot.weapon.definition.id=="barrett","Bot progression caps at Barrett")
	player.spawn_at(Vector3.ZERO)
	var tiers:Array=Data.table("gun_game_tiers")
	for tier in 7:
		bot.spawn_at(Vector3.ZERO)
		bot.apply_damage(1000,player,str(tiers[tier]),false)
		check(game.tiers[player.actor_id]==tier+1 and player.weapon.definition.id==tiers[tier+1],"Player advances from tier%d"%tier)
	check(game.state=="live" and game.dropped_weapons.is_empty(),"Final knife tier still requires a kill and drops no weapons")
	check(game.streak_scores[player.actor_id]==0,"Gun Game kills never fill the scorestreak meter")
	bot.spawn_at(Vector3.ZERO)
	bot.apply_damage(1000,player,"knife",false)
	check(game.state=="end" and game.winner==player.actor_id,"Knife kill wins Gun Game")
	game.free()
	await process_frame
	print("MODE VICTORIES: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
