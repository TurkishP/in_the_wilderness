extends Node3D
## The inside of the scout's own tent. It stands apart from the stage, far off and high up, so
## nothing outside can reach in; going through the door (world.gd enter_home / leave_home)
## moves the player between it and the camp.
##
## Inside: woven rugs, two tent poles, a bed (sleeping saves the game: the only place it is
## saved), a chest for gear and stones, a water jar with cups, and an oil lamp.
## The floor is at y = 0 of this node; the door is at +Z.

const InteractScript := preload("res://scripts/interactable.gd")
const SIZE := Vector3(6.4, 3.4, 8.0)      # width, height at the ridge, depth
const WALL := 1.5                         # height of the side walls
const WOOD := Color(0.42, 0.29, 0.18)
const CLOTH := Color(0.8, 0.72, 0.56)
const STRIPE := Color(0.55, 0.16, 0.13)

var bed: Node3D
var chest: Node3D
var lid_hinge: Node3D
var jar: Node3D
var door: Node3D
var _callbacks := {}


## callbacks: {sleep, chest, drink, leave} -> Callable taking the interactable node.
func build(callbacks: Dictionary) -> void:
	_callbacks = callbacks
	_shell()
	_furnish()


## Where the player stands on coming in, and which way they face (yaw).
## Swings the chest lid open (true) or shut. It moves even while the game is paused behind the
## chest screen.
func open_lid(open: bool) -> void:
	var tw := lid_hinge.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(lid_hinge, "rotation:x", -1.9 if open else 0.0, 0.35)


func entry() -> Vector3:
	return to_global(Vector3(0.0, 0.1, SIZE.z * 0.5 - 2.2))


func entry_yaw() -> float:
	return 0.0          # facing -Z, into the tent


## Beside the bed, where someone carried in is laid down.
func bedside() -> Vector3:
	return to_global(Vector3(-1.4, 0.1, -1.2))


func _box(size: Vector3, color: Color, surface: String, pos: Vector3, rot: Vector3 = Vector3.ZERO, emit: float = 0.0) -> MeshInstance3D:
	var mi := Game.mesh_box(size, color, surface, emit)
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, color: Color, surface: String, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := Game.mesh_cyl(top, bottom, h, color, surface)
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _solid(size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	sb.position = pos
	sb.rotation = rot
	add_child(sb)


func _spot(label: String, pos: Vector3, radius: float, key: String) -> Node3D:
	var it = InteractScript.new()
	it.label = label
	it.interact_radius = radius
	it.callback = _callbacks.get(key, Callable())
	it.position = pos
	add_child(it)
	return it


## Floor, walls and the sloping roof, all solid so the camera stays inside.
func _shell() -> void:
	var hx := SIZE.x * 0.5
	var hz := SIZE.z * 0.5
	# A closed dark box round everything, seen from inside, so no gap ever shows the sky.
	var shell := MeshInstance3D.new()
	var outer := BoxMesh.new()
	outer.size = SIZE + Vector3(1.2, 1.0, 1.2)
	outer.flip_faces = true
	shell.mesh = outer
	shell.material_override = Game.mat(Color(0.18, 0.12, 0.08))
	shell.position.y = SIZE.y * 0.5
	add_child(shell)
	_box(Vector3(SIZE.x + 0.4, 0.2, SIZE.z + 0.4), Color(0.72, 0.62, 0.46), "", Vector3(0, -0.1, 0))
	_solid(Vector3(SIZE.x + 0.4, 0.2, SIZE.z + 0.4), Vector3(0, -0.1, 0))
	# Side walls, and the roof rising from them to the ridge.
	var slope := Vector2(hx, SIZE.y - WALL)
	var roof_len := slope.length()
	var tilt := atan2(slope.y, slope.x)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.06, WALL, SIZE.z), CLOTH, "cloth", Vector3(side * hx, WALL * 0.5, 0))
		_solid(Vector3(0.2, WALL, SIZE.z), Vector3(side * (hx + 0.07), WALL * 0.5, 0))
		var mid := Vector3(side * hx * 0.5, WALL + slope.y * 0.5, 0)
		_box(Vector3(roof_len + 0.1, 0.06, SIZE.z), CLOTH.darkened(0.05), "cloth", mid, Vector3(0, 0, side * -tilt))
		_solid(Vector3(roof_len + 0.1, 0.2, SIZE.z), mid + Vector3(side * 0.05, 0.08, 0), Vector3(0, 0, side * -tilt))
		# A woven band along each wall.
		_box(Vector3(0.07, 0.22, SIZE.z), STRIPE, "cloth", Vector3(side * (hx - 0.01), 1.05, 0))
	# The back wall, and the front wall with the doorway in it.
	for end in [-1.0, 1.0]:
		var z: float = end * hz
		var gable := PrismMesh.new()
		gable.size = Vector3(SIZE.x, SIZE.y - WALL, 0.06)
		var g := MeshInstance3D.new()
		g.mesh = gable
		g.material_override = Game.mat(CLOTH.darkened(0.08), "cloth")
		g.position = Vector3(0, WALL + (SIZE.y - WALL) * 0.5, z)
		add_child(g)
		if end < 0.0:
			_box(Vector3(SIZE.x, WALL, 0.06), CLOTH.darkened(0.08), "cloth", Vector3(0, WALL * 0.5, z))
		else:
			for s in [-1.0, 1.0]:
				_box(Vector3(hx - 0.7, WALL, 0.06), CLOTH.darkened(0.08), "cloth", Vector3(s * (hx + 0.7) * 0.5, WALL * 0.5, z))
			# Daylight in the doorway.
			_box(Vector3(1.4, 2.1, 0.02), Color(0.95, 0.85, 0.66), "", Vector3(0, 1.05, z + 0.12), Vector3.ZERO, 0.7)
			for s in [-1.0, 1.0]:
				_cyl(0.05, 0.05, 2.2, WOOD, "wood", Vector3(s * 0.75, 1.1, z - 0.05))
		_solid(Vector3(SIZE.x + 0.4, SIZE.y + 0.5, 0.2), Vector3(0, SIZE.y * 0.5, z + end * 0.12))
	# Two poles hold up the ridge, with a beam between them.
	for k in [-1.0, 1.0]:
		_cyl(0.07, 0.08, SIZE.y, WOOD, "wood", Vector3(0, SIZE.y * 0.5, k * hz * 0.5))
	_cyl(0.06, 0.06, SIZE.z, WOOD, "wood", Vector3(0, SIZE.y - 0.08, 0), Vector3(PI * 0.5, 0, 0))
	# The lamp light, warm and close, and a soft fill from the doorway.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.4)
	lamp.light_energy = 1.8
	lamp.omni_range = 9.0
	lamp.shadow_enabled = true
	lamp.position = Vector3(0.9, 1.2, -0.4)
	add_child(lamp)
	var day := OmniLight3D.new()
	day.light_color = Color(1.0, 0.92, 0.8)
	day.light_energy = 0.8
	day.omni_range = 7.0
	day.position = Vector3(0, 1.6, hz - 0.6)
	add_child(day)


func _furnish() -> void:
	var hx := SIZE.x * 0.5
	var hz := SIZE.z * 0.5
	# Rugs.
	_box(Vector3(4.2, 0.02, 5.0), Color(0.55, 0.2, 0.15), "cloth", Vector3(0, 0.01, -0.4))
	_box(Vector3(3.6, 0.025, 4.4), Color(0.75, 0.6, 0.35), "cloth", Vector3(0, 0.015, -0.4))
	for k in 3:
		_box(Vector3(3.6, 0.03, 0.18), Color(0.2, 0.26, 0.45), "cloth", Vector3(0, 0.02, -2.2 + k * 1.8))

	# The bed: a low wooden frame, a straw mattress, a woollen blanket and a bolster.
	bed = Node3D.new()
	bed.position = Vector3(-hx + 0.75, 0, -hz + 1.6)
	add_child(bed)
	var frame := Game.mesh_box(Vector3(1.0, 0.3, 2.1), WOOD, "wood")
	frame.position.y = 0.15
	bed.add_child(frame)
	var mattress := Game.mesh_box(Vector3(0.92, 0.14, 2.0), Color(0.86, 0.8, 0.62), "cloth")
	mattress.position.y = 0.37
	bed.add_child(mattress)
	var blanket := Game.mesh_box(Vector3(0.96, 0.06, 1.25), Color(0.6, 0.18, 0.14), "cloth")
	blanket.position = Vector3(0, 0.46, 0.35)
	bed.add_child(blanket)
	for k in 2:
		var band := Game.mesh_box(Vector3(0.97, 0.065, 0.1), Color(0.88, 0.8, 0.6), "cloth")
		band.position = Vector3(0, 0.465, 0.05 + k * 0.6)
		bed.add_child(band)
	var bolster := Game.mesh_cyl(0.12, 0.12, 0.85, Color(0.82, 0.74, 0.55), "linen")
	bolster.position = Vector3(0, 0.52, -0.82)
	bolster.rotation.z = PI * 0.5
	bed.add_child(bolster)
	_solid(Vector3(1.0, 0.5, 2.1), bed.position + Vector3(0, 0.25, 0))
	_spot("Sleep  (saves your progress)", bed.position + Vector3(0.9, 0.5, 0), 1.8, "sleep")

	# The chest: planks bound with bronze, at the foot of the far wall.
	chest = Node3D.new()
	chest.position = Vector3(hx - 0.6, 0, -hz + 1.2)
	chest.rotation.y = -PI * 0.5
	add_child(chest)
	var box := Game.mesh_box(Vector3(1.1, 0.55, 0.62), WOOD.lightened(0.05), "wood")
	box.position.y = 0.3
	chest.add_child(box)
	# The lid turns on a hinge along the back edge (the front faces the player, +Z here).
	lid_hinge = Node3D.new()
	lid_hinge.position = Vector3(0, 0.57, -0.33)
	chest.add_child(lid_hinge)
	var lid := Game.mesh_box(Vector3(1.14, 0.12, 0.66), WOOD.darkened(0.08), "wood")
	lid.position = Vector3(0, 0.06, 0.33)
	lid_hinge.add_child(lid)
	var inside := Game.mesh_box(Vector3(1.0, 0.02, 0.52), WOOD.darkened(0.45), "wood")
	inside.position.y = 0.56
	chest.add_child(inside)
	for x in [-0.4, 0.0, 0.4]:
		var strap := Game.mesh_box(Vector3(0.06, 0.56, 0.68), Color(0.72, 0.5, 0.24), "metal")
		strap.position = Vector3(x, 0.29, 0)
		chest.add_child(strap)
		var band := Game.mesh_box(Vector3(0.06, 0.14, 0.7), Color(0.72, 0.5, 0.24), "metal")
		band.position = Vector3(x, 0.06, 0.33)
		lid_hinge.add_child(band)
	var lock := Game.mesh_box(Vector3(0.12, 0.14, 0.04), Color(0.8, 0.6, 0.28), "metal")
	lock.position = Vector3(0, 0.5, 0.34)
	chest.add_child(lock)
	_solid(Vector3(0.66, 0.7, 1.14), chest.position + Vector3(0, 0.35, 0))
	_spot("Open your chest", chest.position + Vector3(-0.9, 0.5, 0), 1.6, "chest")

	# A water jar on a stand by the door, with two cups.
	jar = Node3D.new()
	jar.position = Vector3(-hx + 0.6, 0, hz - 1.3)
	add_child(jar)
	var clay := Color(0.7, 0.42, 0.28)
	var stand := Game.mesh_box(Vector3(0.6, 0.35, 0.6), WOOD, "wood")
	stand.position.y = 0.175
	jar.add_child(stand)
	var body := Game.mesh_cyl(0.18, 0.26, 0.6, clay, "clay")
	body.position.y = 0.65
	jar.add_child(body)
	var neck := Game.mesh_cyl(0.12, 0.16, 0.14, clay, "clay")
	neck.position.y = 1.02
	jar.add_child(neck)
	for k in 2:
		var cup := Game.mesh_cyl(0.05, 0.04, 0.09, Color(0.5, 0.36, 0.22), "wood")
		cup.position = Vector3(0.2 - k * 0.12, 0.395, 0.2)
		jar.add_child(cup)
	_spot("Drink from your water jar", jar.position + Vector3(0.8, 0.5, 0), 1.6, "drink")

	# The oil lamp on a stool, and a few things of daily life.
	_box(Vector3(0.4, 0.4, 0.4), WOOD, "wood", Vector3(0.9, 0.2, -0.4))
	_cyl(0.07, 0.09, 0.06, clay, "clay", Vector3(0.9, 0.43, -0.4))
	_box(Vector3(0.05, 0.08, 0.05), Color(1.0, 0.7, 0.3), "", Vector3(0.98, 0.5, -0.4), Vector3.ZERO, 3.0)
	_cyl(0.3, 0.24, 0.32, Color(0.62, 0.5, 0.3), "basket", Vector3(hx - 0.6, 0.16, 0.6))
	_cyl(0.22, 0.28, 0.5, clay.darkened(0.1), "clay", Vector3(hx - 0.55, 0.25, 1.4))
	_cyl(0.16, 0.2, 0.35, clay.lightened(0.05), "clay", Vector3(hx - 0.95, 0.175, 1.75))
	for k in 3:
		_cyl(0.03, 0.03, 0.7, WOOD.lightened(0.1), "wood", Vector3(-hx + 0.35, 1.2, -0.6 + k * 0.25), Vector3(0, 0, 0.2))

	# The way out.
	door = _spot("Leave the tent", Vector3(0, 0.5, hz - 0.5), 1.5, "leave")
