class_name SourceShadow
extends Node3D
## Three's one fixed orthographic shadow camera, rendered without modifying
## gameplay nodes. Proxies reuse source mesh data and track animated transforms.
const Materials=preload("res://scripts/world/map_material.gd")
const DEPTH=preload("res://scripts/world/source_shadow_depth.gdshader")
const RESOLUTION=2048
const RADIUS=40.0
var direction:Vector3=Vector3(0.5,1,0.35).normalized()
var viewport:SubViewport
var camera:Camera3D
var proxies:Dictionary={}
var _single:ShaderMaterial
var _double:ShaderMaterial
var _scope:Viewport
var _frame:int=0
var _dirty:=true
var _last_camera:=Transform3D.IDENTITY
var _map_root:Node

func _ready()->void:
	name="SourceShadow"
	process_priority=100
	_scope=get_viewport()
	_map_root=get_parent()
	viewport=SubViewport.new()
	viewport.name="Depth2048"
	viewport.size=Vector2i(RESOLUTION,RESOLUTION)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	viewport.disable_3d=false
	add_child(viewport)
	var world=WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color.WHITE
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED
	world.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	viewport.add_child(world)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=RADIUS*2.0
	camera.near=0.5
	camera.far=200.0
	viewport.add_child(camera)
	camera.current=true
	_single=ShaderMaterial.new()
	_single.shader=DEPTH
	_double=ShaderMaterial.new()
	var shader=Shader.new()
	shader.code=DEPTH.code.replace("cull_front","cull_disabled")
	_double.shader=shader
	get_tree().node_added.connect(_node_added)
	get_tree().node_removed.connect(_node_removed)

func _process(_dt:float)->void:
	var active=_scope.get_camera_3d()
	if active==null:return
	var changed=_dirty
	if _dirty:
		_frame+=1
		_sync(_scope)
		_dirty=false
	var texels=RESOLUTION/(RADIUS*2.0)
	var focus=active.global_position
	focus=Vector3(floor(focus.x*texels+0.5),floor(focus.y*texels+0.5),floor(focus.z*texels+0.5))/texels
	camera.look_at_from_position(focus+direction*88.0,focus,Vector3.UP)
	if camera.transform!=_last_camera:
		changed=true
		_last_camera=camera.transform
	for id in proxies:
		var entry:Dictionary=proxies[id]
		var source=entry.source.get_ref()
		if not is_instance_valid(source):continue
		var visible_now:bool=source.is_visible_in_tree()
		if visible_now!=entry.node.visible:
			entry.node.visible=visible_now
			changed=true
		if entry.dynamic and visible_now and entry.node.transform!=source.global_transform:
			entry.node.transform=source.global_transform
			changed=true
	if changed:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	Materials.set_source_shadow(get_instance_id(),viewport.get_texture(),camera.global_transform.affine_inverse())

func _node_added(node:Node)->void:
	if node is GeometryInstance3D and node.get_viewport()==_scope:_dirty=true

func _node_removed(node:Node)->void:
	var id=node.get_instance_id()
	if proxies.has(id):
		proxies[id].node.queue_free()
		proxies.erase(id)
		_dirty=true

func _sync(node:Node)->void:
	if node==self or (node is SubViewport):return
	if node is GeometryInstance3D and (node is MeshInstance3D or node is MultiMeshInstance3D):
		if node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			var id=node.get_instance_id()
			if not proxies.has(id):
				var proxy:GeometryInstance3D
				if node is MultiMeshInstance3D:
					proxy=MultiMeshInstance3D.new()
					proxy.multimesh=node.multimesh
				else:
					proxy=MeshInstance3D.new()
					proxy.mesh=node.mesh
				var double_sided=node.material_override is ShaderMaterial and "cull_disabled" in node.material_override.shader.code
				proxy.material_override=_double if double_sided else _single
				proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				viewport.add_child(proxy)
				proxies[id]={"node":proxy,"seen":_frame,"source":weakref(node),"dynamic":not _map_root.is_ancestor_of(node)}
			proxies[id].seen=_frame
			proxies[id].node.transform=node.global_transform
	for child in node.get_children():_sync(child)

func _exit_tree()->void:
	Materials.clear_source_shadow(get_instance_id())
