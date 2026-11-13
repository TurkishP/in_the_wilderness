extends Node3D
## A person in the camp or the wilderness. What happens on interaction is decided by the world.
## Roles: villager, giver, merchant, smith, captain, witness, suspect, child, captive.
##
## Villagers are the ordinary people of the camp. Some walk about along the camp's paths,
## some sit by the fire, some kneel at their work. All of them will talk.

const HumanScript := preload("res://scripts/human.gd")
const FEMALE_WORDS := ["mother", "widow", "girl", "woman"]
const MALE_WORDS := ["father", "boy", "man in", "elder", "captain", "shepherd"]

var world
var npc_name := ""
var role := "villager"
var quest := {}
var data := {}
var interact_radius := 3.2
var follow_target: Node3D = null
var figure: Node3D
var settled := false        # sitting or kneeling in one place
var _mark: Label3D
var _camp                   # set for people on foot
var _at := -1               # the walking place this person is at or has just left
var _to := -1               # the one they are heading for
var _from := -1
var _rest := 0.0
var _pace := 1.3
var _dice := RandomNumberGenerator.new()


## opts: scale, solid, sash_color (Color), and any look key (sex, outfit, beard, ...) to force it.
func setup(n: String, r: String, color: Color, opts: Dictionary = {}) -> void:
	npc_name = n
	role = r
	var sc: float = float(opts.get("scale", 1.0))

	# Appearance: random but repeatable per stage, then shaped by the name and the role.
	var lower := n.to_lower()
	var sex := -1
	for w in MALE_WORDS:
		if lower.contains(w):
			sex = 0
	for w in FEMALE_WORDS:
		if lower.contains(w):
			sex = 1
	var look: Dictionary = HumanScript.random_look(world.look_rng, sex)
	if lower.contains("elder"):
		look.merge({"hair_color": 4, "beard": 1, "outfit": 1, "head": 1}, true)
	match role:
		"merchant":
			look.merge({"sex": 0, "outfit": 2, "beard": 1}, true)
		"smith":
			look.merge({"sex": 0, "outfit": 3, "head": 2}, true)
		"captain":
			look.merge({"sex": 0, "outfit": 3, "head": 2, "beard": 1}, true)
		"child":
			look.merge({"beard": 0, "head": 0, "outfit": 0}, true)
	for key in HumanScript.ORDER:
		if opts.has(key):
			look[key] = int(opts[key])
	if int(look["sex"]) == 1:
		look["beard"] = 0
	var fig_opts := {"cloth_color": color, "scale": sc}
	if opts.has("sash_color"):
		fig_opts["sash_color"] = opts["sash_color"]
	figure = HumanScript.new()
	add_child(figure)
	figure.build(look, fig_opts)

	add_to_group("interactable")
	if role != "villager":
		var label := Game.label3d(npc_name, 30, Color(1, 0.95, 0.8))
		label.position.y = 2.15 * sc
		label.visibility_range_end = 22.0
		add_child(label)
	_mark = Game.label3d("", 96, Color(1.0, 0.85, 0.2))
	_mark.position.y = 2.75 * sc
	_mark.visible = false
	_mark.visibility_range_end = 70.0
	add_child(_mark)

	if bool(opts.get("solid", true)):
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.38 * sc
		cap.height = 1.8 * sc
		cs.shape = cap
		cs.position.y = 0.9 * sc
		sb.add_child(cs)
		add_child(sb)


func prompt_text() -> String:
	if npc_name == "":
		return ""
	match role:
		"merchant":
			return "Trade with the %s" % npc_name.to_lower()
		"smith":
			return "Strengthen gear with the %s" % npc_name.to_lower()
	return "Talk to %s" % npc_name.to_lower()


func interact() -> void:
	world.npc_interact(self)


## Shows "!" (quest on offer), "?" (ready to hand in) or nothing above the head.
func set_mark(text: String) -> void:
	_mark.text = text
	_mark.visible = text != ""


## Turns to look at a point on the ground.
func face(point: Vector3) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length() > 0.05:
		rotation.y = atan2(-to.x, -to.z)


## Sits or kneels where they are, in a looping pose. With `seat`, a log is put under them.
func settle(pose_name: String, seat: bool) -> void:
	settled = true
	figure.pose(pose_name)
	if seat:
		# Find where the hips have come to rest and slide a log in beneath them.
		var hips: Vector3 = figure.bone_position("pelvis") * figure.scale
		var log_mesh := Game.mesh_cyl(0.17, 0.19, 0.95, Color(0.38, 0.27, 0.17), "wood")
		log_mesh.rotation.z = PI * 0.5
		log_mesh.position = Vector3(hips.x, maxf(0.17, hips.y - 0.27), hips.z)
		add_child(log_mesh)


## Sets this person walking the camp's paths, starting from walking place `node`.
func start_walking(camp, node: int, pace: float, seed_value: int) -> void:
	_camp = camp
	_at = node
	_to = node
	_pace = pace
	_dice.seed = seed_value
	_rest = _dice.randf_range(0.0, 4.0)
	rotation.y = _dice.randf() * TAU


func _process(delta: float) -> void:
	if settled:
		return
	if follow_target != null and is_instance_valid(follow_target):
		_follow(delta)
	elif _camp != null:
		_wander(delta)
	else:
		figure.animate(delta, 0.0)


func _follow(delta: float) -> void:
	var to: Vector3 = follow_target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var step := 0.0
	if d > 2.5:
		step = minf(7.0 * delta, d - 2.4)
		global_position += to / d * step
	global_position.y = world.terrain.surface_y(global_position.x, global_position.z)
	if d > 0.1:
		rotation.y = atan2(-to.x, -to.z)
	figure.animate(delta, step / maxf(delta, 0.0001))


## Walks from one walking place to the next, pausing now and then.
func _wander(delta: float) -> void:
	if _rest > 0.0:
		_rest -= delta
		figure.animate(delta, 0.0)
		return
	var target: Vector3 = _camp.node_position(_to)
	var to := target - global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.15:
		_from = _at
		_at = _to
		var ways: Array = _camp.links[_at]
		if ways.is_empty():
			_rest = 5.0
			return
		# Prefer not to turn straight back.
		var pick: int = ways[_dice.randi() % ways.size()]
		if pick == _from and ways.size() > 1:
			pick = ways[_dice.randi() % ways.size()]
		_to = pick
		if _dice.randf() < 0.3:
			_rest = _dice.randf_range(2.0, 7.0)
		return
	global_position += to / d * minf(_pace * delta, d)
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 8.0 * delta)
	figure.animate(delta, _pace)
