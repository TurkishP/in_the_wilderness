extends Node3D
## Rocks, dry grass, bushes and trees for one stage.
##
## Each kind is one low-poly mesh drawn many times in a single batch (a MultiMesh), so a few
## thousand plants cost little. Plants gather in patches, as they do along dry stream beds.
## How much of each kind there is comes from the stage's "veg" numbers:
## [grass, bushes, trees, rocks], where 1.0 is an average stretch of wilderness.

const SPREAD := 285.0     # plants are placed out to this distance from the camp

static var _rocks: Array = []
static var _tuft: ArrayMesh
static var _bush: ArrayMesh
static var _acacia: ArrayMesh

var counts := {"grass": 0, "bushes": 0, "trees": 0, "rocks": 0, "solid": 0}
var clear := 30.0         # nothing is placed this close to the middle of the camp


func build(stage: Dictionary, rng: RandomNumberGenerator, terrain, keep_clear: float = 30.0) -> void:
	clear = keep_clear
	_make_meshes()
	var veg: Array = stage.get("veg", [1.0, 1.0, 1.0, 1.0])
	var rock_c: Color = stage["rock"]
	var grass_c: Color = stage.get("grass", Color(0.62, 0.58, 0.36))
	var patches := FastNoiseLite.new()
	patches.seed = int(stage["seed"]) + 31
	patches.frequency = 0.012

	# Dry grass, thick inside the patches and absent between them.
	var xf: Array = []
	var tint: Array = []
	for i in int(2600 * float(veg[0])):
		var p := _spot(rng, terrain)
		if p == Vector3.INF or patches.get_noise_2d(p.x, p.z) < 0.02:
			continue
		var s := rng.randf_range(0.7, 1.7)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), p))
		tint.append(grass_c.lerp(Color(0.78, 0.72, 0.45), rng.randf()).darkened(rng.randf() * 0.15))
	_batch("Grass", _tuft, xf, tint, true)
	counts["grass"] = xf.size()

	# Bushes: mostly small, a few as tall as a man.
	xf = []
	tint = []
	for i in int(240 * float(veg[1])):
		var p := _spot(rng, terrain)
		if p == Vector3.INF or patches.get_noise_2d(p.x, p.z) < -0.15:
			continue
		var roll := rng.randf()
		var s := rng.randf_range(0.35, 0.7)
		if roll > 0.9:
			s = rng.randf_range(1.4, 2.2)
		elif roll > 0.6:
			s = rng.randf_range(0.7, 1.3)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.0), s)), p))
		tint.append(Color(0.36, 0.42, 0.26).lerp(Color(0.52, 0.46, 0.3), rng.randf()))
	_batch("Bushes", _bush, xf, tint, false)
	counts["bushes"] = xf.size()

	# Acacias, with a trunk the player cannot walk through.
	xf = []
	for i in int(26 * float(veg[2])):
		var p := _spot(rng, terrain)
		if p == Vector3.INF:
			continue
		var s := rng.randf_range(0.8, 1.5)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		_solid(p + Vector3(0, 1.0 * s, 0), Vector3(0.35 * s, 2.0 * s, 0.35 * s))
	_batch("Trees", _acacia, xf, [], false)
	counts["trees"] = xf.size()

	# Rocks in three shapes: many stones, some boulders. Boulders are solid.
	for shape in _rocks.size():
		xf = []
		tint = []
		for i in int(95 * float(veg[3])):
			var p := _spot(rng, terrain, 0.0)
			if p == Vector3.INF:
				continue
			var roll := rng.randf()
			var s := rng.randf_range(0.15, 0.5)
			if roll > 0.86:
				s = rng.randf_range(1.5, 3.4)
			elif roll > 0.55:
				s = rng.randf_range(0.5, 1.4)
			var squash := Vector3(s * rng.randf_range(0.8, 1.5), s * rng.randf_range(0.6, 1.1), s * rng.randf_range(0.8, 1.5))
			var basis := Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))).scaled(squash)
			xf.append(Transform3D(basis, p + Vector3(0, squash.y * 0.25, 0)))
			tint.append(rock_c.darkened(rng.randf_range(0.0, 0.3)))
			if s > 1.5:
				_solid(p + Vector3(0, squash.y * 0.35, 0), squash * 1.35)
		_batch("Rocks%d" % shape, _rocks[shape], xf, tint, false)
		counts["rocks"] += xf.size()


## A random place for a plant: on dry land, outside the camp. Vector3.INF if the try landed
## in water or too near the camp.
func _spot(rng: RandomNumberGenerator, terrain, sink: float = 0.02) -> Vector3:
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * SPREAD
	if r < clear:
		return Vector3.INF
	var x := sin(a) * r
	var z := cos(a) * r
	var y: float = terrain.surface_y(x, z)
	if y < float(terrain.water_y(x, z)) + 0.3:
		return Vector3.INF
	return Vector3(x, y - sink, z)


func _batch(batch_name: String, mesh: Mesh, xforms: Array, tints: Array, two_sided: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not tints.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, tints[i])
	var node := MultiMeshInstance3D.new()
	node.name = batch_name
	node.multimesh = mm
	if mm.use_colors:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.95
		if two_sided:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = m
	add_child(node)


func _solid(center: Vector3, box: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box
	cs.shape = shape
	sb.add_child(cs)
	add_child(sb)
	sb.position = center
	counts["solid"] += 1


# ---------------------------------------------------------------- meshes, made once

static func _make_meshes() -> void:
	if _tuft != null:
		return
	for i in 3:
		_rocks.append(_rock_mesh(40 + i))
	_tuft = _tuft_mesh()
	_bush = _bush_mesh()
	_acacia = _acacia_mesh()


## A lumpy stone: a coarse sphere with every corner pushed in or out, shaded in flat facets.
static func _rock_mesh(seed_value: int) -> ArrayMesh:
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 8
	ball.rings = 5
	var arrays := ball.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var lumps := FastNoiseLite.new()
	lumps.seed = seed_value
	lumps.frequency = 0.9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		var v := verts[i]
		var p := v * (1.0 + lumps.get_noise_3dv(v * 1.3) * 0.45)
		p.y *= 0.7
		st.set_color(Color.WHITE)
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## A tuft of dry grass: a handful of thin blades leaning outward, darker at the root.
static func _tuft_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var a := rng.randf() * TAU
		var h := rng.randf_range(0.25, 0.55)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * 0.03
		var root := dir * rng.randf_range(0.0, 0.08)
		var tip := root + dir * rng.randf_range(0.1, 0.45) * h + Vector3(0, h, 0)
		for corner in [[root - side, Color(0.6, 0.55, 0.4)], [root + side, Color(0.6, 0.55, 0.4)], [tip, Color.WHITE]]:
			st.set_color(corner[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(corner[0])
	return st.commit()


## Adds a sphere to `st` as flat facets: moved, squashed, and tinted.
static func _add_blob(st: SurfaceTool, center: Vector3, radii: Vector3, tint: Color, segments: int = 7, rings: int = 4) -> void:
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = segments
	ball.rings = rings
	var arrays := ball.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_color(tint)
		st.add_vertex(center + verts[i] * radii)


## A desert bush: a few squashed lumps sitting on the ground.
static func _bush_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_blob(st, Vector3(0, 0.38, 0), Vector3(0.55, 0.45, 0.55), Color.WHITE)
	_add_blob(st, Vector3(0.38, 0.28, 0.12), Vector3(0.38, 0.32, 0.4), Color(0.86, 0.86, 0.86))
	_add_blob(st, Vector3(-0.3, 0.26, -0.24), Vector3(0.4, 0.3, 0.36), Color(0.92, 0.92, 0.92))
	_add_blob(st, Vector3(-0.05, 0.6, 0.2), Vector3(0.3, 0.26, 0.3), Color(1.0, 1.0, 1.0))
	st.generate_normals()
	return st.commit()


## An acacia: a leaning trunk that forks, under a wide flat crown.
static func _acacia_mesh() -> ArrayMesh:
	var wood := Color(0.36, 0.26, 0.18)
	var leaf := Color(0.4, 0.47, 0.25)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_limb(st, Vector3(0, 0, 0), Vector3(0.18, 1.5, 0.05), 0.13, 0.09, wood)
	_add_limb(st, Vector3(0.18, 1.5, 0.05), Vector3(0.75, 2.6, 0.2), 0.09, 0.05, wood)
	_add_limb(st, Vector3(0.18, 1.5, 0.05), Vector3(-0.55, 2.55, -0.25), 0.08, 0.045, wood)
	_add_blob(st, Vector3(0.6, 2.8, 0.15), Vector3(1.7, 0.3, 1.5), leaf, 9, 4)
	_add_blob(st, Vector3(-0.6, 2.72, -0.3), Vector3(1.3, 0.26, 1.2), leaf.darkened(0.12), 9, 4)
	_add_blob(st, Vector3(0.1, 3.0, -0.1), Vector3(0.9, 0.2, 0.9), leaf.lightened(0.08), 9, 4)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	return mesh


## Adds a tapering six-sided branch from `a` to `b`.
static func _add_limb(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, tint: Color) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3(0.3, 0.1, 0.9)).normalized()
	var v := axis.cross(u)
	var sides := 6
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := a + (u * cos(a0) + v * sin(a0)) * ra
		var p1 := a + (u * cos(a1) + v * sin(a1)) * ra
		var q0 := b + (u * cos(a0) + v * sin(a0)) * rb
		var q1 := b + (u * cos(a1) + v * sin(a1)) * rb
		for p in [p0, q0, p1, p1, q0, q1]:
			st.set_color(tint)
			st.add_vertex(p)
