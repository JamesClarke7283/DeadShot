extends RefCounted
const DIFFICULTY = {
	"recruit":{"aimErrorDeg":18.0,"reaction":0.55,"viewRange":45.0},
	"regular":{"aimErrorDeg":9.0,"reaction":0.32,"viewRange":65.0},
	"veteran":{"aimErrorDeg":3.0,"reaction":0.16,"viewRange":85.0},
}
var params: Dictionary
var target
var reaction_timer: float = 0.0
var error_timer: float = 0.0
var melee_cooldown: float = 0.0
var repath_timer: float = 0.0
var select_timer: float = 0.0
var stuck_time: float = 0.0
var combat_path_timer: float = 0.0
var pulse: bool = false
var aim_noise = Vector2.ZERO

func _init(difficulty: String = "regular") -> void:
	params = DIFFICULTY.get(difficulty, DIFFICULTY.regular)

func tick(bot, dt: float, world) -> void:
	reaction_timer += dt
	error_timer -= dt
	melee_cooldown -= dt
	repath_timer -= dt
	_select_target(bot, world)
	if is_instance_valid(target) and target.alive:
		_engage(bot, dt, world)
	else:
		_patrol(bot, dt, world)
	if bot.weapon.definition.fireMode == "auto":
		bot.weapon.trigger = bot.firing
	else:
		pulse = not pulse
		bot.weapon.trigger = bot.firing and pulse
	bot.weapon.tick(dt, bot, world)
	if bot.weapon.magazine <= 0 and bot.weapon.reserve > 0:
		bot.weapon.reload()

func _visible(bot, other, world) -> bool:
	var vector: Vector3 = other.eye_position() - bot.eye_position()
	var distance = vector.length()
	return distance < 0.001 or world.map.raycast_boxes(bot.eye_position(), vector / distance, distance - 0.6) < 0

func _select_target(bot, world) -> void:
	select_timer -= 1.0 / 60.0
	if is_instance_valid(target) and target.alive and select_timer > 0:
		return
	select_timer = 0.2
	if is_instance_valid(target) and target.alive and _visible(bot, target, world):
		return
	var best = null
	var best_distance: float = INF
	for other in world.actors:
		if other == bot or not other.alive or (bot.team != "ffa" and other.team == bot.team):
			continue
		var distance: float = bot.position.distance_to(other.body_position())
		if distance > params.viewRange:
			continue
		if distance < best_distance and _visible(bot, other, world):
			best = other
			best_distance = distance
	if best != null and best != target:
		reaction_timer = 0
	target = best

func _engage(bot, dt: float, world) -> void:
	var direction: Vector3 = target.eye_position() - bot.eye_position()
	var distance = direction.length()
	direction = direction.normalized()
	bot.rotation.y = atan2(direction.x, direction.z)
	if error_timer <= 0:
		error_timer = 0.12
		var error = deg_to_rad(float(params.aimErrorDeg))
		aim_noise = Vector2(randf_range(-error,error), randf_range(-error,error))
	bot.aim_dir = apply_aim_error(direction, aim_noise)
	var effective_range = minf(params.viewRange, bot.weapon.stats.range.far + 8)
	bot.firing = reaction_timer >= params.reaction and distance <= effective_range and bot.weapon.magazine > 0 and bot.flash_time <= 0
	if distance <= 2.2 and melee_cooldown <= 0:
		melee_cooldown = 0.8
		target.apply_damage(55.0, bot, "melee")
	bot.moving = false
	var goal: Dictionary = world.objective_goal(bot)
	var destination = Vector3.ZERO
	var has_destination = false
	var speed: float = bot.move_speed()
	var on_station = not goal.is_empty() and Vector2(bot.position.x-goal.x,bot.position.z-goal.z).length_squared() <= float(goal.radius)*float(goal.radius)
	if not goal.is_empty() and goal.kind == "carry":
		destination = Vector3(goal.x, 0, goal.z)
		speed *= 1.15
		has_destination = true
	elif not goal.is_empty() and not on_station and bot.health > 30:
		destination = Vector3(goal.x,0,goal.z)
		speed *= 0.9
		has_destination = true
	elif bot.health <= 30:
		var away: Vector3 = bot.position - target.position
		away.y = 0
		destination = bot.position + away.normalized()*4
		has_destination = true
	elif distance > effective_range * 0.7:
		destination = target.position
		has_destination = true
	if has_destination:
		if combat_path_timer > 0 and bot.path_index < bot.path.size():
			combat_path_timer -= dt
			bot.moving = _follow_path(bot,speed,dt,false)
		else:
			combat_path_timer = 0.0
			bot.moving = bot.step_toward(destination,speed,dt)
		if _stuck(bot.moving and bot.blocked,dt):
			bot.path.assign(world.navigator.path(bot.position,destination))
			bot.path_index = 0
			if bot.path.size() > 1:
				combat_path_timer = 2.5
			else:
				_sidestep(bot,destination-bot.position)
				combat_path_timer = 0.6

func _patrol(bot, dt: float, world) -> void:
	bot.firing = false
	var goal: Dictionary = world.objective_goal(bot)
	if bot.path.is_empty() or bot.path_index >= bot.path.size() or repath_timer <= 0:
		var destination = Vector3.ZERO
		if not goal.is_empty():
			repath_timer = 1+randf()
			var on_station := Vector2(bot.position.x-goal.x,bot.position.z-goal.z).length_squared() <= float(goal.radius)*float(goal.radius)
			var angle = randf()*TAU
			var radius = randf()*float(goal.radius)*(1.0 if on_station else 0.5)
			destination = Vector3(goal.x+cos(angle)*radius,0,goal.z+sin(angle)*radius)
		else:
			repath_timer = 2+randf()*2
			var bounds: Dictionary = world.map.bounds
			destination = Vector3(randf_range(bounds.minX,bounds.maxX),0,randf_range(bounds.minZ,bounds.maxZ))
		destination.y = world.map.height_at(destination.x,destination.z)
		bot.path.assign(world.navigator.path(bot.position,destination))
		bot.path_index = 0
	var speed: float = bot.move_speed() * (1.15 if goal.get("kind","") == "carry" else 0.8)
	bot.moving = _follow_path(bot,speed,dt,true)
	if _stuck(bot.moving and bot.blocked,dt) and not bot.path.is_empty():
		_sidestep(bot,bot.path[mini(bot.path_index,bot.path.size()-1)]-bot.position)
		repath_timer = 0.7

func _follow_path(bot, speed: float, dt: float, face: bool) -> bool:
	if bot.path_index >= bot.path.size():
		return false
	var point: Vector3 = bot.path[bot.path_index]
	while bot.path_index < bot.path.size()-1 and Vector2(point.x-bot.position.x,point.z-bot.position.z).length() < 0.5:
		bot.path_index += 1
		point = bot.path[bot.path_index]
	if face:
		var direction: Vector3 = point-bot.position
		direction.y=0
		if direction.length_squared()>0.0001:
			bot.rotation.y = atan2(direction.x,direction.z)
			bot.aim_dir = direction.normalized()
	var moving: bool = bot.step_toward(point,speed,dt)
	if not moving:
		bot.path_index += 1
	return moving

func _stuck(blocked: bool, dt: float) -> bool:
	stuck_time = stuck_time+dt if blocked else maxf(0,stuck_time-dt*3)
	if stuck_time >= 0.4:
		stuck_time=0
		return true
	return false

func _sidestep(bot, direction: Vector3) -> void:
	var perpendicular = Vector3(direction.z,0,-direction.x).normalized() * (1 if randf()<0.5 else -1)
	var destination: Vector3 = bot.position+perpendicular*3
	destination.y = bot.game_match.map.height_at(destination.x,destination.z)
	bot.path.assign([destination])
	bot.path_index=0

static func apply_aim_error(direction: Vector3, noise: Vector2) -> Vector3:
	var up := Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP
	var right := direction.cross(up).normalized()
	var local_up := right.cross(direction).normalized()
	return (direction + right * tan(noise.x) + local_up * tan(noise.y)).normalized()
