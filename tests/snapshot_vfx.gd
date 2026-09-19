extends SceneTree
const MAP=preload("res://scripts/world/map_world.gd")
const VFX=preload("res://scripts/visuals/combat_vfx.gd")
const EQUIPMENT=preload("res://scripts/game/equipment_system.gd")
const VISUALS=preload("res://scripts/visuals/visual_factory.gd")
var map
var actors:Array=[]
var player=null
var elapsed:=20.0
var ui_time:=0.0
var snapshot_pings:Array=[]
var vfx
func explode(point:Vector3,radius:float,_damage:float,_owner,_id:String)->void:vfx.explosion(point,radius)
func radial_damage(_p,_r,_d,_o,_i,_f)->void:pass
class Owner extends RefCounted:
	var alive:=true
	var team:="blue"
	func eye_position()->Vector3:return Vector3.ZERO
	func aim_direction()->Vector3:return Vector3.BACK
func _initialize()->void:call_deferred("_run")
func _run()->void:
	root.size=Vector2i(1280,720)
	var scene=Node3D.new()
	root.add_child(scene)
	map=MAP.new()
	scene.add_child(map)
	map.load_map("desert_town")
	VISUALS.environment=map.environment_data
	var camera=Camera3D.new()
	scene.add_child(camera)
	camera.position=Vector3(-50,5,0)
	camera.look_at(Vector3(-38,0.8,0))
	camera.fov=72
	camera.current=true
	vfx=VFX.new()
	vfx.environment=map.environment_data
	scene.add_child(vfx)
	var equipment=EQUIPMENT.new()
	equipment.game_match=self
	scene.add_child(equipment)
	var owner=Owner.new()
	for id in ["smoke","molotov","thermite"]:
		equipment.throw_item(id,owner)
		var item:Dictionary=equipment.items.back()
		item.node.position=Vector3(-37,0,["smoke","molotov","thermite"].find(id)*4-4)
		equipment._detonate(item)
		equipment._tick_area(item,1.25)
	vfx.explosion(Vector3(-38,0.6,7),3.0)
	vfx.bullet_impact(Vector3(-40,1,1.4),Vector3.LEFT,false)
	vfx.tracer(Vector3(-43,0.7,1),Vector3(-37,2,5))
	vfx.muzzle_flash(Vector3(-42,1,-1),Vector3.RIGHT)
	vfx.tick(0.025)
	for _i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/maps/previews/equipment_vfx.png")
	print("VFX live shader render captured")
	quit()
