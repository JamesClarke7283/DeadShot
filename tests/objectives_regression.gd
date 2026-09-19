extends SceneTree
## Behavioral regression against original DOM/CTF rules and boundary cases.

const OBJECTIVES = preload("res://scripts/game/objectives.gd")

class FakeMap extends RefCounted:
	var bounds := {"minX": -70.0, "maxX": 70.0, "minZ": -70.0, "maxZ": 70.0}
	var environment_data := {}
	func height_at(_x: float, _z: float) -> float:
		return 0.0

class FakeActor extends Node3D:
	var actor_id := 0
	var team := "blue"
	var alive := true
	func body_position() -> Vector3:
		return position + Vector3.UP

class FakeMatch extends Node3D:
	var map := FakeMap.new()
	var actors: Array = []

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _actor(match_instance: FakeMatch, id: int, team: String, position: Vector3) -> FakeActor:
	var actor := FakeActor.new()
	actor.actor_id = id
	actor.team = team
	actor.position = position
	match_instance.add_child(actor)
	match_instance.actors.append(actor)
	return actor

func _run() -> void:
	var match_instance := FakeMatch.new()
	root.add_child(match_instance)
	var objectives = OBJECTIVES.new()
	match_instance.add_child(objectives)
	objectives.setup("dom", match_instance)
	_expect(objectives.points.size() == 3, "Domination has A/B/C")
	_expect(is_equal_approx(objectives.points[0].z, -30.8) and is_equal_approx(objectives.points[2].z, 30.8), "Points use original 28/50/72 percent map positions")
	var blue_actor := _actor(match_instance, 0, "blue", Vector3(0, 0, -30.8))
	objectives.tick(1.0)
	_expect(objectives.points[0].progress == 0.5 and objectives.points[0].owner == "neutral", "Neutral capture advances at .5/sec without early ownership")
	_expect(objectives.blue == 0, "No scoring before complete capture")
	objectives.tick(1.0)
	_expect(objectives.points[0].owner == "blue" and objectives.blue == 1, "Capture grants one point on next whole-second tick")
	var red_actor := _actor(match_instance, 1, "red", blue_actor.position)
	objectives.tick(0.5)
	_expect(objectives.points[0].progress == 1.0, "Contested domination point freezes progress")
	blue_actor.position.x = 20.0
	objectives.tick(0.5)
	_expect(objectives.points[0].progress == 0.75 and objectives.points[0].owner == "neutral", "Enemy presence immediately neutralizes owned scoring")
	_expect(objectives.blue == 1, "Neutralized point gives no tick score")
	red_actor.position.x = 20.0
	objectives.tick(1.0)
	_expect(objectives.points[0].progress == 0.75, "Unoccupied progress is preserved")
	red_actor.position = Vector3(6.0, 10, 0)
	objectives.tick(0.5)
	_expect(objectives.points[1].progress == -0.25, "Domination radius is inclusive and ignores vertical separation")
	_expect(objectives.goal_for(blue_actor).kind == "attack", "Bots attack neutral ground")
	objectives.points[0].owner = "blue"
	_expect(objectives.goal_for(blue_actor).kind == "defend", "One-third of each team defend owned ground")
	var raider := _actor(match_instance, 2, "blue", Vector3.ZERO)
	_expect(objectives.goal_for(raider).kind == "attack", "Remaining team members raid")
	objectives.blue = 200
	_expect(objectives.check_win(0, 600).winner == "blue", "Domination score cap is 200")
	objectives.blue = 1
	objectives.red = 1
	_expect(objectives.check_win(600, 600).over and not objectives.check_win(600, 600).has("winner"), "Timed tie has no winner")
	objectives.setup("ctf", match_instance)
	_expect(objectives.flags.size() == 2 and objectives.flags[0].home.z == -62.0 and objectives.flags[1].home.z == 62.0, "CTF flags use original bases")
	blue_actor.position = Vector3(2.1, 0, 62)
	red_actor.position = Vector3(30, 0, 0)
	raider.position = Vector3(30, 0, 0)
	objectives.tick(0.016)
	_expect(objectives.flags[1].status == "home", "Pickup radius measures source body center, not feet")
	blue_actor.position = Vector3(0, 0, 62)
	objectives.tick(0.016)
	_expect(objectives.flags[1].status == "carried" and objectives.flags[1].carrier == blue_actor.actor_id, "Enemy flag can be picked up")
	_expect(objectives.goal_for(blue_actor).kind == "carry", "Carrier heads to its own base")
	_expect(objectives.goal_for(raider).radius == 4.0, "Raiders escort their carrier")
	blue_actor.position = Vector3(0, 5, -62)
	objectives.tick(0.016)
	_expect(objectives.blue == 1 and objectives.flags[1].status == "home", "Carried flag follows source ground height and captures at own home")
	blue_actor.position = Vector3(0, 0, 62)
	objectives.tick(0.016)
	blue_actor.position = Vector3(5, 2, 12)
	blue_actor.alive = false
	objectives.tick(0.016)
	_expect(objectives.flags[1].status == "dropped" and objectives.flags[1].pos == blue_actor.body_position(), "Carrier death drops flag at source body center")
	red_actor.position = blue_actor.position
	objectives.tick(0.016)
	_expect(objectives.flags[1].status == "home", "Friendly touch returns a dropped flag")
	blue_actor.alive = true
	blue_actor.position = Vector3(0, 0, 62)
	red_actor.position = Vector3(0, 0, -62)
	objectives.tick(0.016)
	_expect(objectives.flags[0].status == "carried" and objectives.flags[1].status == "carried", "Both flags can be stolen")
	blue_actor.position = Vector3(0, 0, -62)
	red_actor.position = Vector3(20, 0, 20)
	objectives.tick(0.016)
	_expect(objectives.blue == 1, "Capture is blocked while own flag is missing")
	red_actor.alive = false
	objectives.tick(0.016)
	_expect(objectives.goal_for(blue_actor).kind == "carry", "Carrier priority wins over own dropped-flag defense")
	blue_actor.alive = false
	objectives.tick(0.016)
	blue_actor.alive = true
	_expect(objectives.goal_for(blue_actor).kind == "return", "Defender returns own dropped flag")
	objectives.blue = 3
	_expect(objectives.check_win(1, 600).winner == "blue", "Three captures win CTF")
	objectives.blue = 0
	objectives.red = 2
	_expect(objectives.check_win(600, 600).winner == "red", "Time limit chooses capture leader")
	for failure: String in failures: push_error(failure)
	print("OBJECTIVE REGRESSION: %d checks, %d failures" % [checks, failures.size()])
	match_instance.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
