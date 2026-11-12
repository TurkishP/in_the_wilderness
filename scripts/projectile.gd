extends Node3D
## A sling stone. Swept each physics step so fast stones cannot pass through a target.

var world
var velocity := Vector3.ZERO
var damage := 1.0
var from_player := true
var life := 3.0


func _ready() -> void:
	add_child(Game.mesh_sphere(0.09, Color(0.55, 0.52, 0.48)))


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	velocity.y -= 5.0 * delta
	var a := global_position
	var b := a + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		queue_free()
		return
	if from_player:
		for e in get_tree().get_nodes_in_group("enemy"):
			if _hits(a, b, e.global_position, float(e.radius), float(e.height)):
				e.take_damage(damage, self)
				queue_free()
				return
	else:
		var p = world.player
		if is_instance_valid(p) and not p.dead and _hits(a, b, p.global_position, 0.4, 1.8):
			p.take_damage(damage, self)
			queue_free()
			return
	global_position = b


## True if segment a-b passes through an upright cylinder standing on `feet`.
func _hits(a: Vector3, b: Vector3, feet: Vector3, radius: float, height: float) -> bool:
	var center := feet + Vector3(0, height * 0.5, 0)
	var ab := b - a
	var t := 0.0
	var len2 := ab.length_squared()
	if len2 > 0.0:
		t = clampf((center - a).dot(ab) / len2, 0.0, 1.0)
	var p := a + ab * t
	var flat := Vector2(p.x - center.x, p.z - center.z).length()
	return flat <= radius + 0.25 and absf(p.y - center.y) <= height * 0.5 + 0.25
