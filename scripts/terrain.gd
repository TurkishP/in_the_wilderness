extends StaticBody3D
## The land for one stage.
##
## Each stage has a real site (latitude, longitude). The land around the camp is shaped from
## the region model in data/region.gd, at 25 real metres to one game metre and with heights
## raised by half, so the sea and the mountains stand where they do at that place:
##
##   - the ground: 600 m square, 5 m cells, with dunes added and collision. The camp at its
##     centre sits on a level patch.
##   - the backdrop: 5 km square, 50 m cells, no collision. It joins the ground without a seam
##     because both take their edge heights from the same samples.
##   - water: each sea in view, cut to the backdrop and laid at its own level.
##
## North is -Z and east is +X.

const Region := preload("res://data/region.gd")
const HALF := 300.0        # half-width of the ground
const CELL := 5.0
const FAR := 2500.0        # half-width of the backdrop
const FAR_CELL := 50.0
const GRID := 50.0         # spacing of the regional height samples (1.25 km on the real map)
const METRES := 25.0       # real metres per game metre
const GAIN := 1.5          # how much taller the regional relief is drawn

static var _grain: NoiseTexture2D
static var _bumps: NoiseTexture2D

var site_km := Vector2.ZERO
var site_elevation := 0.0
var size := 0                              # ground points per side
var heights := PackedFloat32Array()        # ground heights, row by row from north to south
var colors := PackedColorArray()           # ground colors at the same points
var waters: Array = []                     # [{name, y, outline: PackedVector2Array of (x, z)}]
var _regional := PackedFloat32Array()
var _rn := 0
var _dunes := FastNoiseLite.new()
var _crags := FastNoiseLite.new()
var _tint := FastNoiseLite.new()
var _amp := 4.0


func setup(stage: Dictionary) -> void:
	collision_layer = 1
	collision_mask = 0
	var seed_value := int(stage["seed"])
	_dunes.seed = seed_value
	_dunes.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dunes.frequency = 0.011
	_crags.seed = seed_value + 7
	_crags.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_crags.frequency = 0.0035
	_crags.fractal_octaves = 4
	_tint.seed = seed_value + 13
	_tint.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_tint.frequency = 0.02

	var site: Array = stage["site"]
	site_km = Region.to_km(float(site[0]), float(site[1]))
	site_elevation = Region.elevation(site_km)

	# Regional heights on a coarse grid; everything else interpolates these.
	_rn = int(FAR * 2.0 / GRID) + 1
	_regional.resize(_rn * _rn)
	for iz in _rn:
		for ix in _rn:
			var e := Region.elevation(real_km(-FAR + ix * GRID, -FAR + iz * GRID))
			_regional[iz * _rn + ix] = (e - site_elevation) / METRES * GAIN

	_find_water()
	var sand: Color = stage["sand"]
	var rock: Color = stage["rock"]
	var grass: Color = stage.get("grass", Color(0.62, 0.58, 0.36))
	var veg: Array = stage.get("veg", [1.0, 1.0, 1.0, 1.0])
	_build_ground(sand, rock, grass, float(veg[0]))
	_build_backdrop(sand, rock)
	_build_water()


## The real position, in km on the region model, of a point on this stage's map.
func real_km(x: float, z: float) -> Vector2:
	return site_km + Vector2(x, -z) * (METRES / 1000.0)


## Latitude and longitude of a point on this stage's map, as Vector2(lat, lon).
func lat_lon(x: float, z: float) -> Vector2:
	return Region.to_lat_lon(real_km(x, z))


## Regional height (relative to the camp) at any point within the backdrop.
func regional(x: float, z: float) -> float:
	var fx := clampf((x + FAR) / GRID, 0.0, _rn - 1.001)
	var fz := clampf((z + FAR) / GRID, 0.0, _rn - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - ix
	var v := fz - iz
	var a := _regional[iz * _rn + ix]
	var b := _regional[iz * _rn + ix + 1]
	var c := _regional[(iz + 1) * _rn + ix]
	var d := _regional[(iz + 1) * _rn + ix + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


## Height of the ground near the camp: regional shape plus dunes, level at the camp itself and
## exactly regional at the edge, where it meets the backdrop.
func _ground(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var edge := maxf(absf(x), absf(z))
	var settle := smoothstep(30.0, 110.0, d)
	var rise := smoothstep(30.0, 70.0, d) * (1.0 - smoothstep(HALF - 60.0, HALF - 5.0, edge))
	var dunes := (_dunes.get_noise_2d(x, z) + _dunes.get_noise_2d(x * 3.1 + 500.0, z * 3.1) * 0.25) * _amp
	return regional(x, z) * settle + dunes * rise


## Height of the backdrop: regional shape, roughened into crags on high ground.
func _far(x: float, z: float) -> float:
	var h := regional(x, z)
	var edge := maxf(absf(x), absf(z))
	var rough := clampf(h / 30.0, 0.0, 1.0) * smoothstep(HALF, HALF + 250.0, edge)
	return h + _crags.get_noise_2d(x, z) * 16.0 * rough


func _shade(x: float, z: float, h: float, steep: float, sand: Color, rock: Color, grass: Color, grass_amount: float, high_rock: bool) -> Color:
	var broad := _tint.get_noise_2d(x * 0.25, z * 0.25) * 0.5 + 0.5
	var fine := _tint.get_noise_2d(x, z) * 0.5 + 0.5
	var col := sand.darkened(0.2).lerp(sand.lightened(0.08), clampf(broad * 0.75 + fine * 0.35, 0.0, 1.0))
	col = col.lerp(grass, smoothstep(0.55, 0.8, fine * 0.6 + broad * 0.5) * clampf(grass_amount * 0.55, 0.0, 0.85))
	var rocky := smoothstep(0.16, 0.42, steep + (fine - 0.5) * 0.1)
	if high_rock:
		rocky = maxf(rocky, smoothstep(14.0, 55.0, h))
	col = col.lerp(rock.lerp(rock.darkened(0.3), fine), rocky)
	var wet := water_y(x, z)
	if wet > -1e8 and h < wet + 1.0:
		col = col.darkened(0.3)
	return col


func _material() -> StandardMaterial3D:
	if _grain == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.06
		n.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.78, 0.78, 0.78))
		ramp.set_color(1, Color(1, 1, 1))
		_grain = NoiseTexture2D.new()
		_grain.width = 256
		_grain.height = 256
		_grain.seamless = true
		_grain.noise = n
		_grain.color_ramp = ramp
		var n2 := FastNoiseLite.new()
		n2.seed = 3
		n2.frequency = 0.05
		n2.fractal_octaves = 3
		_bumps = NoiseTexture2D.new()
		_bumps.width = 256
		_bumps.height = 256
		_bumps.seamless = true
		_bumps.as_normal_map = true
		_bumps.bump_strength = 5.0
		_bumps.noise = n2
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = _grain
	m.normal_enabled = true
	m.normal_texture = _bumps
	m.normal_scale = 0.6
	m.roughness = 0.96
	# The mesh has no texture coordinates; the grain is laid on in world space.
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.14, 0.14, 0.14)
	return m


func _build_ground(sand: Color, rock: Color, grass: Color, grass_amount: float) -> void:
	var n := int(HALF * 2.0 / CELL)
	size = n + 1
	heights.resize(size * size)
	for iz in size:
		for ix in size:
			heights[iz * size + ix] = _ground(-HALF + ix * CELL, -HALF + iz * CELL)
	colors.resize(size * size)
	for iz in size:
		for ix in size:
			var x0 := clampi(ix - 1, 0, n)
			var x1 := clampi(ix + 1, 0, n)
			var z0 := clampi(iz - 1, 0, n)
			var z1 := clampi(iz + 1, 0, n)
			var gx := (heights[iz * size + x1] - heights[iz * size + x0]) / ((x1 - x0) * CELL)
			var gz := (heights[z1 * size + ix] - heights[z0 * size + ix]) / ((z1 - z0) * CELL)
			colors[iz * size + ix] = _shade(-HALF + ix * CELL, -HALF + iz * CELL, heights[iz * size + ix], sqrt(gx * gx + gz * gz), sand, rock, grass, grass_amount, false)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			# Corners of the cell: a b / d c, wound so the faces look up.
			var corners := [[ix, iz], [ix + 1, iz], [ix + 1, iz + 1], [ix, iz], [ix + 1, iz + 1], [ix, iz + 1]]
			for corner in corners:
				var i: int = corner[1] * size + corner[0]
				st.set_color(colors[i])
				st.add_vertex(Vector3(-HALF + corner[0] * CELL, heights[i], -HALF + corner[1] * CELL))
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = _material()
	add_child(mi)
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


func _build_backdrop(sand: Color, rock: Color) -> void:
	var n := int(FAR * 2.0 / FAR_CELL)
	var side := n + 1
	var h := PackedFloat32Array()
	h.resize(side * side)
	for iz in side:
		for ix in side:
			h[iz * side + ix] = _far(-FAR + ix * FAR_CELL, -FAR + iz * FAR_CELL)
	var tone := PackedColorArray()
	tone.resize(side * side)
	for iz in side:
		for ix in side:
			var x1 := mini(ix + 1, n)
			var z1 := mini(iz + 1, n)
			var gx := (h[iz * side + x1] - h[iz * side + maxi(ix - 1, 0)]) / (FAR_CELL * 2.0)
			var gz := (h[z1 * side + ix] - h[maxi(iz - 1, 0) * side + ix]) / (FAR_CELL * 2.0)
			tone[iz * side + ix] = _shade(-FAR + ix * FAR_CELL, -FAR + iz * FAR_CELL, h[iz * side + ix], sqrt(gx * gx + gz * gz), sand, rock, sand, 0.0, true)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := int(HALF / FAR_CELL)      # cells from the centre covered by the ground
	var mid := n / 2
	for iz in n:
		for ix in n:
			if ix >= mid - inner and ix < mid + inner and iz >= mid - inner and iz < mid + inner:
				continue
			var corners := [[ix, iz], [ix + 1, iz], [ix + 1, iz + 1], [ix, iz], [ix + 1, iz + 1], [ix, iz + 1]]
			for corner in corners:
				var i: int = corner[1] * side + corner[0]
				st.set_color(tone[i])
				st.add_vertex(Vector3(-FAR + corner[0] * FAR_CELL, h[i], -FAR + corner[1] * FAR_CELL))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = st.commit()
	mi.material_override = _material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Works out which seas reach into the backdrop, and where.
func _find_water() -> void:
	waters = []
	var square := PackedVector2Array([Vector2(-FAR, -FAR), Vector2(FAR, -FAR), Vector2(FAR, FAR), Vector2(-FAR, FAR)])
	for i in Region.sea_count():
		var outline := PackedVector2Array()
		for p in Region.sea_outline(i):
			var rel: Vector2 = (p - site_km) * (1000.0 / METRES)
			outline.append(Vector2(rel.x, -rel.y))
		for piece in Geometry2D.intersect_polygons(outline, square):
			if (piece as PackedVector2Array).size() >= 3:
				waters.append({
					"name": Region.sea_name(i),
					"y": (Region.sea_level(i) - site_elevation) / METRES * GAIN,
					"outline": piece,
				})


func _build_water() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.34, 0.5)
	m.roughness = 0.12
	m.metallic = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for w in waters:
		var outline: PackedVector2Array = w["outline"]
		var tris := Geometry2D.triangulate_polygon(outline)
		if tris.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in tris:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(outline[i].x, float(w["y"]), outline[i].y))
		var mi := MeshInstance3D.new()
		mi.name = "Water"
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Level of the water over (x, z), or a very large negative number where there is none.
func water_y(x: float, z: float) -> float:
	for w in waters:
		if Geometry2D.is_point_in_polygon(Vector2(x, z), w["outline"]):
			return float(w["y"])
	return -1e9


## Height of the rendered surface at (x, z). On the ground it matches the mesh exactly.
func surface_y(x: float, z: float) -> float:
	if absf(x) >= HALF or absf(z) >= HALF:
		return _far(x, z)
	var fx := (x + HALF) / CELL
	var fz := (z + HALF) / CELL
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - ix
	var v := fz - iz
	var ha := heights[iz * size + ix]
	var hb := heights[iz * size + ix + 1]
	var hc := heights[(iz + 1) * size + ix + 1]
	var hd := heights[(iz + 1) * size + ix]
	if u >= v:
		return ha + u * (hb - ha) + v * (hc - hb)
	return ha + u * (hc - hd) + v * (hd - ha)


## A top-down picture of the ground for the minimap: one pixel per ground point, lit from the
## north-west, with water painted in.
func map_image() -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for iz in size:
		for ix in size:
			var i := iz * size + ix
			var col := colors[i]
			var west := heights[iz * size + maxi(ix - 1, 0)]
			var north := heights[maxi(iz - 1, 0) * size + ix]
			var lit := clampf((heights[i] * 2.0 - west - north) * 0.06, -0.35, 0.35)
			col = col.lightened(lit) if lit >= 0.0 else col.darkened(-lit)
			var x := -HALF + ix * CELL
			var z := -HALF + iz * CELL
			var wet := water_y(x, z)
			if wet > -1e8 and heights[i] < wet:
				col = Color(0.16, 0.4, 0.56)
			img.set_pixel(ix, iz, col)
	return img
