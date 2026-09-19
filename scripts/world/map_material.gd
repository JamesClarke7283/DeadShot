class_name MapMaterial
extends RefCounted
## Source-exact material palette and three-band toon ramp shared by maps/models.

const TOON: Shader = preload("res://scripts/world/toon.gdshader")
const OUTLINE: Shader = preload("res://scripts/world/outline.gdshader")
static var _variants: Dictionary = {}
static var _live_materials: Array[WeakRef] = []
static var _shadow_materials: Array[WeakRef] = []
static var _point_lights: Array[WeakRef] = []
static var _light_frame: int = -1
const MAX_POINT_LIGHTS := 32
static var _light_positions := PackedVector4Array()
static var _light_colors := PackedVector4Array()
static var _light_count := 0
static var _shadow_owner:int=0
static var _shadow_texture:Texture2D
static var _shadow_view:=Transform3D.IDENTITY

static func color_from_array(values: Array, fallback: Color = Color.WHITE) -> Color:
	if values.size() < 3:
		return fallback
	return Color(float(values[0]), float(values[1]), float(values[2]), 1.0)

static func _rgb(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func create_material(record: Dictionary, environment: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if bool(record.get("outline", false)):
		material.shader = OUTLINE
		material.set_shader_parameter("base_color", _rgb(record.get("color", [0.00303527, 0.00303527, 0.00303527])))
		material.set_shader_parameter("thickness", float(record.get("thickness", 0.03)))
		material.render_priority = -1
		return material
	var transparent := bool(record.get("transparent", false))
	var double_side := bool(record.get("doubleSide", false))
	var depth_test := bool(record.get("depthTest", true))
	var depth_write := bool(record.get("depthWrite", true))
	var additive := bool(record.get("additive", false))
	var variant_key := "%s_%s_%s_%s_%s" % [transparent, double_side, depth_test, depth_write, additive]
	if not _variants.has(variant_key):
		var shader := Shader.new()
		var code: String = TOON.code
		if double_side:
			code = code.replace("cull_back", "cull_disabled")
		if not depth_test:
			code = code.replace("fog_disabled", "fog_disabled, depth_test_disabled")
		if not depth_write:
			code = code.replace("fog_disabled", "fog_disabled, depth_draw_never")
		elif transparent:
			code = code.replace("fog_disabled", "fog_disabled, depth_draw_always")
		if additive:
			code = code.replace("render_mode ", "render_mode blend_add, ")
		if transparent:
			code = code.replace("// ALPHA is inserted only in the transparent material variant.", "ALPHA = opacity;")
		shader.code = code
		_variants[variant_key] = shader
	material.shader = _variants[variant_key]
	material.set_shader_parameter("base_color", _rgb(record.get("color", [1, 1, 1])))
	material.set_shader_parameter("emissive_color", _rgb(record.get("emissive", [0, 0, 0])))
	material.set_shader_parameter("bands", float(record.get("steps", 3)))
	material.set_shader_parameter("opacity", float(record.get("opacity", 1)))
	material.set_shader_parameter("wind_strength", float(record.get("windStrength", 0)))
	material.set_shader_parameter("unlit", bool(record.get("unlit", false)))
	material.set_shader_parameter("raw_unlit", bool(record.get("rawUnlit", false)))
	material.set_shader_parameter("receive_shadows", bool(record.get("receiveShadows", false)))
	apply_environment(material, environment)
	if not bool(record.get("unlit",false)):_live_materials.append(weakref(material))
	if bool(record.get("receiveShadows",false)):_shadow_materials.append(weakref(material))
	if _light_positions.is_empty():
		_light_positions.resize(MAX_POINT_LIGHTS)
		_light_colors.resize(MAX_POINT_LIGHTS)
	_apply_point_lights(material)
	_apply_source_shadow(material)
	return material

static func apply_environment(material: ShaderMaterial, environment: Dictionary) -> void:
	material.set_shader_parameter("hemisphere_sky", _rgb(environment.get("skyColor", [0.520, 0.768, 1.0])))
	material.set_shader_parameter("hemisphere_ground", _rgb(environment.get("groundColor", [0.068, 0.102, 0.042])))
	material.set_shader_parameter("hemisphere_intensity", float(environment.get("hemiIntensity", 1.0)))
	material.set_shader_parameter("fog_color", _rgb(environment.get("fogColor", [0.5, 0.5, 0.5])))
	material.set_shader_parameter("fog_near", float(environment.get("fogNear", 70.0)))
	material.set_shader_parameter("fog_far", float(environment.get("fogFar", 260.0)))
	material.set_shader_parameter("exposure", float(environment.get("exposure", 1.05)))

static func _apply_point_lights(material:ShaderMaterial)->void:
	material.set_shader_parameter("source_light_count",_light_count)
	material.set_shader_parameter("source_light_positions",_light_positions)
	material.set_shader_parameter("source_light_colors",_light_colors)

static func register_point_light(light:Node3D)->void:
	_point_lights.append(weakref(light))
	update_point_lights(true)

static func unregister_point_light(light:Node3D)->void:
	for i in range(_point_lights.size()-1,-1,-1):
		if _point_lights[i].get_ref()==light:_point_lights.remove_at(i)
	update_point_lights(true)

static func update_point_lights(force:bool=false)->void:
	var frame:=Engine.get_process_frames()
	if not force and frame==_light_frame:return
	_light_frame=frame
	_light_count=0
	if _light_positions.is_empty():
		_light_positions.resize(MAX_POINT_LIGHTS)
		_light_colors.resize(MAX_POINT_LIGHTS)
	for i in range(_point_lights.size()-1,-1,-1):
		var light=_point_lights[i].get_ref()
		if not is_instance_valid(light):
			_point_lights.remove_at(i)
			continue
		if not light.is_inside_tree() or not light.is_visible_in_tree() or _light_count>=MAX_POINT_LIGHTS:continue
		var point:Vector3=light.global_position
		var color:Color=light.light_color.srgb_to_linear()
		_light_positions[_light_count]=Vector4(point.x,point.y,point.z,light.omni_range)
		_light_colors[_light_count]=Vector4(color.r*light.light_energy,color.g*light.light_energy,color.b*light.light_energy,light.omni_attenuation)
		_light_count+=1
	for i in range(_live_materials.size()-1,-1,-1):
		var material=_live_materials[i].get_ref()
		if material==null:_live_materials.remove_at(i)
		else:_apply_point_lights(material)

static func _apply_source_shadow(material:ShaderMaterial)->void:
	if not material.get_shader_parameter("receive_shadows"):return
	material.set_shader_parameter("source_shadow_enabled",_shadow_owner!=0)
	if _shadow_texture!=null:
		material.set_shader_parameter("source_shadow_texture",_shadow_texture)
		material.set_shader_parameter("source_shadow_view",_shadow_view)

static func set_source_shadow(owner_id:int,texture:Texture2D,view:Transform3D)->void:
	if _shadow_owner==owner_id and _shadow_view==view and _shadow_texture==texture:return
	_shadow_owner=owner_id
	_shadow_texture=texture
	_shadow_view=view
	for i in range(_shadow_materials.size()-1,-1,-1):
		var material=_shadow_materials[i].get_ref()
		if material==null:_shadow_materials.remove_at(i)
		else:_apply_source_shadow(material)

static func clear_source_shadow(owner_id:int)->void:
	if _shadow_owner!=owner_id:return
	_shadow_owner=0
	_shadow_texture=null
	for reference in _shadow_materials:
		var material=reference.get_ref()
		if material!=null:material.set_shader_parameter("source_shadow_enabled",false)
