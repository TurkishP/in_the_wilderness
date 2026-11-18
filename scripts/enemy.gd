extends CharacterBody3D
## One enemy: wildlife, raider or boss. Plain steering, no navmesh (the desert is open).

const ProjectileScript := preload("res://scripts/projectile.gd")
const HumanScript := preload("res://scripts/human.gd")
const CreatureScript := preload("res://scripts/creature.gd")
const GRAVITY := 20.0
const SPRING := 7.0          # a stalking cat springs from this close

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
var _dodge := Vector3.ZERO   # which way to go round something in the way
var _dodge_t := 0.0          # for how much longer
var _knock := Vector3.ZERO   # being driven back by a blow
var _swished := false        # the blow being wound up has made its sound
var hunting := false         # out to find the scout (an encounter): comes from far, keeps to no home
var _fleeing := false        # had enough (a hyena): runs off
var _stalking := false       # a big cat creeping up low, until it is close enough to spring
var _spring := 0.0           # seconds left of a cat's charge
var _hop := 0.0              # upward speed to leap with on the next step
var seen := false            # has noticed the scout (chased, or been struck)
var struck_once := false     # has been struck by the scout at least once
var last_tree := ""          # the weapon family of the scout's last blow on it, which a kill trains
## Armour and shields (for fighting men): the share of a blow the armour stops, and the shield's
## strength: while it is whole and faces the blow it stops SHIELD of it.
const SHIELD := 0.4
var armor := 0.0
var shield_hp := 0
var on_shield := false       # the last blow fell on the shield
var _shield_open := 0.0      # seconds the shield is pulled aside (a sickle's hook)
var _armor_broken := 0.0     # seconds the armour is broken open (an axe)
var _daze := 0.0             # seconds it can neither move nor strike
var _down := false           # knocked off its feet for the daze
var _slow := 0.0             # seconds it is slowed, and to what share of its speed
var _slow_f := 1.0
var _bleed := 0.0            # damage a second it bleeds, and for how much longer
var _bleed_left := 0.0
var unique := false          # a named guardian of a special place (scripts/places.gd)
var brave := false           # never runs, however hurt
var _xp_mult := 1.0
var _tint: Variant = null    # a colour of its own, in place of its kind's
var soldier := {}  # for human enemies: how this one is dressed and armed (Enemies.soldier)
var _vis: Node3D
var _fig: Node3D   # the human figure, for human enemies only
var _beast: Node3D # the animal model, for wildlife
var _bar: MeshInstance3D


func setup(k: String, mult: float, opts: Dictionary) -> void:
	kind = k
	def = Game.Enemies.ENEMIES[k]
	var sc: float = float(opts.get("scale", def.get("scale", 1.0)))
	display_name = str(opts.get("name", def["name"]))
	if def["shape"] == "human":
		# A fighting man of the people of this stage; unless named, he is called by his arms.
		var people := str(opts.get("people", "Desert"))
		soldier = Game.Enemies.soldier(people, k, bool(opts.get("boss", false)), Game.rng)
		if not opts.has("name") and k != "anak":
			display_name = "%s %s" % [people, soldier["name"]]
	max_hp = float(def["hp"]) * mult * float(opts.get("hp_mult", 1.0))
	hp = max_hp
	# Damage grows at half the rate of health, so late stages stay survivable.
	dmg = float(def["dmg"]) * (1.0 + (mult - 1.0) * 0.5) * float(opts.get("dmg_mult", 1.0))
	unique = bool(opts.get("unique", false))
	brave = bool(opts.get("brave", false))
	_xp_mult = float(opts.get("xp_mult", 1.0))
	_tint = opts.get("color", null)
	speed = float(def["speed"])
	ranged = bool(def.get("ranged", false))
	reach = float(def["reach"]) if ranged else float(def["reach"]) * sc
	aggro = float(def["aggro"])
	radius = float(def["radius"]) * sc
	is_raider = bool(opts.get("raider", false))
	is_boss = bool(opts.get("boss", false))
	drop_item = str(opts.get("drop", ""))
	tier = int(opts.get("tier", 1))
	hunting = bool(opts.get("hunting", false))
	_stalking = bool(def.get("stalk", false))
	if not soldier.is_empty():
		armor = Game.Enemies.armour_of(soldier)
		shield_hp = 2 if str(soldier.get("left", "")) == "shield" else 0
	add_to_group("enemy")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	_build(sc)


func _build(sc: float) -> void:
	var color: Color = def["color"] if _tint == null else _tint
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
		"snake", "scorpion", "beast", "wolf", "hyena", "leopard", "lion", "bear":
			# Animals are low-poly models animated in code (creature.gd).
			_beast = CreatureScript.new()
			_vis.add_child(_beast)
			_beast.build(shape_name, color)
		_:
			var look: Dictionary = HumanScript.random_look(Game.rng, 0)
			look["skin"] = 2 + Game.rng.randi() % 2
			look["beard"] = 1 if Game.rng.randf() < 0.8 else 0
			if soldier.has("hair"):
				look["hair"] = int(soldier["hair"])
			_fig = HumanScript.new()
			_vis.add_child(_fig)
			_fig.build(look, {
				"cloth_color": soldier["cloth_color"], "sash_color": soldier["sash_color"],
				"wear": soldier["wear"], "head_wear": soldier["head"],
			})
			_fig.shield_style = str(soldier.get("shield", "round"))
			if not ranged:
				_fig.set_hands(str(soldier.get("right", "sickle")), str(soldier.get("left", "none")))

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
	if shape_name == "human" or unique:
		var elite := kind == "champion" or kind == "anak" or unique
		var label := Game.label3d(display_name, 44 if is_boss else (34 if elite else 28), Color(1.0, 0.82, 0.35) if elite else Color(1.0, 0.75, 0.6))
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
	_shield_open -= delta
	_armor_broken -= delta
	_slow -= delta
	if _bleed_left > 0.0:
		_bleed_left -= delta
		_wound(_bleed * delta)
		if dead:
			return
	if _daze > 0.0:
		# Dazed or knocked down: it can do nothing until it has its feet and wits again.
		_daze -= delta
		_windup = -1.0
		if _daze <= 0.0 and _down:
			_down = false
			var up := create_tween()
			up.tween_property(_vis, "rotation:z", 0.0, 0.3)
		velocity.x = _knock.x
		velocity.z = _knock.z
		_knock = _knock.move_toward(Vector3.ZERO, 26.0 * delta)
		velocity.y = -1.0 if is_on_floor() else velocity.y - GRAVITY * delta
		move_and_slide()
		if _fig != null:
			_fig.animate(delta, 0.0)
		if _beast != null:
			_beast.animate(delta, 0.0)
		return
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dp := to_p.length()
	var alive: bool = not player.dead
	var chasing := false
	var move := Vector3.ZERO
	var spd := speed

	if is_raider:
		chasing = alive and dp < aggro
	elif hunting:
		chasing = alive and dp < 90.0
	else:
		chasing = alive and dp < aggro and global_position.distance_to(home) < 55.0
	if _fleeing:
		chasing = false
	if chasing:
		seen = true
	if _slow > 0.0:
		spd *= _slow_f

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
			if _stalking:
				# Creeping up low and slow; close enough, it springs.
				if dp > SPRING:
					spd = speed * 0.3
				else:
					_stalking = false
					_spring = 1.0
					_hop = 4.5
			if _spring > 0.0:
				_spring -= delta
				spd = speed * 1.35
			if _windup >= 0.0:
				_windup -= delta
				if _fig != null and not _swished and _windup < 0.13:
					_swished = true
					Game.play_sound("swing", global_position + Vector3(0, height * 0.7, 0), -3.0, 0.9)
				if _windup < 0.0:
					if dp <= r * 1.25 and alive:
						player.take_damage(dmg, self)
					_cd = 1.25
			else:
				if dp > r * 0.8:
					move = to_p / maxf(dp, 0.01)
				if dp <= r and _cd <= 0.0:
					# A raider's blow lands when its swing does; a beast's bite comes quicker.
					_windup = float(HumanScript.blows(_fig.weapon_kind)[0]["hit"]) if _fig != null else 0.3
					_swished = false
					_lunge()
					# A scout standing braced with a spear strikes first (Brace).
					player.brace_against(self)
	elif _fleeing:
		move = -to_p / maxf(dp, 0.01)
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

	# Round a rock, tree or tent in the way: held up by it, go along it for a moment.
	if _dodge_t > 0.0:
		_dodge_t -= delta
		if move.length() > 0.1:
			move = (move * 0.4 + _dodge).normalized()
	elif move.length() > 0.5 and is_on_wall():
		var n := get_wall_normal()
		_dodge = Vector3(-n.z, 0.0, n.x).normalized()
		var along := _dodge.dot(move)
		if along < 0.0 or (absf(along) < 0.15 and get_instance_id() % 2 == 0):
			_dodge = -_dodge
		_dodge_t = 0.7

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

	velocity.x = move.x * spd + _knock.x
	velocity.z = move.z * spd + _knock.z
	_knock = _knock.move_toward(Vector3.ZERO, 26.0 * delta)
	if _hop > 0.0 and is_on_floor():
		velocity.y = _hop
		_hop = 0.0
	elif is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	var face := to_p if chasing else move
	if face.length() > 0.05:
		_vis.rotation.y = lerp_angle(_vis.rotation.y, atan2(-face.x, -face.z), 10.0 * delta)
	if _fig != null:
		_fig.battle = chasing
		_fig.animate(delta, Vector2(velocity.x, velocity.z).length())
	if _beast != null:
		_beast.crouch = move_toward(_beast.crouch, 1.0 if _stalking and chasing else 0.0, delta * 3.0)
		_beast.animate(delta, Vector2(velocity.x, velocity.z).length())


func _lunge() -> void:
	if _fig != null:
		_fig.swing()
	elif _beast != null:
		_beast.strike()


func _shoot(player) -> void:
	_cd = 2.2
	if _fig != null:
		_fig.whirl()
	var origin := global_position + Vector3(0, height * 0.8, 0)
	Game.play_sound("sling_throw", origin, -4.0)
	var aim: Vector3 = player.global_position + Vector3(0, 1.1, 0)
	var shot := ProjectileScript.new()
	shot.world = world
	shot.from_player = false
	shot.damage = dmg
	shot.velocity = (aim - origin).normalized() * 24.0 + Vector3(0, 1.2, 0)
	world.stage_root.add_child(shot)
	shot.global_position = origin


## `knock_mult`: how much further than usual the blow drives it back. `pierce`: the share of its
## armour and shield the blow goes through (an arrow with Through the Gap).
func take_damage(amount: float, _src = null, knock_mult: float = 1.0, pierce: float = 0.0) -> void:
	if dead:
		return
	on_shield = false
	if _src is Node3D:
		seen = true
		# A shield that is whole and faces the blow takes part of it; armour takes some more.
		var from_dir: Vector3 = (_src as Node3D).global_position - global_position
		from_dir.y = 0.0
		var cut := armor * (1.0 - Game.perk("armour_breaker") if _armor_broken > 0.0 else 1.0)
		if shield_hp > 0 and _shield_open <= 0.0 and from_dir.length() > 0.05 and facing().dot(from_dir.normalized()) > 0.3:
			on_shield = true
			cut += SHIELD
		amount *= 1.0 - clampf(cut * (1.0 - pierce), 0.0, 0.75)
	hp -= amount
	_bar.visible = true
	_bar.scale.x = maxf(hp / max_hp, 0.001)
	if _src is Node3D and not is_boss:
		# Struck: driven back a step from whoever or whatever struck, and flinching.
		var from: Vector3 = global_position - (_src as Node3D).global_position
		from.y = 0.0
		if from.length() > 0.05:
			_knock = from.normalized() * (1.6 if kind == "champion" or kind == "anak" else (0.9 if def.get("heavy", false) else 2.8)) * knock_mult
		var flinch := create_tween()
		flinch.tween_property(_vis, "scale", _vis.scale * Vector3(1.06, 0.92, 1.06), 0.05)
		flinch.tween_property(_vis, "scale", _vis.scale, 0.12)
	# A struck cat stops creeping and comes on; a hyena that has had enough runs.
	_stalking = false
	if def.has("flee") and not brave and hp < max_hp * float(def["flee"]):
		_fleeing = true
	if hp <= 0.0:
		_die()


## Damage with no blow behind it (bleeding): no knock, no flinch.
func _wound(amount: float) -> void:
	hp -= amount
	_bar.visible = true
	_bar.scale.x = maxf(hp / max_hp, 0.001)
	if hp <= 0.0 and not dead:
		_die()


## The way it faces, on the ground.
func facing() -> Vector3:
	var ry := _vis.global_rotation.y
	return Vector3(-sin(ry), 0.0, -cos(ry))


## True if a blow from `point` comes from behind it or from the side.
func from_behind(point: Vector3) -> bool:
	var to := point - global_position
	to.y = 0.0
	return to.length() > 0.05 and facing().dot(to.normalized()) < 0.5


## Its swing is broken off before it lands, and it is put off its stroke for a moment.
func interrupt() -> void:
	if _windup >= 0.0:
		_windup = -1.0
		_cd = maxf(_cd, 1.0)
	_daze = maxf(_daze, 0.35)


## Dazed for `seconds`: it can neither move nor strike. `down`: knocked off its feet as well
## (a chief or a son of Anak only reels).
func daze(seconds: float, down: bool = false) -> void:
	_daze = maxf(_daze, seconds)
	_windup = -1.0
	if down and not is_boss and kind != "anak" and not _down:
		_down = true
		var fall := create_tween()
		fall.tween_property(_vis, "rotation:z", 1.35 if _beast != null else 1.1, 0.18)


## Moves at `share` of its speed for `seconds`.
func slow(share: float, seconds: float) -> void:
	_slow_f = minf(_slow_f if _slow > 0.0 else 1.0, share)
	_slow = maxf(_slow, seconds)


## Bleeds `total` damage over `seconds`, on top of any bleeding already.
func bleed(total: float, seconds: float) -> void:
	_bleed = (_bleed * maxf(_bleed_left, 0.0) + total) / maxf(seconds, _bleed_left)
	_bleed_left = maxf(_bleed_left, seconds)


## Drawn a step toward `point` (a sickle's hook).
func pull_toward(point: Vector3, metres: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length() > 1.2:
		_knock = to.normalized() * metres * 5.0


## The weapon is torn from his hand: he fights on with his fists, and hits much less hard.
func disarm() -> bool:
	if _fig == null or is_boss or ranged or _fig.weapon_kind in ["none", ""]:
		return false
	_fig.set_hands("none", _fig.offhand_kind)
	dmg *= 0.5
	reach = 1.6
	return true


## The shield is pulled aside for `seconds`: blows are not stopped by it.
func open_shield(seconds: float) -> void:
	_shield_open = maxf(_shield_open, seconds)


## An axe blow that fell on the shield: the second splits it and it is gone. True when it breaks.
func split_shield() -> bool:
	if not on_shield or shield_hp <= 0:
		return false
	shield_hp -= 1
	if shield_hp > 0:
		return false
	if _fig != null:
		_fig.set_hands(_fig.weapon_kind, "none")
	Game.play_sound("hit_wood", global_position + Vector3(0, 1.2, 0), 2.0, 0.7)
	return true


## Its armour is broken open for `seconds` (an axe).
func break_armour(seconds: float) -> void:
	_armor_broken = maxf(_armor_broken, seconds)


func _die() -> void:
	dead = true
	remove_from_group("enemy")
	_bar.visible = false
	var pos := global_position
	# The weapon that felled it learns from it (data/skills.gd).
	if last_tree != "":
		Game.train_kill(last_tree, kind)
	Game.gain_xp(int(round(float(def.get("xp", 5)) * float(world.stage["mult"]) * _xp_mult)))
	# What it leaves behind is rolled from data/drops.gd, and laid out in a ring round the body.
	var drops: Array = Game.roll_drops(kind, tier, float(world.stage["mult"]))
	if drop_item != "" and not Game.was_found(drop_item):
		drops.append(["item", drop_item])
	for i in drops.size():
		var a := TAU * i / maxf(1.0, drops.size()) + 0.6
		var off := Vector3.ZERO if drops.size() == 1 else Vector3(cos(a), 0, sin(a)) * 0.9
		world.spawn_pickup(str(drops[i][0]), drops[i][1], pos + off)
	world.on_enemy_died(self)
	var tw := create_tween()
	if _fig != null:
		# People fall and lie for a moment; animals just shrink away. The body raises dust
		# where it comes down.
		_fig.die()
		tw.tween_interval(0.55)
		tw.tween_callback(func() -> void:
			world.fx.dust(global_position - _vis.global_basis.z * 0.5, 0.8)
			Game.play_sound("fall", global_position))
		tw.tween_interval(2.05)
	else:
		# Animals roll onto their side, lie still a moment, and sink away.
		tw.tween_property(_vis, "rotation:z", PI * 0.5, 0.35)
		tw.tween_interval(1.2)
		tw.tween_property(_vis, "scale", Vector3.ONE * 0.05, 0.4)
	tw.tween_callback(queue_free)
