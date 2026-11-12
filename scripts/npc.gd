extends Node3D
## A person in the camp or the wilderness. What happens on interaction is decided by the world.
## Roles: villager, giver, merchant, smith, captain, witness, suspect, child, captive.

var world
var npc_name := ""
var role := "villager"
var quest := {}
var data := {}
var interact_radius := 3.2
var follow_target: Node3D = null
var _mark: Label3D


func setup(n: String, r: String, color: Color, opts: Dictionary = {}) -> void:
	npc_name = n
	role = r
	var sc: float = float(opts.get("scale", 1.0))
	var vis := Node3D.new()
	vis.scale = Vector3.ONE * sc
	add_child(vis)
	var robe := Game.mesh_capsule(0.36, 1.5, color)
	robe.position.y = 0.75
	vis.add_child(robe)
	var head := Game.mesh_sphere(0.21, Color(0.7, 0.5, 0.36))
	head.position.y = 1.62
	vis.add_child(head)
	var cloth := Game.mesh_sphere(0.24, color.lightened(0.35))
	cloth.position = Vector3(0, 1.68, 0.05)
	cloth.scale = Vector3(1.0, 0.8, 1.0)
	vis.add_child(cloth)
	if opts.has("sash"):
		var sash := Game.mesh_cyl(0.38, 0.38, 0.16, opts["sash"])
		sash.position.y = 0.88
		vis.add_child(sash)

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
		return
	var to: Vector3 = follow_target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > 2.5:
		global_position += to / d * minf(7.0 * delta, d - 2.4)
	global_position.y = world.terrain.surface_y(global_position.x, global_position.z)
	if d > 0.1:
		rotation.y = atan2(-to.x, -to.z)
