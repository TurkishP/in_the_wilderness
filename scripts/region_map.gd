extends Control
## The map of the whole journey: the Sinai, the gulfs of the Red Sea, the Negev, Edom and Moab,
## with the route from the sea crossing to the Jordan and the ten camps along it.
## The land is coloured from the same model that shapes each stage's mountains and seas.

const Region := preload("res://data/region.gd")
const Stages := preload("res://data/stages.gd")
const LAT_MIN := 27.0
const LAT_MAX := 32.6
const LON_MIN := 31.6
const LON_MAX := 36.6
const WIDTH := 500.0
const HEIGHT := 640.0     # keeps kilometres square: 5.0 deg of longitude by 5.6 deg of latitude here

static var _relief: ImageTexture

var stage_index := 0
var draws := 0            # how many times the map has been drawn in full (used by the self-test)


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Where a latitude and longitude fall on the picture, in pixels.
func spot(lat: float, lon: float) -> Vector2:
	return Vector2((lon - LON_MIN) / (LON_MAX - LON_MIN) * WIDTH, (LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * HEIGHT)


## Land color for an elevation in metres: plain sand, darker hills, pale summits; green-grey below sea level.
static func tone(elev: float) -> Color:
	if elev < 0.0:
		return Color(0.62, 0.66, 0.5).lerp(Color(0.5, 0.56, 0.42), clampf(-elev / 400.0, 0.0, 1.0))
	if elev < 700.0:
		return Color(0.87, 0.78, 0.58).lerp(Color(0.74, 0.6, 0.42), elev / 700.0)
	if elev < 1600.0:
		return Color(0.74, 0.6, 0.42).lerp(Color(0.55, 0.4, 0.3), (elev - 700.0) / 900.0)
	return Color(0.55, 0.4, 0.3).lerp(Color(0.86, 0.82, 0.78), clampf((elev - 1600.0) / 900.0, 0.0, 1.0))


static func relief() -> ImageTexture:
	if _relief == null:
		var w := 150
		var h := 192
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		for y in h:
			for x in w:
				var lat := LAT_MAX - (y + 0.5) / h * (LAT_MAX - LAT_MIN)
				var lon := LON_MIN + (x + 0.5) / w * (LON_MAX - LON_MIN)
				var km := Region.to_km(lat, lon)
				if Region.sea_at(km) >= 0:
					img.set_pixel(x, y, Color(0.22, 0.42, 0.58))
				else:
					img.set_pixel(x, y, tone(Region.elevation(km)))
		_relief = ImageTexture.create_from_image(img)
	return _relief


## The route as points on the picture: the crossing, then each stage's camp.
func route() -> PackedVector2Array:
	var pts := PackedVector2Array([spot(Region.CROSSING[0], Region.CROSSING[1])])
	for s in Stages.LIST:
		var site: Array = s["site"]
		pts.append(spot(site[0], site[1]))
	return pts


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_texture_rect(relief(), Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT)), false)

	# Shorelines, drawn sharp over the soft relief.
	for i in Region.sea_count():
		var line := PackedVector2Array()
		for p in Region.sea_outline(i):
			var ll := Region.to_lat_lon(p)
			line.append(spot(ll.x, ll.y))
		line.append(line[0])
		draw_polyline(line, Color(0.1, 0.25, 0.4), 1.5, true)

	for place in Region.PLACES:
		var p := spot(place[1], place[2])
		var label: String = place[0]
		var big := label == label.to_upper()
		draw_string(font, p + Vector2(-label.length() * (4.5 if big else 3.2), 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17 if big else 12,
			Color(0.25, 0.18, 0.1, 0.75) if big else Color(0.1, 0.1, 0.15, 0.9))

	# The route: gold as far as the current camp, faint beyond it.
	var pts := route()
	for i in pts.size() - 1:
		if i < stage_index + 1:
			draw_line(pts[i], pts[i + 1], Color(0.95, 0.75, 0.2), 3.0, true)
		else:
			draw_dashed_line(pts[i], pts[i + 1], Color(0.3, 0.2, 0.1, 0.7), 2.0, 7.0)
	draw_circle(pts[0], 4.0, Color(0.3, 0.2, 0.1))
	for i in Stages.LIST.size():
		var p := pts[i + 1]
		var here := i == stage_index
		var done := i < stage_index
		draw_circle(p, 9.0 if here else 7.0, Color(1.0, 0.85, 0.3) if here else (Color(0.85, 0.7, 0.4) if done else Color(0.92, 0.9, 0.85)))
		draw_arc(p, 9.0 if here else 7.0, 0.0, TAU, 24, Color(0.2, 0.12, 0.05), 2.0 if here else 1.2)
		var num := str(i + 1)
		draw_string(font, p + Vector2(-3.5 * num.length(), 4.5), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.1, 0.07, 0.03))
	draw_rect(Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT)), Color(0.75, 0.6, 0.35), false, 2.0)
	draws += 1
