class_name CombatVFX
extends Node3D
## Exact source VFX geometry, palette, timing, and persistent bullet-hole cap.
const Materials=preload("res://scripts/world/map_material.gd")
const Map=preload("res://scripts/world/map_world.gd")
const PointLight=preload("res://scripts/visuals/source_point_light.gd")
const MAX_DECALS=96
static var _geometry:Dictionary={}
var environment:Dictionary={}
var transients:Array=[]
var decals:Array[MeshInstance3D]=[]

func _ready()->void:
	name="CombatVFX"
	geometry("sparkGeo")

static func geometry(id:String)->ArrayMesh:
	if _geometry.is_empty():
		var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx.json"))
		for name in source:_geometry[name]=Map._make_mesh(source[name])
	return _geometry[id]

func _mesh(id:String,color:Color,opacity:float=1.0,depth_write:bool=true,additive:bool=false)->MeshInstance3D:
	var node=MeshInstance3D.new()
	node.mesh=geometry(id)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var linear=color.srgb_to_linear()
	node.material_override=Materials.create_material({"color":[linear.r,linear.g,linear.b],"unlit":true,"transparent":true,"opacity":opacity,"depthWrite":depth_write,"additive":additive},environment)
	add_child(node)
	return node

func _transient(node:Node3D,kind:String,life:float,radius:float=1.0)->void:
	transients.append({"node":node,"kind":kind,"age":0.0,"life":life,"radius":radius})

func bullet_impact(point:Vector3,normal:Vector3,on_actor:bool)->void:
	var spark=_mesh("sparkGeo",Color("ff4d4d") if on_actor else Color("ffd166"))
	spark.position=point
	_transient(spark,"spark",0.12)
	if not on_actor:bullet_hole(point,normal)

func bullet_hole(point:Vector3,normal:Vector3)->void:
	var hole=_mesh("holeGeo",Color("14110d"),0.9,false)
	hole.position=point+normal*0.01
	hole.quaternion=Quaternion(Vector3.BACK,normal.normalized())
	# Source polygonOffsetFactor -4 augments this explicit 1cm surface offset.
	hole.material_override.render_priority=1
	decals.append(hole)
	if decals.size()>MAX_DECALS:decals.pop_front().queue_free()

func tracer(from:Vector3,to:Vector3)->void:
	var direction=to-from
	var length=direction.length()
	if length<0.01:return
	var node=_mesh("tracerGeo",Color("fff1a8"),0.85)
	node.scale=Vector3(1,length,1)
	node.position=from+direction*0.5
	node.quaternion=Quaternion(Vector3.UP,direction/length)
	_transient(node,"tracer",0.06)

func muzzle_flash(point:Vector3,direction:Vector3)->void:
	var node=_mesh("flashGeo",Color("ffe08a"),1.0,false,true)
	node.position=point+direction*0.2
	# Three Object3D.lookAt turns local +Z toward the shooter.
	node.quaternion=Quaternion(Vector3.BACK,-direction.normalized())
	node.rotate_object_local(Vector3.BACK,randf()*PI)
	_transient(node,"flash",0.05)

func explosion(center:Vector3,radius:float)->void:
	var ball=_mesh("explosionGeo",Color("ff8a3c"),1.0,false)
	ball.position=center
	_transient(ball,"explosion",0.45,radius)
	var glow=PointLight.new()
	glow.position=center
	glow.light_color=Color("ffa040")
	glow.light_energy=8.0
	glow.omni_range=radius*4.0
	add_child(glow)
	_transient(glow,"light",0.35)

func tick(dt:float)->void:
	for index in range(transients.size()-1,-1,-1):
		var effect:Dictionary=transients[index]
		effect.age+=dt
		var fraction=minf(1,effect.age/effect.life)
		var node=effect.node
		match effect.kind:
			"spark":
				node.scale=Vector3.ONE*(0.5+fraction*1.5)
				node.material_override.set_shader_parameter("opacity",1-fraction)
			"tracer":node.material_override.set_shader_parameter("opacity",0.85*(1-fraction))
			"flash":
				node.scale=Vector3.ONE*(0.6+fraction*0.8)
				node.material_override.set_shader_parameter("opacity",1-fraction)
			"explosion":
				node.scale=Vector3.ONE*effect.radius*(0.3+fraction*0.9)
				node.material_override.set_shader_parameter("opacity",1-fraction)
			"light":node.light_energy=8.0*(1-fraction)
		if effect.age>=effect.life:
			node.queue_free()
			transients.remove_at(index)

func clear()->void:
	for node in decals:node.queue_free()
	decals.clear()
	for effect in transients:effect.node.queue_free()
	transients.clear()
