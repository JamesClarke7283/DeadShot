extends SceneTree
const Recorder = preload("res://scripts/game/replay_recorder.gd")
const Playback = preload("res://scripts/game/replay_player.gd")
const Visuals = preload("res://scripts/visuals/visual_factory.gd")

func snap(id:int,x:float,yaw:float=0.0)->Dictionary:
	return {"id":id,"team":"blue","name":"P%d"%id,"isPlayer":id==0,"x":x,"y":0.0,"z":0.0,"yaw":yaw,"alive":true,"anim":"run","weaponId":"m4"}

func _initialize()->void:
	call_deferred("run")

func run()->void:
	var recorder=Recorder.new(1.0,30.0)
	recorder.record(0.0,[snap(0,0)])
	recorder.record(0.01,[snap(0,1)])
	recorder.record(0.05,[snap(0,2)])
	assert(recorder.frames.size()==2)
	for i in range(1,61):recorder.record(float(i)/30.0,[snap(0,i)])
	assert(recorder.frames[0].t>=1.0 and recorder.latest()==2.0)
	var copied=recorder.recent(2.0,0.5)
	copied[0].actors[0].x=999
	assert(recorder.recent(2.0,0.5)[0].actors[0].x!=999)
	recorder.clear()
	assert(recorder.frames.is_empty() and recorder.latest()==0.0)
	assert(Recorder.new().duration==8.0)

	var a=snap(0,0,-PI+0.1)
	var b=snap(0,10,PI-0.1)
	b.alive=false
	b.anim="die"
	var frames:Array=[{"t":0.0,"actors":[a]},{"t":1.0,"actors":[b,snap(1,5)]}]
	var middle:Dictionary=Recorder.sample_at(frames,0.5)
	assert(is_equal_approx(middle[0].x,5.0) and is_equal_approx(middle[0].yaw,-PI))
	assert(middle[0].alive and middle[0].anim=="run", "Discrete state uses the earlier snapshot")
	assert(middle.has(1), "Source includes actors present only in the later frame")
	assert(Recorder.sample_at(frames,-1.0)[0].x==0.0)
	assert(not Recorder.sample_at(frames,2.0)[0].alive)
	a.yaw=0.0
	b.yaw=PI
	assert(is_equal_approx(Recorder.sample_at(frames,0.5)[0].yaw,PI/2.0))
	b.yaw=-PI
	assert(is_equal_approx(Recorder.sample_at(frames,0.5)[0].yaw,-PI/2.0))
	assert(Recorder.sample_at([],1.0).is_empty())

	var live_camera:=Camera3D.new()
	root.add_child(live_camera)
	live_camera.fov=103.0
	live_camera.near=0.05
	live_camera.far=2000.0
	live_camera.position=Vector3(10,5,15)
	var replay=Playback.new()
	root.add_child(replay)
	var killer=snap(1,10,PI/2)
	var victim=snap(0,0)
	frames=[{"t":4.0,"actors":[killer,victim]},{"t":6.0,"actors":[killer,victim]}]
	replay.setup({"frames":frames,"killerId":1,"victimId":0},"killcam",live_camera)
	assert(replay.camera.global_transform==live_camera.global_transform)
	assert(replay.camera.fov==103.0 and replay.camera.far==2000.0)
	replay.advance(0.2)
	assert(is_equal_approx(replay.elapsed,0.11))
	assert(replay.camera.position.is_equal_approx(Vector3(10,1.55,0)))
	var expected=(Vector3(0,1,0)-replay.camera.position).normalized()
	assert((-replay.camera.global_basis.z).is_equal_approx(expected))
	replay.focus_id=-1
	replay.advance(0.0)
	assert(replay.camera.position.is_equal_approx(Vector3(3.5,2.6,3.5)))
	replay.focus_id=1
	replay.victim_id=-1
	replay.advance(0.0)
	assert((-replay.camera.global_basis.z).is_equal_approx(Vector3.RIGHT))
	replay.kind="best_play"
	replay.advance(0.2)
	assert(is_equal_approx(replay.elapsed,0.28))
	assert(replay.camera.position.is_equal_approx(Vector3(5.5,2.6,0)))
	assert(is_equal_approx(replay.progress(),0.14))
	replay.advance(10.0)
	assert(replay.is_finished() and replay.progress()==1.0)
	var phase:float=replay.ghost_phases[1]
	replay.advance(0.1)
	assert(is_equal_approx(replay.ghost_phases[1],phase+0.085), "Animation continues after playback reaches its final frame")

	# A ghost that first appears several frames into a window starts its own
	# ProceduralHuman phase at that update, rather than at replay elapsed time.
	replay.free()
	replay=Playback.new()
	root.add_child(replay)
	var newcomer=snap(3,20)
	frames=[{"t":0.0,"actors":[victim]},{"t":1.0,"actors":[victim]},{"t":2.0,"actors":[victim,newcomer]}]
	replay.setup({"frames":frames,"playerId":0},"best_play")
	replay.advance(0.5)
	assert(not replay.ghosts.has(3))
	replay.advance(1.0)
	assert(is_equal_approx(replay.ghost_phases[3],0.85))
	assert(is_equal_approx(Visuals.part(replay.ghosts[3],"left_leg").rotation.x,sin(0.85*11)*0.8))
	newcomer.alive=false
	newcomer.anim="die"
	replay.advance(1.0)
	assert(not replay.ghosts[3].visible and replay.ghosts[3].rotation.x<0.0)
	replay.free()
	live_camera.free()
	await process_frame
	print("REPLAY_VERIFICATION: rolling capture, copies, interpolation/angle ties, discrete states, source camera projection, both camera paths, speeds, visibility, independent ghost phases and final-frame animation passed.")
	quit()
