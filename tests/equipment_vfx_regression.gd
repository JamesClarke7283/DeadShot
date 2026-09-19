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
	var tint=Color("ffe08a").srgb_to_linear()
	var material:ShaderMaterial=thermite.particles[0].mesh.material_override
	_expect(material.get_shader_parameter("base_color").is_equal_approx(Vector3(tint.r,tint.g,tint.b)),"Thermite source white-hot palette is retained")
	system._tick_item(thermite,1.0)
	_expect(world.dots.size()==1 and world.dots[0][0]==Vector3(2,0,3) and world.dots[0][2]==40 and not world.dots[0][4],"Thermite DoT uses original impact center and flat 40 damage each second")
	system._tick_item(thermite,4.0)
	_expect(not thermite.active and world.dots.size()==1,"Fire does not catch up damage on its expiry frame")
	system.throw_item("flashbang",player)
	var flash:Dictionary=system.items.back()
	flash.node.position=Vector3.ZERO
	player.position=Vector3(0,17,0)
	system._detonate(flash)
	_expect(world.effects.size()==2 and world.effects[0][1]==0.5,"Flash uses source player body center, including exact range boundary")
	var vfx=VFX.new()
	root.add_child(vfx)
	vfx.bullet_impact(Vector3.ZERO,Vector3.UP,true)
	_expect(vfx.decals.is_empty() and vfx.transients.size()==1,"Actor impacts create spark without a bullet hole")
	vfx.tick(0.06)
	_expect(vfx.transients[0].node.scale.is_equal_approx(Vector3.ONE*1.25) and is_equal_approx(vfx.transients[0].node.material_override.get_shader_parameter("opacity"),0.5),"Impact spark follows exact scale/opacity over 120ms")
	for i in range(100):vfx.bullet_hole(Vector3(i,0,0),Vector3.UP)
	_expect(vfx.decals.size()==96 and vfx.decals[0].position.x==4,"Bullet holes persist with oldest-first recycling at 96")
	vfx.tracer(Vector3.ZERO,Vector3(0,0,4))
	var tracer=vfx.transients.back().node
	_expect(tracer.position==Vector3(0,0,2) and tracer.scale==Vector3(1,4,1),"Tracer uses exact cylinder midpoint and length")
	vfx.muzzle_flash(Vector3(0,0,1),Vector3.BACK)
	var muzzle=vfx.transients.back().node
	_expect(muzzle.position.is_equal_approx(Vector3(0,0,1.2)) and "blend_add" in muzzle.material_override.shader.code,"Muzzle flash is source additive plane 20cm ahead of muzzle")
	vfx.clear()
	vfx.explosion(Vector3(2,3,4),6)
	vfx.tick(0.175)
	_expect(vfx.transients.size()==2 and is_equal_approx(vfx.transients[1].node.light_energy,4.0),"Explosion pairs 450ms sphere with 350ms light fade")
	MATERIALS.update_point_lights(true)
	_expect(MATERIALS._light_count==1 and MATERIALS._light_positions[0]==Vector4(2,3,4,24),"Point-light source range and coordinates feed shared toon radiance")
	vfx.tick(0.3)
	_expect(vfx.transients.is_empty(),"Explosion transient nodes expire at source lifetimes")
	system.queue_free()
	vfx.queue_free()
	await process_frame
	_expect(MATERIALS._light_count==0,"Disposed transient point lights leave no stale illumination")
	if failures.is_empty():print("EQUIPMENT/VFX PARITY PASS: %d checks"%checks)
	else:
		for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
