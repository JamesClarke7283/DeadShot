extends Node3D
## Native projectile equipment with original fuses, bounce, blast/DoT balance.
##
## Grenades fly and land like objects instead of points: quadratic air drag bends
## the arc off the ideal parabola, a tracked spin axis tumbles the body in flight
## and loses energy on contact, and every impact resolves against the surface
## family it landed on, so sand swallows a bounce that concrete returns and a
## resting body rolls to a stop on friction rather than a timer.
##
## Flashbangs resolve visibility geometrically: rays from the blast to the
## target's head, torso and feet give an exposure fraction, the view direction
## decides how much of it reaches the eye, and the enclosure of the blast decides
## how much comes back off the walls.
const Visuals=preload("res://scripts/visuals/visual_factory.gd")
const VFX=preload("res://scripts/visuals/combat_vfx.gd")
const Materials=preload("res://scripts/world/map_material.gd")
const CHARGE_SECONDS=1.25
const CHARGED_MIN_SPEED=18.0
const CHARGED_MAX_SPEED=52.0
## Quadratic drag in speed units per metre flown: enough to bend the arc off the
## ideal parabola without eating the charged throw's range.
const AIR_DRAG=0.0006
## Closing speed below which an impact stops bouncing and starts rolling.
const MIN_BOUNCE_SPEED=1.2
## Fraction of the tangential speed a surface impulse removes per bounce.
const IMPACT_FRICTION=0.35
## Rolling grip per second, and the speed at which a roll counts as stopped.
const ROLL_GRIP=1.2
const ROLL_STOP=0.12
## Spin kept through a bounce, and the cap on a rolling body's tumble rate: a
## true 6 cm roll strobes at frame rate, so the look is capped below it.
const SPIN_DECAY=0.45
const SPIN_ROLL_MAX=16.0
const GRENADE_RADIUS=0.06
## Impact normals this steep are floors and prop tops; flatter ones are walls.
const FLOOR_NORMAL=0.55
## Restitution and grip per surface family. The item's own `bounce` still scales
## the result, so a frag leaves the ground harder than a smoke canister.
const FLIGHT_SURFACES={
	"ground":{"bounce":0.72,"friction":0.55},
	"concrete":{"bounce":1.0,"friction":0.5},
	"asphalt":{"bounce":0.95,"friction":0.5},
	"sand":{"bounce":0.42,"friction":1.15},
	"dirt":{"bounce":0.55,"friction":1.0},
	"grass":{"bounce":0.5,"friction":1.05},
	"wood":{"bounce":0.85,"friction":0.65},
	"metal":{"bounce":1.1,"friction":0.35},
	"water":{"bounce":0.12,"friction":1.6},
	"wall":{"bounce":1.05,"friction":0.4},
}
## Surface-library profiles a floor can resolve to, folded onto those families.
## Anything the profiler does not name (its own "generic") lands on ground.
const FLOOR_FAMILY={"sand":"sand","dirt":"dirt","grass":"grass","foliage":"grass","concrete":"concrete","asphalt":"asphalt","stone":"concrete","plaster":"concrete","tile":"concrete","wood":"wood","fabric":"wood","metal":"metal","painted_metal":"metal","vehicle":"metal","rust":"metal","glazed":"metal","glass":"metal","generic":"ground"}
## Loose ground reacts to a landing instead of bouncing off it clean.
const REACTIVE_FLOORS={"sand":Color("cdbb96"),"dirt":Color("8a7458"),"grass":Color("6f7a52"),"water":Color("9fb3c4")}
## Pooled transient quads behind the whole system: the fuze trail and the impact
## puffs. Ring allocated, so a frame ages live entries and never builds a node.
const TRAIL_POOL=14
const TRAIL_INTERVAL=0.05
const TRAIL_LIFE=0.5
const TRAIL_OPACITY=0.5
const PUFF_COOLDOWN=0.15
## Fuze cadence: ticks per second at release, and how much faster it gets by the
## time the fuse runs out.
const FUZE_RATE_MIN=5.0
const FUZE_RATE_SPAN=17.0
## Indicator colours are constants, not literals parsed out of a string every
## frame: the fuze blink and the placed-charge LEDs all run on the item tick.
const FUZE_LIT=Color("ff3300")
const FUZE_DARK=Color("220800")
const SEMTEX_DARK=Color("224400")
const C4_LIT=Color("660000")
const C4_DARK=Color("220000")
const SPARK_TRAIL=Color("ffb066")
const SMOKE_TRAIL=Color("9a958c")
const SPLASH=Color("e8f2ff")
## Offsets from a target's body centre the flash has to reach before it counts as
## fully exposed; the head sample uses the eye position directly.
const FLASH_BODY_SAMPLES=[Vector3(0.28,0.15,0),Vector3(-0.28,0.15,0),Vector3(0.22,-0.5,0),Vector3(-0.22,-0.5,0)]
const FLASH_RADIUS=18.0
const STUN_RADIUS=12.0
## Fraction of a visible detonation's flash that survives even at the range
## boundary: the wash you get from looking away or standing at the edge.
const FLASH_RESIDUAL=0.5
const STUN_RESIDUAL=0.3
const FLASH_DURATION=3.2
const STUN_DURATION=2.5
const STUN_FLOOR=0.3
## A blast seen side on (dot 0) delivers this much of the full-facing flash, and
## a blast behind the target keeps the same floor rather than nothing.
const FACING_FLOOR=0.25
const ENCLOSURE_RANGE=6.0
const ENCLOSURE_RAYS=[Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
const ENCLOSURE_INTENSITY=1.35
const ENCLOSURE_DURATION=1.6
## Concussive punch from your own blast: the pressure wave reaches the shooter as
## a screen-edge vignette. Team modes give no self-damage, so this is the only
## feedback a shooter gets from a lethal that lands too close.
const CONCUSS_INTENSITY=0.35
const CONCUSS_DURATION=0.45
const CONFIG={
	"frag":{"speed":22.0,"gravity":20.0,"bounce":0.4,"fuse":3.0,"radius":6.0,"damage":120.0,"spin":11.0},
	"semtex":{"speed":24.0,"gravity":18.0,"bounce":0.0,"fuse":0.0,"radius":5.5,"damage":130.0,"spin":9.0},
	"flashbang":{"speed":22.0,"gravity":20.0,"bounce":0.45,"fuse":1.6,"spin":10.0},
	"stun":{"speed":22.0,"gravity":20.0,"bounce":0.45,"fuse":1.6,"spin":10.0},
	"snapshot":{"speed":22.0,"gravity":20.0,"bounce":0.4,"fuse":1.4,"spin":9.0},
	"smoke":{"speed":20.0,"gravity":20.0,"bounce":0.3,"fuse":1.4,"spin":8.0},
	"knife":{"speed":40.0,"gravity":3.0,"bounce":0.0,"fuse":0.0,"spin":0.0},
	"c4":{"speed":18.0,"gravity":20.0,"bounce":0.15,"fuse":0.0,"radius":7.0,"damage":140.0,"spin":6.0},
	"molotov":{"speed":22.0,"gravity":20.0,"bounce":0.0,"fuse":0.0,"radius":3.0,"duration":6.0,"dps":25.0,"spin":8.0},
	"thermite":{"speed":22.0,"gravity":20.0,"bounce":0.0,"fuse":0.0,"radius":2.5,"duration":5.0,"dps":40.0,"spin":7.0},
	"claymore":{"speed":14.0,"gravity":20.0,"bounce":0.1,"fuse":0.0,"radius":5.0,"damage":150.0,"spin":5.0},
}
var game_match
var items:Array=[]
var last_c4_throw:float=-1.0
var _trail:Array=[]
var _trail_cursor:=0
var _trail_material:ShaderMaterial
var _floor_family:="ground"
var _floor_map:=""

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
	# Tumble axis across the throw, so the body turns end over end along its own
	# travel rather than about some axis of its own choosing.
	var travel=Vector3(velocity.x,0,velocity.z)
	var spin_axis:Vector3=travel.normalized().cross(Vector3.UP) if travel.length_squared()>0.000001 else Vector3.RIGHT
	var fuze_light:OmniLight3D=null
	if float(settings.fuse)>0.0:
		# The fuze is a real emitter in flight: a small light that pulses with the
		# body glow, so a thrown grenade reads in the dark instead of only in the
		# glow pass.
		fuze_light=OmniLight3D.new()
		fuze_light.light_color=Color("ff7a2a")
		fuze_light.light_energy=0.0
		fuze_light.omni_range=1.6
		fuze_light.omni_attenuation=2.0
		fuze_light.shadow_enabled=false
		visual.add_child(fuze_light)
	items.append({"id":id,"config":settings,"owner":actor,"node":visual,"velocity":velocity,"charged":charged,"facing":facing,"fuse":settings.fuse,"active":true,"stuck":false,"detonated":false,"age":0.0,"arm":1.0,"rest":6.0,"tick":0.0,"particles":[],"blink":0.0,"laser":null,"effect_point":visual.position,"body":_body_mesh(visual),"fuze_light":fuze_light,"spin_axis":spin_axis,"spin_rate":float(settings.get("spin",0.0)),"spin_angle":0.0,"spin_base":visual.quaternion,"grounded":false,"trail_phase":0.0,"trail_index":0,"puff":0.0,"fuze_rate":0.0})

func tick(dt:float)->void:
	_tick_trail(dt)
	for index in range(items.size()-1,-1,-1):
		var item:Dictionary=items[index]
		if item.active:
			_tick_item(item,dt)
		if not item.active:
			item.node.queue_free()
			items.remove_at(index)

func _tick_item(item:Dictionary,dt:float)->void:
	if item.detonated:
		# Only the lingering-area items age after they detonate; a blast item is
		# already inactive by then and has no area to tick.
		if item.config.has("duration"):_tick_area(item,dt)
		return
	if float(item.puff)>0.0:item.puff=float(item.puff)-dt
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
		_tick_flight(item,dt)
	if item.fuse>0:
		item.fuse-=dt
		# A stuck body has its own indicator (the semtex charge, the C4 LED), so
		# the fuze cue belongs to the items still in the air.
		if not item.stuck:_tick_fuze(item,dt)
		if item.fuse<=0:_detonate(item)
	if item.stuck and not item.detonated and item.active:
		item.blink+=dt
		if item.id=="semtex":
			var rate=6.0+(1.5-maxf(0,item.fuse))*6.0
			_set_emissive(item.node,FUZE_LIT if sin(item.blink*rate)>0 else SEMTEX_DARK,"equipment_semtex")
		elif item.id=="c4":
			_set_emissive(item.node,C4_LIT if sin(item.blink*3.0)>0 else C4_DARK,"part_3")

## Ballistic step: gravity, drag, one swept ray for the whole move. The ray is
## swept over the entire step at every speed so a fast throw cannot tunnel small
## cover, and a charged throw also clears its own thrower inside the sweep.
func _tick_flight(item:Dictionary,dt:float)->void:
	var velocity:Vector3=item.velocity
	velocity.y-=float(item.config.gravity)*dt
	# Drag is quadratic: the arc sheds speed to the air every step, so it never
	# draws the ideal parabola a pure gravity term would.
	velocity*=maxf(0.0,1.0-AIR_DRAG*velocity.length()*dt)
	item.velocity=velocity
	var previous:Vector3=item.node.position
	var step:Vector3=velocity*dt
	item.node.position+=step
	if step.length()>0.00001:
		var hit:Dictionary
		if item.get("charged",false):
			hit=game_match.raycast(previous,step.normalized(),step.length(),item.owner,true,false)
		else:
			hit=game_match.raycast(previous,step.normalized(),step.length(),null,true)
		if not hit.is_empty():
			item.node.position=hit.position
			_impact(item,hit,dt)
	# A thrown knife points along its travel rather than tumbling: it is the one
	# body whose flight orientation is not a spin.
	if item.id=="knife" and item.velocity.length_squared()>0.0001:
		item.node.quaternion=Quaternion(Vector3.BACK,item.velocity.normalized())
	_tick_spin(item,dt)

## Tumbles the body about its tracked axis. The orientation is rebuilt from the
## throw basis every frame, so the accumulated angle cannot drift and the step
## allocates nothing.
func _tick_spin(item:Dictionary,dt:float)->void:
	if float(item.spin_rate)==0.0:return
	item.spin_angle=fposmod(float(item.spin_angle)+float(item.spin_rate)*dt,TAU)
	item.node.quaternion=item.spin_base*Quaternion(item.spin_axis,float(item.spin_angle))

func _impact(item:Dictionary,hit:Dictionary,dt:float=0.0)->void:
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
		_:_bounce(item,hit,dt)

## Surface response. The map carries no surface tags, so the family is inferred
## from what the ray met and where: a near-vertical normal is a wall or a prop
## side, a hit under the terrain surface is submerged, and the floor's family
## comes from the map's own identity run through the shared surface profiler.
func _bounce(item:Dictionary,hit:Dictionary,dt:float)->void:
	var normal:Vector3=hit.normal.normalized()
	var family:=_impact_family(hit.get("position",item.node.position),normal)
	var surface:Dictionary=FLIGHT_SURFACES.get(family,FLIGHT_SURFACES.ground)
	var velocity:Vector3=item.velocity
	var closing:float=-velocity.dot(normal)
	# Split the inbound velocity into the part crossing the surface and the part
	# travelling across it: only the crossing part is what a bounce returns.
	var tangent:Vector3=velocity+normal*closing
	var bounced:=closing>MIN_BOUNCE_SPEED
	var returned:=closing*float(item.config.bounce)*float(surface.bounce) if bounced else 0.0
	var floor_hit:=absf(normal.y)>=FLOOR_NORMAL
	tangent*=maxf(0.0,1.0-float(surface.friction)*IMPACT_FRICTION)
	if bounced:
		item.node.position+=normal*0.05
		item.spin_rate=float(item.spin_rate)*SPIN_DECAY
	else:
		item.node.position+=normal*0.01
	if floor_hit and not bounced:
		# Contact with nothing left to bounce: the residual travel is a roll, and
		# rolling grip brings it to a stop instead of a fixed rest timer.
		item.grounded=true
		tangent*=maxf(0.0,1.0-float(surface.friction)*ROLL_GRIP*dt)
		if tangent.length()<ROLL_STOP:tangent=Vector3.ZERO
		# The tumble rate follows the roll rather than the release, so spin and
		# travel come to rest together instead of the spin outliving the motion.
		item.spin_rate=minf(float(item.spin_rate),minf(SPIN_ROLL_MAX,tangent.length()/GRENADE_RADIUS))
	else:
		item.grounded=floor_hit
	# The surface only reacts to a contact that actually carried something: a body
	# already lying still is not kicking anything up.
	if floor_hit and (bounced or velocity.length()>ROLL_STOP):_impact_reaction(item,hit,family)
	item.velocity=tangent+normal*returned

## Loose ground reacts to a landing: sand, soil, grass and water throw a puff
## instead of returning the body cleanly. A heightmapped arena reports its own
## relief, so the same family kicks up harder there than on a flat pad.
func _impact_reaction(item:Dictionary,hit:Dictionary,family:String)->void:
	if float(item.puff)>0.0 or not REACTIVE_FLOORS.has(family):return
	item.puff=PUFF_COOLDOWN
	var terrain=game_match.map.get("terrain_data") if game_match.map else null
	var scale:=1.4 if terrain is Dictionary and str(terrain.get("kind","flat"))!="flat" else 1.0
	var point:Vector3=hit.get("position",item.node.position)+hit.normal*0.05
	var colour:Color=REACTIVE_FLOORS[family]
	_emit_trail(point,colour,0.0,0.45*scale,TRAIL_LIFE*scale)
	# A splash carries a wet highlight on top of the spray; dry ground does not.
	if family=="water":_emit_trail(point+Vector3.UP*0.1,SPLASH,2.4,0.3*scale,TRAIL_LIFE*0.7)

## Fuze cue in flight: the body ticks with an accelerating pulse and leaves a
## faint smoke trail with the odd spark, so the countdown is legible before the
## blast and the throw reads as a moving object.
func _tick_fuze(item:Dictionary,dt:float)->void:
	item.blink=float(item.blink)+dt
	var urgency:=1.0-clampf(float(item.fuse)/maxf(0.001,float(item.config.fuse)),0.0,1.0)
	var rate:=FUZE_RATE_MIN+urgency*FUZE_RATE_SPAN
	# Published so a HUD or an audio cue can follow the countdown without
	# re-deriving the cadence from the fuse.
	item.fuze_rate=rate
	var lit:=sin(float(item.blink)*rate)>0.0
	_set_node_emissive(item.body,FUZE_LIT if lit else FUZE_DARK,0.35)
	if item.fuze_light!=null:item.fuze_light.light_energy=(1.6 if lit else 0.15)*(0.5+0.5*urgency)
	item.trail_phase=float(item.trail_phase)+dt
	if float(item.trail_phase)>=TRAIL_INTERVAL:
		item.trail_phase=float(item.trail_phase)-TRAIL_INTERVAL
		item.trail_index=int(item.trail_index)+1
		var point:Vector3=item.node.position
		if item.trail_index%3==0:_emit_trail(point,SPARK_TRAIL,2.6,0.16,0.22)
		else:_emit_trail(point+Vector3.UP*0.04,SMOKE_TRAIL,0.0,0.14,TRAIL_LIFE)

## One pooled quad, reused round robin. Every emission re-points a live slot
## instead of building a node, so a trail costs two hundredths of a second of
## shader parameter writes and nothing else.
func _emit_trail(point:Vector3,colour:Color,energy:float,scale:float,life:float)->void:
	if _trail.is_empty():_build_trail()
	var puff:Dictionary=_trail[_trail_cursor]
	_trail_cursor=(_trail_cursor+1)%_trail.size()
	puff.age=0.0
	puff.life=life
	puff.scale=scale
	var node:MeshInstance3D=puff.node
	if not node.visible:node.visible=true
	node.position=point
	node.scale=Vector3.ONE*scale
	var material:ShaderMaterial=puff.material
	material.set_shader_parameter("color",Vector3(colour.r,colour.g,colour.b))
	material.set_shader_parameter("energy",energy)
	material.set_shader_parameter("opacity",TRAIL_OPACITY)

func _build_trail()->void:
	if _trail_material==null:
		# One template shader for the whole pool; each slot duplicates the
		# material so its own fade can differ without recompiling anything.
		_trail_material=Materials.create_flat(SMOKE_TRAIL,0.9)
	for _i in range(TRAIL_POOL):
		var node:=MeshInstance3D.new()
		node.mesh=VFX.geometry("smokeGeo")
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material:ShaderMaterial=_trail_material.duplicate()
		node.material_override=material
		add_child(node)
		node.visible=false
		_trail.append({"node":node,"material":material,"age":0.0,"life":TRAIL_LIFE,"scale":0.2})

func _tick_trail(dt:float)->void:
	for puff in _trail:
		var node:MeshInstance3D=puff.node
		if not node.visible:continue
		puff.age=float(puff.age)+dt
		var fraction=float(puff.age)/float(puff.life)
		if fraction>=1.0:
			node.visible=false
			continue
		node.scale=Vector3.ONE*float(puff.scale)*(0.6+fraction*0.9)
		puff.material.set_shader_parameter("opacity",TRAIL_OPACITY*(1.0-fraction))

## Flash and stun share one visibility model: exposure is the fraction of the
## target's silhouette with a clear line to the blast, the view direction scales
## what reaches the eye, and the enclosure of the blast scales both because a
## closed room returns light that an open field lets escape.
func _detonate(item:Dictionary)->void:
	if item.detonated:return
	item.detonated=true
	var point:Vector3=item.node.position
	match item.id:
		"frag","semtex","c4":
			game_match.explode(point,item.config.radius,item.config.damage,item.owner,item.id)
			_concuss(point,float(item.config.radius),item)
			item.active=false
		"claymore":
			game_match.explode(point,3,0,item.owner,item.id)
			for actor in game_match.actors:
				if _in_claymore_cone(item,actor):
					var distance:float=actor.body_position().distance_to(point)
					# Source Claymore omits sourceId from its damage event.
					actor.apply_damage(150.0*maxf(0,1-distance/5.0),null,"claymore")
			_concuss(point,5.0,item)
			item.active=false
		"flashbang","stun":
			game_match.explode(point,2.0 if item.id=="flashbang" else 1.5,0,item.owner,item.id)
			_flash_blast(point,item)
			item.active=false
		"snapshot":
			game_match.explode(point,2,0,item.owner,item.id)
			for actor in game_match.actors:
				if actor.alive and (item.owner.team=="ffa" or actor.team!=item.owner.team) and actor.body_position().distance_to(point)<=25:
					game_match.snapshot_pings.append({"position":actor.body_position(),"team":item.owner.team,"expire":game_match.elapsed+5.0})
			item.active=false
		"smoke","molotov","thermite":
			_create_area(item)

## Flash magnitude, in the order the terms enter:
##   proximity = 1 - distance / radius          inverse range, capped at the boundary
##   exposure  = clear samples / samples        partial cover gives a partial flash
##   facing    = lerp(0.25, 1, 0.5 + 0.5*dot(aim, to_blast))   looking away washes less
##   enclosed  = 1 + 0.35 * wall hits / rays    a closed room is worse
## player: intensity = (0.5 + 0.5 * proximity * exposure * facing) * enclosed
##         duration  = 3.2 * proximity * exposure * facing * (1 + 0.6 * enclosure)
## The 0.5 residual is the wash every visible detonation delivers, so the pinned
## boundary case (proximity 0) stays exactly 0.5 with no duration left.
func _flash_blast(point:Vector3,item:Dictionary)->void:
	var flash:bool=item.id=="flashbang"
	var radius:=FLASH_RADIUS if flash else STUN_RADIUS
	var residual:=FLASH_RESIDUAL if flash else STUN_RESIDUAL
	var base:=FLASH_DURATION if flash else STUN_DURATION
	var hit_fraction:=_enclosure(point)
	var enclosed:=lerpf(1.0,ENCLOSURE_INTENSITY,hit_fraction)
	var held:=lerpf(1.0,ENCLOSURE_DURATION,hit_fraction)
	var player=game_match.player
	var player_seen:=false
	for actor in game_match.actors:
		if actor==player:player_seen=true
		_flash_actor(point,actor,flash,radius,residual,base,enclosed,held)
	# The player is a flash target even when it is not in the actor roster, which
	# is what lets the boundary case survive a match that only names a player.
	if not player_seen and player:
		_flash_actor(point,player,flash,radius,residual,base,enclosed,held)

## One target's dose. Exposure gates the whole thing, the view direction scales
## what reaches the eye, and the enclosure scales both.
func _flash_actor(point:Vector3,actor,flash:bool,radius:float,residual:float,base:float,enclosed:float,held:float)->void:
	if not actor.alive:return
	var distance:float=actor.body_position().distance_to(point)
	if distance>radius:return
	var exposure:=_exposure(point,actor)
	if exposure<=0.0:return
	var proximity:=1.0-distance/radius
	var facing:=_facing(actor,point)
	var magnitude:=proximity*exposure*facing
	if actor==game_match.player:
		# A direct look both blinds harder and takes longer to recover from, so the
		# facing term gates the duration as well as the intensity.
		var duration:=base*proximity*exposure*facing*held
		var intensity:=(residual+(1.0-residual)*magnitude)*enclosed
		game_match.screen_effect.emit("flash" if flash else "stun",intensity,duration if flash else duration+STUN_FLOOR)
		# Deafness is the pressure wave, not the light: it follows range, cover and
		# the room, but not which way the target happened to be looking.
		game_match.screen_effect.emit("deafen",1.0,(4.0 if flash else 2.0)*proximity*exposure*held)
	elif "flash_time" in actor:
		# Bots read `flash_time` (bot_brain holds fire while it runs); nothing
		# consumes `stun_time`, so the model has no other bot hook to use.
		actor.flash_time=maxf(float(actor.flash_time),base*magnitude*held*0.5)

## Clear fraction of the rays from the blast to the target's head, torso and
## feet. Only world geometry counts as cover: another body absorbs a little
## light but must not read as a wall.
func _exposure(point:Vector3,actor)->float:
	var body:Vector3=actor.body_position()
	var clear:=0
	if not _occluded(point,actor.eye_position(),actor):clear+=1
	for offset in FLASH_BODY_SAMPLES:
		if not _occluded(point,body+offset,actor):clear+=1
	return float(clear)/float(FLASH_BODY_SAMPLES.size()+1)

func _occluded(point:Vector3,target:Vector3,actor)->bool:
	var offset:Vector3=target-point
	var distance=offset.length()
	if distance<=0.001:return false
	var hit=game_match.raycast(point,offset/distance,distance,actor,false)
	return not hit.is_empty() and hit.get("target")==null and float(hit.get("distance",distance))<distance-0.05

## 0..1 enclosure estimate: how many directions out of the blast run into
## geometry inside a short range.
func _enclosure(point:Vector3)->float:
	var hits:=0
	for direction in ENCLOSURE_RAYS:
		var hit=game_match.raycast(point,direction,ENCLOSURE_RANGE,null,false)
		if not hit.is_empty() and hit.get("target")==null:hits+=1
	return float(hits)/float(ENCLOSURE_RAYS.size())

## 0.25..1 facing term: 1 when the target is looking straight at the blast, the
## floor when it is looking straight away, 0.5 + 0.5*dot in between.
func _facing(actor,point:Vector3)->float:
	var to_blast:Vector3=point-actor.eye_position()
	if to_blast.length_squared()<0.0001:return 1.0
	return lerpf(FACING_FLOOR,1.0,clampf(0.5+0.5*actor.aim_direction().dot(to_blast.normalized()),0.0,1.0))

func _concuss(point:Vector3,radius:float,item:Dictionary)->void:
	var player=game_match.player
	if not player or item.owner!=player or not player.alive:return
	var distance:float=player.body_position().distance_to(point)
	if distance>radius:return
	var proximity:=1.0-distance/radius
	# Named for what it is: the edge of the frame closes in, which the screen
	# effects layer draws as its own kind rather than as a coloured wash.
	game_match.screen_effect.emit("concuss",CONCUSS_INTENSITY*proximity,CONCUSS_DURATION*(0.6+0.4*proximity))

## The impact family the body landed on. Steep normals are floors and prop tops,
## near-vertical ones are walls, and a hit under the terrain surface is water.
func _impact_family(point:Vector3,normal:Vector3)->String:
	if absf(normal.y)<FLOOR_NORMAL:return "wall"
	var map=game_match.map
	if map and map.has_method("height_at") and point.y<map.height_at(point.x,point.z)-0.25:return "water"
	return _floor_kind()

## The floor family is read once per map: `profile_for` walks its keyword table
## with string work, and a resting body re-tests its own floor every frame.
func _floor_kind()->String:
	var map=game_match.map
	var id:=str(map.get("map_id")) if map else ""
	if id!=_floor_map:
		_floor_map=id
		_floor_family=FLOOR_FAMILY.get(Materials.profile_for(id,Color.BLACK),"ground")
	return _floor_family

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
		var energy=0.0
		var additive=false
		if item.id=="molotov":
			color=Color("ff8a1e")
			energy=3.2
			additive=true
		elif item.id=="thermite":
			color=Color("ffe08a")
			energy=4.0
			additive=true
		mesh.mesh=VFX.geometry(item.id+"Geo")
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Smoke reads as a grey cloud rather than an emitter; fire and thermite
		# emit above the glow threshold.
		mesh.material_override=(Materials.create_flat(color,0.85) if item.id=="smoke" else Materials.create_unlit(color,energy,1.0 if item.id=="thermite" else 0.9,additive))
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

## The first mesh under an equipment model is its body, which is what the fuze
## pulse lights; parts are named per asset, so this avoids depending on the name.
func _body_mesh(root:Node)->MeshInstance3D:
	for child in root.get_children():
		if child is MeshInstance3D:return child
	return null

func _set_emissive(root:Node,color:Color,part_name:String,energy:float=0.8)->void:
	_set_node_emissive(Visuals.part(root,part_name),color,energy)

func _set_node_emissive(mesh:Node,color:Color,energy:float)->void:
	if mesh is MeshInstance3D and mesh.material_override is ShaderMaterial:
		var material:ShaderMaterial=mesh.material_override
		var linear=color.srgb_to_linear()
		# Both the emissive and flat unlit materials drive a `color` uniform; the
		# realistic surface shader uses its own emissive slot.
		if material.get_shader_parameter("color")!=null:
			material.set_shader_parameter("color",Vector3(linear.r,linear.g,linear.b))
		else:
			material.set_shader_parameter("emissive_color",Vector3(linear.r,linear.g,linear.b))
			material.set_shader_parameter("emissive_energy",energy)

func _spawn_laser(item:Dictionary)->void:
	var geometry=ImmediateMesh.new()
	geometry.surface_begin(Mesh.PRIMITIVE_LINES)
	geometry.surface_add_vertex(Vector3(0,0.12,0))
	geometry.surface_add_vertex(Vector3(0,0.12,5))
	geometry.surface_end()
	var laser=MeshInstance3D.new()
	laser.mesh=geometry
	laser.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser.material_override=Materials.create_unlit(Color("ff2a2a"),2.5,0.0,true)
	item.node.add_child(laser)
	item.laser=laser
