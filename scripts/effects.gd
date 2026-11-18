extends Node3D
## Small things that make the world answer: dust kicked up where feet come down, a burst where a
## blow lands, the camera's jolt, and the instant the game holds its breath on a hit.
##
## Every burst is a handful of soft round puffs thrown out once and then freed. Their color is
## the stage's sand, so the dust belongs to the ground it rises from.

var world
var sand := Color(0.82, 0.71, 0.5)
var bursts := 0               # how many have been made (the tests read this)
var _puff_mesh: QuadMesh
var _holding := false


func _ready() -> void:
	var dot := GradientTexture2D.new()
	dot.width = 64
	dot.height = 64
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.55, Color(1, 1, 1, 0.55))
	dot.gradient = fade
	var m := StandardMaterial3D.new()
	m.albedo_texture = dot
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_puff_mesh = QuadMesh.new()
	_puff_mesh.size = Vector2(1, 1)
	_puff_mesh.material = m


## Dust thrown out along the ground from `at`: a landing, a body falling, a running foot.
## `amount` 1 is a jump's landing.
func dust(at: Vector3, amount: float = 1.0) -> void:
	var p := _burst(at + Vector3(0, 0.08, 0), int(round(18.0 * amount)), 0.7 + 0.35 * amount)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.3
	p.emission_ring_inner_radius = 0.1
	p.emission_ring_height = 0.02
	p.direction = Vector3(1, 0.25, 0)
	p.spread = 180.0
	p.flatness = 0.82
	p.initial_velocity_min = 1.0 * amount
	p.initial_velocity_max = 2.8 * amount
	p.gravity = Vector3(0, 0.5, 0)
	p.damping_min = 2.5
	p.damping_max = 4.0
	p.scale_amount_min = 0.35 * sqrt(amount)
	p.scale_amount_max = 0.8 * sqrt(amount)
	p.scale_amount_curve = _curve(0.45, 1.0)
	p.color = Color(sand.r, sand.g, sand.b, 0.5).lightened(0.12)
	p.color_ramp = _fade_out()
	p.emitting = true


## Where a blow lands: grit and dust knocked off, flying the way the blow was going (`along`).
func impact(at: Vector3, along: Vector3, heavy: bool = false) -> void:
	var p := _burst(at, 14 if heavy else 9, 0.4)
	p.direction = (along.normalized() + Vector3(0, 0.6, 0)).normalized()
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.5 if heavy else 4.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16 if heavy else 0.12
	p.color = Color(1.0, 0.95, 0.82, 0.95)
	p.color_ramp = _fade_out()
	p.emitting = true
	var haze := _burst(at, 4, 0.45)
	haze.direction = Vector3.UP
	haze.spread = 80.0
	haze.initial_velocity_min = 0.3
	haze.initial_velocity_max = 0.9
	haze.gravity = Vector3.ZERO
	haze.scale_amount_min = 0.3
	haze.scale_amount_max = 0.55
	haze.scale_amount_curve = _curve(0.5, 1.0)
	haze.color = Color(sand.r, sand.g, sand.b, 0.4).lightened(0.2)
	haze.color_ramp = _fade_out()
	haze.emitting = true


## Holds the game still for an instant, as a blow that lands should feel. `seconds` of real time.
func hit_stop(seconds: float = 0.05) -> void:
	if _holding or world.hud.auto:
		return
	_holding = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_holding = false


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _burst(at: Vector3, count: int, life: float) -> CPUParticles3D:
	bursts += 1
	var p := CPUParticles3D.new()
	p.mesh = _puff_mesh
	p.amount = maxi(1, count)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = at
	get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)
	return p


func _curve(from: float, to: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, from))
	c.add_point(Vector2(1, to))
	return c


func _fade_out() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	return g
