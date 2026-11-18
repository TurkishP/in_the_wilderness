extends Control
## One of the bars in the corner of the screen: a bronze-framed track that fills with color,
## its name and numbers written inside it, and a small emblem at its head.
##
## What was just lost lingers for a moment as a pale stretch before it drains away, so a blow
## taken can be read at a glance; under `warn_below` the bar pulses. `pips` draws small marks
## after the bar's end (the drinks left in the waterskin).

const Ui := preload("res://scripts/ui.gd")

var ratio := 1.0              # how full, 0..1
var label := ""               # written at the left, inside the bar: "Health"
var value_text := ""          # written at the right, inside the bar: "85 / 110"
var color := Color(0.78, 0.22, 0.16)
var emblem := "heart"         # "heart", "drop", "bolt", "star" or "tent"
var warn_below := 0.0
var cap := 1.0                # the share of the bar that can be filled at all: the rest is struck out
var pips := 0                 # how many of the marks are full
var pips_max := 0
var _ghost := 1.0             # where the bar stood a moment ago
var _hold := 0.0              # seconds before the pale stretch starts to drain
var _shown := false           # a value has been given: before that there is nothing to have lost
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sets how full the bar is and what is written in it.
func show_value(now: float, of: float, name_text: String, numbers: String) -> void:
	var r := clampf(now / maxf(of, 0.001), 0.0, 1.0)
	if not _shown:
		_shown = true
		_ghost = r
	elif r < ratio - 0.004:
		_hold = 0.45
	ratio = r
	label = name_text
	value_text = numbers


func _process(delta: float) -> void:
	_t += delta
	if _ghost < ratio:
		_ghost = ratio
	elif _hold > 0.0:
		_hold -= delta
	else:
		_ghost = move_toward(_ghost, ratio, delta * 0.6)
	queue_redraw()


func _draw() -> void:
	var h := size.y
	var pip_room := (h * 0.62 + 3.0) * pips_max + (6.0 if pips_max > 0 else 0.0)
	var track := Rect2(h * 0.55, h * 0.12, size.x - h * 0.55 - pip_room, h * 0.76)
	var inner := track.grow(-2.0)
	# The track: a dark trough with a shadow under it.
	draw_rect(Rect2(track.position + Vector2(1, 2), track.size), Color(0, 0, 0, 0.45))
	draw_rect(track, Color(0.05, 0.036, 0.028, 0.9))
	# What was just lost, pale, and the fill itself: lighter along its top, darker below.
	if _ghost > ratio + 0.002:
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * _ghost, inner.size.y)), Color(1.0, 0.93, 0.8, 0.5))
	var shown := color
	if ratio < warn_below:
		shown = color.lerp(Color(1.0, 0.92, 0.8), 0.25 + 0.25 * sin(_t * 7.0))
	var w := inner.size.x * ratio
	if w > 0.5:
		var top := shown.lightened(0.28)
		var low := shown.darkened(0.32)
		var a := inner.position
		draw_polygon(PackedVector2Array([a, a + Vector2(w, 0), a + Vector2(w, inner.size.y), a + Vector2(0, inner.size.y)]),
			PackedColorArray([top, top, low, low]))
		draw_rect(Rect2(a, Vector2(w, inner.size.y * 0.38)), Color(1, 1, 1, 0.13))
		draw_line(a + Vector2(w, 0), a + Vector2(w, inner.size.y), Color(1.0, 0.97, 0.88, 0.75), 1.5)
	# What cannot be filled for now (stamina, when dry) is struck out.
	if cap < 0.995:
		var shut := Rect2(inner.position + Vector2(inner.size.x * cap, 0), Vector2(inner.size.x * (1.0 - cap), inner.size.y))
		draw_rect(shut, Color(0.02, 0.015, 0.01, 0.72))
		var x0 := shut.position.x
		while x0 < shut.end.x:
			draw_line(Vector2(x0, shut.end.y), Vector2(minf(x0 + shut.size.y, shut.end.x), shut.end.y - minf(shut.size.y, shut.end.x - x0)), Color(0.62, 0.45, 0.24, 0.55), 1.0)
			x0 += 7.0
		draw_line(shut.position, Vector2(shut.position.x, shut.end.y), Color(0.62, 0.45, 0.24, 0.9), 1.5)
	# A notch at every tenth.
	for k in range(1, 10):
		var x := inner.position.x + inner.size.x * k / 10.0
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.position.y + inner.size.y * 0.3), Color(0, 0, 0, 0.35), 1.0)
	# The frame: bronze, with a thin gold line inside it.
	draw_rect(track, Ui.BRONZE, false, 2.0)
	draw_rect(track.grow(-2.0), Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, 0.22), false, 1.0)
	# The words, inside the bar.
	var font := Ui.font("bold")
	var text_size := int(clampf(h * 0.52, 11.0, 17.0))
	var base := track.position.y + track.size.y * 0.5 + text_size * 0.34
	var left_x := track.position.x + h * 0.55
	_write(font, Vector2(left_x, base), label, HORIZONTAL_ALIGNMENT_LEFT, track.end.x - left_x - 8.0, text_size)
	_write(font, Vector2(left_x, base), value_text, HORIZONTAL_ALIGNMENT_RIGHT, track.end.x - left_x - 8.0, text_size)
	# The emblem: a dark disc ringed in bronze at the bar's head.
	var c := Vector2(h * 0.5, h * 0.5)
	var r := h * 0.5 - 1.0
	draw_circle(c + Vector2(1, 2), r, Color(0, 0, 0, 0.45))
	draw_circle(c, r, Color(0.09, 0.065, 0.05))
	draw_arc(c, r - 1.0, 0.0, TAU, 28, Ui.BRONZE, 2.0, true)
	draw_arc(c, r - 3.2, 0.0, TAU, 28, Color(Ui.GOLD.r, Ui.GOLD.g, Ui.GOLD.b, 0.3), 1.0, true)
	_emblem(c, r * 0.5, color.lightened(0.25))
	# The marks after the bar's end.
	for k in pips_max:
		var pc := Vector2(track.end.x + 8.0 + h * 0.31 + k * (h * 0.62 + 3.0), h * 0.52)
		_drop(pc, h * 0.24, Color(0.45, 0.72, 0.95) if k < pips else Color(0.05, 0.036, 0.028, 0.8), Ui.BRONZE)


func _write(font: Font, at: Vector2, words: String, align: HorizontalAlignment, width: float, text_size: int) -> void:
	if words == "":
		return
	draw_string_outline(font, at, words, align, width, text_size, 4, Color(0.05, 0.03, 0.02, 0.9))
	draw_string(font, at, words, align, width, text_size, Color(1.0, 0.97, 0.9))


func _emblem(c: Vector2, s: float, tint: Color) -> void:
	match emblem:
		"heart":
			draw_circle(c + Vector2(-s * 0.48, -s * 0.3), s * 0.56, tint)
			draw_circle(c + Vector2(s * 0.48, -s * 0.3), s * 0.56, tint)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.0, -s * 0.05), c + Vector2(s * 1.0, -s * 0.05), c + Vector2(0, s * 1.05)]), tint)
		"drop":
			_drop(c, s, tint, Color(0, 0, 0, 0))
		"bolt":
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.3, -s * 1.1), c + Vector2(-s * 0.7, s * 0.15), c + Vector2(-s * 0.05, s * 0.15),
				c + Vector2(-s * 0.3, s * 1.1), c + Vector2(s * 0.7, -s * 0.2), c + Vector2(s * 0.05, -s * 0.2)]), tint)
		"star":
			var pts := PackedVector2Array()
			for k in 8:
				var ang := TAU * k / 8.0 - PI * 0.5
				pts.append(c + Vector2(cos(ang), sin(ang)) * (s * 1.15 if k % 2 == 0 else s * 0.42))
			draw_colored_polygon(pts, tint)
		"tent":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.95), c + Vector2(s * 1.05, s * 0.8), c + Vector2(-s * 1.05, s * 0.8)]), tint)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.1), c + Vector2(s * 0.3, s * 0.8), c + Vector2(-s * 0.3, s * 0.8)]), Color(0.09, 0.065, 0.05))


## A drop of water: round below, drawn to a point above.
func _drop(c: Vector2, s: float, fill: Color, edge: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -s * 1.25)])
	for k in 13:
		var ang := -PI * 0.22 + (PI * 1.44) * k / 12.0
		pts.append(c + Vector2(0, s * 0.2) + Vector2(cos(ang), sin(ang)) * s * 0.85)
	draw_colored_polygon(pts, fill)
	if edge.a > 0.0:
		pts.append(pts[0])
		draw_polyline(pts, edge, 1.2, true)
