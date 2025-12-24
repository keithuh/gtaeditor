extends Node

@onready var world := Node3D.new()

func _ready() -> void:
	# TODO: load all map
	add_child(world)
