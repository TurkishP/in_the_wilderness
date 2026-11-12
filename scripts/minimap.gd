extends Control
## The round map in the top-right corner. North is up and the player is at the centre.
## It shows the ground within RANGE metres, with marks for the camp, the objective, people
## who need help, things to collect and enemies. Marks beyond the rim sit on the rim, so they
## still point the way.

const RADIUS := 92.0      # pixels
const RANGE := 130.0      # metres from the centre to the rim
const MARGIN := 7.0

var world
var draws := 0            # how many times the map has been drawn in full (used by the self-test)
var _picture: ImageTexture
var _half := 300.0


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * (RADIUS + MARGIN) * 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Takes a fresh top-down picture of the stage's ground.
func set_terrain(terrain) -> void:
	_picture = ImageTexture.create_from_image(terrain.map_image())
	_half = terrain.HALF


func has_picture() -> bool:
	return _picture != null


func _process(_delta: float) -> void:
	queue_redraw()


## Where a world position falls on the map, in pixels from the centre. Right is east, down is south.
func offset_of(pos: Vector3, player_pos: Vector3) -> Vector2:
	return Vector2(pos.x - player_pos.x, pos.z - player_pos.z) / RANGE * RADIUS


func _draw() -> void:
	var c := Vector2.ONE * (RADIUS + MARGIN)
	draw_circle(c, RADIUS + 5.0, Color(0.08, 0.06, 0.04, 0.92))
	if world == null or not is_instance_valid(world.player) or _picture == null:
		return
	var pp: Vector3 = world.player.global_position

	# The ground: a disc cut from the picture around the player.
	var rim := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 56:
		var a := TAU * i / 56.0
		var dir := Vector2(cos(a), sin(a))
		rim.append(c + dir * RADIUS)
		uvs.append(Vector2((pp.x + dir.x * RANGE + _half) / (_half * 2.0), (pp.z + dir.y * RANGE + _half) / (_half * 2.0)))
	draw_colored_polygon(rim, Color.WHITE, uvs, _picture)

	for m in world.get_map_points():
		var kind: String = m["kind"]
		var off := offset_of(m["pos"], pp)
		if off.length() > RADIUS - 7.0:
			if kind == "wild" or kind == "item":
				continue      # small marks only show when they are in range
			off = off.normalized() * (RADIUS - 7.0)
		var p := c + off
		match kind:
			"camp":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 5), p + Vector2(-7, 5)]), Color(0.95, 0.9, 0.78))
				draw_polyline(PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 5), p + Vector2(-7, 5), p + Vector2(0, -7)]), Color(0.2, 0.15, 0.1), 1.5)
			"objective":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 0), p + Vector2(0, 7), p + Vector2(-6, 0)]), Color(1.0, 0.82, 0.25))
				draw_polyline(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 0), p + Vector2(0, 7), p + Vector2(-6, 0), p + Vector2(0, -7)]), Color(0.25, 0.18, 0.05), 1.5)
			"exit":
				draw_circle(p, 6.0, Color.WHITE)
				draw_arc(p, 6.0, 0.0, TAU, 20, Color(0.3, 0.3, 0.3), 1.5)
			"raider":
				draw_circle(p, 4.0, Color(0.9, 0.15, 0.1))
				draw_arc(p, 4.0, 0.0, TAU, 14, Color(0.25, 0.0, 0.0), 1.0)
			"wild":
				draw_circle(p, 2.3, Color(0.55, 0.12, 0.08))
			"giver":
				draw_circle(p, 4.5, Color(1.0, 0.85, 0.2))
				draw_rect(Rect2(p + Vector2(-0.9, -3.2), Vector2(1.8, 3.8)), Color(0.2, 0.15, 0.0))
				draw_rect(Rect2(p + Vector2(-0.9, 1.6), Vector2(1.8, 1.6)), Color(0.2, 0.15, 0.0))
			"item":
				draw_circle(p, 2.6, Color(1.0, 0.95, 0.55))

	# The player: an arrow pointing the way the camera faces.
	var f: Vector3 = world.player.forward()
	var d := Vector2(f.x, f.z).normalized()
	var side := Vector2(-d.y, d.x)
	var arrow := PackedVector2Array([c + d * 10.0, c - d * 6.0 + side * 6.5, c - d * 2.5, c - d * 6.0 - side * 6.5])
	draw_colored_polygon(arrow, Color.WHITE)
	arrow.append(arrow[0])
	draw_polyline(arrow, Color(0.1, 0.1, 0.1), 1.5)

	draw_arc(c, RADIUS, 0.0, TAU, 72, Color(0.78, 0.62, 0.36), 2.5)
	# North mark on the rim.
	draw_circle(c + Vector2(0, -RADIUS), 9.0, Color(0.08, 0.06, 0.04))
	draw_arc(c + Vector2(0, -RADIUS), 9.0, 0.0, TAU, 20, Color(0.78, 0.62, 0.36), 1.5)
	var font := ThemeDB.fallback_font
	draw_string(font, c + Vector2(-5.0, -RADIUS + 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.92, 0.7))
	draws += 1


## The player's position as it would read on a real map, e.g. "29.33°N  32.95°E".
func coordinates() -> String:
	if world == null or not is_instance_valid(world.player) or world.terrain == null:
		return ""
	var pp: Vector3 = world.player.global_position
	var ll: Vector2 = world.terrain.lat_lon(pp.x, pp.z)
	return "%.3f°N  %.3f°E" % [ll.x, ll.y]
