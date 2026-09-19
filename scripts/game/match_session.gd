class_name MatchSession
extends Node3D
signal finished(result: Dictionary)
signal kill_event(event: Dictionary)
signal player_hit(headshot: bool, killed: bool)
signal player_damaged(angle: float, amount: float)
signal weapon_sound(id: String, at: Vector3, local: bool)
signal reload_sound
signal screen_effect(kind: String, intensity: float, duration: float)
signal killcam_ready(data: Dictionary)
signal explosion_sound(at: Vector3, radius: float)
const Actor = preload("res://scripts/game/combatant.gd")
const Data = preload("res://scripts/core/game_data.gd")
const Navigator = preload("res://scripts/game/navigator.gd")
const Visuals = preload("res://scripts/visuals/visual_factory.gd")
const BOT_WEAPONS = ["m4","mp5","rpk","kar98","scarl","vector","mk14","spas12","ak12","p90","m249","barrett","m16a4","uzi","ksg","deagle"]
var config: Dictionary = {}
var loadout: Dictionary = {}
var mode: Dictionary = {}
var map
var actors: Array = []
var player
var navigator = Navigator.new()
var elapsed: float = 0.0
var warmup: float = 2.0
var respawn_delay: float = 4.0
var state: String = "warmup"
var winner: Variant = null
var scores: Dictionary = {}
var recent_spawns: Dictionary = {}
var effects: Array = []
var rockets: Array = []
var equipment
var objective
var streaks
var tiers: Dictionary = {}
var streak_scores: Dictionary = {}
var melee_cooldown: float = 0.0
var dropped_weapons: Array = []
var prompt: String = ""
var ui_time: float = 0.0
var snapshot_pings: Array = []
var recorder=preload("res://scripts/game/replay_recorder.gd").new(10.0,30.0)
var best_play:Dictionary={}
var player_killstreak:int=0
var streak_start_time:float=0.0
var pending_deaths:Array=[]
var ammo_pickups:Array=[]
var network_client
var network
var vfx
var throw_charges:Dictionary={}
var equipment_input_enabled:bool=true
var _throw_blocked:Dictionary={}

func start(options: Dictionary, selected_class: Dictionary, settings: Dictionary) -> bool:
	config = options.duplicate(true)
	loadout = selected_class.duplicate(true)
	mode = Data.entry("modes", str(config.get("mode","tdm")))
	if mode.is_empty():
		mode = Data.entry("modes","tdm")
	var Map = load("res://scripts/world/map_world.gd")
	map = Map.new()
	add_child(map)
	if not map.load_map(str(config.get("mapId","desert_town"))):
		return false
	Visuals.environment = map.environment_data
	vfx = preload("res://scripts/visuals/combat_vfx.gd").new()
	vfx.environment = map.environment_data
	add_child(vfx)
	navigator.configure(map.nav_points)
	if is_instance_valid(network_client):
		network = preload("res://scripts/game/match_network.gd").new()
		add_child(network)
		network.setup(self,network_client)
	var has_player: bool = options.get("hasPlayer",true)
	var count = int(options.get("botCount",8))
	if network and not network.is_host:
		count = 0
	for slot in range(count + (1 if has_player else 0)):
		var actor = Actor.new()
		add_child(actor)
		var is_player = slot == 0 and has_player
		var team = "ffa" if mode.id in ["ffa","gungame"] else ("blue" if slot%2==0 else "red")
		var actor_loadout = loadout.duplicate(true)
		if not is_player:
			actor_loadout.primary = {"weaponId":BOT_WEAPONS[(slot-(1 if has_player else 0))%BOT_WEAPONS.size()],"attachments":[]}
		if mode.id == "gungame":
			actor_loadout.primary = {"weaponId":"m9","attachments":[]}
		var actor_id=slot if has_player else slot+1
		if network:
			var bot_index = slot-(1 if has_player else 0)
			actor_id = network.client.self_id if is_player else 1000000+bot_index
			team = network.team_for_player(actor_id) if is_player else ("ffa" if mode.id=="ffa" else ("blue" if bot_index%2==0 else "red"))
			actor.accent_index = bot_index
		actor.setup(actor_id,team,is_player,actor_loadout,self)
		actor.display_name = str(options.get("playerName","You")) if is_player else "Bot %d" % actor_id
		if config.get("hardcore",false):
			actor.set_hardcore()
		if is_player:
			player = actor
			player.apply_settings(settings)
		actors.append(actor)
		scores[actor_id] = {"id":actor_id,"name":actor.display_name,"team":team,"kills":0,"deaths":0,"assists":0,"score":0,"isPlayer":is_player}
		tiers[actor_id] = 0
		streak_scores[actor_id] = 0
		_spawn(actor)
	if network:
		network.begin()
	if ResourceLoader.exists("res://scripts/game/objectives.gd") and mode.id in ["dom","ctf"]:
		objective = load("res://scripts/game/objectives.gd").new()
		add_child(objective)
		objective.setup(mode.id,self)
	if ResourceLoader.exists("res://scripts/game/equipment_system.gd"):
		equipment = load("res://scripts/game/equipment_system.gd").new()
		add_child(equipment)
		equipment.game_match = self
	streaks = preload("res://scripts/game/streak_system.gd").new()
	add_child(streaks)
	streaks.setup(self)
	if mode.id=="gungame":
		if player:player.set_weapon("m9")
		loadout.lethal="knife"
	return true

func tick(dt: float) -> void:
	if state == "end":
		return
	map.update_wind(elapsed)
	ui_time += dt
	melee_cooldown = maxf(0,melee_cooldown-dt)
	_tick_effects(dt)
	_tick_rockets(dt)
	if equipment:
		equipment.tick(dt)
	if state == "warmup":
		warmup -= dt
		if warmup <= 0:
			state="live"
	for actor in actors:
		actor.tick(dt)
	if network:
		network.tick(dt)
	if player and player.alive:
		if Input.is_action_just_pressed("melee"):
			melee(player)
	_update_equipment_input(dt)
	if state != "live":
		return
	elapsed += dt
	for pending in pending_deaths:actor_killed(pending[0],pending[1],pending[2],pending[3])
	pending_deaths.clear()
	_update_ammo_pickups(dt)
	for actor in actors:
		if (not network or network.owns(actor)) and not actor.alive and actor.death_timer >= respawn_delay:
			_spawn(actor)
	if streaks:streaks.tick_pickups(dt)
	_update_pickups(dt)
	if objective:
		objective.tick(dt)
	if streaks and mode.id != "gungame":
		streaks.tick(dt, false)
	recorder.record(elapsed,snapshot_actors())
	if state != "end":
		_check_win()

func _spawn(actor) -> void:
	var candidates: Array = []
	for point in map.spawn_points:
		if point.get("team", "") == actor.team:
			candidates.append(point)
	if candidates.is_empty():
		candidates = map.spawn_points
	if candidates.is_empty():
		push_error("Map contains no valid spawn points")
		return
	var recent: Array = recent_spawns.get(actor.team,[])
	var scored: Array = []
	var best: float = -INF
	for point in candidates:
		var enemy_distance: float = INF
		var ally_distance: float = INF
		for other in actors:
			if other != actor and other.alive and (actor.team == "ffa" or other.team != actor.team):
				enemy_distance = minf(enemy_distance,point.position.distance_to(other.body_position()))
		for previous in recent:
			ally_distance = minf(ally_distance,point.position.distance_to(previous))
		var score: float = (enemy_distance if is_finite(enemy_distance) else 0.0) + 0.8*(ally_distance if is_finite(ally_distance) else 0.0)
		best = maxf(best,score)
		scored.append({"point":point,"score":score})
	var eligible = scored.filter(func(item):return item.score >= best-14.0)
	var choice: Dictionary = eligible[randi()%eligible.size()].point
	actor.spawn_at(choice.position,float(choice.get("yaw",0)))
	recent.append(choice.position)
	while recent.size() > maxi(1,candidates.size()-1):
		recent.pop_front()
	recent_spawns[actor.team] = recent

func cancel_equipment_charges()->void:
	throw_charges.clear()
	for action in ["lethal","tactical"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			_throw_blocked[action]=true
		else:
			_throw_blocked.erase(action)

func begin_charged_throw(action:String)->void:
	if not player or not player.alive or not equipment or not equipment_input_enabled or _throw_blocked.has(action):return
	var item_id:String=loadout.get(action,"frag" if action=="lethal" else "flashbang")
	if item_id in ["frag","flashbang"] and not throw_charges.has(action):
		throw_charges[action]={"id":item_id,"seconds":0.0,"started_ms":Time.get_ticks_msec()}

func _charge_seconds(charge:Dictionary)->float:
	# Input duration must not stretch when a slow renderer drops physics steps.
	var held_time:=float(Time.get_ticks_msec()-int(charge.started_ms))/1000.0
	return minf(equipment.CHARGE_SECONDS,maxf(float(charge.seconds),held_time))

func release_charged_throw(action:String)->void:
	_throw_blocked.erase(action)
	if not throw_charges.has(action):return
	var charge:Dictionary=throw_charges[action]
	throw_charges.erase(action)
	if player and player.alive and equipment and equipment_input_enabled:
		equipment.throw_item(charge.id,player,_charge_seconds(charge)/equipment.CHARGE_SECONDS)

func _update_equipment_input(dt:float)->void:
	if not player or not player.alive or not equipment or not equipment_input_enabled:
		cancel_equipment_charges()
		return
	for action in ["lethal","tactical"]:
		var held:=Input.is_action_pressed(action)
		if _throw_blocked.has(action):
			if not held:_throw_blocked.erase(action)
			continue
		var item_id:String=loadout.get(action,"frag" if action=="lethal" else "flashbang")
		if Input.is_action_just_pressed(action) and held and not throw_charges.has(action):
			if item_id in ["frag","flashbang"]:
				begin_charged_throw(action)
			else:
				equipment.throw_item(item_id,player)
		if not throw_charges.has(action):continue
		var charge:Dictionary=throw_charges[action]
		if held:
			charge.seconds=minf(equipment.CHARGE_SECONDS,float(charge.seconds)+dt)
		else:
			release_charged_throw(action)

func throw_prompt()->String:
	if throw_charges.is_empty():return ""
	var charge:Dictionary=throw_charges.values()[-1]
	var item_name:String="GRENADE" if charge.id=="frag" else "FLASHBANG"
	return "%s POWER %d%% — release to throw"%[item_name,roundi(_charge_seconds(charge)/equipment.CHARGE_SECONDS*100.0)]

func raycast(origin: Vector3, direction: Vector3, max_distance: float, ignore = null, projectile: bool = false, source_skip: bool = true) -> Dictionary:
	var result: Dictionary = {}
	var best_distance = max_distance
	var geometry_skip = 0.6 if projectile and source_skip else 0.0
	if is_inside_tree() and max_distance > geometry_skip:
		var query = PhysicsRayQueryParameters3D.create(origin+direction*geometry_skip,origin+direction*max_distance,2)
		var geometry = get_world_3d().direct_space_state.intersect_ray(query)
		if not geometry.is_empty():
			best_distance = origin.distance_to(geometry.position)
			result = {"position":geometry.position,"normal":geometry.normal,"distance":best_distance,"target":null,"headshot":false}
	var self_skip = 0.0 if projectile else 0.6
	for actor in actors:
		if not actor.alive or actor == ignore:
			continue
		var body_distance = ray_sphere(origin,direction,actor.body_position(),0.6)
		var head_distance = ray_sphere(origin,direction,actor.eye_position(),0.28)
		var distance = -1.0
		var headshot = false
		if head_distance > self_skip:
			distance=head_distance
			headshot=true
		if body_distance > self_skip and (distance<0 or body_distance<distance):
			distance=body_distance
			headshot=false
		if distance>self_skip and distance<best_distance:
			best_distance=distance
			var point=origin+direction*distance
			var center:Vector3=actor.eye_position() if headshot else actor.body_position()
			result={"position":point,"normal":(point-center).normalized(),"distance":distance,"target":actor,"headshot":headshot}
	return result

static func ray_sphere(origin: Vector3,direction: Vector3,center: Vector3,radius: float) -> float:
	var offset=origin-center
	var b=offset.dot(direction)
	var discriminant=b*b-offset.length_squared()+radius*radius
	if discriminant<0:
		return -1.0
	var t=-b-sqrt(discriminant)
	return t if t>=0 else maxf(-1.0,-b+sqrt(discriminant))

func fire_hitscan(actor, gun, origin: Vector3,direction: Vector3) -> void:
	var hit=raycast(origin,direction,500.0,actor)
	var end:Vector3=hit.get("position",origin+direction*500.0)
	tracer(gun.shot_muzzle,end)
	if hit.is_empty():
		return
	var target=hit.target
	impact(hit.position,target!=null,hit.normal)
	if target and target.alive and (actor.team=="ffa" or target.team!=actor.team):
		var damage=Data.damage_at_range(gun.stats,float(hit.distance))
		if hit.headshot:
			damage*=float(gun.stats.headshotMultiplier)
		target.apply_damage(damage,actor,gun.definition.id,hit.headshot)
		if actor==player:
			player_hit.emit(hit.headshot,not target.alive)

func melee(actor) -> void:
	if melee_cooldown>0:
		return
	melee_cooldown=0.8
	actor.melee_slash()
	var hit=raycast(actor.eye_position(),actor.aim_direction(),2.5,actor)
	if not hit.is_empty() and hit.target and (actor.team=="ffa" or actor.team!=hit.target.team):
		hit.target.apply_damage(1000,actor,"melee")
	if not hit.is_empty():
		impact(hit.position,hit.target!=null,hit.normal)

func shot_fired(actor) -> void:
	weapon_sound.emit(actor.weapon.definition.id,actor.eye_position(),actor.is_player)
	vfx.muzzle_flash(actor.weapon.shot_muzzle,actor.weapon.shot_direction)

func reload_started(actor) -> void:
	if actor==player:reload_sound.emit()

func actor_damaged(actor,source,amount:float) -> void:
	if actor==player:
		var angle=0.0
		if source:
			var direction:Vector3=source.position-player.position
			var look:Vector3=player.aim_direction()
			angle=atan2(direction.x,direction.z)-atan2(look.x,look.z)
		player_damaged.emit(angle,amount)

func actor_killed(victim,killer,weapon_id:String,headshot:bool,remote_death:bool=false) -> void:
	if streaks:streaks.reset(victim.actor_id)
	if victim==player:cancel_equipment_charges()
	if state != "live" and not remote_death:
		if state=="warmup":pending_deaths.append([victim,killer,weapon_id,headshot])
		return
	scores[victim.actor_id].deaths+=1
	if killer==victim:
		scores[victim.actor_id].score=maxi(0,int(scores[victim.actor_id].score)-100)
	if killer and killer!=victim:
		scores[killer.actor_id].kills+=1
		var points=125 if headshot else 100
		scores[killer.actor_id].score+=points
	if streaks and mode.id!="gungame":
		streaks.on_kill(killer,victim,headshot)
	var event={"killer":killer.display_name if killer else "World","victim":victim.display_name,"weapon":weapon_id,"weaponId":weapon_id,"headshot":headshot,"killerTeam":killer.team if killer else "ffa","victimTeam":victim.team,"time":elapsed}
	kill_event.emit(event)
	if mode.id!="gungame":_drop_weapon(victim)
	if player and "scavenger" in player.perks and victim!=player and (player.team=="ffa" or victim.team!=player.team):
		_spawn_ammo_pickup(victim.position)
	_track_replay(victim,killer)
	if network and not remote_death:
		network.local_death(victim,killer,weapon_id,headshot)
	if mode.id=="gungame":
		var tier_ids:Array=Data.table("gun_game_tiers")
		if weapon_id=="melee" and tiers[victim.actor_id]>0:
			tiers[victim.actor_id]-=1
			_equip_tier(victim,tier_ids[tiers[victim.actor_id]])
		if killer and killer!=victim:
			var tier:int=tiers[killer.actor_id]
			if tier==7 and weapon_id=="knife":
				end_match(killer.actor_id)
			elif weapon_id==tier_ids[tier] and (killer.is_player or tier<6):
				tiers[killer.actor_id]=mini(7,tier+1)
				_equip_tier(killer,tier_ids[tiers[killer.actor_id]])

func _equip_tier(actor,weapon_id:String)->void:
	if actor==player or (actor.brain!=null and weapon_id!="knife"):
		actor.set_weapon(weapon_id)

func _drop_weapon(actor) -> void:
	_add_weapon_drop(actor.weapon,actor.position)

func _add_weapon_drop(gun,at:Vector3)->void:
	var visual=Visuals.create_model("weapon_drop")
	add_child(visual)
	visual.position=Vector3(at.x,map.height_at(at.x,at.z)+0.5,at.z)
	visual.rotation.z=0.25
	dropped_weapons.append({"node":visual,"weaponId":gun.definition.id,"magazine":gun.magazine,"reserve":gun.reserve,"attachments":gun.attachments.duplicate(),"expire":elapsed+120})

func _update_pickups(dt:float) -> void:
	prompt=""
	var nearest:Dictionary={}
	var nearest_distance=INF
	for drop in dropped_weapons.duplicate():
		drop.node.rotation.y+=dt*1.5
		if elapsed>=drop.expire:
			drop.node.queue_free()
			dropped_weapons.erase(drop)
			continue
		if not player or not player.alive:continue
		var distance=Vector2(player.position.x-drop.node.position.x,player.position.z-drop.node.position.z).length_squared()
		if distance<1.9*1.9 and distance<nearest_distance:
			nearest=drop
			nearest_distance=distance
	if not player or not player.alive:return
	var care: Dictionary = streaks.nearest_pickup(player) if streaks else {}
	if not care.is_empty():
		var distance: float = Vector2(player.position.x-care.node.position.x,player.position.z-care.node.position.z).length_squared()
		if distance < nearest_distance:
			prompt="Press E — Care Package"
			if Input.is_action_just_pressed("interact"):
				streaks.collect_pickup(care,player)
				prompt=""
			return
	if not nearest.is_empty():
		prompt="Press E — %s (%d/%d)" % [Data.weapon(nearest.weaponId).name,nearest.magazine,nearest.reserve]
		if Input.is_action_just_pressed("interact"):
			var gun=load("res://scripts/game/weapon_runtime.gd").new(nearest.weaponId,nearest.attachments)
			gun.magazine=nearest.magazine
			gun.reserve=nearest.reserve
			_add_weapon_drop(player.weapon,player.position)
			player.weapons[player.current_slot]=gun
			gun.swap_in()
			player.refresh_visuals()
			nearest.node.queue_free()
			dropped_weapons.erase(nearest)
			prompt=""

func _spawn_ammo_pickup(at:Vector3)->void:
	var visual=Visuals.create_model("ammo_pickup")
	add_child(visual)
	visual.position=Vector3(at.x,map.height_at(at.x,at.z)+0.4,at.z)
	ammo_pickups.append({"node":visual,"expire":elapsed+25.0})

func _update_ammo_pickups(dt:float)->void:
	for index in range(ammo_pickups.size()-1,-1,-1):
		var pickup:Dictionary=ammo_pickups[index]
		pickup.node.rotation.y+=dt*2
		var collected=false
		if player and player.alive and Vector2(player.position.x-pickup.node.position.x,player.position.z-pickup.node.position.z).length_squared()<1.8*1.8:
			player.weapon.magazine=player.weapon.stats.magazine
			player.weapon.reserve=player.weapon.stats.reserve
			screen_effect.emit("scavenger",0.25,0.4)
			collected=true
		if collected or elapsed>=pickup.expire:
			pickup.node.queue_free()
			ammo_pickups.remove_at(index)

func objective_goal(actor) -> Dictionary:
	return objective.goal_for(actor) if objective else {}

func team_kills(team:String) -> int:
	var total=0
	for score in scores.values():
		if score.team==team:
			total+=int(score.kills)
	return total

func score_rows() -> Array:
	var rows=scores.values().duplicate(true)
	var insertion:Dictionary={}
	for index in rows.size():insertion[rows[index].id]=index
	rows.sort_custom(func(a,b):return a.score>b.score if a.score!=b.score else insertion[a.id]<insertion[b.id])
	return rows

func _check_win() -> void:
	if objective:
		var outcome:Dictionary=objective.check_win(elapsed,float(mode.timeLimit))
		if outcome.get("over",false):
			end_match(outcome.get("winner"))
		return
	var rows=score_rows()
	if mode.id=="tdm":
		var blue=team_kills("blue")
		var red=team_kills("red")
		if blue>=mode.scoreCap or red>=mode.scoreCap:
			end_match("blue" if blue>=red else "red")
		elif elapsed>=mode.timeLimit:
			end_match(("blue" if blue>red else "red") if blue!=red else null)
	elif mode.id in ["ffa","gungame"] and not rows.is_empty():
		rows.sort_custom(func(a,b):
			if a.kills!=b.kills:return a.kills>b.kills
			if a.score!=b.score:return a.score>b.score
			return a.id<b.id)
		if (mode.id=="ffa" and rows[0].kills>=mode.scoreCap) or elapsed>=mode.timeLimit:
			end_match(rows[0].id)

func end_match(winner_value:Variant,finalize_play:bool=true) -> void:
	if state=="end":
		return
	state="end"
	# Source endByStreak ends immediately and keeps an already captured play;
	# ordinary score/time wins also finalize the player's ongoing streak.
	if finalize_play:_finalize_best_play()
	winner=winner_value
	var blue=team_kills("blue")
	var red=team_kills("red")
	# Game.ts captures scoreboard team kills in the result for every mode;
	# objective points replace only the live HUD scoreline.
	finished.emit({"winner":winner,"rows":score_rows(),"blue":blue,"red":red,"mode":mode.id,"bestPlay":best_play})

func snapshot_actors()->Array:
	var snapshots:Array=[]
	for actor in actors:
		var direction:Vector3=actor.aim_direction()
		var animation:String=actor.remote_animation if network and network.remotes.has(actor.actor_id) else ("die" if not actor.alive else ("shoot" if actor.firing else ("run" if actor.moving else "idle")))
		snapshots.append({"id":actor.actor_id,"name":actor.display_name,"team":actor.team,"isPlayer":actor.is_player,"x":actor.position.x,"y":actor.position.y,"z":actor.position.z,"yaw":atan2(direction.x,direction.z),"alive":actor.alive,"anim":animation,"weaponId":actor.weapon.definition.id})
	return snapshots

func _track_replay(victim,killer)->void:
	if not player:return
	if killer==player and victim!=player:
		if player_killstreak==0:streak_start_time=maxf(0,elapsed-1.0)
		player_killstreak+=1
	if victim==player:
		_finalize_best_play()
		var frames:Array=recorder.recent(elapsed,4.0)
		if frames.size()>=2:
			killcam_ready.emit({"frames":frames,"killerId":killer.actor_id if killer else -1,"victimId":victim.actor_id,"killerName":killer.display_name if killer and killer!=victim else "the enemy"})
		player_killstreak=0

func _finalize_best_play()->void:
	if player and player_killstreak>=2 and player_killstreak>int(best_play.get("kills",0)):
		var frames:Array=recorder.window(streak_start_time,elapsed)
		if frames.size()>=2:best_play={"frames":frames,"kills":player_killstreak,"playerId":player.actor_id}

func set_live_visible(value:bool)->void:
	for child in get_children():
		if child is Node3D and child!=map:child.visible=value

func respawn_player_now()->void:
	if player and not player.alive:_spawn(player)

func hud_state() -> Dictionary:
	if not player:
		return {}
	var gun=player.weapon
	var blips:Array=[]
	var jammed: bool = streaks.is_jammed(player.team) if streaks else false
	if streaks:
		for position_ in streaks.active_pings(player.team):
			blips.append({"x":position_.x,"z":position_.z,"enemy":true})
	for ping in snapshot_pings:
		if not jammed and ping.expire>elapsed and ping.team==player.team:
			blips.append({"x":ping.position.x,"z":ping.position.z,"enemy":true})
	snapshot_pings=snapshot_pings.filter(func(ping):return ping.expire>elapsed)
	var objective_hud:Dictionary=objective.hud() if objective else {}
	var blue=int(objective_hud.get("blue",team_kills("blue")))
	var red=int(objective_hud.get("red",team_kills("red")))
	var direction:Vector3=player.aim_direction()
	var result={"health":player.health,"maxHealth":player.max_health,"mag":gun.magazine,"reserve":gun.reserve,"weaponName":gun.definition.name,"blue":blue,"red":red,"mode":mode.id,"timeLeft":maxf(0,float(mode.timeLimit)-elapsed),"spread":18.0*(1-gun.ads_factor)+(10.0 if player.firing else 0.0),"ads":player.ads_factor,"reloading":gun.state=="reloading","alive":player.alive,"deathText":"RESPAWNING IN %d" % ceili(maxf(0,respawn_delay-player.death_timer)),"streakScore":streak_scores[player.actor_id],"prompt":prompt,"objective":objective_hud,"minimap":{"player":{"x":player.position.x,"z":player.position.z,"yaw":atan2(direction.x,direction.z)},"blips":blips,"bounds":map.bounds,"jammed":false}}
	result.minimap.jammed = jammed
	if not throw_charges.is_empty():result.prompt=throw_prompt()
	result.streaks = streaks.hud(player) if streaks else []
	var next: Dictionary = streaks.next_streak(player) if streaks else {}
	result.nextStreakName = next.get("name")
	result.nextStreakCost = next.get("cost")
	if mode.id=="gungame":
		result.gunGameTier=tiers[player.actor_id]+1
		result.gunGameMaxTier=8
		result.gunGameWeapon=gun.definition.name
	return result

func spawn_rocket(origin:Vector3,direction:Vector3,actor,spec:Dictionary) -> void:
	var visual=Visuals.create_model("rocket")
	add_child(visual)
	visual.position=origin
	rockets.append({"node":visual,"velocity":direction*float(spec.speed),"owner":actor,"spec":spec,"age":0.0,"distance":0.0,"weaponId":actor.weapon.definition.id})

func _tick_rockets(dt:float) -> void:
	for index in range(rockets.size()-1,-1,-1):
		var rocket:Dictionary=rockets[index]
		rocket.age+=dt
		var speed:float=rocket.velocity.length()
		if speed<float(rocket.spec.speed)*2.2 and speed>0.0001:rocket.velocity*=1.0+1.5*dt
		if speed>0.0001:rocket.node.quaternion=Quaternion(Vector3.BACK,rocket.velocity.normalized())
		rocket.velocity.y-=3.0*dt
		var origin:Vector3=rocket.node.position
		var step:Vector3=rocket.velocity*dt
		var hit=raycast(origin,step.normalized(),step.length(),null,false)
		rocket.node.position+=step
		rocket.distance+=step.length()
		if not hit.is_empty() or rocket.age>=6.0 or rocket.distance>=300.0:
			var center:Vector3=hit.position if not hit.is_empty() else rocket.node.position
			explode(center,rocket.spec.splashRadius,0,rocket.owner,rocket.weaponId)
			for actor in actors:
				if not actor.alive or (rocket.owner.team!="ffa" and actor.team==rocket.owner.team):continue
				var distance:float=actor.body_position().distance_to(center)
				if distance>rocket.spec.splashRadius:continue
				var splash:float=rocket.spec.splashDamage*maxf(0,1-distance/rocket.spec.splashRadius)
				var direct:float=rocket.spec.directDamage if not hit.is_empty() and hit.target and distance<0.6 else 0.0
				var amount=maxf(splash,direct)
				if amount>0:actor.apply_damage(amount,rocket.owner,rocket.weaponId)
			rocket.node.queue_free()
			rockets.remove_at(index)

func radial_damage(center:Vector3,radius:float,damage:float,source,weapon_id:String,falloff:bool=true) -> void:
	for actor in actors:
		if not actor.alive or (source and source.team!="ffa" and actor.team==source.team):
			continue
		var distance:float=actor.body_position().distance_to(center)
		if distance<=radius:
			actor.apply_damage(damage*(maxf(0,1-distance/radius) if falloff else 1),source,weapon_id)

func explode(center:Vector3,radius:float,damage:float,source,weapon_id:String) -> void:
	if damage>0:radial_damage(center,radius,damage,source,weapon_id)
	explosion_sound.emit(center,radius)
	vfx.explosion(center,radius)

func tracer(origin:Vector3,end:Vector3) -> void:
	vfx.tracer(origin,end)

func impact(point:Vector3,flesh:bool,normal:Vector3=Vector3.UP) -> void:
	vfx.bullet_impact(point,normal,flesh)

func _flash(point:Vector3,size:float,color:Color,duration:float) -> void:
	var node=MeshInstance3D.new()
	var mesh=SphereMesh.new()
	mesh.radius=size
	mesh.height=size*2
	mesh.radial_segments=8
	mesh.rings=4
	node.mesh=mesh
	node.material_override=_unlit(color)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.position=point
	effects.append({"node":node,"remaining":duration,"duration":duration})

func _tick_effects(dt:float) -> void:
	if vfx:vfx.tick(dt)
	for index in range(effects.size()-1,-1,-1):
		var effect:Dictionary=effects[index]
		effect.remaining-=dt
		if effect.remaining<=0:
			effect.node.queue_free()
			effects.remove_at(index)

static func _unlit(color:Color) -> StandardMaterial3D:
	var material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=color
	return material
