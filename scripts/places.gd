extends Node3D
## The special places of the land the scout is in (data/places.gd): where each lies (the same
## every visit), how the ground is shaped round it, what is built there, who guards it, and what
## it gives. A rest place fills the waterskin and heals; a landmark reads its passage once, with
## experience; a lair or ruin, once its guardians are dead, leaves its reward and stays cleared.

const Places := preload("res://data/places.gd")
const SceneryScript := preload("res://scripts/scenery.gd")
const WATER := Color(0.2, 0.42, 0.5)
const GRANITE := Color(0.52, 0.47, 0.45)
const SANDSTONE := Color(0.72, 0.52, 0.38)
const WOOD := Color(0.36, 0.26, 0.17)
const SEEN_NEAR := 10.0       # how much further than its radius a place is seen from

var world
## The places of this land: {def, p (Vector2 on the map), at (Vector3 on the ground), guards
## (their enemies), loot (pickups lying there), dir (toward the mountain or away from the camp),
## a, b (a brook's top and foot)}.
var list: Array = []
var _check := 0.0
static var _palm: ArrayMesh
static var _rough: StandardMaterial3D


# ================================================================ where the places lie

## Called by the terrain before it builds (terrain.setup): finds where each place of this land
## lies and returns how the ground is shaped for them.
func plan(terrain) -> Array:
	list = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world.stage["seed"]) * 13 + 5
	var stamps: Array = []
	for d in Places.for_stage(Game.land_index()):
		var e := {"def": d, "p": Vector2.INF, "guards": [], "loot": []}
		_find_spot(e, terrain, rng)
		if e["p"] == Vector2.INF:
			continue
		list.append(e)
		for g in d.get("ground", []):
			var s: Dictionary = (g as Dictionary).duplicate()
			s["at"] = e["p"]
			if s["kind"] == "flat":
				s["level"] = terrain._ground(e["p"].x, e["p"].y)
			elif s["kind"] == "gully":
				s["a"] = e["a"]
				s["b"] = e["b"]
			stamps.append(s)
	return stamps


func _find_spot(e: Dictionary, terrain, rng: RandomNumberGenerator) -> void:
	var where: Dictionary = e["def"]["where"]
	if where.has("sea"):
		var shore := _nearest_shore(terrain)
		if shore != Vector2.INF and shore.length() < 280.0:
			e["p"] = shore.normalized() * (shore.length() - float(where["sea"]))
			e["dir"] = Vector3(shore.normalized().x, 0, shore.normalized().y)
			# The shore lies beyond the usual bounds: the scout may walk out to it.
			world.walk_limit = maxf(world.walk_limit, e["p"].length() + 20.0)
			return
		where = {"dist": [140.0, 180.0]}
	if where.has("dist"):
		for i in 60:
			var a := rng.randf() * TAU
			var r := rng.randf_range(float(where["dist"][0]), float(where["dist"][1]))
			var p := Vector2(sin(a), cos(a)) * r
			if _free(p, 45.0) and terrain.water_y(p.x, p.y) < -1e8:
				e["p"] = p
				e["dir"] = Vector3(p.x, 0, p.y).normalized()
				return
		return
	var peak := _peak(terrain, 170.0)
	if where.has("high"):
		var best := -1e9
		for r in range(int(where["high"][0]), int(where["high"][1]) + 1, 8):
			for k in 36:
				var a := TAU * k / 36.0
				var p := Vector2(sin(a), cos(a)) * r
				var h: float = terrain._ground(p.x, p.y)
				if h > best and _free(p, 45.0):
					best = h
					e["p"] = p
		if e["p"] != Vector2.INF:
			e["dir"] = Vector3(e["p"].x, 0, e["p"].y).normalized()
		return
	if where.has("foot"):
		var base: float = terrain._ground(0.0, 0.0)
		for r in range(60, 190, 3):
			var p := peak * r
			if terrain._ground(p.x, p.y) - base >= float(where["foot"]) and _free(p, 40.0):
				e["p"] = p
				e["dir"] = Vector3(peak.x, 0, peak.y)
				return
		return
	if where.has("brook"):
		# Down the flank beside the mountain's own line, from ground this high to its foot.
		var base: float = terrain._ground(0.0, 0.0)
		var side := peak.rotated(0.45)
		var top := Vector2.INF
		var foot := Vector2.INF
		for r in range(190, 50, -3):
			var p := side * r
			var h: float = terrain._ground(p.x, p.y) - base
			if top == Vector2.INF and h <= float(where["brook"][0]):
				top = p
			if h <= float(where["brook"][1]):
				foot = p
				break
		if top != Vector2.INF and foot != Vector2.INF and top.distance_to(foot) > 15.0:
			e["a"] = top
			e["b"] = foot
			e["p"] = foot
			e["dir"] = Vector3(side.x, 0, side.y)


## The way toward the highest ground `reach` metres out from the camp, as a unit vector.
func _peak(terrain, reach: float) -> Vector2:
	var best := -1e9
	var dir := Vector2(0, -1)
	for k in 72:
		var a := TAU * k / 72.0
		var p := Vector2(sin(a), cos(a)) * reach
		var h: float = terrain._ground(p.x, p.y)
		if h > best:
			best = h
			dir = p.normalized()
	return dir


func _nearest_shore(terrain) -> Vector2:
	var best := Vector2.INF
	for w in terrain.waters:
		var o: PackedVector2Array = w["outline"]
		for k in o.size():
			var q := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, o[k], o[(k + 1) % o.size()])
			if q.length() < best.length():
				best = q
	return best


func _free(p: Vector2, gap: float) -> bool:
	for e in list:
		if e["p"] != Vector2.INF and (e["p"] as Vector2).distance_to(p) < gap:
			return false
	return true


## Circles the scenery keeps clear of: [centre, radius].
func keep_clear() -> Array:
	var out: Array = []
	for e in list:
		out.append([e["p"], float(e["def"].get("radius", 14.0)) + 8.0])
		if e.has("a"):
			for k in 6:
				out.append([(e["a"] as Vector2).lerp(e["b"], k / 5.0), 6.0])
	return out


# ================================================================ building them

func build() -> void:
	for e in list:
		var d: Dictionary = e["def"]
		var p: Vector2 = e["p"]
		e["at"] = world.ground(p.x, p.y)
		call("_build_" + str(d["build"]), e)
		var label := Game.label3d(str(d["name"]), 40, Color(1.0, 0.9, 0.62))
		label.position = e["at"] + Vector3(0, 5.0, 0)
		label.visibility_range_end = 90.0
		add_child(label)
		if _done(e):
			continue
		var mult: float = float(world.stage["mult"])
		for kind in d.get("guards", {}):
			for i in int(d["guards"][kind]):
				var a := TAU * i / maxf(1.0, float(d["guards"][kind])) + 0.7
				var g = world.spawn_enemy(str(kind), e["at"] + Vector3(cos(a), 0, sin(a)) * 6.0, mult, {})
				e["guards"].append(g)
		if d.has("unique"):
			var u: Dictionary = d["unique"]
			var opts := {"name": u["name"], "scale": u.get("scale", 1.25), "hp_mult": u.get("hp", 3.0), "dmg_mult": u.get("dmg", 1.4),
				"unique": true, "brave": true, "xp_mult": 3.0}
			if u.has("color"):
				opts["color"] = u["color"]
			var spot: Vector3 = e.get("lair", e["at"])
			var g = world.spawn_enemy(str(u["kind"]), spot, mult, opts)
			g.global_position = spot + Vector3(0, 0.3, 0)
			g.home = spot
			e["guards"].append(g)
		for l in d.get("loot", []):
			for i in int(l[1]):
				var a := TAU * i / maxf(1.0, float(l[1])) + 0.3
				e["loot"].append(world.spawn_pickup("item", str(l[0]), e["at"] + Vector3(cos(a), 0, sin(a)) * 3.5))


func _done(e: Dictionary) -> bool:
	return Game.places_done.has(str(e["def"]["id"]))


func _process(delta: float) -> void:
	var player = world.player
	if not is_instance_valid(player) or player.indoors or player.dead:
		return
	var pos: Vector3 = player.global_position
	for e in list:
		var d: Dictionary = e["def"]
		if not e.has("at"):
			continue
		var near := Vector2(pos.x - e["at"].x, pos.z - e["at"].z).length()
		# Resting: at water and shade, out of a fight, the scout heals.
		if d["kind"] == "rest" and near < float(d.get("radius", 14.0)) and not player.in_fight():
			Game.hp = minf(Game.max_hp, Game.hp + 5.0 * delta)
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.25
	for e in list:
		if not e.has("at"):
			continue
		var d: Dictionary = e["def"]
		var near := Vector2(pos.x - e["at"].x, pos.z - e["at"].z).length()
		if not Game.places_seen.has(str(d["id"])) and near < float(d.get("radius", 14.0)) + SEEN_NEAR:
			_arrive(e)
		var guarded: bool = d["kind"] == "lair" or d["kind"] == "ruin"
		if guarded and not _done(e) and not e["guards"].is_empty() and e["guards"].all(func(g) -> bool: return not is_instance_valid(g) or g.dead):
			_clear(e)


## The scout comes to a place for the first time: it is named, its passage read, and a landmark
## gives its experience.
func _arrive(e: Dictionary) -> void:
	var d: Dictionary = e["def"]
	Game.places_seen[str(d["id"])] = true
	var body := str(d["text"])
	if str(d["ref"]) != "":
		body = "[i]%s[/i]\n\n%s" % [d["ref"], body]
	if d["kind"] == "landmark" and not _done(e):
		Game.places_done[str(d["id"])] = true
		var got := Game.gain_xp(int(float(d.get("xp", 30)) * float(world.stage["mult"])))
		body += "\n\n[i]You gain %d experience.[/i]" % got
	elif d["kind"] == "rest":
		body += "\n\n[i]Here you can drink, fill your waterskin and rest.[/i]"
	world.hud.dialog(str(d["name"]), body, [["Go on", Callable()]])
	Game.play_sound("find", null, -6.0, 0.9)


## The guardians of a lair or ruin are all dead: it leaves its reward, and stays cleared.
func _clear(e: Dictionary) -> void:
	var d: Dictionary = e["def"]
	Game.places_done[str(d["id"])] = true
	var r: Dictionary = d.get("reward", {})
	var at: Vector3 = e.get("lair", e["at"])
	var items: Array = []
	if r.has("item"):
		var id := str(r["item"])
		if id == "rare":
			id = Game.roll_table("rare", int(world.stage["tier"]))
		if id != "":
			items.append(id)
	if r.has("loot"):
		items.append(str(r["loot"]))
	for i in items.size():
		world.spawn_pickup("item", items[i], at + Vector3(0.8 * i - 0.4, 0, 0.6))
	if r.has("bronze"):
		world.spawn_pickup("bronze", int(r["bronze"]), at + Vector3(-1.0, 0, -0.6))
	if r.has("silver"):
		world.spawn_pickup("silver", int(float(r["silver"]) * float(world.stage["mult"])), at + Vector3(1.0, 0, -0.6))
	var got := Game.gain_xp(int(float(d.get("xp", 40)) * float(world.stage["mult"])))
	Game.say("%s is cleared.  +%d experience." % [d["name"], got])
	Game.play_sound("find", null, 0.0, 0.8)


## Water at a rest place: the scout drinks and fills the waterskin.
func _drink(_node = null) -> void:
	Game.refill_water()
	Game.say("You drink, and fill your waterskin.")
	Game.play_sound("find", null, -10.0, 1.4)


# ================================================================ pieces

static func _stone_mat() -> StandardMaterial3D:
	if _rough == null:
		_rough = StandardMaterial3D.new()
		_rough.vertex_color_use_as_albedo = true
		_rough.vertex_color_is_srgb = true
		_rough.roughness = 0.95
	return _rough


## A rough lump of stone (or anything lumpy): flat-shaded, `radii` across, its middle at `at`.
func _lump(at: Vector3, radii: Vector3, color: Color, seed_value: int = 0, seg: int = 8, rings: int = 5) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	SceneryScript._add_blob(st, Vector3.ZERO, radii, color, seg, rings)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _stone_mat()
	mi.position = at
	mi.rotation.y = float(seed_value % 17) * 0.37
	add_child(mi)
	return mi


## A mass of rock `size` across (turned `turn`), solid as a block but broken along its top and
## ends by lumps, so it does not read as a box.
func _crag(center: Vector3, size: Vector3, turn: float, color: Color, seed_value: int) -> void:
	var basis := Basis(Vector3.UP, turn)
	_add(Game.mesh_box(size * Vector3(0.94, 0.96, 0.9), color, "stone"), center, Vector3(0, turn, 0))
	_box(size, center, turn)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(clampf(size.x * size.z / 5.0, 8, 24))
	for i in n:
		var u := rng.randf_range(-0.5, 0.5)
		var v := rng.randf_range(-0.5, 0.5)
		var on_top := rng.randf() < 0.55
		var local: Vector3
		if on_top:
			local = Vector3(u * size.x, 0.5 * size.y, v * size.z * 0.9)
		elif rng.randf() < 0.5:
			local = Vector3(0.5 * size.x * signf(u), rng.randf_range(-0.35, 0.4) * size.y, v * size.z * 0.9)
		else:
			local = Vector3(u * size.x, rng.randf_range(-0.35, 0.4) * size.y, 0.47 * size.z * signf(v))
		var r := minf(size.y, minf(size.x, size.z)) * rng.randf_range(0.16, 0.3)
		_lump(center + basis * local, Vector3(r * 1.35, r * 0.75, r), color.darkened(rng.randf() * 0.14), i, 6, 4)


func _add(mi: MeshInstance3D, at: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	mi.position = at
	mi.rotation = rot
	add_child(mi)
	return mi


func _solid(shape: Shape3D, at: Vector3, rot_y: float = 0.0) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	sb.position = at
	sb.rotation.y = rot_y
	add_child(sb)


func _box(size: Vector3, at: Vector3, rot_y: float = 0.0) -> void:
	var b := BoxShape3D.new()
	b.size = size
	_solid(b, at, rot_y)


func _pole(radius: float, height: float, at: Vector3) -> void:
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	_solid(c, at)


func _pool(at: Vector3, radius: float) -> void:
	_add(Game.mesh_cyl(radius + 0.45, radius + 0.55, 0.03, Color(0.36, 0.3, 0.22)), at + Vector3(0, 0.012, 0))
	_add(Game.mesh_cyl(radius, radius, 0.04, WATER, "", 0.12), at + Vector3(0, 0.03, 0))


## Running water from `a` to `b` on the ground: a strip, a little above it.
func _stream(a: Vector3, b: Vector3, width: float) -> void:
	var mid := (a + b) * 0.5
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var strip := Game.mesh_box(Vector3(width, 0.03, flat.length() + 0.4), WATER, "", 0.12)
	strip.position = mid + Vector3(0, 0.04, 0)
	strip.basis = Basis.looking_at((b - a).normalized(), Vector3.UP)
	add_child(strip)


func _point(e: Dictionary, key: String = "p") -> Vector3:
	var p: Vector2 = e[key]
	return world.ground(p.x, p.y)


## A date palm: a leaning, ringed trunk and a crown of drooping fronds (one mesh, shared).
static func _palm_mesh() -> ArrayMesh:
	if _palm == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var bark := Color(0.42, 0.32, 0.22)
		var top := Vector3(0.35, 6.2, 0.0)
		for k in 6:
			var a := top * (k / 6.0)
			var b := top * ((k + 1) / 6.0)
			SceneryScript._add_limb(st, a, b, 0.24 - k * 0.02, 0.22 - k * 0.02, bark.darkened(0.08 * (k % 2)))
		for k in 9:
			var ang := TAU * k / 9.0
			var out := Vector3(cos(ang), 0.0, sin(ang))
			SceneryScript._add_blob(st, top + out * 1.3 + Vector3(0, 0.15, 0), Vector3(1.4, 0.12, 0.38).rotated(Vector3.UP, -ang), Color(0.26, 0.44, 0.2).lightened(0.05 * (k % 3)), 6, 3)
			SceneryScript._add_blob(st, top + out * 2.4 - Vector3(0, 0.45, 0), Vector3(0.9, 0.1, 0.3).rotated(Vector3.UP, -ang), Color(0.3, 0.46, 0.22), 5, 3)
		SceneryScript._add_blob(st, top + Vector3(0, -0.35, 0), Vector3(0.45, 0.3, 0.45), Color(0.6, 0.36, 0.12), 6, 3)
		st.generate_normals()
		_palm = st.commit()
	return _palm


# ================================================================ what is built at each place

## Elim: twelve spring pools in a damp hollow, seventy palms round them.
func _build_oasis(e: Dictionary) -> void:
	var at: Vector3 = e["at"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(e["def"]["id"]))
	var pools: Array = []
	for i in 12:
		var a := TAU * i / 12.0 + rng.randf_range(-0.15, 0.15)
		var r := 4.5 + float(i % 3) * 2.6 + rng.randf()
		var p := Vector2(at.x, at.z) + Vector2(cos(a), sin(a)) * r
		pools.append(p)
		_pool(world.ground(p.x, p.y), rng.randf_range(0.8, 1.3))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _palm_mesh()
	var xf: Array = []
	var tries := 0
	while xf.size() < 70 and tries < 600:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(6.0, 27.0)
		var p := Vector2(at.x, at.z) + Vector2(cos(a), sin(a)) * r
		if pools.any(func(q) -> bool: return (q as Vector2).distance_to(p) < 2.2):
			continue
		var g: Vector3 = world.ground(p.x, p.y)
		var s := rng.randf_range(0.8, 1.2)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), g - Vector3(0, 0.05, 0)))
		_pole(0.24, 6.0, g + Vector3(0, 3.0, 0))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = m
	add_child(mmi)
	world._interactable("Drink at the springs of Elim", at + Vector3(0, 0.6, 0), 9.0, _drink)


## The shore of the crossing: chariots broken on the sand, wheels, shields and spears.
func _build_wreckage(e: Dictionary) -> void:
	var at: Vector3 = e["at"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(e["def"]["id"]))
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf()
		var c: Vector3 = world.ground(at.x + cos(a) * 6.0, at.z + sin(a) * 6.0)
		var turn := rng.randf() * TAU
		# The chariot's box lies on its side; one wheel still on its axle, one fallen flat.
		_add(Game.mesh_box(Vector3(1.3, 0.55, 1.0), WOOD.lightened(0.1), "wood"), c + Vector3(0, 0.5, 0), Vector3(0.2, turn, 1.25))
		_box(Vector3(1.0, 1.0, 1.2), c + Vector3(0, 0.5, 0), turn)
		var wheel := Game.mesh_cyl(0.48, 0.48, 0.08, WOOD, "wood")
		_add(wheel, c + Vector3(cos(turn), 0, sin(turn)) * 0.9 + Vector3(0, 0.48, 0), Vector3(PI * 0.5, turn, 0))
		_add(Game.mesh_cyl(0.48, 0.48, 0.08, WOOD.darkened(0.1), "wood"), c + Vector3(-sin(turn) * 1.4, 0.04, cos(turn) * 1.4), Vector3(0, rng.randf(), 0))
		_add(Game.mesh_cyl(0.035, 0.035, 2.4, WOOD, "wood"), c + Vector3(sin(turn) * 1.3, 0.05, -cos(turn) * 1.3), Vector3(0, turn, PI * 0.5))
	for k in 6:
		var p: Vector3 = world.ground(at.x + rng.randf_range(-9.0, 9.0), at.z + rng.randf_range(-9.0, 9.0))
		_add(Game.mesh_cyl(0.018, 0.02, 1.9, WOOD, "wood"), p + Vector3(0, 0.03, 0), Vector3(0, rng.randf() * TAU, PI * 0.5))
	for k in 5:
		var p: Vector3 = world.ground(at.x + rng.randf_range(-8.0, 8.0), at.z + rng.randf_range(-8.0, 8.0))
		_add(Game.mesh_cyl(0.34, 0.34, 0.05, Color(0.62, 0.5, 0.36), "hide"), p + Vector3(0, 0.06, 0), Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)))


## The rock in Horeb: a granite boulder split in two, a stream running from the cleft to a pool.
func _build_split_rock(e: Dictionary) -> void:
	var at: Vector3 = e["at"]
	var away: Vector3 = e["dir"]
	var side := Vector3(-away.z, 0, away.x)
	for s in [-1.0, 1.0]:
		var c: Vector3 = at + side * (2.5 * s) + Vector3(0, 2.2, 0)
		var tone := GRANITE.darkened(0.05 if s < 0.0 else 0.0)
		_lump(c, Vector3(2.0, 2.5, 2.3), tone, int(s * 5.0) + 7, 6, 4)
		_lump(c + side * (0.5 * s) + Vector3(0, 1.9, 0.3), Vector3(1.3, 1.1, 1.4), tone.lightened(0.04), 3, 6, 4)
		_lump(c + side * (1.1 * s) + Vector3(0, -1.1, -0.9), Vector3(1.5, 1.2, 1.4), tone.darkened(0.06), 5, 6, 4)
		_lump(c + away * 1.4 + Vector3(0, -1.4, 0), Vector3(1.0, 0.8, 0.9), tone, 9, 6, 4)
		_pole(2.0, 4.6, c - Vector3(0, -0.1, 0))
	# The water comes out of the cleft and runs downhill to a pool.
	var from: Vector3 = at + away * 1.5
	var to: Vector3 = at + away * 13.0
	var low := 1e9
	for k in 16:
		var dir := away.rotated(Vector3.UP, (k - 7.5) * 0.12)
		var p: Vector3 = world.ground(at.x + dir.x * 13.0, at.z + dir.z * 13.0)
		if p.y < low:
			low = p.y
			to = p
	var prev: Vector3 = world.ground(from.x, from.z)
	for k in range(1, 7):
		var q: Vector3 = from.lerp(to, k / 6.0)
		var g: Vector3 = world.ground(q.x, q.z)
		_stream(prev, g, 0.7)
		prev = g
	_pool(to, 1.8)
	world._interactable("Drink from the stream of the rock", to + Vector3(0, 0.6, 0), 4.0, _drink)
	world._interactable("Drink from the rock", at + away * 1.8 + Vector3(0, 0.6, 0), 3.0, _drink)


## The hill of the raised hands: on its top, the stone Moses sat on and an altar of uncut stones.
func _build_altar(e: Dictionary) -> void:
	var at: Vector3 = e["at"]
	_lump(at + Vector3(1.6, 0.28, 0.2), Vector3(0.55, 0.32, 0.45), GRANITE.lightened(0.08), 3)
	_box(Vector3(0.9, 0.55, 0.8), at + Vector3(1.6, 0.27, 0.2))
	var c := at + Vector3(-1.5, 0.0, 0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for layer in 3:
		for k in 4 - layer:
			var a := TAU * k / (4 - layer) + layer * 0.5
			var off := Vector3(cos(a), 0, sin(a)) * (0.42 - layer * 0.12)
			_lump(c + off + Vector3(0, 0.22 + layer * 0.36, 0), Vector3(0.36, 0.22, 0.32) * rng.randf_range(0.85, 1.1), Color(0.6, 0.55, 0.5).darkened(rng.randf() * 0.15), k + layer * 3)
	_box(Vector3(1.3, 1.1, 1.3), c + Vector3(0, 0.55, 0))


## The turquoise mines: a cliff of red sandstone with dark galleries cut into it, heaps of spoil,
## and Hathor's temple court of upright stones.
func _build_mines(e: Dictionary) -> void:
	var at: Vector3 = e["at"]
	var away: Vector3 = e["dir"]
	var side := Vector3(-away.z, 0, away.x)
	var turn := atan2(away.x, away.z)
	var wall_at: Vector3 = at + away * 10.0
	var wall_g: Vector3 = world.ground(wall_at.x, wall_at.z)
	_crag(wall_g + Vector3(0, 3.6, 0), Vector3(26.0, 8.0, 5.0), turn, SANDSTONE, 11)
	for k in 3:
		var mouth: Vector3 = wall_at + side * ((k - 1) * 7.0) - away * 2.52
		var g: Vector3 = world.ground(mouth.x, mouth.z)
		_add(Game.mesh_box(Vector3(1.5, 2.0, 0.06), Color(0.05, 0.04, 0.035)), g + Vector3(0, 1.0, 0), Vector3(0, turn, 0))
		var heap: Vector3 = mouth - away * 3.0 + side * 1.5
		_lump(world.ground(heap.x, heap.z) + Vector3(0, 0.25, 0), Vector3(2.0, 0.7, 1.4), SANDSTONE.lightened(0.15), k)
	# The temple court: low walls round a yard of standing stones.
	var court: Vector3 = at - side * 11.0
	var cg: Vector3 = world.ground(court.x, court.z)
	for s in [-1.0, 1.0]:
		var w1: Vector3 = court + side * (4.0 * s)
		_add(Game.mesh_box(Vector3(0.5, 0.45, 12.0), SANDSTONE.lightened(0.05), "stone"), world.ground(w1.x, w1.z) + Vector3(0, 0.22, 0), Vector3(0, turn, 0))
		var w2: Vector3 = court + away * (6.0 * s)
		_add(Game.mesh_box(Vector3(8.0, 0.45, 0.5), SANDSTONE.lightened(0.05), "stone"), world.ground(w2.x, w2.z) + Vector3(0, 0.22, 0), Vector3(0, turn, 0))
	for k in 8:
		var row := -1.0 if k % 2 == 0 else 1.0
		var spot: Vector3 = court + side * (row * 1.6) + away * ((k / 2) * 2.6 - 3.9)
		var g: Vector3 = world.ground(spot.x, spot.z)
		_add(Game.mesh_box(Vector3(0.55, 2.1, 0.2), Color(0.8, 0.66, 0.5), "stone"), g + Vector3(0, 1.05, 0), Vector3(0, turn, 0))
		_box(Vector3(0.55, 2.1, 0.25), g + Vector3(0, 1.05, 0), turn)
	e["lair"] = cg


## The bounds of the mountain: a line of set stones along its foot, across the way up.
func _build_bounds(e: Dictionary) -> void:
	var at: Vector3 = e["at"]
	var toward: Vector3 = e["dir"]
	var side := Vector3(-toward.z, 0, toward.x)
	for k in 21:
		var s := (k - 10) * 3.0
		var p: Vector3 = at + side * s
		var g: Vector3 = world.ground(p.x, p.z)
		_lump(g + Vector3(0, 0.4, 0), Vector3(0.32, 0.55, 0.28), GRANITE.lightened(0.1), k)
		_pole(0.3, 1.0, g + Vector3(0, 0.5, 0))


## The brook from the mountain: water running down a gully in steps, into pools.
func _build_brook(e: Dictionary) -> void:
	var top: Vector3 = _point(e, "a")
	var foot: Vector3 = _point(e, "b")
	var n := maxi(3, int(top.distance_to(foot) / 3.0))
	var prev := top
	for k in range(1, n + 1):
		var q := top.lerp(foot, float(k) / n)
		var g: Vector3 = world.ground(q.x, q.z)
		_stream(prev, g, 0.9)
		if k % 5 == 0:
			_pool(g, 1.2)
		prev = g
	_pool(foot, 2.0)
	for k in 6:
		var a := TAU * k / 6.0
		_lump(foot + Vector3(cos(a) * 2.9, 0.2, sin(a) * 2.9), Vector3(0.5, 0.35, 0.45), GRANITE, k)
	world._interactable("Drink from the brook", foot + Vector3(0, 0.6, 0), 4.5, _drink)


## The grey leopard's ledge: a shelf of rock high on the flank, a cave behind it, and broken
## rock to climb up by.
func _build_ledge(e: Dictionary) -> void:
	var at: Vector3 = e["at"]
	var toward_camp := -(e["dir"] as Vector3)
	var side := Vector3(-toward_camp.z, 0, toward_camp.x)
	var turn := atan2(toward_camp.x, toward_camp.z)
	_crag(at + Vector3(0, 1.8, 0), Vector3(8.0, 3.6, 6.5), turn, GRANITE, 21)
	var back: Vector3 = at - toward_camp * 4.5
	_crag(back + Vector3(0, 3.5, 0), Vector3(9.0, 7.0, 3.5), turn, GRANITE.darkened(0.06), 23)
	var mouth: Vector3 = back + toward_camp * 1.78 + Vector3(0, 4.6, 0)
	_add(Game.mesh_box(Vector3(2.0, 1.8, 0.06), Color(0.04, 0.035, 0.03)), mouth, Vector3(0, turn, 0))
	for k in 4:
		_lump(at + Vector3(0, 3.65, 0) + side * (k * 1.6 - 2.4) + toward_camp * 2.4, Vector3(0.6, 0.25, 0.5), GRANITE.lightened(0.05), k)
	# Broken rock stepping up to the shelf.
	for k in 3:
		var step: Vector3 = at + toward_camp * (5.2 - k * 0.8) + side * (3.0 + k * 0.9)
		var g: Vector3 = world.ground(step.x, step.z)
		var h := 1.0 + k * 0.95
		_add(Game.mesh_box(Vector3(1.8, h, 1.8), GRANITE.lightened(0.04), "stone"), g + Vector3(0, h * 0.5, 0), Vector3(0, turn + k * 0.3, 0))
		_box(Vector3(1.8, h, 1.8), g + Vector3(0, h * 0.5, 0), turn + k * 0.3)
	e["lair"] = at + Vector3(0, 3.65, 0)
