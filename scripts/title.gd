extends Node
## The title screen: the name of the game over a view of Mount Sinai from the plain below it, in
## the evening, with the camp spread over the plain and the cloud on the mountain's top
## (Exodus 19:16-18, 24:15-16). Below, the choice: a new journey, or the saved one.
##
## The view is built here in code and is not part of any stage: granite peaks from layered noise,
## drawn flat-shaded like the rest of the game, the camp as hundreds of small tents, and the cloud
## pillar from the game made wide and low over the summit. The camera drifts slowly.

signal chosen(load_save: bool, path: String)

const CloudScript := preload("res://scripts/cloud_pillar.gd")
const Stages := preload("res://data/stages.gd")
const Ui := preload("res://scripts/ui.gd")
const SUMMIT := Vector3(150.0, 0.0, -3700.0)   # Jebel Musa, as seen from the plain
const CAMERA := Vector3(-150.0, 9.0, 240.0)
const SAND := Color(0.8, 0.68, 0.5)
const GRANITE := Color(0.6, 0.36, 0.25)
const GRANITE_DARK := Color(0.36, 0.21, 0.16)

var world
var buttons := {}            # name -> Button
var mountain: MeshInstance3D
var _scene: Node3D
var _camera: Camera3D
var _ui: CanvasLayer
var _fade: ColorRect
var _t := 0.0
var _kept := {}              # the world's light and sky, put back when the title closes
var _ridges := FastNoiseLite.new()
var _dunes := FastNoiseLite.new()
var _busy := false


func open(w) -> void:
	world = w
	_ridges.seed = 1491
	_ridges.frequency = 0.0011
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 5
	_dunes.seed = 77
	_dunes.frequency = 0.004
	_build_scene()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_restore_light()
	if is_instance_valid(_scene):
		_scene.queue_free()
	if is_instance_valid(_ui):
		_ui.queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _camera != null:
		# A slow drift along the plain, always looking up at the mountain.
		_camera.position = CAMERA + Vector3(sin(_t * 0.05) * 45.0, sin(_t * 0.07) * 2.0, cos(_t * 0.04) * 20.0)
		_camera.look_at(SUMMIT + Vector3(-120.0, 640.0, 0.0))


# ---------------------------------------------------------------- the view

func _build_scene() -> void:
	_scene = Node3D.new()
	world.add_child(_scene)
	_light()
	mountain = MeshInstance3D.new()
	mountain.mesh = _land()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mountain.material_override = m
	_scene.add_child(mountain)
	_camp()
	_foreground()
	var cloud = CloudScript.new()
	_scene.add_child(cloud)
	cloud.build(150.0, 6.0, 16.0, 19)
	cloud.scale = Vector3(11.0, 2.2, 11.0)
	cloud.position = Vector3(SUMMIT.x, _height(SUMMIT.x, SUMMIT.z) - 160.0, SUMMIT.z)
	_camera = Camera3D.new()
	_camera.fov = 48.0
	_camera.far = 20000.0
	_scene.add_child(_camera)
	_camera.position = CAMERA
	_camera.current = true
	_process(0.0)


## Evening light from the south-west, a warm sky, and a haze thin enough for mountains kilometres
## away. The stage's own light is kept and put back on close.
func _light() -> void:
	var env: Environment = world.environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	_kept = {
		"fog": env.fog_density, "fog_color": env.fog_light_color, "sun": world.sun.rotation_degrees,
		"sun_color": world.sun.light_color, "sun_energy": world.sun.light_energy,
		"top": sky.sky_top_color, "horizon": sky.sky_horizon_color, "ground": sky.ground_horizon_color,
	}
	world.daylight.held = true
	env.fog_density = 0.00006
	env.fog_light_color = Color(0.93, 0.78, 0.62)
	world.sun.rotation_degrees = Vector3(-13.0, -42.0, 0.0)
	world.sun.light_color = Color(1.0, 0.8, 0.58)
	world.sun.light_energy = 1.35
	sky.sky_top_color = Color(0.27, 0.42, 0.72)
	sky.sky_horizon_color = Color(0.96, 0.78, 0.58)
	sky.ground_horizon_color = Color(0.9, 0.74, 0.56)


func _restore_light() -> void:
	if _kept.is_empty():
		return
	var env: Environment = world.environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	env.fog_density = _kept["fog"]
	env.fog_light_color = _kept["fog_color"]
	world.sun.rotation_degrees = _kept["sun"]
	world.sun.light_color = _kept["sun_color"]
	world.sun.light_energy = _kept["sun_energy"]
	sky.sky_top_color = _kept["top"]
	sky.sky_horizon_color = _kept["horizon"]
	sky.ground_horizon_color = _kept["ground"]
	world.daylight.held = false
	world.daylight.apply(Game.clock, true)
	_kept = {}


## The height of the land: a sandy plain rising into a wide granite massif with Jebel Musa on its
## front, a higher peak behind it, and further ranges beyond.
func _height(x: float, z: float) -> float:
	var d := -z
	var h := _dunes.get_noise_2d(x, z) * 2.5
	var ridge := (_ridges.get_noise_2d(x, z) + 1.0) * 0.5
	var massif := smoothstep(1700.0, 3300.0, d) * exp(-pow(x - 200.0, 2.0) / (2.0 * 2800.0 * 2800.0))
	h += massif * (160.0 + 560.0 * ridge)
	h += 600.0 * exp(-(pow(x - SUMMIT.x, 2.0) + pow(d + SUMMIT.z, 2.0)) / (2.0 * 430.0 * 430.0))
	h += 780.0 * exp(-(pow(x + 1150.0, 2.0) + pow(d - 5700.0, 2.0)) / (2.0 * 650.0 * 650.0))
	h += smoothstep(5200.0, 8500.0, d) * (350.0 + 650.0 * ridge)
	return h


## The land as flat-shaded triangles: sand on the plain, red granite on the slopes, darker where
## they are steep.
func _land() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -7000.0
	var z0 := -10500.0
	var cols := 170
	var rows := 140
	var cw := 14000.0 / cols
	var ch := 11300.0 / rows
	for j in rows:
		for i in cols:
			var p := [
				Vector3(x0 + i * cw, 0, z0 + j * ch), Vector3(x0 + (i + 1) * cw, 0, z0 + j * ch),
				Vector3(x0 + (i + 1) * cw, 0, z0 + (j + 1) * ch), Vector3(x0 + i * cw, 0, z0 + (j + 1) * ch),
			]
			for k in 4:
				var q: Vector3 = p[k]
				q.y = _height(q.x, q.z)
				p[k] = q
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = p[tri[0]]
				var b: Vector3 = p[tri[1]]
				var c: Vector3 = p[tri[2]]
				var n := (b - a).cross(c - a).normalized()
				if n.y < 0.0:
					n = -n
				var mid := (a + b + c) / 3.0
				var steep := 1.0 - n.y
				var rock := smoothstep(25.0, 140.0, mid.y)
				var col := SAND.lerp(GRANITE, rock).lerp(GRANITE_DARK, clampf(steep * 1.6, 0.0, 1.0) * rock)
				col = col.lightened(_dunes.get_noise_2d(mid.x * 3.0, mid.z * 3.0) * 0.06)
				for v in [a, c, b]:
					st.set_color(col)
					st.set_normal(n)
					st.add_vertex(v)
	return st.commit()


## The camp on the plain below the mountain: rows of small tents, dark goat hair and pale linen.
func _camp() -> void:
	var tent := PrismMesh.new()
	tent.size = Vector3(6.0, 3.2, 4.5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tent
	mm.instance_count = 420
	var rng := RandomNumberGenerator.new()
	rng.seed = 1491
	var shades := [Color(0.2, 0.17, 0.15), Color(0.82, 0.76, 0.64), Color(0.62, 0.5, 0.36), Color(0.44, 0.33, 0.24)]
	for i in mm.instance_count:
		var x := rng.randf_range(-900.0, 700.0)
		var z := rng.randf_range(-1500.0, -600.0)
		var s := rng.randf_range(0.7, 1.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, _height(x, z) + 1.5 * s, z)))
		mm.set_instance_color(i, shades[rng.randi() % shades.size()])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	node.material_override = m
	_scene.add_child(node)


## Near the camera: scattered boulders and a few acacias, dark against the evening plain.
func _foreground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = rock
	mm.instance_count = 140
	for i in mm.instance_count:
		var ang := rng.randf_range(-1.4, 1.4)
		var dist := rng.randf_range(25.0, 700.0)
		var x := CAMERA.x + sin(ang) * dist
		var z := CAMERA.z - cos(ang) * dist
		var s := rng.randf_range(0.6, 3.2) * (1.0 + dist / 400.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(1.0, 1.8), s * rng.randf_range(0.5, 0.9), s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, _height(x, z), z)))
		mm.set_instance_color(i, GRANITE.darkened(rng.randf_range(0.0, 0.35)))
	var rocks := MultiMeshInstance3D.new()
	rocks.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	rocks.material_override = m
	_scene.add_child(rocks)
	for at in [Vector3(-230.0, 0.0, 150.0), Vector3(40.0, 0.0, 95.0), Vector3(-420.0, 0.0, -60.0)]:
		var tree := Node3D.new()
		tree.position = Vector3(at.x, _height(at.x, at.z), at.z)
		var trunk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.25
		cyl.bottom_radius = 0.45
		cyl.height = 5.0
		cyl.radial_segments = 6
		trunk.mesh = cyl
		trunk.position.y = 2.5
		trunk.rotation.z = 0.12
		var bark := StandardMaterial3D.new()
		bark.albedo_color = Color(0.3, 0.22, 0.16)
		trunk.material_override = bark
		tree.add_child(trunk)
		var crown := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 4.2
		disc.bottom_radius = 3.4
		disc.height = 1.1
		disc.radial_segments = 9
		crown.mesh = disc
		crown.position.y = 5.3
		var leaves := StandardMaterial3D.new()
		leaves.albedo_color = Color(0.36, 0.42, 0.2)
		crown.material_override = leaves
		tree.add_child(crown)
		_scene.add_child(tree)


# ---------------------------------------------------------------- the words and the choice

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(root)
	# Darker toward the bottom left, so the menu reads over the plain.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.03, 0.02, 0.7))
	g.set_color(1, Color(0.05, 0.03, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 1.0)
	gt.fill_to = Vector2(0.55, 0.35)
	shade.texture = gt
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	head.offset_left = -700
	head.offset_right = 700
	head.offset_top = 70
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	var serif := Ui.font()
	var title := _label("IN THE WILDERNESS", Ui.font("display"), 96, Color(0.98, 0.87, 0.6))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.2, 0.11, 0.05, 0.85))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 5)
	head.add_child(title)
	var ornament := Ornament.new()
	ornament.custom_minimum_size = Vector2(560, 34)
	ornament.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(ornament)
	var italic := Ui.font("italic")
	var sub := _label("Forty years from the Red Sea to the Jordan", italic, 30, Color(1.0, 0.95, 0.85))
	sub.add_theme_constant_override("outline_size", 8)
	sub.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.04, 0.7))
	head.add_child(sub)

	var menu := VBoxContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	menu.offset_left = 110
	menu.offset_top = -480
	menu.offset_right = 520
	menu.offset_bottom = -90
	menu.add_theme_constant_override("separation", 12)
	root.add_child(menu)
	buttons["new"] = _button(menu, "New journey", serif, _choose.bind(false))
	buttons["load"] = _button(menu, "Continue the journey", serif, _choose.bind(true))
	buttons["saves"] = _button(menu, "Saved journeys", serif, _saves)
	var saved := Game.peek_save()
	var note := _label("", italic, 19, Color(1.0, 0.92, 0.75, 0.9))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if saved.is_empty():
		buttons["load"].disabled = true
		buttons["saves"].disabled = true
		note.text = "   No journey saved yet. Sleep in your tent to save."
	else:
		var st: Dictionary = Stages.LIST[clampi(int(saved.get("stage_index", 0)), 0, Stages.LIST.size() - 1)]
		note.text = "   %s  ·  %s  ·  %s" % [st.get("year", ""), st["name"], st["place"]]
	menu.add_child(note)
	buttons["settings"] = _button(menu, "Settings", serif, _settings)
	buttons["quit"] = _button(menu, "Quit", serif, func() -> void: world.quit_game())

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	var tw := _fade.create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.4)


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(parent: Control, text: String, font: Font, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "  " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 56)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.5))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.8, 0.4))
	b.add_theme_color_override("font_disabled_color", Color(0.7, 0.66, 0.6, 0.55))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.05, 0.03, 0.35 if state == "normal" or state == "disabled" else 0.7)
		sb.border_color = Color(0.85, 0.66, 0.36, 0.0 if state == "normal" or state == "disabled" else 0.9)
		sb.border_width_left = 4
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 14
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Leaves the title: a new journey, or (`load_save`) the save at `path`, the newest if "".
func _choose(load_save: bool, path: String = "") -> void:
	if _busy:
		return
	_busy = true
	var tw := _fade.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	await tw.finished
	close()
	chosen.emit(load_save, path)


func _settings() -> void:
	world.hud.open_settings(func() -> void: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)


## The list of saves (the menu's page); picking one goes on from it.
func _saves() -> void:
	world.hud.menu.open("saves", func() -> void: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE, func(path: String) -> void: _choose(true, path))


## A thin rule with a small mountain in the middle, under the name.
class Ornament extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var gold := Color(0.95, 0.8, 0.5, 0.95)
		var dark := Color(0.2, 0.11, 0.05, 0.6)
		for o in [Vector2(1, 2), Vector2.ZERO]:
			var col := dark if o != Vector2.ZERO else gold
			draw_line(Vector2(10, c.y) + o, Vector2(c.x - 34, c.y) + o, col, 2.0)
			draw_line(Vector2(c.x + 34, c.y) + o, Vector2(size.x - 10, c.y) + o, col, 2.0)
			draw_polyline(PackedVector2Array([c + Vector2(-26, 9) + o, c + Vector2(-8, -9) + o, c + Vector2(0, -2) + o,
				c + Vector2(10, -13) + o, c + Vector2(26, 9) + o]), col, 2.0)
			draw_circle(c + Vector2(10, -19) + o, 2.5, col)
