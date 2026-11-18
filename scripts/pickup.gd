extends Node3D
## Something lying on the ground that is collected by walking over it.
## kind: silver, bronze, item (gear), quest (side-quest item), objective (main objective item).
## An item's payload is its id, or the item itself (a thrown weapon, which keeps its strengthening;
## with the meta "hand" it goes back into that hand if the hand is empty).

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
			# Ordinary gear glows a pale gold; a rare find blue, a legendary one orange and taller.
			var rare: int = Game.rarity(payload if payload is Dictionary else Game.new_item(str(payload)))
			var glow: Color = Color(1.0, 0.8, 0.3) if rare == 0 else Game.RARITY_COLORS[rare]
			_vis.add_child(Game.mesh_box(Vector3(0.4, 0.4, 0.4), glow, "", 1.2 + rare))
			_beam(glow, 9.0 + 5.0 * rare)
		_:
			_vis.add_child(Game.mesh_sphere(0.28, color, "", 0.6))
			_beam(color.lightened(0.4))
			var l := Game.label3d(label, 26, Color(1, 1, 0.9))
			l.position.y = 1.0
			l.visibility_range_end = 30.0
			add_child(l)


func _beam(color: Color, height: float = 9.0) -> void:
	var b := Game.mesh_cyl(0.05, 0.05, height, color, "", 1.5, 0.35)
	b.position.y = height * 0.5
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)


func _process(delta: float) -> void:
	_t += delta
	_vis.rotation.y = _t * 1.6
	_vis.position.y = 0.35 + sin(_t * 2.5) * 0.08
	var p = world.player
	if is_instance_valid(p) and not p.dead and p.global_position.distance_to(global_position) < radius:
		# Gear takes places in the bag; when there is no room for it, it stays where it lies.
		if kind == "item" and not Game.can_take(_item_id()):
			if not _full_warned:
				_full_warned = true
				Game.say("Your bag is full. Store or sell something to make room.")
			return
		collect()
	else:
		_full_warned = false


func _item_id() -> String:
	return str(payload["id"]) if payload is Dictionary else str(payload)


func collect() -> void:
	match kind:
		"silver":
			Game.silver += int(payload)
			Game.say("+%d silver" % int(payload))
			Game.play_sound("coin", null, -4.0)
		"bronze":
			Game.bronze += int(payload)
			Game.say("+%d bronze" % int(payload))
			Game.play_sound("coin", null, -4.0, 0.7)
		"item":
			var inst := Game.add_item(_item_id(), int(payload.get("plus", 0)) if payload is Dictionary else 0)
			Game.record_find(_item_id())
			if has_meta("hand") and not inst.is_empty() and Game.equipped.get(str(get_meta("hand")), {"x": 1}).is_empty():
				Game.equip(inst, str(get_meta("hand")))
			var rare: int = Game.rarity(inst)
			Game.play_sound("find", null, -2.0 + 2.0 * rare, 1.0 + 0.12 * rare)
			Game.say("%s: %s. Press I to see it." % ["Found" if rare == 0 else Game.RARITY_NAMES[rare] + " find", Game.item_name(inst)])
		"quest":
			world.quests.on_gather(int(payload))
		"objective":
			world.on_objective_pickup()
	remove_from_group("pickup")
	queue_free()
