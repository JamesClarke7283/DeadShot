class_name CombatVFX
extends Node3D
## Combat effects rebuilt for the realistic renderer.
##
## Every effect is a **burst**: one transient entry owns a small group of child
## meshes, so a shot ages and frees one slot instead of one per particle. The
## children differ only in transform and in a per-instance `fade`, which lets a
## whole family share a single ShaderMaterial — `tick` therefore neither
## allocates nor mutates a resource while a firefight runs.
##
## Layering is what makes an effect read. A muzzle flash stacks a hot core, a
## crossed star bloom, the unburnt propellant cone and a smoke wisp; an impact
## stacks spark streaks, debris chips, a rising dust puff and an impact flare; a
## blast stacks a white-hot core, an orange shell with a hot inner layer, an ember
## layer that outlives both, a ground shockwave, a rising smoke column and thrown
## debris. The composite cools white through yellow to deep red and then darkens
## because the layers die in sequence, not because a particle changes colour
## mid-life.
##
## Cheap bands keep a single quad and one real light, and skip the smoke, debris,
## halo and shockwave entirely.

const Materials=preload("res://scripts/world/map_material.gd")
const Map=preload("res://scripts/world/map_world.gd")
const QUALITY=preload("res://scripts/world/graphics_quality.gd")
const MAX_DECALS=96
## A fresh decal fades in over this window while the scorch ring above it fades
## off, which is what makes the hole darken into the surface.
const DECAL_SETTLE=0.05
## The streak stretches over this long, which is what reads as travel: the round
## is already gone, so the effect has to show the path being cut.
const TRACER_STRETCH=0.022
static var _geometry:Dictionary={}
static var _primitives:Dictionary={}
## Role to material, built once for the process. Every particle of a kind shares
## its role's material and varies only through its instance `fade`.
static var _roles:Dictionary={}
var environment:Dictionary={}
var transients:Array=[]
var decals:Array[MeshInstance3D]=[]
var rng:=RandomNumberGenerator.new()
## Dynamic light budget from the active tier. A muzzle flash or explosion beyond
## this many concurrent lights skips its light and keeps only the emissive
## geometry, so a firefight cannot spiral the per-fragment light cost.
var max_lights:=8
var _live_lights:=0
## Decals still inside their settle window, so only those pay the per-frame fade.
var _settling:Array=[]
var _rich:=true
var _extra:=false
var _sparks:=4
var _shards:=2
var _chunks:=4
var _puffs:=3

func _ready()->void:
	name="CombatVFX"
	rng.randomize()
	geometry("sparkGeo")
	apply_quality(QUALITY.current())

## The tier decides how much a burst is worth. `viewmodel_detail` is the preset's
## existing "how much detail does an object deserve" knob and separates the cheap
## bands from the rest; the light budget then scales the particle counts, so a
## band allowed more real lights also carries more particles.
func apply_quality(level:String="")->void:
	var preset:Dictionary=QUALITY.preset(level)
	max_lights=int(preset.lights)
	_extra=max_lights>=12
	_rich=float(preset.viewmodel_detail)>=1.0 and max_lights>2
	_sparks=1
	_shards=0
	_chunks=0
	_puffs=0
	if _rich:
		_sparks=3
		_shards=2
		_chunks=4
		_puffs=3
		if max_lights>=8:_sparks=4
		if _extra:
			_sparks=5
			_shards=3
			_chunks=6
			_puffs=5

static func geometry(id:String)->ArrayMesh:
	if _geometry.is_empty():
		var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx.json"))
		for name in source:_geometry[name]=Map._make_mesh(source[name])
	return _geometry[id]

## Shapes the exported set does not carry, built once for the process: a unit quad
## so a flash arm or a spark streak is a plain non-uniform scale, a cone for the
## propellant flash, a flattened torus for the ground shockwave, and a wedge plus
## a box for debris.
static func _primitive(id:String)->Mesh:
	if _primitives.has(id):return _primitives[id]
	var mesh:Mesh
	match id:
		"quad":
			var plane:=PlaneMesh.new()
			plane.size=Vector2.ONE
			plane.orientation=PlaneMesh.FACE_Z
			mesh=plane
		"cone":
			var cone:=CylinderMesh.new()
			cone.top_radius=0.17
			cone.bottom_radius=0.0
			cone.height=0.5
			cone.radial_segments=12
			cone.rings=1
			mesh=cone
		"ring":
			var ring:=TorusMesh.new()
			ring.inner_radius=0.84
			ring.outer_radius=1.0
			ring.rings=28
			ring.ring_segments=6
			mesh=ring
		"chip":
			var chip:=PrismMesh.new()
			chip.size=Vector3(0.09,0.025,0.07)
			mesh=chip
		"flake":
			var flake:=BoxMesh.new()
			flake.size=Vector3(0.07,0.02,0.11)
			mesh=flake
	_primitives[id]=mesh
	return mesh

## One material per visual role, shared by every particle that uses it. `energy`
## above one pushes additive roles into the glow pass, which is what makes a
## tracer or a fireball read as a light source rather than as painted colour.
func _role(id:String)->ShaderMaterial:
	if _roles.has(id):return _roles[id]
	var material:ShaderMaterial
	var two_sided:=false
	match id:
		"core":material=Materials.create_unlit(Color("fff8ea"),18.0,1.0,true)
		"fireball_hot":material=Materials.create_unlit(Color("ffe9a8"),14.0,1.0,true)
		"fireball":material=Materials.create_unlit(Color("ff9a44"),9.0,1.0,true)
		"ember":material=Materials.create_unlit(Color("c03a1c"),4.5,1.0,true)
		"spark":material=Materials.create_unlit(Color("ffc061"),6.0,1.0,true)
		"shock":material=Materials.create_unlit(Color("d6d0c4"),2.6,0.85,true)
		"flare":
			material=Materials.create_unlit(Color("fff0d0"),10.0,1.0,true)
			two_sided=true
		"flash":
			material=Materials.create_unlit(Color("ffd489"),8.0,1.0,true)
			two_sided=true
		"propellant":material=Materials.create_unlit(Color("c2701f"),1.5,0.9,true)
		"tracer":material=Materials.create_unlit(Color("fff0b0"),6.0,0.9,true)
		"tracer_halo":material=Materials.create_unlit(Color("ffb64d"),1.8,0.5,true)
		"wisp":material=Materials.create_flat(Color("b9b3a6"),0.5)
		"dust":material=Materials.create_flat(Color("efe9dc"),0.42)
		"gore":material=Materials.create_flat(Color("8e2f26"),0.8)
		"mist":material=Materials.create_flat(Color("7a2118"),0.72)
		"debris":material=Materials.create_flat(Color("46403a"),0.95)
		"scorch":material=Materials.create_flat(Color("2e2a24"),0.85)
		"smoke":material=Materials.create_flat(Color("4a463f"),0.85)
		"hole":
			material=Materials.create_flat(Color("0a0805"),0.95)
			# The decal has to draw over the surface it sits on.
			material.render_priority=1
	_roles[id]=_fadeable(material,two_sided)
	return _roles[id]

## Gives a substrate material a per-instance opacity multiplier and, for the flat
## additive quads, two-sided drawing so a flash arm cannot vanish when seen from
## behind. The substrate leaves no alpha statement at all when it is asked for
## full opacity, so the write is injected rather than replaced.
func _fadeable(material:ShaderMaterial,two_sided:bool=false)->ShaderMaterial:
	var shader:=material.shader
	var code:=shader.code
	if two_sided:code=code.replace("cull_back","cull_disabled")
	code=code.replace("ALPHA = opacity;","")
	code=code.replace("uniform float opacity : hint_range(0.0, 1.0) = 1.0;","uniform float opacity : hint_range(0.0, 1.0) = 1.0;\ninstance uniform float fade = 1.0;")
	code=code.replace("void fragment() {","void fragment() {\n\tALPHA = opacity * fade;")
	shader.code=code
	material.shader=shader
	return material

## Basis whose local +Z points back along the shot, so a quad reads face-on from
## the shooter, and whose local +Y stays near world up, so a wisp still drifts
## upward in local space.
static func _shot_basis(forward:Vector3)->Basis:
	var back:=-forward
	var up:=Vector3.UP
	if absf(back.dot(up))>0.99:up=Vector3.FORWARD
	var right:=up.cross(back).normalized()
	return Basis(right,back.cross(right).normalized(),back)

## Aligns a streak's long axis with its own velocity and rolls it about that axis.
static func _streak_basis(direction:Vector3,roll:float)->Basis:
	var axis:=direction.normalized()
	var reference:=Vector3.UP if absf(axis.dot(Vector3.UP))<0.95 else Vector3.RIGHT
	var side:=reference.cross(axis).normalized()
	return Basis(side,axis,side.cross(axis)).rotated(axis,roll)

## Assigning `basis` replaces rotation *and* scale, so a streak re-applies the
## size it was created with.
static func _aim(node:MeshInstance3D,basis:Basis,size:Vector3)->void:
	node.basis=basis
	node.scale=size

func _mesh(id:String,material:ShaderMaterial)->MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=geometry(id)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override=material
	add_child(node)
	return node

func _transient(node:Node3D,kind:String,life:float,radius:float=1.0)->Dictionary:
	var effect:Dictionary={"node":node,"kind":kind,"age":0.0,"life":life,"radius":radius,"parts":[],"data":{}}
	transients.append(effect)
	return effect

## Starts a burst: one empty parent that becomes one transient entry, however many
## particles the shot turns out to need.
func _burst(kind:String,life:float,radius:float=1.0)->Dictionary:
	var group:=Node3D.new()
	add_child(group)
	return _transient(group,kind,life,radius)

## One particle inside a burst. `drift`/`gravity` move it, `grow` is the scale it
## reaches at the end of its own `life`, `spin` its roll in radians per second,
## `hold` the fraction of life before the fade starts and `ramp` how long it takes
## to fade in. Every particle retires itself by hiding, so a group can outlive its
## shortest child without paying for an invisible draw.
func _part(burst:Dictionary,mesh:Mesh,material:ShaderMaterial,at:Vector3,size:Vector3,grow:Vector3,drift:Vector3,spin:Vector3,life:float,fade:=1.0,hold:=0.0,gravity:=0.0,ramp:=0.0,billboard:=false)->MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position=at
	node.scale=size
	burst.node.add_child(node)
	# The shader default is one, so a particle that is drawn before its first tick
	# would show at full opacity — a ramp-in puff would land as a solid grey disc.
	# Seeding the instance fade here makes frame zero match the intended envelope.
	node.set_instance_shader_parameter("fade",0.0 if ramp>0.0 else fade)
	burst.parts.append({"node":node,"size":size,"grow":grow,"drift":drift,"spin":spin,"life":life,"fade":fade,"hold":hold,"gravity":gravity,"ramp":ramp,"billboard":billboard,"t":0.0,"dead":false})
	return node

## Emissive props still glow at every tier; only the real light is budgeted. The
## peak energy rides on the effect so `tick` can dim it along its own curve.
func _dynamic_light(color:Color,energy:float,range_value:float,attenuation:float,at:Vector3,life:=0.4,pulse:=false)->Dictionary:
	if _live_lights>=max_lights:return {}
	_live_lights+=1
	var light:=OmniLight3D.new()
	light.light_color=color
	light.light_energy=energy
	light.omni_range=range_value
	light.omni_attenuation=attenuation
	light.shadow_enabled=false
	light.position=at
	add_child(light)
	var effect:=_transient(light,"light",life)
	effect.data.peak=energy
	effect.data.pulse=pulse
	return effect

func bullet_impact(point:Vector3,normal:Vector3,on_actor:bool)->void:
	# The burst's local +Y is the surface normal, so the spark cone, the dust rise
	# and the flare's lie all describe the surface rather than a world axis.
	var surface:=normal.normalized()
	if surface.length()<0.5:surface=Vector3.UP
	var quad:=_primitive("quad")
	var burst:=_burst("burst",0.6 if on_actor else 0.9)
	var root:Node3D=burst.node
	# The burst is lifted a few centimetres off the surface: the sand family
	# displaces up to three centimetres with parallax, so particles spawned exactly
	# on the surface are swallowed by the ground they were kicked off.
	root.position=point+surface*0.03
	root.quaternion=Quaternion(Vector3.UP,surface)
	# The flare lies in the surface plane: a quarter turn about X stands the quad
	# up so its normal runs along the surface normal and it reads face-on to
	# whoever the surface is facing. Its spin then rolls it about that normal.
	var flare:=_part(burst,quad,_role("flare"),Vector3(0,0.05,0),Vector3.ONE*0.45,Vector3.ONE*0.8,Vector3.ZERO,Vector3(0,rng.randf_range(-4.0,4.0),0),0.045)
	flare.rotation.x=-PI/2
	if on_actor:
		# Flesh throws no sparks and no chips: the red mist is the read. The cheap
		# bands keep one puff, and only the flare survives alongside it.
		for _i in range(_shards if _rich else 1):
			var angle:=rng.randf()*TAU
			_part(burst,geometry("smokeGeo"),_role("mist"),Vector3(0,0.12,0),Vector3.ONE*(0.07+rng.randf()*0.05),Vector3.ONE*(0.22+rng.randf()*0.2),Vector3(cos(angle),1.0,sin(angle))*rng.randf_range(0.3,1.1),Vector3.ZERO,0.4+rng.randf()*0.15,0.85,0.0,-1.6,0.05)
		if _rich:
			_part(burst,geometry("smokeGeo"),_role("gore"),Vector3(0,0.1,0),Vector3.ONE*0.08,Vector3.ONE*0.34,Vector3.UP*0.5,Vector3.ZERO,0.45,1.0,0.0,-1.2,0.1)
		return
	if _rich:
		# Sparks fly in a cone around the normal and fall back into the surface.
		for _i in range(_sparks):
			var angle:=rng.randf()*TAU
			var velocity:=Vector3(cos(angle),0.0,sin(angle))*rng.randf_range(0.8,3.4)+Vector3.UP*rng.randf_range(3.6,9.2)
			var size:=Vector3(0.055,0.3+rng.randf()*0.12,1.0)
			var streak:=_part(burst,quad,_role("spark"),Vector3(0,0.06,0),size,Vector3(0.055,0.85,1.0),velocity,Vector3.ZERO,0.13+rng.randf()*0.06,1.0,0.0,7.0)
			_aim(streak,_streak_basis(velocity,rng.randf()*PI),size)
		for index in range(_shards):
			var angle:=rng.randf()*TAU
			var velocity:=Vector3(cos(angle),0.0,sin(angle))*rng.randf_range(1.4,3.6)+Vector3.UP*rng.randf_range(2.2,4.6)
			_part(burst,_primitive("chip") if index%2==0 else _primitive("flake"),_role("debris"),Vector3(0,0.07,0),Vector3.ONE*0.55,Vector3.ONE*0.7,velocity,Vector3(rng.randf_range(-7.0,7.0),rng.randf_range(-7.0,7.0),rng.randf_range(-7.0,7.0)),0.6+rng.randf()*0.25,1.0,0.75,9.5)
		for _i in range(2 if _extra else 1):
			var angle:=rng.randf()*TAU
			_part(burst,geometry("smokeGeo"),_role("dust"),Vector3(0,0.08,0),Vector3.ONE*0.07,Vector3.ONE*rng.randf_range(0.3,0.46),Vector3(cos(angle),0.7,sin(angle))*rng.randf_range(0.3,0.9),Vector3.ZERO,0.34+rng.randf()*0.12,1.0,0.0,-1.4,0.12)
	bullet_hole(point,surface)

func bullet_hole(point:Vector3,normal:Vector3)->void:
	var hole:=_mesh("holeGeo",_role("hole"))
	hole.position=point+normal*0.01
	hole.quaternion=Quaternion(Vector3.BACK,normal.normalized())
	hole.set_instance_shader_parameter("fade",0.25)
	decals.append(hole)
	_settling.append({"node":hole,"age":0.0})
	if decals.size()>MAX_DECALS:decals.pop_front().queue_free()
	if not _rich:return
	# The scorch ring fades off while the hole itself fades in, which is what
	# reads as the decal darkening over its first 50 ms. It is a flat disc rather
	# than a quad, so the scorch has no visible corners on the surface.
	var scorch:=_burst("burst",DECAL_SETTLE)
	var root:Node3D=scorch.node
	root.position=point+normal*0.006
	root.quaternion=Quaternion(Vector3.BACK,normal.normalized())
	_part(scorch,geometry("holeGeo"),_role("scorch"),Vector3.ZERO,Vector3.ONE*0.35,Vector3.ONE*0.6,Vector3.ZERO,Vector3.ZERO,DECAL_SETTLE,0.9)

func tracer(from:Vector3,to:Vector3)->void:
	var direction:=to-from
	var length:=direction.length()
	if length<0.01:return
	# A hot core inside a dimmer wide halo reads as a lit round rather than as a
	# flat bar, and the pair is spawned behind the muzzle so the stretch in `tick`
	# has somewhere to travel from.
	var unit:=direction/length
	var burst:=_burst("tracer",0.055)
	burst.data.origin=from
	burst.data.direction=unit
	burst.data.length=length
	var root:Node3D=burst.node
	root.position=from-unit*0.5
	root.quaternion=Quaternion(Vector3.UP,unit)
	# The tracer geometry already runs one metre along local +Y, so a particle's
	# scale is its width in x/z and a length multiplier in y.
	_part(burst,geometry("tracerGeo"),_role("tracer"),Vector3.ZERO,Vector3(2.2,1.0,2.2),Vector3(2.2,1.0,2.2),Vector3.ZERO,Vector3.ZERO,0.055)
	if _rich:_part(burst,geometry("tracerGeo"),_role("tracer_halo"),Vector3.ZERO,Vector3(5.5,1.0,5.5),Vector3(5.5,1.0,5.5),Vector3.ZERO,Vector3.ZERO,0.055)

func muzzle_flash(point:Vector3,direction:Vector3)->void:
	var forward:=direction.normalized()
	if forward.length()<0.5:forward=Vector3.FORWARD
	var burst:=_burst("burst",0.24 if _rich else 0.07)
	var root:Node3D=burst.node
	root.position=point+forward*0.12
	root.basis=_shot_basis(forward)
	if _rich:
		# A hot point at the muzzle, two crossed elongated quads at independent
		# rolls, the unburnt propellant cone opening forward and a smoke wisp.
		_part(burst,geometry("sparkGeo"),_role("core"),Vector3(0,0,0.03),Vector3.ONE*0.55,Vector3.ONE*0.85,Vector3.ZERO,Vector3.ZERO,0.05)
		var quad:=_primitive("quad")
		for _i in range(2):
			var arm:=_part(burst,quad,_role("flash"),Vector3(0,0,0.06),Vector3(0.5+rng.randf()*0.2,0.11+rng.randf()*0.05,1.0),Vector3(0.68,0.17,1.0),Vector3.ZERO,Vector3.BACK*rng.randf_range(-3.0,3.0),0.06)
			arm.rotation.z=rng.randf()*PI
		# The cone's own axis is local +Y, so a quarter turn about X stands it on
		# the barrel with its apex at the muzzle.
		var flame:=_part(burst,_primitive("cone"),_role("propellant"),Vector3(0,0,0.3),Vector3.ONE,Vector3(1.0,1.35,1.0),Vector3(0,0,0.5),Vector3.ZERO,0.075,0.95,0.0,0.0,0.01)
		flame.rotation.x=-PI/2
		_part(burst,geometry("smokeGeo"),_role("wisp"),Vector3(0,0.02,0.2),Vector3.ONE*0.1,Vector3.ONE*0.36,Vector3(0,0.55,0.4),Vector3.ZERO,0.22,1.0,0.0,-0.7,0.05)
	else:
		_part(burst,_primitive("quad"),_role("flash"),Vector3(0,0,0.06),Vector3.ONE*0.7,Vector3.ONE*0.9,Vector3.ZERO,Vector3.BACK*rng.randf_range(-3.0,3.0),0.07)
	# The real light double-peaks: the propellant burn, a dip, then the muzzle
	# blast, so the flash is not a single blip.
	_dynamic_light(Color("ffcf96"),3.4,7.0,1.6,point+forward*0.25,0.16,true)

func explosion(center:Vector3,radius:float)->void:
	var burst:=_burst("burst",2.2 if _rich else 0.45,radius)
	var root:Node3D=burst.node
	root.position=center
	var sphere:=geometry("explosionGeo")
	if not _rich:
		# The cheap band keeps the original single quad and one real light.
		_part(burst,_primitive("quad"),_role("fireball"),Vector3.ZERO,Vector3.ONE*(radius*0.3),Vector3.ONE*(radius*0.95),Vector3.UP*(radius*0.35),Vector3.ZERO,0.45,1.0,0.0,0.0,0.0,true)
		_dynamic_light(Color("ffa855"),26.0,radius*5.0,1.4,center,0.5)
		return
	# White-hot core, then the orange shell, its hot inner layer and the ember
	# layer that outlives both: the stack cools in sequence.
	_part(burst,sphere,_role("core"),Vector3.ZERO,Vector3.ONE*(radius*0.22),Vector3.ONE*(radius*0.62),Vector3.ZERO,Vector3.ZERO,0.1)
	_part(burst,sphere,_role("fireball"),Vector3.ZERO,Vector3.ONE*(radius*0.3),Vector3.ONE*(radius*0.95),Vector3.UP*(radius*0.35),Vector3.ZERO,0.45)
	_part(burst,sphere,_role("fireball_hot"),Vector3.ZERO,Vector3.ONE*(radius*0.2),Vector3.ONE*(radius*0.6),Vector3.UP*(radius*0.3),Vector3.ZERO,0.22)
	_part(burst,sphere,_role("ember"),Vector3.ZERO,Vector3.ONE*(radius*0.5),Vector3.ONE*(radius*1.15),Vector3.UP*(radius*0.45),Vector3.ZERO,0.85,0.9)
	# A disc shockwave on the plane the blast stands on. The ring is born flat on
	# the torus axis, so only its radius is animated.
	_part(burst,_primitive("ring"),_role("shock"),Vector3(0,-minf(center.y,0.5),0),Vector3(radius*0.25,radius*0.06,radius*0.25),Vector3(radius*1.6,radius*0.08,radius*1.6),Vector3(0,0.15,0),Vector3.ZERO,0.32,1.0,0.0,0.0,0.01)
	# The smoke column keeps expanding and rising after the fireball is gone.
	# The puffs are staggered up the blast axis rather than piled at one height,
	# which is what makes the mass read as a column instead of as one grey ball.
	for index in range(_puffs):
		var angle:=rng.randf()*TAU
		var height:=radius*(0.1+float(index)*0.13+rng.randf()*0.05)
		_part(burst,geometry("smokeGeo"),_role("smoke"),Vector3(cos(angle)*radius*0.18,height,sin(angle)*radius*0.18),Vector3.ONE*(radius*0.3),Vector3.ONE*(radius*rng.randf_range(0.95,1.5)),Vector3(cos(angle)*0.4,rng.randf_range(1.0,2.2),sin(angle)*0.4),Vector3.ZERO,1.5+rng.randf()*0.6,0.62,0.0,-0.35,0.2)
	for index in range(_chunks):
		var angle:=rng.randf()*TAU
		_part(burst,_primitive("chip") if index%2==0 else _primitive("flake"),_role("debris"),Vector3(cos(angle)*radius*0.2,radius*0.15,sin(angle)*radius*0.2),Vector3.ONE*0.6,Vector3.ONE*0.75,Vector3(cos(angle),1.2,sin(angle))*rng.randf_range(radius*1.6,radius*3.4),Vector3(rng.randf_range(-8.0,8.0),rng.randf_range(-8.0,8.0),rng.randf_range(-8.0,8.0)),0.8+rng.randf()*0.55,1.0,0.8,9.5)
	_dynamic_light(Color("ffa855"),26.0,radius*5.0,1.4,center,0.5)

## Ages one particle. Everything it touches is a scalar on the record plus the
## node's own transform: no allocation, no material mutation.
func _age_part(part:Dictionary,dt:float)->void:
	if part.dead:return
	var node:MeshInstance3D=part.node
	if not is_instance_valid(node):
		part.dead=true
		return
	part.t+=dt
	if part.t>=part.life:
		part.dead=true
		node.visible=false
		return
	var fraction:float=part.t/part.life
	var eased:=1.0-(1.0-fraction)*(1.0-fraction)
	var drift:Vector3=part.drift
	if part.gravity!=0.0:
		drift.y-=float(part.gravity)*dt
		part.drift=drift
	var spin:Vector3=part.spin
	if spin!=Vector3.ZERO:node.rotation+=spin*dt
	node.position+=drift*dt
	var size:Vector3=part.size
	var grow:Vector3=part.grow
	node.scale=size.lerp(grow,eased)
	if part.billboard:
		# A flat quad only reads from the front, so a billboarded particle aims
		# its own +Z at the camera instead of spinning with the burst. Its parent
		# is unrotated, which keeps this exact.
		var camera:=get_viewport().get_camera_3d()
		if camera:
			var origin:=node.global_position
			var to_camera:=camera.global_position-origin
			if to_camera.length_squared()>0.0001:
				var forward:=to_camera.normalized()
				var up:=Vector3.UP if absf(forward.dot(Vector3.UP))<0.99 else Vector3.FORWARD
				var right:=up.cross(forward).normalized()
				node.global_basis=Basis(right,forward.cross(right).normalized(),forward)
				node.scale=size.lerp(grow,eased)
	var fade:float=part.fade
	if part.ramp>0.0:fade*=minf(1.0,part.t/float(part.ramp))
	if fraction>part.hold:fade*=1.0-(fraction-float(part.hold))/maxf(0.05,1.0-float(part.hold))
	node.set_instance_shader_parameter("fade",fade)

## One light per effect, dimmed by its own curve: the muzzle light double-peaks
## and a blast light falls away over the fireball's life.
func _age_light(effect:Dictionary,dt:float)->void:
	var light:OmniLight3D=effect.node
	var fraction:=minf(1.0,effect.age/effect.life)
	var curve:float
	if bool(effect.data.get("pulse",false)):
		if fraction<0.08:curve=1.0
		elif fraction<0.2:curve=lerpf(1.0,0.32,(fraction-0.08)/0.12)
		elif fraction<0.38:curve=lerpf(0.32,0.6,(fraction-0.2)/0.18)
		else:curve=lerpf(0.6,0.0,(fraction-0.38)/0.62)
	else:curve=(1.0-fraction)*(1.0-fraction)
	light.light_energy=float(effect.data.get("peak",light.light_energy))*curve

## The round is already gone, so the streak has to show the path being cut: the
## head runs from the muzzle to the impact while the tail stays behind the muzzle,
## so the bar stretches along the way. The core and the halo share the parent's
## axis and differ only in width.
func _age_tracer(effect:Dictionary,dt:float)->void:
	var data:Dictionary=effect.data
	var origin:Vector3=data.origin
	var direction:Vector3=data.direction
	var stretch:=minf(1.0,effect.age/TRACER_STRETCH)
	var head:=origin.lerp(origin+direction*float(data.length),stretch)
	var tail:=origin-direction*0.5
	var length:=tail.distance_to(head)
	effect.node.position=tail
	var fade:=1.0-minf(1.0,effect.age/effect.life)
	for part in effect.parts:
		var child:MeshInstance3D=part.node
		var size:Vector3=part.size
		child.position.y=length*0.5
		child.scale=Vector3(size.x,length,size.z)
		child.set_instance_shader_parameter("fade",fade)

func tick(dt:float)->void:
	# A fresh decal darkens as it settles: its opacity climbs while the scorch ring
	# above it fades off. Reverse `while` loops avoid `range()` building an Array
	# on every frame.
	var index:=_settling.size()-1
	while index>=0:
		var entry:Dictionary=_settling[index]
		var hole:MeshInstance3D=entry.node
		if not is_instance_valid(hole) or hole.is_queued_for_deletion():
			_settling.remove_at(index)
			index-=1
			continue
		entry.age=float(entry.age)+dt
		hole.set_instance_shader_parameter("fade",lerpf(0.25,1.0,minf(1.0,entry.age/DECAL_SETTLE)))
		if entry.age>=DECAL_SETTLE:_settling.remove_at(index)
		index-=1
	index=transients.size()-1
	while index>=0:
		var effect:Dictionary=transients[index]
		effect.age+=dt
		match effect.kind:
			"light":_age_light(effect,dt)
			"tracer":_age_tracer(effect,dt)
			_:
				for part in effect.parts:_age_part(part,dt)
		if effect.age>=effect.life:
			if effect.kind=="light":_live_lights=maxi(0,_live_lights-1)
			effect.node.queue_free()
			transients.remove_at(index)
		index-=1

func clear()->void:
	for node in decals:node.queue_free()
	decals.clear()
	for effect in transients:effect.node.queue_free()
	transients.clear()
	_settling.clear()
	_live_lights=0
