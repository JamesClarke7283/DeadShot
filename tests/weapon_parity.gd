extends SceneTree
const Weapon=preload("res://scripts/game/weapon_runtime.gd")
const Actor=preload("res://scripts/game/combatant.gd")
const Visuals=preload("res://scripts/visuals/visual_factory.gd")
var failures:Array[String]=[]
var checks:=0

class TestActor extends RefCounted:
	var shots:=0
	var recoil:=0.0
	var direction:=Vector3.FORWARD
	var change_aim:=false
	func apply_recoil(pitch:float,_yaw:float)->void:
		recoil+=pitch
		if change_aim:direction=direction.rotated(Vector3.RIGHT,pitch)
	func on_shot()->void:shots+=1
	func eye_position()->Vector3:return Vector3(1,1.7,2)
	func aim_direction()->Vector3:return direction

class TestWorld extends RefCounted:
	var pellets:=0
	var rockets:=0
	var reloads:=0
	var ray_direction:=Vector3.ZERO
	func fire_hitscan(_actor,_gun,_origin,direction)->void:
		pellets+=1
		ray_direction=direction
	func spawn_rocket(_origin,_direction,_actor,_spec)->void:rockets+=1
	func shot_fired(_actor)->void:pass
	func reload_started(_actor)->void:reloads+=1

func _initialize()->void:call_deferred("run")

func check(value:bool,message:String)->void:
	checks+=1
	if not value and failures.size()<30:
		failures.append(message)
		push_error(message)

func vector(value:Array)->Vector3:return Vector3(value[0],value[1],value[2])

func run()->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/weapon_source.json"))
	for record in fixture.weapons:
		var actor:=TestActor.new()
		var world:=TestWorld.new()
		var gun:=Weapon.new(record.id)
		gun.magazine=mini(2,gun.magazine)
		gun.reserve=mini(7,gun.reserve)
		gun.reload_started.connect(func(_empty,_duration):world.reloads+=1)
		for index in record.frames.size():
			var frame:Dictionary=record.frames[index]
			gun.trigger=frame.held
			if frame.reload:gun.reload()
			if frame.swap:gun.swap_in()
			gun.tick(frame.dt,actor,world)
			var label:String="%s frame %d"%[record.id,index]
			check(gun.magazine==int(frame.magazine),label+" magazine")
			check(gun.reserve==int(frame.reserve),label+" reserve")
			check(gun.state==frame.state,label+" state")
			check(actor.shots==int(frame.shots),label+" shots")
			check(world.reloads==int(frame.reloads),label+" reload callback")
			check(absf(actor.recoil-float(frame.recoil))<0.000001,label+" recoil")
			check(world.pellets==int(frame.pellets),label+" pellets")
			check(world.rockets==int(frame.rockets),label+" rockets")
	var aim_actor:=TestActor.new()
	aim_actor.change_aim=true
	var aim_world:=TestWorld.new()
	var aim_gun:=Weapon.new("m4")
	aim_gun.stats.spreadMult=0.0
	aim_gun.recoil_pitch=0.1
	aim_gun.trigger=true
	aim_gun.tick(0.1,aim_actor,aim_world)
	check(aim_gun.shot_direction==Vector3.FORWARD and aim_world.ray_direction==Vector3.FORWARD,"All shot geometry uses cached aim from before recoil recovery and kick")
	check(aim_gun.shot_muzzle.is_equal_approx(Vector3(1,1.7,1.6)),"Tracer and rocket muzzle uses unperturbed aim")
	check(Weapon.perturb(Vector3(0,0,-2),0.0)==Vector3(0,0,-2),"Zero spread returns source direction unchanged")

	var game:=TestWorld.new()
	var player=Actor.new()
	root.add_child(player)
	player.setup(0,"blue",true,{"primary":{"weaponId":"m4"},"secondary":{"weaponId":"m9"}},game)
	var ads_on:=false
	for index in fixture.visualFrames.size():
		var frame:Dictionary=fixture.visualFrames[index]
		var operation:Dictionary=frame.operation
		if operation.has("weapon"):player.set_weapon(operation.weapon)
		if operation.has("ads"):ads_on=operation.ads
		if operation.get("shot",false):player.on_shot()
		if operation.has("reload"):player._reload_started(false,operation.reload)
		if operation.get("melee",false):player.melee_slash()
		player.ads_factor=0.0 if player.weapon.definition.id=="knife" else move_toward(player.ads_factor,1.0 if ads_on else 0.0,float(operation.dt)/maxf(0.05,float(player.weapon.stats.adsTime)))
		player._update_viewmodel(operation.dt)
		var gun=Visuals.part(player.viewmodel,"gun")
		var knife=Visuals.part(player.viewmodel,"knife")
		var label:String="Viewmodel transition %d"%index
		check(is_equal_approx(player.ads_factor,float(frame.ads)),label+" ADS")
		check(player.viewmodel.position.is_equal_approx(vector(frame.root)),label+" root position")
		check(gun.position.is_equal_approx(vector(frame.gun)),label+" gun position")
		check(gun.rotation.is_equal_approx(vector(frame.gunRotation)),label+" gun rotation")
		check(gun.visible==frame.gunVisible,label+" gun visibility")
		check(knife.position.is_equal_approx(vector(frame.knife)),label+" knife position")
		check(knife.rotation.is_equal_approx(vector(frame.knifeRotation)),label+" knife rotation")
		check(knife.visible==frame.knifeVisible,label+" knife visibility")
	player.set_weapon("m4")
	player.weapon.state="ready"
	player.weapon.magazine=0
	player.weapon.reserve=7
	player.weapon.trigger=true
	game.reloads=0
	player.weapon.tick(0.1,player,game)
	check(game.reloads==1 and player.view_reloading,"Auto-empty reload triggers one audio/viewmodel callback")
	player.weapon.reload()
	check(game.reloads==1,"Repeated reload does not duplicate callbacks")
	player.weapon.state="ready"
	player.weapon.magazine=5
	player.refresh_visuals()
	player.weapon.reload()
	check(game.reloads==2,"Manual reload and refresh do not double-connect callbacks")
	player.alive=false
	player.viewmodel.visible=true
	player.tick(0.1)
	check(player.viewmodel.visible,"Dead player retains frozen viewmodel when killcam is disabled")
	player.is_player=false
	player.set_weapon("m9")
	check(player.weapon.state=="ready","Bot weapon changes have no player swap delay")
	player.rotation.y=0.9
	player._animate(0.125)
	var source_matrix:Array=fixture.deathMatrix
	var expected_basis:=Basis(vector(source_matrix.slice(0,3)),vector(source_matrix.slice(4,7)),vector(source_matrix.slice(8,11)))
	check(player.human.global_basis.is_equal_approx(expected_basis),"Bot death preserves source combined XYZ pitch/yaw despite native actor parent")
	player.queue_free()
	await process_frame
	print("WEAPON_PARITY: ",checks," checks; ",failures.size()," failures. Original 19 weapon timelines and 11 viewmodel transitions, reload hooks, knife firing and pre-recoil muzzle verified.")
	quit(0 if failures.is_empty() else 1)
