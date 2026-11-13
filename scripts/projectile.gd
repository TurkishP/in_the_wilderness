extends Node3D
## A sling stone or an arrow. Swept each physics step so fast shots cannot pass through a target.

var world
var velocity := Vector3.ZERO
var damage := 1.0
var from_player := true
var arrow := false        # an arrow, which flies point first; otherwise a stone
var drop := 5.0           # how fast it falls, m/s²
var life := 3.0
var _mesh: Node3D


func _ready() -> void:
	if arrow:
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
		queue_free()
		return
	velocity.y -= drop * delta
	_point()
	var a := global_position
	var b := a + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		queue_free()
		return
	if from_player:
		for e in get_tree().get_nodes_in_group("enemy"):
			if hits(a, b, e.global_position, float(e.radius), float(e.height)):
				e.take_damage(damage, self)
				queue_free()
				return
	else:
		var p = world.player
		if is_instance_valid(p) and not p.dead and hits(a, b, p.global_position, 0.4, 1.8):
			p.take_damage(damage, self)
			queue_free()
			return
	global_position = b


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
