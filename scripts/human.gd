extends Node3D
## A modelled, rigged human (Quaternius "Universal Base Characters", CC0) wearing clothes that
## are generated in code to fit the body. Used for the player, camp people, raiders and bosses.
##
## `look` is a dictionary of indices into OPTIONS, so it can be saved, edited in the character
## creator and randomised. Missing keys count as 0. The figure faces -Z and stands on y = 0.
##
## How the clothes are made (see the "garments" section):
##   - close-fitting pieces (tunic top, sleeves, vest, cap, shoes) are copies of part of the
##     body mesh pushed outward along its normals, so they bend with the body
##   - loose pieces (skirt, sash, cloak) are tubes or sheets sized from cross-sections of the
##     body and weighted to the hip and leg bones
## Everything is measured from the mesh, so the same code fits the male and the female body.

const Retarget := preload("res://scripts/retarget.gd")
const DIR := "res://assets/characters/"

const OPTIONS := {
	"sex": ["Male", "Female"],
	"skin": ["Fair olive", "Olive", "Tan", "Bronze", "Brown", "Deep brown"],
	"face": ["Oval", "Round", "Long", "Broad"],
	"eyes": ["Dark brown", "Brown", "Hazel", "Green", "Grey"],
	"brows": ["Heavy", "Fine"],
	"hair": ["Short", "Parted", "Long", "Buns", "Shaved"],
	"hair_color": ["Black", "Dark brown", "Brown", "Auburn", "Grey"],
	"beard": ["None", "Full"],
	"head": ["Uncovered", "Headcloth", "Headband", "Shawl"],
	"outfit": ["Short tunic", "Long robe", "Robe and cloak", "Scout's leathers"],
	"cloth": ["Undyed linen", "Sand", "Ochre", "Rust", "Madder red", "Olive", "Indigo", "Charcoal"],
	"sash": ["Blue", "Red", "Brown", "Green", "Cream", "Black"],
}
## Order of the rows in the character creator.
const ORDER := ["sex", "skin", "face", "eyes", "brows", "hair", "hair_color", "beard", "head", "outfit", "cloth", "sash"]
const LABELS := {
	"sex": "Sex", "skin": "Skin", "face": "Face shape", "eyes": "Eyes", "brows": "Brows",
	"hair": "Hair", "hair_color": "Hair color", "beard": "Beard", "head": "Head covering",
	"outfit": "Clothing", "cloth": "Cloth color", "sash": "Sash color",
}

## The skin texture is fair olive; darker tones multiply it.
const SKIN_TINTS := [Color(1, 1, 1), Color(0.92, 0.875, 0.81), Color(0.83, 0.75, 0.67), Color(0.71, 0.61, 0.53), Color(0.55, 0.46, 0.4), Color(0.39, 0.32, 0.29)]
## Face shape is a scale on the head bone.
const HEAD_SCALES := [Vector3(1, 1, 1), Vector3(1.05, 0.97, 1.03), Vector3(0.95, 1.05, 0.98), Vector3(1.07, 1.0, 1.0)]
const HAIR_COLORS := [Color(0.1, 0.09, 0.09), Color(0.24, 0.16, 0.11), Color(0.42, 0.27, 0.16), Color(0.58, 0.29, 0.16), Color(0.75, 0.75, 0.75)]
const CLOTH_COLORS := [Color(0.86, 0.82, 0.72), Color(0.76, 0.66, 0.5), Color(0.74, 0.55, 0.25), Color(0.62, 0.32, 0.2), Color(0.6, 0.18, 0.16), Color(0.42, 0.45, 0.26), Color(0.2, 0.26, 0.48), Color(0.25, 0.24, 0.24)]
const SASH_COLORS := [Color(0.2, 0.32, 0.6), Color(0.65, 0.16, 0.14), Color(0.4, 0.27, 0.17), Color(0.22, 0.45, 0.25), Color(0.9, 0.86, 0.74), Color(0.12, 0.12, 0.13)]
const LEATHER := Color(0.36, 0.25, 0.16)
## Hair meshes by "hair" index. "" = no hair mesh.
const HAIR_FILES := ["hair_buzzed", "hair_parted", "hair_long", "hair_buns", ""]

const ANIMS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Sword_Attack", "Spell_Simple_Shoot", "Punch_Cross", "Death01",
	"Sitting_Idle", "Sitting_Talking", "Fixing_Kneeling"]
## The strike animation is long; it is played faster so the blow lands quickly.
const STRIKE_SPEED := 2.0
## The blade is furthest forward 0.46 s into the clip (measured), and the clip is 1.53 s long.
const STRIKE_HIT := 0.46 / STRIKE_SPEED
const STRIKE_TIME := 1.53 / STRIKE_SPEED
const UPPER_BODY := ["spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "clavicle_r",
	"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"]
const FINGERS := ["index", "middle", "ring", "pinky", "thumb"]

static var _bodies := {}     # sex -> measured body data
static var _meshes := {}     # "sex/piece" -> generated ArrayMesh
static var _materials := {}  # key -> StandardMaterial3D
static var _libraries := {}  # sex -> AnimationLibrary retargeted to that body

var look := {}
var weapon_kind := "none"
var weapon: Node3D
var skeleton: Skeleton3D
var head: BoneAttachment3D        # things worn on the head hang from this
var hand_r: BoneAttachment3D      # the weapon hangs from this
var garments: Array = []          # names of the generated clothing pieces, for checks
var dead := false
var posed := false               # holding a sitting or kneeling pose instead of standing and walking
var _model: Node3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _speed := 0.0
var _opts := {}
var _carry := Transform3D.IDENTITY    # how the weapon sits in the hand while walking about
var _strike := Transform3D.IDENTITY   # how it sits during a blow
var _strike_left := 0.0               # seconds until the weapon returns to the carry position


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
		l["hair"] = [2, 2, 3, 1][rng.randi() % 4]
		l["head"] = [0, 2, 3, 3][rng.randi() % 4]
		l["outfit"] = 1 + rng.randi() % 2
	else:
		l["hair"] = [0, 0, 1, 1, 4][rng.randi() % 5]
		l["head"] = [0, 1, 1, 2][rng.randi() % 4]
	return l


func _i(key: String) -> int:
	var names: Array = OPTIONS[key]
	return clampi(int(look.get(key, 0)), 0, names.size() - 1)


# ================================================================ building

## opts: cloth_color, sash_color, head_color (Color overrides), scale (float), crown (bool),
## always_animate (bool: keep animating while the game is paused, for the character creator).
func build(l: Dictionary, opts: Dictionary = {}) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	weapon = null
	weapon_kind = "none"
	garments = []
	dead = false
	posed = false
	look = l.duplicate()
	_opts = opts
	var sex := _i("sex")
	var d := _body(sex)
	scale = Vector3.ONE * float(opts.get("scale", 1.0))

	var scene: PackedScene = d["scene"]
	_model = scene.instantiate()
	_model.rotation.y = PI      # the model faces +Z; figures in this game face -Z
	add_child(_model)
	skeleton = _model.find_child("Skeleton3D", true, false)
	var body_mi: MeshInstance3D = skeleton.get_node(str(d["body_name"]))
	var eyes_mi: MeshInstance3D = skeleton.get_node("Eyes")
	var brows_mi: MeshInstance3D = skeleton.get_node("Eyebrows")

	var hair_c: Color = HAIR_COLORS[_i("hair_color")]
	body_mi.material_override = _skin_material(sex, _i("skin"))
	eyes_mi.material_override = _eye_material(_i("eyes"))
	skeleton.set_bone_pose_scale(skeleton.find_bone("Head"), HEAD_SCALES[_i("face")])

	head = BoneAttachment3D.new()
	head.bone_name = "Head"
	skeleton.add_child(head)
	hand_r = BoneAttachment3D.new()
	hand_r.bone_name = "hand_r"
	skeleton.add_child(hand_r)

	# Brows: the body's own set is "heavy" on the man and "fine" on the woman. For the other
	# choice, hide it and hang the other set on the head.
	var own_brows := 0 if sex == 0 else 1
	if _i("brows") == own_brows:
		brows_mi.material_override = _hair_material(_texture_index(brows_mi), hair_c)
	else:
		brows_mi.visible = false
		_attach_to_head("brows_regular" if _i("brows") == 0 else "brows_female", hair_c, sex)

	var covering := _i("head")
	var covered := covering == 1 or covering == 3
	var hair_file: String = HAIR_FILES[_i("hair")]
	if hair_file == "hair_buzzed" and sex == 1:
		hair_file = "hair_buzzed_f"
	if hair_file != "" and not covered:
		_attach_to_head(hair_file, hair_c, sex)
	if sex == 0 and _i("beard") == 1:
		_attach_to_head("beard", hair_c, sex)

	_dress(sex, d, body_mi, opts)
	_setup_animation(sex)


## Measures one body once: bones, vertex ownership, and the places clothes are fitted to.
static func _body(sex: int) -> Dictionary:
	if _bodies.has(sex):
		return _bodies[sex]
	var scene: PackedScene = load(DIR + ("female.gltf" if sex == 1 else "male.gltf"))
	var inst: Node3D = scene.instantiate()
	var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false)
	var body_mi: MeshInstance3D = null
	for c in sk.get_children():
		if c is MeshInstance3D and c.name != "Eyes" and c.name != "Eyebrows":
			body_mi = c
	var arrays: Array = body_mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per: int = bones.size() / verts.size()

	# Mesh bone numbers index the skin's bind list, which need not match the skeleton's order.
	var skin: Skin = body_mi.skin
	var bind := {}          # bone name -> bind index
	for b in skin.get_bind_count():
		var bone_name := str(skin.get_bind_name(b))
		if bone_name == "" and skin.get_bind_bone(b) >= 0:
			bone_name = sk.get_bone_name(skin.get_bind_bone(b))
		bind[bone_name] = b
	var rest := {}          # bone name -> rest position in model space
	for b in sk.get_bone_count():
		rest[sk.get_bone_name(b)] = sk.get_bone_global_rest(b).origin

	# The bone each vertex follows most.
	var owner := PackedInt32Array()
	owner.resize(verts.size())
	for v in verts.size():
		var best := 0
		var best_w := -1.0
		for k in per:
			if weights[v * per + k] > best_w:
				best_w = weights[v * per + k]
				best = bones[v * per + k]
		owner[v] = best

	# Smooth normals shared by vertices at the same place, so pushed-out shells do not split
	# along texture seams.
	var sums := {}
	for v in verts.size():
		var key := Vector3i((verts[v] * 2000.0).round())
		if sums.has(key):
			sums[key] = (sums[key] as Vector3) + normals[v]
		else:
			sums[key] = normals[v]
	var smooth := PackedVector3Array()
	smooth.resize(verts.size())
	for v in verts.size():
		smooth[v] = (sums[Vector3i((verts[v] * 2000.0).round())] as Vector3).normalized()

	var head_bind: int = bind["Head"]
	var head_lo := Vector3.ONE * 1e9
	var head_hi := Vector3.ONE * -1e9
	for v in verts.size():
		if owner[v] == head_bind:
			head_lo = head_lo.min(verts[v])
			head_hi = head_hi.max(verts[v])
	var brows_aabb: AABB = (sk.get_node("Eyebrows") as MeshInstance3D).mesh.get_aabb()
	var eyes_aabb: AABB = (sk.get_node("Eyes") as MeshInstance3D).mesh.get_aabb()

	var d := {
		"scene": scene, "body_name": str(body_mi.name), "skin": skin, "per": per,
		"verts": verts, "normals": smooth, "bones": bones, "weights": weights, "indices": arrays[Mesh.ARRAY_INDEX],
		"owner": owner, "bind": bind, "rest": rest,
		"head_rest": sk.get_bone_global_rest(sk.find_bone("Head")),
		"head_top": head_hi.y, "head_lo": head_lo, "head_hi": head_hi,
		"brow_top": brows_aabb.position.y + brows_aabb.size.y, "brow_y": brows_aabb.get_center().y,
		"eye_y": eyes_aabb.get_center().y,
	}
	_bodies[sex] = d
	inst.free()
	return d


func _texture(file: String) -> Texture2D:
	return load(DIR + "tex/" + file)


func _skin_material(sex: int, tone: int) -> StandardMaterial3D:
	var key := "skin/%d/%d" % [sex, tone]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _texture("skin_female.png" if sex == 1 else "skin_male.png")
		m.albedo_color = SKIN_TINTS[tone]
		m.normal_enabled = true
		m.normal_texture = _texture("normal_female.png" if sex == 1 else "normal_male.png")
		m.roughness = 0.8
		_materials[key] = m
	return _materials[key]


func _eye_material(color: int) -> StandardMaterial3D:
	var key := "eye/%d" % color
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _texture("eye_%d.png" % color)
		m.roughness = 0.35
		_materials[key] = m
	return _materials[key]


## The kit has two hair texture sheets; a mesh's original material name says which it uses.
func _texture_index(mi: MeshInstance3D) -> int:
	var mat := mi.mesh.surface_get_material(0)
	return 2 if mat != null and str(mat.resource_name).ends_with("2") else 1


func _hair_material(sheet: int, color: Color) -> StandardMaterial3D:
	var key := "hair/%d/%s" % [sheet, color.to_html()]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _texture("hair_%d.png" % sheet)
		# The sheets are light grey, made to be tinted. Lift the tint so colors keep their strength.
		m.albedo_color = Color(color.r * 1.35, color.g * 1.35, color.b * 1.35)
		m.normal_enabled = true
		m.normal_texture = _texture("hair_%d_normal.png" % sheet)
		m.roughness = 0.7
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]


func _cloth_material(color: Color, two_sided: bool = false) -> StandardMaterial3D:
	var key := "cloth/%s/%s" % [color.to_html(), two_sided]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		if two_sided:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]


## Hangs a hair, beard or brow mesh on the head bone. Each mesh in the kit was modelled on one
## of the two bodies; it is moved from that body's head to this one and scaled to its size.
func _attach_to_head(file: String, color: Color, sex: int) -> void:
	var scene: PackedScene = load(DIR + file + ".gltf")
	var inst: Node3D = scene.instantiate()
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	# Some of the kit's meshes are stored scaled and moved, with the correction on their node.
	var placed := placement(mi)
	var fitted := _fitted_sex(file, placed * mi.mesh.get_aabb())
	var from := _body(fitted)
	var to := _body(sex)
	mi.get_parent().remove_child(mi)
	inst.free()
	mi.name = file
	mi.transform = Transform3D.IDENTITY
	mi.material_override = _hair_material(_texture_index(mi), color)
	var holder := Node3D.new()
	holder.name = "holder_" + file
	head.add_child(holder)
	# Model space of the body it was made on -> that body's head bone space.
	var from_head: Transform3D = from["head_rest"]
	holder.transform = from_head.affine_inverse() * placed
	if fitted != sex:
		holder.transform = (to["head_rest"] as Transform3D).affine_inverse() * head_fit(from, to) * placed
	holder.add_child(mi)


## Where a node sits inside the scene file it came from (all parent transforms applied).
static func placement(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## The move that carries something modelled on one body's head onto the other's: scaled about
## the brow line to the new head's width, depth and brow-to-crown height.
static func head_fit(from: Dictionary, to: Dictionary) -> Transform3D:
	var a: Vector3 = (from["head_hi"] as Vector3) - (from["head_lo"] as Vector3)
	var b: Vector3 = (to["head_hi"] as Vector3) - (to["head_lo"] as Vector3)
	var grow := Vector3(b.x / a.x, (float(to["head_top"]) - float(to["brow_y"])) / (float(from["head_top"]) - float(from["brow_y"])), b.z / a.z)
	var anchor := Vector3(0.0, float(from["brow_y"]), ((from["head_lo"] as Vector3).z + (from["head_hi"] as Vector3).z) * 0.5)
	var target := Vector3(0.0, float(to["brow_y"]), ((to["head_lo"] as Vector3).z + (to["head_hi"] as Vector3).z) * 0.5)
	return Transform3D(Basis.from_scale(grow), target - grow * anchor)


## Which body a head mesh was modelled on: the one whose crown or brow line it sits on.
static func _fitted_sex(file: String, aabb: AABB) -> int:
	if file == "beard":
		return 0
	var best := 0
	var best_err := 1e9
	for sex in 2:
		var d := _body(sex)
		var err: float
		if file.begins_with("brows"):
			err = absf(aabb.get_center().y - float(d["brow_y"]))
		else:
			err = absf(aabb.position.y + aabb.size.y - (float(d["head_top"]) + 0.015))
		if err < best_err:
			best_err = err
			best = sex
	return best


# ================================================================ garments

func _dress(sex: int, d: Dictionary, body_mi: MeshInstance3D, opts: Dictionary) -> void:
	var cloth: Color = opts.get("cloth_color", CLOTH_COLORS[_i("cloth")])
	var sash_c: Color = opts.get("sash_color", SASH_COLORS[_i("sash")])
	var outfit := _i("outfit")
	var long_robe := outfit == 1 or outfit == 2
	var leathers := outfit == 3

	_wear(sex, d, body_mi, "top_long" if long_robe else "top_short", cloth)
	_wear(sex, d, body_mi, "skirt_long" if long_robe else "skirt_short", cloth, true)
	_wear(sex, d, body_mi, "sash", LEATHER if leathers else sash_c, true)
	_wear(sex, d, body_mi, "shoes", Color(0.3, 0.2, 0.13))
	if leathers:
		_wear(sex, d, body_mi, "vest", LEATHER)
		_wear(sex, d, body_mi, "bracers", LEATHER)
		_wear(sex, d, body_mi, "leg_wraps", LEATHER)
	if outfit == 2:
		var cloak_c := sash_c.darkened(0.35)
		_wear(sex, d, body_mi, "mantle", cloak_c)
		_wear(sex, d, body_mi, "cloak", cloak_c, true)

	var covering := _i("head")
	var head_c: Color = opts.get("head_color", Color(0.9, 0.86, 0.76) if covering == 1 else cloth.lightened(0.25))
	match covering:
		1:
			_wear(sex, d, body_mi, "cap", head_c)
			_wear(sex, d, body_mi, "band", sash_c, true)
		2:
			_wear(sex, d, body_mi, "band_wide", sash_c, true)
		3:
			_wear(sex, d, body_mi, "cap", head_c)
			_wear(sex, d, body_mi, "shawl", head_c)
	if bool(opts.get("crown", false)):
		_wear(sex, d, body_mi, "crown", Color(0.9, 0.72, 0.2), true)


## Adds one clothing piece as a mesh skinned to the body's skeleton.
func _wear(sex: int, d: Dictionary, body_mi: MeshInstance3D, piece: String, color: Color, two_sided: bool = false) -> void:
	var key := "%d/%s" % [sex, piece]
	if not _meshes.has(key):
		_meshes[key] = _make_piece(d, piece)
	var mesh: ArrayMesh = _meshes[key]
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = piece
	mi.mesh = mesh
	mi.skin = body_mi.skin
	mi.material_override = _cloth_material(color, two_sided)
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	garments.append(piece)


static func _make_piece(d: Dictionary, piece: String) -> ArrayMesh:
	var bind: Dictionary = d["bind"]
	var rest: Dictionary = d["rest"]
	var torso := _bind_set(bind, ["pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"])
	var upper_l: int = bind["upperarm_l"]
	var upper_r: int = bind["upperarm_r"]
	var lower_l: int = bind["lowerarm_l"]
	var lower_r: int = bind["lowerarm_r"]
	var choose: Callable
	match piece:
		"top_short":
			choose = func(p: Vector3, o: int) -> bool:
				if torso.has(o):
					return true
				if o == upper_l:
					return _along(p, rest, "upperarm_l", "lowerarm_l") < 0.55
				if o == upper_r:
					return _along(p, rest, "upperarm_r", "lowerarm_r") < 0.55
				return false
			return _shell(d, 0.018, choose)
		"top_long":
			choose = func(p: Vector3, o: int) -> bool:
				if torso.has(o) or o == upper_l or o == upper_r:
					return true
				if o == lower_l:
					return _along(p, rest, "lowerarm_l", "hand_l") < 0.85
				if o == lower_r:
					return _along(p, rest, "lowerarm_r", "hand_r") < 0.85
				return false
			return _shell(d, 0.018, choose)
		"vest":
			var chest := _bind_set(bind, ["spine_01", "spine_02", "spine_03"])
			choose = func(_p: Vector3, o: int) -> bool:
				return chest.has(o)
			return _shell(d, 0.034, choose)
		"mantle", "shawl":
			# Over the shoulders and the top of the arms.
			var shoulders := _bind_set(bind, ["spine_03", "clavicle_l", "clavicle_r"])
			var line: float = (rest["spine_03"] as Vector3).y + 0.04
			choose = func(p: Vector3, o: int) -> bool:
				if shoulders.has(o):
					return p.y > line
				if o == upper_l:
					return _along(p, rest, "upperarm_l", "lowerarm_l") < 0.3
				if o == upper_r:
					return _along(p, rest, "upperarm_r", "lowerarm_r") < 0.3
				return false
			return _shell(d, 0.045 if piece == "mantle" else 0.03, choose)
		"bracers":
			choose = func(p: Vector3, o: int) -> bool:
				if o == lower_l:
					return _between(_along(p, rest, "lowerarm_l", "hand_l"), 0.3, 0.92)
				if o == lower_r:
					return _between(_along(p, rest, "lowerarm_r", "hand_r"), 0.3, 0.92)
				return false
			return _shell(d, 0.012, choose)
		"leg_wraps":
			var calf_l: int = bind["calf_l"]
			var calf_r: int = bind["calf_r"]
			choose = func(p: Vector3, o: int) -> bool:
				if o == calf_l:
					return _between(_along(p, rest, "calf_l", "foot_l"), 0.12, 0.95)
				if o == calf_r:
					return _between(_along(p, rest, "calf_r", "foot_r"), 0.12, 0.95)
				return false
			return _shell(d, 0.01, choose)
		"shoes":
			var feet := _bind_set(bind, ["foot_l", "foot_r", "ball_l", "ball_r"])
			choose = func(_p: Vector3, o: int) -> bool:
				return feet.has(o)
			return _shell(d, 0.008, choose)
		"cap":
			# The crown and back of the head down to the nape, leaving the face open.
			var head_b: int = bind["Head"]
			var neck_b: int = bind["neck_01"]
			var mid_z: float = ((d["head_lo"] as Vector3).z + (d["head_hi"] as Vector3).z) * 0.5
			var brow: float = float(d["brow_top"]) + 0.03
			var ear: float = float(d["eye_y"]) - 0.05
			choose = func(p: Vector3, o: int) -> bool:
				if o == head_b:
					return p.y > brow or (p.z < mid_z - 0.015 and p.y > ear)
				if o == neck_b:
					return p.z < mid_z - 0.01
				return false
			return _shell(d, 0.014, choose)
		"band":
			return _ring(d, float(d["brow_top"]) + 0.05, 0.022, 0.02, ["Head"], ["Head"])
		"band_wide":
			# Sits over hair, so it stands further off the skull.
			return _ring(d, float(d["brow_top"]) + 0.05, 0.026, 0.034, ["Head"], ["Head"])
		"crown":
			return _ring(d, float(d["brow_top"]) + 0.06, 0.034, 0.03, ["Head"], ["Head"])
		"sash":
			return _ring(d, (rest["spine_01"] as Vector3).y, 0.075, 0.034, ["pelvis", "spine_01", "spine_02"], ["pelvis", "spine_01"])
		"skirt_short":
			return _skirt(d, (rest["calf_l"] as Vector3).y - 0.04)
		"skirt_long":
			return _skirt(d, (rest["foot_l"] as Vector3).y + 0.05)
		"cloak":
			return _cloak(d)
	return null


## The bind numbers of the named bones, as a set.
static func _bind_set(bind: Dictionary, names: Array) -> Dictionary:
	var out := {}
	for n in names:
		out[int(bind[n])] = true
	return out


static func _between(v: float, lo: float, hi: float) -> bool:
	return v > lo and v < hi


## How far `p` lies along the bone from joint `a` to joint `b`: 0 at a, 1 at b.
static func _along(p: Vector3, rest: Dictionary, a: String, b: String) -> float:
	var pa: Vector3 = rest[a]
	var ab: Vector3 = (rest[b] as Vector3) - pa
	return (p - pa).dot(ab) / ab.length_squared()


## A copy of the chosen part of the body, pushed out by `offset` metres. `choose` gets a
## vertex's position and the bone it mostly follows.
static func _shell(d: Dictionary, offset: float, choose: Callable) -> ArrayMesh:
	var verts: PackedVector3Array = d["verts"]
	var normals: PackedVector3Array = d["normals"]
	var bones: PackedInt32Array = d["bones"]
	var weights: PackedFloat32Array = d["weights"]
	var indices: PackedInt32Array = d["indices"]
	var owner: PackedInt32Array = d["owner"]
	var per: int = d["per"]
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_b := PackedInt32Array()
	var out_w := PackedFloat32Array()
	for v in verts.size():
		if choose.call(verts[v], owner[v]):
			remap[v] = out_v.size()
			out_v.append(verts[v] + normals[v] * offset)
			out_n.append(normals[v])
			for k in per:
				out_b.append(bones[v * per + k])
				out_w.append(weights[v * per + k])
		else:
			remap[v] = -1
	var out_i := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var a := remap[indices[t]]
		var b := remap[indices[t + 1]]
		var c := remap[indices[t + 2]]
		if a >= 0 and b >= 0 and c >= 0:
			out_i.append(a)
			out_i.append(b)
			out_i.append(c)
	if out_i.is_empty():
		return null
	return _commit(out_v, out_n, out_b, out_w, out_i, per)


static func _commit(v: PackedVector3Array, n: PackedVector3Array, b: PackedInt32Array, w: PackedFloat32Array, i: PackedInt32Array, per: int) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_BONES] = b
	arrays[Mesh.ARRAY_WEIGHTS] = w
	arrays[Mesh.ARRAY_INDEX] = i
	var mesh := ArrayMesh.new()
	var flags: int = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


## Outline of the body at height `y`, from the vertices that follow the named bones:
## half-width, front and back. Returns {} if nothing is there.
static func _section(d: Dictionary, y: float, names: Array, band: float = 0.035) -> Dictionary:
	var verts: PackedVector3Array = d["verts"]
	var owner: PackedInt32Array = d["owner"]
	var bind: Dictionary = d["bind"]
	var wanted := {}
	for n in names:
		wanted[int(bind[n])] = true
	var half := 0.0
	var front := -1e9
	var back := 1e9
	for v in verts.size():
		var p := verts[v]
		if absf(p.y - y) < band and wanted.has(owner[v]):
			half = maxf(half, absf(p.x))
			front = maxf(front, p.z)
			back = minf(back, p.z)
	if half <= 0.0:
		return {}
	return {"half": half, "front": front, "back": back}


## Writes the bone slots of one generated vertex from up to four [bind, weight] pairs.
static func _put_weights(out_b: PackedInt32Array, out_w: PackedFloat32Array, pairs: Array, per: int) -> void:
	var total := 0.0
	for p in pairs:
		total += float(p[1])
	for k in per:
		if k < pairs.size() and total > 0.0:
			out_b.append(int(pairs[k][0]))
			out_w.append(float(pairs[k][1]) / total)
		else:
			out_b.append(0)
			out_w.append(0.0)


## A band round the body at height `y`: `height` tall, standing `gap` metres off the surface.
static func _ring(d: Dictionary, y: float, height: float, gap: float, measure: Array, follow: Array) -> ArrayMesh:
	var s := _section(d, y, measure, maxf(0.03, height))
	if s.is_empty():
		return null
	var bind: Dictionary = d["bind"]
	var per: int = d["per"]
	var cz: float = (float(s["front"]) + float(s["back"])) * 0.5
	var rx: float = float(s["half"]) + gap
	var rz: float = (float(s["front"]) - float(s["back"])) * 0.5 + gap
	var pairs: Array = []
	for n in follow:
		pairs.append([int(bind[n]), 1.0])
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var b := PackedInt32Array()
	var w := PackedFloat32Array()
	var idx := PackedInt32Array()
	var sides := 28
	for row in 2:
		for k in sides:
			var a := TAU * k / sides
			v.append(Vector3(cos(a) * rx, y + (row - 0.5) * height, cz + sin(a) * rz))
			nrm.append(Vector3(cos(a) / rx, 0.0, sin(a) / rz).normalized())
			_put_weights(b, w, pairs, per)
	for k in sides:
		var k2 := (k + 1) % sides
		idx.append_array([k, sides + k, k2, k2, sides + k, sides + k2])
	return _commit(v, nrm, b, w, idx, per)


## The hanging part of a tunic or robe: a flared tube from the waist to `hem`. Its lower rows
## follow the legs, so it parts and swings as the figure walks.
static func _skirt(d: Dictionary, hem: float) -> ArrayMesh:
	var bind: Dictionary = d["bind"]
	var rest: Dictionary = d["rest"]
	var per: int = d["per"]
	var waist: float = (rest["spine_01"] as Vector3).y
	var knee: float = (rest["calf_l"] as Vector3).y
	var ankle: float = (rest["foot_l"] as Vector3).y
	var leg_bones := ["pelvis", "spine_01", "thigh_l", "thigh_r", "calf_l", "calf_r"]
	var rows := maxi(4, int(ceil((waist - hem) / 0.07)))
	var sides := 28
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var b := PackedInt32Array()
	var w := PackedFloat32Array()
	var idx := PackedInt32Array()
	var rx := 0.0
	var rz := 0.0
	var cz := 0.0
	for row in rows + 1:
		var y := lerpf(waist, hem, float(row) / rows)
		var s := _section(d, y, leg_bones)
		if not s.is_empty():
			# Never narrower than the row above, and always a little wider: the cloth flares.
			rx = maxf(rx + 0.006, float(s["half"]) + 0.03)
			rz = maxf(rz + 0.006, (float(s["front"]) - float(s["back"])) * 0.5 + 0.035)
			cz = (float(s["front"]) + float(s["back"])) * 0.5
		else:
			rx += 0.006
			rz += 0.006
		var down := clampf((waist - y) / (waist - knee), 0.0, 1.0)       # 0 at the waist, 1 at the knee
		var below := clampf((knee - y) / (knee - ankle), 0.0, 1.0)       # 0 at the knee, 1 at the ankle
		for k in sides:
			var a := TAU * k / sides
			var x := cos(a) * rx
			v.append(Vector3(x, y, cz + sin(a) * rz))
			nrm.append(Vector3(cos(a) / rx, 0.15, sin(a) / rz).normalized())
			var left := smoothstep(-0.5, 0.5, x / rx)      # +x is the figure's left side
			var pairs: Array
			if below <= 0.0:
				var legs := 0.75 * down
				pairs = [[bind["pelvis"], 1.0 - legs], [bind["thigh_l"], legs * left], [bind["thigh_r"], legs * (1.0 - left)]]
			else:
				var calf := 0.7 * below
				pairs = [[bind["thigh_l"], (1.0 - calf) * left], [bind["thigh_r"], (1.0 - calf) * (1.0 - left)],
					[bind["calf_l"], calf * left], [bind["calf_r"], calf * (1.0 - left)]]
			_put_weights(b, w, pairs, per)
	for row in rows:
		for k in sides:
			var k2 := (k + 1) % sides
			var a0 := row * sides + k
			var a1 := row * sides + k2
			var b0 := (row + 1) * sides + k
			var b1 := (row + 1) * sides + k2
			idx.append_array([a0, a1, b0, a1, b1, b0])
	return _commit(v, nrm, b, w, idx, per)


## A sheet hanging down the back from the shoulders to the calves.
static func _cloak(d: Dictionary) -> ArrayMesh:
	var bind: Dictionary = d["bind"]
	var rest: Dictionary = d["rest"]
	var per: int = d["per"]
	var top: float = (rest["clavicle_l"] as Vector3).y + 0.01
	var bottom: float = (rest["calf_l"] as Vector3).y - 0.18
	var chest: float = (rest["spine_03"] as Vector3).y
	var hips: float = (rest["pelvis"] as Vector3).y
	var half: float = absf((rest["upperarm_l"] as Vector3).x) + 0.03
	var cols := 8
	var rows := 12
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var b := PackedInt32Array()
	var w := PackedFloat32Array()
	var idx := PackedInt32Array()
	var back := 0.0
	for row in rows + 1:
		var y := lerpf(top, bottom, float(row) / rows)
		var s := _section(d, y, ["pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "thigh_l", "thigh_r", "calf_l", "calf_r"])
		if not s.is_empty():
			back = minf(back, float(s["back"]))
		for col in cols + 1:
			var u := float(col) / cols * 2.0 - 1.0          # -1 at the right edge, +1 at the left
			# The edges wrap a little way round toward the front.
			v.append(Vector3(u * half * (1.0 + 0.12 * float(row) / rows), y, back - 0.05 + u * u * 0.06))
			nrm.append(Vector3(u * 0.5, 0.0, -1.0).normalized())
			var left := smoothstep(-0.5, 0.5, u)
			var pairs: Array
			if y >= chest:
				pairs = [[bind["spine_03"], 1.0]]
			elif y >= hips:
				var t := (chest - y) / (chest - hips)
				pairs = [[bind["spine_03"], 1.0 - t], [bind["pelvis"], t]]
			else:
				var t := clampf((hips - y) / (hips - bottom), 0.0, 1.0) * 0.45
				pairs = [[bind["pelvis"], 1.0 - t], [bind["thigh_l"], t * left], [bind["thigh_r"], t * (1.0 - left)]]
			_put_weights(b, w, pairs, per)
	for row in rows:
		for col in cols:
			var a0 := row * (cols + 1) + col
			var a1 := a0 + 1
			var b0 := a0 + cols + 1
			var b1 := b0 + 1
			idx.append_array([a0, b0, a1, a1, b0, b1])
	return _commit(v, nrm, b, w, idx, per)


# ================================================================ weapons

## kind: none, staff, spear, dagger, sickle, sword. Held in the right fist, pointing where the
## thumb points.
func set_weapon(kind: String) -> void:
	if weapon != null:
		hand_r.remove_child(weapon)
		weapon.queue_free()
		weapon = null
	weapon_kind = kind
	if kind == "none":
		return
	weapon = Node3D.new()
	hand_r.add_child(weapon)

	# Work out the grip from the rest pose: where the palm is and which way the thumb points.
	var hand := skeleton.get_bone_global_rest(skeleton.find_bone("hand_r"))
	var knuckle := skeleton.get_bone_global_rest(skeleton.find_bone("middle_01_r")).origin
	var thumb := skeleton.get_bone_global_rest(skeleton.find_bone("thumb_01_r")).origin
	var fingers := (knuckle - hand.origin).normalized()
	var up := thumb - hand.origin
	up = (up - fingers * up.dot(fingers)).normalized()
	var side := fingers.cross(up).normalized()
	var grip := hand.origin + fingers * 0.085 - side * 0.028
	var held := Basis(side, up, side.cross(up))   # weapon +Y runs along the thumb
	_strike = hand.affine_inverse() * Transform3D(held.orthonormalized(), grip)
	# Held along the thumb, a weapon at rest would cross the body. So while it is only being
	# carried it points a set way relative to the standing figure: a staff upright beside the
	# hip with its foot on the ground, a blade forward and a little up.
	var long_weapon := kind == "staff" or kind == "spear"
	var idle: Animation = _player.get_animation("Idle")
	var hand_idle := pose_basis(idle, skeleton, skeleton.find_bone("hand_r"), 0.0)
	var to_hand := hand_idle.inverse()            # model-space direction -> hand-space direction
	var aim := Vector3(0.0, 1.0, 0.1) if long_weapon else Vector3(-0.2, 0.35, 0.9)   # model faces +Z, right hand is at -X
	var along := (to_hand * aim).normalized()
	var across := along.cross(to_hand * Vector3(1.0, 0.0, 0.0)).normalized()
	var carried := Basis(across, along, across.cross(along))
	_carry = Transform3D(carried.orthonormalized(), _strike.origin)
	if long_weapon:
		_carry.origin += along * -0.3 + (to_hand * Vector3(-0.05, 0.0, 0.0))
	_strike_left = 0.0
	weapon.transform = _carry

	var wood := Color(0.42, 0.28, 0.16)
	var bronze := Color(0.8, 0.6, 0.3)
	var iron := Color(0.66, 0.68, 0.72)
	match kind:
		"staff":
			_part(_cyl(0.02, 0.026, 1.7, wood), Vector3(0, 0.25, 0))
		"spear":
			_part(_cyl(0.017, 0.019, 1.9, wood), Vector3(0, 0.35, 0))
			_part(_cyl(0.0, 0.035, 0.24, bronze), Vector3(0, 1.42, 0))
		"dagger":
			_blade(0.3, bronze)
		"sickle":
			_blade(0.44, bronze)
			_part(_box(Vector3(0.012, 0.16, 0.045), bronze), Vector3(0, 0.56, 0.045), Vector3(0.75, 0, 0))
		_:
			_blade(0.68, iron)


func _cyl(top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = _cloth_material(color)
	return mi


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _cloth_material(color)
	return mi


func _part(mi: MeshInstance3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	mi.position = pos
	mi.rotation = rot
	weapon.add_child(mi)


func _blade(length: float, color: Color) -> void:
	_part(_cyl(0.017, 0.017, 0.13, Color(0.3, 0.2, 0.13)), Vector3.ZERO)
	_part(_box(Vector3(0.03, 0.022, 0.11), color), Vector3(0, 0.07, 0))
	_part(_box(Vector3(0.012, length, 0.05), color), Vector3(0, 0.08 + length * 0.5, 0))


# ================================================================ animation

## The animation library retargeted to this body, made once per sex.
static func _library(sex: int, target: Skeleton3D) -> AnimationLibrary:
	if not _libraries.has(sex):
		var scene: PackedScene = load(DIR + "animations.glb")
		var src: Node3D = scene.instantiate()
		var src_sk: Skeleton3D = src.find_child("Skeleton3D", true, false)
		var src_player: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
		var lib: AnimationLibrary = Retarget.convert(src_sk, src_player, target, ANIMS, "Armature/Skeleton3D")
		for cycle_name in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Sitting_Idle", "Sitting_Talking"]:
			lib.get_animation(cycle_name).loop_mode = Animation.LOOP_LINEAR
		# The kneeling clip kneels down, works, and stands up again. People at work stay down:
		# they use only its middle, where the hips are low and the hands are busy.
		lib.add_animation("Kneeling_Work", _cut(lib.get_animation("Fixing_Kneeling"), 1.0, 4.0))
		_libraries[sex] = lib
		src.free()
	return _libraries[sex]


## Orientation of `bone` in model space at `time` of an animation made for `sk`.
static func pose_basis(anim: Animation, sk: Skeleton3D, bone: int, time: float) -> Basis:
	var chain: Array = []
	var b := bone
	while b >= 0:
		chain.push_front(b)
		b = sk.get_bone_parent(b)
	var out := Basis.IDENTITY
	for i in chain:
		var local := sk.get_bone_rest(i).basis
		var track := anim.find_track(NodePath("Armature/Skeleton3D:%s" % sk.get_bone_name(i)), Animation.TYPE_ROTATION_3D)
		if track >= 0:
			local = Basis(anim.rotation_track_interpolate(track, time))
		out = out * local
	return out


## A stretch of an animation as a clip of its own, played forward and then back so it never jumps.
static func _cut(a: Animation, from: float, to: float) -> Animation:
	var out := Animation.new()
	out.length = to - from
	out.loop_mode = Animation.LOOP_PINGPONG
	var steps := int(ceil((to - from) * 30.0))
	for t in a.get_track_count():
		var track := out.add_track(a.track_get_type(t))
		out.track_set_path(track, a.track_get_path(t))
		for k in steps + 1:
			var time := minf(to - from, k / 30.0)
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(track, time, a.rotation_track_interpolate(t, from + time))
			else:
				out.position_track_insert_key(track, time, a.position_track_interpolate(t, from + time))
	return out


func _clip(anim: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = anim
	return node


func _setup_animation(sex: int) -> void:
	_player = AnimationPlayer.new()
	_model.add_child(_player)
	_player.root_node = NodePath("..")
	_player.add_animation_library("", _library(sex, skeleton))

	# Legs follow the walk cycle; a strike or a sling throw plays over the upper body only.
	var graph := AnimationNodeBlendTree.new()
	var walk := AnimationNodeBlendSpace1D.new()
	walk.min_space = 0.0
	walk.max_space = 10.0
	walk.sync = true
	walk.add_blend_point(_clip("Idle"), 0.0, -1, &"idle")
	walk.add_blend_point(_clip("Walk"), 1.8, -1, &"walk")
	walk.add_blend_point(_clip("Jog_Fwd"), 5.5, -1, &"jog")
	walk.add_blend_point(_clip("Sprint"), 9.5, -1, &"sprint")
	graph.add_node("walk", walk)
	graph.add_node("strike_clip", _clip("Sword_Attack"))
	graph.add_node("strike_speed", AnimationNodeTimeScale.new())
	graph.add_node("punch_clip", _clip("Punch_Cross"))
	graph.add_node("throw_clip", _clip("Spell_Simple_Shoot"))
	for shot in ["strike", "punch", "throw"]:
		var one := AnimationNodeOneShot.new()
		one.fadein_time = 0.06
		one.fadeout_time = 0.15
		one.filter_enabled = true
		for bone in UPPER_BODY:
			one.set_filter_path(NodePath("Armature/Skeleton3D:%s" % bone), true)
		for side in ["l", "r"]:
			for finger in FINGERS:
				for joint in 3:
					one.set_filter_path(NodePath("Armature/Skeleton3D:%s_0%d_%s" % [finger, joint + 1, side]), true)
		graph.add_node(shot, one)
	graph.connect_node("strike_speed", 0, "strike_clip")
	graph.connect_node("strike", 0, "walk")
	graph.connect_node("strike", 1, "strike_speed")
	graph.connect_node("punch", 0, "strike")
	graph.connect_node("punch", 1, "punch_clip")
	graph.connect_node("throw", 0, "punch")
	graph.connect_node("throw", 1, "throw_clip")
	graph.connect_node("output", 0, "throw")

	_tree = AnimationTree.new()
	_model.add_child(_tree)
	_tree.root_node = NodePath("..")
	_tree.tree_root = graph
	_tree.anim_player = _tree.get_path_to(_player)
	if bool(_opts.get("always_animate", false)):
		_tree.process_mode = Node.PROCESS_MODE_ALWAYS
	_tree.active = true
	_tree.set("parameters/strike_speed/scale", STRIKE_SPEED)
	_tree.set("parameters/walk/blend_position", 0.0)
	_tree.advance(0.0)


## Call every frame with the horizontal speed in metres per second (0 when standing).
func animate(delta: float, speed: float) -> void:
	if _tree == null or dead or posed:
		return
	_speed = lerpf(_speed, speed, 1.0 - exp(-10.0 * delta))
	_tree.set("parameters/walk/blend_position", _speed)
	if _strike_left > 0.0:
		_strike_left -= delta
		if _strike_left <= 0.0 and weapon != null:
			weapon.transform = _carry


## A blow with the weapon in the right hand, or a punch if the hand is empty.
func swing() -> void:
	if _tree == null or dead:
		return
	var shot := "punch" if weapon_kind == "none" else "strike"
	_tree.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if weapon != null:
		weapon.transform = _strike
		_strike_left = STRIKE_TIME


## The throwing motion used for the sling.
func whirl() -> void:
	if _tree == null or dead:
		return
	_tree.set("parameters/throw/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func die() -> void:
	if dead or _tree == null:
		return
	dead = true
	_tree.active = false
	_player.play("Death01")


func revive() -> void:
	if not dead:
		return
	dead = false
	_player.stop()
	_tree.active = true
	_speed = 0.0


## Holds a looping pose (sitting, kneeling at work) instead of standing and walking.
func pose(anim: String) -> void:
	if _tree == null or not _player.has_animation(anim):
		return
	posed = true
	_tree.active = false
	_player.play(anim)
	# Start part-way through, so people sitting together do not move as one.
	_player.seek(randf() * _player.current_animation_length, true)


## Where a bone is now, relative to the figure's feet and facing.
func bone_position(bone: String) -> Vector3:
	return _model.transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
