class_name Combatant
extends Node3D
const Weapon = preload("res://scripts/game/weapon_runtime.gd")
const Data = preload("res://scripts/core/game_data.gd")
const Visuals = preload("res://scripts/visuals/visual_factory.gd")
const QUALITY = preload("res://scripts/world/graphics_quality.gd")
const STANCES = [
	{"eye": 0.45, "body": 0.35, "height": 0.6, "speed": 0.22},
	{"eye": 1.0, "body": 0.65, "height": 1.2, "speed": 0.5},
	{"eye": 1.7, "body": 1.0, "height": 1.8, "speed": 1.0},
]
var actor_id: int = 0
var accent_index: int = -1
var display_name: String = "You"
var team: String = "blue"
var is_player: bool = false
var alive: bool = true
var health: float = 100.0
var max_health: float = 100.0
var regen_enabled: bool = true
var regen_timer: float = 5.0
var death_timer: float = 0.0
var last_damage: Dictionary = {}
var weapons: Array = []
var current_slot: int = 0
var camera: Camera3D
var viewmodel: Node3D
## Viewmodel light rig. The weapon is close to the camera, so world lighting
## alone leaves it an unreadable silhouette: AAA shooters light the viewmodel
## separately. These lights ride with the camera, which keeps the rig stable in
## world space and means it needs no per-material or per-mesh special casing.
var viewmodel_rig: Node3D
var human: Node3D
var brain
var game_match
var moving: bool = false
var firing: bool = false
var blocked: bool = false
var aim_dir = Vector3.FORWARD
var stance: int = 2
var eye_height: float = 1.7
var shift_role: String = ""
var lower_hold: float = 0.0
var ads_factor: float = 0.0
var kick: float = 0.0
var melee_time: float = 0.0
var view_reload_time:float=0.0
var view_reload_duration:float=0.0
var view_reloading:bool=false
var animation_time: float = 0.0
var stun_time: float = 0.0
var flash_time: float = 0.0
var camo_color = Color("2b2f36")
var perks: Array = []
var settings: Dictionary = {}
var path: Array[Vector3] = []
var path_index: int = 0
var weapon:
	get:
		return weapons[current_slot]

func setup(id_value: int, team_value: String, player_control: bool, loadout: Dictionary, owner_match) -> void:
	actor_id = id_value
	team = team_value
	is_player = player_control
	game_match = owner_match
	camo_color = Data.camo(str(loadout.get("camo", "gunmetal")))
	perks = loadout.get("perks", []).duplicate()
	var primary: Dictionary = loadout.get("primary", {"weaponId":"m4", "attachments":[]})
	weapons.append(Weapon.new(primary.weaponId, primary.get("attachments", [])))
	if player_control:
		var secondary: Dictionary = loadout.get("secondary", {"weaponId":"m9", "attachments":[]})
		weapons.append(Weapon.new(secondary.weaponId, secondary.get("attachments", [])))
		camera = Camera3D.new()
		camera.name = "PlayerCamera"
		camera.near = 0.05
		camera.far = 2000
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.cull_mask = 1 | (1 << (QUALITY.VIEWMODEL_LAYER - 1))
		camera.position.y = eye_height
		add_child(camera)
		camera.make_current()
		_build_viewmodel_rig()
	else:
		eye_height = 1.6
		var Brain = load("res://scripts/game/bot_brain.gd")
		brain = Brain.new(str(owner_match.config.get("difficulty", "regular")))
	refresh_visuals()

func refresh_visuals() -> void:
	if not ResourceLoader.exists("res://scripts/visuals/visual_factory.gd"):
		return
	var factory = load("res://scripts/visuals/visual_factory.gd")
	if is_player:
		for held in weapons:
			if not held.reload_started.is_connected(_reload_started):
				held.reload_started.connect(_reload_started)
		var old_root:=Transform3D(Basis.IDENTITY,Vector3(0.22,-0.2,-0.55))
		var old_gun:=Transform3D.IDENTITY
		var old_knife:=Transform3D.IDENTITY
		var was_visible:=true
		var gun_visible:=true
		var knife_visible:=false
		if is_instance_valid(viewmodel):
			old_root=viewmodel.transform
			old_gun=Visuals.part(viewmodel,"gun").transform
			gun_visible=Visuals.part(viewmodel,"gun").visible
			old_knife=Visuals.part(viewmodel,"knife").transform
			was_visible=viewmodel.visible
			knife_visible=Visuals.part(viewmodel,"knife").visible
			viewmodel.free()
		viewmodel = factory.create_weapon(str(weapon.definition.id), camo_color, weapon.attachments)
		_set_render_layer(viewmodel, QUALITY.VIEWMODEL_LAYER)
		camera.add_child(viewmodel)
		viewmodel.transform=old_root
		viewmodel.visible=was_visible
		Visuals.part(viewmodel,"gun").transform=old_gun
		Visuals.part(viewmodel,"gun").visible=gun_visible or weapon.definition.id=="knife"
		Visuals.part(viewmodel,"knife").transform=old_knife
		Visuals.part(viewmodel,"knife").visible=knife_visible
		Visuals.part(viewmodel,"knife").rotation_order=EULER_ORDER_XYZ
	elif not is_instance_valid(human):
		human = factory.create_human(team, maxi(0, actor_id - 1) if accent_index < 0 else accent_index)
		add_child(human)

## Key from the upper left, a cool fill from the opposite side to keep the
## shadowed face readable, and a tight rim behind the shooter so the weapon edge
## separates from the background. All unshadowed: the rig is only a few tens of
## centimetres deep, so shadowing it would cost far more than it could show.
func _build_viewmodel_rig() -> void:
	viewmodel_rig = Node3D.new()
	viewmodel_rig.name = "ViewmodelRig"
	camera.add_child(viewmodel_rig)
	var key := OmniLight3D.new()
	key.name = "ViewmodelKey"
	key.light_color = Color("fff1dc")
	key.light_energy = 1.7
	key.omni_range = 2.2
	key.omni_attenuation = 1.2
	key.shadow_enabled = false
	key.light_cull_mask = 1 << (QUALITY.VIEWMODEL_LAYER - 1)
	key.position = Vector3(-0.55, 0.85, 0.35)
	viewmodel_rig.add_child(key)
	var fill := OmniLight3D.new()
	fill.name = "ViewmodelFill"
	fill.light_color = Color("a9c6ee")
	fill.light_energy = 0.85
	fill.omni_range = 2.4
	fill.omni_attenuation = 1.2
	fill.shadow_enabled = false
	fill.light_cull_mask = 1 << (QUALITY.VIEWMODEL_LAYER - 1)
	fill.position = Vector3(0.75, -0.35, 0.15)
	viewmodel_rig.add_child(fill)
	var rim := OmniLight3D.new()
	rim.name = "ViewmodelRim"
	rim.light_color = Color("ffe6c0")
	rim.light_energy = 1.4
	rim.omni_range = 2.0
	rim.omni_attenuation = 1.4
	rim.shadow_enabled = false
	rim.light_cull_mask = 1 << (QUALITY.VIEWMODEL_LAYER - 1)
	rim.position = Vector3(0.15, 0.45, -1.4)
	viewmodel_rig.add_child(rim)

## Moves a model's meshes onto the viewmodel layer, which is what keeps the
## camera-mounted rig from lighting the world as well as the weapon.
func _set_render_layer(node: Node, layer: int) -> void:
	if node is MeshInstance3D:
		node.layers = 1 << (layer - 1)
	for child in node.get_children():
		_set_render_layer(child, layer)

## The rig is the only lighting the player can see on their own weapon, so every
## band keeps the key light; the cheaper bands drop the fill and rim, which are
## the two lights whose contribution is least missed at speed.
func apply_quality(level: String = "") -> void:
	if not is_instance_valid(viewmodel_rig):
		return
	var settings := QUALITY.preset(level)
	var fill := viewmodel_rig.get_node_or_null("ViewmodelFill")
	var rim := viewmodel_rig.get_node_or_null("ViewmodelRim")
	var full := float(settings.viewmodel_detail) >= 1.0
	if fill: fill.visible = full
	if rim: rim.visible = full

func apply_settings(value: Dictionary) -> void:
	settings = value
	if camera:
		camera.fov = float(value.get("fov", 75))

func set_hardcore() -> void:
	max_health = 30.0
	health = 30.0
	regen_enabled = false

func eye_position() -> Vector3:
	return position + Vector3.UP * eye_height

func body_position() -> Vector3:
	return position + Vector3.UP * (float(STANCES[stance].body) if is_player else 1.0)

func aim_direction() -> Vector3:
	return -camera.global_basis.z if is_player else aim_dir

func apply_recoil(pitch: float, yaw: float) -> void:
	if is_player:
		camera.rotation.x = clampf(camera.rotation.x + pitch, -PI/2 + 0.01, PI/2 - 0.01)
		rotation.y += yaw

func look_motion(delta: Vector2) -> void:
	var sensitivity = float(settings.get("sensitivity", 1.0)) * 0.002
	rotation.y -= delta.x * sensitivity
	var invert = -1.0 if settings.get("invertY", false) else 1.0
	camera.rotation.x = clampf(camera.rotation.x - delta.y * sensitivity * invert, -PI/2 + 0.01, PI/2 - 0.01)

func on_shot() -> void:
	kick = minf(1.0, kick + 0.5)
	game_match.shot_fired(self)

func _reload_started(_empty:bool,duration:float)->void:
	view_reload_time=0.0
	view_reload_duration=maxf(0.1,duration)
	view_reloading=true
	game_match.reload_started(self)

func melee_slash()->void:
	melee_time=0.3
	if viewmodel:
		var knife=Visuals.part(viewmodel,"knife")
		knife.visible=true
		knife.position=Vector3(-0.35,-0.16,-0.55)
		knife.rotation=Vector3(0.2,-1.2,-0.6)

func select_weapon(slot: int) -> void:
	if slot < 0 or slot >= weapons.size() or slot == current_slot:
		return
	current_slot = slot
	weapon.swap_in()
	refresh_visuals()

func set_weapon(id_value: String, selected: Array = []) -> void:
	weapons = [Weapon.new(id_value, selected)]
	current_slot = 0
	if is_player:weapon.swap_in()
	refresh_visuals()

func apply_damage(amount: float, source, weapon_id: String, headshot: bool = false) -> void:
	if not alive:
		return
	health = maxf(0.0, health - amount)
	regen_timer = 0.0
	last_damage = {"sourceId": source.actor_id if source != null else -1, "weaponId": weapon_id, "headshot":headshot, "amount": amount}
	game_match.actor_damaged(self, source, amount)
	if health <= 0:
		alive = false
		death_timer = 0.0
		firing = false
		weapon.trigger = false
		game_match.actor_killed(self, source, weapon_id, headshot)
		# Let the death callback snapshot the dropped weapon's spent ammo first.
		# Remote actors override apply_damage, so only the owning peer resets it.
		reset_loadout_for_life()

func reset_loadout_for_life() -> void:
	for held in weapons:held.reset_for_life()
	firing=false
	ads_factor=0.0
	kick=0.0
	melee_time=0.0
	view_reload_time=0.0
	view_reload_duration=0.0
	view_reloading=false
	if viewmodel:
		var knife=Visuals.part(viewmodel,"knife")
		if knife:knife.visible=false
		_update_viewmodel(0.0)

func spawn_at(point: Vector3, yaw: float = 0.0) -> void:
	reset_loadout_for_life()
	position = point
	# Source Player.spawnAt retains the player's look direction. Bot respawn
	# applies the pad yaw; resetting the human camera would snap their aim.
	if not is_player:
		rotation = Vector3(0.0, yaw, 0.0)
	health = max_health
	alive = true
	death_timer = 0.0
	stance = 2
	shift_role = ""
	lower_hold = 0.0
	eye_height = 1.7 if is_player else 1.6
	path.clear()
	path_index = 0
	if camera:
		camera.position.y = eye_height
	if human:
		human.rotation = Vector3.ZERO
	if viewmodel:
		viewmodel.visible = true

func tick(dt: float) -> void:
	animation_time += dt
	stun_time = maxf(0.0, stun_time - dt)
	flash_time = maxf(0.0, flash_time - dt)
	if not alive:
		death_timer += dt
		_animate(dt)
		return
	if is_player:
		_player_tick(dt)
	else:
		brain.tick(self, dt, game_match)
	_animate(dt)

func _player_tick(dt: float) -> void:
	regen_timer += dt
	if regen_enabled and regen_timer >= 5.0:
		health = minf(max_health, health + 35.0 * dt)
	if not Input.is_action_pressed("streaks"):
		if Input.is_action_just_pressed("weapon_primary"):
			select_weapon(0)
		if Input.is_action_just_pressed("weapon_secondary"):
			select_weapon(1)
	if Input.is_action_just_pressed("weapon_next"):
		select_weapon((current_slot + 1) % weapons.size())
	var target_ads = 1.0 if Input.is_action_pressed("ads") and weapon.definition.id != "knife" else 0.0
	# Source feeds this frame's weapon the previous viewmodel ADS value, then
	# advances the viewmodel. Preserve its first-frame spread during transitions.
	weapon.ads_factor = ads_factor
	weapon.trigger = Input.is_action_pressed("fire")
	firing = weapon.trigger
	if Input.is_action_just_pressed("reload"):
		weapon.reload()
	weapon.tick(dt, self, game_match)
	ads_factor = 0.0 if weapon.definition.id == "knife" else move_toward(ads_factor, target_ads, dt / maxf(0.05, float(weapon.stats.adsTime)))
	_update_viewmodel(dt)
	var forward_input = Input.get_axis("back", "forward")
	var right_input = Input.get_axis("left", "right")
	if Input.is_action_just_pressed("sprint"):
		shift_role = "sprint" if forward_input > 0 and stance == 2 else "stance"
		if shift_role == "stance":
			stance = maxi(0, stance - 1)
			lower_hold = 0.0
	if not Input.is_action_pressed("sprint"):
		shift_role = ""
	if Input.is_action_just_pressed("crouch"):
		stance = maxi(0, stance - 1)
		lower_hold = 0.0
	if stance!=0 and (Input.is_action_pressed("crouch") or (Input.is_action_pressed("sprint") and shift_role == "stance")):
		lower_hold += dt
		if lower_hold >= 0.45:
			stance = maxi(0, stance - 1)
			lower_hold = 0.0
	if Input.is_action_just_pressed("jump"):
		stance = mini(2, stance + 1)
	var sprinting = stance == 2 and shift_role == "sprint" and Input.is_action_pressed("sprint")
	var speed = (7.5 if sprinting else 5.0) * float(STANCES[stance].speed) * float(weapon.stats.mobility) / 80.0
	var forward = -basis.z
	var right = basis.x
	position += (forward * forward_input + right * right_input) * speed * dt
	position.y = game_match.map.height_at(position.x, position.z)
	position = game_match.map.resolve_position(position, 0.4, float(STANCES[stance].height))
	moving = absf(forward_input) + absf(right_input) > 0
	eye_height = lerpf(eye_height, float(STANCES[stance].eye), minf(1.0, dt * 10.0))
	camera.position.y = eye_height

func _update_viewmodel(dt:float)->void:
	kick = maxf(0.0, kick - dt * 6.0)
	if viewmodel:
		viewmodel.position = Vector3(0.22, -0.2, -0.55).lerp(Vector3(0, -0.13, -0.4), ads_factor)
		var dip:=0.0
		if view_reloading:
			view_reload_time+=dt
			dip=sin(minf(1.0,view_reload_time/view_reload_duration)*PI)
			if view_reload_time>=view_reload_duration:view_reloading=false
		var gun = Visuals.part(viewmodel,"gun")
		var knife = Visuals.part(viewmodel,"knife")
		if melee_time>0 and knife:
			melee_time=maxf(0,melee_time-dt)
			var progress=1.0-melee_time/0.3
			if progress<1.0:
				var lift=sin(progress*PI)
				knife.position=Vector3(-0.35+0.7*progress,-0.16+0.04*lift,-0.55)
				knife.rotation=Vector3(0.2-0.3*lift,-1.2+2.4*progress,-0.6+0.4*lift)
			knife.visible=progress<1.0
		if gun:
			gun.visible=melee_time<=0.0
			if melee_time<=0.0:
				gun.position=Vector3(0,-0.12*dip+kick*0.06,0)
				gun.rotation=Vector3(kick*0.12+dip*0.5,0,0)

func step_toward(destination: Vector3, speed: float, dt: float) -> bool:
	var direction = Vector3(destination.x - position.x, 0, destination.z - position.z)
	if direction.length() < 0.15:
		blocked = false
		return false
	direction = direction.normalized()
	var step = speed * dt
	var old_position = position
	position.x += direction.x * step
	position = game_match.map.resolve_position(position, 0.4, 1.8)
	position.z += direction.z * step
	position.y = game_match.map.height_at(position.x, position.z)
	position = game_match.map.resolve_position(position, 0.4, 1.8)
	blocked = step > 0.00001 and Vector2(position.x - old_position.x, position.z - old_position.z).length() < step * 0.3
	return true

func move_speed() -> float:
	return 5.0 * float(weapon.stats.mobility) / 85.0

func _animate(dt: float) -> void:
	if human:
		human.rotation=Vector3.ZERO
		var animation = "die" if not alive else ("shoot" if firing else ("run" if moving else "idle"))
		Visuals.animate_human(human, animation, animation_time, dt)
		if not alive:
			# Source Bot's character root owns both angles in Three XYZ order.
			# Undo the native parent yaw before applying that combined matrix.
			var death_basis:=Basis.from_euler(Vector3(human.rotation.x,rotation.y,0),EULER_ORDER_XYZ)
			var body_scale:Vector3=human.scale
			human.basis=basis.inverse()*death_basis.scaled(body_scale)
