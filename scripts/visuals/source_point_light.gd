class_name SourcePointLight
extends Node3D
## Three point lights join the sun/hemisphere BEFORE source ACES tone mapping.
## Godot's per-light shader callback otherwise repeats ACES/ambient per light.
const Materials=preload("res://scripts/world/map_material.gd")
var light_color:Color=Color("ffa040")
var light_energy:float=2.0
var omni_range:float=6.0
var omni_attenuation:float=2.0

func _ready()->void:
	Materials.register_point_light(self)

func _process(_dt:float)->void:
	Materials.update_point_lights()

func _exit_tree()->void:
	Materials.unregister_point_light(self)
