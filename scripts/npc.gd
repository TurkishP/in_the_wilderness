extends Node3D
## A person in the camp or the wilderness. What happens on interaction is decided by the world.
## Roles: villager, giver, merchant, smith, captain, witness, suspect, child, captive.

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
var _mark: Label3D


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

	if role != "villager":
		add_to_group("interactable")
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
	match role:
		"merchant":
			return "Trade with the %s" % npc_name.to_lower()
		"smith":
			return "Strengthen gear with the %s" % npc_name.to_lower()
		"villager":
			return ""
	return "Talk to %s" % npc_name.to_lower()


func interact() -> void:
	world.npc_interact(self)


## Shows "!" (quest on offer), "?" (ready to hand in) or nothing above the head.
func set_mark(text: String) -> void:
	_mark.text = text
	_mark.visible = text != ""


func _process(delta: float) -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		figure.animate(delta, 0.0)
		return
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
