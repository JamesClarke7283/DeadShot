extends SceneTree
const Session=preload("res://scripts/game/match_session.gd")
const Remote=preload("res://scripts/game/remote_combatant.gd")
const Data=preload("res://scripts/core/game_data.gd")
const Visuals=preload("res://scripts/visuals/visual_factory.gd")

class PassiveBrain extends RefCounted:
	func tick(_actor,_dt,_match):pass

class NetworkOwnership extends RefCounted:
	var remotes:Dictionary={}
	var sent_deaths:=0
	func owns(actor)->bool:return not remotes.has(actor.actor_id)
	func local_death(_victim,_killer,_weapon,_headshot):sent_deaths+=1
	func tick(_dt):pass

class RemoteWire extends RefCounted:
	var hits:=0
	func send_hit(_id,_amount,_headshot,_weapon):hits+=1

class ShotWorld extends RefCounted:
	var shots:=0
	func fire_hitscan(_actor,_gun,_origin,_direction):shots+=1

func _initialize():call_deferred("run")

func assert_fresh(actor)->void:
	for weapon in actor.weapons:
		assert(weapon.magazine==int(weapon.stats.magazine) and weapon.reserve==int(weapon.stats.reserve),"Every carried weapon refills from attachment-adjusted capacity")
		assert(weapon.state=="ready" and weapon.reload_timer==0.0 and weapon.swap_timer==0.0)
		assert(weapon.burst_remaining==0 and weapon.recoil_pitch==0.0 and weapon.shot_index==0)
		assert(not weapon.trigger and not weapon.last_trigger and weapon.cooldown==0.0)
	assert(not actor.view_reloading and actor.melee_time==0.0 and actor.ads_factor==0.0 and actor.kick==0.0)

func run()->void:
	var input_setup=load("res://scripts/core/main.gd").new()
	input_setup._setup_input()
	input_setup.free()
	var defaults:Dictionary=Data.table("default_save")
	var selected:Dictionary=defaults.classes[0].duplicate(true)
	selected.primary={"weaponId":"m16a4","attachments":["extmag"]}
	var game=Session.new()
	root.add_child(game)
	assert(game.start({"mapId":"desert_town","mode":"ffa","botCount":1},selected,defaults.settings))
	game.state="live"
	var player=game.player
	var bot=game.actors[1]
	bot.brain=PassiveBrain.new()
	var network:=NetworkOwnership.new()
	game.network=network
	player.select_weapon(1)
	for weapon in player.weapons:
		weapon.magazine=2
		weapon.reserve=3
		weapon.state="reloading"
		weapon.reload_timer=1.5
		weapon.reload_duration=2.0
		weapon.swap_timer=0.3
		weapon.burst_remaining=2
		weapon.recoil_pitch=0.2
		weapon.shot_index=4
		weapon.trigger=true
		weapon.last_trigger=true
		weapon.cooldown=0.5
	player.view_reloading=true
	player.view_reload_time=0.4
	player.view_reload_duration=2.0
	player.ads_factor=0.8
	player.kick=0.7
	player.melee_slash()
	game.scores[player.actor_id].kills=9
	game.scores[player.actor_id].score=1234
	game.streaks.add_score(player.actor_id,750)
	assert(game.streaks.activate(player,"uav"))
	game.streaks.tick(0.01)
	player.apply_damage(1000,bot,"m4")
	assert(not player.alive and network.sent_deaths==1)
	assert_fresh(player)
	assert(player.current_slot==1 and player.weapons[0].definition.id=="m16a4" and player.weapons[0].attachments==["extmag"])
	assert(game.dropped_weapons[-1].magazine==2 and game.dropped_weapons[-1].reserve==3,"The dropped weapon retains spent ammo from the previous life")
	assert(game.streaks.score_of(player.actor_id)==0 and not game.streaks.is_available(player.actor_id,"care_package"))
	assert(game.streaks.active.size()==1 and game.streaks.hud(player)[0].active,"Called-in UAV survives the owner's death")
	assert(game.scores[player.actor_id].kills==9 and game.scores[player.actor_id].score==1234 and game.scores[player.actor_id].deaths==1,"Reset does not erase scoreboard progress")
	game.tick(game.respawn_delay+0.01)
	assert(player.alive)
	assert_fresh(player)
	assert(not Visuals.part(player.viewmodel,"knife").visible and Visuals.part(player.viewmodel,"gun").visible)
	assert(game.streaks.score_of(player.actor_id)==0 and game.streaks.active.size()==1)
	var world:=ShotWorld.new()
	player.weapon.trigger=true
	player.weapon.tick(0.0,player,world)
	assert(world.shots==1,"A fresh semi-auto weapon fires immediately, without stale trigger or swap state")
	player.weapon.trigger=false

	bot.weapon.magazine=1
	bot.weapon.reserve=2
	bot.weapon.state="reloading"
	bot.weapon.reload_timer=3.0
	game.streaks.add_score(bot.actor_id,1300)
	var bot_points:int=game.scores[bot.actor_id].score
	bot.apply_damage(1000,player,"m9")
	assert_fresh(bot)
	assert(game.streaks.score_of(bot.actor_id)==0 and game.scores[bot.actor_id].score==bot_points)
	game.tick(game.respawn_delay+0.01)
	assert(bot.alive)
	assert_fresh(bot)
	assert(game.streaks.score_of(bot.actor_id)==0)
	assert(game.streaks.score_of(player.actor_id)==100,"Kills in a new life earn fresh streak progress")

	# A remote proxy never owns its ammo, damage or respawn. Its local meter can
	# reflect a reported death without simulating a new life on this peer.
	var remote=Remote.new()
	game.add_child(remote)
	var wire:=RemoteWire.new()
	remote.setup_remote(10,"ffa","Remote",0,game,wire)
	game.actors.append(remote)
	network.remotes[10]=remote
	game.scores[10]={"id":10,"name":"Remote","team":"ffa","kills":0,"deaths":0,"assists":0,"score":0,"isPlayer":false}
	game.tiers[10]=0
	game.streak_scores[10]=700
	remote.weapon.magazine=3
	remote.weapon.reserve=4
	remote.apply_damage(1000,player,"m4")
	assert(wire.hits==1 and remote.alive and remote.weapon.magazine==3)
	game.actor_killed(remote,player,"m4",false,true)
	remote.mark_dead()
	remote.death_timer=100.0
	var deaths_sent:=network.sent_deaths
	game.tick(game.respawn_delay+0.01)
	assert(not remote.alive and remote.weapon.magazine==3 and remote.weapon.reserve==4,"Peer does not refill or respawn a remote proxy")
	assert(game.streaks.score_of(10)==0 and network.sent_deaths==deaths_sent,"Remote death clears local streak availability without rebroadcast")
	game.free()
	await process_frame
	print("DEATH_RESETS: owned player/bot death-to-respawn refills all carried ammo and clears weapon state; streak progress resets, scoreboard and active UAV persist; remote ownership preserved.")
	quit()
