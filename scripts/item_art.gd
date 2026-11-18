extends RefCounted
## The pictures of things in the bag, the chest, the trader's goods and the gear slots.
##
## Each item is drawn from shaded parts, lit from the upper left: blades in two bevelled faces
## with a ridge and a bright edge, wood with its grain, leather wrapped round grips, metal
## fittings that catch the light, cloth in soft folds, all outlined and casting a small shadow.
## The tile under it is dark, with a glow in the item's tier color behind the item; rare finds
## get a blue frame with corner pieces, legendary ones an orange frame that pulses and sparkles.

const OUTLINE := Color(0.03, 0.02, 0.015, 0.85)
const SHADOW := Color(0.0, 0.0, 0.0, 0.32)
const WOOD := Color(0.47, 0.31, 0.18)
const LEATHER := Color(0.34, 0.22, 0.13)
const BRONZE := Color(0.8, 0.6, 0.3)
const GOLD := Color(0.95, 0.76, 0.28)
const LIGHT := Vector2(-0.7, -0.7)       # where the light comes from, on the screen

static var _ci: CanvasItem               # what is being drawn on
static var _fade := 1.0                  # everything is drawn this opaque (a faded ghost in a slot)
static var _glow_tex: GradientTexture2D


# ---------------------------------------------------------------- the tile

## The tile an item lies on: its ground, a glow in `accent` (the tier's color, or blue / orange
## for rare / legendary finds, `rarity` 1 / 2) and a frame. `lit` when the pointer is on it.
static func tile(ci: CanvasItem, r: Rect2, accent: Color, rarity: int, lit: bool) -> void:
	_ci = ci
	_fade = 1.0
	var box := r.grow(-2.0)
	var top := Color(0.24, 0.19, 0.14, 0.97) if lit else Color(0.17, 0.135, 0.1, 0.97)
	var low := Color(0.09, 0.07, 0.05, 0.97)
	_grad(_rect_pts(box), [top, top, low, low])
	var pulse := 1.0
	if rarity == 2:
		pulse = 0.78 + 0.22 * sin(Time.get_ticks_msec() * 0.0035)
	var strength: float = [0.2, 0.36, 0.55][clampi(rarity, 0, 2)] * pulse * (1.3 if lit else 1.0)
	var glow_box := Rect2(box.get_center() - box.size * 0.55, box.size * 1.1)
	ci.draw_texture_rect(_glow(), glow_box.intersection(box), false, Color(accent.r, accent.g, accent.b, strength))
	ci.draw_rect(box, Color(0, 0, 0, 0.7), false, 1.0)
	ci.draw_rect(box.grow(-1.0), Color(accent.r, accent.g, accent.b, 0.5 if rarity == 0 else 0.9), false, 1.0 if rarity == 0 else 1.6)
	if rarity > 0:
		# Corner pieces, as on a box bound in metal.
		var arm := clampf(minf(box.size.x, box.size.y) * 0.28, 5.0, 12.0)
		var c := accent.lightened(0.25)
		for corner in [[box.position, Vector2(1, 1)], [Vector2(box.end.x, box.position.y), Vector2(-1, 1)],
				[Vector2(box.position.x, box.end.y), Vector2(1, -1)], [box.end, Vector2(-1, -1)]]:
			var p: Vector2 = corner[0] + corner[1] * 1.5
			var s: Vector2 = corner[1]
			ci.draw_line(p, p + Vector2(s.x * arm, 0), c, 2.5)
			ci.draw_line(p, p + Vector2(0, s.y * arm), c, 2.5)
	if rarity == 2:
		# Sparks that run round the frame.
		var t := Time.get_ticks_msec() * 0.00025
		var per := 2.0 * (box.size.x + box.size.y)
		for k in 3:
			var along := fposmod(t * per + per * k / 3.0, per)
			_spark(_round_frame(box.grow(-1.0), along), 3.0 + sin(t * 40.0 + k) * 1.2, Color(1.0, 0.9, 0.6, 0.9 * pulse))


static func _round_frame(b: Rect2, along: float) -> Vector2:
	if along < b.size.x:
		return b.position + Vector2(along, 0)
	along -= b.size.x
	if along < b.size.y:
		return Vector2(b.end.x, b.position.y + along)
	along -= b.size.y
	if along < b.size.x:
		return Vector2(b.end.x - along, b.end.y)
	along -= b.size.x
	return Vector2(b.position.x, b.end.y - along)


static func _spark(p: Vector2, s: float, c: Color) -> void:
	_ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.25, -s * 0.25), p + Vector2(s, 0), p + Vector2(s * 0.25, s * 0.25),
		p + Vector2(0, s), p + Vector2(-s * 0.25, s * 0.25), p + Vector2(-s, 0), p + Vector2(-s * 0.25, -s * 0.25)]), c)


static func _glow() -> GradientTexture2D:
	if _glow_tex == null:
		_glow_tex = GradientTexture2D.new()
		_glow_tex.width = 64
		_glow_tex.height = 64
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(0.5, 0.0)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.45))
		_glow_tex.gradient = g
	return _glow_tex


# ---------------------------------------------------------------- the item

## Draws the item `def` (an entry of data/items.gd, with its `id`) inside `r`. `fade` < 1 draws
## it as a faint ghost.
static func icon(ci: CanvasItem, r: Rect2, id: String, def: Dictionary, fade: float = 1.0) -> void:
	_ci = ci
	_fade = fade
	var col: Color = def.get("color", Color(0.7, 0.7, 0.7))
	var metal := col if col.r > 0.55 and col.g > 0.45 else BRONZE
	var c := r.get_center()
	var w := r.size.x
	var h := r.size.y
	var top := r.position.y
	var bottom := r.end.y
	var gilded: bool = int(def.get("rarity", 0)) >= 2
	match str(def.get("kind", "")):
		"dagger", "sword", "sword_short", "sword_long":
			var share: float = {"dagger": 0.56, "sword_short": 0.62, "sword": 0.67, "sword_long": 0.71}[def["kind"]]
			var half := clampf(w * (0.15 if def["kind"] == "dagger" else 0.12), 3.0, 7.0)
			var guard_y := top + h * share
			_blade(Vector2(c.x, top + 2.0), Vector2(c.x, guard_y), half * 1.1, half * 0.95, metal)
			_hilt(c.x, guard_y, bottom, half, GOLD if gilded or id.begins_with("gilded") else metal.darkened(0.15), gilded)
		"sickle":
			_khopesh(r, metal, gilded)
		"staff":
			_staff(r, id, gilded)
		"spear", "spear_long":
			var head_end := top + h * (0.2 if def["kind"] == "spear" else 0.16)
			_rod(Vector2(c.x, head_end + 2.0), Vector2(c.x, bottom - 3.0), clampf(w * 0.07, 2.0, 3.2), WOOD, true)
			var spear_metal := metal if metal != WOOD else Color(0.7, 0.7, 0.72)
			_leaf(Vector2(c.x, top + 1.0), Vector2(c.x, head_end), clampf(w * 0.17, 4.0, 8.0), spear_metal)
			_band(Vector2(c.x, head_end + 1.0), clampf(w * 0.1, 3.0, 4.5), 4.0, spear_metal.darkened(0.1))
			_wrap(Vector2(c.x, head_end + 6.0), Vector2(c.x, head_end + 18.0), clampf(w * 0.075, 2.2, 3.4), LEATHER)
			_cone(Vector2(c.x, bottom), Vector2(c.x, bottom - 9.0), 3.0, spear_metal.darkened(0.2))
		"club":
			_club(r, col if col.r < 0.55 else WOOD, id == "thorn_club")
		"mace":
			var head_r := clampf(w * 0.3, 7.0, 13.0)
			_rod(Vector2(c.x, top + head_r * 1.5), Vector2(c.x, bottom - 4.0), clampf(w * 0.075, 2.2, 3.4), WOOD, true)
			_wrap(Vector2(c.x, bottom - h * 0.3), Vector2(c.x, bottom - 6.0), clampf(w * 0.09, 2.6, 4.0), LEATHER)
			if def.get("color", BRONZE).r < 0.6:
				_stone_head(Vector2(c.x, top + head_r + 2.0), head_r, col)
			else:
				_ball(Vector2(c.x, top + head_r + 2.0), head_r, metal)
				for k in [-1.0, 1.0]:
					_ci.draw_line(Vector2(c.x + k * head_r * 0.5, top + head_r * 0.35 + 2.0), Vector2(c.x + k * head_r * 0.5, top + head_r * 1.65 + 2.0), _a(metal.darkened(0.35)), 1.5, true)
			_band(Vector2(c.x, top + head_r * 2.0 + 3.0), clampf(w * 0.09, 2.6, 4.0), 3.0, metal.darkened(0.2))
		"axe":
			_axe(r, metal, id)
		"bow":
			_bow(r, col, gilded)
		"shield":
			_shield(r, id, col)
		"sling":
			_sling(r, col)
		"cap", "helmet":
			_headgear(r, def, col, id)
		"necklace":
			_necklace(r, col, id)
		"belt":
			_belt(r, col, id)
		"tunic", "armor":
			_tunic(r, col, id, def)
		"kilt", "skirt":
			_kilt(r, col, id)
		"robe", "dress":
			_robe(r, col, id)
		"skin":
			_skin(r, col)
		"sting":
			_sting(r, col)
		"stones":
			for p in [Vector2(-0.22, 0.12), Vector2(0.2, 0.16), Vector2(0.0, -0.18)]:
				_ball(c + Vector2(p.x * w, p.y * h), minf(w, h) * 0.17, col)
		"arrows":
			for k in 3:
				var x := c.x - w * 0.22 + k * w * 0.22
				_rod(Vector2(x, top + 12.0), Vector2(x, bottom - 2.0), 1.4, Color(0.62, 0.5, 0.32), false)
				_leaf(Vector2(x, top + 1.0), Vector2(x, top + 13.0), 4.0, Color(0.68, 0.68, 0.72))
				for side in [-1.0, 1.0]:
					var fl := PackedVector2Array([Vector2(x, bottom - 14.0), Vector2(x + side * 4.0, bottom - 10.0), Vector2(x + side * 4.0, bottom - 3.0), Vector2(x, bottom - 6.0)])
					_part(fl, Color(0.95, 0.92, 0.85), Color(0.7, 0.66, 0.6))


# ---------------------------------------------------------------- weapons

## A straight blade from `tip` to `base`: two bevelled faces meeting at a ridge, the lit one
## lighter, a bright edge, and an outline.
static func _blade(tip: Vector2, base: Vector2, half_base: float, half_mid: float, col: Color) -> void:
	var along := base - tip
	var d := along.normalized()
	var n := _lit_normal(d)
	var shoulder := tip + along * 0.16
	var outline := PackedVector2Array([tip, shoulder + n * half_mid, base + n * half_base, base - n * half_base, shoulder - n * half_mid])
	_shadow(outline)
	var light := col.lightened(0.55)
	var mid := col.lightened(0.15)
	var dark := col.darkened(0.4)
	_grad(PackedVector2Array([tip, shoulder + n * half_mid, base + n * half_base, base]), [light.lightened(0.2), light, mid, mid.lightened(0.1)])
	_grad(PackedVector2Array([tip, base, base - n * half_base, shoulder - n * half_mid]), [mid, dark, dark.darkened(0.2), dark])
	# The fuller down the middle, and the light along the ridge and the edge.
	_ci.draw_line(tip + along * 0.22, base - d * 3.0, _a(Color(dark.r, dark.g, dark.b, 0.55)), 1.6, true)
	_ci.draw_line(tip + along * 0.22 + n * 1.2, base - d * 3.0 + n * 1.2, _a(Color(1, 1, 1, 0.35)), 1.0, true)
	_ci.draw_polyline(PackedVector2Array([tip, shoulder + n * half_mid, base + n * half_base]), _a(Color(1, 1, 1, 0.7)), 1.0, true)
	_edge(outline)


## The guard, the wrapped grip and the pommel of a sword or dagger.
static func _hilt(x: float, guard_y: float, bottom: float, half: float, fittings: Color, gem: bool) -> void:
	var gw := half * 2.7
	var guard := PackedVector2Array([Vector2(x - gw, guard_y), Vector2(x + gw, guard_y), Vector2(x + gw * 0.85, guard_y + 5.0), Vector2(x - gw * 0.85, guard_y + 5.0)])
	_shadow(guard)
	_part(guard, fittings.lightened(0.35), fittings.darkened(0.35))
	_ci.draw_line(Vector2(x - gw + 1.0, guard_y + 1.0), Vector2(x + gw - 1.0, guard_y + 1.0), _a(Color(1, 1, 1, 0.55)), 1.0, true)
	var pommel_r := clampf(half * 0.85, 3.0, 5.5)
	_wrap(Vector2(x, guard_y + 5.0), Vector2(x, bottom - pommel_r * 1.6), clampf(half * 0.55, 2.2, 3.6), LEATHER)
	_ball(Vector2(x, bottom - pommel_r - 1.0), pommel_r, fittings)
	if gem:
		_ball(Vector2(x, guard_y + 2.5), 2.6, Color(0.75, 0.12, 0.12))


## The khopesh: a grip, a straight neck, and the hooked blade that curves forward over it.
static func _khopesh(r: Rect2, metal: Color, gilded: bool) -> void:
	var w := r.size.x
	var h := r.size.y
	var x := r.get_center().x - w * 0.12
	var grip_top := r.position.y + h * 0.7
	var rad := clampf(minf(w * 0.5, h * 0.3), 10.0, 26.0)
	var center := Vector2(x + rad * 0.55, r.position.y + rad + 3.0)
	# The neck, from the grip up to where the curve begins.
	var neck_top := center + Vector2(-rad, 0)
	var neck := PackedVector2Array([neck_top + Vector2(-2.6, 0), neck_top + Vector2(2.6, 0), Vector2(x + 2.4, grip_top), Vector2(x - 2.4, grip_top)])
	_shadow(neck)
	_part(neck, metal.lightened(0.3), metal.darkened(0.35))
	# The curve: thick in the middle and drawn to a point at its end.
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var cols_outer: Array = []
	var cols_inner: Array = []
	var a0 := PI
	var a1 := TAU + 0.55
	var steps := 18
	for k in steps + 1:
		var f := float(k) / steps
		var a := lerpf(a0, a1, f)
		var thick := rad * 0.62 * sin(PI * minf(1.0, f * 1.1 + 0.08)) + 2.5 * (1.0 - f)
		outer.append(center + Vector2(cos(a), sin(a)) * rad)
		inner.append(center + Vector2(cos(a), sin(a)) * maxf(rad - thick, rad * 0.25))
		cols_outer.append(metal.lightened(0.5))
		cols_inner.append(metal.darkened(0.3))
	var shape := PackedVector2Array()
	var cols: Array = []
	for k in outer.size():
		shape.append(outer[k])
		cols.append(cols_outer[k])
	for k in range(inner.size() - 1, -1, -1):
		shape.append(inner[k])
		cols.append(cols_inner[k])
	_shadow(shape)
	_grad(shape, cols)
	_ci.draw_polyline(outer, _a(Color(1, 1, 1, 0.7)), 1.2, true)
	_edge(shape)
	_hilt(x, grip_top - 2.0, r.end.y, clampf(w * 0.1, 2.5, 4.0), GOLD if gilded else metal.darkened(0.2), gilded)


## A shepherd's staff: a long rod of wood with a crook at the top; a bronze-shod one has metal
## at the foot, the elders' carved bands and a gold cap.
static func _staff(r: Rect2, id: String, gilded: bool) -> void:
	var w := r.size.x
	var x := r.get_center().x - w * 0.08
	var top := r.position.y
	var bottom := r.end.y
	var half := clampf(w * 0.08, 2.4, 3.6)
	var hook := clampf(w * 0.22, 5.0, 10.0)
	_rod(Vector2(x, top + hook + 2.0), Vector2(x, bottom - 2.0), half, WOOD, true)
	# The crook: a thick arc drawn as a dark rope, then the wood over it, then its light.
	var arc := PackedVector2Array()
	for k in 13:
		var a := PI + PI * 1.15 * k / 12.0
		arc.append(Vector2(x + hook, top + hook + 2.0) + Vector2(cos(a), sin(a)) * hook)
	_ci.draw_polyline(arc, _a(SHADOW), half * 2.0 + 2.0, true)
	_ci.draw_polyline(arc, _a(OUTLINE), half * 2.0 + 1.5, true)
	_ci.draw_polyline(arc, _a(WOOD), half * 2.0 - 0.5, true)
	_ci.draw_polyline(arc, _a(WOOD.lightened(0.35)), 1.0, true)
	_wrap(Vector2(x, top + r.size.y * 0.42), Vector2(x, top + r.size.y * 0.56), half + 0.8, LEATHER)
	if id == "shod_staff" or gilded:
		_cone(Vector2(x, bottom), Vector2(x, bottom - 12.0), half + 0.8, BRONZE)
	if gilded:
		for k in 3:
			_band(Vector2(x, top + r.size.y * (0.25 + 0.12 * k)), half + 0.6, 2.5, GOLD)
		_ball(Vector2(x + hook * 2.0, top + hook + 2.0), half + 0.8, GOLD)


## A leaf-shaped head of a spear or an arrow, from `tip` to `base`.
static func _leaf(tip: Vector2, base: Vector2, half: float, col: Color) -> void:
	var along := base - tip
	var n := _lit_normal(along.normalized())
	var wide := tip + along * 0.55
	var neck := base - along.normalized() * 1.0
	var pts := PackedVector2Array([tip, wide + n * half, neck + n * half * 0.35, neck - n * half * 0.35, wide - n * half])
	_shadow(pts)
	_grad(PackedVector2Array([tip, wide + n * half, neck + n * half * 0.35, neck]), [col.lightened(0.6), col.lightened(0.4), col.lightened(0.1), col])
	_grad(PackedVector2Array([tip, neck, neck - n * half * 0.35, wide - n * half]), [col.lightened(0.1), col.darkened(0.3), col.darkened(0.45), col.darkened(0.35)])
	_ci.draw_line(tip + along * 0.1, neck, _a(Color(1, 1, 1, 0.35)), 1.0, true)
	_ci.draw_polyline(PackedVector2Array([tip, wide + n * half, neck + n * half * 0.35]), _a(Color(1, 1, 1, 0.6)), 1.0, true)
	_edge(pts)


static func _club(r: Rect2, col: Color, thorns: bool) -> void:
	var w := r.size.x
	var x := r.get_center().x
	var top := r.position.y
	var bottom := r.end.y
	var fat := clampf(w * 0.24, 5.0, 11.0)
	var thin := clampf(w * 0.08, 2.4, 3.6)
	var pts := PackedVector2Array([Vector2(x - thin, bottom - 3.0), Vector2(x - fat * 0.9, top + fat * 1.6), Vector2(x - fat * 0.7, top + fat * 0.5),
		Vector2(x, top + 2.0), Vector2(x + fat * 0.7, top + fat * 0.5), Vector2(x + fat, top + fat * 1.6), Vector2(x + thin, bottom - 3.0)])
	_shadow(pts)
	_part(pts, col.lightened(0.35), col.darkened(0.4))
	for k in 3:
		var p := Vector2(x + [-0.3, 0.35, -0.1][k] * fat, top + r.size.y * [0.18, 0.3, 0.45][k])
		_ci.draw_circle(p, 1.8, _a(col.darkened(0.5)))
		_ci.draw_arc(p, 2.6, PI * 0.9, PI * 1.9, 6, _a(col.darkened(0.3)), 1.0, true)
	_ci.draw_line(Vector2(x - fat * 0.45, top + fat * 0.8), Vector2(x - thin * 0.6, bottom - r.size.y * 0.3), _a(Color(1, 1, 1, 0.25)), 1.2, true)
	_wrap(Vector2(x, bottom - r.size.y * 0.26), Vector2(x, bottom - 5.0), thin + 1.0, LEATHER)
	if thorns:
		for k in 6:
			var side := -1.0 if k % 2 == 0 else 1.0
			var y := top + fat * 0.6 + k * r.size.y * 0.06
			var base_x := x + side * lerpf(fat * 0.75, fat * 0.95, float(k) / 5.0)
			var spike := PackedVector2Array([Vector2(base_x, y - 2.5), Vector2(base_x + side * 5.0, y), Vector2(base_x, y + 2.5)])
			_part(spike, Color(0.85, 0.82, 0.75), Color(0.45, 0.42, 0.38))


static func _stone_head(c: Vector2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 9:
		var a := TAU * k / 9.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad * (0.88 + 0.12 * sin(k * 2.7)))
	_shadow(pts)
	_part(pts, col.lightened(0.3), col.darkened(0.4))
	for k in 5:
		_ci.draw_circle(c + Vector2(cos(k * 1.9), sin(k * 2.3)) * rad * 0.5, 1.0, _a(col.darkened(0.45)))


## An axe: a haft, and a bronze head bound to it whose edge is a curve, ground bright. A
## duckbill axe has its two openings.
static func _axe(r: Rect2, metal: Color, id: String) -> void:
	var w := r.size.x
	var h := r.size.y
	var x := r.position.x + w * 0.3
	var top := r.position.y
	_rod(Vector2(x, top + 3.0), Vector2(x, r.end.y - 3.0), clampf(w * 0.05, 2.2, 3.4), WOOD, true)
	var head_top := top + h * 0.05
	var head_low := top + h * 0.38
	var edge_x := r.end.x - 3.0
	var pts := PackedVector2Array([Vector2(x + 2.0, head_top + h * 0.06), Vector2(x + w * 0.2, head_top + h * 0.05)])
	for k in 9:
		var f := float(k) / 8.0
		pts.append(Vector2(lerpf(edge_x - w * 0.08, edge_x, sin(PI * f)), lerpf(head_top, head_low, f)))
	pts.append(Vector2(x + w * 0.2, head_low - h * 0.05))
	pts.append(Vector2(x + 2.0, head_low - h * 0.07))
	_shadow(pts)
	_part(pts, metal.lightened(0.35), metal.darkened(0.4))
	var edge := PackedVector2Array()
	for k in 9:
		var f := float(k) / 8.0
		edge.append(Vector2(lerpf(edge_x - w * 0.08, edge_x, sin(PI * f)) - 2.5, lerpf(head_top, head_low, f) + (1.5 if k == 0 else (-1.5 if k == 8 else 0.0))))
	_ci.draw_polyline(edge, _a(Color(1, 1, 1, 0.6)), 2.0, true)
	if id == "duckbill_axe":
		for k in [0.33, 0.67]:
			var hole := Vector2(x + w * 0.38, lerpf(head_top, head_low, k))
			_ci.draw_circle(hole, clampf(w * 0.07, 2.0, 4.0), _a(Color(0.08, 0.06, 0.04)))
	_wrap(Vector2(x, head_top + h * 0.04), Vector2(x, head_low - h * 0.04), clampf(w * 0.06, 2.6, 4.0), LEATHER)
	_wrap(Vector2(x, r.end.y - h * 0.24), Vector2(x, r.end.y - 6.0), clampf(w * 0.06, 2.6, 4.0), LEATHER)


## A recurved bow: the limbs as a thick dark line with the wood over it and a light along it,
## the string, and the grip wrapped in leather.
static func _bow(r: Rect2, col: Color, gilded: bool) -> void:
	var h := r.size.y
	var w := r.size.x
	var x0 := r.position.x + w * 0.3
	var limb := PackedVector2Array()
	for k in 21:
		var f := float(k) / 20.0
		var y := r.position.y + 4.0 + f * (h - 8.0)
		var bend := sin(PI * f) * w * 0.38 - (0.0 if f > 0.12 and f < 0.88 else w * 0.12 * (1.0 - absf(f - 0.5) / 0.5 * 0.0))
		var recurve := -w * 0.1 * (pow(maxf(0.0, 0.1 - f), 1.0) / 0.1 + pow(maxf(0.0, f - 0.9), 1.0) / 0.1)
		limb.append(Vector2(x0 + bend + recurve, y))
	var tips := [limb[1], limb[limb.size() - 2]]
	_ci.draw_line(tips[0], tips[1], _a(Color(0.92, 0.88, 0.8, 0.9)), 1.2, true)
	var shade := PackedVector2Array()
	for p in limb:
		shade.append(p + Vector2(2.0, 3.0))
	_ci.draw_polyline(shade, _a(SHADOW), 6.0, true)
	_ci.draw_polyline(limb, _a(OUTLINE), 6.5, true)
	_ci.draw_polyline(limb, _a(col.lightened(0.05)), 4.5, true)
	var lit := PackedVector2Array()
	for p in limb:
		lit.append(p + Vector2(-1.0, -0.5))
	_ci.draw_polyline(lit, _a(col.lightened(0.45)), 1.2, true)
	var mid: Vector2 = limb[10]
	_wrap(mid + Vector2(0, -h * 0.08), mid + Vector2(0, h * 0.08), 3.6, LEATHER)
	if gilded:
		for t in tips:
			_ball(t, 2.8, GOLD)


static func _shield(r: Rect2, id: String, col: Color) -> void:
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.46
	match id:
		"hide_shield":
			var pts := _oval(c, rad * 0.82, rad, 20)
			_shadow(pts)
			_part(pts, col.lightened(0.3), col.darkened(0.35))
			for k in 14:
				var a := TAU * k / 14.0
				_ci.draw_circle(c + Vector2(cos(a) * rad * 0.7, sin(a) * rad * 0.86), 1.2, _a(Color(0.9, 0.85, 0.7)))
			_ball(c, rad * 0.2, col.lightened(0.15))
		"wicker_shield":
			var pts := _oval(c, rad, rad, 22)
			_shadow(pts)
			_part(pts, col.lightened(0.2), col.darkened(0.3))
			for k in range(1, 5):
				_ci.draw_arc(c, rad * k / 5.0, 0.0, TAU, 28, _a(col.darkened(0.35)), 1.4, true)
			for k in 8:
				var a := TAU * k / 8.0
				_ci.draw_line(c + Vector2(cos(a), sin(a)) * rad * 0.2, c + Vector2(cos(a), sin(a)) * rad * 0.95, _a(col.darkened(0.25)), 1.0, true)
			_ball(c, rad * 0.18, WOOD)
		_:
			var rim_col := GOLD if id == "giants_shield" else BRONZE.darkened(0.1)
			var face_col := col if id != "rimmed_shield" else Color(0.55, 0.38, 0.22)
			var outer := _oval(c, rad, rad, 28)
			_shadow(outer)
			_part(outer, rim_col.lightened(0.35), rim_col.darkened(0.4))
			var face := _oval(c, rad * 0.84, rad * 0.84, 28)
			_part(face, face_col.lightened(0.3), face_col.darkened(0.35))
			if id != "rimmed_shield":
				for k in range(1, 3):
					_ci.draw_arc(c, rad * (0.35 + 0.22 * k), 0.0, TAU, 28, _a(face_col.darkened(0.3)), 1.2, true)
			for k in 10:
				var a := TAU * k / 10.0
				_ball(c + Vector2(cos(a), sin(a)) * rad * 0.92, maxf(1.4, rad * 0.06), rim_col)
			_ball(c, rad * 0.24, rim_col)
			_ci.draw_arc(c, rad * 0.8, PI * 1.05, PI * 1.45, 10, _a(Color(1, 1, 1, 0.35)), 2.0, true)


static func _sling(r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var top := r.position.y
	var bottom := r.end.y
	var pouch := Vector2(c.x, bottom - r.size.y * 0.22)
	for side in [-1.0, 1.0]:
		var cord := PackedVector2Array()
		for k in 9:
			var f := float(k) / 8.0
			cord.append(Vector2(c.x + side * (3.0 + sin(PI * f) * r.size.x * 0.12) * (1.0 - f * 0.4), lerpf(top + 2.0, pouch.y - 3.0, f)))
		_ci.draw_polyline(cord, _a(OUTLINE), 3.2, true)
		_ci.draw_polyline(cord, _a(col), 2.0, true)
	_ci.draw_circle(Vector2(c.x - 3.0, top + 3.0), 2.6, _a(col.darkened(0.2)))
	var cup := _oval(pouch, r.size.x * 0.28, r.size.y * 0.1, 14)
	_shadow(cup)
	_part(cup, LEATHER.lightened(0.3), LEATHER.darkened(0.3))
	_ball(pouch + Vector2(0, -2.0), r.size.x * 0.12, Color(0.62, 0.58, 0.52))


# ---------------------------------------------------------------- what is worn

static func _headgear(r: Rect2, def: Dictionary, col: Color, id: String) -> void:
	var c := r.get_center() + Vector2(0, r.size.y * 0.08)
	var rad := minf(r.size.x, r.size.y) * 0.42
	var dome := PackedVector2Array()
	for k in 15:
		var a := PI + PI * k / 14.0
		dome.append(c + Vector2(cos(a), sin(a)) * Vector2(rad, rad * 1.05))
	_shadow(dome)
	var metal: bool = def["kind"] == "helmet"
	_part(dome, col.lightened(0.45 if metal else 0.25), col.darkened(0.4 if metal else 0.25))
	if metal:
		_ci.draw_arc(c, rad * 0.7, PI * 1.15, PI * 1.5, 8, _a(Color(1, 1, 1, 0.55)), 2.0, true)
		var rim := PackedVector2Array([c + Vector2(-rad * 1.08, -1.0), c + Vector2(rad * 1.08, -1.0), c + Vector2(rad * 1.0, 5.0), c + Vector2(-rad * 1.0, 5.0)])
		_part(rim, col.lightened(0.2), col.darkened(0.45))
		for k in 5:
			_ball(c + Vector2(-rad * 0.8 + k * rad * 0.4, 2.0), 1.4, col.lightened(0.3))
		if id == "crested_helmet":
			var crest := PackedVector2Array()
			for k in 9:
				var a := PI * 1.12 + PI * 0.76 * k / 8.0
				crest.append(c + Vector2(cos(a), sin(a)) * rad * 1.28)
			_ci.draw_polyline(crest, _a(OUTLINE), 5.0, true)
			_ci.draw_polyline(crest, _a(GOLD), 3.2, true)
	else:
		for k in 3:
			var x := c.x - rad * 0.5 + k * rad * 0.5
			_ci.draw_line(Vector2(x, c.y - rad * 0.85), Vector2(x * 0.98 + c.x * 0.02, c.y - 1.0), _a(col.darkened(0.2)), 1.0, true)
		var band := PackedVector2Array([c + Vector2(-rad * 1.02, -4.0), c + Vector2(rad * 1.02, -4.0), c + Vector2(rad * 1.02, 1.5), c + Vector2(-rad * 1.02, 1.5)])
		_part(band, Color(0.3, 0.42, 0.75) if id == "headcloth" else col.darkened(0.3), Color(0.15, 0.22, 0.45) if id == "headcloth" else col.darkened(0.55))


static func _necklace(r: Rect2, col: Color, id: String) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var count := 11
	for k in count:
		var a := PI * 0.08 + PI * 0.84 * k / (count - 1)
		var p := c + Vector2(cos(a) * s * 0.4, sin(a) * s * 0.32 - s * 0.14)
		_ball(p, maxf(1.6, s * 0.06), col)
	var pend := c + Vector2(0, s * 0.3)
	if id == "gold_pectoral":
		var plate := PackedVector2Array([pend + Vector2(-s * 0.2, -s * 0.12), pend + Vector2(s * 0.2, -s * 0.12), pend + Vector2(s * 0.12, s * 0.1), pend + Vector2(-s * 0.12, s * 0.1)])
		_shadow(plate)
		_part(plate, GOLD.lightened(0.4), GOLD.darkened(0.35))
		_ball(pend, s * 0.06, Color(0.2, 0.45, 0.8))
	else:
		_ball(pend, maxf(2.5, s * 0.1), col.lightened(0.15))


static func _belt(r: Rect2, col: Color, id: String) -> void:
	var c := r.get_center()
	var strap := _rect_pts(Rect2(r.position.x + 1.0, c.y - 6.0, r.size.x - 2.0, 12.0))
	_shadow(strap)
	_grad(strap, [col.lightened(0.3), col.lightened(0.3), col.darkened(0.3), col.darkened(0.3)])
	_edge(strap)
	var x := r.position.x + 4.0
	while x < r.end.x - 4.0:
		_ci.draw_line(Vector2(x, c.y - 4.0), Vector2(x + 2.0, c.y - 4.0), _a(col.lightened(0.45)), 1.0)
		_ci.draw_line(Vector2(x, c.y + 4.0), Vector2(x + 2.0, c.y + 4.0), _a(col.lightened(0.45)), 1.0)
		x += 5.0
	if id == "studded_belt":
		for k in 5:
			_ball(Vector2(r.position.x + r.size.x * (0.1 + 0.2 * k), c.y), 2.0, BRONZE)
	var buckle := Rect2(c.x - 7.0, c.y - 8.0, 14.0, 16.0)
	_ci.draw_rect(buckle.grow(1.0), _a(OUTLINE), false, 4.5)
	_ci.draw_rect(buckle, _a(BRONZE.lightened(0.15)), false, 3.0)
	_ci.draw_line(buckle.position + Vector2(1.0, 1.0), Vector2(buckle.end.x - 1.0, buckle.position.y + 1.0), _a(Color(1, 1, 1, 0.6)), 1.0)


static func _tunic(r: Rect2, col: Color, id: String, def: Dictionary) -> void:
	var w := r.size.x
	var x0 := r.position.x
	var top := r.position.y
	var bottom := r.end.y
	var pts := PackedVector2Array([
		Vector2(x0 + w * 0.32, top), Vector2(x0 + w * 0.68, top), Vector2(r.end.x, top + 18.0),
		Vector2(r.end.x - 9.0, top + 34.0), Vector2(x0 + w * 0.8, top + 26.0), Vector2(x0 + w * 0.8, bottom),
		Vector2(x0 + w * 0.2, bottom), Vector2(x0 + w * 0.2, top + 26.0), Vector2(x0 + 9.0, top + 34.0),
		Vector2(x0, top + 18.0)])
	_shadow(pts)
	_part(pts, col.lightened(0.3), col.darkened(0.35))
	var body := Rect2(x0 + w * 0.22, top + 14.0, w * 0.56, bottom - top - 16.0)
	match id:
		"bronze_scale", "maryannu_scale":
			var row := 0
			var y := body.position.y
			while y < body.end.y - 3.0:
				var x := body.position.x + (3.0 if row % 2 == 1 else 0.0)
				while x < body.end.x - 3.0:
					_ci.draw_arc(Vector2(x + 3.0, y + 2.0), 3.0, 0.1, PI - 0.1, 5, _a(col.darkened(0.45)), 1.0, true)
					_ci.draw_circle(Vector2(x + 2.0, y + 1.0), 0.8, _a(col.lightened(0.5)))
					x += 6.0
				y += 4.5
				row += 1
		"iron_mail":
			var y := body.position.y
			while y < body.end.y:
				var x := body.position.x + 2.0
				while x < body.end.x - 1.0:
					_ball(Vector2(x, y + 2.0), 1.1, col)
					x += 5.0
				y += 5.0
		"leather":
			for k in 3:
				var y := body.position.y + body.size.y * (0.2 + 0.28 * k)
				_ci.draw_line(Vector2(body.position.x, y), Vector2(body.end.x, y), _a(col.darkened(0.45)), 2.0, true)
				_ball(Vector2(body.get_center().x, y), 1.6, BRONZE)
		"linen":
			for k in 4:
				var x := body.position.x + body.size.x * (0.15 + 0.23 * k)
				_ci.draw_line(Vector2(x, body.position.y), Vector2(x, body.end.y), _a(col.darkened(0.25)), 1.0, true)
		_:
			for k in 2:
				var x := body.position.x + body.size.x * (0.3 + 0.4 * k)
				_ci.draw_line(Vector2(x, body.position.y + 6.0), Vector2(x - 2.0, body.end.y - 2.0), _a(col.darkened(0.2)), 1.0, true)
	_ci.draw_polyline(PackedVector2Array([Vector2(r.get_center().x - 7.0, top + 1.0), Vector2(r.get_center().x, top + 11.0), Vector2(r.get_center().x + 7.0, top + 1.0)]), _a(col.darkened(0.55)), 2.0, true)
	_edge(pts)


static func _kilt(r: Rect2, col: Color, id: String) -> void:
	var x0 := r.position.x
	var top := r.position.y
	var pts := PackedVector2Array([Vector2(x0 + 9.0, top + 4.0), Vector2(r.end.x - 9.0, top + 4.0), Vector2(r.end.x - 1.0, r.end.y), Vector2(x0 + 1.0, r.end.y)])
	_shadow(pts)
	_part(pts, col.lightened(0.3), col.darkened(0.3))
	for k in 6:
		var f := (k + 1) / 7.0
		_ci.draw_line(Vector2(lerpf(x0 + 9.0, r.end.x - 9.0, f), top + 9.0), Vector2(lerpf(x0 + 1.0, r.end.x - 1.0, f), r.end.y - 1.0), _a(col.darkened(0.22)), 1.0, true)
	var band := _rect_pts(Rect2(x0 + 8.0, top + 2.0, r.size.x - 16.0, 6.0))
	_part(band, col.darkened(0.2), col.darkened(0.5))
	if id == "bronze_greaves" or id == "leg_wraps":
		var metal := BRONZE if id == "bronze_greaves" else LEATHER
		for side in [-1.0, 1.0]:
			var gx: float = r.get_center().x + side * r.size.x * 0.2
			var greave := PackedVector2Array([Vector2(gx - 4.0, top + r.size.y * 0.45), Vector2(gx + 4.0, top + r.size.y * 0.45), Vector2(gx + 3.0, r.end.y - 2.0), Vector2(gx - 3.0, r.end.y - 2.0)])
			_part(greave, metal.lightened(0.35), metal.darkened(0.35))
	_edge(pts)


static func _robe(r: Rect2, col: Color, id: String) -> void:
	var w := r.size.x
	var x0 := r.position.x
	var top := r.position.y
	var pts := PackedVector2Array([
		Vector2(x0 + w * 0.32, top), Vector2(x0 + w * 0.68, top), Vector2(r.end.x - 2.0, top + 22.0),
		Vector2(r.end.x - 9.0, top + 36.0), Vector2(x0 + w * 0.75, top + 28.0), Vector2(r.end.x - 2.0, r.end.y),
		Vector2(x0 + 2.0, r.end.y), Vector2(x0 + w * 0.25, top + 28.0), Vector2(x0 + 9.0, top + 36.0),
		Vector2(x0 + 2.0, top + 22.0)])
	_shadow(pts)
	_part(pts, col.lightened(0.3), col.darkened(0.35))
	for k in 3:
		var x := x0 + w * (0.35 + 0.15 * k)
		_ci.draw_line(Vector2(x, top + 30.0), Vector2(x + (k - 1) * 4.0, r.end.y - 2.0), _a(col.darkened(0.25)), 1.2, true)
	var trim := Color(0.85, 0.7, 0.3) if id == "priestly_robe" or id == "dress" else col.darkened(0.45)
	_ci.draw_line(Vector2(x0 + 4.0, r.end.y - 5.0), Vector2(r.end.x - 4.0, r.end.y - 5.0), _a(trim), 3.0)
	if id == "dress":
		for k in 6:
			_ci.draw_circle(Vector2(r.get_center().x, top + 16.0 + k * 9.0), 1.3, _a(Color(0.9, 0.85, 0.6)))
	if id == "cloak":
		var mantle := PackedVector2Array([Vector2(x0 + w * 0.25, top + 2.0), Vector2(x0 + w * 0.75, top + 2.0), Vector2(r.end.x - 4.0, top + 30.0), Vector2(x0 + 4.0, top + 30.0)])
		_part(mantle, col.darkened(0.1), col.darkened(0.45))
	_edge(pts)


# ---------------------------------------------------------------- spoils

static func _skin(r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var w := r.size.x * 0.34
	var h := r.size.y * 0.38
	var pts := PackedVector2Array([c + Vector2(-w, -h), c + Vector2(-w * 0.45, -h * 0.7), c + Vector2(w * 0.45, -h * 0.7), c + Vector2(w, -h),
		c + Vector2(w * 0.6, 0), c + Vector2(w, h), c + Vector2(w * 0.45, h * 0.75), c + Vector2(-w * 0.45, h * 0.75), c + Vector2(-w, h), c + Vector2(-w * 0.6, 0)])
	_shadow(pts)
	_part(pts, col.lightened(0.3), col.darkened(0.3))
	_ci.draw_line(c + Vector2(0, -h * 0.6), c + Vector2(0, h * 0.65), _a(col.darkened(0.4)), 2.0, true)
	for k in 4:
		_ci.draw_circle(c + Vector2((k - 1.5) * w * 0.4, -h * 0.1 + (k % 2) * h * 0.3), 1.5, _a(col.darkened(0.45)))


static func _sting(r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var curl := PackedVector2Array()
	for k in 12:
		var a := PI * 0.9 + PI * 1.2 * k / 11.0
		curl.append(c + Vector2(-2.0, 3.0) + Vector2(cos(a), sin(a)) * s * 0.26)
	_ci.draw_polyline(curl, _a(OUTLINE), 6.5, true)
	_ci.draw_polyline(curl, _a(col.lightened(0.2)), 4.5, true)
	_ci.draw_polyline(curl, _a(col.lightened(0.6)), 1.0, true)
	var tip := PackedVector2Array([curl[curl.size() - 1] + Vector2(-2.0, 0), curl[curl.size() - 1] + Vector2(2.5, 0), curl[curl.size() - 1] + Vector2(1.0, -s * 0.2)])
	_part(tip, col.lightened(0.5), col)


# ---------------------------------------------------------------- the pieces things are made of

## A shaded part: filled from light (upper left) to dark (lower right), outlined, with a shadow.
static func _part(pts: PackedVector2Array, light: Color, dark: Color) -> void:
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := hi - lo
	var cols: Array = []
	for p in pts:
		var f := 0.65 * ((p.x - lo.x) / maxf(span.x, 0.001)) + 0.35 * ((p.y - lo.y) / maxf(span.y, 0.001))
		cols.append(light.lerp(dark, clampf(f, 0.0, 1.0)))
	_grad(pts, cols)
	_edge(pts)


## A round rod from `a` to `b` (a shaft, a haft): lit along one side, with the grain of wood.
static func _rod(a: Vector2, b: Vector2, half: float, col: Color, grain: bool) -> void:
	var d := (b - a).normalized()
	var n := _lit_normal(d)
	var pts := PackedVector2Array([a + n * half, b + n * half, b - n * half, a - n * half])
	_shadow(pts)
	_grad(pts, [col.lightened(0.3), col.lightened(0.15), col.darkened(0.45), col.darkened(0.4)])
	if grain:
		var length := a.distance_to(b)
		var k := 0
		var at := 6.0
		while at < length - 4.0:
			var off := n * half * (0.45 if k % 2 == 0 else -0.25)
			_ci.draw_line(a + d * at + off, a + d * minf(at + 7.0 + (k % 3) * 3.0, length - 2.0) + off, _a(col.darkened(0.35)), 0.8, true)
			at += 9.0 + (k % 2) * 4.0
			k += 1
	_ci.draw_line(a + n * half * 0.55, b + n * half * 0.55, _a(Color(1, 1, 1, 0.28)), 1.0, true)
	_edge(pts)


## Leather wound round a rod between `a` and `b`.
static func _wrap(a: Vector2, b: Vector2, half: float, col: Color) -> void:
	var d := (b - a).normalized()
	var n := _lit_normal(d)
	var pts := PackedVector2Array([a + n * half, b + n * half, b - n * half, a - n * half])
	_grad(pts, [col.lightened(0.3), col.lightened(0.3), col.darkened(0.35), col.darkened(0.35)])
	var length := a.distance_to(b)
	var at := 2.0
	while at < length:
		_ci.draw_line(a + d * at + n * half, a + d * minf(at + half * 1.2, length) - n * half, _a(col.darkened(0.55)), 1.0, true)
		at += 3.2
	_edge(pts)


## A metal ring round a rod at `at`.
static func _band(at: Vector2, half: float, tall: float, col: Color) -> void:
	var pts := _rect_pts(Rect2(at.x - half, at.y - tall * 0.5, half * 2.0, tall))
	_part(pts, col.lightened(0.45), col.darkened(0.35))


## A pointed metal foot or tip: from `base` (wide) to `point`.
static func _cone(point: Vector2, base: Vector2, half: float, col: Color) -> void:
	var d := (point - base).normalized()
	var n := _lit_normal(d)
	var pts := PackedVector2Array([base + n * half, point, base - n * half])
	_part(pts, col.lightened(0.4), col.darkened(0.35))


## A shiny ball: a rivet, a pommel, a bead, a mace's head.
static func _ball(c: Vector2, rad: float, col: Color) -> void:
	_ci.draw_circle(c + Vector2(1.2, 2.0), rad, _a(SHADOW))
	_ci.draw_circle(c, rad + 0.9, _a(OUTLINE))
	_ci.draw_circle(c, rad, _a(col.darkened(0.3)))
	_ci.draw_circle(c - Vector2(rad, rad) * 0.15, rad * 0.8, _a(col))
	_ci.draw_circle(c - Vector2(rad, rad) * 0.32, rad * 0.4, _a(col.lightened(0.45)))
	_ci.draw_circle(c - Vector2(rad, rad) * 0.42, maxf(0.6, rad * 0.15), _a(Color(1, 1, 1, 0.85)))


static func _oval(c: Vector2, rx: float, ry: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in sides:
		var a := TAU * k / sides
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _rect_pts(b: Rect2) -> PackedVector2Array:
	return PackedVector2Array([b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)])


## Of the two sides of a line running `d`, the one facing the light.
static func _lit_normal(d: Vector2) -> Vector2:
	var n := Vector2(-d.y, d.x)
	return n if n.dot(LIGHT) >= 0.0 else -n


static func _a(c: Color) -> Color:
	return Color(c.r, c.g, c.b, c.a * _fade)


static func _grad(pts: PackedVector2Array, cols: Array) -> void:
	var pc := PackedColorArray()
	for c in cols:
		pc.append(_a(c))
	_ci.draw_polygon(pts, pc)


static func _edge(pts: PackedVector2Array) -> void:
	var line := pts.duplicate()
	line.append(pts[0])
	_ci.draw_polyline(line, _a(OUTLINE), 1.2, true)


static func _shadow(pts: PackedVector2Array) -> void:
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(p + Vector2(2.0, 3.0))
	_ci.draw_colored_polygon(moved, _a(SHADOW))
