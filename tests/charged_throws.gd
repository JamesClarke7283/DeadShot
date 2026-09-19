extends SceneTree
const Session=preload("res://scripts/game/match_session.gd")
const Data=preload("res://scripts/core/game_data.gd")
const Main=preload("res://scripts/core/main.gd")
var failures:Array[String]=[]
var checks:=0
var game

class PauseUI extends RefCounted:
	var console_open:=false
	func show_pause()->void:pass
	func show_match(_hardcore:bool)->void:pass
	func toggle_console()->void:console_open=not console_open

func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures.append(message)
		push_error(message)
func clear_items()->void:
	for item in game.equipment.items:item.node.free()
	game.equipment.items.clear()
func press(action:String,seconds:float)->void:
	await process_frame
	Input.action_press(action)
	game._update_equipment_input(seconds)
func release(action:String)->void:
	Input.action_release(action)
	game._update_equipment_input(0)
	await process_frame

func run()->void:
	var main=Main.new()
	main._setup_input()
	var defaults:Dictionary=Data.table("default_save")
	game=Session.new()
	root.add_child(game)
	check(game.start({"mapId":"desert_town","mode":"tdm","botCount":0},defaults.classes[0],defaults.settings),"Match starts")
	game.state="live"
	game.player.position=Vector3(0,80,0)
	game.player.rotation=Vector3.ZERO
	game.player.camera.rotation=Vector3.ZERO
	game.loadout.lethal="frag"
	game.loadout.tactical="flashbang"
	await physics_frame
	await physics_frame
	var distances:Array[float]=[]
	for seconds in [0.0,0.625,1.25]:
		clear_items()
		await press("lethal",seconds)
		check(game.equipment.items.is_empty(),"Holding a grenade creates no projectile or running fuse")
		check(game.hud_state().prompt.contains("%d%%"%roundi(seconds/1.25*100)),"HUD displays charge power")
		await release("lethal")
		check(game.equipment.items.size()==1,"Release throws exactly one grenade")
		var item:Dictionary=game.equipment.items[0]
		check(is_equal_approx(item.fuse,3.0),"Grenade fuse starts on release")
		var origin:Vector3=item.node.position
		for _step in 60:game.equipment.tick(1.0/60.0)
		var distance:float=Vector2(item.node.position.x-origin.x,item.node.position.z-origin.z).length()
		distances.append(distance)
		check(item.velocity.z<0,"Grenade clears its owner without bouncing backward")
	check(distances[0]>17 and distances[0]<19,"Tap throws a short lob")
	check(distances[1]>distances[0] and distances[2]>distances[1],"Physical travel increases continuously with hold time")
	check(distances[2]>50 and distances[2]>distances[0]*2.5,"Fully charged throw travels over50m in one second")
	clear_items()
	await press("tactical",5.0)
	check(game.throw_charges.tactical.seconds==1.25,"Holding beyond maximum caps power without throwing")
	await release("tactical")
	var flash:Dictionary=game.equipment.items[0]
	check(flash.id=="flashbang" and is_equal_approx(flash.fuse,1.6),"Flashbang releases with its full fuse")
	check(is_equal_approx(flash.velocity.z,-52.0),"Flashbang receives the same long-distance charge")
	clear_items()
	# A wall closer than one old0.6m geometry skip still blocks a short step.
	var wall=StaticBody3D.new()
	wall.collision_layer=2
	wall.collision_mask=0
	var shape=CollisionShape3D.new()
	shape.shape=BoxShape3D.new()
	shape.shape.size=Vector3(2,2,0.05)
	wall.add_child(shape)
	root.add_child(wall)
	wall.position=game.player.eye_position()+Vector3.FORWARD*0.2
	await physics_frame
	await physics_frame
	game.equipment.throw_item("frag",game.player,0.0)
	game.equipment.tick(1.0/60)
	check(game.equipment.items[0].velocity.z>0,"Charged short-step ray collides with nearby cover")
	wall.free()
	clear_items()
	await press("lethal",0.8)
	game.player.alive=false
	game._update_equipment_input(0.1)
	check(game.throw_charges.is_empty(),"Death cancels a held throw")
	await release("lethal")
	game.player.alive=true
	game._update_equipment_input(0.1)
	check(game.equipment.items.is_empty(),"A cancelled throw never fires after respawn")
	main.game_match=game
	main.state="playing"
	main.ui=PauseUI.new()
	await press("tactical",0.8)
	var escape=InputEventAction.new()
	escape.action="pause"
	escape.pressed=true
	main._unhandled_input(escape)
	check(main.paused and game.throw_charges.is_empty(),"Opening Escape cancels a charged throw")
	await release("tactical")
	main.resume_match()
	game._update_equipment_input(0.1)
	check(game.equipment.items.is_empty(),"Resuming does not fire a throw released while paused")
	await press("lethal",0.8)
	var console_key=InputEventKey.new()
	console_key.keycode=KEY_QUOTELEFT
	console_key.pressed=true
	main._unhandled_input(console_key)
	check(main.ui.console_open and game.throw_charges.is_empty(),"Opening console cancels charge")
	await release("lethal")
	main._unhandled_input(console_key)
	check(not main.ui.console_open and game.equipment_input_enabled,"Closing console re-enables equipment input")
	await press("lethal",0.8)
	main._notification(Main.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._update_equipment_input(0.1)
	check(game.throw_charges.is_empty(),"Focus loss cancels charge and blocks rearming while held")
	await release("lethal")
	check(game.equipment.items.is_empty(),"Focus-loss release cannot launch a stored throw")
	game.loadout.lethal="c4"
	await press("lethal",0.1)
	check(game.equipment.items.size()==1 and game.equipment.items[0].id=="c4","Other equipment still uses press-to-throw")
	await release("lethal")
	check(game.equipment.items.size()==1,"Non-charged equipment is not duplicated on release")
	clear_items()
	game.loadout.lethal="frag"
	await process_frame
	var tap=InputEventKey.new()
	tap.physical_keycode=KEY_G
	tap.pressed=true
	main._unhandled_input(tap)
	tap.pressed=false
	main._unhandled_input(tap)
	check(game.equipment.items.size()==1,"Keyboard tap entirely between physics frames still throws once")
	check(not game.equipment.items.is_empty() and absf(game.equipment.items[0].velocity.z+18.0)<0.3,"A short keyboard tap uses minimum power")
	clear_items()
	main._unhandled_input(tap)
	tap.pressed=true
	main._unhandled_input(tap)
	# No Match.tick/input poll runs during this hold: emulate a stalled renderer.
	await create_timer(1.3).timeout
	check(game.hud_state().prompt.contains("100%"),"Real hold time fills the meter even without physics updates")
	tap.pressed=false
	main._unhandled_input(tap)
	check(game.equipment.items.size()==1 and is_equal_approx(game.equipment.items[0].velocity.z,-52.0),"Slow rendering cannot reduce a fully held throw")
	main.game_match=null
	main.free()
	game.free()
	await process_frame
	print("CHARGED THROWS: %d checks, %d failures; tap/half/full travel in1s %s"%[checks,failures.size(),distances])
	quit(0 if failures.is_empty() else 1)
