extends Node3D
## Something lying on the ground that is collected by walking over it.
## kind: silver, bronze, item (gear), quest (side-quest item), objective (main objective item).

var world
var kind := ""
var payload: Variant = null
var radius := 1.9
var _vis: Node3D
var _t := 0.0
var _full_warned := false


func setup(k: String, p: Variant, label: String, color: Color) -> void:
	kind = k
	payload = p
	add_to_group("pickup")
	_vis = Node3D.new()
	add_child(_vis)
	match kind:
		"silver":
			_vis.add_child(Game.mesh_cyl(0.16, 0.16, 0.08, Color(0.85, 0.85, 0.8), "", 0.3))
		"bronze":
			_vis.add_child(Game.mesh_box(Vector3(0.26, 0.18, 0.26), Color(0.8, 0.5, 0.2), "", 0.3))
		"item":
			_vis.add_child(Game.mesh_box(Vector3(0.4, 0.4, 0.4), Color(1.0, 0.8, 0.3), "", 1.2))
			_beam(Color(1.0, 0.8, 0.3))
		_:
			_vis.add_child(Game.mesh_sphere(0.28, color, "", 0.6))
			_beam(color.lightened(0.4))
			var l := Game.label3d(label, 26, Color(1, 1, 0.9))
			l.position.y = 1.0
			l.visibility_range_end = 30.0
			add_child(l)


func _beam(color: Color) -> void:
	var b := Game.mesh_cyl(0.05, 0.05, 9.0, color, "", 1.5, 0.35)
	b.position.y = 4.5
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)


func _process(delta: float) -> void:
	_t += delta
	_vis.rotation.y = _t * 1.6
	_vis.position.y = 0.35 + sin(_t * 2.5) * 0.08
	var p = world.player
	if is_instance_valid(p) and not p.dead and p.global_position.distance_to(global_position) < radius:
		# Gear takes places in the bag; when there is no room for it, it stays where it lies.
		if kind == "item" and not Game.can_take(str(payload)):
			if not _full_warned:
				_full_warned = true
				Game.say("Your bag is full. Store or sell something to make room.")
			return
		collect()
	else:
		_full_warned = false


func collect() -> void:
	match kind:
		"silver":
			Game.silver += int(payload)
			Game.say("+%d silver" % int(payload))
		"bronze":
			Game.bronze += int(payload)
			Game.say("+%d bronze" % int(payload))
		"item":
			var inst := Game.add_item(str(payload))
			Game.say("Found: %s. Press I to see it." % Game.item_name(inst))
		"quest":
			world.quests.on_gather(int(payload))
		"objective":
			world.on_objective_pickup()
	remove_from_group("pickup")
	queue_free()
