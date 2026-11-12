extends CharacterBody3D
## One enemy: wildlife, raider or boss. Plain steering, no navmesh (the desert is open).

const ProjectileScript := preload("res://scripts/projectile.gd")
const HumanScript := preload("res://scripts/human.gd")
const GRAVITY := 20.0

var world
var kind := ""
var def := {}
var display_name := ""
var hp := 1.0
var max_hp := 1.0
var dmg := 1.0
var speed := 1.0
var reach := 1.5
var aggro := 10.0
var radius := 0.4
var height := 1.0
var ranged := false
var is_raider := false
var is_boss := false
var drop_item := ""
var tier := 1
var home := Vector3.ZERO
var dead := false
var _wander := Vector3.ZERO
var _wander_t := 0.0
var _cd := 0.0
var _windup := -1.0
var _vis: Node3D
var _fig: Node3D   # the human figure, for human enemies only
var _bar: MeshInstance3D


func setup(k: String, mult: float, opts: Dictionary) -> void:
	kind = k
	def = Game.Enemies.ENEMIES[k]
	var sc: float = float(opts.get("scale", def.get("scale", 1.0)))
	display_name = str(opts.get("name", def["name"]))
	max_hp = float(def["hp"]) * mult * float(opts.get("hp_mult", 1.0))
	hp = max_hp
	# Damage grows at half the rate of health, so late stages stay survivable.
	dmg = float(def["dmg"]) * (1.0 + (mult - 1.0) * 0.5)
	speed = float(def["speed"])
	ranged = bool(def.get("ranged", false))
	reach = float(def["reach"]) if ranged else float(def["reach"]) * sc
	aggro = float(def["aggro"])
	radius = float(def["radius"]) * sc
	is_raider = bool(opts.get("raider", false))
	is_boss = bool(opts.get("boss", false))
	drop_item = str(opts.get("drop", ""))
	tier = int(opts.get("tier", 1))
	add_to_group("enemy")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	_build(sc)


func _build(sc: float) -> void:
	var color: Color = def["color"]
	var shape_name: String = def["shape"]
	var cs := CollisionShape3D.new()
	if shape_name == "human":
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4 * sc
		cap.height = 1.8 * sc
		cs.shape = cap
		cs.position.y = 0.9 * sc
		height = 1.8 * sc
	else:
		var sph := SphereShape3D.new()
		sph.radius = radius
		cs.shape = sph
		cs.position.y = radius
		height = radius * 2.0
	add_child(cs)

	_vis = Node3D.new()
	_vis.scale = Vector3.ONE * sc
	add_child(_vis)
	match shape_name:
		"snake":
			var b := Game.mesh_capsule(0.11, 1.5, color)
			b.rotation.x = PI * 0.5
			b.position.y = 0.12
			_vis.add_child(b)
			var h := Game.mesh_sphere(0.16, color.darkened(0.25))
			h.position = Vector3(0, 0.22, -0.78)
			_vis.add_child(h)
		"scorpion":
			var b := Game.mesh_sphere(0.4, color)
			b.scale = Vector3(1.0, 0.4, 1.4)
			b.position.y = 0.22
			_vis.add_child(b)
			var tail := Game.mesh_cyl(0.05, 0.09, 0.9, color)
			tail.position = Vector3(0, 0.6, 0.5)
			tail.rotation.x = -0.6
			_vis.add_child(tail)
			var sting := Game.mesh_sphere(0.1, Color(0.6, 0.15, 0.1))
			sting.position = Vector3(0, 1.0, 0.3)
			_vis.add_child(sting)
			for side in [-1.0, 1.0]:
				var claw := Game.mesh_box(Vector3(0.14, 0.1, 0.5), color)
				claw.position = Vector3(0.32 * side, 0.2, -0.65)
				_vis.add_child(claw)
		"beast":
			var b := Game.mesh_box(Vector3(0.4, 0.45, 1.0), color)
			b.position.y = 0.6
			_vis.add_child(b)
			var h := Game.mesh_box(Vector3(0.3, 0.3, 0.42), color.darkened(0.15))
			h.position = Vector3(0, 0.85, -0.62)
			_vis.add_child(h)
			for lx in [-0.15, 0.15]:
				for lz in [-0.38, 0.38]:
					var leg := Game.mesh_box(Vector3(0.09, 0.42, 0.09), color.darkened(0.25))
					leg.position = Vector3(lx, 0.21, lz)
					_vis.add_child(leg)
		_:
			var look: Dictionary = HumanScript.random_look(Game.rng, 0)
			look["head"] = 1
			look["outfit"] = 3 if kind == "anak" else (2 if is_boss else 0)
			_fig = HumanScript.new()
			_vis.add_child(_fig)
			_fig.build(look, {
				"cloth_color": color, "sash_color": color.darkened(0.5),
				"head_color": color.darkened(0.45), "crown": is_boss,
			})
			if not ranged:
				_fig.set_weapon("spear" if kind == "anak" else ("sword" if is_boss else "sickle"))

	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 0.12)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.15, 0.1)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.billboard_keep_scale = true
	bm.no_depth_test = true
	_bar = MeshInstance3D.new()
	_bar.mesh = quad
	_bar.material_override = bm
	_bar.position.y = height + 0.45
	_bar.visible = false
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)
	if shape_name == "human":
		var label := Game.label3d(display_name, 44 if is_boss else 28, Color(1.0, 0.75, 0.6))
		label.position.y = height + 0.8
		label.visibility_range_end = 60.0 if is_boss else 28.0
		add_child(label)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var player = world.player
	if not is_instance_valid(player):
		return
	_cd -= delta
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dp := to_p.length()
	var alive: bool = not player.dead
	var chasing := false
	var move := Vector3.ZERO
	var spd := speed

	if is_raider:
		chasing = alive and dp < aggro
	else:
		chasing = alive and dp < aggro and global_position.distance_to(home) < 55.0

	if chasing:
		if ranged:
			if dp > reach * 0.8:
				move = to_p / maxf(dp, 0.01)
			elif dp < reach * 0.35:
				move = -to_p / maxf(dp, 0.01)
			if dp <= reach and _cd <= 0.0:
				_shoot(player)
		else:
			var r := reach + 0.3
			if _windup >= 0.0:
				_windup -= delta
				if _windup < 0.0:
					if dp <= r * 1.25 and alive:
						player.take_damage(dmg, self)
					_cd = 1.25
			else:
				if dp > r * 0.8:
					move = to_p / maxf(dp, 0.01)
				if dp <= r and _cd <= 0.0:
					_windup = 0.3
					_lunge()
	elif is_raider:
		var to_c: Vector3 = world.camp_pos - global_position
		to_c.y = 0.0
		if to_c.length() > world.camp_radius * 0.6:
			move = to_c.normalized()
		else:
			world.damage_camp(dmg * 0.06 * delta)
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 6.0)
			_wander = home + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
		var to_w := _wander - global_position
		to_w.y = 0.0
		if to_w.length() > 1.0:
			move = to_w.normalized()
			spd = speed * 0.35

	# Keep enemies from stacking on one spot.
	for o in get_tree().get_nodes_in_group("enemy"):
		if o == self:
			continue
		var d: Vector3 = global_position - o.global_position
		d.y = 0.0
		var l := d.length()
		var min_d: float = radius + float(o.radius) + 0.3
		if l < min_d and l > 0.01:
			move += d / l * (min_d - l) * 1.5

	velocity.x = move.x * spd
	velocity.z = move.z * spd
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	var face := to_p if chasing else move
	if face.length() > 0.05:
		_vis.rotation.y = lerp_angle(_vis.rotation.y, atan2(-face.x, -face.z), 10.0 * delta)
	if _fig != null:
		_fig.animate(delta, Vector2(velocity.x, velocity.z).length())


func _lunge() -> void:
	if _fig != null:
		_fig.swing()
		return
	var tw := create_tween()
	tw.tween_property(_vis, "position:y", 0.35, 0.18)
	tw.tween_property(_vis, "position:y", 0.0, 0.2)


func _shoot(player) -> void:
	_cd = 2.2
	if _fig != null:
		_fig.whirl()
	var origin := global_position + Vector3(0, height * 0.8, 0)
	var aim: Vector3 = player.global_position + Vector3(0, 1.1, 0)
	var shot := ProjectileScript.new()
	shot.world = world
	shot.from_player = false
	shot.damage = dmg
	shot.velocity = (aim - origin).normalized() * 24.0 + Vector3(0, 1.2, 0)
	world.stage_root.add_child(shot)
	shot.global_position = origin


func take_damage(amount: float, _src = null) -> void:
	if dead:
		return
	hp -= amount
	_bar.visible = true
	_bar.scale.x = maxf(hp / max_hp, 0.001)
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	remove_from_group("enemy")
	_bar.visible = false
	var pos := global_position
	var sv: Array = def["silver"]
	var amount := int(randi_range(int(sv[0]), int(sv[1])) * (0.6 + 0.4 * float(world.stage["mult"])))
	if amount > 0:
		world.spawn_pickup("silver", amount, pos)
	if def["shape"] == "human":
		if randf() < 0.3 or is_boss:
			world.spawn_pickup("bronze", 3 if is_boss else 1 + randi() % 2, pos + Vector3(0.8, 0, 0.3))
		var item := drop_item
		if item == "" and randf() < (1.0 if is_boss else 0.1):
			item = Game.roll_drop(tier)
		if item != "":
			world.spawn_pickup("item", item, pos + Vector3(-0.8, 0, 0.4))
	world.on_enemy_died(self)
	var tw := create_tween()
	if _fig != null:
		# People fall and lie for a moment; animals just shrink away.
		_fig.die()
		tw.tween_interval(2.6)
	else:
		tw.tween_property(_vis, "scale", Vector3.ONE * 0.05, 0.3)
	tw.tween_callback(queue_free)
