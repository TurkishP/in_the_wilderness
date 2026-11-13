extends Node3D
## The Israelite camp: tents of many shapes pitched close together, cooking fires, a flock at
## the edge, and from Sinai onward the tabernacle at its centre.
##
## Before Sinai the gathering ground (the "plaza": main fire, trader, craftsman, people with
## errands) is the middle of the camp. Once the tabernacle stands, the court takes the middle
## and the plaza lies just south of it.
##
## The tabernacle follows Exodus 26-27 and 38 at full size (one cubit = 0.457 m): a court of
## 100 by 50 cubits hung with linen on sixty posts, its gate on the east; the tent of 30 by 10
## cubits in the western half; the bronze altar and the basin before it.
##
## Everything here is on level ground, so heights are simply metres above zero.

const SceneryScript := preload("res://scripts/scenery.gd")
const CloudScript := preload("res://scripts/cloud_pillar.gd")
const CUBIT := 0.457
const COURT := Vector2(100.0 * CUBIT, 50.0 * CUBIT)     # east-west by north-south
const GAP := 1.4              # least space between two tents
const PLAZA_RADIUS := 15.0
const HOME_OFFSET := Vector3(-12.0, 0, 14.0)   # the scout's tent, from the middle of the plaza
const HOME_RADIUS := 3.0
const CLOTHS := [Color(0.86, 0.8, 0.68), Color(0.74, 0.62, 0.46), Color(0.6, 0.45, 0.33), Color(0.5, 0.38, 0.3), Color(0.82, 0.76, 0.6)]
const DARKS := [Color(0.17, 0.14, 0.13), Color(0.24, 0.19, 0.16), Color(0.3, 0.24, 0.2)]
const WOOD := Color(0.4, 0.28, 0.17)
const BRONZE := Color(0.72, 0.46, 0.2)
const GOLD := Color(0.86, 0.68, 0.25)
const LINEN := Color(0.9, 0.88, 0.82)

static var _sheep: ArrayMesh

var world
var plaza := Vector3.ZERO
var has_court := false
var reach := Vector2(46.0, 42.0)      # half-extent of the tented ground, east-west and north-south
var tents: Array = []                 # [{pos: Vector2, r: float, kind: String}]
var kinds := {}                       # tent kind -> how many
var nodes := PackedVector2Array()     # places people walk between
var links: Array = []                 # for each node, the nodes it connects to
var spots: Array = []                 # seated and working people: [{pos, look_at, pose, who, work, seat}]
var tabernacle: Node3D
var cloud: Node3D                    # over the tabernacle
var guide: Node3D                    # the pillar of cloud standing by the camp before there is a tabernacle
var _site: Node3D
var _lights := 0
var home := Vector3.ZERO              # the scout's own tent, at the edge of the plaza
var home_door := Vector3.ZERO         # where to stand to go in
var home_facing := 0.0                # yaw of someone walking out of the door
var waters: Array = []                # [{pos, kind}] places to drink: "barrel" or "cups"


func build(stage_index: int, rng: RandomNumberGenerator) -> void:
	has_court = stage_index >= 2
	if has_court:
		plaza = Vector3(0, 0, 27.0)
		reach = Vector2(54.0, 48.0)
	if stage_index >= 3:
		raise_tabernacle()
	elif stage_index == 2:
		_mark_site()
	home = plaza + HOME_OFFSET
	_pitch_tents(rng)
	_plan_spots()
	_place_props(rng)
	_place_flock(rng)
	_build_home()
	# Water stations get their own random numbers, so the rest of the layout is as before.
	var wrng := RandomNumberGenerator.new()
	wrng.seed = rng.seed * 7 + 11
	_place_waters(wrng)
	_plan_paths(rng)


## The farthest a tent stands from the middle of the camp.
func radius() -> float:
	return maxf(reach.x, reach.y) + 2.0


func _add(parent: Node3D, mi: MeshInstance3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _solid(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	sb.position = pos
	parent.add_child(sb)


func _in_court(p: Vector2, margin: float) -> bool:
	return has_court and absf(p.x) < COURT.x * 0.5 + margin and absf(p.y) < COURT.y * 0.5 + margin


## True where no tent of footprint radius `r` may stand: outside the camp, on the plaza, on
## the ways in, or on the court and its surround.
func _reserved(p: Vector2, r: float) -> bool:
	var ex := (absf(p.x) + r) / reach.x
	var ez := (absf(p.y) + r) / reach.y
	if ex * ex + ez * ez > 1.0:
		return true
	var pl := Vector2(plaza.x, plaza.z)
	if p.distance_to(pl) < PLAZA_RADIUS + r:
		return true
	if p.distance_to(Vector2(home.x, home.z)) < HOME_RADIUS + 2.0 + r:
		return true                                   # the scout's own tent and its doorway
	if absf(p.x - pl.x) < 4.0 + r and p.y > pl.y:
		return true                                   # the way in from the south
	if has_court:
		if _in_court(p, 4.0 + r):
			return true
		if p.x > 0.0 and absf(p.y) < 3.5 + r:
			return true                               # the approach to the gate from the east
		if absf(p.x) < 4.0 + r and p.y > 0.0 and p.y < pl.y:
			return true                               # from the court to the plaza
	return false


# ================================================================ tents

func _pitch_tents(rng: RandomNumberGenerator) -> void:
	var wanted := 66 if has_court else 68
	var tries := 0
	while tents.size() < wanted and tries < 12000:
		tries += 1
		var p := Vector2(rng.randf_range(-reach.x, reach.x), rng.randf_range(-reach.y, reach.y))
		var roll := rng.randf()
		var kind := "ridge"
		if roll > 0.86:
			kind = "long"
		elif roll > 0.74:
			kind = "booth"
		elif roll > 0.6:
			kind = "round"
		elif roll > 0.34:
			kind = "black"
		var s := rng.randf_range(0.85, 1.25)
		var r: float = {"ridge": 2.3, "black": 3.7, "round": 2.1, "booth": 2.3, "long": 3.9}[kind] * s
		if _reserved(p, r):
			continue
		var free := true
		for t in tents:
			if p.distance_to(t["pos"]) < r + float(t["r"]) + GAP:
				free = false
				break
		if not free:
			continue
		tents.append({"pos": p, "r": r, "kind": kind})
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		_tent(kind, p, rng.randf() * TAU, s, rng)


func _tent(kind: String, p: Vector2, angle: float, s: float, rng: RandomNumberGenerator) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = Vector3(p.x, 0, p.y)
	node.rotation.y = angle
	var cloth: Color = CLOTHS[rng.randi() % CLOTHS.size()]
	var dark: Color = DARKS[rng.randi() % DARKS.size()]
	match kind:
		"ridge":
			# A small family tent: two sloping sides meeting at a ridge.
			var size := Vector3(2.9 * s, 2.1 * s, 3.7 * s)
			var prism := PrismMesh.new()
			prism.size = size
			_add(node, _mesh(prism, cloth, "cloth"), Vector3(0, size.y * 0.5, 0))
			_solid(node, Vector3(size.x * 0.85, size.y, size.z), Vector3(0, size.y * 0.5, 0))
		"black":
			# The long, low tent of dark goat hair, with upright walls and a shallow roof.
			var w := 5.8 * s
			var d := 3.4 * s
			_add(node, Game.mesh_box(Vector3(w, 1.15, d), dark, "hair"), Vector3(0, 0.575, 0))
			var roof := PrismMesh.new()
			roof.size = Vector3(d + 0.5, 0.85, w + 0.7)
			_add(node, _mesh(roof, dark.lightened(0.06), "hair"), Vector3(0, 1.15 + 0.425, 0), Vector3(0, PI * 0.5, 0))
			for k in 3:
				_add(node, Game.mesh_cyl(0.045, 0.045, 1.7, WOOD, "wood"), Vector3((k - 1) * w * 0.4, 0.85, d * 0.5 + 0.35))
			_solid(node, Vector3(w, 2.0, d), Vector3(0, 1.0, 0))
		"round":
			var rad := 1.9 * s
			var h := 2.9 * s
			_add(node, Game.mesh_cyl(0.07, rad, h, cloth, "cloth"), Vector3(0, h * 0.5, 0))
			_add(node, Game.mesh_cyl(0.03, 0.03, 0.5, WOOD, "wood"), Vector3(0, h + 0.2, 0))
			_solid(node, Vector3(rad * 1.5, h, rad * 1.5), Vector3(0, h * 0.5, 0))
		"booth":
			# An open shelter: a cloth roof on four poles, for shade and for work.
			var w := 3.1 * s
			for cx in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					var h: float = 2.2 if cz < 0.0 else 1.9
					_add(node, Game.mesh_cyl(0.05, 0.05, h, WOOD, "wood"), Vector3(cx * w * 0.47, h * 0.5, cz * w * 0.47))
			_add(node, Game.mesh_box(Vector3(w + 0.3, 0.06, w + 0.3), cloth.darkened(0.1), "cloth"), Vector3(0, 2.08, 0), Vector3(0.1, 0, 0))
		"long":
			# A large tent for a big household, with two poles through the ridge.
			var size := Vector3(3.5 * s, 2.5 * s, 7.2 * s)
			var prism := PrismMesh.new()
			prism.size = size
			_add(node, _mesh(prism, cloth, "cloth"), Vector3(0, size.y * 0.5, 0))
			for k in [-1.0, 1.0]:
				_add(node, Game.mesh_cyl(0.04, 0.04, 0.5, WOOD, "wood"), Vector3(0, size.y + 0.15, k * size.z * 0.3))
			_solid(node, Vector3(size.x * 0.85, size.y, size.z), Vector3(0, size.y * 0.5, 0))


## The scout's own tent: a family tent of striped cloth with its door open toward the plaza and
## a pennant on the ridge pole, so it can be found. Going in leads to its inside (home.gd).
func _build_home() -> void:
	var to_plaza := Vector3(plaza.x - home.x, 0, plaza.z - home.z).normalized()
	var node := Node3D.new()
	node.name = "HomeTent"
	add_child(node)
	node.position = home
	node.rotation.y = atan2(to_plaza.x, to_plaza.z)      # +Z of the tent faces the plaza
	var cloth := Color(0.84, 0.76, 0.6)
	var stripe := Color(0.55, 0.16, 0.13)
	var size := Vector3(4.0, 2.8, 5.0)
	var prism := PrismMesh.new()
	prism.size = size
	_add(node, _mesh(prism, cloth, "cloth"), Vector3(0, size.y * 0.5, 0))
	# Woven bands of red and blue across both slopes.
	for k in 3:
		var band := PrismMesh.new()
		band.size = Vector3(size.x + 0.04, size.y + 0.02, 0.22)
		_add(node, _mesh(band, stripe if k != 1 else Color(0.2, 0.28, 0.5), "cloth"), Vector3(0, size.y * 0.5, -1.6 + k * 1.6))
	# The doorway: a dark opening with the flap rolled up above it.
	var door := PrismMesh.new()
	door.size = Vector3(1.3, 1.9, 0.06)
	_add(node, _mesh(door, Color(0.12, 0.09, 0.07)), Vector3(0, 0.95, size.z * 0.5 + 0.01))
	_add(node, Game.mesh_cyl(0.09, 0.09, 1.4, cloth.darkened(0.15), "cloth"), Vector3(0, 1.95, size.z * 0.5 + 0.06), Vector3(0, 0, PI * 0.5))
	for side in [-1.0, 1.0]:
		_add(node, Game.mesh_cyl(0.04, 0.04, 2.0, WOOD, "wood"), Vector3(side * 0.75, 1.0, size.z * 0.5 + 0.35))
	# Ridge poles, and a pennant on the front one.
	for k in [-1.0, 1.0]:
		_add(node, Game.mesh_cyl(0.045, 0.045, 0.9, WOOD, "wood"), Vector3(0, size.y + 0.3, k * size.z * 0.3))
	var flag := Game.mesh_box(Vector3(0.03, 0.32, 0.55), Color(0.2, 0.28, 0.55), "linen")
	_add(node, flag, Vector3(0, size.y + 0.6, size.z * 0.3 + 0.3))
	_solid(node, Vector3(size.x * 0.85, size.y, size.z), Vector3(0, size.y * 0.5, 0))
	var sign := Game.label3d("Your tent", 64, Color(1.0, 0.92, 0.7))
	sign.position = Vector3(0, size.y + 1.3, 0)
	sign.visibility_range_end = 35.0
	node.add_child(sign)
	home_door = home + to_plaza * (size.z * 0.5 + 1.0)
	home_facing = atan2(-to_plaza.x, -to_plaza.z)


## Places to drink about the camp: wooden water barrels, and low tables with a jug and cups.
## Two stand on the plaza; the rest are among the tents.
func _place_waters(rng: RandomNumberGenerator) -> void:
	_water_station("barrel", plaza + Vector3(3.8, 0, -6.8), rng)
	_water_station("cups", plaza + Vector3(-4.2, 0, 9.2), rng)
	var tries := 0
	while waters.size() < 8 and tries < 600:
		tries += 1
		var p := Vector2(rng.randf_range(-reach.x, reach.x), rng.randf_range(-reach.y, reach.y))
		if _reserved(p, 0.8) or _blocked(p, 0.9):
			continue
		var far := true
		for w in waters:
			if p.distance_to(Vector2((w["pos"] as Vector3).x, (w["pos"] as Vector3).z)) < 14.0:
				far = false
		if far:
			_water_station("barrel" if waters.size() % 2 == 0 else "cups", Vector3(p.x, 0, p.y), rng)


func _water_station(kind: String, at: Vector3, rng: RandomNumberGenerator) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = at
	node.rotation.y = rng.randf() * TAU
	var wood := WOOD.lightened(0.1)
	var water := Color(0.25, 0.45, 0.55)
	if kind == "barrel":
		# A staved barrel bound with dark hoops, its lid pushed aside, a dipper hanging on it.
		_add(node, Game.mesh_cyl(0.36, 0.33, 0.95, wood, "wood"), Vector3(0, 0.475, 0))
		_add(node, Game.mesh_cyl(0.375, 0.375, 0.5, wood.darkened(0.06), "wood"), Vector3(0, 0.5, 0))
		for y in [0.12, 0.5, 0.86]:
			_add(node, Game.mesh_cyl(0.385, 0.385, 0.05, Color(0.2, 0.16, 0.12)), Vector3(0, y, 0))
		_add(node, Game.mesh_cyl(0.33, 0.33, 0.02, water, "", 0.15), Vector3(0, 0.9, 0))
		_add(node, Game.mesh_cyl(0.3, 0.3, 0.04, wood.darkened(0.1), "wood"), Vector3(0.22, 0.97, 0.12), Vector3(0.12, 0, 0.18))
		_add(node, Game.mesh_cyl(0.015, 0.015, 0.45, wood.darkened(0.2), "wood"), Vector3(-0.3, 0.9, 0), Vector3(0, 0, 0.9))
		_add(node, Game.mesh_sphere(0.06, wood.darkened(0.2), "wood"), Vector3(-0.47, 0.72, 0))
	else:
		# A low table with a clay jug and three wooden cups.
		_add(node, Game.mesh_box(Vector3(0.9, 0.06, 0.6), wood, "wood"), Vector3(0, 0.42, 0))
		for cx in [-0.38, 0.38]:
			for cz in [-0.24, 0.24]:
				_add(node, Game.mesh_box(Vector3(0.06, 0.4, 0.06), wood.darkened(0.15), "wood"), Vector3(cx, 0.2, cz))
		var clay := Color(0.7, 0.42, 0.28)
		_add(node, Game.mesh_cyl(0.11, 0.16, 0.32, clay, "clay"), Vector3(-0.2, 0.61, 0))
		_add(node, Game.mesh_cyl(0.06, 0.1, 0.1, clay, "clay"), Vector3(-0.2, 0.82, 0))
		_add(node, Game.mesh_cyl(0.07, 0.06, 0.05, clay.darkened(0.1), "clay"), Vector3(-0.2, 0.9, 0))
		_add(node, Game.mesh_box(Vector3(0.03, 0.2, 0.05), clay.darkened(0.1), "clay"), Vector3(-0.05, 0.66, 0), Vector3(0, 0, -0.3))
		for k in 3:
			_add(node, Game.mesh_cyl(0.05, 0.04, 0.09, Color(0.5, 0.36, 0.22), "wood"), Vector3(0.12 + (k % 2) * 0.13, 0.5, -0.14 + k * 0.14))
		# Two large water jars beside the table.
		for k in 2:
			_add(node, Game.mesh_cyl(0.2, 0.28, 0.7, clay.darkened(0.05), "clay"), Vector3(0.75 + k * 0.5, 0.35, 0.1))
	waters.append({"pos": at, "kind": kind})


func _mesh(mesh: Mesh, color: Color, surface: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Game.mat(color, surface)
	return mi


# ================================================================ the tabernacle

## Posts mark out the court while the tabernacle is still being made (the Sinai stage).
func _mark_site() -> void:
	_site = Node3D.new()
	add_child(_site)
	var hx := COURT.x * 0.5
	var hz := COURT.y * 0.5
	for corner in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
		_add(_site, Game.mesh_cyl(0.07, 0.09, 2.3, BRONZE, "metal"), Vector3(corner.x, 1.15, corner.y))
	# Timber and cloth laid ready where the tent will stand.
	for k in 6:
		_add(_site, Game.mesh_box(Vector3(0.7, 0.12, 4.4), GOLD.darkened(0.25), "wood"), Vector3(-9.0 + k * 0.8, 0.06 + (k % 2) * 0.12, 0))
	for k in 4:
		_add(_site, Game.mesh_cyl(0.3, 0.3, 1.6, LINEN, "linen"), Vector3(4.0 + k * 0.7, 0.3, 3.0), Vector3(0, 0, PI * 0.5))


## Sets up the finished tabernacle. Called at once from Paran onward, and at Sinai when the
## craftsmen have what they need.
func raise_tabernacle() -> void:
	if tabernacle != null:
		return
	if _site != null:
		_site.queue_free()
		_site = null
	has_court = true
	tabernacle = Node3D.new()
	tabernacle.name = "Tabernacle"
	add_child(tabernacle)
	var hx := COURT.x * 0.5
	var hz := COURT.y * 0.5
	var span := 5.0 * CUBIT
	var post_h := 5.0 * CUBIT

	# The court: sixty posts, five cubits apart, hung with linen. The gate is the middle
	# twenty cubits of the east side, with a screen of blue, purple and scarlet.
	var spans: Array = []      # [from, to, is_gate]
	for i in 20:
		spans.append([Vector2(-hx + i * span, hz), Vector2(-hx + (i + 1) * span, hz), false])
		spans.append([Vector2(-hx + i * span, -hz), Vector2(-hx + (i + 1) * span, -hz), false])
	for i in 10:
		spans.append([Vector2(-hx, -hz + i * span), Vector2(-hx, -hz + (i + 1) * span), false])
		spans.append([Vector2(hx, -hz + i * span), Vector2(hx, -hz + (i + 1) * span), i >= 3 and i <= 6])
	var posted := {}
	for sp in spans:
		var a: Vector2 = sp[0]
		var b: Vector2 = sp[1]
		for corner in [a, b]:
			var end: Vector2 = corner
			var key := Vector2i((end * 100.0).round())
			if not posted.has(key):
				posted[key] = true
				_add(tabernacle, Game.mesh_cyl(0.06, 0.06, post_h, BRONZE, "metal"), Vector3(end.x, post_h * 0.5, end.y))
				_add(tabernacle, Game.mesh_box(Vector3(0.2, 0.1, 0.2), BRONZE.darkened(0.2), "metal"), Vector3(end.x, 0.05, end.y))
				_add(tabernacle, Game.mesh_sphere(0.085, Color(0.82, 0.82, 0.85), "metal"), Vector3(end.x, post_h + 0.04, end.y))
		var mid := (a + b) * 0.5
		var turn := Vector3(0, PI * 0.5, 0) if is_equal_approx(a.x, b.x) else Vector3.ZERO
		if sp[2]:
			var bands := [Color(0.16, 0.26, 0.62), Color(0.42, 0.2, 0.52), Color(0.72, 0.12, 0.12)]
			for k in 3:
				_add(tabernacle, Game.mesh_box(Vector3(span - 0.1, 0.68, 0.05), bands[k], "linen"), Vector3(mid.x, 0.4 + k * 0.7, mid.y), turn)
		else:
			_add(tabernacle, Game.mesh_box(Vector3(span - 0.08, post_h - 0.15, 0.04), LINEN, "linen"), Vector3(mid.x, post_h * 0.5, mid.y), turn)
	# The linen is solid; the gate screen is a hanging you can walk through.
	_solid(tabernacle, Vector3(COURT.x, post_h, 0.3), Vector3(0, post_h * 0.5, hz))
	_solid(tabernacle, Vector3(COURT.x, post_h, 0.3), Vector3(0, post_h * 0.5, -hz))
	_solid(tabernacle, Vector3(0.3, post_h, COURT.y), Vector3(-hx, post_h * 0.5, 0))
	var wing := 15.0 * CUBIT
	_solid(tabernacle, Vector3(0.3, post_h, wing), Vector3(hx, post_h * 0.5, -hz + wing * 0.5))
	_solid(tabernacle, Vector3(0.3, post_h, wing), Vector3(hx, post_h * 0.5, hz - wing * 0.5))

	# The tent: thirty cubits long, ten wide, ten high, its door to the east at the middle of the court.
	var length := 30.0 * CUBIT
	var width := 10.0 * CUBIT
	var height := 10.0 * CUBIT
	var cx := -length * 0.5
	_add(tabernacle, Game.mesh_box(Vector3(length, height, width), GOLD.darkened(0.15), "metal"), Vector3(cx, height * 0.5, 0))
	_add(tabernacle, Game.mesh_box(Vector3(length + 0.25, height - 0.5, width + 0.5), Color(0.17, 0.13, 0.12), "hair"), Vector3(cx - 0.2, height * 0.5 + 0.3, 0))
	_add(tabernacle, Game.mesh_box(Vector3(length + 0.4, 0.1, width + 0.7), Color(0.45, 0.2, 0.15)), Vector3(cx - 0.2, height + 0.08, 0))
	for k in 5:
		_add(tabernacle, Game.mesh_cyl(0.13, 0.13, height, GOLD, "metal", 0.15), Vector3(0.2, height * 0.5, -width * 0.5 + 0.2 + k * (width - 0.4) / 4.0))
	var bands2 := [Color(0.16, 0.26, 0.62), Color(0.42, 0.2, 0.52), Color(0.72, 0.12, 0.12)]
	for k in 3:
		_add(tabernacle, Game.mesh_box(Vector3(0.05, height / 3.0 - 0.04, width - 0.5), bands2[k], "linen"), Vector3(0.05, height / 6.0 + k * height / 3.0, 0))
	_solid(tabernacle, Vector3(length + 0.4, height, width + 0.5), Vector3(cx - 0.1, height * 0.5, 0))

	# The bronze altar, five cubits square and three high, with a horn at each corner, and its fire.
	var altar := Vector3(11.4, 0, 0)
	var side := 5.0 * CUBIT
	var tall := 3.0 * CUBIT
	_add(tabernacle, Game.mesh_box(Vector3(side, tall, side), BRONZE, "metal"), altar + Vector3(0, tall * 0.5, 0))
	for hx2 in [-1.0, 1.0]:
		for hz2 in [-1.0, 1.0]:
			_add(tabernacle, Game.mesh_box(Vector3(0.16, 0.3, 0.16), BRONZE.lightened(0.1), "metal"), altar + Vector3(hx2 * (side * 0.5 - 0.08), tall + 0.15, hz2 * (side * 0.5 - 0.08)))
	_add(tabernacle, Game.mesh_cyl(0.0, 0.75, 1.5, Color(1.0, 0.5, 0.1), "", 3.0), altar + Vector3(0, tall + 0.75, 0))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.25)
	glow.light_energy = 2.5
	glow.omni_range = 12.0
	glow.position = altar + Vector3(0, tall + 1.2, 0)
	tabernacle.add_child(glow)
	_solid(tabernacle, Vector3(side, tall, side), altar + Vector3(0, tall * 0.5, 0))
	# The bronze basin between the altar and the tent.
	_add(tabernacle, Game.mesh_cyl(0.3, 0.42, 0.55, BRONZE, "metal"), Vector3(4.6, 0.275, 0))
	_add(tabernacle, Game.mesh_cyl(0.75, 0.5, 0.35, BRONZE.lightened(0.08), "metal"), Vector3(4.6, 0.72, 0))
	_solid(tabernacle, Vector3(1.2, 0.9, 1.2), Vector3(4.6, 0.45, 0))

	# The cloud that covers the tent by day.
	cloud = CloudScript.new()
	cloud.position = Vector3(cx, height + 1.0, 0)
	tabernacle.add_child(cloud)
	cloud.build(145.0, 3.2, 11.0, 7)


## The cloud is taken up from over the tent when it is time to set out.
func lift_cloud() -> void:
	if cloud != null:
		cloud.visible = false
	if guide != null:
		guide.visible = false


## Before the tabernacle, the pillar of cloud stands at the edge of the camp on the side they
## will travel (Exodus 13:21-22). `bearing` is in degrees clockwise from north.
func stand_cloud(bearing: float) -> void:
	var b := deg_to_rad(bearing)
	var out := radius() + 16.0
	guide = CloudScript.new()
	guide.position = Vector3(sin(b) * out, 0.0, -cos(b) * out)
	add_child(guide)
	guide.build(150.0, 4.0, 11.0, 3)


# ================================================================ life in the camp

## Places for people who stay where they are: a ring of seats at the main fire, and people at
## their work round the edge of the plaza. The world puts a person on each.
func _plan_spots() -> void:
	var seats := [50.0, 120.0, 180.0, 245.0, 310.0]
	for k in seats.size():
		var a := deg_to_rad(seats[k])
		spots.append({
			"pos": plaza + Vector3(sin(a), 0, cos(a)) * 2.9, "look_at": plaza,
			"pose": "Sitting_Talking" if k % 2 == 0 else "Sitting_Idle",
			"who": "man" if k % 2 == 0 else "woman", "work": "fire", "seat": true,
		})
	# [work, where on the plaza, pose, who, seated]
	var jobs := [
		["weave", Vector3(10.0, 0, 6.5), "Kneeling_Work", "woman", false],
		["spin", Vector3(8.3, 0, 9.8), "Sitting_Idle", "woman", true],
		["grind", Vector3(10.5, 0, -7.5), "Kneeling_Work", "woman", false],
		["cook", Vector3(7.0, 0, -10.8), "Kneeling_Work", "woman", false],
		["arms", Vector3(-11.5, 0, 7.5), "Kneeling_Work", "man", false],
		["mend", Vector3(-6.5, 0, -11.5), "Kneeling_Work", "man", false],
	]
	for job in jobs:
		var pos: Vector3 = plaza + job[1]
		var toward := (plaza - pos).normalized()
		var bench := pos + toward * 0.5          # the work lies under the worker's hands, on the plaza side
		spots.append({"pos": pos, "look_at": bench, "pose": job[2], "who": job[3], "work": job[0], "seat": job[4]})
		_work(str(job[0]), bench, atan2(toward.x, toward.z))


## The things a worker is busy with.
func _work(work: String, at: Vector3, angle: float) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = at
	node.rotation.y = angle
	match work:
		"weave":
			# A ground loom: two beams pegged to the earth with the cloth growing between them.
			_add(node, Game.mesh_box(Vector3(1.0, 0.06, 0.06), WOOD, "wood"), Vector3(0, 0.1, -0.1))
			_add(node, Game.mesh_box(Vector3(1.0, 0.06, 0.06), WOOD, "wood"), Vector3(0, 0.1, 1.5))
			_add(node, Game.mesh_box(Vector3(0.86, 0.015, 1.55), LINEN, "linen"), Vector3(0, 0.1, 0.7))
			_add(node, Game.mesh_box(Vector3(0.86, 0.03, 0.5), Color(0.35, 0.28, 0.24), "cloth"), Vector3(0, 0.11, 0.2))
		"spin":
			_add(node, Game.mesh_cyl(0.3, 0.22, 0.25, Color(0.55, 0.42, 0.28), "basket"), Vector3(0.1, 0.125, 0.1))
			for k in 4:
				_add(node, Game.mesh_sphere(0.11, Color(0.93, 0.91, 0.86)), Vector3(0.1 + sin(k * 1.6) * 0.12, 0.3, 0.1 + cos(k * 1.6) * 0.12))
		"grind":
			# A saddle quern: a broad lower stone and a smaller one worked across it.
			_add(node, Game.mesh_box(Vector3(0.36, 0.12, 0.6), Color(0.45, 0.43, 0.41), "stone"), Vector3(0, 0.06, 0.05), Vector3(0.08, 0, 0))
			_add(node, Game.mesh_box(Vector3(0.3, 0.08, 0.14), Color(0.35, 0.33, 0.32), "stone"), Vector3(0, 0.17, 0.05))
			_add(node, Game.mesh_cyl(0.2, 0.14, 0.14, Color(0.66, 0.42, 0.3), "clay"), Vector3(0.45, 0.07, 0.2))
		"cook":
			for k in 3:
				_add(node, Game.mesh_sphere(0.14, Color(0.35, 0.32, 0.3), "stone"), Vector3(sin(TAU * k / 3.0) * 0.28, 0.1, 0.25 + cos(TAU * k / 3.0) * 0.28))
			_add(node, Game.mesh_cyl(0.0, 0.2, 0.3, Color(1.0, 0.5, 0.1), "", 2.5), Vector3(0, 0.15, 0.25))
			_add(node, Game.mesh_cyl(0.3, 0.24, 0.3, Color(0.2, 0.17, 0.15), "clay"), Vector3(0, 0.42, 0.25))
			_add(node, Game.mesh_cyl(0.015, 0.015, 0.6, WOOD, "wood"), Vector3(0.12, 0.7, 0.25), Vector3(0.4, 0, 0.3))
		"arms":
			# A whetstone with a blade on it, and spears stood in a rack.
			_add(node, Game.mesh_box(Vector3(0.5, 0.14, 0.3), Color(0.42, 0.42, 0.44), "stone"), Vector3(0, 0.07, 0.1))
			_add(node, Game.mesh_box(Vector3(0.05, 0.012, 0.55), BRONZE.lightened(0.15), "metal"), Vector3(0, 0.15, 0.12), Vector3(0, 0.5, 0))
			for k in [-1.0, 1.0]:
				_add(node, Game.mesh_cyl(0.04, 0.04, 1.3, WOOD, "wood"), Vector3(1.1 + k * 0.5, 0.65, 0.6))
			_add(node, Game.mesh_cyl(0.03, 0.03, 1.1, WOOD, "wood"), Vector3(1.1, 1.2, 0.6), Vector3(0, 0, PI * 0.5))
			for k in 3:
				_add(node, Game.mesh_cyl(0.018, 0.02, 1.9, WOOD, "wood"), Vector3(0.8 + k * 0.3, 0.92, 0.42), Vector3(-0.2, 0, 0))
				_add(node, Game.mesh_cyl(0.0, 0.03, 0.2, BRONZE, "metal"), Vector3(0.8 + k * 0.3, 1.93, 0.21), Vector3(-0.2, 0, 0))
		"mend":
			_add(node, Game.mesh_cyl(0.28, 0.28, 0.1, Color(0.7, 0.62, 0.45), "basket"), Vector3(0, 0.05, 0.1))
			for k in 5:
				_add(node, Game.mesh_cyl(0.02, 0.035, 0.35, WOOD, "wood"), Vector3(0.45 + (k % 3) * 0.07, 0.04 + (k / 3) * 0.07, 0.1), Vector3(0, 0, PI * 0.5))


func _place_props(rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < 30 and tries < 800:
		tries += 1
		var p := Vector2(rng.randf_range(-reach.x, reach.x), rng.randf_range(-reach.y, reach.y))
		if _reserved(p, 0.6) or _blocked(p, 0.7):
			continue
		placed += 1
		var at := Vector3(p.x, 0, p.y)
		match rng.randi() % 4:
			0:
				# A cooking fire in a ring of stones. Only a few of them cast light.
				for k in 6:
					_add(self, Game.mesh_sphere(0.14, Color(0.35, 0.32, 0.3), "stone"), at + Vector3(sin(TAU * k / 6.0) * 0.42, 0.08, cos(TAU * k / 6.0) * 0.42))
				_add(self, Game.mesh_cyl(0.0, 0.26, 0.55, Color(1.0, 0.5, 0.1), "", 2.5), at + Vector3(0, 0.28, 0))
				if _lights < 4:
					_lights += 1
					var glow := OmniLight3D.new()
					glow.light_color = Color(1.0, 0.6, 0.25)
					glow.light_energy = 1.3
					glow.omni_range = 6.0
					glow.position = at + Vector3(0, 0.8, 0)
					add_child(glow)
			1:
				for k in 2 + rng.randi() % 2:
					_add(self, Game.mesh_cyl(0.2, 0.3, 0.7, Color(0.66, 0.42, 0.3), "clay"), at + Vector3(k * 0.55, 0.35, (k % 2) * 0.3))
			2:
				_add(self, Game.mesh_cyl(0.34, 0.26, 0.3, Color(0.6, 0.48, 0.3), "basket"), at + Vector3(0, 0.15, 0))
				_add(self, Game.mesh_cyl(0.26, 0.2, 0.24, Color(0.55, 0.43, 0.27), "basket"), at + Vector3(0.6, 0.12, 0.2))
			3:
				for k in 5:
					_add(self, Game.mesh_cyl(0.05, 0.05, 1.0, WOOD.darkened(k * 0.05), "wood"), at + Vector3(0, 0.05 + (k / 3) * 0.1, (k % 3) * 0.11), Vector3(0, rng.randf_range(-0.15, 0.15), PI * 0.5))


static func _sheep_mesh() -> ArrayMesh:
	if _sheep == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wool := Color(0.9, 0.87, 0.8)
		var face := Color(0.3, 0.26, 0.23)
		SceneryScript._add_blob(st, Vector3(0, 0.58, 0), Vector3(0.3, 0.28, 0.5), wool)
		SceneryScript._add_blob(st, Vector3(0, 0.74, -0.56), Vector3(0.13, 0.14, 0.19), face)
		for lx in [-0.16, 0.16]:
			for lz in [-0.3, 0.3]:
				SceneryScript._add_limb(st, Vector3(lx, 0.4, lz), Vector3(lx, 0.0, lz), 0.045, 0.035, face)
		st.generate_normals()
		_sheep = st.commit()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_sheep.surface_set_material(0, m)
	return _sheep


## Two small flocks grazing just outside the tents.
func _place_flock(rng: RandomNumberGenerator) -> void:
	var xforms: Array = []
	for flock in 2:
		var a := rng.randf() * TAU
		var centre := Vector2(sin(a) * (reach.x + 5.0), cos(a) * (reach.y + 5.0))
		for k in 7:
			var p := centre + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
			var s := rng.randf_range(0.85, 1.1)
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0, p.y)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _sheep_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Flock"
	node.multimesh = mm
	add_child(node)


# ================================================================ paths for people on foot

## True where a person cannot stand: inside a tent, the court, or a seated person's place.
func _blocked(p: Vector2, margin: float) -> bool:
	for t in tents:
		if p.distance_to(t["pos"]) < float(t["r"]) + margin:
			return true
	if _in_court(p, margin + 0.4):
		return true
	if p.distance_to(Vector2(home.x, home.z)) < HOME_RADIUS + margin:
		return true
	for w in waters:
		var wp: Vector3 = w["pos"]
		if p.distance_to(Vector2(wp.x, wp.z)) < 0.7 + margin:
			return true
	for s in spots:
		var sp: Vector3 = s["pos"]
		if p.distance_to(Vector2(sp.x, sp.z)) < 1.2 + margin:
			return true
	return p.distance_to(Vector2(plaza.x, plaza.z)) < 1.6 + margin      # the main fire


func _clear_way(a: Vector2, b: Vector2) -> bool:
	var steps := int(ceil(a.distance_to(b) / 0.8))
	for i in steps + 1:
		if _blocked(a.lerp(b, float(i) / steps), 0.55):
			return false
	return true


## Lays out the places people walk between, and which of them can be reached from which
## without passing through a tent.
func _plan_paths(rng: RandomNumberGenerator) -> void:
	var step := 4.2
	var nx := int(reach.x / step)
	var nz := int(reach.y / step)
	for gx in range(-nx, nx + 1):
		for gz in range(-nz, nz + 1):
			var p := Vector2(gx * step + rng.randf_range(-1.1, 1.1), gz * step + rng.randf_range(-1.1, 1.1))
			var ex := p.x / reach.x
			var ez := p.y / reach.y
			if ex * ex + ez * ez > 0.96 or _blocked(p, 0.9):
				continue
			nodes.append(p)
	for i in nodes.size():
		links.append([])
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if nodes[i].distance_to(nodes[j]) < 6.6 and _clear_way(nodes[i], nodes[j]):
				links[i].append(j)
				links[j].append(i)


## A walking place that leads somewhere, or -1 if there is none.
func random_node(rng: RandomNumberGenerator) -> int:
	for attempt in 40:
		var i := rng.randi() % maxi(nodes.size(), 1)
		if i < links.size() and links[i].size() > 0:
			return i
	return -1


func node_position(i: int) -> Vector3:
	return Vector3(nodes[i].x, 0, nodes[i].y)
