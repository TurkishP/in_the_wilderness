extends Node3D
## The pillar of cloud: a tall column of soft white billows, widening as it rises to a
## rounded head, slowly turning on itself.
##
## It is made of two things, both drawn in batches:
##   - a few hundred smooth white balls of different sizes, lit softly by the sun, which give
##     the cloud its lumpy, billowing shape
##   - a haze of faint round sprites over them, which blurs the edges
## The balls are split into three groups that turn at different speeds, so the column churns.

static var _ball: SphereMesh
static var _sprite: QuadMesh
static var _ball_material: StandardMaterial3D
static var _haze_material: StandardMaterial3D

var puffs := 0               # how many balls make up the column
var top := 0.0               # height of the highest one
var _groups: Array = []      # [[node, turn speed], ...]


## height and radii in metres. The column starts at this node's position and rises from it.
func build(height: float = 150.0, base_radius: float = 4.0, top_radius: float = 11.0, seed_value: int = 1) -> void:
	_make_shared()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var swell := FastNoiseLite.new()
	swell.seed = seed_value
	swell.frequency = 0.03

	var balls := [[], [], []]
	var tints := [[], [], []]
	var haze: Array = []
	var haze_tint: Array = []
	var y := 0.0
	var n := 0
	while y < height:
		var f := y / height
		# Wider with height, swelling and narrowing along the way, and rounded off at the head.
		var radius := lerpf(base_radius, top_radius, pow(f, 0.8)) * (1.0 + 0.28 * swell.get_noise_1d(y * 2.0))
		if f > 0.82:
			radius *= lerpf(1.3, 0.45, (f - 0.82) / 0.18)
		var count := 5 + int(radius * 0.55)
		for k in count:
			var a := rng.randf() * TAU
			var out := radius * rng.randf_range(0.3, 1.0)
			var s := radius * rng.randf_range(0.42, 0.78)
			var pos := Vector3(cos(a) * out, y + rng.randf_range(-0.35, 0.35) * radius, sin(a) * out)
			balls[n % 3].append(Transform3D(Basis.from_scale(Vector3(s, s * rng.randf_range(0.78, 1.0), s)), pos))
			# Mostly white; some billows a little grey, more so low down, to give depth.
			var grey := rng.randf() * lerpf(0.16, 0.06, f)
			tints[n % 3].append(Color(1.0 - grey, 1.0 - grey * 0.9, 1.0 - grey * 0.75))
			top = maxf(top, pos.y + s)
			n += 1
		for k in 2:
			var a := rng.randf() * TAU
			var size := radius * rng.randf_range(1.4, 2.1)
			haze.append(Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3(cos(a) * radius * 0.9, y + rng.randf_range(-0.3, 0.3) * radius, sin(a) * radius * 0.9)))
			haze_tint.append(Color(1, 1, 1, rng.randf_range(0.5, 1.0)))
		y += radius * 0.5
	puffs = n

	var speeds := [0.04, -0.028, 0.055]
	for g in 3:
		_groups.append([_batch(_ball, balls[g], tints[g], _ball_material), speeds[g]])
	_groups.append([_batch(_sprite, haze, haze_tint, _haze_material), -0.02])


func _batch(mesh: Mesh, xforms: Array, tints: Array, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, tints[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _process(delta: float) -> void:
	for g in _groups:
		(g[0] as Node3D).rotate_y(float(g[1]) * delta)


static func _make_shared() -> void:
	if _ball != null:
		return
	_ball = SphereMesh.new()
	_ball.radius = 1.0
	_ball.height = 2.0
	_ball.radial_segments = 14
	_ball.rings = 7

	# White, with light wrapping round each ball and a soft glow so the shaded side stays pale.
	_ball_material = StandardMaterial3D.new()
	_ball_material.vertex_color_use_as_albedo = true
	_ball_material.vertex_color_is_srgb = true
	_ball_material.roughness = 1.0
	_ball_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_ball_material.emission_enabled = true
	_ball_material.emission = Color(1.0, 1.0, 1.0)
	_ball_material.emission_energy_multiplier = 0.12
	_ball_material.rim_enabled = true
	_ball_material.rim = 0.5
	_ball_material.rim_tint = 0.2

	_sprite = QuadMesh.new()
	_sprite.size = Vector2(1.0, 1.0)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.2))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.55, Color(1, 1, 1, 0.1))
	var disc := GradientTexture2D.new()
	disc.gradient = fade
	disc.width = 128
	disc.height = 128
	disc.fill = GradientTexture2D.FILL_RADIAL
	disc.fill_from = Vector2(0.5, 0.5)
	disc.fill_to = Vector2(0.5, 0.0)
	_haze_material = StandardMaterial3D.new()
	_haze_material.albedo_texture = disc
	_haze_material.vertex_color_use_as_albedo = true
	_haze_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_haze_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_haze_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_haze_material.billboard_keep_scale = true
	_haze_material.cull_mode = BaseMaterial3D.CULL_DISABLED
