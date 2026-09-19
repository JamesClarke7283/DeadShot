extends RefCounted
var frames:Array=[]
var duration:float=8.0
var hz:float=30.0

func _init(duration_seconds:float=8.0,frequency:float=30.0)->void:
	duration=duration_seconds
	hz=frequency

func latest()->float:
	return float(frames[-1].t) if not frames.is_empty() else 0.0

func clear()->void:
	frames.clear()

func record(time:float,actors:Array)->void:
	if not frames.is_empty() and time-float(frames[-1].t)<1.0/hz:return
	frames.append({"t":time,"actors":actors.duplicate(true)})
	while frames.size()>1 and frames[0].t<time-duration:frames.pop_front()

func window(start_time:float,end_time:float)->Array:
	return frames.filter(func(frame):return frame.t>=start_time and frame.t<=end_time).duplicate(true)

func recent(now:float,seconds:float)->Array:
	return window(now-seconds,now)

static func sample_at(window_frames:Array,time:float)->Dictionary:
	var output:Dictionary={}
	if window_frames.is_empty():return output
	var index=0
	while index<window_frames.size()-1 and window_frames[index+1].t<=time:index+=1
	var a:Dictionary=window_frames[index]
	var b:Dictionary=window_frames[mini(index+1,window_frames.size()-1)]
	var span:float=b.t-a.t
	var weight=clampf((time-a.t)/span,0,1) if span>0.000001 else 0.0
	var b_by_id:Dictionary={}
	for actor in b.actors:b_by_id[int(actor.id)]=actor
	for actor in a.actors:
		var next:Dictionary=b_by_id.get(int(actor.id),actor)
		var snapshot:Dictionary=actor.duplicate(true)
		for coordinate in ["x","y","z"]:snapshot[coordinate]=lerpf(float(actor[coordinate]),float(next[coordinate]),weight)
		# Preserve the source's signed half-turn tie (Godot lerp_angle may
		# choose the opposite direction at exactly PI).
		var angle_delta:float=float(next.yaw)-float(actor.yaw)
		while angle_delta>PI:angle_delta-=TAU
		while angle_delta< -PI:angle_delta+=TAU
		snapshot.yaw=float(actor.yaw)+angle_delta*weight
		output[int(actor.id)]=snapshot
	for actor in b.actors:
		if not output.has(int(actor.id)):output[int(actor.id)]=actor.duplicate(true)
	return output
