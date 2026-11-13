extends Node3D
## A low-poly animal: the desert viper (and the fiery serpent), the scorpion and the jackal.
## Faces -Z and stands on y = 0, like the human figure.
##
## Every part is a small mesh of flat-shaded triangles, built the way the sheep and the scenery
## are (scenery.gd _add_blob and _add_limb), so the animals read as modelled creatures. Parts
## that move are nodes of their own and are animated in code: the snake's body follows a
## travelling wave, the scorpion and the jackal step with their legs in turn.

const SceneryScript := preload("res://scripts/scenery.gd")
const SNAKE_SEGMENTS := 16
const SNAKE_LENGTH := 1.7

static var _material: StandardMaterial3D

var kind := ""
var _t := 0.0
var _speed := 0.0
var _strike := -1.0          # seconds into a bite or sting, or -1
var _segments: Array = []    # snake: body pieces, head first
var _seg_len := 0.0
var _legs: Array = []        # [{node, phase, base}] legs that step
var _head: Node3D
var _tail: Node3D
var _tongue: Node3D
var _claws: Array = []       # scorpion: the moving finger of each pincer


## shape: snake, scorpion or beast (the jackal). color: the main color from the enemy table.
func build(shape: String, color: Color) -> void:
	kind = shape
	match shape:
		"snake":
			_build_snake(color)
		"scorpion":
			_build_scorpion(color)
		_:
			_build_jackal(color)


# ================================================================ parts

static func _mat() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.75
	return _material


## A mesh part. `add` gets a SurfaceTool to fill with blobs and limbs.
func _piece(parent: Node3D, add: Callable, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add.call(st)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat()
	mi.position = pos
	parent.add_child(mi)
	return mi


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, tint: Color, seg: int = 7, rings: int = 4) -> void:
	SceneryScript._add_blob(st, c, r, tint, seg, rings)


static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, tint: Color) -> void:
	SceneryScript._add_limb(st, a, b, ra, rb, tint)
	# Cap the ends so a limb seen end-on is not hollow.
	SceneryScript._add_blob(st, b, Vector3.ONE * rb, tint, 6, 3)


# ================================================================ the snake

func _build_snake(color: Color) -> void:
	_seg_len = SNAKE_LENGTH / SNAKE_SEGMENTS
	var dark := color.darkened(0.45)
	var belly := color.lightened(0.25)
	for i in SNAKE_SEGMENTS:
		var k := float(i) / (SNAKE_SEGMENTS - 1)
		# Thickest a third of the way back, thin at the neck and tapering to a fine tail.
		var r := lerpf(0.05, 0.075, clampf(k * 3.0, 0.0, 1.0)) * (1.0 - smoothstep(0.35, 1.0, k) * 0.82)
		var seg := Node3D.new()
		add_child(seg)
		# Long overlapping pieces, so the body reads as one smooth length, with a row of dark
		# blotches down the back as on a viper.
		var mark := dark if i % 2 == 0 else color.darkened(0.15)
		_piece(seg, func(st: SurfaceTool) -> void:
			_blob(st, Vector3.ZERO, Vector3(r, r * 0.82, _seg_len * 0.95), color, 7, 4)
			_blob(st, Vector3(0, -r * 0.3, 0), Vector3(r * 0.92, r * 0.52, _seg_len * 0.9), belly, 6, 3)
			_blob(st, Vector3(0, r * 0.55, 0), Vector3(r * 0.6, r * 0.32, _seg_len * 0.5), mark, 5, 2))
		_segments.append({"node": seg, "r": r})
	_head = Node3D.new()
	add_child(_head)
	_piece(_head, func(st: SurfaceTool) -> void:
		# A broad flat wedge of a head, wider at the jaws, with a blunt snout.
		_blob(st, Vector3(0, 0.0, 0.01), Vector3(0.068, 0.04, 0.075), color, 6, 4)
		_blob(st, Vector3(0, -0.005, -0.06), Vector3(0.05, 0.032, 0.06), color, 6, 3)
		_blob(st, Vector3(0, 0.022, -0.02), Vector3(0.05, 0.016, 0.07), dark, 5, 2)
		for side in [-1.0, 1.0]:
			_blob(st, Vector3(side * 0.045, 0.018, -0.035), Vector3(0.014, 0.014, 0.014), Color(0.08, 0.06, 0.04), 5, 3)
			_blob(st, Vector3(side * 0.04, 0.036, -0.03), Vector3(0.018, 0.008, 0.02), dark, 4, 2))
	_tongue = Node3D.new()
	_tongue.position = Vector3(0, -0.01, -0.11)
	_head.add_child(_tongue)
	var red := Color(0.7, 0.12, 0.12)
	_piece(_tongue, func(st: SurfaceTool) -> void:
		_limb(st, Vector3.ZERO, Vector3(0, 0, -0.06), 0.004, 0.003, red)
		_limb(st, Vector3(0, 0, -0.06), Vector3(0.012, 0, -0.085), 0.003, 0.002, red)
		_limb(st, Vector3(0, 0, -0.06), Vector3(-0.012, 0, -0.085), 0.003, 0.002, red))
	_animate_snake(0.0)


func _animate_snake(delta: float) -> void:
	# A wave runs from head to tail; it is wider and quicker when the snake is moving.
	var moving := clampf(_speed / 3.0, 0.0, 1.0)
	var amp := lerpf(0.035, 0.15, moving)
	var wave := _t * lerpf(1.5, 9.0, moving)
	var lift := 0.0
	var lunge := 0.0
	if _strike >= 0.0:
		var s := clampf(_strike / 0.4, 0.0, 1.0)
		lunge = sin(s * PI) * 0.3
		lift = sin(s * PI) * 0.12
	var pts: Array = []
	for i in SNAKE_SEGMENTS + 1:
		var k := float(i) / SNAKE_SEGMENTS
		var z := -SNAKE_LENGTH * 0.42 + i * _seg_len * 0.9 - lunge * (1.0 - k)
		var a := amp * smoothstep(0.0, 0.25, k) * (0.6 + 0.4 * k)
		var x := sin(wave - k * 7.0) * a
		var y := 0.07 + maxf(0.0, 0.2 - k) / 0.2 * (0.06 + lift) * (1.0 if _speed > 0.3 or _strike >= 0.0 else 0.4)
		pts.append(Vector3(x, y, z))
	for i in SNAKE_SEGMENTS:
		var seg: Node3D = _segments[i]["node"]
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		seg.position = (a + b) * 0.5
		seg.basis = _facing(b - a)
	var front: Vector3 = pts[0]
	var neck: Vector3 = pts[1]
	_head.position = front + (front - neck).normalized() * 0.05
	_head.basis = _facing(neck - front)     # the head is modelled snout to -Z
	# The tongue flicks out now and then.
	var flick := fmod(_t, 1.7)
	_tongue.scale = Vector3.ONE * (1.0 if flick < 0.25 and int(_t / 1.7) % 2 == 0 else 0.01)


## A basis whose +Z runs along `dir`.
static func _facing(dir: Vector3) -> Basis:
	var z := dir.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)


# ================================================================ the scorpion

func _build_scorpion(color: Color) -> void:
	var shell := color
	var pale := color.lightened(0.25)
	var dark := color.darkened(0.4)
	_piece(self, func(st: SurfaceTool) -> void:
		# Head-and-body shield, then the broad segmented belly behind it.
		_blob(st, Vector3(0, 0.2, -0.16), Vector3(0.2, 0.08, 0.19), shell, 8, 4)
		_blob(st, Vector3(0, 0.25, -0.2), Vector3(0.1, 0.04, 0.1), dark, 6, 3)
		for side in [-1.0, 1.0]:
			_blob(st, Vector3(side * 0.03, 0.285, -0.22), Vector3(0.018, 0.018, 0.018), Color(0.05, 0.04, 0.03), 5, 3)
		for k in 5:
			var w := 0.21 - k * 0.022
			_blob(st, Vector3(0, 0.205 - k * 0.004, 0.02 + k * 0.085), Vector3(w, 0.075, 0.06), shell if k % 2 == 0 else shell.lightened(0.08), 8, 3)
			_blob(st, Vector3(0, 0.255, 0.02 + k * 0.085), Vector3(w * 0.45, 0.025, 0.045), dark, 6, 2))
	# Eight legs, four a side, each bent up at the knee and down to the foot.
	var hips := [-0.2, -0.1, 0.0, 0.1]
	for i in hips.size():
		for side in [-1.0, 1.0]:
			var hip := _joint(self, Vector3(side * 0.15, 0.19, float(hips[i])))
			var spread: float = lerpf(-0.6, 0.55, float(i) / 3.0) * side
			hip.rotation.y = -spread
			_piece(hip, func(st: SurfaceTool) -> void:
				_limb(st, Vector3.ZERO, Vector3(side * 0.2, 0.1, 0), 0.024, 0.018, pale)
				_limb(st, Vector3(side * 0.2, 0.1, 0), Vector3(side * 0.34, -0.19, 0), 0.018, 0.008, pale))
			var pair := (i + (0 if side < 0.0 else 1)) % 2
			_legs.append({"node": hip, "phase": pair * PI + i * 0.35, "base": hip.rotation.y, "side": side})
	# The pincers, held forward.
	for side in [-1.0, 1.0]:
		var arm := _joint(self, Vector3(side * 0.13, 0.2, -0.3))
		_piece(arm, func(st: SurfaceTool) -> void:
			_limb(st, Vector3.ZERO, Vector3(side * 0.16, 0.03, -0.14), 0.028, 0.024, shell)
			_limb(st, Vector3(side * 0.16, 0.03, -0.14), Vector3(side * 0.12, 0.04, -0.3), 0.026, 0.03, shell)
			_blob(st, Vector3(side * 0.11, 0.04, -0.36), Vector3(0.06, 0.045, 0.09), shell.lightened(0.05), 7, 4)
			_limb(st, Vector3(side * 0.13, 0.04, -0.43), Vector3(side * 0.13, 0.04, -0.55), 0.022, 0.006, dark))
		var finger := _joint(arm, Vector3(side * 0.09, 0.04, -0.43))
		_piece(finger, func(st: SurfaceTool) -> void:
			_limb(st, Vector3.ZERO, Vector3(side * -0.01, 0.0, -0.12), 0.02, 0.005, dark))
		_claws.append({"node": finger, "side": side})
	# The tail: five segments arching up over the back, the sting at its tip.
	_tail = _joint(self, Vector3(0, 0.22, 0.42))
	var node := _tail
	for k in 5:
		var seg := _joint(node, Vector3(0, 0, 0) if k == 0 else Vector3(0, 0.0, 0.11))
		seg.rotation.x = -0.55 if k > 0 else -0.4    # negative turns +Z (back) upward
		_piece(seg, func(st: SurfaceTool) -> void:
			_blob(st, Vector3(0, 0, 0.055), Vector3(0.055 - k * 0.004, 0.05 - k * 0.003, 0.07), shell if k % 2 == 0 else shell.lightened(0.07), 7, 3))
		node = seg
	var sting := _joint(node, Vector3(0, 0.0, 0.12))
	sting.rotation.x = -0.7
	_piece(sting, func(st: SurfaceTool) -> void:
		_blob(st, Vector3(0, 0, 0.04), Vector3(0.05, 0.045, 0.065), Color(0.55, 0.32, 0.15), 7, 4)
		_limb(st, Vector3(0, 0, 0.09), Vector3(0, -0.06, 0.15), 0.02, 0.003, Color(0.12, 0.08, 0.05)))
	_animate_scorpion(0.0)


func _animate_scorpion(_delta: float) -> void:
	var moving := clampf(_speed / 2.0, 0.0, 1.0)
	var step := _t * lerpf(1.0, 11.0, moving)
	for leg in _legs:
		var n: Node3D = leg["node"]
		var p: float = step + float(leg["phase"])
		n.rotation.y = float(leg["base"]) + sin(p) * 0.28 * moving
		n.rotation.z = maxf(0.0, cos(p)) * 0.25 * moving * float(leg["side"])
	var open := 0.25 + 0.2 * sin(_t * 2.3)
	var sting := 0.0
	if _strike >= 0.0:
		var s := clampf(_strike / 0.45, 0.0, 1.0)
		sting = sin(s * PI)
		open = 0.5
	for c in _claws:
		(c["node"] as Node3D).rotation.y = open * float(c["side"])
	# The tail sways while waiting and whips forward over the back to sting.
	_tail.rotation.x = -(0.4 + 0.08 * sin(_t * 1.7) + sting * 0.5)
	_tail.rotation.z = 0.1 * sin(_t * 1.1) * (1.0 - sting)
	var node: Node3D = _tail
	for k in 4:
		node = node.get_child(node.get_child_count() - 1) as Node3D
		node.rotation.x = -(0.55 + sting * 0.25)


# ================================================================ the jackal

func _build_jackal(color: Color) -> void:
	var dark := color.darkened(0.35)
	var pale := color.lightened(0.3)
	_piece(self, func(st: SurfaceTool) -> void:
		_blob(st, Vector3(0, 0.56, 0.02), Vector3(0.14, 0.15, 0.36), color, 8, 4)
		_blob(st, Vector3(0, 0.58, -0.25), Vector3(0.15, 0.17, 0.17), color, 8, 4)
		_blob(st, Vector3(0, 0.5, -0.22), Vector3(0.11, 0.12, 0.14), pale, 7, 3)
		_blob(st, Vector3(0, 0.57, 0.27), Vector3(0.13, 0.13, 0.13), color, 7, 4)
		_blob(st, Vector3(0, 0.645, -0.05), Vector3(0.085, 0.07, 0.32), color.darkened(0.15), 7, 3)
		_limb(st, Vector3(0, 0.64, -0.32), Vector3(0, 0.78, -0.46), 0.08, 0.065, color))
	_head = _joint(self, Vector3(0, 0.8, -0.5))
	_piece(_head, func(st: SurfaceTool) -> void:
		_blob(st, Vector3(0, 0.0, 0.0), Vector3(0.085, 0.08, 0.1), color, 7, 4)
		_limb(st, Vector3(0, -0.02, -0.06), Vector3(0, -0.04, -0.2), 0.05, 0.024, color)
		_blob(st, Vector3(0, -0.035, -0.205), Vector3(0.022, 0.018, 0.018), Color(0.08, 0.06, 0.05), 5, 3)
		_limb(st, Vector3(0, -0.06, -0.08), Vector3(0, -0.06, -0.17), 0.03, 0.016, pale)
		for side in [-1.0, 1.0]:
			_limb(st, Vector3(side * 0.045, 0.05, 0.02), Vector3(side * 0.065, 0.17, 0.035), 0.032, 0.004, color)
			_blob(st, Vector3(side * 0.052, 0.07, 0.016), Vector3(0.012, 0.03, 0.006), dark, 4, 2)
			_blob(st, Vector3(side * 0.045, 0.015, -0.07), Vector3(0.014, 0.012, 0.012), Color(0.1, 0.08, 0.04), 5, 3))
	# Four legs, each a thigh and a shin, set at the shoulders and the hips.
	var at := [Vector3(-0.09, 0.52, -0.27), Vector3(0.09, 0.52, -0.27), Vector3(-0.09, 0.52, 0.27), Vector3(0.09, 0.52, 0.27)]
	for i in 4:
		var leg := _joint(self, at[i])
		var hind := i >= 2
		_piece(leg, func(st: SurfaceTool) -> void:
			var knee := Vector3(0, -0.24, 0.06 if hind else -0.02)
			_limb(st, Vector3(0, 0.03, 0), knee, 0.055 if hind else 0.045, 0.03, color)
			_limb(st, knee, Vector3(0, -0.5, 0.0), 0.028, 0.02, color if not hind else color.darkened(0.05))
			_blob(st, Vector3(0, -0.5, -0.025), Vector3(0.03, 0.02, 0.045), dark, 5, 3))
		# Trot: diagonal pairs move together.
		_legs.append({"node": leg, "phase": PI * float((i + (i / 2)) % 2), "base": 0.0, "side": 1.0})
	_tail = _joint(self, Vector3(0, 0.62, 0.36))
	_piece(_tail, func(st: SurfaceTool) -> void:
		_limb(st, Vector3.ZERO, Vector3(0, -0.16, 0.2), 0.04, 0.06, color)
		_limb(st, Vector3(0, -0.16, 0.2), Vector3(0, -0.3, 0.3), 0.06, 0.03, dark))
	_animate_jackal(0.0)


func _animate_jackal(_delta: float) -> void:
	var moving := clampf(_speed / 5.0, 0.0, 1.0)
	var step := _t * lerpf(1.0, 13.0, moving)
	for leg in _legs:
		(leg["node"] as Node3D).rotation.x = sin(step + float(leg["phase"])) * 0.55 * moving
	var bite := 0.0
	if _strike >= 0.0:
		bite = sin(clampf(_strike / 0.35, 0.0, 1.0) * PI)
	_head.rotation.x = -0.15 + 0.06 * sin(_t * 1.3) + bite * 0.45 - moving * 0.15
	_head.position.z = -0.5 - bite * 0.12
	_tail.rotation.y = sin(_t * (2.0 + moving * 6.0)) * 0.3
	_tail.rotation.x = -0.1 * moving


# ================================================================ every frame

## Call every frame with the horizontal speed in metres per second.
func animate(delta: float, speed: float) -> void:
	_t += delta
	_speed = lerpf(_speed, speed, 1.0 - exp(-8.0 * delta))
	if _strike >= 0.0:
		_strike += delta
		if _strike > 0.5:
			_strike = -1.0
	match kind:
		"snake":
			_animate_snake(delta)
		"scorpion":
			_animate_scorpion(delta)
		_:
			_animate_jackal(delta)


## A bite or a sting.
func strike() -> void:
	_strike = 0.0
