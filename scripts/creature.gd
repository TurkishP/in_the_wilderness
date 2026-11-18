extends Node3D
## A low-poly animal: the desert viper (and the fiery serpent), the scorpion, the jackal, and the
## larger beasts of the wilderness (BEASTS: wolf, hyena, leopard, lion, bear) and the pack donkey.
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


## shape: snake, scorpion, beast (the jackal), or one of BEASTS. color: the main color.
func build(shape: String, color: Color) -> void:
	kind = shape
	match shape:
		"snake":
			_build_snake(color)
		"scorpion":
			_build_scorpion(color)
		_:
			_build_beast(shape if BEASTS.has(shape) else "jackal", color)


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
	# Corners shared within a part are merged, so each part is smoothly shaded.
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat()
	# Past this an animal is a speck; its detail is not worth drawing.
	mi.visibility_range_end = 160.0
	mi.position = pos
	parent.add_child(mi)
	return mi


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## A rounded lump. The bigger it is, the more facets it gets: a body or a head up to 1.8 times
## as many each way as asked for, a spot or a claw as asked.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, tint: Color, seg: int = 7, rings: int = 4) -> void:
	var k := clampf(maxf(r.x, maxf(r.y, r.z)) / 0.04, 1.0, 1.8)
	SceneryScript._add_blob(st, c, r, tint, int(round(seg * k)), int(round(rings * k)))


## A tapering round limb from `a` to `b`, rounded off at both ends like a joint.
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, tint: Color) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3(0.3, 0.1, 0.9)).normalized()
	var v := axis.cross(u)
	var sides := 12 if maxf(ra, rb) > 0.03 else 8
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		for q in [a + d0 * ra, b + d0 * rb, a + d1 * ra, a + d1 * ra, b + d0 * rb, b + d1 * rb]:
			st.set_color(tint)
			st.add_vertex(q)
	_blob(st, a, Vector3.ONE * ra, tint, 6, 3)
	_blob(st, b, Vector3.ONE * rb, tint, 6, 3)


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


# ================================================================ walking and biting

## Every four-legged animal: the legs step, the head bobs and the jaw drops to bite, or to
## pant at a run.
func _animate_jackal(_delta: float) -> void:
	var moving := clampf(_speed / 5.0, 0.0, 1.0)
	var step := _t * lerpf(1.0, _stride, moving)
	for leg in _legs:
		(leg["node"] as Node3D).rotation.x = sin(step + float(leg["phase"])) * 0.55 * moving
	var bite := 0.0
	if _strike >= 0.0:
		bite = sin(clampf(_strike / 0.35, 0.0, 1.0) * PI)
	_head.rotation.x = -0.15 - _tilt + 0.06 * sin(_t * 1.3) + bite * 0.45 - moving * 0.15
	_head.position.z = _head_rest.z - bite * 0.12
	if _jaw != null:
		_jaw.rotation.x = -(bite * 0.55 + moving * 0.12 * (0.5 + 0.5 * sin(_t * 9.0)))
	if _body != null:
		# A stalking cat creeps low, its head level with its back.
		_body.position.y = -crouch * 0.18
		_head.position.y = _head_rest.y - crouch * 0.1
	_tail.rotation.y = sin(_t * (2.0 + moving * 6.0)) * 0.3
	_tail.rotation.x = -0.1 * moving


# ================================================================ the four-legged animals

## The four-legged animals, all built on one frame from their proportions (metres): h the height
## of the trunk's middle at the shoulder, rear the same at the hips, l half the trunk's length,
## w and t half its width and depth, head the head's size, snout its length (muzzle its
## thickness, tilt how low the head is carried), leg the thickness of the legs; the shape of the
## ears, tail and feet, the coat's markings, and the colors of the belly, the dark markings
## ("back"), the eyes, the nose and a dark or pale muzzle ("mask").
## Sizes are of the animals of the region: the golden jackal; the Arabian wolf and the Arabian
## leopard, both small for their kinds; the striped hyena; the Asiatic lion (a maned male); the
## Syrian brown bear, pale and not large; and the pack donkey of the caravans.
const BEASTS := {
	"jackal": {"h": 0.42, "rear": 0.41, "l": 0.32, "w": 0.1, "t": 0.11, "head": 0.075, "snout": 0.12, "ears": "pointed", "tail": "brush", "leg": 0.03, "feet": "paw",
		"belly": Color(0.88, 0.82, 0.68), "back": Color(0.3, 0.25, 0.2), "coat": "saddle", "eye": Color(0.7, 0.5, 0.15)},
	"wolf": {"h": 0.55, "rear": 0.53, "l": 0.42, "w": 0.13, "t": 0.15, "head": 0.1, "snout": 0.17, "ears": "pointed", "tail": "brush", "leg": 0.045, "feet": "paw",
		"belly": Color(0.85, 0.82, 0.74), "back": Color(0.38, 0.34, 0.3), "coat": "saddle", "ruff": true, "eye": Color(0.78, 0.58, 0.18), "mask": Color(0.86, 0.83, 0.76)},
	"hyena": {"h": 0.6, "rear": 0.47, "l": 0.42, "w": 0.15, "t": 0.17, "head": 0.13, "snout": 0.15, "muzzle": 0.6, "ears": "big", "tail": "brush", "leg": 0.05, "feet": "paw", "tilt": 0.2,
		"belly": Color(0.78, 0.74, 0.64), "back": Color(0.2, 0.18, 0.16), "coat": "stripes", "crest": true, "eye": Color(0.4, 0.28, 0.12), "mask": Color(0.26, 0.23, 0.2)},
	"leopard": {"h": 0.48, "rear": 0.5, "l": 0.5, "w": 0.13, "t": 0.15, "head": 0.1, "snout": 0.06, "muzzle": 0.62, "ears": "round", "tail": "long", "leg": 0.05, "feet": "paw", "cat": true,
		"belly": Color(0.94, 0.9, 0.8), "back": Color(0.16, 0.12, 0.08), "coat": "rosettes", "eye": Color(0.75, 0.62, 0.2), "nose": Color(0.62, 0.4, 0.36), "mask": Color(0.93, 0.88, 0.78)},
	"lion": {"h": 0.85, "rear": 0.84, "l": 0.68, "w": 0.23, "t": 0.26, "head": 0.16, "snout": 0.12, "muzzle": 0.62, "ears": "round", "tail": "tuft", "leg": 0.085, "feet": "paw", "cat": true,
		"belly": Color(0.86, 0.76, 0.58), "back": Color(0.62, 0.46, 0.28), "coat": "plain", "mane": Color(0.36, 0.22, 0.12), "eye": Color(0.72, 0.55, 0.2), "nose": Color(0.5, 0.3, 0.26), "mask": Color(0.88, 0.8, 0.66)},
	"bear": {"h": 0.72, "rear": 0.7, "l": 0.58, "w": 0.3, "t": 0.33, "head": 0.17, "snout": 0.13, "muzzle": 0.55, "ears": "round", "tail": "stub", "leg": 0.1, "feet": "claws", "tilt": 0.25,
		"belly": Color(0.72, 0.6, 0.44), "back": Color(0.5, 0.38, 0.26), "coat": "shaggy", "hump": true, "eye": Color(0.18, 0.12, 0.08)},
	"donkey": {"h": 0.88, "rear": 0.88, "l": 0.55, "w": 0.19, "t": 0.24, "head": 0.13, "snout": 0.25, "muzzle": 0.72, "ears": "long", "tail": "thin", "leg": 0.055, "feet": "hoof", "tilt": 0.6,
		"belly": Color(0.86, 0.84, 0.8), "back": Color(0.3, 0.27, 0.24), "coat": "cross", "packs": true, "eye": Color(0.15, 0.1, 0.07), "mask": Color(0.85, 0.83, 0.78)},
}

var _head_rest := Vector3(0, 0.8, -0.5)   # where the head joint sits when still
var _stride := 13.0                       # how fast the legs step at a run
var crouch := 0.0                         # 0 standing .. 1 low, creeping (a stalking cat)
var _body: Node3D
var _jaw: Node3D
var _tilt := 0.0                          # how far the head hangs below level


func _build_beast(model: String, color: Color) -> void:
	var p: Dictionary = BEASTS[model]
	var h: float = p["h"]
	var rear: float = p["rear"]
	var l: float = p["l"]
	var w: float = p["w"]
	var t: float = p["t"]
	var hs: float = p["head"]
	_stride = clampf(13.0 * 0.6 / h, 6.5, 14.0)
	_body = _joint(self, Vector3.ZERO)
	_head_rest = _head_rest_for(p)
	_tilt = float(p.get("tilt", 0.0))
	_piece(_body, func(st: SurfaceTool) -> void: _beast_trunk(st, model, p, color))
	_head = _joint(_body, _head_rest)
	_piece(_head, func(st: SurfaceTool) -> void: _beast_head(st, model, p, color))
	# The lower jaw hinges below the ears, so a bite opens the mouth.
	_jaw = _joint(_head, Vector3(0, -hs * 0.5, -hs * 0.3))
	_piece(_jaw, func(st: SurfaceTool) -> void: _beast_jaw(st, p, color))
	# Legs at the shoulders and the hips.
	var at := [Vector3(-w * 0.62, h - t * 0.3, -l * 0.7), Vector3(w * 0.62, h - t * 0.3, -l * 0.7), Vector3(-w * 0.62, rear - t * 0.3, l * 0.7), Vector3(w * 0.62, rear - t * 0.3, l * 0.7)]
	for i in 4:
		var leg := _joint(_body, at[i])
		var hind := i >= 2
		var reach: float = at[i].y
		_piece(leg, func(st: SurfaceTool) -> void: _beast_leg(st, model, p, color, reach, hind))
		# Trot: diagonal pairs move together; a bear paces, both legs of a side together.
		var phase := PI * float((i + (i / 2)) % 2) if model != "bear" else PI * float(i % 2)
		_legs.append({"node": leg, "phase": phase, "base": 0.0, "side": 1.0})
	_tail = _joint(_body, Vector3(0, rear + t * 0.4, l * 1.05))
	_piece(_tail, func(st: SurfaceTool) -> void: _beast_tail(st, p, color))
	_animate_jackal(0.0)


## The trunk's three lumps, chest, waist and haunch: [centre, radii].
static func _trunk_lumps(p: Dictionary) -> Array:
	var h: float = p["h"]
	var rear: float = p["rear"]
	var l: float = p["l"]
	var w: float = p["w"]
	var t: float = p["t"]
	var mid := (h + rear) * 0.5 - 0.04
	return [[Vector3(0, h - 0.02, -l * 0.62), Vector3(w * 1.05, t * 1.08, l * 0.5)],
		[Vector3(0, mid + t * 0.05, 0.0), Vector3(w * 0.95, t * 0.9, l * 0.62)],
		[Vector3(0, rear - 0.03, l * 0.62), Vector3(w * 0.98, t * 0.98, l * 0.44)]]


## The point on the hide `z` along the trunk and `a` round it (0 on top of the back), `sink`
## metres in: found by stepping out from the middle until clear of all three lumps, so markings
## sit on the hide instead of floating above it or sinking out of sight.
static func _on_trunk(p: Dictionary, z: float, a: float, sink: float = 0.0) -> Vector3:
	var l: float = p["l"]
	var lumps := _trunk_lumps(p)
	var from := Vector3(0, lerpf(float(p["h"]), float(p["rear"]), clampf((z + l) / (2.0 * l), 0.0, 1.0)) - 0.03, z)
	var dir := Vector3(sin(a), cos(a), 0.0)
	var step := maxf(float(p["w"]), float(p["t"])) * 0.03
	var reach := 0.0
	for i in 80:
		var q := from + dir * (i * step)
		for lump in lumps:
			if ((q - (lump[0] as Vector3)) / (lump[1] as Vector3)).length_squared() <= 1.0:
				reach = i * step
				break
	return from + dir * maxf(0.0, reach - sink)


static func _beast_trunk(st: SurfaceTool, model: String, p: Dictionary, color: Color) -> void:
	var h: float = p["h"]
	var rear: float = p["rear"]
	var l: float = p["l"]
	var w: float = p["w"]
	var t: float = p["t"]
	var hs: float = p["head"]
	var belly: Color = p["belly"]
	var back: Color = p["back"]
	var mid := (h + rear) * 0.5 - 0.04
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(model)
	# The trunk: deep chest, waist and haunch, sloping where the hips are lower.
	for lump in _trunk_lumps(p):
		_blob(st, lump[0], lump[1], color, 12, 7)
	# The breast in front of the forelegs, and the belly tucked up towards the hips.
	_blob(st, Vector3(0, h - t * 0.42, -l * 0.98), Vector3(w * 0.72, t * 0.62, l * 0.2), belly.lerp(color, 0.45), 9, 5)
	_blob(st, Vector3(0, h - t * 0.6, -l * 0.35), Vector3(w * 0.8, t * 0.44, l * 0.5), belly, 9, 5)
	_blob(st, Vector3(0, mid - t * 0.5, l * 0.15), Vector3(w * 0.72, t * 0.34, l * 0.45), belly, 9, 5)
	# Shoulder blades and the tops of the haunches, standing out under the hide.
	for side in [-1.0, 1.0]:
		_blob(st, Vector3(side * w * 0.5, h + t * 0.32, -l * 0.68), Vector3(w * 0.42, t * 0.62, l * 0.22), color.darkened(0.03), 9, 5)
		_blob(st, Vector3(side * w * 0.48, rear + t * 0.14, l * 0.66), Vector3(w * 0.5, t * 0.7, l * 0.28), color.darkened(0.02), 9, 5)
	# The line of the spine, a shade darker, lying along the back.
	for k in 9:
		_blob(st, _on_trunk(p, -l * 0.95 + k * l * 0.24, 0.0, t * 0.07), Vector3(w * 0.3, t * 0.09, l * 0.15), color.darkened(0.08), 8, 4)
	if p.get("hump", false):
		_blob(st, Vector3(0, h + t * 0.5, -l * 0.55), Vector3(w * 0.75, t * 0.55, l * 0.34), color.lightened(0.05), 10, 6)
	# The neck rising to the head, its throat paler.
	var head_at := _head_rest_for(p)
	_limb(st, Vector3(0, h + t * 0.45, -l * 0.95), head_at + Vector3(0, -hs * 0.1, hs * 0.55), w * 0.78, hs * 0.78, color)
	_limb(st, Vector3(0, h - t * 0.1, -l * 1.0), head_at + Vector3(0, -hs * 0.5, hs * 0.2), w * 0.6, hs * 0.55, belly.lerp(color, 0.5))
	if p.get("ruff", false):
		# A wolf's thick ruff of paler fur round the neck.
		_blob(st, Vector3(0, h + t * 0.25, -l * 1.05), Vector3(w * 1.1, t * 1.0, l * 0.26), color.lerp(belly, 0.3), 10, 6)
	var coat := str(p["coat"])
	if coat == "saddle":
		# A dark saddle over the back, its edge broken into tufts.
		_blob(st, Vector3(0, mid + t * 0.62, 0.0), Vector3(w * 0.78, t * 0.42, l * 0.72), back.lerp(color, 0.25), 10, 5)
		for k in 10:
			var z := -l * 0.6 + k * l * 0.13
			for side in [-1.0, 1.0]:
				_blob(st, _on_trunk(p, z, side * rng.randf_range(0.95, 1.2), t * 0.1), Vector3(w * 0.2, t * 0.16, l * 0.09), back.lerp(color, 0.45), 6, 3)
	elif coat == "cross":
		# The donkey's dark stripe down the back, crossed at the shoulders.
		_blob(st, Vector3(0, mid + t * 0.92, 0.0), Vector3(w * 0.16, t * 0.12, l * 0.98), back, 7, 3)
		for side in [-1.0, 1.0]:
			_blob(st, _on_trunk(p, -l * 0.62, side * 0.9, w * 0.08), Vector3(w * 0.2, t * 0.5, w * 0.12), back, 7, 4)
	elif coat == "stripes":
		# The striped hyena: dark bars down the sides, a little wavy.
		for k in 8:
			var z := -l * 0.95 + k * l * 0.27
			for side in [-1.0, 1.0]:
				_blob(st, _on_trunk(p, z, side * 1.05, 0.01), Vector3(0.016, t * 0.5, 0.022), back, 6, 4)
				_blob(st, _on_trunk(p, z + l * 0.05, side * 1.8, 0.01), Vector3(0.016, t * 0.34, 0.021), back, 6, 4)
	elif coat == "rosettes":
		# Each rosette a ring of dark spots round a deeper gold; small solid spots between.
		for k in 70:
			var z := rng.randf_range(-l * 1.1, l * 1.05)
			var a := rng.randf_range(-PI * 0.86, PI * 0.86)
			var c := _on_trunk(p, z, a, 0.004)
			var across := Vector3(cos(a), -sin(a), 0.0)
			_blob(st, c, Vector3.ONE * 0.02, color.darkened(0.14), 6, 3)
			for j in 5:
				var r := TAU * j / 5.0 + rng.randf() * 0.5
				_blob(st, c + (across * cos(r) + Vector3(0, 0, 1) * sin(r)) * 0.027, Vector3.ONE * 0.014, back, 5, 3)
		for k in 50:
			_blob(st, _on_trunk(p, rng.randf_range(-l * 1.1, l * 1.05), rng.randf_range(-PI * 0.9, PI * 0.9), 0.006), Vector3.ONE * rng.randf_range(0.008, 0.013), back, 5, 3)
	elif coat == "shaggy":
		# A bear's coat: long hair lying in clumps of lighter and darker brown.
		for k in 40:
			var rad := t * rng.randf_range(0.14, 0.2)
			var c := _on_trunk(p, rng.randf_range(-l * 1.05, l * 1.0), rng.randf_range(-PI * 0.8, PI * 0.8), rad * 0.75)
			_blob(st, c, Vector3(rad, rad, rad * 1.4), color.lerp(back, rng.randf_range(0.0, 0.6)).lightened(rng.randf_range(0.0, 0.08)), 7, 4)
	if p.get("crest", false):
		# The hyena's mane: long ash-grey hair, dark at the tips, from the nape to the rump.
		var crest: Array = []
		for k in 16:
			crest.append(_on_trunk(p, -l * 0.95 + k * l * 0.12, 0.0, 0.0))
		var nape := Vector3(0, h + t * 0.45 + w * 0.78, -l * 0.95)
		var poll := _head_rest_for(p) + Vector3(0, -hs * 0.1 + hs * 0.78, hs * 0.55)
		for k in 6:
			crest.push_front(nape.lerp(poll, (k + 1) / 7.0))
		# Overlapping, so the hair reads as one ridge rather than a row of pegs.
		for at in crest:
			_blob(st, at + Vector3(0, t * 0.08, 0), Vector3(0.024, t * 0.22, l * 0.12), color.lerp(back, 0.3), 6, 4)
			_blob(st, at + Vector3(0, t * 0.26, 0.01), Vector3(0.015, t * 0.1, l * 0.1), back, 5, 3)
	if p.has("mane"):
		# A lion's mane: tufts all round the neck and down over the chest.
		var mane: Color = p["mane"]
		var c := Vector3(0, h + t * 0.35, -l * 1.0)
		_blob(st, c, Vector3(w * 1.15, t * 1.15, l * 0.34), mane, 12, 7)
		for k in 14:
			var a := -PI + TAU * k / 14.0
			var tuft := c + Vector3(sin(a) * w * 1.15, cos(a) * t * 1.15, rng.randf_range(-0.05, 0.08))
			_blob(st, tuft, Vector3(w * 0.42, t * 0.42, l * 0.22), mane.darkened(0.06 * (k % 3)), 8, 5)
		for k in 4:
			_blob(st, Vector3((k - 1.5) * w * 0.3, h - t * (0.55 + 0.1 * (k % 2)), -l * (0.92 - k * 0.04)), Vector3(w * 0.3, t * 0.45, l * 0.16), mane.lightened(0.04), 8, 5)
	if p.get("packs", false):
		# A woven blanket over the back, panniers of reed on each side, roped under the belly.
		var red := Color(0.55, 0.18, 0.14)
		var ochre := Color(0.78, 0.58, 0.26)
		_blob(st, Vector3(0, mid + t * 0.84, -0.04), Vector3(w * 1.12, 0.045, l * 0.46), red, 12, 4)
		for k in 3:
			_blob(st, Vector3(0, mid + t * 0.86, -0.04 + (k - 1) * l * 0.28), Vector3(w * 1.14, 0.03, 0.02), ochre, 10, 3)
		for side in [-1.0, 1.0]:
			var basket := Vector3(side * (w + 0.1), mid + 0.04, -0.04)
			_blob(st, basket, Vector3(0.1, 0.17, 0.2), Color(0.66, 0.54, 0.34), 10, 6)
			for k in 3:
				_blob(st, basket + Vector3(side * 0.005, -0.1 + k * 0.1, 0), Vector3(0.102, 0.018, 0.202), Color(0.52, 0.41, 0.25), 10, 3)
			_blob(st, basket + Vector3(0, 0.17, 0), Vector3(0.11, 0.04, 0.21), Color(0.5, 0.4, 0.26), 8, 3)
			_limb(st, basket + Vector3(-side * 0.06, 0.16, 0.0), Vector3(0, mid + t * 0.92, -0.04), 0.008, 0.008, Color(0.62, 0.55, 0.42))
		_limb(st, Vector3(-w * 0.9, mid - t * 0.2, -0.04), Vector3(w * 0.9, mid - t * 0.2, -0.04), 0.01, 0.01, Color(0.62, 0.55, 0.42))
		# Its short upright mane along the top of the neck.
		var neck_top := Vector3(0, h + t * 0.45 + w * 0.78, -l * 0.95)
		var poll := head_at + Vector3(0, -hs * 0.1 + hs * 0.78, hs * 0.55)
		for k in 8:
			var at := neck_top.lerp(poll, (k + 2) / 10.0)
			_blob(st, at + Vector3(0, 0.02, 0), Vector3(0.02, 0.045, 0.032), back, 6, 3)


static func _beast_head(st: SurfaceTool, model: String, p: Dictionary, color: Color) -> void:
	var hs: float = p["head"]
	var sn: float = p["snout"]
	var m := float(p.get("muzzle", 0.5))
	var belly: Color = p["belly"]
	var back: Color = p["back"]
	var cat := bool(p.get("cat", false))
	var ears := str(p["ears"])
	var mask: Color = p.get("mask", belly.lerp(color, 0.4))
	var tip := Vector3(0, -hs * 0.28, -hs * 0.5 - sn)
	# The skull, the forehead and the cheeks.
	_blob(st, Vector3.ZERO, Vector3(hs * 0.88, hs * 0.82, hs), color, 12, 8)
	_blob(st, Vector3(0, hs * 0.3, -hs * 0.35), Vector3(hs * 0.6, hs * 0.45, hs * 0.55), color, 10, 6)
	for side in [-1.0, 1.0]:
		_blob(st, Vector3(side * hs * 0.5, -hs * 0.22, -hs * 0.3), Vector3(hs * 0.42, hs * 0.42, hs * 0.5), color.lerp(belly, 0.2) if cat else color, 9, 6)
		if p.get("ruff", false):
			_blob(st, Vector3(side * hs * 0.72, -hs * 0.28, hs * 0.12), Vector3(hs * 0.4, hs * 0.5, hs * 0.45), color.lerp(belly, 0.4), 9, 6)
	# The muzzle: the bridge of the nose, the upper lip and the nose itself.
	_limb(st, Vector3(0, hs * 0.18, -hs * 0.5), tip + Vector3(0, hs * m * 0.35, hs * 0.05), hs * 0.4, hs * m * 0.4, color)
	_limb(st, Vector3(0, -hs * 0.18, -hs * 0.45), tip, hs * m, hs * m * 0.62, mask)
	var nose: Color = p.get("nose", Color(0.08, 0.06, 0.05))
	_blob(st, tip + Vector3(0, hs * m * 0.32, -hs * m * 0.5), Vector3(hs * m * 0.48, hs * m * 0.3, hs * m * 0.28), nose, 8, 5)
	var hoofed := str(p.get("feet", "")) == "hoof"
	for side in [-1.0, 1.0]:
		_blob(st, tip + Vector3(side * hs * m * 0.22, hs * m * 0.25, -hs * m * 0.72), Vector3(hs * m * 0.1, hs * m * 0.07, hs * m * 0.06), Color(0.04, 0.03, 0.03), 5, 3)
		# Whisker pads, and on the cats the whiskers.
		var pad := tip + Vector3(side * hs * m * 0.42, -hs * m * 0.1, hs * m * 0.25)
		_blob(st, pad, Vector3(hs * m * 0.38, hs * m * 0.36, hs * m * 0.42), mask.lightened(0.06), 8, 5)
		if cat:
			for k in 3:
				_limb(st, pad + Vector3(side * hs * m * 0.3, 0, 0), pad + Vector3(side * hs * 0.95, hs * (0.12 - k * 0.12), hs * 0.32), 0.0025, 0.001, Color(0.95, 0.93, 0.88))
		# Fangs, behind the lip until the mouth opens.
		if not hoofed:
			_limb(st, tip + Vector3(side * hs * m * 0.3, -hs * m * 0.4, hs * m * 0.7), tip + Vector3(side * hs * m * 0.28, -hs * m * 0.4 - hs * 0.16, hs * m * 0.75), hs * 0.04, hs * 0.008, Color(0.95, 0.92, 0.82))
		# Eyes: a dark rim, the iris, the pupil (a cat's is tall), a glint; the brow above.
		var eye := Vector3(side * hs * 0.47, hs * 0.17, -hs * 0.72)
		var look := Vector3(side * 0.55, 0.05, -0.83).normalized()
		_blob(st, eye, Vector3(hs * 0.14, hs * 0.11, hs * 0.11), Color(0.1, 0.07, 0.05), 8, 5)
		_blob(st, eye + look * hs * 0.04, Vector3(hs * 0.11, hs * 0.09, hs * 0.09), p.get("eye", Color(0.5, 0.35, 0.15)), 8, 5)
		_blob(st, eye + look * hs * 0.11, Vector3(hs * 0.045, hs * (0.075 if cat else 0.05), hs * 0.05), Color(0.02, 0.02, 0.02), 6, 4)
		_blob(st, eye + look * hs * 0.15 + Vector3(0, hs * 0.03, 0), Vector3.ONE * hs * 0.02, Color(1, 1, 1), 4, 3)
		_blob(st, eye + Vector3(0, hs * 0.13, hs * 0.04), Vector3(hs * 0.17, hs * 0.06, hs * 0.13), color.darkened(0.12), 7, 4)
		if hoofed:
			# The donkey's pale ring round the eye.
			_blob(st, eye + Vector3(0, 0, hs * 0.03), Vector3(hs * 0.2, hs * 0.17, hs * 0.12), mask, 8, 5)
		# Ears, the inside paler; a cat's are dark behind.
		if ears == "pointed" or ears == "big":
			var wide := 1.3 if ears == "big" else 1.0
			_limb(st, Vector3(side * hs * 0.45, hs * 0.6, 0.0), Vector3(side * hs * 0.66 * wide, hs * 1.6, hs * 0.1), hs * 0.32 * wide, hs * 0.03, color)
			_limb(st, Vector3(side * hs * 0.47, hs * 0.72, -hs * 0.17), Vector3(side * hs * 0.62 * wide, hs * 1.4, -hs * 0.05), hs * 0.2 * wide, hs * 0.02, belly.lightened(0.05))
			_blob(st, Vector3(side * hs * 0.66 * wide, hs * 1.55, hs * 0.1), Vector3.ONE * hs * 0.07, back, 5, 3)
		elif ears == "long":
			var root := Vector3(side * hs * 0.4, hs * 0.6, hs * 0.2)
			var mid_ear := Vector3(side * hs * 0.95, hs * 1.45, hs * 0.75)
			var tip_ear := Vector3(side * hs * 1.4, hs * 2.2, hs * 1.25)
			_limb(st, root, mid_ear, hs * 0.2, hs * 0.3, color)
			_limb(st, mid_ear, tip_ear, hs * 0.3, hs * 0.08, color)
			_limb(st, root.lerp(mid_ear, 0.3) + Vector3(0, 0, -hs * 0.14), mid_ear + Vector3(0, 0, -hs * 0.16), hs * 0.12, hs * 0.18, mask)
			_blob(st, tip_ear, Vector3.ONE * hs * 0.12, back, 6, 4)
		else:
			var ear := Vector3(side * hs * 0.6, hs * 0.72, hs * 0.1)
			_blob(st, ear, Vector3(hs * 0.24, hs * 0.24, hs * 0.1), color.darkened(0.12), 9, 5)
			_blob(st, ear + Vector3(0, -hs * 0.02, -hs * 0.06), Vector3(hs * 0.15, hs * 0.15, hs * 0.05), belly.lerp(Color(0.8, 0.6, 0.55), 0.3), 7, 4)
			if cat:
				_blob(st, ear + Vector3(0, 0, hs * 0.06), Vector3(hs * 0.2, hs * 0.2, hs * 0.05), back, 7, 4)
	if str(p["coat"]) == "rosettes":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(model) + 1
		for k in 14:
			var a := rng.randf_range(-1.2, 1.2)
			var c := Vector3(sin(a) * hs * 0.86, cos(a) * hs * 0.6 + hs * 0.12, rng.randf_range(-hs * 0.55, hs * 0.2))
			_blob(st, c, Vector3.ONE * hs * 0.05, p["back"], 5, 3)
	if p.has("mane"):
		# The mane frames the face in a ring of tufts and swells behind the head.
		var mane: Color = p["mane"]
		_blob(st, Vector3(0, hs * 0.05, hs * 0.65), Vector3(hs * 1.45, hs * 1.55, hs * 1.0), mane, 12, 8)
		for k in 16:
			var a := TAU * k / 16.0
			var tuft := Vector3(cos(a) * hs * 1.05, sin(a) * hs * 1.0 - hs * 0.05, hs * 0.32)
			_blob(st, tuft, Vector3(hs * 0.42, hs * 0.42, hs * 0.55), mane.darkened(0.05 * (k % 3)).lightened(0.04 * (k % 2)), 8, 5)
		_blob(st, Vector3(0, -hs * 0.95, hs * 0.1), Vector3(hs * 0.6, hs * 0.45, hs * 0.5), mane.lightened(0.05), 8, 5)


static func _beast_jaw(st: SurfaceTool, p: Dictionary, color: Color) -> void:
	var hs: float = p["head"]
	var sn: float = p["snout"]
	var m := float(p.get("muzzle", 0.5))
	var belly: Color = p["belly"]
	var mask: Color = p.get("mask", belly.lerp(color, 0.4))
	var end := Vector3(0, -hs * 0.25, -(sn + hs * 0.15))
	_limb(st, Vector3.ZERO, end, hs * m * 0.62, hs * m * 0.4, mask.lerp(belly, 0.3))
	# The tongue inside, seen when the mouth opens; lower fangs at the front.
	_blob(st, end * 0.55 + Vector3(0, hs * m * 0.28, 0), Vector3(hs * m * 0.36, hs * m * 0.12, -end.z * 0.36), Color(0.66, 0.32, 0.32), 8, 4)
	if str(p.get("feet", "")) != "hoof":
		for side in [-1.0, 1.0]:
			var root := end + Vector3(side * hs * m * 0.24, hs * m * 0.2, hs * m * 0.3)
			_limb(st, root, root + Vector3(0, hs * 0.11, hs * 0.02), hs * 0.032, hs * 0.007, Color(0.95, 0.92, 0.82))


## Joints of a leg from the top down: [point, radius]. A hind leg goes forward to the knee, back
## to the hock and down the long foot; a foreleg back to the elbow and straight down.
static func _leg_joints(p: Dictionary, reach: float, hind: bool) -> Array:
	var lt: float = p["leg"]
	var top := Vector3(0, lt * 1.2, 0)
	if str(p.get("feet", "")) == "hoof":
		if hind:
			return [[top, lt * 2.0], [Vector3(0, -reach * 0.32, -lt * 1.0), lt * 1.15], [Vector3(0, -reach * 0.56, lt * 1.6), lt * 0.85], [Vector3(0, -reach * 0.88, lt * 1.2), lt * 0.7]]
		return [[top, lt * 1.7], [Vector3(0, -reach * 0.34, lt * 0.6), lt * 1.1], [Vector3(0, -reach * 0.62, 0.0), lt * 0.85], [Vector3(0, -reach * 0.88, -lt * 0.1), lt * 0.7]]
	if hind:
		return [[top, lt * 2.1], [Vector3(0, -reach * 0.3, -lt * 1.3), lt * 1.15], [Vector3(0, -reach * 0.66, lt * 1.9), lt * 0.8], [Vector3(0, -reach + lt * 0.55, lt * 0.5), lt * 0.7]]
	return [[top, lt * 1.7], [Vector3(0, -reach * 0.36, lt * 0.7), lt * 1.1], [Vector3(0, -reach * 0.84, lt * 0.1), lt * 0.78], [Vector3(0, -reach + lt * 0.55, -lt * 0.25), lt * 0.7]]


## A point `s` (0 top .. 1 foot) down a leg, and the leg's thickness there.
static func _down_leg(joints: Array, s: float) -> Array:
	var f := clampf(s, 0.0, 0.999) * (joints.size() - 1)
	var i := int(f)
	var k := f - i
	return [(joints[i][0] as Vector3).lerp(joints[i + 1][0], k), lerpf(float(joints[i][1]), float(joints[i + 1][1]), k)]


static func _beast_leg(st: SurfaceTool, model: String, p: Dictionary, color: Color, reach: float, hind: bool) -> void:
	var lt: float = p["leg"]
	var coat := str(p["coat"])
	var lower := color.darkened(0.18 if coat == "shaggy" else 0.06)
	var joints := _leg_joints(p, reach, hind)
	for i in joints.size() - 1:
		_limb(st, joints[i][0], joints[i + 1][0], joints[i][1], joints[i + 1][1], color if i == 0 else lower)
	# The shoulder or the haunch at the top of the leg, and the swell of the forearm or shank.
	var top: Vector3 = (joints[0][0] as Vector3).lerp(joints[1][0], 0.45)
	_blob(st, top + Vector3(0, reach * 0.06, 0), Vector3(lt * 1.35, reach * 0.3, lt * (1.9 if hind else 1.5)), color, 10, 6)
	_blob(st, (joints[1][0] as Vector3).lerp(joints[2][0], 0.3), Vector3(lt * 0.95, reach * 0.16, lt * 1.0), lower, 8, 5)
	_beast_foot(st, p, joints[3][0], lower, reach)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(model) + (7 if hind else 3)
	if coat == "stripes":
		# The hyena's legs are barred all the way down.
		for k in 6:
			var d := _down_leg(joints, 0.2 + k * 0.13)
			_blob(st, d[0], Vector3(float(d[1]) * 1.08, 0.012, float(d[1]) * 1.08), p["back"], 9, 3)
	elif coat == "rosettes":
		for k in 9:
			var d := _down_leg(joints, rng.randf_range(0.05, 0.9))
			var a := rng.randf() * TAU
			_blob(st, (d[0] as Vector3) + Vector3(cos(a), 0, sin(a)) * float(d[1]) * 0.82, Vector3.ONE * float(d[1]) * 0.24, p["back"], 5, 3)


## The foot at the bottom of a leg, `at` its last joint; the ground is `reach` below the hip.
static func _beast_foot(st: SurfaceTool, p: Dictionary, at: Vector3, color: Color, reach: float) -> void:
	var lt: float = p["leg"]
	var feet := str(p.get("feet", "paw"))
	if feet == "hoof":
		# The pastern slopes forward to a hard dark hoof, widest at the ground.
		var hoof := Color(0.16, 0.13, 0.11)
		var ground_y := -reach
		var crown := Vector3(0, ground_y + lt * 1.1, at.z - lt * 0.35)
		_limb(st, at, crown, lt * 0.7, lt * 0.75, color)
		_limb(st, crown, Vector3(0, ground_y + lt * 0.15, at.z - lt * 0.55), lt * 0.82, lt * 1.05, hoof)
		_blob(st, Vector3(0, ground_y + lt * 0.12, at.z - lt * 0.55), Vector3(lt * 1.05, lt * 0.12, lt * 1.1), hoof, 9, 3)
		return
	# A paw: the pad, four toes in front, and claws (a cat keeps its claws drawn in).
	var big := feet == "claws"
	var ground_y2 := -reach
	var pad := Vector3(0, ground_y2 + lt * 0.45, at.z - lt * 0.45)
	_blob(st, pad, Vector3(lt * 1.05, lt * 0.5, lt * 1.15), color, 9, 5)
	var dark := Color(0.14, 0.11, 0.09)
	for k in 4:
		var x := (float(k) - 1.5) * lt * 0.55
		var toe := Vector3(x, ground_y2 + lt * 0.32, pad.z - lt * (0.95 - absf(float(k) - 1.5) * 0.18))
		_blob(st, toe, Vector3(lt * 0.32, lt * 0.3, lt * 0.38), color, 6, 4)
		if not bool(p.get("cat", false)):
			var claw := lt * (0.9 if big else 0.35)
			_limb(st, toe + Vector3(0, lt * 0.05, -lt * 0.3), toe + Vector3(0, -lt * 0.25, -lt * 0.3 - claw), lt * 0.12, lt * 0.03, Color(0.82, 0.78, 0.68) if big else dark)


static func _beast_tail(st: SurfaceTool, p: Dictionary, color: Color) -> void:
	var back: Color = p["back"]
	var kind := str(p["tail"])
	# Each tail is drawn for a wolf-sized animal, then scaled to this one.
	var s := float(p["l"]) / 0.42
	var pts: Array = []   # [point, thickness, color]
	if kind == "brush":
		pts = [[Vector3.ZERO, 0.035, color], [Vector3(0, -0.1, 0.1), 0.05, color], [Vector3(0, -0.22, 0.19), 0.062, color], [Vector3(0, -0.33, 0.25), 0.055, color], [Vector3(0, -0.42, 0.28), 0.04, back], [Vector3(0, -0.48, 0.29), 0.015, back]]
	elif kind == "long":
		pts = [[Vector3.ZERO, 0.03, color], [Vector3(0, -0.16, 0.08), 0.028, color], [Vector3(0, -0.32, 0.15), 0.026, color], [Vector3(0, -0.44, 0.24), 0.024, color], [Vector3(0, -0.48, 0.36), 0.022, color], [Vector3(0, -0.42, 0.46), 0.02, back], [Vector3(0, -0.32, 0.5), 0.015, back]]
	elif kind == "tuft":
		pts = [[Vector3.ZERO, 0.028, color], [Vector3(0, -0.14, 0.07), 0.022, color], [Vector3(0, -0.28, 0.12), 0.019, color], [Vector3(0, -0.4, 0.17), 0.017, color], [Vector3(0, -0.47, 0.21), 0.016, color]]
	elif kind == "thin":
		pts = [[Vector3.ZERO, 0.024, color], [Vector3(0, -0.14, 0.05), 0.02, color], [Vector3(0, -0.3, 0.08), 0.016, color], [Vector3(0, -0.46, 0.09), 0.012, back]]
	else:
		_blob(st, Vector3(0, -0.02, 0.03), Vector3(0.06, 0.05, 0.07), color, 7, 4)
		return
	for i in pts.size() - 1:
		_limb(st, (pts[i][0] as Vector3) * s, (pts[i + 1][0] as Vector3) * s, float(pts[i][1]) * s, float(pts[i + 1][1]) * s, pts[i + 1][2])
		if kind == "brush":
			# Long hair: the brush is fuller than its bone.
			_blob(st, ((pts[i][0] as Vector3) + (pts[i + 1][0] as Vector3)) * 0.5 * s, Vector3.ONE * float(pts[i + 1][1]) * s * 1.1, pts[i + 1][2], 8, 5)
	var end: Vector3 = (pts[pts.size() - 1][0] as Vector3) * s
	if kind == "tuft":
		_blob(st, end + Vector3(0, -0.03, 0.01) * s, Vector3(0.035, 0.06, 0.035) * s, p.get("mane", back), 8, 5)
	elif kind == "thin":
		_limb(st, end, end + Vector3(0, -0.14, 0.01) * s, 0.026 * s, 0.01 * s, back)
	elif kind == "long":
		# Dark rings towards the leopard's tail tip.
		for i in [3, 4, 5]:
			_blob(st, ((pts[i][0] as Vector3).lerp(pts[i + 1][0], 0.5)) * s, Vector3.ONE * float(pts[i][1]) * s * 1.06, back if i % 2 == 1 else color, 7, 4)


## Where the head sits when the animal stands: ahead of the shoulders, a little above them.
static func _head_rest_for(p: Dictionary) -> Vector3:
	var h: float = p["h"]
	var l: float = p["l"]
	var lift := 0.22 if str(p["ears"]) == "long" else 0.14
	return Vector3(0, h + lift + float(p["head"]) * 0.5, -l * 1.2 - float(p["head"]) * 0.8)


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
