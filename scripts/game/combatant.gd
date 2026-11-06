class_name Combatant
extends Node3D
const Weapon = preload("res://scripts/game/weapon_runtime.gd")
const Data = preload("res://scripts/core/game_data.gd")
const Visuals = preload("res://scripts/visuals/visual_factory.gd")
const QUALITY = preload("res://scripts/world/graphics_quality.gd")
const Materials = preload("res://scripts/world/map_material.gd")
const Sights = preload("res://scripts/game/sights.gd")
## Distance from the eye to the aimed lens at full aim, in metres. A reflex
## window sits far enough out that its housing frames rather than fills the view;
## a scope comes close, because the eyepiece takes over at the end of the raise.
const EYE_RELIEF := {"reflex": 0.17, "scope": 0.16, "iron": 0.3}
## Iron sights line up the top of the rear sight just under the point of aim.
const IRON_SIGHT_LIFT := 0.004
## Fraction of the aim raise over which a sight window opens, and over which a
## scope's eyepiece picture takes over the view.
const WINDOW_OPEN := Vector2(0.3, 0.8)
const SCOPE_IN := Vector2(0.72, 0.96)
## Radius of the eyepiece picture as a fraction of screen height (sight_overlay).
const SCOPE_APERTURE := 0.47
## The bore is a little narrower than the lens, leaving the tube a visible wall.
const BORE_FILL := 0.9
## Share of the weapon's own kick left at full aim.
const ADS_KICK := 0.15
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
var radar_shots := 0
var radar_last_shot := -100.0
var radar_shot_position := Vector3.ZERO
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
## Aim-down-sight state of the active weapon; see `_configure_sight`.
var sight: Dictionary = Sights.NONE
var ads_position: Vector3 = Visuals.ADS_POSITION
var base_fov := 75.0
## Current magnification (1 at the hip) and how much of the view the scope's
## eyepiece picture covers (0..1).
var zoom := 1.0
var scope_amount := 0.0
## View-space cone of the see-through window: unit direction and the cosine of
## its half-angle. A cosine above one means closed.
var sight_window := Vector4(0.0, 0.0, -1.0, 2.0)
var _sight_lens: MeshInstance3D
var _sight_lens_center := Vector3.ZERO
var _sight_lens_radius := 0.0
## How far the housing's rear opening sits behind the lens, toward the eye.
var _sight_rear_offset := 0.0
var _sight_materials: Array[ShaderMaterial] = []
var _scope_hidden := false
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
		_configure_sight()
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
	base_fov = float(value.get("fov", 75))
	if camera:
		# Replays reuse this camera, and must not inherit an aimed-in zoom.
		camera.set_meta("base_fov", base_fov)
		camera.fov = Sights.zoomed_fov(base_fov, zoom)

## Finds the aimed optic and solves the full-aim position that puts it on the
## line of fire. The viewmodel's ADS root is derived from the lens itself, so
## every sight, fitted or built in, ends exactly on the camera axis at its eye
## relief instead of at one shared offset that left most of them under the
## crosshair. Reflex sights and scopes also get the window material; the model
## reticle, a broad ring meant to be seen from the front, is hidden because the
## HUD projects the reticle at the point of aim, where a real one appears.
func _configure_sight() -> void:
	sight = Sights.profile(str(weapon.definition.id), weapon.attachments)
	ads_position = Visuals.ADS_POSITION
	_sight_lens = null
	_sight_materials.clear()
	sight_window = Vector4(0.0, 0.0, -1.0, 2.0)
	var gun := Visuals.part(viewmodel, "gun")
	if gun == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(gun, meshes)
	var kind: String = sight.kind
	if kind in ["reflex", "scope"]:
		for mesh: MeshInstance3D in meshes:
			var key := String(mesh.name)
			if key.ends_with("reticle"):
				mesh.visible = false
			elif key.ends_with("lens") and mesh.visible and _sight_lens == null:
				_sight_lens = mesh
		if _sight_lens == null:
			kind = "iron"
	if kind in ["reflex", "scope"]:
		var box: AABB = _sight_lens.mesh.get_aabb()
		var to_gun := _relative_transform(_sight_lens, gun)
		var on_gun: AABB = to_gun * box
		# The lens is a disc facing down the barrel (the gun's Z axis).
		_sight_lens_center = box.get_center()
		_sight_lens_radius = minf(on_gun.size.x, on_gun.size.y) * 0.5
		var lens_on_gun: Vector3 = to_gun * _sight_lens_center
		ads_position = Vector3(0.0, 0.0, -float(EYE_RELIEF[kind])) - lens_on_gun
		# The housing around the lens: the attachment's body or the built-in optic.
		_sight_rear_offset = 0.0
		for mesh: MeshInstance3D in meshes:
			var key := String(mesh.name)
			if mesh.visible and (key.ends_with("__body") or key.ends_with("__optic")):
				var housing: AABB = _relative_transform(mesh, gun) * mesh.mesh.get_aabb()
				if Rect2(housing.position.x, housing.position.y, housing.size.x, housing.size.y).has_point(Vector2(lens_on_gun.x, lens_on_gun.y)):
					_sight_rear_offset = maxf(_sight_rear_offset, housing.end.z - lens_on_gun.z)
		for mesh: MeshInstance3D in meshes:
			if not mesh.has_meta("material_source"):
				continue
			var source: Dictionary = mesh.get_meta("material_source")
			source.sightWindow = true
			var material := Materials.create_material(source, Visuals.environment)
			mesh.material_override = material
			_sight_materials.append(material)
	elif kind == "iron":
		# Line up the top of the rear sight, or of the whole weapon for guns
		# modelled without one, just under the point of aim.
		var rear := AABB()
		var found := false
		for mesh: MeshInstance3D in meshes:
			if String(mesh.name).ends_with("sights") and mesh.visible:
				rear = _relative_transform(mesh, gun) * mesh.mesh.get_aabb()
				found = true
				break
		if not found:
			for mesh: MeshInstance3D in meshes:
				if not mesh.visible or mesh.mesh == null or _has_ancestor(mesh, Visuals.part(viewmodel, "knife")):
					continue
				var box: AABB = _relative_transform(mesh, gun) * mesh.mesh.get_aabb()
				rear = box if not found else rear.merge(box)
				found = true
		if found:
			var point := Vector3(rear.get_center().x, rear.end.y + IRON_SIGHT_LIFT, rear.end.z)
			ads_position = Vector3(0.0, 0.0, -float(EYE_RELIEF.iron)) - point
	# A replacement viewmodel inherits the old one's visibility; undo only a hide
	# the scope made, and let the next update decide again.
	if _scope_hidden and viewmodel:
		viewmodel.visible = true
	_scope_hidden = false

func _collect_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		into.append(node)
	for child in node.get_children():
		_collect_meshes(child, into)

static func _has_ancestor(node: Node, ancestor: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false

## Transform from `node` into `ancestor`'s space, accumulated through the local
## transforms so it also works before the viewmodel enters the tree.
static func _relative_transform(node: Node, ancestor: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

## Mouse, stick and touch look slow down with magnification, so a 6x scope
## turns the same on-screen distance per hand movement as the hip view.
func look_scale() -> float:
	return 1.0 / maxf(zoom, 1.0)

## The sight picture the HUD draws. `window` is the see-through window projected
## to the screen: centre as a fraction of the viewport and radius as a fraction
## of its height.
func sight_state() -> Dictionary:
	var state := {"kind": str(sight.get("kind", "none")), "reticle": str(sight.get("reticle", "")), "name": str(sight.get("name", "")),
		"ads": ads_factor, "zoom": zoom, "scope": scope_amount, "kick": kick}
	if sight_window.w <= 1.0 and camera and camera.is_inside_tree():
		var viewport_size := camera.get_viewport().get_visible_rect().size
		var axis := Vector3(sight_window.x, sight_window.y, sight_window.z)
		if viewport_size.y > 0.0 and axis.z < -0.001:
			var side := axis.cross(Vector3.UP).normalized()
			var rim := axis + side * tan(acos(clampf(sight_window.w, -1.0, 1.0)))
			var centre := camera.unproject_position(camera.to_global(axis))
			var edge := camera.unproject_position(camera.to_global(rim))
			state.window = Vector3(centre.x / viewport_size.x, centre.y / viewport_size.y, centre.distance_to(edge) / viewport_size.y)
	return state

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
	var sensitivity = float(settings.get("sensitivity", 1.0)) * 0.002 * look_scale()
	rotation.y -= delta.x * sensitivity
	var invert = -1.0 if settings.get("invertY", false) else 1.0
	camera.rotation.x = clampf(camera.rotation.x - delta.y * sensitivity * invert, -PI/2 + 0.01, PI/2 - 0.01)

func on_shot() -> void:
	radar_shots += 1
	radar_last_shot = game_match.ui_time
	radar_shot_position = position
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
	# A scope comes off the eye to reload, so the reload is seen rather than
	# hidden behind a frozen eyepiece picture.
	if sight.get("kind", "") == "scope" and weapon.state == "reloading":
		target_ads = 0.0
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
		viewmodel.position = Visuals.HIP_POSITION.lerp(ads_position, ads_factor)
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
				# Aimed, a shot's climb is carried by the camera; the weapon stays on
				# the eye, or full-auto kick would lift the sight off the aim point.
				var recoil:=kick*lerpf(1.0,ADS_KICK,ads_factor)
				gun.position=Vector3(0,-0.12*dip+recoil*0.06,0)
				gun.rotation=Vector3(recoil*0.12+dip*0.5,0,0)
	_update_sight()

## Zoom, the scope's eyepiece picture and the see-through window all follow the
## aim raise. A scope keeps most of its magnification for the end of the raise,
## where the eye meets the eyepiece; before that the rising housing would only
## be blown up. Once the eyepiece picture covers the view the weapon itself is
## hidden, which also spares drawing it behind a full-screen scope.
func _update_sight() -> void:
	if not camera:
		return
	var aim := ads_factor if alive else 0.0
	var kind: String = sight.get("kind", "none")
	var ramp := smoothstep(0.35, 0.95, aim) if kind == "scope" else smoothstep(0.0, 1.0, aim)
	zoom = lerpf(1.0, float(sight.get("zoom", 1.0)), ramp)
	camera.fov = Sights.zoomed_fov(base_fov, zoom)
	scope_amount = smoothstep(SCOPE_IN.x, SCOPE_IN.y, aim) if kind == "scope" and is_instance_valid(_sight_lens) else 0.0
	var hide := scope_amount >= 0.999
	if viewmodel and hide != _scope_hidden:
		viewmodel.visible = not hide
		_scope_hidden = hide
	_update_sight_window(aim)

## The window is the cone from the eye through the bore of the aimed optic,
## opening over the raise. It is sized at the housing's rear opening, the part
## nearest the eye, so the housing reads as a thin-walled tube rather than a
## block with a small hole at the far end. A scope's window then widens to the
## eyepiece picture's own aperture, so the moment the weapon is hidden behind a
## full scope changes nothing on screen.
func _update_sight_window(aim: float) -> void:
	var window := Vector4(0.0, 0.0, -1.0, 2.0)
	var opening := smoothstep(WINDOW_OPEN.x, WINDOW_OPEN.y, aim)
	if is_instance_valid(_sight_lens) and opening > 0.0 and melee_time <= 0.0 and viewmodel and viewmodel.visible:
		var to_camera := _relative_transform(_sight_lens, camera)
		var centre: Vector3 = to_camera * _sight_lens_center
		var distance := centre.length()
		var rear := (centre + (_relative_transform(Visuals.part(viewmodel, "gun"), camera).basis * Vector3.BACK).normalized() * _sight_rear_offset).length()
		if distance > 0.001 and rear > 0.001:
			var spread := _sight_lens_radius * BORE_FILL * opening / minf(rear, distance)
			if scope_amount > 0.0:
				var aperture := SCOPE_APERTURE * 2.0 * tan(deg_to_rad(camera.fov) * 0.5)
				spread = lerpf(spread, maxf(spread, aperture), scope_amount)
			var axis := centre / distance
			window = Vector4(axis.x, axis.y, axis.z, cos(atan(spread)))
	if window != sight_window:
		sight_window = window
		for material: ShaderMaterial in _sight_materials:
			material.set_shader_parameter("sight_window", window)

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
