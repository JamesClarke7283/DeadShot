extends SceneTree
const Data=preload("res://scripts/core/game_data.gd")
const Weapon=preload("res://scripts/game/weapon_runtime.gd")
const Session=preload("res://scripts/game/match_session.gd")
var failures:Array[String]=[]

class TestActor extends RefCounted:
	var shots=0
	func apply_recoil(_pitch:float,_yaw:float)->void:pass
	func on_shot()->void:shots+=1
	func eye_position()->Vector3:return Vector3(0,1.7,0)
	func aim_direction()->Vector3:return Vector3.FORWARD

class TestWorld extends RefCounted:
	var hits=0
	func fire_hitscan(_actor,_gun,_origin,_direction)->void:hits+=1
	func spawn_rocket(_origin,_direction,_actor,_spec)->void:hits+=1

func _initialize()->void:
	call_deferred("run")

func check(ok:bool,message:String)->void:
	if not ok:
		failures.append(message)
		push_error(message)

func compare(expected:Variant,actual:Variant,path:String)->void:
	if expected is Dictionary:
		for key in expected:
			check(actual is Dictionary and actual.has(key),path+" missing "+key)
			if actual is Dictionary and actual.has(key):compare(expected[key],actual[key],path+"."+key)
	elif expected is Array:
		check(expected==actual,path+" differs")
	elif expected is float or expected is int:
		check(is_equal_approx(float(expected),float(actual)),path+" differs: "+str(actual)+" / "+str(expected))
	else:check(expected==actual,path+" differs")

func run()->void:
	for fixture in Data.table("stat_fixtures"):
		compare(fixture.expected,Data.stats(Data.weapon(fixture.weapon),fixture.attachments),fixture.weapon)
	var actor=TestActor.new()
	var world=TestWorld.new()
	var gun=Weapon.new("m9")
	gun.trigger=true
	for i in range(120):gun.tick(1.0/60,actor,world)
	check(actor.shots==1,"Semi-auto must fire once per trigger press")
	gun.trigger=false
	gun.tick(1.0/60,actor,world)
	gun.trigger=true
	gun.tick(1.0/60,actor,world)
	check(actor.shots==2,"Semi-auto second press must fire")
	gun=Weapon.new("m16a4")
	actor.shots=0
	gun.trigger=true
	gun.tick(1.0/60,actor,world)
	gun.trigger=false
	for i in range(90):gun.tick(1.0/60,actor,world)
	check(actor.shots==3,"Burst must complete after trigger release")
	gun=Weapon.new("m4")
	gun.magazine=0
	gun.reserve=17
	check(gun.reload(),"Empty weapon should reload")
	for i in range(180):gun.tick(1.0/60,actor,world)
	check(gun.magazine==17 and gun.reserve==0,"Reload conserves scarce reserve ammo")
	check(is_equal_approx(Data.damage_at_range(Data.stats(Data.weapon("m4")),47),27.5),"M4 range falloff matches source")
	check(is_equal_approx(Session.ray_sphere(Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,-5),0.6),4.4),"Analytic hit distance")
	check(Session.ray_sphere(Vector3.ZERO,Vector3.FORWARD,Vector3(8,0,-5),0.6)<0,"Missed sphere is not a hit")
	var scene=Session.new()
	root.add_child(scene)
	check(scene.start({"mapId":"desert_town","mode":"tdm","botCount":8,"difficulty":"regular","hasPlayer":false},Data.table("default_save").classes[0],Data.table("default_save").settings),"Match loads")
	await physics_frame
	await physics_frame
	var initial:Array=[]
	for bot in scene.actors:initial.append(bot.position)
	# Eight bots fight for 60 simulated seconds from randomised spawns. Two
	# properties vary per run and one does not:
	#   * the kill total is sparse and noisy — measured 0 kills in about a quarter
	#     of runs, and 0-3 otherwise. The map is 140 m across with 27 spawn pads,
	#     so bots frequently spend the window closing rather than shooting, and
	#     between engagements they regenerate to full. Asserting a kill on one
	#     window fails intermittently for reasons unrelated to the code under test.
	#   * the damage the bots deal is stable — measured 380-460 per 60 s window
	#     across runs.
	# The contract worth defending is therefore that the combat loop is live:
	# bots close, acquire and damage each other. Damage is accumulated per tick
	# rather than sampled at the end, because regeneration would otherwise erase
	# an engagement that completed inside the window.
	var previous:Array=[]
	for bot in scene.actors:previous.append(bot.health)
	var damage_dealt := 0.0
	var total_kills := 0
	var moved := 0
	for step in range(3600):
		scene.tick(1.0/60)
		for index in range(scene.actors.size()):
			var now:float=scene.actors[index].health
			if now<previous[index]:damage_dealt+=previous[index]-now
			previous[index]=now
		if step%60==0:await process_frame
	total_kills=scene.team_kills("blue")+scene.team_kills("red")
	for index in range(scene.actors.size()):
		if scene.actors[index].position.distance_to(initial[index])>2:moved+=1
	check(damage_dealt>150.0,"Bots must engage and damage each other (dealt %.1f, kills %d)" % [damage_dealt,total_kills])
	check(moved>=6,"Bots navigate beyond spawn pads")
	print("SIMULATION: kills=",total_kills," damage=%.1f"%damage_dealt," moved=",moved," elapsed=",scene.elapsed)
	scene.free()
	print("CORE REGRESSION: ","PASS" if failures.is_empty() else "FAIL", " (",failures.size()," failures)")
	quit(0 if failures.is_empty() else 1)
