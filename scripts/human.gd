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
## The material of everything worn: woven cloth. Each point is looked up by where it is on the
## standing body (CUSTOM0, set in _commit), from whichever side faces it most squarely, so the
## threads and patterns do not slide as the figure moves. The weave fades out with distance,
## where it would only shimmer; broad uneven shades stay.
const CLOTH_SHADER := """
shader_type spatial;
render_mode %s;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 second : source_color = vec3(1.0);
uniform vec3 third : source_color = vec3(1.0);
uniform int pattern = 0;
uniform float hem = 0.0;
varying vec3 rest;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float cloud(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Plain weave: each thread goes over one and under the next.
float weave(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float along = mod(cell.x + cell.y, 2.0) < 1.0 ? f.x : f.y;
	float across = mod(cell.x + cell.y, 2.0) < 1.0 ? f.y : f.x;
	return 0.72 + 0.28 * sin(along * 3.14159) * (0.6 + 0.4 * sin(across * 3.14159));
}

void vertex() {
	rest = CUSTOM0.xyz;
}

void fragment() {
	vec3 face = abs(normalize(cross(dFdx(rest), dFdy(rest))));
	vec3 w = pow(face, vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 q = rest * 130.0;
	float threads = weave(q.zy) * w.x + weave(q.xz) * w.y + weave(q.xy) * w.z;
	float far = clamp(max(fwidth(q.x), max(fwidth(q.y), fwidth(q.z))) * 1.3, 0.0, 1.0);
	threads = mix(threads, 0.88, far);
	vec3 color = tint;
	if (pattern == 1) {
		float s = fract(atan(rest.x, rest.z) / 6.28318 * 9.0 + cloud(rest * 3.0) * 0.08);
		color = s < 0.5 ? tint : (s < 0.66 ? second : (s < 0.84 ? tint : third));
	} else if (pattern == 2) {
		float h = rest.y - hem;
		color = h < 0.03 ? second : (h < 0.045 ? tint : (h < 0.07 ? third : (h < 0.085 ? tint : (h < 0.1 ? second : tint))));
	}
	float shade = 0.86 + 0.2 * cloud(rest * vec3(7.0, 2.5, 7.0)) + 0.06 * cloud(rest * 40.0);
	ALBEDO = color * threads * shade * 1.12;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
"""
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
## _library(). The timing follows real fencing and staff work: about a third of a second gathering
## the body and drawing the weapon back, a quick cut of under 0.2 s, then half a second of
## recovering balance before the figure is ready again.
const BLOWS := [
	{"shot": "blow_a", "hit": 0.5, "chain": 0.62, "length": 1.0, "power": 1.0, "arc": 0.2},
	{"shot": "blow_b", "hit": 0.42, "chain": 0.55, "length": 0.9, "power": 1.1, "arc": -0.1},
	{"shot": "blow_c", "hit": 0.55, "chain": 1e9, "length": 1.15, "power": 1.4, "arc": -0.1},
]
## Each kind of weapon is used in its own way: swords cut (BLOWS, poses in _blow_keys), daggers
## stab, sickle swords hook and slash, axes chop, clubs and maces smash, spears thrust, and the
## staff strikes with its butt (poses in _style_keys). Each style's blows in the order of a combo
## (the staff has only one): hit, chain and length as in BLOWS; power, the damage as a share of
## the weapon's; arc, how wide it reaches (the cosine of the angle off straight ahead that it
## still hits: 0.7 a narrow thrust, -0.3 a wide sweep). A bare fist punches with a sword's timing.
const STYLE_OF := {"dagger": "dagger", "sickle": "sickle", "sword_short": "sword", "sword": "sword", "sword_long": "sword",
	"axe": "axe", "club": "bludgeon", "mace": "bludgeon", "spear": "spear", "spear_long": "spear", "staff": "staff"}
const STYLES := {
	"sword": BLOWS,
	"dagger": [
		{"shot": "blow_a", "hit": 0.32, "chain": 0.42, "length": 0.7, "power": 1.0, "arc": 0.6},
		{"shot": "blow_b", "hit": 0.3, "chain": 0.4, "length": 0.7, "power": 1.1, "arc": 0.5},
		{"shot": "blow_c", "hit": 0.38, "chain": 1e9, "length": 0.85, "power": 1.4, "arc": 0.45},
	],
	"sickle": [
		{"shot": "blow_a", "hit": 0.5, "chain": 0.62, "length": 1.0, "power": 1.0, "arc": 0.3},
		{"shot": "blow_b", "hit": 0.45, "chain": 0.58, "length": 0.95, "power": 1.1, "arc": -0.1},
		{"shot": "blow_c", "hit": 0.55, "chain": 1e9, "length": 1.15, "power": 1.4, "arc": -0.2},
	],
	"axe": [
		{"shot": "blow_a", "hit": 0.55, "chain": 0.68, "length": 1.1, "power": 1.0, "arc": 0.2},
		{"shot": "blow_b", "hit": 0.5, "chain": 0.65, "length": 1.05, "power": 1.1, "arc": -0.2},
		{"shot": "blow_c", "hit": 0.62, "chain": 1e9, "length": 1.3, "power": 1.4, "arc": 0.35},
	],
	"bludgeon": [
		{"shot": "blow_a", "hit": 0.55, "chain": 0.68, "length": 1.1, "power": 1.0, "arc": 0.35},
		{"shot": "blow_b", "hit": 0.48, "chain": 0.62, "length": 1.0, "power": 1.1, "arc": 0.0},
		{"shot": "blow_c", "hit": 0.62, "chain": 1e9, "length": 1.3, "power": 1.4, "arc": -0.3},
	],
	"spear": [
		{"shot": "blow_a", "hit": 0.45, "chain": 0.58, "length": 0.95, "power": 1.0, "arc": 0.7},
		{"shot": "blow_b", "hit": 0.45, "chain": 0.58, "length": 0.95, "power": 1.1, "arc": 0.65},
		{"shot": "blow_c", "hit": 0.55, "chain": 1e9, "length": 1.15, "power": 1.4, "arc": 0.7},
	],
	"staff": [
		{"shot": "blow_a", "hit": 0.55, "chain": 1e9, "length": 1.05, "power": 1.25, "arc": 0.6},
		{"shot": "blow_b", "hit": 0.66, "chain": 1e9, "length": 1.2, "power": 0.8, "arc": -1.0, "stomp": true},
	],
}
## The sword's fourth blow (Fourth Cut): the first cut played backwards, rising from low to high.
const FOURTH_CUT := {"shot": "blow_a", "letter": "D", "hit": 0.5, "chain": 1e9, "length": 1.0, "power": 1.2, "arc": 0.2}
## The left arm in the poses of _style_keys: guarding (a shield before the chest), held back for
## balance, raised, out to the side, reaching ahead.
const GUARD_L := {"upperarm_l": Vector3(0.3, -0.75, 0.6), "lowerarm_l": Vector3(-0.2, 0.25, 0.95)}
const BALANCE_L := {"upperarm_l": Vector3(0.45, -0.85, -0.25), "lowerarm_l": Vector3(0.3, -0.6, 0.75)}
const RAISED_L := {"upperarm_l": Vector3(0.35, 0.05, 0.94), "lowerarm_l": Vector3(0.05, 0.3, 0.95)}
const OUT_L := {"upperarm_l": Vector3(0.8, -0.5, 0.3), "lowerarm_l": Vector3(0.6, -0.3, 0.75)}
const REACH_L := {"upperarm_l": Vector3(0.35, -0.35, 0.87), "lowerarm_l": Vector3(0.1, -0.1, 0.99)}
## How far a spear's shaft runs behind the fist and ahead of it, head and all (see _item_model).
const SPEAR_BACK := 0.6
const SPEAR_FRONT := 1.45
## The sling: whirled overhead for as long as the button is held (at least WHIRL_TIME), then the
## arm comes over and lets go RELEASE seconds later; the throw is over THROW_TIME after letting go.
## When the fist of the punch clip (Punch_Cross) is out furthest, at its own speed. A punch is
## played at the rate that brings the fist out when the blow lands.
const PUNCH_HIT := 0.25
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
## Weapons swung with both hands (Items "hands": 2), and how far apart the hands are on them.
const TWO_HANDED := ["staff"]
const STAFF_GRIP := 0.4
## How far a staff runs from the right fist to its butt and to its tip (see _item_model), and
## how thick it is: what _clear_shaft keeps out of the body.
const STAFF_BUTT := 0.6
const STAFF_TIP := 1.1
## For a blow the fists slide this far up a staff from where it is carried, to near its top: the
## butt is then STAFF_BACK behind the right fist and the top STAFF_FRONT ahead of it.
const STAFF_SLIDE := 0.75
const STAFF_BACK := STAFF_BUTT + STAFF_SLIDE
const STAFF_FRONT := STAFF_TIP - STAFF_SLIDE
const STAFF_RADIUS := 0.022


## Which way a weapon of `kind` is used (STYLE_OF); a bare fist or anything else, as a sword.
static func style_of(kind: String) -> String:
	return str(STYLE_OF.get(kind, "sword"))


## The blows of a weapon of `kind`, in the order of a combo (see STYLES).
static func blows(kind: String) -> Array:
	return STYLES[style_of(kind)]


## The clip of blow `letter` ("A", "B", "C" or "Air") made by `side`'s hand with a weapon of
## `kind`. Swords have the plain names (Blow_A_R); the others are named for their style
## (Blow_A_R_spear). Off the ground every one-handed weapon comes down from overhead as a sword
## does; the staff has its own thrust there too.
static func blow_clip(letter: String, side: String, kind: String) -> String:
	var style := style_of(kind)
	if style == "staff":
		return "Blow_%s_R_staff" % ("Air" if letter == "Air" else letter)
	if style == "sword" or letter == "Air":
		return "Blow_%s_%s" % [letter, side.to_upper()]
	return "Blow_%s_%s_%s" % [letter, side.to_upper(), style]
const DENSE := 0.03
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
## Figures built smaller than this are children (see _child_body).
const CHILD_SCALE := 0.8

static var _bodies := {}     # sex -> measured body data
static var _meshes := {}     # "sex/piece" -> generated ArrayMesh
static var _materials := {}  # key -> StandardMaterial3D
static var _libraries := {}  # sex -> AnimationLibrary retargeted to that body

var look := {}
var weapon_kind := "none"
var shield_style := "round"       # the shape of a shield made by set_hands: "round", "hide" or "rect"
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
var _blow_nodes := {}             # side -> the animation nodes of blows A, B and C
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
var _child := false               # built with a child's body (see _child_body)


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
## always_animate (bool: keep animating while the game is paused, for the character creator),
## child (bool; by default a figure scaled below CHILD_SCALE is a child, see _child_body).
## A figure built before it was put into the scene (as the camp's people are) takes its standing
## pose as it arrives, not at the first frame after: a dialog that opens at once would hold that
## frame up and leave the figure with its arms out.
func _ready() -> void:
	if _tree != null:
		_tree.advance(0.0)


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
	var size := float(opts.get("scale", 1.0))
	_child = bool(opts.get("child", size < CHILD_SCALE))
	var d := _body(sex, _child)
	scale = Vector3.ONE * size

	var scene: PackedScene = d["scene"]
	_model = scene.instantiate()
	_model.rotation.y = PI      # the model faces +Z; figures in this game face -Z
	add_child(_model)
	skeleton = _model.find_child("Skeleton3D", true, false)
	var body_mi: MeshInstance3D = skeleton.get_node(str(d["body_name"]))
	var eyes_mi: MeshInstance3D = skeleton.get_node("Eyes")
	var brows_mi: MeshInstance3D = skeleton.get_node("Eyebrows")

	var hair_c: Color = HAIR_COLORS[_i("hair_color")]
	body_mi.material_override = _skin_material(sex, _i("skin"), _child)
	eyes_mi.material_override = _eye_material(_i("eyes"))
	var head_size: Vector3 = HEAD_SCALES[_i("face")]
	if _child:
		# A child has a large, round head, narrow shoulders and short limbs; the smaller the child,
		# the more so. The legs are shortened by scaling the thighs (and all below them), and the
		# body is lowered by what that takes off, so the feet stay on the ground.
		body_mi.mesh = d["mesh"]
		var young := clampf((0.9 - size) / 0.35, 0.0, 1.0)
		head_size *= Vector3(1.04, 0.98, 1.02) * lerpf(1.25, 1.55, young)
		var legs := lerpf(0.95, 0.92, young)
		var arms := lerpf(0.92, 0.86, young)
		for side in ["l", "r"]:
			skeleton.set_bone_pose_scale(skeleton.find_bone("thigh_" + side), Vector3.ONE * legs)
			skeleton.set_bone_pose_scale(skeleton.find_bone("clavicle_" + side), Vector3.ONE * arms)
		_model.position.y = -(1.0 - legs) * float((d["rest"] as Dictionary)["thigh_l"].y)
	skeleton.set_bone_pose_scale(skeleton.find_bone("Head"), head_size)

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
	var brows := 1 if _child else _i("brows")   # children have fine brows
	if brows == own_brows:
		brows_mi.material_override = _hair_material(_texture_index(brows_mi), hair_c)
	else:
		brows_mi.visible = false
		_attach_to_head("brows_regular" if brows == 0 else "brows_female", hair_c, sex)

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
static func _body(sex: int, child: bool = false) -> Dictionary:
	var id := "%d%s" % [sex, "c" if child else ""]
	if _bodies.has(id):
		return _bodies[id]
	if child:
		_bodies[id] = _child_body(_body(sex), id)
		return _bodies[id]
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
		"arrays": arrays, "id": id,
	}
	_bodies[id] = d
	inst.free()
	return d


## A child's body: the adult body made fuller, so that scaled down it has a child's soft, rounded
## limbs instead of a small man's thin ones. Each vertex moves out along its normal by an amount
## set by the bones it follows (none for the head, a little for hands and feet, most for the
## thighs and the belly). Clothes are fitted to this body, not the adult one.
static func _child_body(adult: Dictionary, id: String) -> Dictionary:
	var verts: PackedVector3Array = adult["verts"]
	var normals: PackedVector3Array = adult["normals"]
	var bones: PackedInt32Array = adult["bones"]
	var weights: PackedFloat32Array = adult["weights"]
	var per: int = adult["per"]
	var bind: Dictionary = adult["bind"]
	var fuller := {}
	for name in bind:
		fuller[int(bind[name])] = _plump(str(name))
	var grown := PackedVector3Array()
	grown.resize(verts.size())
	for v in verts.size():
		var by := 0.0
		for k in per:
			by += weights[v * per + k] * float(fuller.get(bones[v * per + k], 0.0))
		grown[v] = verts[v] + normals[v] * by
	var arrays: Array = (adult["arrays"] as Array).duplicate()
	arrays[Mesh.ARRAY_VERTEX] = grown
	for extra in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[extra] = null    # unused by the skin material, and they would need their format flags
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
	var d := adult.duplicate()
	d["verts"] = grown
	d["mesh"] = mesh
	d["id"] = id
	return d


## How much fuller a child is at each bone (metres, before the figure is scaled down).
static func _plump(bone: String) -> float:
	for part in [["thigh", 0.02], ["calf", 0.013], ["upperarm", 0.018], ["lowerarm", 0.013],
			["pelvis", 0.018], ["spine_01", 0.024], ["spine_02", 0.02], ["spine_03", 0.014], ["clavicle", 0.01],
			["neck", 0.012], ["hand", 0.005], ["foot", 0.005], ["ball", 0.004]]:
		if bone.begins_with(str(part[0])):
			return float(part[1])
	return 0.0


func _texture(file: String) -> Texture2D:
	return load(DIR + "tex/" + file)


## A child's skin has much less of the grown body's muscle relief.
func _skin_material(sex: int, tone: int, child: bool = false) -> StandardMaterial3D:
	var key := "skin/%d/%d/%s" % [sex, tone, child]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _texture("skin_female.png" if sex == 1 else "skin_male.png")
		m.albedo_color = SKIN_TINTS[tone]
		m.normal_enabled = true
		m.normal_texture = _texture("normal_female.png" if sex == 1 else "normal_male.png")
		m.normal_scale = 0.3 if child else 1.0
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


## Woven cloth of `color`. `pattern` "stripes" runs bands of `second` and `third` down the
## garment; "hem" puts them as a border above its lower edge (`hem` is that edge's height).
func _cloth_material(color: Color, two_sided: bool = false, pattern: String = "", second: Color = Color.WHITE, third: Color = Color.WHITE, hem: float = 0.0) -> Material:
	var key := "cloth/%s/%s/%s/%s/%s/%.2f" % [color.to_html(), two_sided, pattern, second.to_html(), third.to_html(), hem]
	if not _materials.has(key):
		var cull := "cull_disabled" if two_sided else "cull_back"
		if not _materials.has(cull):
			var shader := Shader.new()
			shader.code = CLOTH_SHADER % cull
			_materials[cull] = shader
		var m := ShaderMaterial.new()
		m.shader = _materials[cull]
		m.set_shader_parameter("tint", color)
		m.set_shader_parameter("second", second)
		m.set_shader_parameter("third", third)
		m.set_shader_parameter("pattern", ["", "stripes", "hem"].find(pattern))
		m.set_shader_parameter("hem", hem)
		_materials[key] = m
	return _materials[key]


## Wood, hide, horn or (`metal`) bronze and iron, for what is held in the hand.
func _hard_material(color: Color, metal: bool = false) -> StandardMaterial3D:
	var key := "hard/%s/%s" % [color.to_html(), metal]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.38 if metal else 0.85
		m.metallic = 0.7 if metal else 0.0
		m.metallic_specular = 0.6
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
		# A third entry names a pattern woven into the piece (see _cloth_material), in the sash
		# color and a darker shade of the cloth.
		for p in opts["wear"]:
			var base := _wear_color(p[1], cloth, sash_c)
			_wear(sex, d, body_mi, str(p[0]), base, TWO_SIDED.has(str(p[0])), str(p[2]) if p.size() > 2 else "", sash_c, base.darkened(0.45))
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
func _wear(sex: int, d: Dictionary, body_mi: MeshInstance3D, piece: String, color: Color, two_sided: bool = false, pattern: String = "", second: Color = Color.WHITE, third: Color = Color.WHITE) -> void:
	var key := "%s/%s" % [d["id"], piece]
	if not _meshes.has(key):
		_meshes[key] = _make_piece(d, piece)
	var mesh: ArrayMesh = _meshes[key]
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = piece
	mi.mesh = mesh
	mi.skin = body_mi.skin
	mi.material_override = _cloth_material(color, two_sided, pattern, second, third, mesh.get_aabb().position.y)
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
			return _shell(d, 0.045 if piece == "mantle" else 0.02, choose)
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
			var brow: float = float(d["brow_top"]) + 0.012
			var ear: float = float(d["eye_y"]) - 0.05
			var skull := _skull_half(d)
			choose = func(p: Vector3, o: int) -> bool:
				if o == head_b:
					if absf(p.x) > skull and p.y < brow + 0.01:
						return false    # the ears stay out, or the cloth would stand off round them
					return p.y > brow or (p.z < mid_z - 0.015 and p.y > ear)
				if o == neck_b:
					return p.z < mid_z - 0.01
				return false
			return _shell(d, 0.009, choose)
		"helmet":
			# Like the cap but thicker, coming down over the brow and the ears.
			var head_b: int = bind["Head"]
			var mid_z: float = ((d["head_lo"] as Vector3).z + (d["head_hi"] as Vector3).z) * 0.5
			var brow: float = float(d["brow_top"]) + 0.01
			var ear: float = float(d["eye_y"]) - 0.07
			var skull := _skull_half(d)
			choose = func(p: Vector3, o: int) -> bool:
				if o == head_b:
					if absf(p.x) > skull and p.y < brow + 0.01:
						return false
					return p.y > brow or (p.z < mid_z + 0.01 and p.y > ear)
				return false
			return _shell(d, 0.02, choose)
		"necklace":
			var neck_y: float = (rest["neck_01"] as Vector3).y
			return _ring(d, neck_y + 0.015, 0.018, 0.012, ["neck_01"], ["neck_01"])
		"band":
			# Round the forehead just above the brows, over the edge of the cap.
			return _band(d, float(d["brow_top"]) + 0.016, 0.02, 0.014)
		"band_wide":
			# Sits over hair, so it stands further off the skull.
			return _band(d, float(d["brow_top"]) + 0.018, 0.026, 0.024)
		"crown":
			return _band(d, float(d["brow_top"]) + 0.03, 0.032, 0.012)
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
	# Where each corner is on the standing body, for the cloth's weave and patterns: laid on
	# from there they stay put on the cloth however the limbs move (see CLOTH_SHADER).
	var rest := PackedFloat32Array()
	rest.resize(v.size() * 3)
	for k in v.size():
		rest[k * 3] = v[k].x
		rest[k * 3 + 1] = v[k].y
		rest[k * 3 + 2] = v[k].z
	arrays[Mesh.ARRAY_CUSTOM0] = rest
	var mesh := ArrayMesh.new()
	var flags: int = (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
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


## Half the width of the skull just above the ears: anything of the head wider than this, lower
## down, is an ear.
static func _skull_half(d: Dictionary) -> float:
	return float(_section(d, float(d["brow_top"]) + 0.03, ["Head"], 0.012).get("half", 0.075)) + 0.006


## A band round the head at height `y`, `height` tall and `gap` off it, following the head's own
## outline (taken angle by angle from the vertices, ears left out, dents filled) rather than an
## ellipse, so it sits close all round.
static func _band(d: Dictionary, y: float, height: float, gap: float) -> ArrayMesh:
	var verts: PackedVector3Array = d["verts"]
	var owner: PackedInt32Array = d["owner"]
	var bind: Dictionary = d["bind"]
	var per: int = d["per"]
	var head_b: int = bind["Head"]
	var skull := _skull_half(d)
	var near: Array = []
	var center := Vector2.ZERO
	for i in verts.size():
		var p := verts[i]
		if owner[i] == head_b and absf(p.y - y) < maxf(0.012, height * 0.6) and absf(p.x) <= skull:
			near.append(Vector2(p.x, p.z))
			center += Vector2(p.x, p.z)
	if near.is_empty():
		return null
	center /= near.size()
	var sides := 32
	var r := PackedFloat32Array()
	r.resize(sides)
	for q in near:
		var off: Vector2 = q - center
		var k := int(round(fposmod(off.angle(), TAU) / TAU * sides)) % sides
		r[k] = maxf(r[k], off.length())
	for step in 2:
		# Empty or dented places take their neighbours' reach.
		var out := r.duplicate()
		for k in sides:
			var beside := (r[(k + sides - 1) % sides] + r[(k + 1) % sides]) * 0.5
			out[k] = maxf(r[k], beside)
		r = out
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var b := PackedInt32Array()
	var w := PackedFloat32Array()
	var idx := PackedInt32Array()
	for row in 2:
		for k in sides:
			var a := TAU * k / sides
			var reach := r[k] + gap
			v.append(Vector3(center.x + cos(a) * reach, y + (row - 0.5) * height, center.y + sin(a) * reach))
			nrm.append(Vector3(cos(a), 0.0, sin(a)))
			_put_weights(b, w, [[head_b, 1.0]], per)
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
			rx = maxf(rx + 0.006, float(s["half"]) + 0.035)
			rz = maxf(rz + 0.006, (float(s["front"]) - float(s["back"])) * 0.5 + 0.045)
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
			var left := smoothstep(-0.3, 0.3, x / rx)      # +x is the figure's left side
			var pairs: Array
			if below <= 0.0:
				# From halfway down the thigh the cloth goes wholly with the leg under it, so a leg
				# stepping forward carries the cloth instead of coming through it.
				var legs := smoothstep(0.0, 0.55, down)
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
## Gives the battle stance the clip of the weapon in the right hand.
func _set_guard_clip() -> void:
	var style := style_of(weapon_kind if is_weapon(weapon_kind) else "none")
	if not GUARD_STYLES.has(style):
		style = "sword"
	for c in _guard_clips:
		(c as AnimationNodeAnimation).animation = "Guard_" + style


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
	_set_guard_clip()
	_strike_left = 0.0
	var idle: Animation = _player.get_animation("Idle")
	var fist_anim: Animation = _player.get_animation("Sword_Attack")
	_strike = fist_frame(skeleton, fist_anim, 0.46, "r")
	if TWO_HANDED.has(right):
		# A staff is struck with held near its top (STAFF_SLIDE): it slides through the hands as
		# the blow begins, since the carry and the strike are blended (see animate()).
		_strike.origin -= _strike.basis.y.normalized() * STAFF_SLIDE
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
			_part(n, _cyl(0.0, 0.035, 0.3 if long else 0.24, metal, true), Vector3(0, 1.9 if long else 1.42, 0))
		"dagger":
			_blade(n, 0.3, metal)
		"sickle":
			_blade(n, 0.44, metal)
			_part(n, _box(Vector3(0.012, 0.16, 0.045), metal, true), Vector3(0, 0.56, 0.045), Vector3(0.75, 0, 0))
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
			head.material_override = _hard_material(metal, true)
			_part(n, head, Vector3(0, 0.52, 0))
		"axe":
			_part(n, _cyl(0.017, 0.019, 0.72, wood), Vector3(0, 0.22, 0))
			_part(n, _box(Vector3(0.016, 0.2, 0.17), metal, true), Vector3(0, 0.5, 0.1))
		"shield" when shield_style == "hide":
			# A nomad's small shield: hide stretched over a wicker frame, with a darker edge.
			var hide := tint if tint.a > 0.0 else Color(0.55, 0.42, 0.28)
			var skin := _cyl(0.25, 0.25, 0.03, hide)
			skin.scale = Vector3(0.85, 1.0, 1.15)
			_part(n, skin, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
			var edge := _cyl(0.265, 0.265, 0.02, hide.darkened(0.4))
			edge.scale = Vector3(0.85, 1.0, 1.15)
			_part(n, edge, Vector3(0, 0, -0.004), Vector3(PI * 0.5, 0, 0))
			_part(n, _cyl(0.05, 0.07, 0.025, hide.lightened(0.25)), Vector3(0, 0, 0.025), Vector3(PI * 0.5, 0, 0))
		"shield" when shield_style == "rect":
			# The rectangular shield of Canaan and Syria: a board covered in cowhide, bound at
			# the edges, with a bronze boss.
			var hide := tint if tint.a > 0.0 else Color(0.66, 0.52, 0.36)
			_part(n, _box(Vector3(0.46, 0.72, 0.03), hide), Vector3.ZERO)
			for end in [-1.0, 1.0]:
				_part(n, _box(Vector3(0.5, 0.045, 0.036), hide.darkened(0.45)), Vector3(0, end * 0.36, 0))
				_part(n, _box(Vector3(0.045, 0.72, 0.036), hide.darkened(0.45)), Vector3(end * 0.23, 0, 0))
			_part(n, _cyl(0.03, 0.07, 0.04, bronze, true), Vector3(0, 0.0, 0.03), Vector3(PI * 0.5, 0, 0))
		"shield":
			var face := _cyl(0.34, 0.34, 0.035, tint if tint.a > 0.0 else Color(0.6, 0.45, 0.3))
			_part(n, face, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
			var rim := _cyl(0.36, 0.36, 0.025, bronze.darkened(0.2), true)
			_part(n, rim, Vector3(0, 0, -0.004), Vector3(PI * 0.5, 0, 0))
			var boss := _cyl(0.02, 0.08, 0.05, bronze, true)
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


func _cyl(top: float, bottom: float, height: float, color: Color, metal: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = _hard_material(color, metal)
	return mi


func _box(size: Vector3, color: Color, metal: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _hard_material(color, metal)
	return mi


func _part(to: Node3D, mi: MeshInstance3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	mi.position = pos
	mi.rotation = rot
	to.add_child(mi)


func _blade(to: Node3D, length: float, color: Color) -> void:
	_part(to, _cyl(0.017, 0.017, 0.13, Color(0.3, 0.2, 0.13)), Vector3.ZERO)
	_part(to, _box(Vector3(0.03, 0.022, 0.11), color, true), Vector3(0, 0.07, 0))
	_part(to, _box(Vector3(0.012, length, 0.05), color, true), Vector3(0, 0.08 + length * 0.5, 0))


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
	var d := _body(_i("sex"), _child)
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
	stone.material_override = _hard_material(Color(0.55, 0.52, 0.48))
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
			lib.add_animation("Blow_D_%s" % side.to_upper(), _aimed(target, idle, strike, _backwards(keys["a"]), true))
		for style in ["dagger", "sickle", "axe", "bludgeon", "spear"]:
			var right: Dictionary = _style_keys(style)
			for side in ["r", "l"]:
				for blow in ["a", "b", "c"]:
					var keys: Array = right[blow] if side == "r" else _mirror_keys(right[blow])
					lib.add_animation(blow_clip(blow.to_upper(), side, style if style != "bludgeon" else "club"), _aimed(target, idle, strike, keys, true))
		var staff_keys := _style_keys("staff")
		for blow in staff_keys:
			lib.add_animation(blow_clip(blow.capitalize(), "r", "staff"), _aimed(target, idle, strike, staff_keys[blow], true))
		# The battle stance of each way of fighting (see `battle`).
		for style in GUARD_STYLES:
			lib.add_animation("Guard_" + style, _guard_clip(target, idle, strike, style))
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
	# Every blow starts from a wind-up the whole body takes part in: the hips and chest coil away
	# from the cut, the weight rocks back, the shoulder lifts and the weapon is drawn far back
	# ("shrug_r" lifts the shoulder, "reach_r" carries it forward, both in radians). Then the hips
	# drive round, the weight goes onto the front foot, the shoulder follows the arm through, and
	# the other arm pulls back to balance. The cut carries on well past where it lands.
	# The fist is placed ("hold_r", model space, metres from the feet) and the blade pointed
	# ("blade_r"); the elbow then bends toward "pole_r" (by default out and down). A one-handed
	# cut is drawn back no higher than the head: the fist goes beside the ear, not over it.
	# A starts from the guard of the battle stance (see _guard_pose): the fist low in front, at
	# the belly, the blade pointing ahead and up at the foe.
	var a := [
		[0.0, {"hips": -0.1, "twist": -0.1, "lean": -0.04, "shift": Vector3(0.0, 0.0, -0.02),
			"hold_r": Vector3(-0.2, 1.12, 0.24), "blade_r": Vector3(0.1, 0.5, 0.86),
			"upperarm_l": Vector3(0.3, -0.6, 0.75), "lowerarm_l": Vector3(0.0, 0.0, 1.0)}],
		[0.305, {"hips": -0.32, "twist": -0.22, "lean": -0.12, "pitch": -0.05, "shift": Vector3(-0.02, 0.0, -0.08), "sink": 0.02,
			"shrug_r": 0.12, "reach_r": -0.1,
			"hold_r": Vector3(-0.3, 1.58, -0.1), "blade_r": Vector3(0.05, 0.3, -0.95),
			"upperarm_l": Vector3(0.3, -0.2, 0.93), "lowerarm_l": Vector3(0.05, 0.15, 0.99)}],
		[0.38, {"hips": -0.05, "twist": 0.0, "lean": 0.06, "shift": Vector3(0.0, 0.0, 0.03), "sink": 0.03,
			"shrug_r": 0.1, "reach_r": 0.1,
			"hold_r": Vector3(-0.2, 1.6, 0.22), "blade_r": Vector3(0.05, 0.8, 0.6),
			"upperarm_l": Vector3(0.35, -0.3, 0.88), "lowerarm_l": Vector3(0.1, -0.1, 0.99)}],
		[0.477, {"hips": 0.3, "twist": 0.15, "lean": 0.32, "pitch": 0.08, "shift": Vector3(0.02, 0.0, 0.15), "sink": 0.08,
			"reach_r": 0.32,
			"hold_r": Vector3(-0.1, 1.25, 0.62), "blade_r": Vector3(0.08, -0.3, 0.95),
			"upperarm_l": Vector3(0.45, -0.85, -0.25), "lowerarm_l": Vector3(0.3, -0.6, 0.75)}],
		[0.643, {"hips": 0.4, "twist": 0.22, "lean": 0.42, "pitch": 0.12, "shift": Vector3(0.03, 0.0, 0.19), "sink": 0.12,
			"reach_r": 0.32,
			"hold_r": Vector3(-0.03, 0.95, 0.48), "blade_r": Vector3(0.12, -0.8, 0.58),
			"upperarm_l": Vector3(0.45, -0.8, -0.4), "lowerarm_l": Vector3(0.35, -0.75, 0.5)}],
	]
	# B: the backhand, drawn back past the left hip at chest height and cut across to the right.
	var backhand := [
		[0.0, {"hips": 0.2, "twist": 0.25, "lean": 0.15, "shift": Vector3(0.02, 0.0, 0.06), "sink": 0.06, "reach_r": 0.15,
			"hold_r": Vector3(0.12, 1.28, 0.42), "blade_r": Vector3(0.7, 0.1, -0.7), "pole_r": Vector3(-0.2, -0.5, 0.8),
			"upperarm_l": Vector3(0.45, -0.8, -0.15), "lowerarm_l": Vector3(0.25, -0.55, 0.8)}],
		[0.285, {"hips": 0.45, "twist": 0.6, "lean": 0.12, "shift": Vector3(0.04, 0.0, 0.0), "sink": 0.08, "reach_r": 0.38, "shrug_r": 0.05,
			"hold_r": Vector3(0.3, 1.32, 0.3), "blade_r": Vector3(0.4, 0.15, -0.9), "pole_r": Vector3(-0.2, -0.5, 0.8),
			"upperarm_l": Vector3(0.45, -0.85, -0.2), "lowerarm_l": Vector3(0.15, -0.4, 0.9)}],
		[0.36, {"hips": 0.25, "twist": 0.3, "lean": 0.12, "shift": Vector3(0.02, 0.0, 0.03), "sink": 0.09, "reach_r": 0.3,
			"hold_r": Vector3(0.06, 1.32, 0.55), "blade_r": Vector3(0.98, 0.08, 0.15), "pole_r": Vector3(-0.3, -0.6, 0.5),
			"upperarm_l": Vector3(0.55, -0.8, -0.1), "lowerarm_l": Vector3(0.3, -0.6, 0.72)}],
		[0.42, {"hips": 0.0, "twist": 0.0, "lean": 0.12, "shift": Vector3(0.0, 0.0, 0.06), "sink": 0.1, "reach_r": 0.15,
			"hold_r": Vector3(-0.22, 1.32, 0.56), "blade_r": Vector3(-0.25, 0.05, 0.97),
			"upperarm_l": Vector3(0.7, -0.6, -0.2), "lowerarm_l": Vector3(0.6, -0.4, 0.6)}],
		[0.497, {"hips": -0.3, "twist": -0.35, "lean": 0.1, "shift": Vector3(-0.04, 0.0, 0.05), "sink": 0.09, "reach_r": -0.1,
			"hold_r": Vector3(-0.46, 1.3, 0.26), "blade_r": Vector3(-0.97, 0.05, 0.2),
			"upperarm_l": Vector3(0.8, -0.5, 0.0), "lowerarm_l": Vector3(0.7, -0.3, 0.6)}],
		[0.606, {"hips": -0.45, "twist": -0.55, "lean": 0.08, "shift": Vector3(-0.05, 0.0, 0.03), "sink": 0.08, "reach_r": -0.2,
			"hold_r": Vector3(-0.52, 1.26, -0.04), "blade_r": Vector3(-0.65, 0.05, -0.75),
			"upperarm_l": Vector3(0.85, -0.45, 0.25), "lowerarm_l": Vector3(0.7, -0.2, 0.7)}],
	]
	# The forehand (the left hand's B, mirrored): drawn back past the right hip at chest height and
	# cut across to the left.
	var forehand := [
		[0.0, {"hips": -0.2, "twist": -0.25, "lean": 0.06, "shift": Vector3(-0.02, 0.0, 0.02), "sink": 0.05, "reach_r": -0.1,
			"hold_r": Vector3(-0.42, 1.25, 0.3), "blade_r": Vector3(-0.6, 0.15, 0.78),
			"upperarm_l": Vector3(0.3, -0.5, 0.8), "lowerarm_l": Vector3(-0.1, -0.05, 0.99)}],
		[0.285, {"hips": -0.45, "twist": -0.6, "lean": 0.06, "shift": Vector3(-0.05, 0.0, 0.0), "sink": 0.07, "reach_r": -0.2, "shrug_r": 0.05,
			"hold_r": Vector3(-0.5, 1.3, -0.05), "blade_r": Vector3(-0.3, 0.2, -0.93),
			"upperarm_l": Vector3(0.25, -0.4, 0.88), "lowerarm_l": Vector3(-0.25, -0.05, 0.97)}],
		[0.36, {"hips": -0.25, "twist": -0.3, "lean": 0.08, "shift": Vector3(-0.03, 0.0, 0.03), "sink": 0.08, "reach_r": 0.0,
			"hold_r": Vector3(-0.45, 1.3, 0.3), "blade_r": Vector3(-0.98, 0.08, 0.1),
			"upperarm_l": Vector3(0.4, -0.65, 0.6), "lowerarm_l": Vector3(0.1, -0.3, 0.95)}],
		[0.42, {"hips": 0.0, "twist": 0.0, "lean": 0.12, "shift": Vector3(0.0, 0.0, 0.06), "sink": 0.09, "reach_r": 0.25,
			"hold_r": Vector3(-0.15, 1.32, 0.58), "blade_r": Vector3(0.4, 0.02, 0.92),
			"upperarm_l": Vector3(0.55, -0.75, -0.2), "lowerarm_l": Vector3(0.35, -0.6, 0.7)}],
		[0.497, {"hips": 0.3, "twist": 0.35, "lean": 0.12, "shift": Vector3(0.03, 0.0, 0.05), "sink": 0.09, "reach_r": 0.35,
			"hold_r": Vector3(0.12, 1.3, 0.5), "blade_r": Vector3(0.97, 0.0, 0.2), "pole_r": Vector3(-0.3, -0.6, 0.5),
			"upperarm_l": Vector3(0.65, -0.7, -0.25), "lowerarm_l": Vector3(0.45, -0.7, 0.55)}],
		[0.606, {"hips": 0.45, "twist": 0.55, "lean": 0.12, "shift": Vector3(0.04, 0.0, 0.05), "sink": 0.08, "reach_r": 0.4,
			"hold_r": Vector3(0.28, 1.28, 0.28), "blade_r": Vector3(0.8, 0.0, -0.6), "pole_r": Vector3(-0.2, -0.5, 0.8),
			"upperarm_l": Vector3(0.7, -0.6, -0.35), "lowerarm_l": Vector3(0.55, -0.7, 0.4)}],
	]
	# C: drawn back beside the right ear, cut from high on the right down across to low on the left
	# with a step into it.
	var c := [
		[0.0, {"hips": -0.3, "twist": -0.35, "lean": 0.0, "shift": Vector3(-0.02, 0.0, 0.0), "sink": 0.04, "shrug_r": 0.08,
			"hold_r": Vector3(-0.42, 1.45, -0.05), "blade_r": Vector3(-0.5, 0.5, -0.7),
			"upperarm_l": Vector3(0.4, -0.6, 0.7), "lowerarm_l": Vector3(0.0, -0.1, 1.0)}],
		[0.34, {"hips": -0.5, "twist": -0.6, "lean": -0.1, "pitch": -0.04, "shift": Vector3(-0.04, 0.0, -0.08), "sink": 0.03,
			"shrug_r": 0.12, "reach_r": -0.15,
			"hold_r": Vector3(-0.36, 1.58, -0.2), "blade_r": Vector3(-0.3, 0.3, -0.9),
			"upperarm_l": Vector3(0.25, 0.05, 0.97), "lowerarm_l": Vector3(-0.1, 0.15, 0.98)}],
		[0.445, {"hips": -0.2, "twist": -0.2, "lean": 0.05, "shift": Vector3(0.0, 0.0, 0.04), "sink": 0.05, "step": Vector3(0.0, 0.08, 0.12),
			"shrug_r": 0.08, "reach_r": 0.1,
			"hold_r": Vector3(-0.32, 1.58, 0.25), "blade_r": Vector3(0.15, 0.85, 0.5),
			"upperarm_l": Vector3(0.35, -0.4, 0.85), "lowerarm_l": Vector3(0.05, -0.2, 0.98)}],
		[0.55, {"hips": 0.3, "twist": 0.25, "lean": 0.3, "pitch": 0.08, "shift": Vector3(0.03, 0.0, 0.2), "sink": 0.15, "step": Vector3(0.0, 0.0, 0.3),
			"reach_r": 0.35,
			"hold_r": Vector3(-0.16, 1.28, 0.7), "blade_r": Vector3(0.55, -0.45, 0.7),
			"upperarm_l": Vector3(0.55, -0.8, -0.15), "lowerarm_l": Vector3(0.35, -0.6, 0.72)}],
		[0.724, {"hips": 0.5, "twist": 0.55, "lean": 0.38, "pitch": 0.12, "shift": Vector3(0.04, 0.0, 0.24), "sink": 0.18, "step": Vector3(0.0, 0.0, 0.3),
			"reach_r": 0.4,
			"hold_r": Vector3(0.24, 1.02, 0.6), "blade_r": Vector3(0.75, -0.65, -0.15), "pole_r": Vector3(-0.3, -0.6, 0.5),
			"upperarm_l": Vector3(0.6, -0.65, -0.45), "lowerarm_l": Vector3(0.45, -0.75, 0.5)}],
	]
	# The last blow holds its end for a moment, then the front foot steps back under the body
	# and the sword comes back toward the guard.
	var spent: Dictionary = c[4][1]
	c.append([0.866, spent])
	c.append([1.008, _with(spent, {"hips": 0.3, "twist": 0.35, "lean": 0.22, "pitch": 0.06, "shift": Vector3(0.02, 0.0, 0.12), "sink": 0.11, "step": Vector3(0.0, 0.05, 0.12),
		"hold_r": Vector3(0.12, 1.06, 0.5), "blade_r": Vector3(0.6, -0.3, 0.75)})])
	c.append([1.15, _with(spent, {"hips": 0.12, "twist": 0.15, "lean": 0.1, "pitch": 0.02, "shift": Vector3(0.0, 0.0, 0.03), "sink": 0.04, "step": Vector3.ZERO, "reach_r": 0.15,
		"hold_r": Vector3(-0.08, 1.1, 0.36), "blade_r": Vector3(0.2, 0.2, 0.96), "pole_r": Vector3.ZERO})])
	# The first blow made off the ground: the body arches back with the weapon high and the legs
	# trailing, then folds forward and brings the weapon down as the knees come up in front and
	# the legs reach for the ground. Here the legs are not held by the feet; each thigh and shin
	# points the way given.
	var air := [
		[0.0, {"hips": -0.15, "pitch": -0.12, "twist": -0.2, "lean": -0.3,
			"hold_r": Vector3(-0.3, 1.6, -0.12), "blade_r": Vector3(0.05, 0.35, -0.93),
			"upperarm_l": Vector3(0.3, 0.3, 0.9), "lowerarm_l": Vector3(0.0, 0.5, 0.87),
			"thigh_r": Vector3(-0.08, -0.9, -0.42), "calf_r": Vector3(0.0, -0.3, -0.95),
			"thigh_l": Vector3(0.1, -0.97, 0.2), "calf_l": Vector3(0.0, -0.55, -0.83)}],
		[0.23, {"hips": -0.08, "pitch": -0.08, "twist": -0.12, "lean": -0.2,
			"hold_r": Vector3(-0.22, 1.64, 0.2), "blade_r": Vector3(0.08, 0.95, 0.3),
			"upperarm_l": Vector3(0.35, 0.05, 0.93), "lowerarm_l": Vector3(0.05, 0.3, 0.95),
			"thigh_r": Vector3(-0.08, -0.95, -0.3), "calf_r": Vector3(0.0, -0.35, -0.94),
			"thigh_l": Vector3(0.1, -0.9, 0.42), "calf_l": Vector3(0.0, -0.6, -0.8)}],
		[0.32, {"hips": 0.08, "pitch": 0.08, "twist": 0.05, "lean": 0.15,
			"hold_r": Vector3(-0.15, 1.48, 0.5), "blade_r": Vector3(0.08, 0.2, 0.97),
			"upperarm_l": Vector3(0.45, -0.5, 0.55), "lowerarm_l": Vector3(0.2, -0.3, 0.93),
			"thigh_r": Vector3(-0.1, -0.85, 0.3), "calf_r": Vector3(0.0, -0.7, -0.7),
			"thigh_l": Vector3(0.1, -0.7, 0.7), "calf_l": Vector3(0.0, -0.8, -0.6)}],
		[0.41, {"hips": 0.2, "pitch": 0.2, "twist": 0.15, "lean": 0.42,
			"hold_r": Vector3(-0.1, 1.2, 0.6), "blade_r": Vector3(0.1, -0.55, 0.83),
			"upperarm_l": Vector3(0.55, -0.75, -0.2), "lowerarm_l": Vector3(0.35, -0.7, 0.6),
			"thigh_r": Vector3(-0.12, -0.6, 0.79), "calf_r": Vector3(-0.03, -0.88, -0.47),
			"thigh_l": Vector3(0.12, -0.45, 0.88), "calf_l": Vector3(0.03, -0.8, -0.6)}],
		[0.571, {"hips": 0.22, "pitch": 0.2, "twist": 0.2, "lean": 0.5,
			"hold_r": Vector3(-0.05, 1.0, 0.5), "blade_r": Vector3(0.12, -0.9, 0.42),
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


## The blows of every weapon that is not a sword (STYLE_OF), for the right hand; the left hand's are
## these mirrored. Each pose puts the fist where it should be ("hold_r", model space: +Z ahead, -X
## the figure's right, metres from the feet) and points what it holds ("blade_r": the way its
## head or point faces). The rest is as in _blow_keys: the hips, chest and legs, and the left arm
## guarding (GUARD_L), held back for balance (BALANCE_L), raised (RAISED_L), out to the side
## (OUT_L) or reaching ahead (REACH_L).
##   dagger    A: a straight stab at the chest; B: a stab driven up from low at the right hip;
##             C: an overhand stab brought down from above the shoulder, stepping in.
##   sickle    A: from behind the head, as the Egyptians drew the khopesh, cut down in front;
##             B: the hook: reached out to the left and drawn back hard to the right;
##             C: a low sweep at the legs from right to left, crouching and stepping in.
##   axe       A: chopped down across from over the right shoulder; B: a level chop from the
##             right at the waist; C: raised high behind the head and brought straight down.
##   bludgeon  (club and mace) A: lifted straight up and slammed down on both feet; B: swung up
##             from the left hip to high on the right; C: a wide swing at head height, turning
##             the whole body round and stepping in.
##   spear     A: thrust from the hip; B: raised over the shoulder and thrust down; C: a long
##             lunge, all the reach of the arm and the step.
##   staff     one blow: held near its top, the right hand above the left; drawn back over the
##             right shoulder, a moment's pause to gather, then the butt driven forward and down.
##             "air" is the same off the ground.
static func _style_keys(style: String) -> Dictionary:
	var out := {}
	match style:
		"dagger":
			var ready := _with(GUARD_L, {"hold_r": Vector3(-0.16, 1.12, 0.3), "blade_r": Vector3(0.0, 0.2, 0.98)})
			var stab := _with(BALANCE_L, {"hips": 0.2, "twist": 0.25, "lean": 0.2, "pitch": 0.04, "shift": Vector3(0.0, 0.0, 0.12), "sink": 0.06,
				"step": Vector3(0.0, 0.0, 0.15), "reach_r": 0.3, "hold_r": Vector3(-0.06, 1.25, 0.6), "blade_r": Vector3(0.04, 0.0, 1.0)})
			var back := _with(GUARD_L, {"hips": 0.05, "twist": 0.05, "lean": 0.05, "shift": Vector3(0.0, 0.0, 0.04), "sink": 0.02,
				"hold_r": Vector3(-0.14, 1.12, 0.35), "blade_r": Vector3(0.0, 0.15, 0.99)})
			out["a"] = [
				[0.0, ready],
				[0.18, _with(GUARD_L, {"hips": -0.2, "twist": -0.3, "lean": -0.05, "shift": Vector3(-0.02, 0.0, -0.04), "sink": 0.03, "shrug_r": 0.05,
					"hold_r": Vector3(-0.26, 1.1, 0.0), "blade_r": Vector3(0.05, 0.1, 0.99)})],
				[0.32, stab],
				[0.42, _with(stab, {"hold_r": Vector3(-0.06, 1.25, 0.63)})],
				[0.6, back],
			]
			var rise := _with(BALANCE_L, {"hips": 0.25, "twist": 0.3, "lean": 0.18, "sink": 0.04, "shift": Vector3(0.0, 0.0, 0.1), "step": Vector3(0.0, 0.0, 0.12),
				"reach_r": 0.25, "hold_r": Vector3(-0.04, 1.18, 0.55), "blade_r": Vector3(0.0, 0.62, 0.78)})
			out["b"] = [
				[0.0, back],
				[0.16, _with(GUARD_L, {"hips": -0.25, "twist": -0.35, "lean": 0.05, "sink": 0.08, "shift": Vector3(-0.02, 0.0, -0.02),
					"hold_r": Vector3(-0.28, 0.95, 0.08), "blade_r": Vector3(0.05, 0.55, 0.83)})],
				[0.3, rise],
				[0.4, _with(rise, {"hold_r": Vector3(-0.02, 1.3, 0.55), "blade_r": Vector3(0.0, 0.8, 0.6)})],
				[0.6, back],
			]
			var down := _with(BALANCE_L, {"hips": 0.25, "twist": 0.2, "lean": 0.32, "pitch": 0.07, "sink": 0.12, "shift": Vector3(0.02, 0.0, 0.18),
				"step": Vector3(0.0, 0.0, 0.25), "reach_r": 0.3, "hold_r": Vector3(-0.06, 1.22, 0.5), "blade_r": Vector3(0.0, -0.6, 0.8)})
			var spent := _with(down, {"hold_r": Vector3(-0.03, 1.05, 0.48), "blade_r": Vector3(0.0, -0.85, 0.5)})
			out["c"] = [
				[0.0, back],
				[0.22, _with(RAISED_L, {"hips": -0.2, "twist": -0.25, "lean": -0.12, "shrug_r": 0.25, "shift": Vector3(-0.02, 0.0, -0.05),
					"hold_r": Vector3(-0.24, 1.7, -0.02), "blade_r": Vector3(0.0, 0.75, 0.65)})],
				[0.38, down],
				[0.5, spent],
				[0.62, spent],
				[0.74, _with(spent, {"hips": 0.1, "twist": 0.1, "lean": 0.12, "pitch": 0.02, "sink": 0.05, "shift": Vector3(0.0, 0.0, 0.06), "step": Vector3(0.0, 0.05, 0.1)})],
				[0.85, _with(back, {"step": Vector3.ZERO})],
			]
		"sickle":
			var ready := _with(GUARD_L, {"hold_r": Vector3(-0.18, 1.15, 0.3), "blade_r": Vector3(0.0, 0.6, 0.8)})
			var cut := _with(BALANCE_L, {"hips": 0.3, "twist": 0.2, "lean": 0.3, "pitch": 0.06, "sink": 0.08, "shift": Vector3(0.02, 0.0, 0.15), "reach_r": 0.3,
				"hold_r": Vector3(-0.1, 1.3, 0.5), "blade_r": Vector3(0.05, -0.45, 0.9)})
			var after_a := _with(cut, {"hips": 0.38, "twist": 0.28, "lean": 0.38, "pitch": 0.1, "sink": 0.11, "shift": Vector3(0.03, 0.0, 0.18),
				"hold_r": Vector3(-0.05, 1.02, 0.42), "blade_r": Vector3(0.1, -0.85, 0.5)})
			out["a"] = [
				[0.0, ready],
				[0.32, _with(RAISED_L, {"hips": -0.2, "twist": -0.25, "lean": -0.15, "shrug_r": 0.3, "shift": Vector3(-0.02, 0.0, -0.06),
					"hold_r": Vector3(-0.14, 1.74, -0.08), "blade_r": Vector3(0.1, 0.15, -0.98)})],
				[0.43, _with(GUARD_L, {"lean": 0.05, "shrug_r": 0.2, "hold_r": Vector3(-0.12, 1.7, 0.25), "blade_r": Vector3(0.05, 0.95, 0.3)})],
				[0.5, cut],
				[0.65, after_a],
			]
			var pulled := _with(BALANCE_L, {"hips": -0.25, "twist": -0.3, "lean": 0.08, "shift": Vector3(-0.03, 0.0, 0.04), "sink": 0.07,
				"hold_r": Vector3(-0.3, 1.2, 0.28), "blade_r": Vector3(0.7, 0.05, 0.71)})
			var after_b := _with(pulled, {"hips": -0.35, "twist": -0.42, "lean": 0.05, "sink": 0.06,
				"hold_r": Vector3(-0.38, 1.12, 0.1), "blade_r": Vector3(0.25, -0.2, 0.95)})
			out["b"] = [
				[0.0, after_a],
				[0.28, _with(REACH_L, {"hips": 0.25, "twist": 0.35, "lean": 0.15, "shift": Vector3(0.02, 0.0, 0.08), "sink": 0.05, "reach_r": 0.35,
					"hold_r": Vector3(0.14, 1.3, 0.55), "blade_r": Vector3(0.9, 0.1, 0.42)})],
				[0.45, pulled],
				[0.58, after_b],
			]
			var sweep := _with(BALANCE_L, {"hips": 0.35, "twist": 0.3, "lean": 0.38, "pitch": 0.1, "sink": 0.22, "shift": Vector3(0.02, 0.0, 0.2),
				"step": Vector3(0.0, 0.0, 0.3), "reach_r": 0.3, "hold_r": Vector3(0.0, 0.88, 0.5), "blade_r": Vector3(0.45, -0.55, 0.7)})
			var spent := _with(sweep, {"hips": 0.5, "twist": 0.55, "sink": 0.2, "shift": Vector3(0.03, 0.0, 0.2),
				"hold_r": Vector3(0.25, 0.92, 0.35), "blade_r": Vector3(0.85, -0.4, 0.34)})
			out["c"] = [
				[0.0, after_b],
				[0.34, _with(OUT_L, {"hips": -0.45, "twist": -0.55, "sink": 0.08, "shift": Vector3(-0.03, 0.0, -0.03),
					"hold_r": Vector3(-0.45, 1.05, -0.12), "blade_r": Vector3(-0.6, -0.3, -0.74)})],
				[0.47, _with(OUT_L, {"hips": -0.1, "twist": -0.1, "lean": 0.3, "sink": 0.18, "shift": Vector3(0.0, 0.0, 0.15), "step": Vector3(0.0, 0.0, 0.25),
					"hold_r": Vector3(-0.3, 0.92, 0.42), "blade_r": Vector3(-0.3, -0.55, 0.78)})],
				[0.55, sweep],
				[0.7, spent],
				[0.86, spent],
				[1.0, _with(spent, {"hips": 0.3, "twist": 0.35, "lean": 0.2, "pitch": 0.05, "sink": 0.1, "shift": Vector3(0.02, 0.0, 0.1), "step": Vector3(0.0, 0.05, 0.12)})],
				[1.15, _with(ready, {"hips": 0.1, "twist": 0.15, "lean": 0.08, "sink": 0.04, "shift": Vector3(0.0, 0.0, 0.03)})],
			]
		"axe":
			var ready := _with(GUARD_L, {"hold_r": Vector3(-0.2, 1.12, 0.3), "blade_r": Vector3(0.0, 0.7, 0.7)})
			var chop := _with(BALANCE_L, {"hips": 0.3, "twist": 0.2, "lean": 0.32, "pitch": 0.07, "sink": 0.1, "shift": Vector3(0.02, 0.0, 0.16), "reach_r": 0.3,
				"hold_r": Vector3(-0.03, 1.25, 0.5), "blade_r": Vector3(0.35, -0.45, 0.82)})
			var after_a := _with(chop, {"hips": 0.4, "twist": 0.32, "lean": 0.38, "pitch": 0.1, "sink": 0.12, "shift": Vector3(0.03, 0.0, 0.18),
				"hold_r": Vector3(0.1, 1.0, 0.4), "blade_r": Vector3(0.55, -0.75, 0.36)})
			out["a"] = [
				[0.0, ready],
				[0.36, _with(RAISED_L, {"hips": -0.3, "twist": -0.4, "lean": -0.12, "shrug_r": 0.25, "shift": Vector3(-0.02, 0.0, -0.06), "sink": 0.02,
					"hold_r": Vector3(-0.32, 1.62, -0.1), "blade_r": Vector3(-0.2, 0.3, -0.93)})],
				[0.47, _with(GUARD_L, {"hips": -0.05, "twist": -0.05, "lean": 0.05, "shrug_r": 0.15, "shift": Vector3(0.0, 0.0, 0.03), "sink": 0.04,
					"hold_r": Vector3(-0.24, 1.62, 0.25), "blade_r": Vector3(0.15, 0.92, 0.36)})],
				[0.55, chop],
				[0.72, after_a],
			]
			var level := _with(BALANCE_L, {"hips": 0.2, "twist": 0.15, "lean": 0.15, "sink": 0.08, "shift": Vector3(0.02, 0.0, 0.08), "reach_r": 0.3,
				"hold_r": Vector3(-0.05, 1.13, 0.55), "blade_r": Vector3(0.4, 0.0, 0.92)})
			var after_b := _with(level, {"hips": 0.45, "twist": 0.55, "lean": 0.12, "sink": 0.07, "shift": Vector3(0.03, 0.0, 0.06), "reach_r": 0.35,
				"hold_r": Vector3(0.25, 1.13, 0.35), "blade_r": Vector3(0.95, 0.0, 0.3)})
			out["b"] = [
				[0.0, after_a],
				[0.32, _with(OUT_L, {"hips": -0.45, "twist": -0.6, "lean": 0.04, "shift": Vector3(-0.04, 0.0, 0.0), "sink": 0.05,
					"hold_r": Vector3(-0.48, 1.18, -0.04), "blade_r": Vector3(-0.75, 0.12, -0.65)})],
				[0.42, _with(OUT_L, {"hips": -0.15, "twist": -0.2, "lean": 0.1, "sink": 0.07, "shift": Vector3(0.0, 0.0, 0.04),
					"hold_r": Vector3(-0.36, 1.15, 0.4), "blade_r": Vector3(-0.6, 0.05, 0.8)})],
				[0.5, level],
				[0.64, after_b],
			]
			var fall := _with(BALANCE_L, {"hips": 0.25, "twist": 0.1, "lean": 0.42, "pitch": 0.12, "sink": 0.18, "shift": Vector3(0.02, 0.0, 0.22),
				"step": Vector3(0.0, 0.0, 0.32), "reach_r": 0.3, "hold_r": Vector3(-0.08, 1.12, 0.55), "blade_r": Vector3(0.05, -0.6, 0.8)})
			var spent := _with(fall, {"lean": 0.46, "hold_r": Vector3(-0.05, 0.92, 0.5), "blade_r": Vector3(0.05, -0.9, 0.42)})
			out["c"] = [
				[0.0, after_b],
				[0.42, _with(RAISED_L, {"hips": -0.25, "twist": -0.15, "lean": -0.25, "pitch": -0.05, "shrug_r": 0.35, "shift": Vector3(0.0, 0.0, -0.08),
					"hold_r": Vector3(-0.16, 1.82, -0.15), "blade_r": Vector3(0.0, 0.15, -0.99)})],
				[0.54, _with(GUARD_L, {"hips": -0.05, "lean": 0.0, "shrug_r": 0.25, "sink": 0.04, "shift": Vector3(0.0, 0.0, 0.04), "step": Vector3(0.0, 0.08, 0.15),
					"hold_r": Vector3(-0.13, 1.78, 0.28), "blade_r": Vector3(0.0, 0.92, 0.4)})],
				[0.62, fall],
				[0.8, spent],
				[0.98, spent],
				[1.14, _with(spent, {"hips": 0.12, "twist": 0.05, "lean": 0.25, "pitch": 0.06, "sink": 0.1, "shift": Vector3(0.0, 0.0, 0.1), "step": Vector3(0.0, 0.05, 0.14)})],
				[1.3, _with(ready, {"lean": 0.08, "sink": 0.04, "shift": Vector3(0.0, 0.0, 0.03)})],
			]
		"bludgeon":
			var ready := _with(GUARD_L, {"hold_r": Vector3(-0.2, 1.15, 0.3), "blade_r": Vector3(0.0, 0.8, 0.6)})
			var slam := _with(BALANCE_L, {"hips": 0.15, "twist": 0.08, "lean": 0.45, "pitch": 0.12, "sink": 0.2, "shift": Vector3(0.0, 0.0, 0.12), "reach_r": 0.25,
				"hold_r": Vector3(-0.1, 1.08, 0.5), "blade_r": Vector3(0.0, -0.75, 0.66)})
			var after_a := _with(slam, {"lean": 0.48, "pitch": 0.13, "sink": 0.21, "shift": Vector3(0.0, 0.0, 0.13),
				"hold_r": Vector3(-0.1, 0.95, 0.48), "blade_r": Vector3(0.0, -0.9, 0.42)})
			out["a"] = [
				[0.0, ready],
				[0.36, _with(RAISED_L, {"hips": -0.15, "twist": -0.1, "lean": -0.2, "pitch": -0.05, "shrug_r": 0.35, "shift": Vector3(0.0, 0.0, -0.05),
					"hold_r": Vector3(-0.18, 1.86, 0.0), "blade_r": Vector3(0.0, 0.55, -0.84)})],
				[0.47, _with(GUARD_L, {"lean": 0.05, "shrug_r": 0.25, "sink": 0.05, "hold_r": Vector3(-0.16, 1.8, 0.3), "blade_r": Vector3(0.0, 0.95, 0.3)})],
				[0.55, slam],
				[0.72, after_a],
			]
			var upper := _with(BALANCE_L, {"hips": -0.25, "twist": -0.3, "lean": -0.05, "sink": 0.03, "shift": Vector3(0.0, 0.0, 0.05), "reach_r": 0.15,
				"hold_r": Vector3(-0.15, 1.45, 0.45), "blade_r": Vector3(-0.35, 0.75, 0.56)})
			var after_b := _with(upper, {"hips": -0.4, "twist": -0.5, "lean": -0.08, "sink": 0.02, "shrug_r": 0.15,
				"hold_r": Vector3(-0.35, 1.6, 0.15), "blade_r": Vector3(-0.6, 0.75, -0.27)})
			out["b"] = [
				[0.0, after_a],
				[0.3, _with(OUT_L, {"hips": 0.35, "twist": 0.45, "lean": 0.15, "sink": 0.1,
					"hold_r": Vector3(0.12, 0.98, 0.18), "blade_r": Vector3(0.6, -0.55, -0.58)})],
				[0.48, upper],
				[0.6, after_b],
			]
			var swing := _with(BALANCE_L, {"hips": 0.4, "twist": 0.3, "lean": 0.2, "sink": 0.1, "shift": Vector3(0.02, 0.0, 0.16), "step": Vector3(0.0, 0.0, 0.28),
				"reach_r": 0.3, "hold_r": Vector3(0.0, 1.38, 0.55), "blade_r": Vector3(0.45, 0.05, 0.89)})
			var spent := _with(swing, {"hips": 0.6, "twist": 0.7, "lean": 0.18, "reach_r": 0.35,
				"hold_r": Vector3(0.3, 1.3, 0.3), "blade_r": Vector3(0.95, -0.1, 0.28)})
			out["c"] = [
				[0.0, after_b],
				[0.42, _with(OUT_L, {"hips": -0.5, "twist": -0.65, "shift": Vector3(-0.04, 0.0, -0.02), "sink": 0.04,
					"hold_r": Vector3(-0.5, 1.45, -0.15), "blade_r": Vector3(-0.6, 0.3, -0.74)})],
				[0.54, _with(OUT_L, {"hips": -0.15, "twist": -0.2, "lean": 0.1, "sink": 0.07, "shift": Vector3(0.0, 0.0, 0.06), "step": Vector3(0.0, 0.06, 0.18),
					"hold_r": Vector3(-0.36, 1.42, 0.42), "blade_r": Vector3(-0.5, 0.15, 0.85)})],
				[0.62, swing],
				[0.78, spent],
				[0.98, spent],
				[1.14, _with(spent, {"hips": 0.3, "twist": 0.35, "lean": 0.12, "sink": 0.07, "shift": Vector3(0.01, 0.0, 0.08), "step": Vector3(0.0, 0.05, 0.12)})],
				[1.3, _with(ready, {"hips": 0.1, "twist": 0.1, "lean": 0.05, "sink": 0.03, "shift": Vector3(0.0, 0.0, 0.03)})],
			]
		"spear":
			var ready := _with(GUARD_L, {"hold_r": Vector3(-0.22, 1.05, 0.15), "blade_r": Vector3(0.04, 0.12, 0.99)})
			var low := _with(GUARD_L, {"hips": 0.25, "twist": 0.25, "lean": 0.2, "pitch": 0.04, "sink": 0.07, "shift": Vector3(0.0, 0.0, 0.14),
				"step": Vector3(0.0, 0.0, 0.2), "reach_r": 0.3, "hold_r": Vector3(-0.2, 1.12, 0.5), "blade_r": Vector3(0.03, 0.04, 1.0)})
			var back := _with(GUARD_L, {"hips": 0.05, "twist": 0.05, "lean": 0.05, "sink": 0.02, "shift": Vector3(0.0, 0.0, 0.04),
				"hold_r": Vector3(-0.2, 1.05, 0.2), "blade_r": Vector3(0.04, 0.1, 0.99)})
			out["a"] = [
				[0.0, ready],
				[0.28, _with(GUARD_L, {"hips": -0.25, "twist": -0.3, "lean": -0.05, "sink": 0.03, "shift": Vector3(-0.02, 0.0, -0.05),
					"hold_r": Vector3(-0.27, 1.0, -0.1), "blade_r": Vector3(0.04, 0.12, 0.99)})],
				[0.45, low],
				[0.58, _with(low, {"hold_r": Vector3(-0.19, 1.12, 0.54)})],
				[0.8, back],
			]
			var high := _with(GUARD_L, {"hips": 0.2, "twist": 0.25, "lean": 0.2, "sink": 0.05, "shift": Vector3(0.0, 0.0, 0.12), "step": Vector3(0.0, 0.0, 0.15),
				"shrug_r": 0.15, "reach_r": 0.3, "hold_r": Vector3(-0.24, 1.5, 0.42), "blade_r": Vector3(0.04, -0.35, 0.94)})
			out["b"] = [
				[0.0, back],
				[0.28, _with(GUARD_L, {"hips": -0.2, "twist": -0.25, "lean": -0.08, "shrug_r": 0.25, "shift": Vector3(-0.02, 0.0, -0.04),
					"hold_r": Vector3(-0.24, 1.66, -0.08), "blade_r": Vector3(0.04, -0.12, 0.99)})],
				[0.45, high],
				[0.58, _with(high, {"hold_r": Vector3(-0.23, 1.48, 0.46)})],
				[0.8, back],
			]
			var lunge := _with(GUARD_L, {"hips": 0.35, "twist": 0.35, "lean": 0.3, "pitch": 0.08, "sink": 0.15, "shift": Vector3(0.02, 0.0, 0.25),
				"step": Vector3(0.0, 0.0, 0.4), "reach_r": 0.4, "hold_r": Vector3(-0.18, 1.2, 0.62), "blade_r": Vector3(0.03, 0.0, 1.0)})
			var spent := _with(lunge, {"hold_r": Vector3(-0.17, 1.2, 0.65)})
			out["c"] = [
				[0.0, back],
				[0.36, _with(GUARD_L, {"hips": -0.4, "twist": -0.45, "lean": -0.1, "sink": 0.06, "shift": Vector3(-0.03, 0.0, -0.08),
					"hold_r": Vector3(-0.3, 1.04, -0.18), "blade_r": Vector3(0.04, 0.1, 0.99)})],
				[0.55, lunge],
				[0.72, spent],
				[0.88, spent],
				[1.02, _with(spent, {"hips": 0.15, "twist": 0.15, "lean": 0.15, "pitch": 0.03, "sink": 0.08, "shift": Vector3(0.0, 0.0, 0.1), "step": Vector3(0.0, 0.05, 0.15),
					"hold_r": Vector3(-0.2, 1.1, 0.4)})],
				[1.15, back],
			]
			# The shaft runs on behind the fist: it is kept out of the body (see _aimed).
			for blow in out:
				for k in out[blow]:
					k[1] = _with(k[1], {"shaft_back": SPEAR_BACK, "shaft_front": SPEAR_FRONT})
		"staff":
			# Held near its top (the fists STAFF_SLIDE further up the shaft than when it is carried),
			# the right hand above the left, a little more than a shoulder's width apart ("staff":
			# + toward the butt). "blade_r" is the way the top points: back over the right
			# shoulder, so the butt is ahead. Drawn back, a moment's pause to gather, and the butt
			# driven forward and down.
			var ready := {"hips": -0.15, "twist": -0.25, "hold_r": Vector3(-0.16, 1.28, 0.12), "blade_r": Vector3(-0.25, 0.6, -0.76), "staff": STAFF_GRIP}
			var drawn := {"hips": -0.25, "twist": -0.35, "lean": -0.12, "shrug_r": 0.2, "shift": Vector3(-0.02, 0.0, -0.07), "sink": 0.03,
				"hold_r": Vector3(-0.26, 1.56, -0.06), "blade_r": Vector3(-0.25, 0.4, -0.88), "staff": STAFF_GRIP}
			var gathered := _with(drawn, {"hips": -0.3, "twist": -0.42, "lean": -0.15, "shrug_r": 0.25, "shift": Vector3(-0.02, 0.0, -0.08), "sink": 0.05,
				"hold_r": Vector3(-0.27, 1.6, -0.1), "blade_r": Vector3(-0.26, 0.42, -0.87)})
			var driven := {"hips": 0.0, "twist": -0.35, "lean": 0.25, "pitch": 0.06, "sink": 0.1, "shift": Vector3(0.0, 0.0, 0.18),
				"step": Vector3(0.0, 0.0, 0.28), "reach_r": 0.2, "hold_r": Vector3(-0.22, 1.3, 0.26), "blade_r": Vector3(-0.35, 0.5, -0.79), "staff": STAFF_GRIP}
			var spent := _with(driven, {"twist": -0.38, "hold_r": Vector3(-0.2, 1.29, 0.24)})
			out["a"] = [
				[0.0, ready],
				[0.28, drawn],
				[0.42, gathered],
				[0.55, driven],
				[0.7, spent],
				[0.86, spent],
				[0.96, _with(spent, {"hips": 0.05, "twist": -0.05, "lean": 0.12, "pitch": 0.02, "sink": 0.05, "shift": Vector3(0.0, 0.0, 0.08), "step": Vector3(0.0, 0.05, 0.12)})],
				[1.05, _with(ready, {"lean": 0.04, "sink": 0.02, "shift": Vector3(0.0, 0.0, 0.03)})],
			]
			# Off the ground: the legs of the jump attack, the same blow with the arms.
			var air: Array = []
			var leap: Array = _blow_keys("r")["air"]
			var arms := [ready, drawn, gathered, driven, spent]
			var times := [0.0, 0.28, 0.42, 0.55, 0.7]
			for i in leap.size():
				var pose: Dictionary = (leap[i][1] as Dictionary).duplicate()
				for part in ["upperarm_r", "lowerarm_r", "upperarm_l", "lowerarm_l", "blade_r"]:
					pose.erase(part)
				pose["lean"] = minf(float(pose.get("lean", 0.0)), 0.22)
				pose["pitch"] = minf(float(pose.get("pitch", 0.0)), 0.1)
				var hands: Dictionary = arms[mini(i, arms.size() - 1)]
				for key in ["hold_r", "blade_r", "staff", "shrug_r", "twist", "hips"]:
					if hands.has(key):
						pose[key] = hands[key]
				air.append([times[mini(i, times.size() - 1)], pose])
			out["air"] = air
			# The stomp: the staff lifted upright in both hands before the face, held there a
			# moment, then its butt driven straight down into the ground before the feet, the
			# knees giving with it.
			var upright := {"hips": 0.0, "twist": 0.0, "lean": -0.06, "shrug_r": 0.15, "sink": 0.0,
				"hold_r": Vector3(-0.08, 1.72, 0.3), "blade_r": Vector3(0.0, 1.0, 0.04), "staff": STAFF_GRIP}
			var lifted := _with(upright, {"lean": -0.1, "shrug_r": 0.3, "hold_r": Vector3(-0.08, 1.86, 0.3)})
			var struck := {"hips": 0.0, "twist": 0.0, "lean": 0.22, "pitch": 0.05, "sink": 0.2, "shift": Vector3(0.0, 0.0, 0.06),
				"hold_r": Vector3(-0.08, 1.36, 0.36), "blade_r": Vector3(0.0, 1.0, 0.06), "staff": STAFF_GRIP}
			out["b"] = [
				[0.0, ready],
				[0.26, upright],
				[0.42, lifted],
				[0.56, lifted],
				[0.66, struck],
				[0.84, _with(struck, {"sink": 0.16})],
				[1.04, _with(upright, {"hold_r": Vector3(-0.1, 1.5, 0.24), "lean": 0.04})],
				[1.2, ready],
			]
	var table: Array = STYLES[style]
	for blow in out:
		var keys: Array = out[blow]
		var length: float = float(table[mini(maxi(0, ["a", "b", "c"].find(blow)), table.size() - 1)]["length"])
		if blow == "air":
			length = float(BLOWS[0]["length"])
		if float(keys[keys.size() - 1][0]) < length - 0.001:
			keys.append([length, keys[keys.size() - 1][1]])
		# Bones turn evenly between poses on their own, which would let a long shaft swing
		# through the body or slip out of the second hand: poses every so often keep it right.
		if style == "staff":
			out[blow] = _dense(keys, DENSE * 0.5)
		elif style == "spear":
			out[blow] = _dense(keys, DENSE * 1.5)
	return out


## More poses between the given ones, each a straight blend of its neighbours (directions blended
## and made unit length again), so that whatever is solved per pose is solved often.
static func _dense(keys: Array, step: float) -> Array:
	var out: Array = []
	for i in keys.size() - 1:
		var t0 := float(keys[i][0])
		var t1 := float(keys[i + 1][0])
		var p0: Dictionary = keys[i][1]
		var p1: Dictionary = keys[i + 1][1]
		out.append(keys[i])
		var n := int(floor((t1 - t0) / step - 0.001))
		for j in range(1, n + 1):
			var f := float(j) / (n + 1)
			var pose := {}
			for key in p0.keys() + p1.keys():
				if pose.has(key):
					continue
				var unit := _is_direction(str(key))
				var a: Variant = p0.get(key)
				var b: Variant = p1.get(key)
				if a == null:
					a = b if unit else _zero_like(b)
				if b == null:
					b = a if unit else _zero_like(a)
				if a is Vector3:
					var v: Vector3 = (a as Vector3).lerp(b, f)
					pose[key] = v.normalized() if unit else v
				else:
					pose[key] = lerpf(float(a), float(b), f)
			out.append([t0 + (t1 - t0) * f, pose])
	out.append(keys[keys.size() - 1])
	return out


## Puts the left fist on the shaft of what the right fist holds, with both thumbs toward the
## striking end: `spacing` metres from the right fist toward the butt if the arm reaches that far,
## otherwise the nearest place along the shaft it can reach (hands slide on a staff). The arm
## reaches there (_reach), then the forearm and wrist turn the fist along the shaft (_grip); twice,
## because turning the fist moves its hollow a little.
static func _two_hands(sk: Skeleton3D, local: Dictionary, pelvis_at: Vector3, fist_r: Transform3D, fist_l: Transform3D, spacing: float) -> float:
	var right := _model_pose(sk, local, pelvis_at, sk.find_bone("hand_r"))
	var hold: Vector3 = right * fist_r.origin
	var along: Vector3 = (right.basis * fist_r.basis.y).normalized()
	var shoulder := _model_pose(sk, local, pelvis_at, sk.find_bone("upperarm_l")).origin
	var arm := (sk.get_bone_rest(sk.find_bone("lowerarm_l")).origin.length() + sk.get_bone_rest(sk.find_bone("hand_l")).origin.length()) * 0.92
	# Where the arm cannot reach, the hand slides along the shaft toward the right fist (but stays
	# a hand's breadth and more from it), or a little the other way.
	var want := hold - along * spacing
	var best := 1e9
	var gap := 0.16
	while gap <= absf(spacing) + 0.101:
		var p := hold - along * signf(spacing) * gap
		var score := maxf(0.0, shoulder.distance_to(p) - arm) * 10.0 + absf(gap - absf(spacing)) * 0.5
		if score < best:
			best = score
			want = p
		gap += 0.02
	# Turning the fist moves its hollow, so reach and turn are repeated until they agree.
	var wrist0: Basis = local[sk.find_bone("hand_l")]
	for i in 6:
		local[sk.find_bone("hand_l")] = wrist0
		var left := _model_pose(sk, local, pelvis_at, sk.find_bone("hand_l"))
		_reach(sk, local, pelvis_at, "l", want - left.basis * fist_l.origin, Vector3(0.7, -0.5, 0.1))
		_grip(sk, local, "l", fist_l.basis.y, along)
	return maxf(0.0, shoulder.distance_to(want) - arm)


## The body as balls and rods for keeping a staff out of it: [from, to, radius] each, in whatever
## space `where` gives the bones' places in (it is called with a bone's name).
static func body_parts(where: Callable) -> Array:
	var parts: Array = []
	var side: Vector3 = ((where.call("upperarm_l") as Vector3) - (where.call("upperarm_r") as Vector3)).normalized()
	for bone in ["pelvis", "spine_01", "spine_02", "spine_03"]:
		var c: Vector3 = where.call(bone)
		parts.append([c - side * 0.07, c + side * 0.07, 0.115])
	var head_at: Vector3 = where.call("Head")
	parts.append([head_at + Vector3(0, 0.06, 0), head_at + Vector3(0, 0.14, 0), 0.1])
	parts.append([where.call("neck_01"), head_at, 0.06])
	for s in ["l", "r"]:
		parts.append([where.call("clavicle_" + s), where.call("upperarm_" + s), 0.055])
		parts.append([where.call("thigh_" + s), where.call("calf_" + s), 0.075])
		parts.append([where.call("calf_" + s), where.call("foot_" + s), 0.055])
	return parts


## How deep the shaft from `a` to `b` is inside the body (see body_parts), and which way out is
## shortest: [depth in metres (0 or less = clear), direction].
static func shaft_depth(parts: Array, a: Vector3, b: Vector3) -> Array:
	var deepest := -1.0
	var out := Vector3.ZERO
	for p in parts:
		var pts := Geometry3D.get_closest_points_between_segments(a, b, p[0], p[1])
		var away: Vector3 = pts[0] - pts[1]
		var into: float = float(p[2]) + STAFF_RADIUS - away.length()
		if into > deepest:
			deepest = into
			# Right through the middle there is no shortest way out: go forward.
			out = away.normalized() if away.length() > 0.005 else Vector3(0, 0, 1)
	return [deepest, out]


## Moves the right fist, and the staff with it, until the whole shaft is outside the body: at
## each turn it is shifted the shortest way out of whatever it is deepest in. `at` and `along`
## are what _hold was given; returns where the fist was moved to.
static func _clear_shaft(sk: Skeleton3D, local: Dictionary, pelvis_at: Vector3, fist: Transform3D, at: Vector3, along: Vector3, side: String = "r", back: float = STAFF_BACK, front: float = STAFF_FRONT) -> Vector3:
	for i in 10:
		var hit := _shaft_hit(sk, local, pelvis_at, fist, side, back, front)
		if float(hit[0]) < 0.004:
			break
		at += (hit[1] as Vector3) * (float(hit[0]) + 0.012)
		_hold(sk, local, pelvis_at, fist, at, along, side)
	return at


## How deep the staff in the right fist is inside the body in this pose, and the way out
## (see shaft_depth).
static func _shaft_hit(sk: Skeleton3D, local: Dictionary, pelvis_at: Vector3, fist: Transform3D, side: String = "r", back: float = STAFF_BACK, front: float = STAFF_FRONT) -> Array:
	var where := func(bone: String) -> Vector3: return _model_pose(sk, local, pelvis_at, sk.find_bone(bone)).origin
	var hand := _model_pose(sk, local, pelvis_at, sk.find_bone("hand_" + side))
	var hollow: Vector3 = hand * fist.origin
	var runs: Vector3 = (hand.basis * fist.basis.y).normalized()
	return shaft_depth(body_parts(where), hollow - runs * back, hollow + runs * front)


static func _shaft_in(sk: Skeleton3D, local: Dictionary, pelvis_at: Vector3, fist: Transform3D) -> float:
	return float(_shaft_hit(sk, local, pelvis_at, fist)[0])


## Puts the right fist's hollow at `at` (model space) with what it holds pointing `along`: the arm
## reaches, the wrist turns, and again, since turning the fist moves its hollow.
static func _hold(sk: Skeleton3D, local: Dictionary, pelvis_at: Vector3, fist: Transform3D, at: Vector3, along: Vector3, side: String = "r", pole: Vector3 = Vector3.ZERO) -> void:
	if pole == Vector3.ZERO:
		pole = Vector3(-0.7, -0.5, -0.1) if side == "r" else Vector3(0.7, -0.5, -0.1)
	# Each pass bends the wrist afresh from where it began, so the bends do not pile up.
	var wrist0: Basis = local[sk.find_bone("hand_" + side)]
	for i in 6:
		local[sk.find_bone("hand_" + side)] = wrist0
		var hand := _model_pose(sk, local, pelvis_at, sk.find_bone("hand_" + side))
		_reach(sk, local, pelvis_at, side, at - hand.basis * fist.origin, pole)
		_grip(sk, local, side, fist.basis.y, along)


## Bends an arm so that its wrist comes to `target` (model space), the elbow bending toward
## `pole`. Out of reach, the arm points at the target at full stretch.
static func _reach(sk: Skeleton3D, local: Dictionary, pelvis_at: Vector3, side: String, target: Vector3, pole: Vector3) -> void:
	var upper := sk.find_bone("upperarm_" + side)
	var lower := sk.find_bone("lowerarm_" + side)
	var hand := sk.find_bone("hand_" + side)
	var shoulder := _model_pose(sk, local, pelvis_at, upper).origin
	var l1 := sk.get_bone_rest(lower).origin.length()
	var l2 := sk.get_bone_rest(hand).origin.length()
	var to := target - shoulder
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dir := to.normalized()
	var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var out_by := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < 0.01:
		bend = dir.cross(Vector3.UP)
	var elbow := shoulder + dir * along + bend.normalized() * out_by
	_bend_arm(sk, local, side, elbow - shoulder, shoulder + dir * d - elbow)


## Each elbow's hinge, learned from the base pose of the clip being made (see _aimed): "axis", the
## line the forearm bends about, in the upper arm's own space (turning about it + bends the arm);
## "straight", the forearm's own orientation with the elbow straight and the forearm unrolled.
static var _elbows := {}


static func _learn_elbows(sk: Skeleton3D, base: Animation) -> void:
	for side in ["r", "l"]:
		var lower := sk.find_bone("lowerarm_" + side)
		var hand := sk.find_bone("hand_" + side)
		var u := sk.get_bone_rest(lower).origin.normalized()
		var lb := _anim_basis(base, sk, lower, 0.0)
		var f := (lb * sk.get_bone_rest(hand).origin).normalized()
		var axis := u.cross(f)
		if axis.length() < 0.1:
			_elbows.erase(side)
			continue
		_elbows[side] = {"axis": axis.normalized(), "straight": Basis(axis.normalized(), -u.angle_to(f)) * lb}


## Lays an arm along two directions (model space): the upper arm along `upper_dir`, the forearm
## along `fore_dir`. The elbow only bends as an elbow does, about its hinge and inward: the upper
## arm turns about its own length so that the hinge lies across the bend, and the forearm comes
## round the hinge. Its roll is then left to _grip.
static func _bend_arm(sk: Skeleton3D, local: Dictionary, side: String, upper_dir: Vector3, fore_dir: Vector3) -> void:
	var upper := sk.find_bone("upperarm_" + side)
	var lower := sk.find_bone("lowerarm_" + side)
	var hand := sk.find_bone("hand_" + side)
	_point_bone(sk, local, upper, lower, upper_dir)
	if not _elbows.has(side):
		_point_bone(sk, local, lower, hand, fore_dir)
		return
	var elbow: Dictionary = _elbows[side]
	var u := upper_dir.normalized()
	var f := fore_dir.normalized()
	var across := u.cross(f)
	if across.length() > 0.12:
		var parent := _model_basis(sk, local, sk.get_bone_parent(upper))
		var mu: Basis = parent * (local[upper] as Basis)
		var hinge: Vector3 = mu * (elbow["axis"] as Vector3)
		hinge = (hinge - u * hinge.dot(u)).normalized()
		var roll := hinge.signed_angle_to(across.normalized(), u)
		local[upper] = parent.inverse() * Basis(u, roll) * mu
	local[lower] = Basis(elbow["axis"] as Vector3, minf(u.angle_to(f), 2.5)) * (elbow["straight"] as Basis)


## Turns a bone the short way so that it runs toward `child` along `want` (model space).
static func _point_bone(sk: Skeleton3D, local: Dictionary, bone: int, child: int, want: Vector3) -> void:
	var parent := _model_basis(sk, local, sk.get_bone_parent(bone))
	var along := sk.get_bone_rest(child).origin.normalized()
	var from := ((local[bone] as Basis) * along).normalized()
	var to := (parent.inverse() * want).normalized()
	local[bone] = Basis(Quaternion(from, to)) * (local[bone] as Basis)


## Whether a pose value is a direction a bone or a held weapon points (blended as a direction).
static func _is_direction(key: String) -> bool:
	return key.contains("arm") or key.begins_with("blade") or key.begins_with("thigh") or key.begins_with("calf")


static func _zero_like(v: Variant) -> Variant:
	return Vector3.ZERO if v is Vector3 else 0.0


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
## The ways of fighting that have a battle stance; a bare fist takes the sword's.
const GUARD_STYLES := ["sword", "dagger", "sickle", "axe", "bludgeon", "spear", "staff"]


## The battle stance of a way of fighting: the weapon held ready as the first blow starts from
## (so a blow flows straight out of it), the knees a little bent and the chest forward over them.
## The staff is held in both hands, a good way apart, slanting down across the front of the body
## with its butt toward the ground ahead.
static func _guard_pose(style: String) -> Dictionary:
	var pose: Dictionary
	if style == "staff":
		pose = {"hips": -0.15, "twist": -0.2, "hold_r": Vector3(-0.2, 1.24, 0.16), "blade_r": Vector3(-0.25, 0.55, -0.8), "staff": STAFF_GRIP + 0.05}
	elif style == "sword":
		pose = (_blow_keys("r")["a"][0][1] as Dictionary).duplicate()
	else:
		pose = (_style_keys(style)["a"][0][1] as Dictionary).duplicate()
	pose["sink"] = float(pose.get("sink", 0.0)) + 0.07
	pose["lean"] = float(pose.get("lean", 0.0)) + 0.1
	return pose


## The stance as a loop: the body rises and settles a hand's breadth, slowly, as one ready to move.
static func _guard_clip(sk: Skeleton3D, idle: Animation, strike: Animation, style: String) -> Animation:
	var low := _guard_pose(style)
	var high := _with(low, {"sink": float(low["sink"]) - 0.025, "lean": float(low["lean"]) - 0.02})
	var keys: Array = [[0.0, low], [0.8, high], [1.6, low]]
	if style == "staff":
		keys = _dense(keys, DENSE * 0.5)
	var anim := _aimed(sk, idle, strike, keys, true)
	anim.loop_mode = Animation.LOOP_LINEAR
	return anim


## Keys of a move played backwards: the poses in reverse order, at mirrored times.
static func _backwards(keys: Array) -> Array:
	var length := float(keys[keys.size() - 1][0])
	var out: Array = []
	for i in range(keys.size() - 1, -1, -1):
		out.append([length - float(keys[i][0]), keys[i][1]])
	return out


static func _aimed(sk: Skeleton3D, base: Animation, fist: Animation, keys: Array, whole_body: bool = false) -> Animation:
	var names: Array = UPPER_BODY.duplicate()
	for side in ["l", "r"]:
		for finger in FINGERS:
			for joint in 3:
				names.append("%s_0%d_%s" % [finger, joint + 1, side])
	if whole_body:
		names.append_array(LOWER_BODY)
	_learn_elbows(sk, base)
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
	var fists := {"r": fist_frame(sk, fist, 0.46, "r"), "l": fist_frame(sk, base, 0.0, "l")}
	var grips := {"r": (fists["r"] as Transform3D).basis.y, "l": (fists["l"] as Transform3D).basis.y}
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
		# The shoulders: "shrug_*" lifts one, "reach_*" carries it forward round the chest.
		for side in ["r", "l"]:
			var shrug := float(aims.get("shrug_" + side, 0.0))
			var reach := float(aims.get("reach_" + side, 0.0))
			if shrug != 0.0 or reach != 0.0:
				var out_side := 1.0 if side == "r" else -1.0    # the right collarbone runs toward -X
				_turn(sk, local, sk.find_bone("clavicle_" + side), Basis(Vector3.UP, reach * out_side) * Basis(Vector3.BACK, -shrug * out_side))
		for side in ["r", "l"]:
			if aims.has("upperarm_" + side) and aims.has("lowerarm_" + side):
				_bend_arm(sk, local, side, aims["upperarm_" + side], aims["lowerarm_" + side])
		for n in ["upperarm_r", "lowerarm_r", "upperarm_l", "lowerarm_l"]:
			var arm_side: String = n.right(1)
			if not aims.has(n) or (aims.has("upperarm_" + arm_side) and aims.has("lowerarm_" + arm_side)):
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
			# A fist put in a place ("hold_r" / "hold_l"); a spear's shaft is then kept out of
			# the body ("shaft_back" / "shaft_front": how far it runs behind and ahead of the fist).
			if not aims.has("hold_" + side):
				continue
			var held: Vector3 = (aims.get("blade_" + side, Vector3.FORWARD) as Vector3).normalized()
			_hold(sk, local, pelvis_at, fists[side], aims["hold_" + side], held, side, aims.get("pole_" + side, Vector3.ZERO))
			if aims.has("shaft_back"):
				_clear_shaft(sk, local, pelvis_at, fists[side], aims["hold_" + side], held, side, float(aims["shaft_back"]), float(aims["shaft_front"]))
		if aims.has("hold_r"):
			var blade := (aims.get("blade_r", Vector3.FORWARD) as Vector3).normalized()
			if aims.has("staff"):
				# A staff is kept out of the body and within the left hand's reach: where that
				# hand cannot get to the shaft, the staff is brought toward its shoulder.
				var held_at := _clear_shaft(sk, local, pelvis_at, fists["r"], aims["hold_r"], blade)
				for attempt in 4:
					var short := _two_hands(sk, local, pelvis_at, fists["r"], fists["l"], float(aims["staff"]))
					if short < 0.01:
						break
					var before := {}
					for arm_bone in ["upperarm_r", "lowerarm_r", "hand_r"]:
						before[arm_bone] = local[sk.find_bone(arm_bone)]
					var shoulder_l := _model_pose(sk, local, pelvis_at, sk.find_bone("upperarm_l")).origin
					var nearer := held_at + (shoulder_l - held_at).normalized() * (short + 0.02)
					_hold(sk, local, pelvis_at, fists["r"], nearer, blade)
					nearer = _clear_shaft(sk, local, pelvis_at, fists["r"], nearer, blade)
					if _shaft_in(sk, local, pelvis_at, fists["r"]) > 0.004:
						# Nearer would be inside the body: better a hand that slides than that.
						for arm_bone in before:
							local[sk.find_bone(arm_bone)] = before[arm_bone]
						break
					held_at = nearer
		for side in ["r", "l"]:
			if aims.has("blade_" + side) and not aims.has("hold_" + side):
				_grip(sk, local, side, grips[side], (aims["blade_" + side] as Vector3).normalized())
		if aims.has("staff"):
			_two_hands(sk, local, pelvis_at, fists["r"], fists["l"], float(aims["staff"]))
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
	# In battle (see `battle`) the knees bend and the body bobs while standing still.
	_guard_clips.clear()
	var guard_legs := AnimationNodeBlend2.new()
	guard_legs.filter_enabled = true
	for bone in LOWER_BODY:
		guard_legs.set_filter_path(NodePath("Armature/Skeleton3D:%s" % bone), true)
	graph.add_node("guard_legs", guard_legs)
	_guard_clips.append(_clip("Guard_sword"))
	graph.add_node("Guard_low", _guard_clips[0])
	graph.connect_node("guard_legs", 0, "walk")
	graph.connect_node("guard_legs", 1, "Guard_low")
	# Off the ground the whole body goes over to the kit's jump pose.
	graph.add_node("air", AnimationNodeBlend2.new())
	graph.add_node("Jump", _clip("Jump"))
	graph.connect_node("air", 0, "guard_legs")
	graph.connect_node("air", 1, "Jump")
	var upper := _upper_paths()
	# The arms and chest of the battle stance, under the sling, the bow and every blow.
	var guard_arms := AnimationNodeBlend2.new()
	guard_arms.filter_enabled = true
	for path in upper:
		guard_arms.set_filter_path(path, true)
	graph.add_node("guard_hold", guard_arms)
	_guard_clips.append(_clip("Guard_sword"))
	graph.add_node("Guard_up", _guard_clips[1])
	_set_guard_clip()
	graph.connect_node("guard_hold", 0, "air")
	graph.connect_node("guard_hold", 1, "Guard_up")
	# Poses held for as long as a button is: the sling going round, the bow drawn.
	var below := "guard_hold"
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
		["blow_a_r", "Blow_A_R", 0.1, 0.2], ["blow_b_r", "Blow_B_R", 0.1, 0.18], ["blow_c_r", "Blow_C_R", 0.1, 0.2],
		["blow_a_l", "Blow_A_L", 0.1, 0.2], ["blow_b_l", "Blow_B_L", 0.1, 0.18], ["blow_c_l", "Blow_C_L", 0.1, 0.2],
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
			if source.begins_with("Blow_"):
				# Blow_<A|B|C>_<R|L>: given the staff's or the jump attack's clip when those are used.
				var hand := source.right(1).to_lower()
				if not _blow_nodes.has(hand):
					_blow_nodes[hand] = [null, null, null]
				(_blow_nodes[hand] as Array)[["A", "B", "C"].find(source.substr(5, 1))] = made
				if source.substr(5, 1) == "A":
					_first_blow[hand] = made
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
## Battle mode: set by whoever moves the figure. The figure takes its weapon's battle stance
## (Guard_<style>) while it is armed and has its weapon out, and leaves it smoothly.
var battle := false
var _guard := 0.0
var _guard_clips: Array = []   # the stance's legs and arms (AnimationNodeAnimation)
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
	# In battle the stance comes in over a quarter of a second; with the weapon put away, a bow in
	# hand, or nothing to hold, it goes.
	var guarding := battle and not sheathed and _swap_left < 0.0 and is_weapon(weapon_kind) and weapon_kind != "bow" and offhand_kind != "bow" and _speed < 7.0
	_guard = move_toward(_guard, 1.0 if guarding else 0.0, delta * 4.0)
	_tree.set("parameters/guard_hold/blend_amount", _guard)
	_tree.set("parameters/guard_legs/blend_amount", _guard * (1.0 - clampf((_speed - 0.3) / 1.5, 0.0, 1.0)))
	var k := 1.0 - exp(-28.0 * delta)
	if weapon != null and weapon.get_parent() == hand_r:
		var target := _strike if (_strike_left > 0.0 and _strike_side == "r") or _guard > 0.5 else _carry
		weapon.transform = weapon.transform.interpolate_with(target, k)
	if offhand != null and offhand.get_parent() == hand_l:
		var up := (_strike_left > 0.0 and _strike_side == "l") or (offhand_kind == "bow" and (drawing or _loose_t >= 0.0)) or (_guard > 0.5 and is_weapon(offhand_kind))
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


## Blow `step` of a combo (see STYLES: each weapon has its own), made with the right hand ("r") or the left ("l"), at
## `speed` (1 = normal). A hand with no weapon punches. A blow that follows another takes over.
## A figure standing still puts its hips and legs into the blow; one on the move keeps walking
## and strikes with the upper body only. Off the ground the first blow is a different one: the
## weapon comes down from overhead with the whole body folding behind it.
func attack(step: int, side: String = "r", speed: float = 1.0) -> void:
	if _tree == null or dead:
		return
	var held := weapon_kind if side == "r" else offhand_kind
	var armed := is_weapon(held)
	var list: Array = blows(held if armed else "none")
	var m: Dictionary
	if armed and step >= list.size() and style_of(held) == "sword":
		m = FOURTH_CUT
	else:
		step = clampi(step, 0, list.size() - 1)
		m = list[step]
	var shot := "%s_%s" % [m["shot"], side] if armed else "punch"
	var leap := armed and _in_air and step == 0
	var clip := blow_clip("Air" if leap else str(m.get("letter", str(m["shot"]).right(1).to_upper())), side, held)
	if armed:
		((_blow_nodes[side] as Array)[["blow_a", "blow_b", "blow_c"].find(str(m["shot"]))] as AnimationNodeAnimation).animation = clip
	if _shot != "" and _shot != shot:
		_tree.set("parameters/%s/request" % _shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_tree.set("parameters/%s_speed/scale" % shot, speed if armed else speed * PUNCH_HIT / float(m["hit"]))
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


## Changes the speed of the blow under way: 0 holds it where it is (a blow being charged). `left`
## is how much of the clip, at normal speed, is still to play.
func set_blow_speed(speed: float, left: float) -> void:
	if _tree == null or _shot == "":
		return
	_tree.set("parameters/%s_speed/scale" % _shot, speed)
	_strike_left = 1e9 if speed <= 0.0 else left / speed
	if _legs == "blow":
		_tree.set("parameters/stance_%d_speed/scale" % _stance, speed)
		_legs_left = 1e9 if speed <= 0.0 else left / speed


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
