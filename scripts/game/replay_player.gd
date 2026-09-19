extends Node3D
const Recorder=preload("res://scripts/game/replay_recorder.gd")
const Visuals=preload("res://scripts/visuals/visual_factory.gd")
var frames:Array=[]
var ghosts:Dictionary={}
var ghost_phases:Dictionary={}
var elapsed:float=0.0
var duration:float=0.0
var start_time:float=0.0
var snapshots:Dictionary={}
var camera:Camera3D
var kind:String="killcam"
var focus_id:int=-1
var victim_id:int=-1

func setup(data:Dictionary,replay_kind:String,source_camera:Camera3D=null)->void:
	frames=data.frames
	kind=replay_kind
	focus_id=int(data.get("killerId",-1)) if kind=="killcam" else int(data.get("playerId",0))
	victim_id=int(data.get("victimId",0))
	if not frames.is_empty():
		start_time=float(frames[0].t)
		duration=float(frames[-1].t)-start_time
	camera=Camera3D.new()
	camera.fov=75
	camera.near=0.05
	camera.far=2000
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	add_child(camera)
	if source_camera!=null:
		# Three reuses the live perspective camera, including the user's FOV
		# and its last pose when neither focused actor is in the window.
		camera.global_transform=source_camera.global_transform
		camera.projection=source_camera.projection
		camera.fov=source_camera.fov
		camera.near=source_camera.near
		camera.far=source_camera.far
		camera.keep_aspect=source_camera.keep_aspect
		camera.size=source_camera.size
		camera.frustum_offset=source_camera.frustum_offset
		camera.h_offset=source_camera.h_offset
		camera.v_offset=source_camera.v_offset
		camera.cull_mask=source_camera.cull_mask
		camera.environment=source_camera.environment
		camera.attributes=source_camera.attributes
	camera.make_current()

func advance(dt:float)->void:
	var speed=0.55 if kind=="killcam" else 0.85
	elapsed=minf(duration,elapsed+dt*speed)
	snapshots=Recorder.sample_at(frames,start_time+elapsed)
	for id in snapshots:
		var snapshot:Dictionary=snapshots[id]
		if not ghosts.has(id):
			var human=Visuals.create_human(snapshot.team,id%6)
			human.rotation_order=EULER_ORDER_XYZ
			add_child(human)
			ghosts[id]=human
			ghost_phases[id]=0.0
		var ghost:Node3D=ghosts[id]
		ghost.position=Vector3(snapshot.x,snapshot.y,snapshot.z)
		ghost.rotation.y=snapshot.yaw
		ghost.visible=snapshot.alive
		# Each newly constructed source ghost owns its own animation phase.
		# Its pose keeps animating even while killcam time holds its last frame.
		ghost_phases[id]+=dt*speed
		var previous_pitch:=ghost.rotation.x
		Visuals.animate_human(ghost,snapshot.anim,ghost_phases[id],dt*speed)
		if snapshot.anim!="die":
			ghost.rotation.x=previous_pitch
	_update_camera()

func _update_camera()->void:
	var focus:Dictionary=snapshots.get(focus_id,{})
	var victim:Dictionary=snapshots.get(victim_id,{})
	if kind=="killcam":
		if focus.is_empty():
			if not victim.is_empty():
				camera.position=Vector3(victim.x+3.5,victim.y+2.6,victim.z+3.5)
				camera.look_at(Vector3(victim.x,victim.y+1.0,victim.z))
		else:
			camera.position=Vector3(focus.x,focus.y+1.55,focus.z)
			var target=Vector3(victim.x,victim.y+1.0,victim.z) if not victim.is_empty() else camera.position+Vector3(sin(focus.yaw),0,cos(focus.yaw))
			if target.distance_squared_to(camera.position)>0.00001:camera.look_at(target)
	elif not focus.is_empty():
		var forward=Vector3(sin(focus.yaw),0,cos(focus.yaw))
		var position_value=Vector3(focus.x,focus.y,focus.z)
		camera.position=position_value-forward*4.5+Vector3.UP*2.6
		camera.look_at(position_value+forward*2+Vector3.UP*1.2)

func is_finished()->bool:return elapsed>=duration

func progress()->float:return minf(1.0,elapsed/duration) if duration>0.0 else 1.0
