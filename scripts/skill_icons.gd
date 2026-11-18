extends RefCounted
## The pictures of the weapon skills, drawn in lines and shapes inside each skill's medallion on
## the lampstand (scripts/lampstand.gd). A skill's "icon" in data/skills.gd names one picture
## below, or two joined by "+": the second is drawn small in the lower right, as a badge.

const RED := Color(0.8, 0.16, 0.12)


static func draw(ci: CanvasItem, spec: String, c: Vector2, r: float, col: Color, ground: Color) -> void:
	var parts := spec.split("+")
	if parts.size() == 1:
		_glyph(ci, parts[0], c, r, col)
		return
	_glyph(ci, parts[0], c + Vector2(-0.14, -0.14) * r, r * 0.8, col)
	var at := c + Vector2(0.52, 0.52) * r
	ci.draw_circle(at, r * 0.5, ground)
	ci.draw_arc(at, r * 0.5, 0.0, TAU, 16, col, 1.2, true)
	_glyph(ci, parts[1], at, r * 0.38, col)


# ---------------------------------------------------------------- drawing in the unit square

## A polyline through points given in units of `r` about `c`.
static func _pl(ci: CanvasItem, c: Vector2, r: float, pts: Array, col: Color, w: float = 2.0) -> void:
	var line := PackedVector2Array()
	for p in pts:
		line.append(c + (p as Vector2) * r)
	ci.draw_polyline(line, col, maxf(1.0, w * r / 16.0), true)


static func _fill(ci: CanvasItem, c: Vector2, r: float, pts: Array, col: Color) -> void:
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(c + (p as Vector2) * r)
	ci.draw_colored_polygon(poly, col)


static func _dot(ci: CanvasItem, c: Vector2, r: float, at: Vector2, size: float, col: Color) -> void:
	ci.draw_circle(c + at * r, size * r, col)


static func _ring(ci: CanvasItem, c: Vector2, r: float, at: Vector2, size: float, col: Color, w: float = 2.0, from: float = 0.0, to: float = TAU) -> void:
	ci.draw_arc(c + at * r, size * r, from, to, 24, col, maxf(1.0, w * r / 16.0), true)


static func _arrowhead(ci: CanvasItem, c: Vector2, r: float, tip: Vector2, dir: Vector2, col: Color, size: float = 0.32) -> void:
	var d := dir.normalized()
	var s := Vector2(-d.y, d.x)
	_fill(ci, c, r, [tip, tip - d * size + s * size * 0.6, tip - d * size - s * size * 0.6], col)


static func _star(ci: CanvasItem, c: Vector2, r: float, at: Vector2, size: float, col: Color) -> void:
	var pts: Array = []
	for i in 10:
		var a := -PI * 0.5 + TAU * i / 10.0
		pts.append(at + Vector2(cos(a), sin(a)) * size * (1.0 if i % 2 == 0 else 0.45))
	_fill(ci, c, r, pts, col)


# ---------------------------------------------------------------- the pictures

static func _glyph(ci: CanvasItem, g: String, c: Vector2, r: float, col: Color) -> void:
	var dark := Color(0.08, 0.06, 0.04)
	match g:
		"blade":
			_fill(ci, c, r, [Vector2(-0.38, 0.38), Vector2(0.6, -0.68), Vector2(0.68, -0.6), Vector2(-0.3, 0.46)], col)
			_pl(ci, c, r, [Vector2(-0.6, 0.2), Vector2(-0.2, 0.6)], col, 2.5)
			_pl(ci, c, r, [Vector2(-0.4, 0.4), Vector2(-0.72, 0.72)], col, 3.0)
		"dagger":
			_fill(ci, c, r, [Vector2(-0.12, 0.12), Vector2(0.5, -0.5), Vector2(0.56, -0.44), Vector2(-0.04, 0.2)], col)
			_pl(ci, c, r, [Vector2(-0.34, 0.0), Vector2(0.0, 0.34)], col, 2.5)
			_pl(ci, c, r, [Vector2(-0.12, 0.14), Vector2(-0.5, 0.52)], col, 3.0)
		"cross_daggers":
			_glyph(ci, "dagger", c + Vector2(-0.12, 0.0) * r, r, col)
			_fill(ci, c, r, [Vector2(0.12, 0.12), Vector2(-0.5, -0.5), Vector2(-0.56, -0.44), Vector2(0.04, 0.2)], col)
			_pl(ci, c, r, [Vector2(0.34, 0.0), Vector2(0.0, 0.34)], col, 2.5)
			_pl(ci, c, r, [Vector2(0.12, 0.14), Vector2(0.5, 0.52)], col, 3.0)
		"axe":
			_pl(ci, c, r, [Vector2(-0.6, 0.72), Vector2(0.28, -0.55)], col, 3.0)
			_fill(ci, c, r, [Vector2(0.0, -0.62), Vector2(0.4, -0.78), Vector2(0.72, -0.3), Vector2(0.55, 0.1), Vector2(0.22, -0.22)], col)
		"mace":
			_pl(ci, c, r, [Vector2(-0.6, 0.7), Vector2(0.1, -0.05)], col, 3.0)
			_dot(ci, c, r, Vector2(0.28, -0.25), 0.34, col)
			for a in [0.0, 1.2, 2.4, 3.6, 4.8]:
				var d := Vector2(cos(a), sin(a))
				_pl(ci, c, r, [Vector2(0.28, -0.25) + d * 0.3, Vector2(0.28, -0.25) + d * 0.5], col, 2.0)
		"spear":
			_pl(ci, c, r, [Vector2(-0.75, 0.75), Vector2(0.32, -0.32)], col, 2.5)
			_fill(ci, c, r, [Vector2(0.78, -0.78), Vector2(0.4, -0.2), Vector2(0.26, -0.26), Vector2(0.2, -0.4)], col)
		"staff":
			_pl(ci, c, r, [Vector2(0.0, 0.85), Vector2(0.0, -0.85)], col, 3.5)
			_dot(ci, c, r, Vector2(0.0, -0.82), 0.14, col)
		"crook":
			_pl(ci, c, r, [Vector2(-0.1, 0.85), Vector2(-0.1, -0.2)], col, 3.5)
			_ring(ci, c, r, Vector2(0.18, -0.3), 0.28, col, 3.5, PI, TAU + 0.6)
		"sling":
			_pl(ci, c, r, [Vector2(-0.5, -0.7), Vector2(0.0, 0.3)], col, 1.8)
			_pl(ci, c, r, [Vector2(0.5, -0.7), Vector2(0.0, 0.3)], col, 1.8)
			_dot(ci, c, r, Vector2(0.0, 0.42), 0.26, col)
			_ring(ci, c, r, Vector2(-0.55, -0.75), 0.12, col, 1.8)
		"bow":
			_ring(ci, c, r, Vector2(0.45, 0.0), 0.82, col, 3.0, PI * 0.62, PI * 1.38)
			_pl(ci, c, r, [Vector2(0.05, -0.75), Vector2(-0.25, 0.0), Vector2(0.05, 0.75)], col, 1.5)
			_pl(ci, c, r, [Vector2(-0.25, 0.0), Vector2(0.8, 0.0)], col, 1.8)
			_arrowhead(ci, c, r, Vector2(0.9, 0.0), Vector2(1, 0), col, 0.25)
		"arrow":
			_pl(ci, c, r, [Vector2(-0.7, 0.7), Vector2(0.55, -0.55)], col, 2.2)
			_arrowhead(ci, c, r, Vector2(0.72, -0.72), Vector2(1, -1), col, 0.36)
			_pl(ci, c, r, [Vector2(-0.7, 0.7), Vector2(-0.82, 0.38)], col, 2.0)
			_pl(ci, c, r, [Vector2(-0.7, 0.7), Vector2(-0.38, 0.82)], col, 2.0)
		"arrows2":
			_glyph(ci, "arrow", c + Vector2(-0.18, 0.12) * r, r * 0.85, col)
			_glyph(ci, "arrow", c + Vector2(0.22, -0.1) * r, r * 0.85, col)
		"stone":
			_fill(ci, c, r, [Vector2(-0.5, 0.1), Vector2(-0.25, -0.42), Vector2(0.3, -0.45), Vector2(0.55, 0.0), Vector2(0.35, 0.42), Vector2(-0.3, 0.45)], col)
		"stones":
			_glyph(ci, "stone", c + Vector2(-0.38, 0.28) * r, r * 0.55, col)
			_glyph(ci, "stone", c + Vector2(0.38, 0.3) * r, r * 0.55, col)
			_glyph(ci, "stone", c + Vector2(0.0, -0.3) * r, r * 0.55, col)
		"wind":
			for i in 3:
				var y := -0.45 + i * 0.45
				_pl(ci, c, r, [Vector2(-0.75, y), Vector2(0.25, y), Vector2(0.45, y - 0.12), Vector2(0.38, y - 0.3), Vector2(0.2, y - 0.25)], col, 2.2)
		"chevrons":
			for x in [-0.35, 0.2]:
				_pl(ci, c, r, [Vector2(x - 0.2, -0.5), Vector2(x + 0.2, 0.0), Vector2(x - 0.2, 0.5)], col, 3.0)
		"drop":
			var pts: Array = [Vector2(0.0, -0.8)]
			for i in 13:
				var a := PI * 0.15 + PI * 1.7 * i / 12.0
				pts.append(Vector2(sin(a) * 0.45, 0.25 - cos(a) * 0.45))
			_fill(ci, c, r, pts, RED)
		"eye", "eye_shut":
			var top: Array = []
			var bottom: Array = []
			for i in 13:
				var x := -0.8 + 1.6 * i / 12.0
				var h := 0.42 * (1.0 - pow(x / 0.8, 2.0))
				top.append(Vector2(x, -h))
				bottom.append(Vector2(x, h))
			_pl(ci, c, r, top, col, 2.2)
			_pl(ci, c, r, bottom, col, 2.2)
			_dot(ci, c, r, Vector2.ZERO, 0.2, col)
			if g == "eye_shut":
				_pl(ci, c, r, [Vector2(-0.7, 0.7), Vector2(0.7, -0.7)], col, 2.5)
		"shield", "shield_broken", "shield_plus":
			_dot(ci, c, r, Vector2.ZERO, 0.72, col)
			_ring(ci, c, r, Vector2.ZERO, 0.48, dark, 1.6)
			_dot(ci, c, r, Vector2.ZERO, 0.14, dark)
			if g == "shield_broken":
				_pl(ci, c, r, [Vector2(0.1, -0.8), Vector2(-0.12, -0.3), Vector2(0.15, 0.05), Vector2(-0.1, 0.4), Vector2(0.08, 0.8)], dark, 2.8)
			elif g == "shield_plus":
				_pl(ci, c, r, [Vector2(-0.3, 0.0), Vector2(0.3, 0.0)], dark, 3.0)
				_pl(ci, c, r, [Vector2(0.0, -0.3), Vector2(0.0, 0.3)], dark, 3.0)
		"hook":
			_pl(ci, c, r, [Vector2(-0.6, 0.7), Vector2(-0.2, 0.25)], col, 3.0)
			_ring(ci, c, r, Vector2(0.15, -0.12), 0.5, col, 3.0, PI * 0.75, PI * 2.1)
		"crescent":
			var pts: Array = []
			for i in 13:
				var a := -PI * 0.5 + PI * i / 12.0
				pts.append(Vector2(cos(a) * 0.7, sin(a) * 0.7))
			for i in 13:
				var a := PI * 0.5 - PI * i / 12.0
				pts.append(Vector2(cos(a) * 0.32 + 0.05, sin(a) * 0.62))
			_fill(ci, c, r, pts, col)
		"stars":
			_star(ci, c, r, Vector2(-0.38, -0.3), 0.3, col)
			_star(ci, c, r, Vector2(0.38, -0.25), 0.26, col)
			_star(ci, c, r, Vector2(0.0, 0.38), 0.32, col)
		"spiral":
			var pts: Array = []
			for i in 40:
				var a := i * 0.42
				pts.append(Vector2(cos(a), sin(a)) * (0.06 + i * 0.019))
			_pl(ci, c, r, pts, col, 2.2)
		"hourglass":
			_fill(ci, c, r, [Vector2(-0.45, -0.7), Vector2(0.45, -0.7), Vector2(0.0, 0.0)], col)
			_fill(ci, c, r, [Vector2(0.0, 0.0), Vector2(0.45, 0.7), Vector2(-0.45, 0.7)], col)
			_pl(ci, c, r, [Vector2(-0.55, -0.78), Vector2(0.55, -0.78)], col, 2.5)
			_pl(ci, c, r, [Vector2(-0.55, 0.78), Vector2(0.55, 0.78)], col, 2.5)
		"push", "retreat":
			var s := 1.0 if g == "push" else -1.0
			_pl(ci, c, r, [Vector2(-0.7 * s, -0.6), Vector2(-0.7 * s, 0.6)], col, 3.0)
			_pl(ci, c, r, [Vector2(-0.45 * s, 0.0), Vector2(0.5 * s, 0.0)], col, 3.0)
			_arrowhead(ci, c, r, Vector2(0.8 * s, 0.0), Vector2(s, 0.0), col, 0.4)
			_pl(ci, c, r, [Vector2(-0.3 * s, -0.4), Vector2(0.2 * s, -0.4)], col, 1.6)
			_pl(ci, c, r, [Vector2(-0.3 * s, 0.4), Vector2(0.2 * s, 0.4)], col, 1.6)
		"sweep":
			_ring(ci, c, r, Vector2.ZERO, 0.62, col, 3.0, -PI * 0.3, PI * 1.45)
			_arrowhead(ci, c, r, Vector2(cos(-PI * 0.3), sin(-PI * 0.3)) * 0.62 + Vector2(0.05, 0.2), Vector2(0.4, -1.0), col, 0.38)
			_dot(ci, c, r, Vector2.ZERO, 0.14, col)
		"return":
			_ring(ci, c, r, Vector2(0.0, -0.05), 0.5, col, 3.0, PI * 1.0, PI * 2.25)
			_pl(ci, c, r, [Vector2(-0.5, -0.05), Vector2(-0.5, 0.45)], col, 3.0)
			_arrowhead(ci, c, r, Vector2(-0.5, 0.75), Vector2(0, 1), col, 0.38)
		"rising":
			_pl(ci, c, r, [Vector2(-0.6, 0.65), Vector2(-0.1, 0.35), Vector2(0.3, -0.2), Vector2(0.45, -0.5)], col, 3.0)
			_arrowhead(ci, c, r, Vector2(0.55, -0.82), Vector2(0.3, -1.0), col, 0.4)
		"slashes2", "slashes3":
			var n := 2 if g == "slashes2" else 3
			for i in n:
				var o := (i - (n - 1) * 0.5) * 0.4
				_pl(ci, c, r, [Vector2(-0.45 + o, 0.6), Vector2(0.45 + o, -0.6)], col, 3.0)
		"crown":
			_fill(ci, c, r, [Vector2(-0.7, 0.45), Vector2(-0.7, -0.35), Vector2(-0.35, 0.05), Vector2(0.0, -0.55), Vector2(0.35, 0.05), Vector2(0.7, -0.35), Vector2(0.7, 0.45)], col)
			_pl(ci, c, r, [Vector2(-0.7, 0.62), Vector2(0.7, 0.62)], col, 3.0)
		"skull":
			_dot(ci, c, r, Vector2(0.0, -0.15), 0.55, col)
			_fill(ci, c, r, [Vector2(-0.3, 0.2), Vector2(0.3, 0.2), Vector2(0.25, 0.65), Vector2(-0.25, 0.65)], col)
			_dot(ci, c, r, Vector2(-0.22, -0.12), 0.15, dark)
			_dot(ci, c, r, Vector2(0.22, -0.12), 0.15, dark)
			_pl(ci, c, r, [Vector2(-0.1, 0.45), Vector2(-0.1, 0.65)], dark, 1.5)
			_pl(ci, c, r, [Vector2(0.1, 0.45), Vector2(0.1, 0.65)], dark, 1.5)
		"target":
			_ring(ci, c, r, Vector2.ZERO, 0.72, col, 2.2)
			_ring(ci, c, r, Vector2.ZERO, 0.42, col, 2.2)
			_dot(ci, c, r, Vector2.ZERO, 0.14, col)
		"paw":
			_fill(ci, c, r, [Vector2(-0.4, 0.55), Vector2(-0.3, 0.15), Vector2(0.0, 0.0), Vector2(0.3, 0.15), Vector2(0.4, 0.55), Vector2(0.0, 0.7)], col)
			for t in [Vector2(-0.55, -0.15), Vector2(-0.2, -0.45), Vector2(0.2, -0.45), Vector2(0.55, -0.15)]:
				_dot(ci, c, r, t, 0.15, col)
		"waves", "stomp", "stomp_big":
			_pl(ci, c, r, [Vector2(-0.85, 0.62), Vector2(0.85, 0.62)], col, 2.5)
			var rings := 3 if g == "stomp_big" else 2
			for i in rings:
				var s := 0.3 + i * 0.25
				_ring(ci, c, r, Vector2(0.0, 0.62), s, col, 2.0, PI * 1.12, PI * 1.88)
			if g != "waves":
				_pl(ci, c, r, [Vector2(0.0, 0.6), Vector2(0.0, -0.85)], col, 3.5)
		"brace":
			_pl(ci, c, r, [Vector2(-0.85, 0.7), Vector2(0.85, 0.7)], col, 2.5)
			_pl(ci, c, r, [Vector2(-0.5, 0.7), Vector2(0.3, -0.3)], col, 2.5)
			_fill(ci, c, r, [Vector2(0.62, -0.68), Vector2(0.38, -0.18), Vector2(0.22, -0.3)], col)
		"motion":
			_pl(ci, c, r, [Vector2(-0.8, -0.35), Vector2(0.1, -0.35)], col, 2.0)
			_pl(ci, c, r, [Vector2(-0.6, 0.0), Vector2(0.5, 0.0)], col, 2.0)
			_pl(ci, c, r, [Vector2(-0.8, 0.35), Vector2(0.1, 0.35)], col, 2.0)
			_arrowhead(ci, c, r, Vector2(0.85, 0.0), Vector2(1, 0), col, 0.35)
		"through", "through3":
			var n := 2 if g == "through" else 3
			for i in n:
				var x := -0.45 + i * (0.9 / (n - 1))
				_ring(ci, c, r, Vector2(x, 0.0), 0.2, col, 2.2)
			_pl(ci, c, r, [Vector2(-0.85, 0.0), Vector2(0.6, 0.0)], col, 2.2)
			_arrowhead(ci, c, r, Vector2(0.9, 0.0), Vector2(1, 0), col, 0.32)
		"split":
			_pl(ci, c, r, [Vector2(-0.85, 0.3), Vector2(-0.05, 0.0)], col, 2.2)
			for d in [Vector2(0.75, -0.55), Vector2(0.85, 0.0), Vector2(0.75, 0.55)]:
				_pl(ci, c, r, [Vector2(-0.05, 0.0), d * 0.85], col, 2.0)
				_arrowhead(ci, c, r, d, d - Vector2(-0.05, 0.0), col, 0.26)
		"plus":
			_pl(ci, c, r, [Vector2(-0.6, 0.0), Vector2(0.6, 0.0)], col, 4.0)
			_pl(ci, c, r, [Vector2(0.0, -0.6), Vector2(0.0, 0.6)], col, 4.0)
		"x":
			_pl(ci, c, r, [Vector2(-0.55, -0.55), Vector2(0.55, 0.55)], col, 4.0)
			_pl(ci, c, r, [Vector2(-0.55, 0.55), Vector2(0.55, -0.55)], col, 4.0)
		"down":
			_pl(ci, c, r, [Vector2(0.0, -0.75), Vector2(0.0, 0.35)], col, 4.0)
			_arrowhead(ci, c, r, Vector2(0.0, 0.85), Vector2(0, 1), col, 0.5)
		"helmet", "helmet_broken":
			_fill(ci, c, r, [Vector2(-0.65, 0.35), Vector2(-0.6, -0.15), Vector2(-0.35, -0.5), Vector2(0.0, -0.62), Vector2(0.35, -0.5), Vector2(0.6, -0.15), Vector2(0.65, 0.35), Vector2(0.3, 0.35), Vector2(0.25, 0.6), Vector2(-0.25, 0.6), Vector2(-0.3, 0.35)], col)
			if g == "helmet_broken":
				_pl(ci, c, r, [Vector2(-0.05, -0.62), Vector2(0.12, -0.25), Vector2(-0.1, 0.05), Vector2(0.08, 0.35)], dark, 2.8)
		_:
			_dot(ci, c, r, Vector2.ZERO, 0.3, col)
