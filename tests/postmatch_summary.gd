extends SceneTree
const Session=preload("res://scripts/game/match_session.gd")
const Streaks=preload("res://scripts/game/streak_system.gd")

class ReplayPlayer extends RefCounted:
	var actor_id:=0
	var team:="blue"

class BoundsOnly extends RefCounted:
	var bounds:={"minX":-20.0,"maxX":20.0,"minZ":-20.0,"maxZ":20.0}

class ObjectiveScore extends RefCounted:
	var reads:=0
	func hud()->Dictionary:
		reads+=1
		return {"blue":200,"red":150}

func row(id:int,team:String,kills:int,points:int)->Dictionary:
	return {"id":id,"name":"P%d"%id,"team":team,"kills":kills,"deaths":0,"assists":0,"score":points,"isPlayer":false}

func _initialize()->void:call_deferred("run")

func replay_match():
	var game=Session.new()
	root.add_child(game)
	game.mode={"id":"tdm"}
	game.state="live"
	game.player=ReplayPlayer.new()
	game.player_killstreak=4
	game.elapsed=2.0
	game.recorder.record(1.0,[])
	game.recorder.record(2.0,[])
	game.best_play={"kills":2,"playerId":0,"frames":[{"t":-2.0,"actors":[]},{"t":-1.0,"actors":[]}]}
	return game

func run()->void:
	# Source Game.updatePlaying keeps blue/red as scoreboard.teamKills; only
	# hud.setScoreline selects objective totals. postResult stores blue/red.
	for mode_id in ["dom","ctf"]:
		var game=Session.new()
		root.add_child(game)
		game.mode={"id":mode_id}
		game.state="live"
		game.objective=ObjectiveScore.new()
		game.scores={0:row(0,"blue",4,400),1:row(1,"red",2,200),2:row(2,"blue",3,300)}
		var results:Array=[]
		game.finished.connect(func(result):results.append(result))
		game.end_match("red")
		assert(results.size()==1 and results[0].blue==7 and results[0].red==2,"Objective-mode postmatch totals must remain team kills")
		assert(results[0].winner=="red" and results[0].mode==mode_id,"Result winner remains the objective winner even when it has fewer kills")
		assert(game.objective.reads==0,"Result capture must not substitute the live objective HUD")
		assert(results[0].rows.map(func(value):return value.id)==[0,2,1])
		game.end_match("blue")
		assert(results.size()==1 and game.winner=="red","Repeated end cannot replace the captured winner")
		game.free()
	var ordinary=replay_match()
	ordinary.end_match("blue")
	assert(ordinary.best_play.kills==4 and ordinary.best_play.frames[0].t==1.0,"Ordinary match end finalizes a better ongoing streak")
	ordinary.free()
	var nuclear=replay_match()
	nuclear.map=BoundsOnly.new()
	var retained:Dictionary=nuclear.best_play.duplicate(true)
	var streaks=Streaks.new()
	nuclear.add_child(streaks)
	streaks.game_match=nuclear
	var nuke_mesh:=Node3D.new()
	streaks.add_child(nuke_mesh)
	var nuke:Dictionary={"id":"nuke","owner":nuclear.player,"elapsed":5.9,"timer":0.0,"node":nuke_mesh,"done":false}
	streaks._tick_entry(nuke,0.2)
	assert(nuclear.state=="end" and nuclear.winner=="blue" and nuke.done)
	assert(nuclear.best_play==retained,"Source nuke endByStreak retains the previous captured play")
	nuclear.free()
	await process_frame
	print("POSTMATCH_SUMMARY: DOM/CTF team kills, objective winner, ranked rows, one end event, ordinary best-play finalization and nuke retaining the prior replay passed.")
	quit()
