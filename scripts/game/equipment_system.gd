extends Node3D
## Native projectile equipment with original fuses, bounce, blast/DoT balance.
const Visuals=preload("res://scripts/visuals/visual_factory.gd")
const VFX=preload("res://scripts/visuals/combat_vfx.gd")
const Materials=preload("res://scripts/world/map_material.gd")
const CHARGE_SECONDS=1.25
const CHARGED_MIN_SPEED=18.0
const CHARGED_MAX_SPEED=52.0
const CONFIG={
	"frag":{"speed":22.0,"gravity":20.0,"bounce":0.4,"fuse":3.0,"radius":6.0,"damage":120.0},
	"semtex":{"speed":24.0,"gravity":18.0,"bounce":0.0,"fuse":0.0,"radius":5.5,"damage":130.0},
	"flashbang":{"speed":22.0,"gravity":20.0,"bounce":0.45,"fuse":1.6},
	"stun":{"speed":22.0,"gravity":20.0,"bounce":0.45,"fuse":1.6},
	"snapshot":{"speed":22.0,"gravity":20.0,"bounce":0.4,"fuse":1.4},
	"smoke":{"speed":20.0,"gravity":20.0,"bounce":0.3,"fuse":1.4},
	"knife":{"speed":40.0,"gravity":3.0,"bounce":0.0,"fuse":0.0},
	"c4":{"speed":18.0,"gravity":20.0,"bounce":0.15,"fuse":0.0,"radius":7.0,"damage":140.0},
	"molotov":{"speed":22.0,"gravity":20.0,"bounce":0.0,"fuse":0.0,"radius":3.0,"duration":6.0,"dps":25.0},
	"thermite":{"speed":22.0,"gravity":20.0,"bounce":0.0,"fuse":0.0,"radius":2.5,"duration":5.0,"dps":40.0},
	"claymore":{"speed":14.0,"gravity":20.0,"bounce":0.1,"fuse":0.0,"radius":5.0,"damage":150.0},
}
var game_match
var items:Array=[]
var last_c4_throw:float=-1.0

func throw_item(id:String,actor,charge:float=-1.0)->void:
	if not CONFIG.has(id) or not actor.alive:
		return
	if id=="c4" and game_match.elapsed-last_c4_throw<0.35:
		for item in items:
			if item.id=="c4" and item.active:_detonate(item)
		last_c4_throw=game_match.elapsed
		return
	if id=="c4":last_c4_throw=game_match.elapsed
	var settings:Dictionary=CONFIG[id]
	var visual=Visuals.create_equipment(id,actor.team)
	add_child(visual)
	visual.position=actor.eye_position()
	var direction:Vector3=actor.aim_direction()
	var charged:=charge>=0.0 and id in ["frag","flashbang"]
	var velocity:Vector3=direction*float(settings.speed)
	if charged:
		var power:=clampf(charge,0.0,1.0)
		velocity=direction*lerpf(CHARGED_MIN_SPEED,CHARGED_MAX_SPEED,power)+Vector3.UP*lerpf(4.0,12.0,power)
	var facing=Vector3(direction.x,0,direction.z)
	if facing.length_squared()<0.000001:facing=Vector3.BACK
	facing=facing.normalized()
	items.append({"id":id,"config":settings,"owner":actor,"node":visual,"velocity":velocity,"charged":charged,"facing":facing,"fuse":settings.fuse,"active":true,"stuck":false,"detonated":false,"age":0.0,"arm":1.0,"rest":6.0,"tick":0.0,"particles":[],"blink":0.0,"laser":null,"effect_point":visual.position})

func tick(dt:float)->void:
	for index in range(items.size()-1,-1,-1):
		var item:Dictionary=items[index]
		if item.active:
			_tick_item(item,dt)
		if not item.active:
			item.node.queue_free()
			items.remove_at(index)

func _tick_item(item:Dictionary,dt:float)->void:
	if item.detonated:
		_tick_area(item,dt)
		return
	if item.stuck:
		if item.id=="knife":
			item.rest-=dt
			item.active=item.rest>0
		elif item.id=="claymore":
			if item.arm>0:
				item.arm-=dt
				return
			if item.laser:item.laser.material_override.set_shader_parameter("opacity",0.35)
			if item.arm<=0:
				for actor in game_match.actors:
					if _in_claymore_cone(item,actor):
						_detonate(item)
						break
	else:
		item.velocity.y-=item.config.gravity*dt
		var previous:Vector3=item.node.position
		var step:Vector3=item.velocity*dt
		item.node.position+=step
		if step.length()>0.00001:
			# Charged throws clear the thrower and check the entire swept segment,
			# including short steps, so they cannot bounce off their owner's head
			# or pass through nearby cover at a high frame rate.
			var hit:Dictionary
			if item.get("charged",false):
				hit=game_match.raycast(previous,step.normalized(),step.length(),item.owner,true,false)
			else:
				hit=game_match.raycast(previous,step.normalized(),step.length(),null,true)
			if not hit.is_empty():
				item.node.position=hit.position
				_impact(item,hit)
		if item.id=="knife" and item.velocity.length_squared()>0.0001:
			item.node.quaternion=Quaternion(Vector3.BACK,item.velocity.normalized())
	if item.fuse>0:
		item.fuse-=dt
		if item.fuse<=0:_detonate(item)
	if item.stuck and not item.detonated and item.active:
		item.blink+=dt
		if item.id=="semtex":
			var rate=6.0+(1.5-maxf(0,item.fuse))*6.0
			_set_emissive(item.node,Color("ff3300") if sin(item.blink*rate)>0 else Color("224400"),"equipment_semtex")
		elif item.id=="c4":
			_set_emissive(item.node,Color("660000") if sin(item.blink*3.0)>0 else Color("220000"),"part_3")

func _impact(item:Dictionary,hit:Dictionary)->void:
	match item.id:
		"semtex":
			item.stuck=true
			item.velocity=Vector3.ZERO
			item.fuse=1.5
		"c4","claymore":
			item.stuck=true
			item.velocity=Vector3.ZERO
			if item.id=="claymore":
				item.node.rotation.y=atan2(item.facing.x,item.facing.z)
				_spawn_laser(item)
		"knife":
			if hit.target and hit.target.alive and (item.owner.team=="ffa" or hit.target.team!=item.owner.team):
				hit.target.apply_damage(1000,item.owner,"knife")
				if item.owner==game_match.player:game_match.player_hit.emit(false,not hit.target.alive)
			item.stuck=true
			item.velocity=Vector3.ZERO
		"molotov","thermite":_detonate(item)
		_:
			item.velocity=item.velocity.bounce(hit.normal)*float(item.config.bounce)
			item.node.position+=hit.normal*0.05

func _detonate(item:Dictionary)->void:
	if item.detonated:return
	item.detonated=true
	var point:Vector3=item.node.position
	match item.id:
		"frag","semtex","c4":
			game_match.explode(point,item.config.radius,item.config.damage,item.owner,item.id)
			item.active=false
		"claymore":
			game_match.explode(point,3,0,item.owner,item.id)
			for actor in game_match.actors:
				if _in_claymore_cone(item,actor):
					var distance:float=actor.body_position().distance_to(point)
					# Source Claymore omits sourceId from its damage event.
					actor.apply_damage(150.0*maxf(0,1-distance/5.0),null,"claymore")
			item.active=false
		"flashbang","stun":
			game_match.explode(point,2.0 if item.id=="flashbang" else 1.5,0,item.owner,item.id)
			var player=game_match.player
			if player:
				var offset:Vector3=player.body_position()-point
				var distance=offset.length()
				var radius=18.0 if item.id=="flashbang" else 12.0
				var hit:Dictionary={}
				if distance>0.001:hit=game_match.raycast(point,offset.normalized(),distance,null,false)
				if distance<=radius and (hit.is_empty() or hit.distance>=distance-0.5):
					var proximity=1.0-distance/radius
					if item.id=="flashbang":
						game_match.screen_effect.emit("flash",0.5+0.5*proximity,3.2*proximity)
						game_match.screen_effect.emit("deafen",1.0,4.0*proximity)
					else:
						game_match.screen_effect.emit("stun",0.6*proximity,2.5*proximity+0.3)
						game_match.screen_effect.emit("deafen",1.0,2.0*proximity)
			item.active=false
		"snapshot":
			game_match.explode(point,2,0,item.owner,item.id)
			for actor in game_match.actors:
				if actor.alive and (item.owner.team=="ffa" or actor.team!=item.owner.team) and actor.body_position().distance_to(point)<=25:
					game_match.snapshot_pings.append({"position":actor.body_position(),"team":item.owner.team,"expire":game_match.elapsed+5.0})
			item.active=false
		"smoke","molotov","thermite":
			_create_area(item)

func _in_claymore_cone(item:Dictionary,actor)->bool:
	if not actor.alive or (item.owner.team!="ffa" and actor.team==item.owner.team):return false
	var offset:Vector3=actor.body_position()-item.node.position
	var distance=offset.length()
	return distance>=0.001 and distance<=5 and offset.normalized().dot(item.facing)>=0.5

func _create_area(item:Dictionary)->void:
	var point:Vector3=item.node.position
	item.effect_point=point
	item.node.queue_free()
	item.node=Node3D.new()
	add_child(item.node)
	item.node.position=point+Vector3.UP*(0.5 if item.id=="smoke" else (0.04 if item.id=="thermite" else 0.05))
	var count=7 if item.id=="smoke" else (10 if item.id=="molotov" else 14)
	for i in range(count):
		var mesh=MeshInstance3D.new()
		var color=Color("cdd2d8")
		var emissive=Color.BLACK
		if item.id=="molotov":
			color=Color("ff8a1e")
			emissive=Color("ff4400")
		elif item.id=="thermite":
			color=Color("ffe08a")
			emissive=Color("ffaa00")
		mesh.mesh=VFX.geometry(item.id+"Geo")
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var linear=color.srgb_to_linear()
		var emit_linear=emissive.srgb_to_linear()
		mesh.material_override=Materials.create_material({"color":[linear.r,linear.g,linear.b],"emissive":[emit_linear.r,emit_linear.g,emit_linear.b],"transparent":true,"opacity":0.0 if item.id=="smoke" else (1.0 if item.id=="thermite" else 0.9),"doubleSide":item.id!="thermite"},game_match.map.environment_data)
		item.node.add_child(mesh)
		var base=randf_range(1.4,2.8) if item.id=="smoke" else randf_range(0.3,0.8)
		if item.id=="smoke":
			mesh.position=Vector3(randf_range(-2,2),randf()*1.2,randf_range(-2,2))
			mesh.scale=Vector3.ONE*0.1
		else:
			var angle=randf()*TAU if item.id=="thermite" else TAU*float(i)/count
			var radius=randf()*float(item.config.radius)
			mesh.position=Vector3(cos(angle)*radius,randf_range(0.1,0.4) if item.id=="thermite" else base*0.5,sin(angle)*radius)
		item.particles.append({"mesh":mesh,"base":base,"phase":randf()*TAU})
	if item.id!="smoke":game_match.explode(point,0.8 if item.id=="thermite" else 1.0,0,item.owner,item.id)

func _tick_area(item:Dictionary,dt:float)->void:
	item.age+=dt
	if item.id=="smoke":
		var grow=minf(1,item.age/1.5)
		var fade=clampf((9-item.age)/2.5,0,1)
		for particle in item.particles:
			particle.mesh.position.y+=0.35*dt
			particle.mesh.scale=Vector3.ONE*float(particle.base)*grow
			particle.mesh.material_override.set_shader_parameter("opacity",0.55*grow*fade)
		item.active=item.age<9
	else:
		var lifetime:float=item.config.duration
		var fade=clampf(lifetime-item.age,0,1)
		for particle in item.particles:
			particle.phase+=dt*randf_range(6,8) if item.id=="molotov" else dt*randf_range(10,14)
			var flick=0.7+sin(particle.phase)*0.3 if item.id=="molotov" else 0.6+absf(sin(particle.phase))*0.8
			particle.mesh.scale=Vector3.ONE*flick
			particle.mesh.material_override.set_shader_parameter("opacity",fade*(0.9 if item.id=="molotov" else 1.0))
		item.tick+=dt
		while item.tick>=1 and item.age<lifetime:
			item.tick-=1
			game_match.radial_damage(item.effect_point,item.config.radius,item.config.dps,item.owner,item.id,false)
		item.active=item.age<lifetime

func _set_emissive(root:Node,color:Color,part_name:String)->void:
	var part=Visuals.part(root,part_name)
	if part is MeshInstance3D and part.material_override is ShaderMaterial:
		var linear=color.srgb_to_linear()
		part.material_override.set_shader_parameter("emissive_color",Vector3(linear.r,linear.g,linear.b))

func _spawn_laser(item:Dictionary)->void:
	var geometry=ImmediateMesh.new()
	geometry.surface_begin(Mesh.PRIMITIVE_LINES)
	geometry.surface_add_vertex(Vector3(0,0.12,0))
	geometry.surface_add_vertex(Vector3(0,0.12,5))
	geometry.surface_end()
	var laser=MeshInstance3D.new()
	laser.mesh=geometry
	laser.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var linear=Color("ff2a2a").srgb_to_linear()
	laser.material_override=Materials.create_material({"color":[linear.r,linear.g,linear.b],"unlit":true,"transparent":true,"opacity":0.0},game_match.map.environment_data)
	item.node.add_child(laser)
	item.laser=laser
