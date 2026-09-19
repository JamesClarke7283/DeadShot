class_name BotNavigator
extends RefCounted
var astar = AStar3D.new()

func configure(points: Array) -> void:
	astar.clear()
	for point in points:
		astar.add_point(int(point.id), point.position)
	for point in points:
		for neighbor in point.neighbors:
			if astar.has_point(int(neighbor)) and not astar.are_points_connected(int(point.id), int(neighbor)):
				astar.connect_points(int(point.id), int(neighbor), true)

func path(start: Vector3, goal: Vector3) -> Array[Vector3]:
	if astar.get_point_count() == 0:
		return []
	var a = astar.get_closest_point(start)
	var b = astar.get_closest_point(goal)
	if a == b:
		return [goal]
	var result: Array[Vector3] = []
	result.assign(astar.get_point_path(a, b))
	if not result.is_empty():
		result.append(goal)
	return result
