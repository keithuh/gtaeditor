extends Node

var items: Dictionary[int, ItemDef]
var itemchilds: Array[TDFX]
var placements: Array[ItemPlacement]
var collisions: Array[ColFile]
var map: Node3D
var _loaded := false

var streaming_distance := 300.0
var active_instances: Dictionary[ItemPlacement, Node3D] = {}
var camera: Camera3D

#var stream_files: Array[String] = []

func _ready() -> void:
	var file := FileAccess.open(GameManager.gta_path + "data/gta.dat", FileAccess.READ)
	assert(file != null, "%d" % FileAccess.get_open_error())
	while not file.eof_reached():
		var line := file.get_line()
		if not line.begins_with("#"):
			var tokens := line.split(" ", false)
			if tokens.size() > 0:
				match tokens[0]:
					"IDE":
						_read_map_data(tokens[1], _read_ide_line, "")
					"COLFILE":
						var colfile := AssetLoader.open(GameManager.gta_path + tokens[2])
						
						while colfile.get_position() < colfile.get_length():
							collisions.append(ColFile.new(colfile))
					"IPL":
						var ipl_path: String = tokens[1]
						print("Loading IPL: %s" % ipl_path)
						_read_map_data(ipl_path, _read_ipl_line, ipl_path)
					"IMG":
						# only load gta3.img for the models
						var img_path: String = tokens[1].to_lower()
						if "gta3.img" in img_path:
							AssetLoader.load_cd_image(tokens[1])
						else:
							push_warning("Skipping IMG file: %s (only loading gta3.img)" % tokens[1])
					_:
						push_warning("implement %s" % tokens[0])
	
	# link 2DFX children to items
	for child in itemchilds:
		if child.parent in items:
			items[child.parent].childs.append(child)
	
	# link collision files to items
	for colfile in collisions:
		if colfile.model_id in items:
			items[colfile.model_id].colfile = colfile
		else:
			for k in items:
				var item := items[k] as ItemDef
				if item.model_name.matchn(colfile.model_name):
					items[k].colfile = colfile
	
	# initialize map root
	clear_map()
	# use call_deferred to add the map node after _ready() completes
	call_deferred("_add_map_to_parent")
	
	print("Loaded %d placements total" % placements.size())

func _add_map_to_parent() -> void:
	if map != null and get_parent() != null:
		add_child(map)

func _process(_delta: float) -> void:
	# TODO: shit code
	# get camera reference if we dont have it
	if camera == null:
		camera = get_viewport().get_camera_3d()
		return
	
	var cam_pos := camera.global_position
	var unload_distance := streaming_distance * 1.2 
	
	# check all placements for streaming
	for placement in placements:
		var distance := cam_pos.distance_to(placement.position)
		var is_active := placement in active_instances
		
		# load if within streaming distance and not loaded
		if distance < streaming_distance and not is_active:
			var instance := spawn_placement(placement)
			if instance != null:
				map.add_child(instance)
				active_instances[placement] = instance
		
		# unload if beyond unload distance and currently loaded
		elif distance > unload_distance and is_active:
			var instance := active_instances[placement]
			instance.queue_free()
			active_instances.erase(placement)

func _read_ide_line(section: String, tokens: Array[String], context: String):
	var item := ItemDef.new()
	var id := tokens[0].to_int()
	match section:
		"objs":
			item.model_name = tokens[1]
			item.txd_name = tokens[2]
			item.render_distance = tokens[4].to_float()
			item.flags = tokens[tokens.size() - 1].to_int()
			items[id] = item
		"tobj":
			# Timed objects
			item.model_name = tokens[1]
			item.txd_name = tokens[2]
			item.render_distance = tokens[4].to_float()
			item.flags = tokens[tokens.size() - 1].to_int()
			items[id] = item
		"2dfx":
			var parent := tokens[0].to_int()
			# Convert GTA to Godot coordinate system
			var position := Vector3(
				tokens[1].to_float(),
				tokens[3].to_float(),
				-tokens[2].to_float() )
			var color := Color(
				tokens[4].to_float() / 255,
				tokens[5].to_float() / 255,
				tokens[6].to_float() / 255 )
			match tokens[8].to_int():
				0:
					var lightdef := TDFXLight.new()
					lightdef.parent = parent
					lightdef.position = position
					lightdef.color = color
					lightdef.render_distance = tokens[11].to_float()
					lightdef.range = tokens[12].to_float()
					lightdef.shadow_intensity = tokens[15].to_int()
					itemchilds.append(lightdef)
				var type:
					push_warning("implement 2DFX type %d" % type)

func _read_ipl_line(section: String, tokens: Array[String], context: String):
	match section:
		"inst":
			# gta sa ipl (not binary) format: ID, ModelName, Interior, PosX, PosY, PosZ, RotX, RotY, RotZ, RotW, LOD_index
			if tokens.size() < 11:
				push_warning("Invalid inst line, expected at least 11 tokens, got %d" % tokens.size())
				return
			
			var placement := ItemPlacement.new()
			placement.id = tokens[0].to_int()
			placement.model_name = tokens[1].to_lower()
			placement.interior = tokens[2].to_int()
			
			# Convert GTA to Godot coordinate system
			placement.position = Vector3(
				tokens[3].to_float(),
				tokens[5].to_float(),
				-tokens[4].to_float(), )
			
			# rotation quaternion (gta sa uses X, Y, Z, W order)
			placement.rotation = Quaternion(
				-tokens[6].to_float(),
				-tokens[8].to_float(),
				-tokens[7].to_float(),
				tokens[9].to_float(), )
			
			# lod index
			placement.lod_index = tokens[10].to_int()

			placement.scale = Vector3.ONE
			
			placements.append(placement)

func _read_map_data(path: String, line_handler: Callable, context: String) -> void:
	var file := AssetLoader.open(path)

	if file == null:
		push_warning("Failed to open map data file: %s" % path)
		return
	
	var section: String
	while not file.eof_reached():
		var line := file.get_line()
		if line.length() == 0 or line.begins_with("#"):
			continue
		var tokens := line.replace(" ", "").split(",", false)
		if tokens.size() == 1:
			section = tokens[0]
		else:
			line_handler.call(section, tokens, context)

func clear_map() -> void:
	if map != null:
		map.queue_free()
	map = Node3D.new()
	map.name = "GTAMap"
	active_instances.clear()

func spawn_placement(ipl: ItemPlacement) -> Node3D:
	return spawn(ipl.id, ipl.model_name, ipl.position, ipl.scale, ipl.rotation)

func spawn(id: int, model_name: String, position: Vector3, scale: Vector3, rotation: Quaternion) -> Node3D:
	var item := items[id] as ItemDef
	if item.flags & 0x40:
		return Node3D.new()
	var instance := StreamedMesh.new(item)
	instance.position = position
	instance.scale = scale
	instance.quaternion = rotation
	instance.visibility_range_end = item.render_distance
	for child in item.childs:
		if child is TDFXLight:
			var light := OmniLight3D.new()
			light.position = child.position
			light.light_color = child.color
			light.distance_fade_enabled = true
			# TODO: Remove half distance when https://github.com/godotengine/godot/issues/56657 is solved
			light.distance_fade_begin = child.render_distance / 2.0
			light.omni_range = child.range
			light.light_energy = float(child.shadow_intensity) / 20.0
#			light.shadow_enabled = true
			instance.add_child(light)
	var sb := StaticBody3D.new()
	if item.colfile != null:
		for collision in item.colfile.collisions:
			var colshape := CollisionShape3D.new()
			if collision is ColFile.TBox:
				var aabb := AABB()
				# Get min and max positions from collision box
				var min_pos := collision.min as Vector3
				var max_pos := collision.max as Vector3
				
				# Ensure AABB has positive size by sorting min/max for each axis
				aabb.position = Vector3(
					min(min_pos.x, max_pos.x),
					min(min_pos.y, max_pos.y),
					min(min_pos.z, max_pos.z)
				)
				aabb.end = Vector3(
					max(min_pos.x, max_pos.x),
					max(min_pos.y, max_pos.y),
					max(min_pos.z, max_pos.z)
				)
				
				# Only create the shape if size is valid
				if aabb.size.x > 0 and aabb.size.y > 0 and aabb.size.z > 0:
					var shape := BoxShape3D.new()
					shape.size = aabb.size
					colshape.shape = shape
					colshape.position = aabb.get_center()
					sb.add_child(colshape)
			else:
				sb.add_child(colshape)
		if item.colfile.vertices.size() > 0:
			var colshape := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(item.colfile.vertices)
			colshape.shape = shape
			sb.add_child(colshape)
	instance.add_child(sb)
	return instance
