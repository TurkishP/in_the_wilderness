extends Node3D
## A sling stone or an arrow. Swept each physics step so fast shots cannot pass through a target.

var world
var velocity := Vector3.ZERO
var damage := 1.0
var from_player := true
var arrow := false        # an arrow, which flies point first; otherwise a stone
var drop := 5.0           # how fast it falls, m/s²
var life := 3.0
# What the scout's skills (data/skills.gd) give the shot:
var tree := ""            # the weapon family a hit trains ("sling", "bow", or a thrown weapon's)
var pierce := 0.0         # the share of armour and shield it goes through (Through the Gap)
var pin := false          # slows what it strikes (Pinning Shot)
var stun_head := false    # dazes when it strikes the head (Stunning Stone)
var recover := 0.0        # the chance it can be picked up again where it lands (Thrifty, Gather Arrows)
var volley := false       # splits where it comes down, striking all round (Volley)
var carry := {}           # a thrown weapon (an item): it lies where it falls, to be picked up
var carry_hand := ""      # the hand it was thrown from, which it goes back to
var _mesh: Node3D


func _ready() -> void:
	if not carry.is_empty():
		# A thrown knife or spear: a shaft as long as the weapon, point first.
		var spear := Game.kind(carry) in ["spear", "spear_long"]
		var long := 2.0 if spear else 0.32
		_mesh = Node3D.new()
		var shaft := Game.mesh_cyl(0.015 if spear else 0.02, 0.015 if spear else 0.012, long, Color(0.45, 0.32, 0.2) if spear else Game.item_def(carry)["color"], "wood" if spear else "")
		shaft.position.y = -long * 0.5
		_mesh.add_child(shaft)
		var head := Game.mesh_cyl(0.0, 0.03, 0.14, Game.item_def(carry)["color"])
		head.position.y = 0.05
		_mesh.add_child(head)
		add_child(_mesh)
		_point()
	elif arrow:
		_mesh = Node3D.new()
		var shaft := Game.mesh_cyl(0.007, 0.007, 0.72, Color(0.62, 0.5, 0.32), "wood")
		shaft.position.y = -0.36
		_mesh.add_child(shaft)
		var head := Game.mesh_cyl(0.0, 0.016, 0.07, Color(0.5, 0.5, 0.52))
		head.position.y = 0.03
		_mesh.add_child(head)
		add_child(_mesh)
		_point()
	else:
		add_child(Game.mesh_sphere(0.09, Color(0.55, 0.52, 0.48)))


## Turns an arrow to point the way it is flying.
func _point() -> void:
	if _mesh == null or velocity.length() < 0.01:
		return
	var y := velocity.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	_mesh.basis = Basis(x, y, x.cross(y))


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_land(global_position)
		queue_free()
		return
	velocity.y -= drop * delta
	_point()
	var a := global_position
	var b := a + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	var ground := get_world_3d().direct_space_state.intersect_ray(q)
	if not ground.is_empty():
		# Into the sand or a rock: a spurt of dust where it struck.
		world.fx.dust(ground["position"], 0.35)
		Game.play_sound("thock", ground["position"], -6.0)
		if volley:
			_split(ground["position"])
		_land(ground["position"])
		queue_free()
		return
	if from_player:
		for e in get_tree().get_nodes_in_group("enemy"):
			if hits(a, b, e.global_position, float(e.radius), float(e.height)):
				if tree != "":
					e.last_tree = tree
					e.struck_once = true
				e.take_damage(damage, self, 1.0, pierce)
				Game.train(tree, Game.Skills.BLOW)
				if not e.dead:
					if pin:
						e.slow(1.0 - Game.perk("pinning_shot"), Game.perk_time("pinning_shot"))
					if stun_head and b.y > e.global_position.y + float(e.height) * 0.72:
						e.daze(Game.perk_time("stunning_stone"))
				world.fx.impact(b, velocity, false)
				Game.play_sound("thock", b)
				if not carry.is_empty():
					_land(e.global_position + Vector3(0.7, 0.0, 0.0))
				queue_free()
				return
	else:
		var p = world.player
		if is_instance_valid(p) and not p.dead and hits(a, b, p.global_position, 0.4, 1.8):
			p.take_damage(damage, self)
			queue_free()
			return
	global_position = b


## Where it comes to rest: a thrown weapon lies there to be picked up, and a stone or arrow may
## (Thrifty, Gather Arrows).
func _land(at: Vector3) -> void:
	if not carry.is_empty():
		var p = world.spawn_pickup("item", carry, at)
		p.set_meta("hand", carry_hand)
		carry = {}
	elif recover > 0.0 and Game.rng.randf() < recover:
		world.spawn_pickup("item", "arrows" if arrow else "stones", at)


## Volley: the arrow splits as it comes down, and strikes those standing near.
func _split(at: Vector3) -> void:
	var struck := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if struck >= 3:
			break
		var to: Vector3 = e.global_position - at
		to.y = 0.0
		if to.length() <= Game.perk("volley") + float(e.radius):
			e.last_tree = "bow"
			e.take_damage(damage, self, 1.0, pierce)
			world.fx.impact(e.global_position + Vector3(0, float(e.height) * 0.6, 0), Vector3.DOWN, false)
			struck += 1
	if struck > 0:
		Game.train("bow", Game.Skills.BLOW)


## True if segment a-b passes through an upright cylinder standing on `feet`.
static func hits(a: Vector3, b: Vector3, feet: Vector3, radius: float, height: float) -> bool:
	var center := feet + Vector3(0, height * 0.5, 0)
	var ab := b - a
	var t := 0.0
	var len2 := ab.length_squared()
	if len2 > 0.0:
		t = clampf((center - a).dot(ab) / len2, 0.0, 1.0)
	var p := a + ab * t
	var flat := Vector2(p.x - center.x, p.z - center.z).length()
	return flat <= radius + 0.25 and absf(p.y - center.y) <= height * 0.5 + 0.25
