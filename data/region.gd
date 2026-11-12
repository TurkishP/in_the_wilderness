extends RefCounted
## A coarse model of the land between Egypt and the Jordan: the Sinai peninsula, the Negev,
## Edom and Moab, with the Gulf of Suez, the Gulf of Aqaba, the Mediterranean and the Dead Sea.
##
## It is hand-built from well-known coordinates and heights, not from survey data: mountain
## masses are smooth bumps, ranges are ridges along a line, the Arabah and Jordan valley are a
## trough, and coastlines are short outlines. It is accurate to roughly ten kilometres and a
## few hundred metres of height, which is enough to put the sea and the mountains on the right
## side of each camp and at about the right size.
##
## Positions are in kilometres east (x) and north (y) of LAT0, LON0.

const LAT0 := 29.6
const LON0 := 34.2
const KM_LAT := 110.6
const KM_LON := 96.8      # one degree of longitude at 29.6 N
const BASE := 200.0       # elevation of open desert, metres

## [lat, lon, spread east-west km, spread north-south km, height m]
const BLOBS := [
	[28.55, 33.95, 30.0, 30.0, 1500.0],   # the southern Sinai massif
	[28.51, 33.95, 2.2, 2.2, 780.0],      # Jebel Katherina
	[28.539, 33.975, 1.3, 1.3, 600.0],    # Jebel Musa, the traditional Mount Sinai
	[28.65, 33.65, 4.0, 4.0, 900.0],      # Jebel Serbal
	[28.36, 33.92, 5.0, 5.0, 700.0],      # Jebel Umm Shomar
	[29.55, 33.95, 55.0, 38.0, 700.0],    # the et-Tih plateau
	[30.55, 34.7, 35.0, 30.0, 600.0],     # the Negev highlands
	[28.65, 35.3, 14.0, 14.0, 900.0],     # Jebel al-Lawz
	[31.768, 35.725, 3.0, 3.0, 400.0],    # the spur of Mount Nebo
	[30.317, 35.407, 2.5, 2.5, 450.0],    # Jebel Harun, the traditional Mount Hor
]
## [[lat, lon] along the crest, spread km, height m]
const RIDGES := [
	[[[29.75, 33.15], [29.3, 33.45], [28.95, 33.6]], 9.0, 520.0],      # hills behind the Gulf of Suez shore
	[[[29.75, 35.4], [30.3, 35.5], [30.9, 35.65]], 13.0, 1250.0],      # Edom
	[[[31.0, 35.75], [31.5, 35.8], [31.95, 35.85]], 15.0, 1000.0],     # Moab and the Abarim range
	[[[28.2, 35.0], [29.0, 35.2], [29.5, 35.35]], 15.0, 1300.0],       # Midian
	[[[31.2, 34.95], [31.55, 35.1], [31.95, 35.22]], 10.0, 650.0],     # the Judean hills
	[[[27.5, 33.2], [28.3, 32.6], [29.0, 32.2]], 15.0, 850.0],         # Egypt's Eastern Desert
]
## The rift from the Gulf of Aqaba up the Arabah to the Jordan valley: [lat, lon, floor elevation m]
const RIFT := [
	[29.53, 34.98, 0.0], [30.0, 35.12, 100.0], [30.35, 35.25, 210.0], [30.8, 35.35, -100.0],
	[31.05, 35.42, -390.0], [31.4, 35.48, -440.0], [31.78, 35.55, -400.0], [32.2, 35.57, -330.0], [32.7, 35.58, -210.0],
]
const RIFT_SPREAD := 10.0
## level: water surface in metres. shore: width in km over which the land falls to the water.
const SEAS := [
	{"name": "Gulf of Suez", "level": 0.0, "shore": 25.0, "outline": [
		[29.95, 32.58], [29.60, 32.70], [29.20, 32.95], [29.05, 33.10], [28.85, 33.18], [28.55, 33.33], [28.24, 33.62],
		[27.95, 33.95], [27.73, 34.25], [27.45, 34.05], [27.25, 33.83], [27.75, 33.55], [28.35, 33.08], [28.90, 32.65],
		[29.35, 32.42], [29.60, 32.36], [29.93, 32.52]]},
	{"name": "Gulf of Aqaba", "level": 0.0, "shore": 10.0, "outline": [
		[29.545, 34.955], [29.03, 34.68], [28.50, 34.52], [28.10, 34.44], [27.90, 34.33], [27.73, 34.25], [28.0, 34.62],
		[28.40, 34.76], [28.85, 34.83], [29.29, 34.94], [29.53, 35.00]]},
	{"name": "Red Sea", "level": 0.0, "shore": 14.0, "outline": [
		[27.73, 34.25], [28.0, 34.62], [27.6, 35.45], [26.6, 36.0], [26.4, 35.0], [26.6, 34.0], [27.25, 33.83], [27.45, 34.05]]},
	{"name": "Mediterranean Sea", "level": 0.0, "shore": 18.0, "outline": [
		[33.2, 31.4], [31.55, 31.4], [31.5, 31.85], [31.27, 32.30], [31.05, 32.65], [31.07, 33.1], [31.13, 33.8],
		[31.30, 34.24], [31.52, 34.45], [31.80, 34.63], [32.08, 34.77], [32.8, 34.95], [33.2, 35.15]]},
	{"name": "Dead Sea", "level": -430.0, "shore": 6.0, "outline": [
		[31.76, 35.50], [31.76, 35.58], [31.55, 35.58], [31.30, 35.56], [31.08, 35.50], [31.06, 35.40], [31.25, 35.38],
		[31.50, 35.40], [31.70, 35.44]]},
]
## Names shown on the region map: [name, lat, lon]
const PLACES := [
	["EGYPT", 29.9, 31.95], ["SINAI", 29.75, 33.75], ["MIDIAN", 28.4, 35.55], ["EDOM", 30.2, 35.85],
	["MOAB", 31.3, 36.05], ["CANAAN", 31.75, 34.9], ["NEGEV", 30.95, 34.75],
	["Gulf of Suez", 28.75, 32.85], ["Gulf of Aqaba", 28.55, 34.63], ["Red Sea", 27.25, 34.7],
	["Mediterranean Sea", 32.1, 33.2], ["Dead Sea", 31.42, 35.48],
	["Mt Sinai", 28.54, 33.98], ["Jericho", 31.87, 35.44], ["Mt Nebo", 31.77, 35.73],
]
## Where the journey begins on the map: the traditional crossing near the head of the gulf.
const CROSSING := [29.93, 32.62]

static var _prepared := false
static var _blobs: Array = []
static var _ridges: Array = []
static var _rift := PackedVector2Array()
static var _rift_floor := PackedFloat32Array()
static var _seas: Array = []


static func to_km(lat: float, lon: float) -> Vector2:
	return Vector2((lon - LON0) * KM_LON, (lat - LAT0) * KM_LAT)


## Returns Vector2(latitude, longitude).
static func to_lat_lon(p: Vector2) -> Vector2:
	return Vector2(LAT0 + p.y / KM_LAT, LON0 + p.x / KM_LON)


static func _prepare() -> void:
	if _prepared:
		return
	_prepared = true
	for b in BLOBS:
		_blobs.append([to_km(b[0], b[1]), float(b[2]), float(b[3]), float(b[4])])
	for r in RIDGES:
		var line := PackedVector2Array()
		for p in r[0]:
			line.append(to_km(p[0], p[1]))
		_ridges.append([line, float(r[1]), float(r[2])])
	for p in RIFT:
		_rift.append(to_km(p[0], p[1]))
		_rift_floor.append(float(p[2]))
	for s in SEAS:
		var poly := PackedVector2Array()
		for p in s["outline"]:
			poly.append(to_km(p[0], p[1]))
		_seas.append([poly, float(s["level"]), float(s["shore"]), str(s["name"])])


## Number of seas, and one sea's outline in km, water level in metres, or name.
static func sea_count() -> int:
	_prepare()
	return _seas.size()


static func sea_outline(i: int) -> PackedVector2Array:
	_prepare()
	return _seas[i][0]


static func sea_level(i: int) -> float:
	_prepare()
	return _seas[i][1]


static func sea_name(i: int) -> String:
	_prepare()
	return _seas[i][3]


## Index of the sea covering `p`, or -1 on land.
static func sea_at(p: Vector2) -> int:
	_prepare()
	for i in _seas.size():
		if Geometry2D.is_point_in_polygon(p, _seas[i][0]):
			return i
	return -1


## Ground elevation in metres at `p` (km). Sea beds are 40 m below their water level.
static func elevation(p: Vector2) -> float:
	_prepare()
	var sea := sea_at(p)
	if sea >= 0:
		return float(_seas[sea][1]) - 40.0

	var e := BASE
	for b in _blobs:
		var c: Vector2 = b[0]
		var dx := (p.x - c.x) / float(b[1])
		var dy := (p.y - c.y) / float(b[2])
		var q := dx * dx + dy * dy
		if q < 18.0:
			e += float(b[3]) * exp(-0.5 * q)
	for r in _ridges:
		var line: PackedVector2Array = r[0]
		var best := 1e9
		for i in line.size() - 1:
			best = minf(best, p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])))
		var q := best / (float(r[1]) * float(r[1]))
		if q < 18.0:
			e += float(r[2]) * exp(-0.5 * q)

	# The rift pulls the land down (or up) to the valley floor along its line.
	var rift_d := 1e9
	var rift_floor := 0.0
	for i in _rift.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(p, _rift[i], _rift[i + 1])
		var d := p.distance_squared_to(c)
		if d < rift_d:
			rift_d = d
			var seg := _rift[i + 1] - _rift[i]
			var t := clampf((c - _rift[i]).dot(seg) / seg.length_squared(), 0.0, 1.0)
			rift_floor = lerpf(_rift_floor[i], _rift_floor[i + 1], t)
	# The valley floor is wide and flat, so the pull saturates near the line.
	var pull := minf(1.0, 1.35 * exp(-0.5 * rift_d / (RIFT_SPREAD * RIFT_SPREAD)))
	e = lerpf(e, rift_floor, pull)

	# Land falls to the water over the width of the shore.
	var shore_d := 1e9
	var shore_level := 0.0
	var shore_width := 1.0
	for s in _seas:
		var poly: PackedVector2Array = s[0]
		for i in poly.size():
			var d := p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]))
			if d < shore_d:
				shore_d = d
				shore_level = s[1]
				shore_width = s[2]
	var inland := smoothstep(0.0, shore_width, sqrt(shore_d))
	return lerpf(shore_level + 3.0, e, inland)
