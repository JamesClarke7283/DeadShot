extends SceneTree
## Meaningful source lifecycle and visual-effect state regressions.
const EQUIPMENT=preload("res://scripts/game/equipment_system.gd")
const VFX=preload("res://scripts/visuals/combat_vfx.gd")
const MATERIALS=preload("res://scripts/world/map_material.gd")
const VISUALS=preload("res://scripts/visuals/visual_factory.gd")
var failures:Array[String]=[]
var checks:=0

class World extends RefCounted:
	var environment_data:Dictionary={}

class Actor extends RefCounted:
	var alive:=true
	var team:="blue"
	var position:=Vector3.ZERO
	var direction:=Vector3.BACK
	var health:=100.0
	var damage_owner:Variant="unhit"
	func eye_position()->Vector3:return position+Vector3.UP*1.7
	func body_position()->Vector3:return position+Vector3.UP
	func aim_direction()->Vector3:return direction
	func apply_damage(amount:float,_owner,_id)->void:
		damage_owner=_owner
		health-=amount
		alive=health>0

class MatchStub extends RefCounted:
	signal screen_effect(kind:String,intensity:float,duration:float)
	signal player_hit(headshot:bool,killed:bool)
	var map=World.new()
	var player=Actor.new()
	var actors:Array=[]
	var elapsed:=10.0
	var ui_time:=0.0
	var snapshot_pings:Array=[]
	var blasts:Array=[]
	var dots:Array=[]
	var last_ray:Array=[]
	var effects:Array=[]
	func _init()->void:screen_effect.connect(_record_effect)
	func _record_effect(kind:String,intensity:float,duration:float)->void:effects.append([kind,intensity,duration])
	func raycast(origin:Vector3,direction:Vector3,distance:float,ignore=null,projectile:bool=false)->Dictionary:
		last_ray=[origin,direction,distance,ignore,projectile]
		return {}
	func explode(center:Vector3,radius:float,damage:float,_owner,id:String)->void:blasts.append([center,radius,damage,id])
	func radial_damage(center:Vector3,radius:float,damage:float,_owner,id:String,falloff:bool)->void:dots.append([center,radius,damage,id,falloff])

func _initialize()->void:call_deferred("_run")
func _expect(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)

## First recorded screen effect of a kind, or an empty array.
func _effect(effects:Array,kind:String)->Array:
	for effect in effects:
		if str(effect[0])==kind:return effect
	return []

func _run()->void:
	var world=MatchStub.new()
	var system=EQUIPMENT.new()
	system.game_match=world
	root.add_child(system)
	var player=world.player
	system.throw_item("semtex",player)
	var semtex:Dictionary=system.items.back()
	system._impact(semtex,{"position":semtex.node.position,"normal":Vector3.UP,"target":null})
	system._tick_item(semtex,0.1)
	var semtex_part=VISUALS.part(semtex.node,"equipment_semtex")
	var red=Color("ff3300").srgb_to_linear()
	_expect(semtex.stuck and is_equal_approx(semtex.fuse,1.4),"Semtex starts 1.5s fuse on contact and cooks on impact tick")
	_expect(semtex_part.material_override.get_shader_parameter("emissive_color").is_equal_approx(Vector3(red.r,red.g,red.b)),"Stuck semtex emissive blink follows accelerating source sine")
	system._tick_item(semtex,1.4)
	_expect(not semtex.active and world.blasts.back()[1]==5.5,"Semtex detonates once at source radius")
	system.throw_item("c4",player)
	var charge:Dictionary=system.items.back()
	system._impact(charge,{"normal":Vector3.UP,"target":null})
	system._tick_item(charge,0.1)
	var led=VISUALS.part(charge.node,"part_3")
	red=Color("660000").srgb_to_linear()
	_expect(led.material_override.get_shader_parameter("emissive_color").is_equal_approx(Vector3(red.r,red.g,red.b)),"Placed C4 uses slow red LED pulse")
	world.elapsed+=0.2
	system.throw_item("c4",player)
	_expect(not charge.active and world.blasts.back()[1]==7.0,"Double-press remotely detonates active C4")
	player.direction=Vector3.UP
	system.throw_item("claymore",player)
	var mine:Dictionary=system.items.back()
	_expect(mine.facing==Vector3.BACK,"Vertical claymore throw falls back to positive Z")
	mine.node.position=Vector3.ZERO
	system._impact(mine,{"normal":Vector3.UP,"target":null})
	var enemy=Actor.new()
	enemy.team="red"
	enemy.position=Vector3(0,0,2)
	world.actors=[player,enemy]
	system._tick_item(mine,1.0)
	_expect(mine.active and mine.laser.material_override.get_shader_parameter("opacity")==0.0,"Claymore arm boundary does not scan or reveal laser until next update")
	system._tick_item(mine,0.01)
	_expect(not mine.active and mine.laser.material_override.get_shader_parameter("opacity")==0.35,"Armed claymore reveals source beam and triggers frontal target")
	_expect(enemy.health<100.0 and player.health==100.0,"Directional claymore damage uses body-center distance and skips team")
	_expect(enemy.damage_owner==null,"Claymore retains source omitted killer attribution")
	player.direction=Vector3.BACK
	system.throw_item("frag",player)
	var frag:Dictionary=system.items.back()
	system._tick_item(frag,0.016)
	_expect(world.last_ray[3]==null and world.last_ray[4],"Thrown equipment requests zero actor skip and source geometry spawn skip")
	system.throw_item("thermite",player)
	var thermite:Dictionary=system.items.back()
	thermite.node.position=Vector3(2,0,3)
	system._detonate(thermite)
	_expect(thermite.particles.size()==14 and thermite.node.position==Vector3(2,0.04,3),"Thermite spawns 14 source sparks at four centimeter offset")
	var placements=true
	for particle in thermite.particles:placements=placements and particle.mesh.position.y>=0.1 and particle.mesh.position.y<=0.4
	_expect(placements and world.blasts.back()[1]==0.8,"Thermite uses source height distribution and 0.8m pop")
	# Emissive props now feed the environment glow pass, so energy above one is
	# what makes them read as light rather than painted-on colour.
	var material:ShaderMaterial=thermite.particles[0].mesh.material_override
	var tint=Color("ffe08a")
	_expect(material.get_shader_parameter("color").is_equal_approx(Vector3(tint.r,tint.g,tint.b)) and float(material.get_shader_parameter("energy"))>1.0,"Thermite white-hot palette emits above the glow threshold")
	system._tick_item(thermite,1.0)
	_expect(world.dots.size()==1 and world.dots[0][0]==Vector3(2,0,3) and world.dots[0][2]==40 and not world.dots[0][4],"Thermite DoT uses original impact center and flat 40 damage each second")
	system._tick_item(thermite,4.0)
	_expect(not thermite.active and world.dots.size()==1,"Fire does not catch up damage on its expiry frame")
	system.throw_item("flashbang",player)
	var flash:Dictionary=system.items.back()
	flash.node.position=Vector3.ZERO
	# A flashbang's effect is now a visibility model rather than a single
	# line-of-sight test: the blast is sampled through to several points across
	# the victim, scaled by how much of it they can see. The stub reports every
	# ray as clear, so the blast is unoccluded and the victim faces it.
	player.position=Vector3(0,0,2)
	player.direction=Vector3.FORWARD
	system._detonate(flash)
	# The thrower's own screen also takes a concussive shake, so the flash and
	# deafen are looked up by kind rather than by position in the list.
	var flash_effect:=_effect(world.effects,"flash")
	var deafen_effect:=_effect(world.effects,"deafen")
	_expect(not flash_effect.is_empty() and not deafen_effect.is_empty(),"Flash emits a flash and a deafen through the screen-effect channel")
	# Standing almost on the blast is the fully-exposed end of the scale, so the
	# flash must be at its strongest and last the longest there.
	var centred_intensity:=float(flash_effect[1])
	var centred_duration:=float(flash_effect[2])
	_expect(centred_intensity>0.0 and centred_duration>0.0,"An unoccluded point-blank flash is at full strength")
	system.throw_item("flashbang",player)
	var far_flash:Dictionary=system.items.back()
	far_flash.node.position=Vector3.ZERO
	player.position=Vector3(0,0,14)
	world.effects.clear()
	system._detonate(far_flash)
	var far_effect:=_effect(world.effects,"flash")
	var far_intensity:=float(far_effect[1])
	var far_duration:=float(far_effect[2])
	_expect(far_intensity<centred_intensity and far_duration<centred_duration,"A distant flash is weaker and shorter than a point-blank one")
	var vfx=VFX.new()
	root.add_child(vfx)
	vfx.bullet_impact(Vector3.ZERO,Vector3.UP,true)
	# An impact is now one burst transient whose node is a container owning the
	# individual particles, so a blast costs one ageing entry rather than one per
	# spark.
	_expect(vfx.decals.is_empty() and vfx.transients.size()==1,"Actor impacts kick up sparks and blood without a bullet hole")
	_expect(vfx.transients[0].node is Node3D and not (vfx.transients[0].node is MeshInstance3D) and vfx.transients[0].parts.size()>0,"Impact is a layered burst of particles under one container")
	vfx.tick(0.06)
	# Per-particle fade is an instanced uniform now, so the burst can animate
	# every spark from a single material.
	var faded:=false
	var hidden:=false
	for part in vfx.transients[0].parts:
		var particle:MeshInstance3D=part.node
		var fade:Variant=particle.get_instance_shader_parameter("fade")
		if fade != null and float(fade)<1.0:faded=true
		if not particle.visible:hidden=true
	_expect(faded or hidden,"Impact particles fade or expire over their lifetime")
	for i in range(100):vfx.bullet_hole(Vector3(i,0,0),Vector3.UP)
	_expect(vfx.decals.size()==96 and vfx.decals[0].position.x==4,"Bullet holes persist with oldest-first recycling at 96")
	vfx.tracer(Vector3.ZERO,Vector3(0,0,4))
	var tracer_burst=vfx.transients.back()
	var tracer_core:MeshInstance3D=tracer_burst.parts[0].node
	# The round now visibly travels: it spawns at the muzzle and its parent
	# advances to the segment midpoint over its travel time, while the core
	# stretches from short to the segment's full length.
	_expect(tracer_core.scale.y<4.0 and tracer_burst.node.position.z<0.0,"Tracer spawns short at the muzzle and stretches into its segment")
	vfx.tick(0.02)
	# The parent advances rather than sitting at the midpoint: each particle keeps
	# its own local offset, so only the core lands on the midpoint.
	_expect(absf(tracer_core.position.y-2.0)<0.35,"Tracer reaches the segment midpoint as it stretches")
	_expect(absf(tracer_core.scale.y-4.0)<0.4,"Tracer reaches the full segment length")
	vfx.muzzle_flash(Vector3(0,0,1),Vector3.BACK)
	var muzzle=vfx.transients.back()
	# A muzzle flash carries a real light, so it illuminates the scene instead of
	# only adding a bright quad.
	_expect(muzzle.kind=="light" and muzzle.node is OmniLight3D and muzzle.node.light_energy>1.0,"Muzzle flash adds a real light source")
	vfx.clear()
	vfx.explosion(Vector3(2,3,4),6)
	var light_count:=0
	for effect in vfx.transients:
		if effect.kind=="light":
			light_count+=1
			_expect(effect.node.omni_range==30.0,"Explosion light range scales from the blast radius")
	_expect(vfx.transients.size()==2 and light_count==1,"Explosion pairs one layered blast with one real light")
	# The light is the shortest-lived half of the blast and outlives the fireball
	# but not the smoke, so the burst is the only thing left once it expires.
	vfx.tick(0.6)
	_expect(vfx.transients.size()==1 and vfx.transients[0].kind=="burst","The blast light expires while the smoke and debris burst lingers")
	vfx.tick(4.0)
	_expect(vfx.transients.is_empty(),"Explosion transients expire")
	system.queue_free()
	vfx.queue_free()
	await process_frame
	if failures.is_empty():print("EQUIPMENT/VFX PARITY PASS: %d checks"%checks)
	else:
		for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
