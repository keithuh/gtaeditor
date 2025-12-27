@icon("res://addons/tessarakkt.oceanfft/icons/OceanEnvironment.svg")
extends Node
class_name Ocean

@export var ocean:Ocean3D
@export var material:ShaderMaterial = preload("res://addons/tessarakkt.oceanfft/Ocean.tres")

func _ready() -> void:
	if ocean and not ocean.initialized:
		ocean.initialize_simulation()
		print("ocean initialized")

func _process(delta:float) -> void:
	if not ocean.initialized:
		ocean.initialize_simulation()
	ocean.simulate(delta)
