extends Node3D
## The dust wind. Now and then a gust comes over the land carrying dust, sand and bits of dry
## grass, and dies away again. No two are alike: each takes a kind (below), a direction near the
## stage's prevailing wind, a strength, a length, a color of dust, a rhythm of surges and a sound
## of its own. The parts it is drawn with:
##   streaks  fast lines of dust at head height
##   puffs    soft clouds of dust drifting past
##   ground   sand snaking low along the ground
##   debris   grit and bits of dry grass tumbling by
##   devils   whirlwinds of dust that wander across the land
##   haze     the air thickens and takes the color of the dust
##   lens     dust blowing across the view
## The node follows the player; inside the tent nothing is seen and the wind is only heard.

## weight: how often the kind comes; time: how long it lasts, [min, max] seconds; speed: wind in
## m/s; then how much of each part (0..1, devils: how many); haze: how many times thicker the air
## gets at the height of it; veer: how far the wind turns while it blows (radians); sound: loudness.
const KINDS := {
	"breeze": {"weight": 3.0, "time": [7.0, 13.0], "speed": [4.0, 7.0], "streaks": 0.4, "puffs": 0.25, "ground": 0.35, "debris": 0.15, "devils": 0, "haze": 2.0, "lens": 0.05, "veer": 0.2, "sound": 0.35},
	"gust": {"weight": 3.0, "time": [8.0, 15.0], "speed": [8.0, 12.0], "streaks": 0.85, "puffs": 0.5, "ground": 0.75, "debris": 0.65, "devils": 0, "haze": 5.0, "lens": 0.14, "veer": 0.3, "sound": 0.7},
	"drifts": {"weight": 2.0, "time": [10.0, 18.0], "speed": [6.0, 10.0], "streaks": 0.3, "puffs": 0.1, "ground": 1.0, "debris": 0.3, "devils": 0, "haze": 2.0, "lens": 0.04, "veer": 0.15, "sound": 0.45},
	"devils": {"weight": 2.0, "time": [16.0, 28.0], "speed": [3.0, 6.0], "streaks": 0.2, "puffs": 0.15, "ground": 0.3, "debris": 0.2, "devils": 3, "haze": 1.6, "lens": 0.0, "veer": 0.5, "sound": 0.3},
	"veering": {"weight": 1.5, "time": [12.0, 20.0], "speed": [6.0, 10.0], "streaks": 0.65, "puffs": 0.4, "ground": 0.55, "debris": 0.45, "devils": 1, "haze": 3.0, "lens": 0.1, "veer": 1.6, "sound": 0.55},
	"squall": {"weight": 1.0, "time": [16.0, 26.0], "speed": [11.0, 16.0], "streaks": 1.0, "puffs": 0.85, "ground": 1.0, "debris": 1.0, "devils": 0, "haze": 11.0, "lens": 0.28, "veer": 0.35, "sound": 0.95},
	"dust_wall": {"weight": 0.6, "time": [22.0, 34.0], "speed": [9.0, 14.0], "streaks": 0.7, "puffs": 1.0, "ground": 0.85, "debris": 0.6, "devils": 0, "haze": 28.0, "lens": 0.45, "veer": 0.2, "sound": 0.85},
}
## Dust colors: pale sand, golden, ochre, red earth, grey, white sand.
const PALETTES := [Color(0.86, 0.79, 0.65), Color(0.85, 0.72, 0.5), Color(0.8, 0.64, 0.42), Color(0.74, 0.52, 0.36), Color(0.72, 0.69, 0.62), Color(0.92, 0.87, 0.76)]
const SOUNDS := ["res://assets/sounds/wind_1.ogg", "res://assets/sounds/wind_2.ogg", "res://assets/sounds/wind_3.ogg"]
const CALM := Vector2(25.0, 70.0)    # seconds of still air between gusts
const FIRST := Vector2(12.0, 30.0)   # before the first one on a stage
const AROUND := 26.0                  # how far round the player dust is blown

var world
var gust := {}            # the gust blowing now, or {} when the air is still
var strength := 0.0       # how hard it blows now, 0 .. a little over 1
var wind := Vector3.ZERO  # where it blows now, horizontal unit
var _t := 0.0
var _wait := 20.0
var _rng := RandomNumberGenerator.new()
var _prevailing := 0.0
var _parts := {}          # part -> GPUParticles3D
var _devils: Array = []
var _lens: ColorRect
var _lens_drift := Vector2.ZERO
var _sound: AudioStreamPlayer
var _fog := 0.0
var _fog_color := Color.WHITE
var _soft: Texture2D


func setup(w) -> void:
	world = w
	_rng.randomize()
	_fog = world.environment.fog_density
	_fog_color = world.environment.fog_light_color
	_soft = _soft_texture()
	_parts["streaks"] = _streaks()
	_parts["puffs"] = _puffs()
	_parts["ground"] = _ground()
	_parts["debris"] = _debris()
	_make_lens()
	_sound = AudioStreamPlayer.new()
	_sound.bus = "Effects"
	add_child(_sound)
	reset(0.0)


## A new stage: the air is still, and the first gust comes after a while. Each stage has a
## prevailing wind of its own.
func reset(prevailing: float) -> void:
	stop()
	_prevailing = prevailing
	_wait = _rng.randf_range(FIRST.x, FIRST.y)


## Starts a gust now: of the given kind, or a kind picked by weight.
func start(kind: String = "") -> void:
	if kind == "" or not KINDS.has(kind):
		kind = _pick()
	var k: Dictionary = KINDS[kind]
	var dir := _prevailing + _rng.randf_range(-1.1, 1.1)
	if _rng.randf() < 0.15:
		dir = _rng.randf() * TAU    # now and then from anywhere
	gust = {
		"kind": kind,
		"length": _rng.randf_range(k["time"][0], k["time"][1]),
		"speed": _rng.randf_range(k["speed"][0], k["speed"][1]),
		"dir": dir,
		"veer": float(k["veer"]) * _rng.randf_range(0.5, 1.0) * (1.0 if _rng.randf() < 0.5 else -1.0),
		"color": _color(kind),
		"rise": _rng.randf_range(0.12, 0.3),
		"fall": _rng.randf_range(0.2, 0.4),
		# The surges: two slow waves of different speed, and how deep they go.
		"surge": _rng.randf_range(0.15, 0.6),
		"f1": _rng.randf_range(0.12, 0.45), "f2": _rng.randf_range(0.5, 1.3),
		"p1": _rng.randf() * TAU, "p2": _rng.randf() * TAU,
		"sound": _rng.randi() % SOUNDS.size(),
		"pitch": _rng.randf_range(0.82, 1.18),
	}
	for part in ["streaks", "puffs", "ground", "debris", "haze", "lens"]:
		# Each part a little more or less than the kind says.
		gust[part] = float(k[part]) * _rng.randf_range(0.7, 1.15)
	gust["loud"] = float(k["sound"]) * _rng.randf_range(0.8, 1.1)
	_t = 0.0
	for d in _devils:
		(d["node"] as Node).queue_free()
	_devils.clear()
	_devils_for(int(k["devils"]))
	var stream: AudioStream = load(SOUNDS[int(gust["sound"])])
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_sound.stream = stream
	_sound.pitch_scale = float(gust["pitch"])
	_sound.volume_db = -60.0
	_sound.play()


## Ends any gust at once and clears the air.
func stop() -> void:
	gust = {}
	strength = 0.0
	for d in _devils:
		(d["node"] as Node).queue_free()
	_devils.clear()
	if _sound != null:
		_sound.stop()
	if world != null and world.environment != null:
		world.environment.fog_density = _fog
		world.environment.fog_light_color = _fog_color
	for part in _parts:
		(_parts[part] as GPUParticles3D).emitting = false
	if _lens != null:
		_lens.visible = false


func _pick() -> String:
	var total := 0.0
	for kind in KINDS:
		total += float(KINDS[kind]["weight"])
	var roll := _rng.randf() * total
	for kind in KINDS:
		roll -= float(KINDS[kind]["weight"])
		if roll <= 0.0:
			return kind
	return "breeze"


func _color(kind: String) -> Color:
	var c: Color = PALETTES[_rng.randi() % PALETTES.size()]
	if kind == "dust_wall":
		c = PALETTES[2 + _rng.randi() % 2]     # walls of dust come ochre or red
	return c.lerp(Color(_rng.randf(), _rng.randf(), _rng.randf()), 0.05)


func _process(delta: float) -> void:
	var p = world.player if world != null else null
	if not is_instance_valid(p):
		return
	global_position = p.global_position
	if gust.is_empty():
		_wait -= delta
		if _wait <= 0.0:
			start()
		_fade_out(delta)
		return
	_t += delta
	var length := float(gust["length"])
	var k := _t / length
	var env := 1.0
	if k < float(gust["rise"]):
		env = smoothstep(0.0, float(gust["rise"]), k)
	elif k > 1.0 - float(gust["fall"]):
		env = 1.0 - smoothstep(1.0 - float(gust["fall"]), 1.0, k)
	var surge := 1.0 + float(gust["surge"]) * (0.6 * sin(TAU * float(gust["f1"]) * _t + float(gust["p1"])) + 0.4 * sin(TAU * float(gust["f2"]) * _t + float(gust["p2"])))
	strength = clampf(env * surge, 0.0, 1.25)
	# The wind turns as it blows, by up to "veer" over the gust.
	var heading := float(gust["dir"]) + float(gust["veer"]) * sin(k * PI * 0.9)
	wind = Vector3(sin(heading), 0.0, cos(heading))
	_apply(delta, bool(p.indoors))
	if _t >= length:
		gust = {}
		_wait = _rng.randf_range(CALM.x, CALM.y)


## Sets every part from the gust and how hard it blows now.
func _apply(delta: float, inside: bool) -> void:
	var seen := 0.0 if inside else strength
	var speed := float(gust["speed"]) * (0.65 + 0.45 * strength)
	var color: Color = gust["color"]
	for part in _parts:
		var ps: GPUParticles3D = _parts[part]
		var amount := clampf(seen * float(gust[part]), 0.0, 1.0)
		ps.amount_ratio = amount
		ps.emitting = amount > 0.02
		var pm: ParticleProcessMaterial = ps.process_material
		pm.direction = (wind + Vector3(0, 0.04 if part != "ground" else 0.0, 0)).normalized()
		var fast := {"streaks": 1.0, "puffs": 0.55, "ground": 0.85, "debris": 1.1}
		pm.initial_velocity_min = speed * float(fast[part]) * 0.8
		pm.initial_velocity_max = speed * float(fast[part]) * 1.2
		pm.color = Color(color.r, color.g, color.b, 1.0)
		# Dust is blown in from upwind, so it crosses the whole view.
		ps.position = -wind * AROUND * 0.6 + Vector3(0, ps.position.y, 0)
	# The air thickens toward the color of the dust.
	var thick: float = 1.0 + (float(gust["haze"]) - 1.0) * seen
	world.environment.fog_density = _fog * thick
	world.environment.fog_light_color = _fog_color.lerp(color, clampf(seen * minf(1.0, float(gust["haze"]) / 6.0), 0.0, 0.7))
	_update_lens(delta, seen * float(gust["lens"]), speed, color)
	_update_devils(delta, inside, speed)
	_sound.volume_db = linear_to_db(maxf(0.0001, strength * float(gust["loud"]) * (0.3 if inside else 1.0)))


## The color of the air when no wind is blowing, which changes through the day (daylight.gd).
func set_still_color(color: Color) -> void:
	_fog_color = color
	if strength <= 0.0:
		world.environment.fog_light_color = color


## Between gusts: what is left settles.
func _fade_out(delta: float) -> void:
	if strength <= 0.0 and _devils.is_empty():
		return
	strength = move_toward(strength, 0.0, delta * 0.5)
	for part in _parts:
		(_parts[part] as GPUParticles3D).emitting = false
	world.environment.fog_density = lerpf(_fog, world.environment.fog_density, exp(-delta))
	world.environment.fog_light_color = _fog_color.lerp(world.environment.fog_light_color, exp(-delta))
	if _lens != null:
		_lens.visible = false
	if strength <= 0.0:
		_sound.stop()
		world.environment.fog_density = _fog
		world.environment.fog_light_color = _fog_color
		for d in _devils:
			(d["node"] as Node).queue_free()
		_devils.clear()


# ---------------------------------------------------------------- the parts

func _soft_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _ramp(peak: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, peak))
	g.add_point(0.7, Color(1, 1, 1, peak * 0.8))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _process_material(box: Vector3, gravity: float, swirl: float, peak: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.spread = 8.0
	pm.gravity = Vector3(0, gravity, 0)
	pm.turbulence_enabled = swirl > 0.0
	pm.turbulence_noise_strength = 0.6 + swirl * 0.6
	pm.turbulence_noise_scale = 5.0
	pm.turbulence_influence_min = 0.01 * swirl
	pm.turbulence_influence_max = 0.04 * swirl
	pm.color_ramp = _ramp(peak)
	return pm


func _system(amount: int, lifetime: float, mesh: Mesh, pm: ParticleProcessMaterial, height: float) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = lifetime
	ps.process_material = pm
	ps.draw_pass_1 = mesh
	ps.local_coords = false
	ps.emitting = false
	ps.amount_ratio = 0.0
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ps.visibility_aabb = AABB(Vector3(-90, -30, -90), Vector3(180, 70, 180))
	ps.position.y = height
	add_child(ps)
	return ps


func _dust_material(trails: bool, billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.use_particle_trails = trails
	# Dust right at the camera would smear across the view: it fades out within a few metres.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.5
	m.distance_fade_max_distance = 6.0
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.albedo_texture = _soft
	return m


## Fast lines of dust, each drawing a short trail behind it.
func _streaks() -> GPUParticles3D:
	var ribbon := RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_CROSS
	ribbon.size = 0.03
	ribbon.sections = 3
	ribbon.section_length = 0.1
	ribbon.material = _dust_material(true, false)
	var pm := _process_material(Vector3(AROUND, 1.6, AROUND), 0.0, 0.6, 0.28)
	pm.spread = 3.0
	var ps := _system(260, 1.6, ribbon, pm, 1.3)
	ps.trail_enabled = true
	ps.trail_lifetime = 0.14
	return ps


## Soft clouds of dust drifting past, growing as they go.
func _puffs() -> GPUParticles3D:
	var quad := QuadMesh.new()
	quad.material = _dust_material(false, true)
	var pm := _process_material(Vector3(AROUND * 1.3, 1.4, AROUND * 1.3), 0.12, 0.6, 0.34)
	pm.scale_min = 3.0
	pm.scale_max = 9.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.0))
	var curve := CurveTexture.new()
	curve.curve = grow
	pm.scale_curve = curve
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -15.0
	pm.angular_velocity_max = 15.0
	return _system(150, 6.0, quad, pm, 1.4)


## Sand snaking along close to the ground.
func _ground() -> GPUParticles3D:
	var ribbon := RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_CROSS
	ribbon.size = 0.07
	ribbon.sections = 5
	ribbon.section_length = 0.15
	ribbon.material = _dust_material(true, false)
	var pm := _process_material(Vector3(AROUND, 0.1, AROUND), -0.4, 1.4, 0.42)
	pm.spread = 4.0
	var ps := _system(300, 1.8, ribbon, pm, 0.15)
	ps.trail_enabled = true
	ps.trail_lifetime = 0.4
	return ps


## Grit and bits of dry grass, spinning as they tumble.
func _debris() -> GPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.03)
	var m := _dust_material(false, true)
	m.albedo_texture = null
	quad.material = m
	var pm := _process_material(Vector3(AROUND, 1.0, AROUND), -3.0, 2.5, 1.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.45, 0.3))
	g.set_color(1, Color(0.75, 0.68, 0.45))
	g.add_point(0.5, Color(0.42, 0.33, 0.22))
	var shades := GradientTexture1D.new()
	shades.gradient = g
	pm.color_initial_ramp = shades
	return _system(80, 2.6, quad, pm, 0.8)


# ---------------------------------------------------------------- dust devils

## Whirlwinds of dust: columns of soft puffs going round, leaning with the wind and wandering.
func _devils_for(count: int) -> void:
	# Where the player is looking, so they are seen.
	var ahead: Vector3 = world.player.forward()
	for i in count:
		var ang := atan2(ahead.x, ahead.z) + _rng.randf_range(-1.2, 1.2)
		var dist := _rng.randf_range(22.0, 55.0)
		var at: Vector3 = world.player.global_position + Vector3(sin(ang), 0, cos(ang)) * dist
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.instance_count = 72
		var quad := QuadMesh.new()
		mm.mesh = quad
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		var m := _dust_material(false, false)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = _soft
		node.material_override = m
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.top_level = true
		add_child(node)
		_devils.append({
			"node": node, "pos": at, "age": -_rng.randf_range(0.0, float(gust["length"]) * 0.4),
			"life": _rng.randf_range(8.0, 15.0), "height": _rng.randf_range(7.0, 16.0),
			"spin": _rng.randf_range(4.0, 8.0) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"radius": _rng.randf_range(0.5, 1.1), "wander": _rng.randf() * TAU,
		})


func _update_devils(delta: float, inside: bool, speed: float) -> void:
	var color: Color = (gust["color"] as Color).darkened(0.35)
	for d in _devils.duplicate():
		d["age"] = float(d["age"]) + delta
		var age := float(d["age"])
		var node: MultiMeshInstance3D = d["node"]
		node.visible = age > 0.0 and not inside
		if age <= 0.0:
			continue
		var life := float(d["life"])
		if age > life:
			node.queue_free()
			_devils.erase(d)
			continue
		var fade := minf(1.0, minf(age / 2.0, (life - age) / 2.0))
		d["wander"] = float(d["wander"]) + delta * 0.6
		var move := wind * speed * 0.35 + Vector3(sin(float(d["wander"])), 0, cos(float(d["wander"] * 1.3))) * 1.5
		var pos: Vector3 = (d["pos"] as Vector3) + move * delta
		pos.y = world.terrain.surface_y(pos.x, pos.z)
		d["pos"] = pos
		var mm: MultiMesh = node.multimesh
		var n := mm.instance_count
		var tall := float(d["height"]) * (0.4 + 0.6 * fade)
		for i in n:
			var f := float(i) / n
			var skirt := i < 14
			var h := 0.15 if skirt else pow(f, 1.4) * tall
			var turn := i * 2.4 + age * float(d["spin"]) * (1.4 - f * 0.6)
			var r := (float(d["radius"]) + f * tall * 0.17) * (0.8 + 0.2 * sin(i * 1.7))
			if skirt:
				r = 0.8 + fmod(i * 0.37, 1.0) * 2.4
			var lean := wind * f * tall * 0.18
			var at := pos + Vector3(cos(turn) * r, h, sin(turn) * r) + lean
			var size := (2.4 if skirt else 0.9 + f * 2.4)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
			var alpha := fade * (0.38 if skirt else 0.5 * (1.0 - f * 0.75))
			mm.set_instance_color(i, Color(color.r, color.g, color.b, alpha))


# ---------------------------------------------------------------- dust across the view

func _make_lens() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_lens = ColorRect.new()
	_lens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform vec2 drift = vec2(0.0);
uniform vec4 tint : source_color = vec4(0.85, 0.75, 0.6, 0.0);
void fragment() {
	vec2 uv = SCREEN_UV * vec2(1.8, 1.0);
	float a = texture(noise, uv * 0.9 + drift).r;
	float b = texture(noise, uv * 2.3 + drift * 1.7 + vec2(0.37, 0.11)).r;
	float d = smoothstep(0.3, 0.85, a * 0.6 + b * 0.4);
	COLOR = vec4(tint.rgb, tint.a * (0.3 + 0.7 * d));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	var noise := FastNoiseLite.new()
	noise.frequency = 0.006
	noise.fractal_octaves = 4
	tex.noise = noise
	mat.set_shader_parameter("noise", tex)
	_lens.material = mat
	_lens.visible = false
	layer.add_child(_lens)


func _update_lens(delta: float, amount: float, speed: float, color: Color) -> void:
	_lens.visible = amount > 0.005
	if not _lens.visible:
		return
	# The dust crosses the view the way the wind blows past the camera.
	var cam := get_viewport().get_camera_3d()
	var across := 0.0
	if cam != null:
		across = wind.dot(cam.global_transform.basis.x)
	_lens_drift += Vector2(-across, 0.15 * (1.0 - absf(across))) * speed * 0.004 * delta
	var mat := _lens.material as ShaderMaterial
	mat.set_shader_parameter("drift", _lens_drift)
	mat.set_shader_parameter("tint", Color(color.r, color.g, color.b, amount))
