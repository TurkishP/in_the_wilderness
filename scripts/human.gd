extends Node3D
## A stylised human figure built from primitive meshes, with jointed limbs and a procedural
## walk. Used for the player, the camp people, raiders and bosses.
##
## `look` is a dictionary of indices into OPTIONS, so it can be saved, edited in the character
## creator and randomised. Missing keys count as 0. The figure faces -Z and stands on y = 0.

const OPTIONS := {
	"sex": ["Male", "Female"],
	"skin": ["Fair olive", "Olive", "Tan", "Bronze", "Brown", "Deep brown"],
	"face": ["Oval", "Round", "Square", "Long"],
	"eyes": ["Dark brown", "Brown", "Hazel", "Green", "Grey"],
	"brows": ["Fine", "Heavy", "Arched"],
	"nose": ["Small", "Medium", "Strong"],
	"hair": ["Short", "Shoulder length", "Long", "Tied back", "Braid", "Curly", "Shaved"],
	"hair_color": ["Black", "Dark brown", "Brown", "Auburn", "Grey"],
	"beard": ["None", "Short", "Full"],
	"head": ["Uncovered", "Headcloth", "Headband", "Shawl"],
	"outfit": ["Short tunic", "Long robe", "Robe and cloak", "Scout's leathers"],
	"cloth": ["Undyed linen", "Sand", "Ochre", "Rust", "Madder red", "Olive", "Indigo", "Charcoal"],
	"sash": ["Blue", "Red", "Brown", "Green", "Cream", "Black"],
}
## Order of the rows in the character creator.
const ORDER := ["sex", "skin", "face", "eyes", "brows", "nose", "hair", "hair_color", "beard", "head", "outfit", "cloth", "sash"]
const LABELS := {
	"sex": "Sex", "skin": "Skin", "face": "Face shape", "eyes": "Eyes", "brows": "Brows", "nose": "Nose",
	"hair": "Hair", "hair_color": "Hair color", "beard": "Beard", "head": "Head covering",
	"outfit": "Clothing", "cloth": "Cloth color", "sash": "Sash color",
}

const SKIN_COLORS := [Color(0.87, 0.72, 0.58), Color(0.8, 0.63, 0.47), Color(0.72, 0.54, 0.39), Color(0.62, 0.44, 0.31), Color(0.48, 0.33, 0.23), Color(0.34, 0.23, 0.17)]
const EYE_COLORS := [Color(0.16, 0.1, 0.07), Color(0.36, 0.22, 0.12), Color(0.52, 0.4, 0.18), Color(0.3, 0.47, 0.3), Color(0.47, 0.52, 0.57)]
const HAIR_COLORS := [Color(0.07, 0.06, 0.06), Color(0.17, 0.11, 0.08), Color(0.32, 0.2, 0.12), Color(0.45, 0.22, 0.12), Color(0.62, 0.62, 0.62)]
const CLOTH_COLORS := [Color(0.86, 0.82, 0.72), Color(0.76, 0.66, 0.5), Color(0.74, 0.55, 0.25), Color(0.62, 0.32, 0.2), Color(0.6, 0.18, 0.16), Color(0.42, 0.45, 0.26), Color(0.2, 0.26, 0.48), Color(0.25, 0.24, 0.24)]
const SASH_COLORS := [Color(0.2, 0.32, 0.6), Color(0.65, 0.16, 0.14), Color(0.4, 0.27, 0.17), Color(0.22, 0.45, 0.25), Color(0.9, 0.86, 0.74), Color(0.12, 0.12, 0.13)]
const LEATHER := Color(0.36, 0.25, 0.16)

## Pose of the right arm while it holds a weapon in front of the body.
const HOLD_SHOULDER := 0.2
const HOLD_ELBOW := 1.25

var look := {}
var body: Node3D
var torso: Node3D
var head: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var weapon: Node3D
var weapon_kind := "none"
var stride := 0.55
var _phase := 0.0
var _amp := 0.0
var _time := 0.0
var _busy_r := 0.0
var _busy_l := 0.0
var _rest_wrist := 0.0
var _grip_shift := 0.0   # how far a long weapon slides through the hand during a strike


static func value_name(key: String, l: Dictionary) -> String:
	var names: Array = OPTIONS[key]
	return names[clampi(int(l.get(key, 0)), 0, names.size() - 1)]


## Moves one option forward or back, wrapping round. Women have no beard option.
static func cycle(l: Dictionary, key: String, step: int) -> void:
	var names: Array = OPTIONS[key]
	l[key] = posmod(int(l.get(key, 0)) + step, names.size())
	if int(l.get("sex", 0)) == 1:
		l["beard"] = 0


## A believable random person. sex: 0 male, 1 female, -1 either.
static func random_look(rng: RandomNumberGenerator, sex: int = -1) -> Dictionary:
	var l := {}
	for key in ORDER:
		var names: Array = OPTIONS[key]
		l[key] = rng.randi() % names.size()
	if sex >= 0:
		l["sex"] = sex
	l["skin"] = 1 + rng.randi() % 3
	l["hair_color"] = [0, 0, 1, 1, 2][rng.randi() % 5]
	if int(l["sex"]) == 1:
		l["beard"] = 0
		l["hair"] = [1, 2, 2, 3, 4][rng.randi() % 5]
		l["head"] = [0, 2, 3, 3][rng.randi() % 4]
		l["outfit"] = 1 + rng.randi() % 2
	else:
		l["hair"] = [0, 0, 1, 5, 6, 3][rng.randi() % 6]
		l["head"] = [0, 1, 1, 2][rng.randi() % 4]
	return l


func _i(key: String) -> int:
	var names: Array = OPTIONS[key]
	return clampi(int(look.get(key, 0)), 0, names.size() - 1)


func _add(parent: Node3D, mi: MeshInstance3D, pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## A unit sphere, to be scaled into an ellipsoid. `fine` gives the smoother mesh used for heads.
func _ball(color: Color, fine: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 28 if fine else 16
	s.rings = 14 if fine else 8
	mi.mesh = s
	mi.material_override = Game.mat(color)
	return mi


## A smooth cylinder or cone for torsos and skirts (the shared helper has too few sides).
func _tube(top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 28
	mi.mesh = c
	mi.material_override = Game.mat(color)
	return mi


## Depth (z) of the front of an ellipsoid head with radii `r` at face position (x, y).
func _face_z(x: float, y: float, r: Vector3) -> float:
	var k := 1.0 - (x / r.x) * (x / r.x) - (y / r.y) * (y / r.y)
	return -r.z * sqrt(maxf(k, 0.0))


## opts: cloth_color, sash_color, head_color (Color overrides), scale (float), crown (bool).
func build(l: Dictionary, opts: Dictionary = {}) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	weapon = null
	weapon_kind = "none"
	look = l.duplicate()

	var female := _i("sex") == 1
	var t := 0.88 if female else 1.0              # limb thickness
	var shoulder_w := 0.172 if female else 0.205
	var hip_w := 0.095 if female else 0.085
	var chest_r := 0.155 if female else 0.185
	var waist_r := 0.118 if female else 0.15
	var hip_r := 0.172 if female else 0.155
	scale = Vector3.ONE * (0.95 if female else 1.0) * float(opts.get("scale", 1.0))

	var skin: Color = SKIN_COLORS[_i("skin")]
	var cloth: Color = opts.get("cloth_color", CLOTH_COLORS[_i("cloth")])
	var sash_c: Color = opts.get("sash_color", SASH_COLORS[_i("sash")])
	var hair_c: Color = HAIR_COLORS[_i("hair_color")]
	var outfit := _i("outfit")
	var long_robe := outfit == 1 or outfit == 2
	var leathers := outfit == 3
	stride = 0.3 if long_robe else 0.55

	body = Node3D.new()
	add_child(body)

	# Hips and legs.
	var hips := Node3D.new()
	hips.position.y = 0.92
	body.add_child(hips)
	_add(hips, _ball(cloth), Vector3(0, -0.02, 0), Vector3(hip_r, 0.12, hip_r * 0.72))
	var shin_c := LEATHER if leathers else skin
	var ll := _leg(hips, -hip_w, t, skin, shin_c)
	leg_l = ll[0]
	knee_l = ll[1]
	var lr := _leg(hips, hip_w, t, skin, shin_c)
	leg_r = lr[0]
	knee_r = lr[1]

	# The skirt of the garment hangs from the waist and does not move with the legs.
	var top_y := 0.98
	var hem_y := 0.14 if long_robe else 0.52
	var hem_r := 0.3 if long_robe else 0.235
	var skirt_h := top_y - hem_y
	_add(body, _tube(waist_r + 0.012, hem_r, skirt_h, cloth), Vector3(0, hem_y + skirt_h * 0.5, 0), Vector3(1, 1, 0.78))
	var belt_c := LEATHER if leathers else sash_c
	_add(body, _tube(waist_r + 0.03, waist_r + 0.03, 0.075, belt_c), Vector3(0, 0.975, 0), Vector3(1, 1, 0.7))
	if not leathers:
		var r_at := lerpf(waist_r + 0.012, hem_r, (top_y - 0.84) / skirt_h) * 0.78
		_add(body, Game.mesh_box(Vector3(0.05, 0.26, 0.02), sash_c), Vector3(-0.07, 0.84, -r_at - 0.012))

	# Torso, neck and arms.
	torso = Node3D.new()
	torso.position.y = 0.92
	body.add_child(torso)
	_add(torso, _tube(chest_r, waist_r, 0.5, cloth), Vector3(0, 0.27, 0), Vector3(1, 1, 0.62))
	# A shallow dome closes the top of the torso at the shoulders, flush with its rim.
	_add(torso, _ball(cloth, true), Vector3(0, 0.52, 0), Vector3(chest_r, 0.055, chest_r * 0.62))
	if leathers:
		_add(torso, _tube(chest_r + 0.014, waist_r + 0.014, 0.4, LEATHER), Vector3(0, 0.28, 0), Vector3(1, 1, 0.64))
	_add(torso, Game.mesh_cyl(0.05 * t, 0.056 * t, 0.13, skin), Vector3(0, 0.58, 0))
	var la := _arm(torso, -shoulder_w, t, skin, cloth, long_robe, leathers)
	arm_l = la[0]
	elbow_l = la[1]
	hand_l = la[2]
	var ra := _arm(torso, shoulder_w, t, skin, cloth, long_robe, leathers)
	arm_r = ra[0]
	elbow_r = ra[1]
	hand_r = ra[2]
	if outfit == 2:
		var cloak_c := sash_c.darkened(0.35)
		_add(torso, _tube(0.08, chest_r + 0.075, 0.17, cloak_c), Vector3(0, 0.47, 0.01), Vector3(1.12, 1, 0.76))
		_add(torso, Game.mesh_box(Vector3(shoulder_w * 2.0 + 0.16, 0.98, 0.03), cloak_c), Vector3(0, -0.02, 0.17), Vector3.ONE, Vector3(0.07, 0, 0))

	_build_head(skin, hair_c, sash_c, cloth, female, opts)
	animate(0.0, 0.0)


func _leg(parent: Node3D, x: float, t: float, skin: Color, shin_c: Color) -> Array:
	var hip := Node3D.new()
	hip.position = Vector3(x, 0, 0)
	parent.add_child(hip)
	_add(hip, Game.mesh_capsule(0.078 * t, 0.46, skin), Vector3(0, -0.21, 0))
	var knee := Node3D.new()
	knee.position = Vector3(0, -0.42, 0)
	hip.add_child(knee)
	_add(knee, Game.mesh_capsule(0.058 * t, 0.44, shin_c), Vector3(0, -0.2, 0))
	_add(knee, Game.mesh_box(Vector3(0.1 * t + 0.01, 0.06, 0.25), Color(0.3, 0.2, 0.13)), Vector3(0, -0.445, -0.05))
	return [hip, knee]


func _arm(parent: Node3D, x: float, t: float, skin: Color, sleeve: Color, long_sleeve: bool, bracer: bool) -> Array:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(x, 0.47, 0)
	shoulder.rotation.z = 0.08 * signf(x)
	parent.add_child(shoulder)
	_add(shoulder, Game.mesh_capsule(0.05 * t, 0.32, skin), Vector3(0, -0.14, 0))
	if long_sleeve:
		_add(shoulder, Game.mesh_capsule(0.06 * t, 0.34, sleeve), Vector3(0, -0.135, 0))
	else:
		_add(shoulder, Game.mesh_capsule(0.06 * t, 0.2, sleeve), Vector3(0, -0.07, 0))
	var elbow := Node3D.new()
	elbow.position = Vector3(0, -0.28, 0)
	shoulder.add_child(elbow)
	_add(elbow, Game.mesh_capsule(0.043 * t, 0.29, skin), Vector3(0, -0.13, 0))
	if long_sleeve:
		_add(elbow, Game.mesh_capsule(0.057 * t, 0.2, sleeve), Vector3(0, -0.08, 0))
	if bracer:
		_add(elbow, Game.mesh_cyl(0.052 * t, 0.047 * t, 0.13, LEATHER), Vector3(0, -0.17, 0))
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.29, 0)
	elbow.add_child(hand)
	_add(hand, _ball(skin), Vector3.ZERO, Vector3(0.04, 0.056, 0.05) * t)
	return [shoulder, elbow, hand]


func _build_head(skin: Color, hair_c: Color, sash_c: Color, cloth: Color, female: bool, opts: Dictionary) -> void:
	head = Node3D.new()
	head.position.y = 0.72
	torso.add_child(head)
	var face := _i("face")
	var skull_s: Vector3 = [Vector3(0.92, 1.1, 1.0), Vector3(1.0, 1.04, 1.0), Vector3(0.98, 1.06, 1.0), Vector3(0.87, 1.17, 0.98)][face]
	var chin_s: Vector3 = [Vector3(0.85, 0.95, 0.95), Vector3(0.92, 0.85, 0.92), Vector3(1.2, 0.9, 1.0), Vector3(0.8, 1.15, 0.95)][face]
	var r := skull_s * 0.115          # radii of the skull ellipsoid
	var wide := skull_s.x / 0.92
	_add(head, _ball(skin, true), Vector3.ZERO, r)
	# The chin sits low and forward, so its seam falls under the mouth rather than across the face.
	_add(head, _ball(skin, true), Vector3(0, -0.092, -0.03), chin_s * 0.062)

	# Face. Each feature is placed on the front surface of the skull.
	var eye_c: Color = EYE_COLORS[_i("eyes")]
	var brows := _i("brows")
	var brow_h: float = [0.005, 0.009, 0.006][brows]
	var brow_tilt: float = [0.06, 0.04, 0.26][brows]
	var nose_k: float = [0.8, 1.0, 1.25][_i("nose")]
	var ez := _face_z(0.04, 0.012, r)
	var bz := _face_z(0.04, 0.038, r)
	for side in [-1.0, 1.0]:
		var sx: float = side
		_add(head, _ball(skin), Vector3(r.x * 0.97 * sx, -0.005, 0.01), Vector3(0.012, 0.028, 0.02))
		_add(head, _ball(Color(0.95, 0.94, 0.9)), Vector3(0.04 * sx, 0.012, ez + 0.002), Vector3(0.019, 0.0115, 0.006))
		_add(head, _ball(eye_c), Vector3(0.04 * sx, 0.011, ez - 0.002), Vector3(0.0085, 0.0085, 0.004))
		_add(head, _ball(Color(0.02, 0.02, 0.02)), Vector3(0.04 * sx, 0.011, ez - 0.0045), Vector3(0.0042, 0.0042, 0.002))
		_add(head, _ball(skin.darkened(0.04)), Vector3(0.04 * sx, 0.0225, ez - 0.0005), Vector3(0.022, 0.0065, 0.008))
		_add(head, Game.mesh_box(Vector3(0.04, brow_h, 0.008), hair_c), Vector3(0.04 * sx, 0.038, bz - 0.003), Vector3.ONE, Vector3(0, 0, -brow_tilt * sx))
	var nose_c := skin.darkened(0.05)
	_add(head, _ball(nose_c), Vector3(0, 0.0, _face_z(0.0, 0.0, r) - 0.003), Vector3(0.0095 * nose_k, 0.028, 0.012), Vector3(-0.25, 0, 0))
	_add(head, _ball(nose_c), Vector3(0, -0.028, _face_z(0.0, -0.028, r) - 0.011), Vector3(0.016, 0.012, 0.015) * nose_k)
	var lip_c := skin.darkened(0.28).lerp(Color(0.62, 0.22, 0.2), 0.45 if female else 0.18)
	_add(head, _ball(lip_c), Vector3(0, -0.066, _face_z(0.0, -0.066, r) - 0.002), Vector3(0.024, 0.0055, 0.006))

	var covering := _i("head")
	var covered := covering == 1 or covering == 3
	if not covered:
		_build_hair(hair_c, skin, skull_s)
	var beard := 0 if female else _i("beard")
	if beard > 0:
		_add(head, _ball(hair_c), Vector3(0, -0.05, _face_z(0.0, -0.05, r) - 0.003), Vector3(0.03, 0.006, 0.007))
		if beard == 1:
			_add(head, _ball(hair_c), Vector3(0, -0.1, -0.035), Vector3(0.07 * chin_s.x, 0.045, 0.062))
		else:
			_add(head, _ball(hair_c), Vector3(0, -0.128, -0.032), Vector3(0.082 * chin_s.x, 0.095, 0.07))

	var head_c: Color = opts.get("head_color", Color(0.9, 0.86, 0.76) if covering == 1 else cloth.lightened(0.25))
	match covering:
		1:  # headcloth with a band, falling to the neck
			_add(head, _ball(head_c, true), Vector3(0, 0.05, 0.04), Vector3(0.126 * wide, 0.127, 0.13))
			_add(head, _ball(head_c), Vector3(0, -0.1, 0.085), Vector3(0.12, 0.19, 0.058))
			_add(head, _tube(0.1215, 0.1215, 0.022, sash_c), Vector3(0, 0.09, 0.04), Vector3(wide, 1, 1.03), Vector3(0.1, 0, 0))
		2:  # plain headband over the hair
			_add(head, _tube(0.1195, 0.1195, 0.02, sash_c), Vector3(0, 0.075, 0.028), Vector3(wide, 1, 1.02), Vector3(0.1, 0, 0))
		3:  # shawl over the head and shoulders
			_add(head, _ball(head_c, true), Vector3(0, 0.05, 0.04), Vector3(0.127 * wide, 0.128, 0.131))
			_add(head, _ball(head_c), Vector3(0, -0.17, 0.07), Vector3(0.19, 0.24, 0.095))
	if bool(opts.get("crown", false)):
		_add(head, _tube(0.124, 0.124, 0.034, Color(0.9, 0.72, 0.2)), Vector3(0, 0.1, 0.04), Vector3(wide, 1, 1.03), Vector3(0.1, 0, 0))


func _build_hair(hair_c: Color, skin: Color, skull_s: Vector3) -> void:
	var style := _i("hair")
	var wide := skull_s.x / 0.92
	if style == 6:
		# Shaved: a shadow of stubble just above the scalp.
		_add(head, _ball(skin.lerp(hair_c, 0.4), true), Vector3(0, 0.022, 0.016), Vector3(0.113 * wide, 0.121, 0.118))
		return
	var cap := 1.08 if style == 5 else 1.0
	_add(head, _ball(hair_c, true), Vector3(0, 0.035, 0.028), Vector3(0.123 * wide, 0.128, 0.126) * cap)
	match style:
		1:
			_add(head, _ball(hair_c), Vector3(0, -0.07, 0.065), Vector3(0.118 * wide, 0.16, 0.075))
		2:
			_add(head, _ball(hair_c), Vector3(0, -0.19, 0.078), Vector3(0.12 * wide, 0.3, 0.07))
		3:
			_add(head, _ball(hair_c), Vector3(0, 0.0, 0.13), Vector3(0.052, 0.052, 0.052))
		4:
			_add(head, Game.mesh_capsule(0.03, 0.44, hair_c), Vector3(0, -0.22, 0.112), Vector3.ONE, Vector3(0.1, 0, 0))
			_add(head, _ball(hair_c), Vector3(0, -0.02, 0.105), Vector3(0.06, 0.07, 0.05))
		5:
			for k in 9:
				var a := TAU * k / 9.0
				_add(head, _ball(hair_c), Vector3(sin(a) * 0.092 * wide, 0.075, 0.03 + cos(a) * 0.095), Vector3.ONE * 0.05)
			_add(head, _ball(hair_c), Vector3(0, 0.14, 0.03), Vector3.ONE * 0.055)


# ---------------------------------------------------------------- weapons

## kind: none, staff, spear, dagger, sickle, sword. The right arm holds it out in front.
func set_weapon(kind: String) -> void:
	if weapon != null:
		hand_r.remove_child(weapon)
		weapon.queue_free()
		weapon = null
	weapon_kind = kind
	_rest_wrist = 0.0
	_grip_shift = 0.6 if kind == "staff" or kind == "spear" else 0.0
	if kind != "none":
		weapon = Node3D.new()
		hand_r.add_child(weapon)
		var wood := Color(0.42, 0.28, 0.16)
		var bronze := Color(0.8, 0.6, 0.3)
		var iron := Color(0.66, 0.68, 0.72)
		var tilt := 0.0   # how far the weapon leans forward from upright while held
		match kind:
			"staff":
				_add(weapon, Game.mesh_cyl(0.022, 0.028, 1.75, wood), Vector3(0, -0.17, 0))
			"spear":
				_add(weapon, Game.mesh_cyl(0.018, 0.02, 1.9, wood), Vector3(0, -0.1, 0))
				_add(weapon, Game.mesh_cyl(0.0, 0.035, 0.24, bronze), Vector3(0, 0.97, 0))
			"dagger":
				_blade(0.3, bronze)
				tilt = 0.9
			"sickle":
				_blade(0.44, bronze)
				_add(weapon, Game.mesh_box(Vector3(0.045, 0.16, 0.012), bronze), Vector3(0, 0.56, -0.045), Vector3.ONE, Vector3(-0.75, 0, 0))
				tilt = 0.8
			_:
				_blade(0.68, iron)
				tilt = 0.8
		_rest_wrist = -(HOLD_SHOULDER + HOLD_ELBOW) - tilt
	hand_r.rotation.x = _rest_wrist
	animate(0.0, 0.0)


func _blade(length: float, color: Color) -> void:
	_add(weapon, Game.mesh_cyl(0.018, 0.018, 0.13, Color(0.3, 0.2, 0.13)), Vector3.ZERO)
	_add(weapon, Game.mesh_box(Vector3(0.03, 0.022, 0.11), color), Vector3(0, 0.07, 0))
	_add(weapon, Game.mesh_box(Vector3(0.012, length, 0.05), color), Vector3(0, 0.08 + length * 0.5, 0))


# ---------------------------------------------------------------- animation

## Call every frame with the horizontal speed in metres per second (0 when standing).
func animate(delta: float, speed: float) -> void:
	if body == null:
		return
	_time += delta
	var target := clampf(speed / 6.0, 0.0, 1.4) * stride
	_amp = lerpf(_amp, target, 1.0 - exp(-12.0 * delta))
	_phase += delta * (3.0 + speed * 1.2)
	var s := sin(_phase)
	var c := cos(_phase)
	leg_l.rotation.x = s * _amp
	leg_r.rotation.x = -s * _amp
	knee_l.rotation.x = -maxf(0.0, c) * _amp * 1.5
	knee_r.rotation.x = -maxf(0.0, -c) * _amp * 1.5
	body.position.y = absf(c) * 0.035 * _amp / stride
	torso.rotation.x = -0.13 * clampf(speed / 9.5, 0.0, 1.0)
	var sway := sin(_time * 1.4) * 0.025
	_busy_l -= delta
	_busy_r -= delta
	if _busy_l <= 0.0:
		arm_l.rotation.x = -s * _amp * 0.85 + sway
		elbow_l.rotation.x = 0.15 + _amp * 0.6
	if _busy_r <= 0.0:
		if weapon_kind != "none":
			arm_r.rotation.x = HOLD_SHOULDER + s * _amp * 0.12
			elbow_r.rotation.x = HOLD_ELBOW
			hand_r.rotation.x = _rest_wrist
		else:
			arm_r.rotation.x = s * _amp * 0.85 - sway
			elbow_r.rotation.x = 0.15 + _amp * 0.6


## A strike with the right arm: raise, chop forward, recover. Takes about 0.4 s.
func swing() -> void:
	if arm_r == null:
		return
	_busy_r = 0.42
	var tw := create_tween()
	if weapon_kind == "none":
		tw.tween_property(arm_r, "rotation:x", 1.5, 0.1)
		tw.parallel().tween_property(elbow_r, "rotation:x", 0.3, 0.1)
		tw.tween_property(arm_r, "rotation:x", 0.0, 0.26)
		return
	tw.tween_property(arm_r, "rotation:x", 1.25, 0.07)
	tw.parallel().tween_property(hand_r, "rotation:x", _rest_wrist + 0.55, 0.07)
	tw.parallel().tween_property(weapon, "position:y", _grip_shift, 0.07)
	tw.tween_property(arm_r, "rotation:x", 0.55, 0.09)
	tw.parallel().tween_property(hand_r, "rotation:x", _rest_wrist - 1.45, 0.09)
	tw.tween_property(arm_r, "rotation:x", HOLD_SHOULDER, 0.22)
	tw.parallel().tween_property(hand_r, "rotation:x", _rest_wrist, 0.22)
	tw.parallel().tween_property(weapon, "position:y", 0.0, 0.22)


## The left arm whirls and releases a sling stone. Takes about 0.4 s.
func whirl() -> void:
	if arm_l == null:
		return
	_busy_l = 0.42
	var tw := create_tween()
	tw.tween_property(arm_l, "rotation:x", -0.7, 0.08)
	tw.tween_property(arm_l, "rotation:x", 2.7, 0.14)
	tw.tween_property(arm_l, "rotation:x", 0.0, 0.2)
