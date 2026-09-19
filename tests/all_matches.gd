extends SceneTree
## Build and simulate every shipped map/mode combination through live Match.
const Session=preload("res://scripts/game/match_session.gd")
const Data=preload("res://scripts/core/game_data.gd")
var failures:Array[String]=[]

func _initialize()->void:call_deferred("run")

func check(value:bool,message:String)->void:
	if not value:
		failures.append(message)
		push_error(message)

func run()->void:
	seed(1717)
	var defaults:Dictionary=Data.table("default_save")
	for map_id in ["desert_town","forest_facility","urban_docks"]:
		for mode_id in ["tdm","ffa","dom","ctf","gungame"]:
			var game=Session.new()
			root.add_child(game)
			check(game.start({"mapId":map_id,"mode":mode_id,"botCount":6,"hasPlayer":false,"difficulty":"regular"},defaults.classes[0],defaults.settings),"Build %s/%s"%[map_id,mode_id])
			await physics_frame
			await physics_frame
			var starts:Array=[]
			for actor in game.actors:starts.append(actor.position)
			for step in 900:
				game.tick(1.0/60)
				if step%60==0:await process_frame
			var moved:=0
			for index in game.actors.size():
				if game.actors[index].position.distance_to(starts[index])>1:moved+=1
			check(game.state=="live","Warmup completes %s/%s"%[map_id,mode_id])
			check(moved>=3,"Bots navigate %s/%s"%[map_id,mode_id])
			check(not game.recorder.frames.is_empty(),"Live actors recorded %s/%s"%[map_id,mode_id])
			if mode_id in ["dom","ctf"]:
				check(game.objective!=null and game.objective.hud().kind==mode_id,"Native objective updates %s/%s"%[map_id,mode_id])
			if mode_id=="gungame":
				check(game.dropped_weapons.is_empty(),"Gun Game has no weapon drops")
			print("MATCH %s/%s: %d/6 bots moved, %.2fs elapsed"%[map_id,mode_id,moved,game.elapsed])
			game.free()
			await process_frame
	print("ALL MATCHES: %d combinations, %d failures"%[15,failures.size()])
	quit(0 if failures.is_empty() else 1)
