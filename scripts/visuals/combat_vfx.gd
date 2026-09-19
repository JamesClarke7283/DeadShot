class_name CombatVFX
extends Node3D
## Combat effects rebuilt for the realistic renderer.
##
## Impacts kick up surface dust, muzzle flashes and explosions carry a real
## OmniLight3D so they light the scene instead of being painted-on sprites, and
## the persistent bullet-hole cap is retained from the original port.

const Materials=preload("res://scripts/world/map_material.gd")
const Map=preload("res://scripts/world/map_world.gd")
const QUALITY=preload("res://scripts/world/graphics_quality.gd")
const MAX_DECALS=96
static var _geometry:Dictionary={}
var environment:Dictionary={}
var transients:Array=[]
var decals:Array[MeshInstance3D]=[]
var rng:=RandomNumberGenerator.new()
## Dynamic light budget from the active tier. A muzzle flash or explosion beyond
## this many concurrent lights skips its light and keeps only the emissive quad,
## so a firefight cannot spiral the per-fragment light cost.
var max_lights:=8
var _live_lights:=0

func _ready()->void:
	name="CombatVFX"
	rng.randomize()
	geometry("sparkGeo")
	apply_quality(QUALITY.current())

## Light budget per tier: fewer concurrent dynamic lights on the cheaper levels.
func apply_quality(level:String="")->void:
	match QUALITY.normalize(level if not level.is_empty() else QUALITY.current()):
		"low":max_lights=2
		"medium":max_lights=4
		"ultra":max_lights=12
		_:max_lights=8

static func geometry(id:String)->ArrayMesh:
	if _geometry.is_empty():
		var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx.json"))
		for name in source:_geometry[name]=Map._make_mesh(source[name])
	return _geometry[id]

func _unlit(color:Color,energy:float,opacity:float,additive:bool=false)->ShaderMaterial:
	return Materials.create_unlit(color,energy,opacity,additive)

func _mesh(id:String,material:ShaderMaterial)->MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=geometry(id)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override=material
	add_child(node)
	return node

func _transient(node:Node3D,kind:String,life:float,radius:float=1.0)->void:
	transients.append({"node":node,"kind":kind,"age":0.0,"life":life,"radius":radius})

## Emissive props still glow at every tier; only the real light is budgeted.
func _dynamic_light(color:Color,energy:float,range_value:float,attenuation:float,at:Vector3)->void:
	if _live_lights>=max_lights:
		return
	_live_lights+=1
	var light:=OmniLight3D.new()
	light.light_color=color
	light.light_energy=energy
	light.omni_range=range_value
	light.omni_attenuation=attenuation
	light.shadow_enabled=false
	light.position=at
	add_child(light)
	_transient(light,"light",0.4 if energy>8.0 else 0.05)

func bullet_impact(point:Vector3,normal:Vector3,on_actor:bool)->void:
	# Sparks fly along the surface; the dust puff is thrown back at the shooter.
	var spark:=_mesh("sparkGeo",_unlit(Color("ffd9a0") if on_actor else Color("ffbe5c"),3.5,1.0,false))
	spark.position=point
	_transient(spark,"spark",0.1)
	var dust:=_mesh("sparkGeo",Materials.create_flat(Color("cdc3ad") if not on_actor else Color("a8443a"),0.55))
	dust.position=point
	dust.scale=Vector3.ONE*0.35
	_transient(dust,"dust",0.32)
	if not on_actor:bullet_hole(point,normal)

func bullet_hole(point:Vector3,normal:Vector3)->void:
	var hole:=_mesh("holeGeo",Materials.create_flat(Color("0a0805"),0.95))
	hole.position=point+normal*0.01
	hole.quaternion=Quaternion(Vector3.BACK,normal.normalized())
	hole.material_override.render_priority=1
	decals.append(hole)
	if decals.size()>MAX_DECALS:decals.pop_front().queue_free()

func tracer(from:Vector3,to:Vector3)->void:
	var direction=to-from
	var length=direction.length()
	if length<0.01:return
	# A hot core with a dimmer halo reads as a lit round rather than a flat bar.
	var node:=_mesh("tracerGeo",_unlit(Color("fff0b0"),6.0,0.85,true))
	node.scale=Vector3(1,length,1)
	node.position=from+direction*0.5
	node.quaternion=Quaternion(Vector3.UP,direction/length)
	_transient(node,"tracer",0.055)

func muzzle_flash(point:Vector3,direction:Vector3)->void:
	var node:=_mesh("flashGeo",_unlit(Color("ffd489"),8.0,1.0,true))
	node.position=point+direction*0.2
	# Three Object3D.lookAt turns local +Z toward the shooter.
	node.quaternion=Quaternion(Vector3.BACK,-direction.normalized())
	node.rotate_object_local(Vector3.BACK,rng.randf()*PI)
	_transient(node,"flash",0.045)
	# Real light so the flash illuminates nearby geometry and characters.
	_dynamic_light(Color("ffcf96"),3.4,7.0,1.6,point+direction*0.25)

func explosion(center:Vector3,radius:float)->void:
	var fireball:=_mesh("explosionGeo",_unlit(Color("ff9a44"),9.0,1.0,true))
	fireball.position=center
	_transient(fireball,"explosion",0.4,radius)
	var smoke:=_mesh("explosionGeo",Materials.create_flat(Color("6a665e"),0.8))
	smoke.position=center
	smoke.scale=Vector3.ONE*0.5
	_transient(smoke,"smoke",1.5,radius*0.9)
	_dynamic_light(Color("ffa855"),14.0,radius*5.0,1.4,center)

func tick(dt:float)->void:
	for index in range(transients.size()-1,-1,-1):
		var effect:Dictionary=transients[index]
		effect.age+=dt
		var fraction=minf(1,effect.age/effect.life)
		var node=effect.node
		match effect.kind:
			"spark":
				node.scale=Vector3.ONE*(0.5+fraction*1.5)
				node.material_override.set_shader_parameter("energy",3.5*(1-fraction))
				node.material_override.set_shader_parameter("opacity",1-fraction)
			"dust":
				node.scale=Vector3.ONE*(0.35+fraction*1.5)
				node.material_override.set_shader_parameter("opacity",0.55*(1-fraction))
			"tracer":node.material_override.set_shader_parameter("opacity",0.85*(1-fraction))
			"flash":
				node.scale=Vector3.ONE*(0.6+fraction*0.8)
				node.material_override.set_shader_parameter("energy",8.0*(1-fraction))
				node.material_override.set_shader_parameter("opacity",1-fraction)
			"explosion":
				node.scale=Vector3.ONE*effect.radius*(0.3+fraction*0.9)
				node.material_override.set_shader_parameter("energy",9.0*(1-fraction))
				node.material_override.set_shader_parameter("opacity",1-fraction)
			"smoke":
				node.scale=Vector3.ONE*effect.radius*(0.5+fraction*1.6)
				node.position.y+=0.6*dt
				node.material_override.set_shader_parameter("opacity",0.8*(1-fraction))
			"light":node.light_energy=(14.0 if effect.radius>1.0 else 3.4)*(1-fraction)
		if effect.age>=effect.life:
			if effect.kind=="light":_live_lights=maxi(0,_live_lights-1)
			node.queue_free()
			transients.remove_at(index)

func clear()->void:
	for node in decals:node.queue_free()
	decals.clear()
	for effect in transients:effect.node.queue_free()
	transients.clear()
	_live_lights=0
