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
## Clothing pieces seen from inside as well as out.
const TWO_SIDED := ["skirt_short", "skirt_long", "sash", "cloak", "band", "band_wide", "crown", "necklace"]
## Hair meshes by "hair" index. "" = no hair mesh.
const HAIR_FILES := ["hair_buzzed", "hair_parted", "hair_long", "hair_buns", ""]

const ANIMS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Sword_Attack", "Spell_Simple_Shoot", "Punch_Cross", "Death01",
	"Sitting_Idle", "Sitting_Talking", "Fixing_Kneeling", "Jump", "Jump_Land"]
## The blows of a combo, in order: A cuts from top to bottom, B sweeps from left to right, C cuts
## from top right to bottom left. hit: when it lands; chain: the soonest the next blow may follow;
## length: how long the move takes if nothing follows (seconds at normal speed; a heavy weapon is
## slower, see attack()). The clips are made from poses of the arms, chest, hips and legs in
## _library().
const BLOWS := [
	{"shot": "blow_a", "hit": 0.16, "chain": 0.26, "length": 0.5},
	{"shot": "blow_b", "hit": 0.13, "chain": 0.22, "length": 0.42},
	{"shot": "blow_c", "hit": 0.2, "chain": 1e9, "length": 0.55},
]
## The sling: whirled overhead for as long as the button is held (at least WHIRL_TIME), then the
## arm comes over and lets go RELEASE seconds later; the throw is over THROW_TIME after letting go.
const WHIRL_TIME := 0.34
const RELEASE := 0.08
const THROW_TIME := 0.3
const THROW_RELEASE := WHIRL_TIME + RELEASE
## The bow: drawn fully in DRAW_TIME; after loosing, the arms come down in LOOSE_TIME.
const DRAW_TIME := 0.5
const LOOSE_TIME := 0.3
## Shapes that are carried on the back when put away; the rest hang at the belt.
## How far _grip may roll a forearm and bend a wrist (radians).
const ROLL_MAX := 2.3
const WRIST_MAX := 1.1
const ON_BACK := ["staff", "spear", "spear_long", "bow", "shield"]
const NOT_WEAPONS := ["none", "shield", "bow"]
## Reaching to the back or the belt to draw or put away a weapon; it changes place halfway.
const STOW_SWAP := 0.14
const STOW_TIME := 0.36
const UPPER_BODY := ["spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "clavicle_r",
	"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"]
const FINGERS := ["index", "middle", "ring", "pinky", "thumb"]
## The hips and legs. A blow made standing still moves these too (see attack()).
const LOWER_BODY := ["pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
## Below PLANT_SPEED (m/s) a figure counts as standing and puts its hips and legs into a blow;
## if it gets going faster than UNPLANT_SPEED during the blow, the legs go back to walking.
const PLANT_SPEED := 1.0
const UNPLANT_SPEED := 2.0
## Coming down after at least this long off the ground (seconds), a figure standing still sinks
## on its knees to take the landing.
const LAND_AFTER := 0.3

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
var _stow := Transform3D.IDENTITY     # how it sits on the back or the belt when put away
var _strike_left := 0.0               # seconds until the weapon returns to the carry position
var sheathed := false             # the weapon is on the back or the belt, not in the hand
var _back: BoneAttachment3D       # a staff or spear is carried here when put away
var _hip: BoneAttachment3D        # a blade hangs here when put away
var _sling: Node3D                # the sling, shown only while throwing
var _sling_pouch: Node3D
var _throw_t := -1.0              # seconds since the sling was let go, or -1
var _throw_yaw := 0.0
var _stowed_for_throw := false
var _swap_left := -1.0            # seconds until a drawn or stowed weapon changes place
var _shot := ""                   # the one-shot of the latest blow
var offhand: Node3D               # what the left hand holds: a weapon, a shield or a bow
var offhand_kind := "none"
var hand_l: BoneAttachment3D
var _arm_l: BoneAttachment3D      # a shield is strapped to the forearm
var _arm_r: BoneAttachment3D
var _carry_l := Transform3D.IDENTITY
var _strike_l := Transform3D.IDENTITY
var _stow_l := Transform3D.IDENTITY
var _strike_side := "r"           # which hand the latest blow was made with
var _stance := 0                  # which of the two stance one-shots the latest blow used
var _stance_clips: Array = []     # their animation nodes, given the clip of the blow each time
var _legs := ""                   # what the hips and legs are doing over the walk: "" nothing,
                                  # "blow" a blow made standing, "air" a blow made off the ground
var _legs_left := 0.0             # seconds until that is over
var _land_left := 0.0             # seconds until the knees have come up again after a landing
var _first_blow := {}             # side -> animation node of the first blow, which has an airborne form
var _in_air := false              # off the ground
var _air_time := 0.0              # for how long
var _air := 0.0                   # how far the body has gone over to the airborne pose, 0..1
var _whirling := false            # the sling is going round overhead
var _whirl_t := 0.0
var _auto_release := -1.0         # whirl(): let go by itself after this long
var drawing := false              # the bow is drawn or being drawn
var draw_amount := 0.0            # how far it is drawn, 0..1
var _loose_t := -1.0              # seconds since an arrow was loosed, or -1
var _arrow: Node3D                # the arrow on the string while the bow is drawn
var _string: Array = []           # the two halves of the bow string


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
	offhand = null
	offhand_kind = "none"
	garments = []
	dead = false
	posed = false
	_throw_t = -1.0
	_swap_left = -1.0
	_stowed_for_throw = false
	_whirling = false
	_auto_release = -1.0
	drawing = false
	draw_amount = 0.0
	_loose_t = -1.0
	_arrow = null
	_string = []
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
	hand_l = BoneAttachment3D.new()
	hand_l.bone_name = "hand_l"
	skeleton.add_child(hand_l)
	_arm_l = BoneAttachment3D.new()
	_arm_l.bone_name = "lowerarm_l"
	skeleton.add_child(_arm_l)
	_arm_r = BoneAttachment3D.new()
	_arm_r.bone_name = "lowerarm_r"
	skeleton.add_child(_arm_r)
	_back = BoneAttachment3D.new()
	_back.bone_name = "spine_03"
	skeleton.add_child(_back)
	_hip = BoneAttachment3D.new()
	_hip.bone_name = "pelvis"
	skeleton.add_child(_hip)

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
	var head_wear: Array = opts.get("head_wear", [])
	if not head_wear.is_empty():
		covered = head_wear.any(func(p) -> bool: return p[0] == "cap" or p[0] == "helmet")
	var hair_file: String = HAIR_FILES[_i("hair")]
	if hair_file == "hair_buzzed" and sex == 1:
		hair_file = "hair_buzzed_f"
	if hair_file != "" and not covered:
		_attach_to_head(hair_file, hair_c, sex)
	if sex == 0 and _i("beard") == 1:
		_attach_to_head("beard", hair_c, sex)

	_dress(sex, d, body_mi, opts)
	_setup_animation(sex)
	_make_sling()


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

	_wear(sex, d, body_mi, "shoes", Color(0.3, 0.2, 0.13))
	if opts.has("wear"):
		# The player: what is equipped decides the clothes (Items "wear"), dyed in the chosen colors.
		for p in opts["wear"]:
			_wear(sex, d, body_mi, str(p[0]), _wear_color(p[1], cloth, sash_c), TWO_SIDED.has(str(p[0])))
	else:
		_wear(sex, d, body_mi, "top_long" if long_robe else "top_short", cloth)
		_wear(sex, d, body_mi, "skirt_long" if long_robe else "skirt_short", cloth, true)
		_wear(sex, d, body_mi, "sash", LEATHER if leathers else sash_c, true)
		if leathers:
			_wear(sex, d, body_mi, "vest", LEATHER)
			_wear(sex, d, body_mi, "bracers", LEATHER)
			_wear(sex, d, body_mi, "leg_wraps", LEATHER)
		if outfit == 2:
			var cloak_c := sash_c.darkened(0.35)
			_wear(sex, d, body_mi, "mantle", cloak_c)
			_wear(sex, d, body_mi, "cloak", cloak_c, true)

	var head_wear: Array = opts.get("head_wear", [])
	if not head_wear.is_empty():
		for p in head_wear:
			_wear(sex, d, body_mi, str(p[0]), _wear_color(p[1], cloth, sash_c), TWO_SIDED.has(str(p[0])))
		return
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


## A color from an item's "wear" list: a Color, or "cloth" / "sash" for the chosen colors.
static func _wear_color(c: Variant, cloth: Color, sash: Color) -> Color:
	if c is Color:
		return c
	return sash if str(c) == "sash" else cloth


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
		"helmet":
			# Like the cap but thicker, coming down over the brow and the ears.
			var head_b: int = bind["Head"]
			var mid_z: float = ((d["head_lo"] as Vector3).z + (d["head_hi"] as Vector3).z) * 0.5
			var brow: float = float(d["brow_top"]) + 0.01
			var ear: float = float(d["eye_y"]) - 0.07
			choose = func(p: Vector3, o: int) -> bool:
				if o == head_b:
					return p.y > brow or (p.z < mid_z + 0.01 and p.y > ear)
				return false
			return _shell(d, 0.032, choose)
		"necklace":
			var neck_y: float = (rest["neck_01"] as Vector3).y
			return _ring(d, neck_y + 0.015, 0.018, 0.012, ["neck_01"], ["neck_01"])
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

## kind: none, staff, spear, spear_long, dagger, sickle, sword, sword_short, sword_long, club,
## mace, axe. Held in the right fist, pointing where the thumb points. Leaves the left hand as it is.
func set_weapon(kind: String, color: Color = Color(0, 0, 0, 0)) -> void:
	set_hands(kind, offhand_kind, color)


## What each hand holds. The right takes weapons; the left takes a weapon, a shield or a bow.
## `rc` and `lc` tint the metal (or the wood of a bow, the face of a shield); alpha 0 = usual.
func set_hands(right: String, left: String, rc: Color = Color(0, 0, 0, 0), lc: Color = Color(0, 0, 0, 0)) -> void:
	for n in [weapon, offhand]:
		if n != null:
			n.get_parent().remove_child(n)
			n.queue_free()
	weapon = null
	offhand = null
	_arrow = null
	_string = []
	weapon_kind = right
	offhand_kind = left
	_strike_left = 0.0
	var idle: Animation = _player.get_animation("Idle")
	var fist_anim: Animation = _player.get_animation("Sword_Attack")
	_strike = fist_frame(skeleton, fist_anim, 0.46, "r")
	_strike_l = fist_frame(skeleton, idle, 0.0, "l")
	if right != "none":
		weapon = _item_model(right, rc)
		_hand_holder("r", right).add_child(weapon)
		# During a blow the weapon runs through the hollow of the fist, coming out on the thumb
		# side. Held along the thumb, a weapon at rest would cross the body, so while it is only
		# carried it points a set way relative to the standing figure: a staff upright beside the
		# hip with its foot on the ground, a blade forward and a little up.
		_carry = _shield_frame("r") if right == "shield" else _carry_frame(idle, "r", right)
		_stow = _stow_transform(right, "r")
	if left != "none":
		offhand = _item_model(left, lc)
		_hand_holder("l", left).add_child(offhand)
		_carry_l = _shield_frame("l") if left == "shield" else _carry_frame(idle, "l", left)
		_stow_l = _stow_transform(left, "l")
		if left == "bow":
			_make_arrow()
	_strike_side = "r"
	sheathe(sheathed)


## How an item is carried at rest in one hand: through the hollow of the relaxed fist, pointing a
## set way in model space (the model faces +Z; its right is -X).
func _carry_frame(idle: Animation, side: String, kind: String) -> Transform3D:
	var hand_idle := pose_basis(idle, skeleton, skeleton.find_bone("hand_" + side), 0.0)
	var to_hand := hand_idle.inverse()            # model-space direction -> hand-space direction
	var out := 1.0 if side == "r" else -1.0       # which way is away from the body
	var aim := Vector3(0.0, 1.0, 0.1)
	if kind == "bow":
		aim = Vector3(-0.15 * out, 1.0, 0.25)
	elif not _long(kind):
		aim = Vector3(-0.2 * out, 0.35, 0.9)
	var along := (to_hand * aim).normalized()
	var across := along.cross(to_hand * Vector3(1.0, 0.0, 0.0)).normalized()
	var carried := Basis(across, along, across.cross(along))
	var t := Transform3D(carried.orthonormalized(), fist_frame(skeleton, idle, 0.0, side).origin)
	if _long(kind):
		t.origin += along * -0.3
	return t


## What an item hangs from while it is in use: a shield from the forearm, the rest from the hand.
func _hand_holder(side: String, kind: String) -> Node3D:
	if kind == "shield":
		return _arm_r if side == "r" else _arm_l
	return hand_r if side == "r" else hand_l


## A shield strapped to the outside of the forearm, its face turned away from the body.
func _shield_frame(side: String) -> Transform3D:
	var lower := skeleton.find_bone("lowerarm_" + side)
	var hand := skeleton.find_bone("hand_" + side)
	var length := skeleton.get_bone_rest(hand).origin.length()
	var arm := pose_basis(_player.get_animation("Idle"), skeleton, lower, 0.0)
	var along := skeleton.get_bone_rest(hand).origin.normalized()
	var out := (arm.inverse() * Vector3(1.0 if side == "l" else -1.0, 0.0, 0.35)).normalized()
	out = (out - along * out.dot(along)).normalized()
	var basis := Basis(along.cross(out).normalized(), along, out)
	return Transform3D(basis, along * length * 0.55 + out * 0.07)


## The mesh of a weapon, shield or bow. The grip is at the origin and the item runs along +Y.
func _item_model(kind: String, tint: Color) -> Node3D:
	var n := Node3D.new()
	var wood := Color(0.42, 0.28, 0.16)
	var bronze := Color(0.8, 0.6, 0.3)
	var iron := Color(0.66, 0.68, 0.72)
	var metal := tint if tint.a > 0.0 else (iron if kind in ["sword", "sword_long", "spear_long"] else bronze)
	match kind:
		"staff":
			_part(n, _cyl(0.02, 0.026, 1.7, wood), Vector3(0, 0.25, 0))
		"spear", "spear_long":
			var long := kind == "spear_long"
			_part(n, _cyl(0.017, 0.02, 2.4 if long else 1.9, wood), Vector3(0, 0.55 if long else 0.35, 0))
			_part(n, _cyl(0.0, 0.035, 0.3 if long else 0.24, metal), Vector3(0, 1.9 if long else 1.42, 0))
		"dagger":
			_blade(n, 0.3, metal)
		"sickle":
			_blade(n, 0.44, metal)
			_part(n, _box(Vector3(0.012, 0.16, 0.045), metal), Vector3(0, 0.56, 0.045), Vector3(0.75, 0, 0))
		"sword_short":
			_blade(n, 0.5, metal)
		"sword_long":
			_blade(n, 0.86, metal)
		"club":
			_part(n, _cyl(0.045, 0.018, 0.7, tint if tint.a > 0.0 else wood), Vector3(0, 0.25, 0))
		"mace":
			_part(n, _cyl(0.016, 0.018, 0.62, wood), Vector3(0, 0.2, 0))
			var head := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 0.07
			ball.height = 0.12
			ball.radial_segments = 8
			ball.rings = 4
			head.mesh = ball
			head.material_override = _cloth_material(metal)
			_part(n, head, Vector3(0, 0.52, 0))
		"axe":
			_part(n, _cyl(0.017, 0.019, 0.72, wood), Vector3(0, 0.22, 0))
			_part(n, _box(Vector3(0.016, 0.2, 0.17), metal), Vector3(0, 0.5, 0.1))
		"shield":
			var face := _cyl(0.34, 0.34, 0.035, tint if tint.a > 0.0 else Color(0.6, 0.45, 0.3))
			_part(n, face, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
			var rim := _cyl(0.36, 0.36, 0.025, bronze.darkened(0.2))
			_part(n, rim, Vector3(0, 0, -0.004), Vector3(PI * 0.5, 0, 0))
			var boss := _cyl(0.02, 0.08, 0.05, bronze)
			_part(n, boss, Vector3(0, 0, 0.035), Vector3(PI * 0.5, 0, 0))
		"bow":
			var c := tint if tint.a > 0.0 else wood
			_part(n, _cyl(0.022, 0.022, 0.14, LEATHER), Vector3.ZERO)
			for s in [-1.0, 1.0]:
				# Each limb in two pieces, bowing away from the archer and then curving back toward
				# them (+Z here) at the tip.
				var mid := Vector3(0, s * 0.38, -0.03)
				var end := Vector3(0, s * 0.66, 0.06)
				var inner := _cyl(0.013, 0.019, 1.0, c)
				_segment(inner, Vector3(0, s * 0.06, 0), mid)
				n.add_child(inner)
				var outer := _cyl(0.008, 0.013, 1.0, c)
				_segment(outer, mid, end)
				n.add_child(outer)
				var tip := Node3D.new()
				tip.name = "Tip%d" % (0 if s < 0.0 else 1)
				tip.position = end
				n.add_child(tip)
			for k in 2:
				var str_mi := _cyl(0.003, 0.003, 1.0, Color(0.85, 0.82, 0.74))
				n.add_child(str_mi)
				_string.append(str_mi)
		_:
			_blade(n, 0.68, metal)
	return n


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


func _part(to: Node3D, mi: MeshInstance3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	mi.position = pos
	mi.rotation = rot
	to.add_child(mi)


func _blade(to: Node3D, length: float, color: Color) -> void:
	_part(to, _cyl(0.017, 0.017, 0.13, Color(0.3, 0.2, 0.13)), Vector3.ZERO)
	_part(to, _box(Vector3(0.03, 0.022, 0.11), color), Vector3(0, 0.07, 0))
	_part(to, _box(Vector3(0.012, length, 0.05), color), Vector3(0, 0.08 + length * 0.5, 0))


## An arrow, nocked on the string while the bow is drawn.
func _make_arrow() -> void:
	_arrow = Node3D.new()
	_part(_arrow, _cyl(0.006, 0.006, 0.72, Color(0.62, 0.5, 0.32)), Vector3(0, 0.36, 0))
	_part(_arrow, _cyl(0.0, 0.014, 0.06, Color(0.5, 0.5, 0.52)), Vector3(0, 0.75, 0))
	_part(_arrow, _box(Vector3(0.002, 0.08, 0.03), Color(0.85, 0.82, 0.74)), Vector3(0, 0.05, 0))
	hand_r.add_child(_arrow)
	_arrow.visible = false


## Long things go on the back when put away; the rest hang at the belt.
static func _long(kind: String) -> bool:
	return kind in ["staff", "spear", "spear_long"]


static func is_weapon(kind: String) -> bool:
	return not NOT_WEAPONS.has(kind)


## Where `bone` is at `time` of `anim`, in the space of one hand ("l" or "r").
static func _in_hand(sk: Skeleton3D, anim: Animation, side: String, bone: String, time: float) -> Vector3:
	var hand := sk.find_bone("hand_" + side)
	var chain: Array = []
	var b := sk.find_bone(bone)
	while b >= 0 and b != hand:
		chain.push_front(b)
		b = sk.get_bone_parent(b)
	var t := Transform3D.IDENTITY
	for i in chain:
		var local := sk.get_bone_rest(i)
		local.basis = _anim_basis(anim, sk, i, time)
		t = t * local
	return t.origin


## How something gripped sits in a fist as `anim` has it at `time`, in hand space: at the hollow
## the curled fingers make, running across the knuckles and out on the thumb side (+Y), the flat
## facing the way the fingers point (-Z).
static func fist_frame(sk: Skeleton3D, anim: Animation, time: float, side: String) -> Transform3D:
	var hollow := Vector3.ZERO
	for f in ["index", "middle", "ring"]:
		for j in 3:
			hollow += _in_hand(sk, anim, side, "%s_0%d_%s" % [f, j + 1, side], time)
	hollow /= 9.0
	var up := (_in_hand(sk, anim, side, "index_01_" + side, time) - _in_hand(sk, anim, side, "pinky_01_" + side, time)).normalized()
	var fingers := _in_hand(sk, anim, side, "middle_01_" + side, time)
	fingers = (fingers - up * fingers.dot(up)).normalized()
	var z := -fingers
	return Transform3D(Basis(up.cross(z).normalized(), up, z), hollow)


func _fist(anim: Animation, time: float) -> Transform3D:
	return fist_frame(skeleton, anim, time, "r")


## Where a put-away item sits, in the space of the bone it hangs from. From the right hand: a
## staff or spear slantwise across the back, top over the right shoulder; a blade at the left hip,
## hilt at the sash, pointing down and back. From the left hand the same on the other side, and a
## shield flat on the back.
func _stow_transform(kind: String, side: String) -> Transform3D:
	var d := _body(_i("sex"))
	var rest: Dictionary = d["rest"]
	var dir: Vector3
	var at: Vector3
	var bone := "spine_03"
	var mirror := 1.0 if side == "r" else -1.0
	var s3: Vector3 = rest["spine_03"]
	var back_sec := _section(d, s3.y, ["spine_02", "spine_03", "clavicle_l", "clavicle_r"])
	var back_z := float(back_sec.get("back", s3.z - 0.14))
	var z := Vector3(0, 0, 1)
	if kind == "shield":
		dir = Vector3(0, 1, 0)
		z = Vector3(0, 0, -1)
		at = Vector3(s3.x, s3.y - 0.05, back_z - 0.08)
	elif ON_BACK.has(kind):
		dir = Vector3(-0.55 * mirror, 1.0, 0.0).normalized()       # model faces +Z; its right is -X
		var middle := 0.0 if kind == "bow" else (0.25 if kind == "staff" else 0.4)   # the middle of the shaft, from the grip
		var off := 0.06
		if (side == "r" and offhand_kind == "shield") or side == "l" and _long(weapon_kind):
			off += 0.07    # over the shield, or behind the other shaft
		at = Vector3(s3.x, s3.y, back_z - off) - dir * middle
	else:
		bone = "pelvis"
		var waist: Vector3 = rest["spine_01"]
		var sec := _section(d, waist.y, ["pelvis", "spine_01"])
		dir = Vector3(0.14 * mirror, -0.78, -0.6).normalized()
		at = Vector3((float(sec.get("half", 0.16)) + 0.06) * mirror, waist.y + 0.02, 0.05)
		z = Vector3(mirror, 0, 0)
	z = (z - dir * z.dot(dir)).normalized()
	var model := Transform3D(Basis(dir.cross(z).normalized(), dir, z), at)
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).affine_inverse() * model


func _holder(kind: String) -> Node3D:
	return _back if ON_BACK.has(kind) else _hip


## Moves what both hands hold at once to the back or belt (true), or into the hands (false).
func sheathe(on: bool) -> void:
	sheathed = on
	_swap_left = -1.0
	_strike_left = 0.0
	for side in ["r", "l"]:
		var n: Node3D = weapon if side == "r" else offhand
		if n == null:
			continue
		var kind := weapon_kind if side == "r" else offhand_kind
		var holder: Node3D = _holder(kind)
		if not on:
			holder = _hand_holder(side, kind)
		if n.get_parent() != holder:
			n.get_parent().remove_child(n)
			holder.add_child(n)
		if side == "r":
			n.transform = _stow if on else _carry
		else:
			n.transform = _stow_l if on else _carry_l


## Reaches to the back or the belt to put away what the hands hold (true) or take it up (false).
## It changes place STOW_SWAP seconds in. Returns false if there is nothing to do.
func stow(on: bool) -> bool:
	if (weapon == null and offhand == null) or dead or _tree == null or on == sheathed or _swap_left >= 0.0:
		return false
	var kind := weapon_kind if weapon != null else offhand_kind
	_play("reach_back" if ON_BACK.has(kind) else "reach_hip")
	_swap_left = STOW_SWAP
	return true


## True while drawing or putting away, slinging or shooting: the hands are busy.
func busy() -> bool:
	return _swap_left >= 0.0 or _throw_t >= 0.0 or _whirling or drawing or _loose_t >= 0.0


## Where the right hand is, in the world.
func hand_point() -> Vector3:
	return hand_r.global_position


## Where the left hand is, in the world (the bow's grip).
func left_hand_point() -> Vector3:
	return hand_l.global_position


## The sling: two cords from the fist to a leather pouch holding a stone. It hangs from the
## hand but is turned in world space while it is whirled.
func _make_sling() -> void:
	_sling = Node3D.new()
	hand_r.add_child(_sling)
	_sling.position = _fist(_player.get_animation("Sling_Whirl"), 0.0).origin
	var cord := Color(0.5, 0.42, 0.3)
	for side in [-1.0, 1.0]:
		var c := _cyl(0.005, 0.005, 0.6, cord)
		c.rotation.x = PI * 0.5
		c.position = Vector3(side * 0.012, 0.0, 0.3)
		_sling.add_child(c)
	_sling_pouch = Node3D.new()
	_sling_pouch.position = Vector3(0, 0, 0.62)
	_sling.add_child(_sling_pouch)
	var pouch := _box(Vector3(0.07, 0.025, 0.09), LEATHER)
	_sling_pouch.add_child(pouch)
	var stone := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.035
	ball.height = 0.07
	ball.radial_segments = 6
	ball.rings = 3
	stone.mesh = ball
	stone.material_override = _cloth_material(Color(0.55, 0.52, 0.48))
	stone.name = "Stone"
	stone.position.y = 0.025
	_sling_pouch.add_child(stone)
	_sling.visible = false


func _sling_turn(yaw: float, droop: float) -> void:
	var s := global_transform.basis.get_scale().x
	_sling.global_basis = (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, droop)).scaled(Vector3.ONE * s)


# ================================================================ animation

## The animation library retargeted to this body, made once per sex.
static func _library(sex: int, target: Skeleton3D) -> AnimationLibrary:
	if not _libraries.has(sex):
		var scene: PackedScene = load(DIR + "animations.glb")
		var src: Node3D = scene.instantiate()
		var src_sk: Skeleton3D = src.find_child("Skeleton3D", true, false)
		var src_player: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
		var lib: AnimationLibrary = Retarget.convert(src_sk, src_player, target, ANIMS, "Armature/Skeleton3D")
		for cycle_name in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Sitting_Idle", "Sitting_Talking", "Jump"]:
			lib.get_animation(cycle_name).loop_mode = Animation.LOOP_LINEAR
		# The kneeling clip kneels down, works, and stands up again. People at work stay down:
		# they use only its middle, where the hips are low and the hands are busy.
		lib.add_animation("Kneeling_Work", _cut(lib.get_animation("Fixing_Kneeling"), 1.0, 4.0))
		# Poses no clip has are made by aiming the arm bones (directions in model space: the model
		# faces +Z, its right is -X), turning the forearm and wrist so the blade held in the fist
		# points along the cut ("blade_r"), and turning ("twist", + to the left) or bending
		# ("lean", + forward) the chest. The blows also move the hips over the feet (see _stand).
		var strike := lib.get_animation("Sword_Attack")
		var idle := lib.get_animation("Idle")
		for side in ["r", "l"]:
			var keys: Dictionary = _blow_keys(side)
			for blow in ["a", "b", "c", "air"]:
				lib.add_animation("Blow_%s_%s" % [blow.capitalize(), side.to_upper()], _aimed(target, idle, strike, keys[blow], true))
		# Landing from a jump: the knees give, the hips sink over the feet and come up again.
		lib.add_animation("Land", _aimed(target, idle, strike, [
			[0.0, {"sink": 0.15, "pitch": 0.14, "shift": Vector3(0.0, 0.0, 0.03)}],
			[0.08, {"sink": 0.2, "pitch": 0.16, "shift": Vector3(0.0, 0.0, 0.04)}],
			[0.22, {"sink": 0.08, "pitch": 0.06, "shift": Vector3(0.0, 0.0, 0.02)}],
			[0.36, {}]], true))
		# The sling: the right hand held high over the head while the sling goes round (looped for
		# as long as it is held), the left arm pointing at the mark; then the arm comes over and
		# forward, and follows through.
		var whirl := {"upperarm_r": Vector3(-0.5, 0.85, 0.05), "lowerarm_r": Vector3(0.35, 0.85, 0.25),
			"upperarm_l": Vector3(0.3, -0.1, 0.95), "lowerarm_l": Vector3(0.1, 0.05, 1.0)}
		var whirl2 := whirl.duplicate()
		whirl2["lowerarm_r"] = Vector3(0.3, 0.9, -0.15)
		var release := {"upperarm_r": Vector3(-0.2, 0.55, 0.8), "lowerarm_r": Vector3(-0.05, 0.35, 0.95),
			"upperarm_l": Vector3(0.35, -0.6, 0.4), "lowerarm_l": Vector3(0.2, -0.5, 0.6)}
		var follow := {"upperarm_r": Vector3(0.1, -0.35, 0.93), "lowerarm_r": Vector3(0.35, -0.5, 0.75),
			"upperarm_l": Vector3(0.3, -0.9, 0.15), "lowerarm_l": Vector3(0.15, -0.85, 0.35)}
		var spin := _aimed(target, idle, strike, [[0.0, whirl], [0.11, whirl2], [0.22, whirl]])
		spin.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("Sling_Whirl", spin)
		lib.add_animation("Sling_Release", _aimed(target, idle, strike, [
			[0.0, whirl2], [RELEASE, release], [RELEASE + 0.12, follow], [THROW_TIME, follow]]))
		# The bow: held out at arm's length in the left fist, upright, while the right hand draws
		# the string back to the jaw; the chest turns side-on to the mark.
		var nock := {"twist": -0.35, "upperarm_l": Vector3(0.25, 0.08, 0.97), "lowerarm_l": Vector3(0.1, 0.06, 1.0),
			"blade_l": Vector3(0.0, 1.0, 0.05), "upperarm_r": Vector3(-0.2, 0.1, 0.97), "lowerarm_r": Vector3(0.35, 0.08, 0.93)}
		var full := {"twist": -0.55, "upperarm_l": Vector3(0.12, 0.1, 1.0), "lowerarm_l": Vector3(0.02, 0.08, 1.0),
			"blade_l": Vector3(0.0, 1.0, 0.05), "upperarm_r": Vector3(-0.75, 0.2, -0.5), "lowerarm_r": Vector3(0.82, 0.12, 0.55)}
		lib.add_animation("Bow_Draw", _aimed(target, idle, strike, [[0.0, nock], [DRAW_TIME, full]]))
		var after := full.duplicate()
		after["lowerarm_r"] = Vector3(-0.3, 0.0, -0.95)
		after["upperarm_r"] = Vector3(-0.85, 0.0, -0.5)
		lib.add_animation("Bow_Loose", _aimed(target, idle, strike, [[0.0, full], [0.06, after], [LOOSE_TIME, after]]))
		# Reaching over the right shoulder to the back, and across to the left hip.
		var back := {"upperarm_r": Vector3(-0.25, 0.9, -0.15), "lowerarm_r": Vector3(0.25, 0.1, -0.95)}
		var hip := {"upperarm_r": Vector3(0.15, -0.85, 0.45), "lowerarm_r": Vector3(0.9, -0.2, 0.35)}
		lib.add_animation("Reach_Back", _aimed(target, idle, strike, [[0.0, back], [STOW_TIME - 0.12, back]]))
		lib.add_animation("Reach_Hip", _aimed(target, idle, strike, [[0.0, hip], [STOW_TIME - 0.12, hip]]))
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


## Where `bone` is in model space at `time` of an animation made for `sk`. Bones the animation
## leaves alone take their pose from the start of `base`.
static func pose_transform(anim: Animation, sk: Skeleton3D, bone: int, time: float, base: Animation = null) -> Transform3D:
	var out := Transform3D.IDENTITY
	var b := bone
	while b >= 0:
		var path := NodePath("Armature/Skeleton3D:%s" % sk.get_bone_name(b))
		var local := sk.get_bone_rest(b)
		var from := anim
		var at := time
		if base != null and anim.find_track(path, Animation.TYPE_ROTATION_3D) < 0:
			from = base
			at = 0.0
		var turn := from.find_track(path, Animation.TYPE_ROTATION_3D)
		if turn >= 0:
			local.basis = Basis(from.rotation_track_interpolate(turn, at))
		var place := from.find_track(path, Animation.TYPE_POSITION_3D)
		if place >= 0:
			local.origin = from.position_track_interpolate(place, at)
		out = local * out
		b = sk.get_bone_parent(b)
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


## The poses of the three blows of a combo, made with the right hand ("r") or the left ("l").
## Right hand: A chops from overhead down the middle; B is a backhand from the left across to the
## right; C cuts from high on the right down to low on the left. Left hand: the same moves seen in
## a mirror, except that B is the left hand's forehand, which also sweeps from left to right.
##
## The whole body goes into each blow. The hips turn with the cut ("hips") and carry the weight
## from the back foot to the front ("shift", "sink", "pitch"), the chest turns and bends further
## on top of that ("twist", "lean"), and the other arm swings the opposite way to balance. The
## feet stay where the figure stands (the left foot in front, as in the Idle clip); only the last
## blow steps into the cut with the front foot ("step") and steps back as it ends.
static func _blow_keys(side: String) -> Dictionary:
	var a := [
		[0.0, {"hips": -0.2, "twist": -0.12, "lean": -0.12, "shift": Vector3(-0.01, 0.0, -0.05),
			"upperarm_r": Vector3(-0.3, 0.9, 0.15), "lowerarm_r": Vector3(0.2, 0.7, -0.7), "blade_r": Vector3(0.05, 0.45, -0.9),
			"upperarm_l": Vector3(0.35, -0.5, 0.8), "lowerarm_l": Vector3(-0.05, 0.2, 0.98)}],
		[0.08, {"hips": -0.1, "twist": -0.08, "lean": -0.06, "shift": Vector3(0.0, 0.0, -0.02),
			"upperarm_r": Vector3(-0.15, 0.8, 0.55), "lowerarm_r": Vector3(0.12, 0.75, 0.65), "blade_r": Vector3(0.08, 0.99, 0.1),
			"upperarm_l": Vector3(0.35, -0.55, 0.75), "lowerarm_l": Vector3(0.0, 0.1, 1.0)}],
		[0.14, {"hips": 0.12, "twist": 0.06, "lean": 0.14, "pitch": 0.04, "shift": Vector3(0.01, 0.0, 0.07), "sink": 0.05,
			"upperarm_r": Vector3(-0.08, 0.35, 0.93), "lowerarm_r": Vector3(0.15, 0.05, 0.99), "blade_r": Vector3(0.08, 0.25, 0.96),
			"upperarm_l": Vector3(0.45, -0.8, 0.3), "lowerarm_l": Vector3(0.15, -0.4, 0.9)}],
		[0.2, {"hips": 0.26, "twist": 0.12, "lean": 0.28, "pitch": 0.08, "shift": Vector3(0.02, 0.0, 0.12), "sink": 0.075,
			"upperarm_r": Vector3(-0.03, -0.2, 0.98), "lowerarm_r": Vector3(0.2, -0.6, 0.78), "blade_r": Vector3(0.1, -0.45, 0.89),
			"upperarm_l": Vector3(0.5, -0.85, -0.05), "lowerarm_l": Vector3(0.3, -0.65, 0.7)}],
		[0.3, {"hips": 0.3, "twist": 0.15, "lean": 0.34, "pitch": 0.1, "shift": Vector3(0.02, 0.0, 0.14), "sink": 0.09,
			"upperarm_r": Vector3(0.0, -0.7, 0.7), "lowerarm_r": Vector3(0.2, -0.9, 0.4), "blade_r": Vector3(0.12, -0.85, 0.5),
			"upperarm_l": Vector3(0.5, -0.8, -0.3), "lowerarm_l": Vector3(0.35, -0.75, 0.55)}],
	]
	var backhand := [
		[0.0, {"hips": 0.3, "twist": 0.5, "lean": 0.1, "shift": Vector3(0.03, 0.0, 0.05), "sink": 0.07,
			"upperarm_r": Vector3(0.55, 0.0, 0.83), "lowerarm_r": Vector3(0.95, 0.1, -0.1), "blade_r": Vector3(0.5, 0.1, -0.85),
			"upperarm_l": Vector3(0.5, -0.85, 0.1), "lowerarm_l": Vector3(0.2, -0.7, 0.65)}],
		[0.06, {"hips": 0.2, "twist": 0.3, "lean": 0.1, "shift": Vector3(0.02, 0.0, 0.05), "sink": 0.08,
			"upperarm_r": Vector3(0.25, 0.0, 0.97), "lowerarm_r": Vector3(0.7, 0.05, 0.7), "blade_r": Vector3(0.98, 0.08, 0.15),
			"upperarm_l": Vector3(0.55, -0.8, 0.05), "lowerarm_l": Vector3(0.3, -0.7, 0.6)}],
		[0.13, {"lean": 0.08, "shift": Vector3(-0.01, 0.0, 0.04), "sink": 0.09,
			"upperarm_r": Vector3(-0.3, 0.02, 0.95), "lowerarm_r": Vector3(-0.15, 0.02, 0.99), "blade_r": Vector3(-0.25, 0.05, 0.97),
			"upperarm_l": Vector3(0.65, -0.75, -0.05), "lowerarm_l": Vector3(0.4, -0.7, 0.55)}],
		[0.185, {"hips": -0.2, "twist": -0.25, "lean": 0.06, "shift": Vector3(-0.03, 0.0, 0.03), "sink": 0.08,
			"upperarm_r": Vector3(-0.7, 0.0, 0.7), "lowerarm_r": Vector3(-0.7, 0.0, 0.7), "blade_r": Vector3(-0.97, 0.05, 0.2),
			"upperarm_l": Vector3(0.7, -0.65, -0.2), "lowerarm_l": Vector3(0.55, -0.7, 0.4)}],
		[0.24, {"hips": -0.3, "twist": -0.45, "lean": 0.05, "shift": Vector3(-0.04, 0.0, 0.02), "sink": 0.07,
			"upperarm_r": Vector3(-0.9, 0.0, 0.4), "lowerarm_r": Vector3(-0.85, 0.0, 0.1), "blade_r": Vector3(-0.7, 0.05, -0.7),
			"upperarm_l": Vector3(0.75, -0.6, -0.25), "lowerarm_l": Vector3(0.6, -0.7, 0.35)}],
	]
	var forehand := [
		[0.0, {"hips": -0.3, "twist": -0.5, "lean": 0.05, "shift": Vector3(-0.04, 0.0, 0.02), "sink": 0.07,
			"upperarm_r": Vector3(-0.85, 0.1, -0.3), "lowerarm_r": Vector3(-0.6, 0.15, -0.75), "blade_r": Vector3(-0.3, 0.15, -0.95),
			"upperarm_l": Vector3(0.35, -0.55, 0.75), "lowerarm_l": Vector3(0.0, -0.1, 1.0)}],
		[0.06, {"hips": -0.2, "twist": -0.3, "lean": 0.06, "shift": Vector3(-0.03, 0.0, 0.03), "sink": 0.08,
			"upperarm_r": Vector3(-0.75, 0.05, 0.4), "lowerarm_r": Vector3(-0.55, 0.05, 0.6), "blade_r": Vector3(-0.98, 0.08, 0.1),
			"upperarm_l": Vector3(0.45, -0.65, 0.6), "lowerarm_l": Vector3(0.1, -0.3, 0.95)}],
		[0.13, {"lean": 0.08, "shift": Vector3(-0.01, 0.0, 0.04), "sink": 0.09,
			"upperarm_r": Vector3(-0.3, 0.0, 0.95), "lowerarm_r": Vector3(0.15, 0.0, 0.99), "blade_r": Vector3(0.4, 0.02, 0.92),
			"upperarm_l": Vector3(0.6, -0.75, 0.2), "lowerarm_l": Vector3(0.3, -0.6, 0.75)}],
		[0.185, {"hips": 0.2, "twist": 0.25, "lean": 0.1, "shift": Vector3(0.02, 0.0, 0.05), "sink": 0.08,
			"upperarm_r": Vector3(0.05, -0.02, 1.0), "lowerarm_r": Vector3(0.65, -0.02, 0.75), "blade_r": Vector3(0.97, 0.0, 0.2),
			"upperarm_l": Vector3(0.65, -0.7, -0.1), "lowerarm_l": Vector3(0.45, -0.7, 0.55)}],
		[0.24, {"hips": 0.3, "twist": 0.45, "lean": 0.1, "shift": Vector3(0.03, 0.0, 0.05), "sink": 0.07,
			"upperarm_r": Vector3(0.35, -0.05, 0.93), "lowerarm_r": Vector3(0.9, -0.05, 0.4), "blade_r": Vector3(0.85, 0.0, -0.5),
			"upperarm_l": Vector3(0.7, -0.6, -0.3), "lowerarm_l": Vector3(0.5, -0.7, 0.45)}],
	]
	var c := [
		[0.0, {"hips": -0.3, "twist": -0.45, "lean": -0.08, "shift": Vector3(-0.02, 0.0, -0.05), "sink": 0.03,
			"upperarm_r": Vector3(-0.7, 0.65, -0.2), "lowerarm_r": Vector3(-0.2, 0.85, -0.45), "blade_r": Vector3(-0.35, 0.55, -0.75),
			"upperarm_l": Vector3(0.3, -0.45, 0.85), "lowerarm_l": Vector3(-0.1, 0.1, 1.0)}],
		[0.11, {"hips": -0.08, "twist": -0.15, "lean": 0.05, "shift": Vector3(0.0, 0.0, 0.03), "sink": 0.05, "step": Vector3(0.0, 0.06, 0.1),
			"upperarm_r": Vector3(-0.45, 0.5, 0.72), "lowerarm_r": Vector3(-0.05, 0.45, 0.9), "blade_r": Vector3(0.15, 0.8, 0.55),
			"upperarm_l": Vector3(0.4, -0.6, 0.65), "lowerarm_l": Vector3(0.05, -0.15, 1.0)}],
		[0.2, {"hips": 0.22, "twist": 0.2, "lean": 0.22, "pitch": 0.06, "shift": Vector3(0.03, 0.0, 0.15), "sink": 0.13, "step": Vector3(0.0, 0.0, 0.2),
			"upperarm_r": Vector3(-0.1, 0.0, 1.0), "lowerarm_r": Vector3(0.35, -0.3, 0.88), "blade_r": Vector3(0.55, -0.45, 0.7),
			"upperarm_l": Vector3(0.55, -0.8, 0.1), "lowerarm_l": Vector3(0.3, -0.6, 0.75)}],
		[0.32, {"hips": 0.35, "twist": 0.45, "lean": 0.3, "pitch": 0.1, "shift": Vector3(0.03, 0.0, 0.18), "sink": 0.16, "step": Vector3(0.0, 0.0, 0.2),
			"upperarm_r": Vector3(0.3, -0.55, 0.78), "lowerarm_r": Vector3(0.75, -0.6, 0.3), "blade_r": Vector3(0.75, -0.65, -0.1),
			"upperarm_l": Vector3(0.6, -0.7, -0.35), "lowerarm_l": Vector3(0.45, -0.75, 0.5)}],
	]
	# The last blow holds its end for a moment, then the front foot steps back under the body
	# while the arms stay where the cut left them.
	var spent: Dictionary = c[3][1]
	c.append([0.41, spent])
	c.append([0.48, _with(spent, {"hips": 0.22, "lean": 0.2, "pitch": 0.06, "shift": Vector3(0.02, 0.0, 0.1), "sink": 0.1, "step": Vector3(0.0, 0.05, 0.1)})])
	c.append([0.55, _with(spent, {"hips": 0.1, "lean": 0.1, "pitch": 0.02, "shift": Vector3(0.0, 0.0, 0.03), "sink": 0.04, "step": Vector3.ZERO})])
	# The first blow made off the ground: the body arches back with the weapon high and the legs
	# trailing, then folds forward and brings the weapon down as the knees come up in front and
	# the legs reach for the ground. Here the legs are not held by the feet; each thigh and shin
	# points the way given.
	var air := [
		[0.0, {"hips": -0.15, "pitch": -0.12, "twist": -0.2, "lean": -0.3,
			"upperarm_r": Vector3(-0.35, 0.9, -0.15), "lowerarm_r": Vector3(0.15, 0.6, -0.78), "blade_r": Vector3(0.05, 0.35, -0.93),
			"upperarm_l": Vector3(0.3, 0.3, 0.9), "lowerarm_l": Vector3(0.0, 0.5, 0.87),
			"thigh_r": Vector3(-0.08, -0.9, -0.42), "calf_r": Vector3(0.0, -0.3, -0.95),
			"thigh_l": Vector3(0.1, -0.97, 0.2), "calf_l": Vector3(0.0, -0.55, -0.83)}],
		[0.07, {"hips": -0.08, "pitch": -0.08, "twist": -0.12, "lean": -0.2,
			"upperarm_r": Vector3(-0.15, 0.85, 0.5), "lowerarm_r": Vector3(0.12, 0.8, 0.58), "blade_r": Vector3(0.08, 0.99, 0.1),
			"upperarm_l": Vector3(0.35, 0.05, 0.93), "lowerarm_l": Vector3(0.05, 0.3, 0.95),
			"thigh_r": Vector3(-0.08, -0.95, -0.3), "calf_r": Vector3(0.0, -0.35, -0.94),
			"thigh_l": Vector3(0.1, -0.9, 0.42), "calf_l": Vector3(0.0, -0.6, -0.8)}],
		[0.13, {"hips": 0.08, "pitch": 0.08, "twist": 0.05, "lean": 0.15,
			"upperarm_r": Vector3(-0.08, 0.3, 0.95), "lowerarm_r": Vector3(0.15, 0.0, 0.99), "blade_r": Vector3(0.08, 0.2, 0.97),
			"upperarm_l": Vector3(0.45, -0.5, 0.55), "lowerarm_l": Vector3(0.2, -0.3, 0.93),
			"thigh_r": Vector3(-0.1, -0.85, 0.3), "calf_r": Vector3(0.0, -0.7, -0.7),
			"thigh_l": Vector3(0.1, -0.7, 0.7), "calf_l": Vector3(0.0, -0.8, -0.6)}],
		[0.19, {"hips": 0.2, "pitch": 0.2, "twist": 0.15, "lean": 0.42,
			"upperarm_r": Vector3(-0.03, -0.3, 0.95), "lowerarm_r": Vector3(0.2, -0.68, 0.7), "blade_r": Vector3(0.1, -0.55, 0.83),
			"upperarm_l": Vector3(0.55, -0.75, -0.2), "lowerarm_l": Vector3(0.35, -0.7, 0.6),
			"thigh_r": Vector3(-0.12, -0.6, 0.79), "calf_r": Vector3(-0.03, -0.88, -0.47),
			"thigh_l": Vector3(0.12, -0.45, 0.88), "calf_l": Vector3(0.03, -0.8, -0.6)}],
		[0.3, {"hips": 0.22, "pitch": 0.2, "twist": 0.2, "lean": 0.5,
			"upperarm_r": Vector3(0.0, -0.78, 0.63), "lowerarm_r": Vector3(0.2, -0.93, 0.3), "blade_r": Vector3(0.12, -0.9, 0.42),
			"upperarm_l": Vector3(0.55, -0.7, -0.45), "lowerarm_l": Vector3(0.4, -0.8, 0.45),
			"thigh_r": Vector3(-0.1, -0.9, 0.42), "calf_r": Vector3(-0.02, -0.98, -0.2),
			"thigh_l": Vector3(0.12, -0.8, 0.6), "calf_l": Vector3(0.02, -0.95, -0.3)}],
	]
	var out := {"a": a, "b": backhand, "c": c, "air": air}
	if side == "l":
		out = {"a": _mirror_keys(a), "b": _mirror_keys(forehand), "c": _mirror_keys(c), "air": _mirror_keys(air)}
	for blow in out:
		# Hold the last pose to the end of the move; the one-shot then fades back to the walk.
		var keys: Array = out[blow]
		var length: float = BLOWS[maxi(0, ["a", "b", "c"].find(blow))]["length"]
		if float(keys[keys.size() - 1][0]) < length - 0.001:
			keys.append([length, keys[keys.size() - 1][1]])
	return out


## A pose with some of its values changed.
static func _with(pose: Dictionary, changes: Dictionary) -> Dictionary:
	var out := pose.duplicate()
	for key in changes:
		out[key] = changes[key]
	return out


## The same poses for the other side of the body: right and left swapped, directions mirrored.
## The feet are not swapped: the left one is in front whichever hand strikes.
static func _mirror_keys(keys: Array) -> Array:
	var out: Array = []
	for k in keys:
		var m := {}
		for key in k[1]:
			var v: Variant = k[1][key]
			var name: String = key
			if name.ends_with("_r"):
				name = name.trim_suffix("_r") + "_l"
			elif name.ends_with("_l"):
				name = name.trim_suffix("_l") + "_r"
			if v is Vector3:
				m[name] = Vector3(-v.x, v.y, v.z)
			elif name == "twist" or name == "hips":
				m[name] = -float(v)
			else:
				m[name] = v
		out.append([k[0], m])
	return out


## A clip made from poses. Each key is [time, {bone: direction}]: the bone is turned from its pose
## in `base` so that it points that way (model space). Everything else keeps its pose from `base`,
## except that the right hand is closed as in `fist`. A key may also hold "twist" and "lean" for
## the chest, and "blade_r" / "blade_l": the way something held in that fist should point (see
## _grip). With `whole_body` the clip also moves the hips and legs (see _stand); without it, it
## holds the upper body only.
static func _aimed(sk: Skeleton3D, base: Animation, fist: Animation, keys: Array, whole_body: bool = false) -> Animation:
	var names: Array = UPPER_BODY.duplicate()
	for side in ["l", "r"]:
		for finger in FINGERS:
			for joint in 3:
				names.append("%s_0%d_%s" % [finger, joint + 1, side])
	if whole_body:
		names.append_array(LOWER_BODY)
	var out := Animation.new()
	out.loop_mode = Animation.LOOP_NONE
	var tracks := {}
	for n in names:
		if sk.find_bone(n) >= 0:
			var track := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(track, NodePath("Armature/Skeleton3D:%s" % n))
			tracks[n] = track
	# Where the hips are in `base`, in the space of the bone above them.
	var pelvis_path := NodePath("Armature/Skeleton3D:pelvis")
	var pelvis_at := sk.get_bone_rest(sk.find_bone("pelvis")).origin
	var base_place := base.find_track(pelvis_path, Animation.TYPE_POSITION_3D)
	if base_place >= 0:
		pelvis_at = base.position_track_interpolate(base_place, 0.0)
	var place := -1
	if whole_body:
		place = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(place, pelvis_path)
	var child_of := {"upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l"}
	# The way out of each fist on the thumb side, in hand space: what "blade_*" aims.
	var grips := {"r": fist_frame(sk, fist, 0.46, "r").basis.y, "l": fist_frame(sk, base, 0.0, "l").basis.y}
	for key in keys:
		var local := {}
		for b in sk.get_bone_count():
			local[b] = _anim_basis(base, sk, b, 0.0)
		for finger in FINGERS:
			for joint in 3:
				var fb := sk.find_bone("%s_0%d_r" % [finger, joint + 1])
				if fb >= 0:
					local[fb] = _anim_basis(fist, sk, fb, 0.46)
		var aims: Dictionary = key[1]
		var turned := 0.0   # how far the hips have turned and bent the body above them
		var bent := 0.0
		if whole_body:
			out.position_track_insert_key(place, float(key[0]), _stand(sk, local, pelvis_at, aims))
			turned = float(aims.get("hips", 0.0))
			bent = float(aims.get("pitch", 0.0))
		# The chest turns and bends, a third at each spine bone; the head turns back to the front
		# and lifts, so the eyes stay on what is being struck.
		var tw := float(aims.get("twist", 0.0))
		var ln := float(aims.get("lean", 0.0))
		if tw != 0.0 or ln != 0.0:
			var r := Basis(Vector3.UP, tw / 3.0) * Basis(Vector3.RIGHT, ln / 3.0)
			for n in ["spine_01", "spine_02", "spine_03"]:
				_turn(sk, local, sk.find_bone(n), r)
		if tw + turned != 0.0 or ln + bent != 0.0:
			_turn(sk, local, sk.find_bone("neck_01"), Basis(Vector3.UP, -(tw + turned) * 0.6) * Basis(Vector3.RIGHT, -maxf(ln + bent, 0.0) * 0.45))
		for n in ["upperarm_r", "lowerarm_r", "upperarm_l", "lowerarm_l"]:
			if not aims.has(n):
				continue
			var b := sk.find_bone(n)
			var parent := Basis.IDENTITY
			var p := sk.get_bone_parent(b)
			while p >= 0:
				parent = (local[p] as Basis) * parent
				p = sk.get_bone_parent(p)
			var along: Vector3 = sk.get_bone_rest(sk.find_bone(child_of[n])).origin.normalized()
			var from: Vector3 = ((local[b] as Basis) * along).normalized()
			var to: Vector3 = (parent.inverse() * (aims[n] as Vector3)).normalized()
			local[b] = Basis(Quaternion(from, to)) * (local[b] as Basis)
		for side in ["r", "l"]:
			if aims.has("blade_" + side):
				_grip(sk, local, side, grips[side], (aims["blade_" + side] as Vector3).normalized())
		for n in tracks:
			out.rotation_track_insert_key(tracks[n], float(key[0]), (local[sk.find_bone(n)] as Basis).get_rotation_quaternion())
	# Between two poses the bones turn evenly, which lets a planted foot drift a little while
	# the hips travel. The hips and legs get one more pose halfway to hold the feet down.
	if whole_body:
		for i in keys.size() - 1:
			var here: Dictionary = keys[i][1]
			var next: Dictionary = keys[i + 1][1]
			if here.has("thigh_r") or here.has("thigh_l") or next.has("thigh_r") or next.has("thigh_l"):
				continue
			var half := {}
			for n in ["hips", "pitch", "sink"]:
				half[n] = (float(here.get(n, 0.0)) + float(next.get(n, 0.0))) * 0.5
			for n in ["shift", "step"]:
				half[n] = ((here.get(n, Vector3.ZERO) as Vector3) + (next.get(n, Vector3.ZERO) as Vector3)) * 0.5
			var local := {}
			for b in sk.get_bone_count():
				local[b] = _anim_basis(base, sk, b, 0.0)
			var time := (float(keys[i][0]) + float(keys[i + 1][0])) * 0.5
			out.position_track_insert_key(place, time, _stand(sk, local, pelvis_at, half))
			for n in LOWER_BODY:
				out.rotation_track_insert_key(tracks[n], time, (local[sk.find_bone(n)] as Basis).get_rotation_quaternion())
	out.length = float(keys[keys.size() - 1][0])
	return out


## Moves the hips of a pose and bends the legs so that the feet stay where they stand. `local`
## holds the pose (bone -> local orientation) and is changed; `at` is where the pelvis is in it,
## in the space of the bone above. Returns where the pelvis goes, in that same space.
## From `aims`, all in model space: "hips" turns the pelvis (+ to the left), "pitch" bends it
## forward, "shift" moves it and "sink" lowers it (metres); "step" moves the front (left) foot
## from its place. The rear (right) heel comes off the ground as that hip turns and drives
## forward, and either heel rises as far as it must for the leg to reach the hip.
## A leg given a "thigh_r" / "thigh_l" (and "calf_*") direction is off the ground instead: thigh
## and shin point that way and the foot goes where they take it.
static func _stand(sk: Skeleton3D, local: Dictionary, at: Vector3, aims: Dictionary) -> Vector3:
	var pelvis := sk.find_bone("pelvis")
	var above := _model_pose(sk, local, at, sk.get_bone_parent(pelvis))
	var before := above * Transform3D(local[pelvis] as Basis, at)
	# Where the legs are before anything moves.
	var legs := {}
	for side in ["l", "r"]:
		var leg := {}
		for part in ["thigh", "calf", "foot", "ball"]:
			leg[part] = _model_pose(sk, local, at, sk.find_bone("%s_%s" % [part, side]))
		legs[side] = leg
	var hips := float(aims.get("hips", 0.0))
	var shift: Vector3 = aims.get("shift", Vector3.ZERO)
	var turn := Basis(Vector3.UP, hips) * Basis(Vector3.RIGHT, float(aims.get("pitch", 0.0)))
	var after := Transform3D(turn * before.basis, before.origin + shift - Vector3(0.0, float(aims.get("sink", 0.0)), 0.0))
	var placed := above.affine_inverse() * after
	local[pelvis] = placed.basis
	for side in ["l", "r"]:
		var leg: Dictionary = legs[side]
		var thigh := sk.find_bone("thigh_" + side)
		var calf := sk.find_bone("calf_" + side)
		var foot := sk.find_bone("foot_" + side)
		var ball := sk.find_bone("ball_" + side)
		var hip0: Vector3 = (leg["thigh"] as Transform3D).origin
		var knee0: Vector3 = (leg["calf"] as Transform3D).origin
		var ankle0: Vector3 = (leg["foot"] as Transform3D).origin
		var toe0: Vector3 = (leg["ball"] as Transform3D).origin
		if aims.has("thigh_" + side):
			var thigh_free := _lie_along((leg["thigh"] as Transform3D).basis, sk.get_bone_rest(calf).origin, aims["thigh_" + side] as Vector3)
			var shin: Vector3 = aims.get("calf_" + side, Vector3.DOWN)
			var calf_free := _lie_along((leg["calf"] as Transform3D).basis, sk.get_bone_rest(foot).origin, shin)
			local[thigh] = after.basis.inverse() * thigh_free
			local[calf] = thigh_free.inverse() * calf_free
			continue
		var moved := Vector3.ZERO
		if side == "l":
			moved = aims.get("step", Vector3.ZERO)
		var hip: Vector3 = after * sk.get_bone_rest(thigh).origin
		var upper := sk.get_bone_rest(calf).origin.length()
		var lower := sk.get_bone_rest(foot).origin.length()
		# The heel turns up about the ball of the foot, which stays on the ground.
		var ahead := Vector3(toe0.x - ankle0.x, 0.0, toe0.z - ankle0.z).normalized()
		var hinge := Vector3.UP.cross(ahead).normalized()
		var lift := 0.0
		if side == "r":
			lift = clampf(hips * 1.2 + shift.z * 2.5, 0.0, 0.6)
		var ankle := ankle0 + moved
		while true:
			ankle = toe0 + moved + Basis(hinge, lift) * (ankle0 - toe0)
			if hip.distance_to(ankle) <= (upper + lower) * 0.995 or lift >= 1.0:
				break
			lift += 0.05
		# The knee: where a leg of these two lengths bends between hip and ankle, on the side it
		# bends to in the pose we started from.
		var to := ankle - hip
		var d := clampf(to.length(), absf(upper - lower) + 0.01, (upper + lower) * 0.999)
		var dir := to.normalized()
		var along := (upper * upper - lower * lower + d * d) / (2.0 * d)
		var out_by := sqrt(maxf(upper * upper - along * along, 0.0))
		var line := (ankle0 - hip0).normalized()
		var bend := (knee0 - hip0) - line * (knee0 - hip0).dot(line)
		if bend.length() < 0.01:
			bend = ahead
		bend -= dir * bend.dot(dir)
		var knee := hip + dir * along + bend.normalized() * out_by
		# Thigh and shin turn to lie along the new leg, keeping the roll they had over the foot;
		# the foot tips up on its ball, and the toes stay flat.
		var thigh_m := _lie_along((leg["thigh"] as Transform3D).basis, sk.get_bone_rest(calf).origin, knee - hip)
		var calf_m := _lie_along((leg["calf"] as Transform3D).basis, sk.get_bone_rest(foot).origin, ankle - knee)
		var foot_m := Basis(hinge, lift) * (leg["foot"] as Transform3D).basis
		local[thigh] = after.basis.inverse() * thigh_m
		local[calf] = thigh_m.inverse() * calf_m
		local[foot] = calf_m.inverse() * foot_m
		local[ball] = foot_m.inverse() * (leg["ball"] as Transform3D).basis
	return placed.origin


## An orientation (model space) turned the short way so that its direction `along` (in its own
## space) points the way `want`.
static func _lie_along(held: Basis, along: Vector3, want: Vector3) -> Basis:
	return Basis(Quaternion((held * along).normalized(), want.normalized())) * held


## Where a bone is in model space, from the local orientations in `local`, the rest offsets of
## the bones, and the place of the pelvis (`pelvis_at`, in the space of the bone above it).
static func _model_pose(sk: Skeleton3D, local: Dictionary, pelvis_at: Vector3, bone: int) -> Transform3D:
	var pelvis := sk.find_bone("pelvis")
	var out := Transform3D.IDENTITY
	var b := bone
	while b >= 0:
		out = Transform3D(local[b] as Basis, pelvis_at if b == pelvis else sk.get_bone_rest(b).origin) * out
		b = sk.get_bone_parent(b)
	return out


## A bone's orientation in model space, from the local orientations in `local`.
static func _model_basis(sk: Skeleton3D, local: Dictionary, bone: int) -> Basis:
	var out := Basis.IDENTITY
	var b := bone
	while b >= 0:
		out = (local[b] as Basis) * out
		b = sk.get_bone_parent(b)
	return out


## Turns a bone by `r`, a rotation in model space.
static func _turn(sk: Skeleton3D, local: Dictionary, bone: int, r: Basis) -> void:
	var parent := _model_basis(sk, local, sk.get_bone_parent(bone))
	local[bone] = parent.inverse() * r * parent * (local[bone] as Basis)


## Points what is held in a fist (`grip`, hand space) the way `want` (model space): first the
## forearm rolls about its length, then the wrist bends the rest of the way, but no further than a
## wrist can.
static func _grip(sk: Skeleton3D, local: Dictionary, side: String, grip: Vector3, want: Vector3) -> void:
	var lower := sk.find_bone("lowerarm_" + side)
	var hand := sk.find_bone("hand_" + side)
	var parent := _model_basis(sk, local, sk.get_bone_parent(lower))
	var ml: Basis = parent * (local[lower] as Basis)
	var f := (ml * sk.get_bone_rest(hand).origin).normalized()
	var mh: Basis = ml * (local[hand] as Basis)
	var b := (mh * grip).normalized()
	var bp := b - f * b.dot(f)
	var dp := want - f * want.dot(f)
	if bp.length() > 0.05 and dp.length() > 0.05:
		var roll := clampf(bp.normalized().signed_angle_to(dp.normalized(), f), -ROLL_MAX, ROLL_MAX)
		var r := Basis(f, roll)
		local[lower] = parent.inverse() * r * ml
		ml = r * ml
		mh = ml * (local[hand] as Basis)
		b = (mh * grip).normalized()
	var axis := b.cross(want)
	if axis.length() > 0.001:
		var q := Basis(axis.normalized(), minf(b.angle_to(want), WRIST_MAX))
		local[hand] = ml.inverse() * q * mh


## A bone's local orientation in `anim` at `time`, or its rest orientation if the clip leaves it.
static func _anim_basis(anim: Animation, sk: Skeleton3D, bone: int, time: float) -> Basis:
	var track := anim.find_track(NodePath("Armature/Skeleton3D:%s" % sk.get_bone_name(bone)), Animation.TYPE_ROTATION_3D)
	if track >= 0:
		return Basis(anim.rotation_track_interpolate(track, time))
	return sk.get_bone_rest(bone).basis


func _clip(anim: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = anim
	return node


## The upper body and the fingers: what the moves of the arms play over.
static func _upper_paths() -> Array:
	var out: Array = []
	for bone in UPPER_BODY:
		out.append(NodePath("Armature/Skeleton3D:%s" % bone))
	for side in ["l", "r"]:
		for finger in FINGERS:
			for joint in 3:
				out.append(NodePath("Armature/Skeleton3D:%s_0%d_%s" % [finger, joint + 1, side]))
	return out


func _setup_animation(sex: int) -> void:
	_player = AnimationPlayer.new()
	_model.add_child(_player)
	_player.root_node = NodePath("..")
	_player.add_animation_library("", _library(sex, skeleton))

	# Legs follow the walk cycle; blows, the sling and the bow play over the upper body only.
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
	# Off the ground the whole body goes over to the kit's jump pose.
	graph.add_node("air", AnimationNodeBlend2.new())
	graph.add_node("Jump", _clip("Jump"))
	graph.connect_node("air", 0, "walk")
	graph.connect_node("air", 1, "Jump")
	var upper := _upper_paths()
	# Poses held for as long as a button is: the sling going round, the bow drawn.
	var below := "air"
	for held in [["whirl_hold", "Sling_Whirl"], ["draw_hold", "Bow_Draw"]]:
		var blend := AnimationNodeBlend2.new()
		blend.filter_enabled = true
		for path in upper:
			blend.set_filter_path(path, true)
		graph.add_node(held[0], blend)
		graph.add_node(held[1], _clip(held[1]))
		var source: String = held[1]
		if held[0] == "draw_hold":
			# The draw starts from the beginning each time.
			graph.add_node("draw_seek", AnimationNodeTimeSeek.new())
			graph.connect_node("draw_seek", 0, held[1])
			source = "draw_seek"
		graph.connect_node(held[0], 0, below)
		graph.connect_node(held[0], 1, source)
		below = held[0]
	# Each upper-body move is a one-shot laid over everything before it in this list. Blows have
	# a speed of their own: a heavy weapon swings slower.
	var shots := [
		["blow_a_r", "Blow_A_R", 0.05, 0.15], ["blow_b_r", "Blow_B_R", 0.05, 0.12], ["blow_c_r", "Blow_C_R", 0.05, 0.15],
		["blow_a_l", "Blow_A_L", 0.05, 0.15], ["blow_b_l", "Blow_B_L", 0.05, 0.12], ["blow_c_l", "Blow_C_L", 0.05, 0.15],
		["punch", "Punch_Cross", 0.06, 0.15], ["throw", "Sling_Release", 0.04, 0.15], ["loose", "Bow_Loose", 0.03, 0.15],
		["reach_back", "Reach_Back", 0.12, 0.12], ["reach_hip", "Reach_Hip", 0.12, 0.12],
	]
	for s in shots:
		var shot: String = s[0]
		var one := AnimationNodeOneShot.new()
		one.fadein_time = float(s[2])
		one.fadeout_time = float(s[3])
		one.filter_enabled = true
		for path in upper:
			one.set_filter_path(path, true)
		graph.add_node(shot, one)
		var source: String = s[1]
		if not graph.has_node(source):
			var made := _clip(source)
			graph.add_node(source, made)
			if source == "Blow_A_R" or source == "Blow_A_L":
				_first_blow[source.right(1).to_lower()] = made
		if shot.begins_with("blow") or shot == "punch":
			graph.add_node(shot + "_speed", AnimationNodeTimeScale.new())
			graph.connect_node(shot + "_speed", 0, source)
			source = shot + "_speed"
		graph.connect_node(shot, 0, below)
		graph.connect_node(shot, 1, source)
		below = shot
	# The hips and legs of a blow made standing still or off the ground, and of a landing. Two
	# one-shots are used in turn and given the clip each time, so one stance fades into the next.
	_stance_clips.clear()
	for i in 2:
		var stance := "stance_%d" % i
		var one := AnimationNodeOneShot.new()
		one.fadein_time = 0.05
		one.fadeout_time = 0.15
		one.filter_enabled = true
		for bone in LOWER_BODY:
			one.set_filter_path(NodePath("Armature/Skeleton3D:%s" % bone), true)
		graph.add_node(stance, one)
		var clip := _clip("Blow_A_R")
		_stance_clips.append(clip)
		graph.add_node(stance + "_clip", clip)
		graph.add_node(stance + "_speed", AnimationNodeTimeScale.new())
		graph.connect_node(stance + "_speed", 0, stance + "_clip")
		graph.connect_node(stance, 0, below)
		graph.connect_node(stance, 1, stance + "_speed")
		below = stance
	# Landing has a one-shot of its own, laid over whatever else the legs are doing, so the feet
	# are on the ground at once.
	var land := AnimationNodeOneShot.new()
	land.fadein_time = 0.05
	land.fadeout_time = 0.15
	land.filter_enabled = true
	for bone in LOWER_BODY:
		land.set_filter_path(NodePath("Armature/Skeleton3D:%s" % bone), true)
	graph.add_node("land", land)
	graph.add_node("Land", _clip("Land"))
	graph.connect_node("land", 0, below)
	graph.connect_node("land", 1, "Land")
	below = "land"
	graph.connect_node("output", 0, below)

	_tree = AnimationTree.new()
	_model.add_child(_tree)
	_tree.root_node = NodePath("..")
	_tree.tree_root = graph
	_tree.anim_player = _tree.get_path_to(_player)
	if bool(_opts.get("always_animate", false)):
		_tree.process_mode = Node.PROCESS_MODE_ALWAYS
	_tree.active = true
	for s in shots:
		if str(s[0]).begins_with("blow") or s[0] == "punch":
			_tree.set("parameters/%s_speed/scale" % s[0], 1.0)
	for i in 2:
		_tree.set("parameters/stance_%d_speed/scale" % i, 1.0)
	_legs = ""
	_legs_left = 0.0
	_land_left = 0.0
	_in_air = false
	_air_time = 0.0
	_air = 0.0
	_tree.set("parameters/air/blend_amount", 0.0)
	_tree.set("parameters/walk/blend_position", 0.0)
	_tree.advance(0.0)


var _whirl_blend := 0.0
var _draw_blend := 0.0


## Call every frame with the horizontal speed in metres per second (0 when standing), and
## whether the figure is off the ground (jumping or falling).
func animate(delta: float, speed: float, airborne: bool = false) -> void:
	if _tree == null or dead or posed:
		return
	_speed = lerpf(_speed, speed, 1.0 - exp(-10.0 * delta))
	_tree.set("parameters/walk/blend_position", _speed)
	if _strike_left > 0.0:
		_strike_left -= delta
	# Off the ground the body takes the jump pose; coming down from a real jump, a figure that
	# stands still takes the landing on its knees.
	var flown := _air_time
	_air_time = _air_time + delta if airborne else 0.0
	var landed := _in_air and not airborne
	_in_air = airborne
	_air = move_toward(_air, 1.0 if _in_air else 0.0, delta * (10.0 if _in_air else 7.0))
	_tree.set("parameters/air/blend_amount", _air)
	if _legs_left > 0.0:
		_legs_left -= delta
		if _legs_left <= 0.0:
			_legs = ""
	if _land_left > 0.0:
		_land_left -= delta
	if landed:
		_legs_stop()
		if flown >= LAND_AFTER and _speed < PLANT_SPEED:
			_play("land")
			_land_left = _player.get_animation("Land").length
	elif _in_air or _speed > UNPLANT_SPEED:
		# A stance taken standing still: once the figure moves off or jumps, the legs let go of it.
		if _legs == "blow":
			_legs_stop()
		_land_stop()
	# What each hand holds turns smoothly between how it is carried and how it is gripped for a
	# blow (or, for a bow, held up to shoot), so it never jumps out of the fist.
	var k := 1.0 - exp(-28.0 * delta)
	if weapon != null and weapon.get_parent() == hand_r:
		var target := _strike if _strike_left > 0.0 and _strike_side == "r" else _carry
		weapon.transform = weapon.transform.interpolate_with(target, k)
	if offhand != null and offhand.get_parent() == hand_l:
		var up := (_strike_left > 0.0 and _strike_side == "l") or (offhand_kind == "bow" and (drawing or _loose_t >= 0.0))
		offhand.transform = offhand.transform.interpolate_with(_strike_l if up else _carry_l, k)
	if _swap_left >= 0.0:
		_swap_left -= delta
		if _swap_left < 0.0:
			sheathe(not sheathed)

	_whirl_blend = move_toward(_whirl_blend, 1.0 if _whirling else 0.0, delta * 10.0)
	_tree.set("parameters/whirl_hold/blend_amount", _whirl_blend)
	if _whirling:
		_whirl_t += delta
		_sling_turn(_throw_yaw + _whirl_t * 17.0, 0.35)
		if _auto_release >= 0.0 and _whirl_t >= _auto_release:
			sling_release()
	if _throw_t >= 0.0:
		_throw_t += delta
		if _throw_t < RELEASE:
			_sling_turn(_throw_yaw + (_whirl_t + _throw_t) * 17.0, 0.35)
		else:
			_sling_pouch.get_node("Stone").visible = false
			var droop := clampf((_throw_t - RELEASE) / 0.15, 0.0, 1.0)
			_sling_turn(_throw_yaw + PI, lerpf(0.35, 1.3, droop))
		if _throw_t >= THROW_TIME:
			_throw_t = -1.0
			_sling.visible = false
			if _stowed_for_throw:
				_stowed_for_throw = false
				_right_away(false)

	if drawing:
		draw_amount = minf(1.0, draw_amount + delta / DRAW_TIME)
	_draw_blend = move_toward(_draw_blend, 1.0 if drawing else 0.0, delta * 12.0)
	_tree.set("parameters/draw_hold/blend_amount", _draw_blend)
	if _loose_t >= 0.0:
		_loose_t += delta
		if _loose_t >= LOOSE_TIME:
			_loose_t = -1.0
	_update_bow()


## A blow with the weapon in the right hand, or a punch if the hand is empty.
func swing() -> void:
	attack(0)


## Blow `step` of a combo (see BLOWS), made with the right hand ("r") or the left ("l"), at
## `speed` (1 = normal). A hand with no weapon punches. A blow that follows another takes over.
## A figure standing still puts its hips and legs into the blow; one on the move keeps walking
## and strikes with the upper body only. Off the ground the first blow is a different one: the
## weapon comes down from overhead with the whole body folding behind it.
func attack(step: int, side: String = "r", speed: float = 1.0) -> void:
	if _tree == null or dead:
		return
	step = clampi(step, 0, BLOWS.size() - 1)
	var m: Dictionary = BLOWS[step]
	var held := weapon_kind if side == "r" else offhand_kind
	var armed := is_weapon(held)
	var shot := "%s_%s" % [m["shot"], side] if armed else "punch"
	var leap := armed and _in_air and step == 0
	var clip := "Blow_%s_%s" % ["Air" if leap else str(m["shot"]).right(1).to_upper(), side.to_upper()]
	if armed and step == 0:
		(_first_blow[side] as AnimationNodeAnimation).animation = clip
	if _shot != "" and _shot != shot:
		_tree.set("parameters/%s/request" % _shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_tree.set("parameters/%s_speed/scale" % shot, speed)
	_play(shot)
	_shot = shot
	_strike_side = side
	if leap:
		_legs_play(clip, speed, "air")
	elif armed and not _in_air and _speed < PLANT_SPEED:
		_land_stop()
		_legs_play(clip, speed, "blow")
	else:
		_legs_stop()
	if armed:
		_strike_left = float(m["length"]) / speed


## Plays the hips and legs of `clip` over the walk, taking over from whatever stance was there.
## `what` says what it is for (see _legs).
func _legs_play(clip: String, speed: float, what: String) -> void:
	_legs_stop()
	_stance = 1 - _stance
	(_stance_clips[_stance] as AnimationNodeAnimation).animation = clip
	_tree.set("parameters/stance_%d_speed/scale" % _stance, speed)
	_play("stance_%d" % _stance)
	_legs = what
	_legs_left = _player.get_animation(clip).length / speed


## Lets the hips and legs go back to walking, standing or the jump pose.
func _legs_stop() -> void:
	if _legs != "":
		_tree.set("parameters/stance_%d/request" % _stance, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_legs = ""
	_legs_left = 0.0


## Lets the knees come up from a landing early.
func _land_stop() -> void:
	if _land_left > 0.0:
		_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_land_left = 0.0


func _play(shot: String) -> void:
	_tree.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Puts the right hand's weapon on the back or belt for a moment (true), or back in the hand.
func _right_away(on: bool) -> void:
	if weapon == null:
		return
	var holder: Node3D = _holder(weapon_kind) if on else _hand_holder("r", weapon_kind)
	if weapon.get_parent() != holder:
		weapon.get_parent().remove_child(weapon)
		holder.add_child(weapon)
	weapon.transform = _stow if on else _carry


## Starts whirling the sling overhead. It keeps going round until sling_release().
func sling_start() -> void:
	if _tree == null or dead:
		return
	_whirling = true
	_whirl_t = 0.0
	_auto_release = -1.0
	_throw_t = -1.0
	_throw_yaw = global_rotation.y
	_sling.visible = true
	_sling_pouch.get_node("Stone").visible = true
	_sling_turn(_throw_yaw, 0.35)
	if weapon != null and not sheathed and weapon.get_parent() == hand_r:
		# The weapon goes on the back or belt for the throw, and comes back to the hand after.
		_right_away(true)
		_stowed_for_throw = true


## Lets the sling go: the arm comes over, and the stone leaves RELEASE seconds later.
func sling_release() -> void:
	if not _whirling:
		return
	_whirling = false
	_auto_release = -1.0
	_play("throw")
	_throw_t = 0.0


## A whole throw: whirled for WHIRL_TIME, then let go (enemies, and the checks).
func whirl() -> void:
	sling_start()
	_auto_release = WHIRL_TIME


func whirling() -> bool:
	return _whirling


## Starts drawing the bow; it stays drawn until bow_loose().
func bow_draw() -> void:
	if offhand_kind != "bow" or dead or _tree == null:
		return
	if sheathed:
		sheathe(false)
	drawing = true
	draw_amount = 0.0
	_loose_t = -1.0
	_tree.set("parameters/draw_seek/seek_request", 0.0)


## Lets the arrow go. Returns how far the bow was drawn (0..1).
func bow_loose() -> float:
	if not drawing:
		return 0.0
	var amount := draw_amount
	drawing = false
	draw_amount = 0.0
	_play("loose")
	_loose_t = 0.0
	return amount


## The string runs from tip to tip, or to the drawing hand while the bow is drawn; the arrow lies
## on the string from the hand to the grip.
func _update_bow() -> void:
	if offhand == null or offhand_kind != "bow" or _string.size() < 2:
		return
	var tips := [offhand.get_node("Tip0").global_position, offhand.get_node("Tip1").global_position]
	var nock: Vector3 = (tips[0] + tips[1]) * 0.5
	var in_hand := offhand.get_parent() == hand_l
	var pulled := in_hand and _draw_blend > 0.05
	if pulled:
		nock = nock.lerp(hand_r.global_transform * _strike.origin, _draw_blend)
	for k in 2:
		_stretch(_string[k], tips[k], nock)
	if _arrow != null:
		_arrow.visible = pulled and drawing
		if _arrow.visible:
			var grip: Vector3 = offhand.global_position
			var y := (grip - nock).normalized()
			var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
			var s := global_transform.basis.get_scale().x
			_arrow.global_transform = Transform3D(Basis(x, y, x.cross(y)).scaled(Vector3.ONE * s), nock)


## Stretches a unit-long cylinder between two points in its parent's space.
static func _segment(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	n.transform = Transform3D(Basis(x, d, x.cross(y)), (a + b) * 0.5)


## Stretches a unit-long cylinder between two points in the world.
static func _stretch(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var y := d / length
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	n.global_transform = Transform3D(Basis(x, y * length, x.cross(y)), (a + b) * 0.5)


func die() -> void:
	if dead or _tree == null:
		return
	dead = true
	_whirling = false
	drawing = false
	_model.rotation.y = PI
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
