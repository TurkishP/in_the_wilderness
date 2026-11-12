extends StaticBody3D
## Low-poly dune terrain with matching collision. Flat around the origin, where the camp stands.

const HALF := 300.0
const CELL := 5.0

var noise := FastNoiseLite.new()
var amp := 5.0
var flat_radius := 30.0


func setup(seed_value: int, sand: Color) -> void:
	collision_layer = 1
	collision_mask = 0
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.011
	var n := int(HALF * 2.0 / CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var x0 := -HALF + ix * CELL
			var z0 := -HALF + iz * CELL
			var a := Vector3(x0, _h(x0, z0), z0)
			var b := Vector3(x0 + CELL, _h(x0 + CELL, z0), z0)
			var c := Vector3(x0 + CELL, _h(x0 + CELL, z0 + CELL), z0 + CELL)
			var d := Vector3(x0, _h(x0, z0 + CELL), z0 + CELL)
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Game.mat(sand)
	add_child(mi)
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)

	# A wide sand floor below the dunes hides the edge of the terrain mesh.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(4000.0, 4000.0)
	var fm := MeshInstance3D.new()
	fm.mesh = floor_mesh
	fm.material_override = Game.mat(sand)
	fm.position.y = -amp * 1.3
	add_child(fm)


## Noise height, faded to zero near the origin.
func _h(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var f := clampf((d - flat_radius) / 40.0, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var h := noise.get_noise_2d(x, z) * amp + noise.get_noise_2d(x * 3.1 + 500.0, z * 3.1) * amp * 0.25
	return h * f


## Height of the rendered surface at (x, z); matches the mesh triangles exactly.
func surface_y(x: float, z: float) -> float:
	var fx := (x + HALF) / CELL
	var fz := (z + HALF) / CELL
	var ix := floorf(fx)
	var iz := floorf(fz)
	var u := fx - ix
	var v := fz - iz
	var x0 := -HALF + ix * CELL
	var z0 := -HALF + iz * CELL
	var ha := _h(x0, z0)
	var hb := _h(x0 + CELL, z0)
	var hc := _h(x0 + CELL, z0 + CELL)
	var hd := _h(x0, z0 + CELL)
	if u >= v:
		return ha + u * (hb - ha) + v * (hc - hb)
	return ha + u * (hc - hd) + v * (hd - ha)
