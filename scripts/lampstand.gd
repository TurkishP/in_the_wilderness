extends Control
## One weapon's skill tree drawn as the seven-branched lampstand of the tabernacle (Exodus
## 25:31-40): beaten gold, a shaft with three branches out of each side, each branch rising to a
## lamp, with knops and almond-blossom cups along them. The basic skills stand on its foot, the
## advanced ones further up: tier I on the foot, tier II on the outer branches and the lowest
## knop of the shaft, tier III on the middle branches, the capstone in the centre lamp at the
## top. Each skill shows only its picture (scripts/skill_icons.gd); hovering over it shows what
## it is and does. A skill learned lights its lamp. Click a skill to choose it (`picked`).

signal picked(id: String)

const Skills := preload("res://data/skills.gd")
const Ui := preload("res://scripts/ui.gd")
const Icons := preload("res://scripts/skill_icons.gd")
const GOLD_DARK := Color(0.5, 0.36, 0.14)
const GOLD_MID := Color(0.78, 0.6, 0.27)
const GOLD_LIGHT := Color(1.0, 0.86, 0.52)
const NODE_R := 24.0

var tree := "staff"
var selected := ""
var nodes: Array = []       # [{id, pos, lamp (index into _lamps or -1)}]
var _lamps: Array = []      # the seven lamp positions, left to right
var _branches: Array = []   # each branch as a list of points, for drawing
var _hover := ""
var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 404)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	# The skills that can be learned now shimmer.
	_t += delta
	queue_redraw()


## A point on the cubic curve a-b-c-d.
static func _bez(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t


## Lays the lampstand out for the control's size, and puts the eight skills on it.
func _layout() -> void:
	var w := size.x
	var cx := w * 0.5
	var lamp_y := 48.0
	var reach := minf(w * 0.4, 330.0)
	var widths := [reach, reach * 0.67, reach * 0.35]   # outer, middle, inner branches
	var from_y := [250.0, 210.0, 170.0]                   # where each pair leaves the shaft
	_branches.clear()
	_lamps = []
	var curves := {}
	for k in 3:
		for side in [-1.0, 1.0]:
			var a := Vector2(cx, from_y[k])
			var d := Vector2(cx + side * float(widths[k]), lamp_y + 22.0)
			var b := Vector2(cx + side * float(widths[k]) * 0.18, float(from_y[k]) + float(widths[k]) * 0.26)
			var c := Vector2(cx + side * float(widths[k]), float(from_y[k]) + float(widths[k]) * 0.26)
			var pts: Array = []
			for i in 25:
				pts.append(_bez(a, b, c, d, i / 24.0))
			_branches.append(pts)
			curves["%d%s" % [k, "l" if side < 0.0 else "r"]] = [a, b, c, d]
	# The lamps, left to right: outer, middle, inner, centre, inner, middle, outer.
	for k in [0, 1, 2]:
		_lamps.append(Vector2(cx - float(widths[k]), lamp_y))
	_lamps.append(Vector2(cx, lamp_y))
	for k in [2, 1, 0]:
		_lamps.append(Vector2(cx + float(widths[k]), lamp_y))
	var on := func(key: String, t: float) -> Vector2:
		var q: Array = curves[key]
		return _bez(q[0], q[1], q[2], q[3], t)
	var skills: Array = Skills.TREES[tree]["skills"]
	var by_tier := {1: [], 2: [], 3: [], 4: []}
	for s in skills:
		(by_tier[int(s["tier"])] as Array).append(str(s["id"]))
	# Where each skill sits, and which lamp it lights.
	var places := [
		[by_tier[1][0], Vector2(cx - 74.0, 364.0), 2], [by_tier[1][1], Vector2(cx + 74.0, 364.0), 4],
		[by_tier[2][0], on.call("0l", 0.5), 0], [by_tier[2][1], Vector2(cx, 250.0), -1], [by_tier[2][2], on.call("0r", 0.5), 6],
		[by_tier[3][0], on.call("1l", 0.72), 1], [by_tier[3][1], on.call("1r", 0.72), 5],
		[by_tier[4][0], Vector2(cx, lamp_y + 8.0), 3],
	]
	nodes = []
	for p in places:
		nodes.append({"id": p[0], "pos": p[1], "lamp": p[2]})


func _draw() -> void:
	_layout()
	var cx := size.x * 0.5
	# The foot: a bell-shaped base on a plinth, chased with leaves.
	var foot := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		var x := lerpf(-118.0, 118.0, t)
		var bell := pow(absf(x) / 118.0, 1.6)
		foot.append(Vector2(cx + x, lerpf(330.0, 384.0, bell)))
	foot.append(Vector2(cx + 128.0, 392.0))
	foot.append(Vector2(cx - 128.0, 392.0))
	draw_colored_polygon(foot, GOLD_MID.darkened(0.15))
	draw_polyline(foot, GOLD_DARK, 2.0, true)
	draw_rect(Rect2(cx - 132.0, 390.0, 264.0, 12.0), GOLD_MID.darkened(0.25))
	for side in [-1.0, 1.0]:
		for k in 3:
			var x0: float = cx + side * (22.0 + k * 30.0)
			draw_line(Vector2(x0, 348.0 + k * 8.0), Vector2(x0 + side * 14.0, 380.0), GOLD_DARK, 2.0, true)
	# The shaft, with a knop where each pair of branches goes out.
	_rod([Vector2(cx, 333.0), Vector2(cx, 50.0)], 13.0)
	# The branches.
	for pts in _branches:
		_rod(pts, 9.0)
		# Almond-blossom cups along each branch.
		for t in [0.35, 0.62, 0.85]:
			var at: Vector2 = pts[int(t * (pts.size() - 1))]
			draw_circle(at, 6.0, GOLD_MID)
			draw_arc(at, 6.0, 0.0, TAU, 14, GOLD_DARK, 1.5, true)
	for y in [250.0, 210.0, 170.0, 296.0]:
		draw_set_transform(Vector2(cx, y), 0.0, Vector2(1.0, 0.6))
		draw_circle(Vector2.ZERO, 14.0, GOLD_MID)
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 20, GOLD_DARK, 2.0, true)
		draw_set_transform(Vector2.ZERO)
	# The seven lamps, each lit by its skill.
	var lit := {}
	for n in nodes:
		if int(n["lamp"]) >= 0 and Game.has_perk(str(n["id"])):
			lit[int(n["lamp"])] = true
	for i in _lamps.size():
		_lamp(_lamps[i], lit.has(i))
	# The skills, and what the one under the mouse is.
	for n in nodes:
		_node(n)
	for n in nodes:
		if str(n["id"]) == _hover:
			_card(n)


## A rod of beaten gold along `pts`: dark edge, body, a highlight down one side.
func _rod(pts: Array, width: float) -> void:
	var line := PackedVector2Array(pts)
	draw_polyline(line, GOLD_DARK, width + 3.0, true)
	draw_polyline(line, GOLD_MID, width, true)
	var shine := PackedVector2Array()
	for p in pts:
		shine.append((p as Vector2) + Vector2(-width * 0.22, -width * 0.12))
	draw_polyline(shine, GOLD_LIGHT, maxf(1.5, width * 0.28), true)


## A lamp: a cup on the branch's end, and a flame if it is lit.
func _lamp(at: Vector2, lit: bool) -> void:
	var cup := PackedVector2Array([at + Vector2(-17, -6), at + Vector2(17, -6), at + Vector2(9, 14), at + Vector2(-9, 14)])
	draw_colored_polygon(cup, GOLD_MID)
	draw_polyline(PackedVector2Array([cup[0], cup[1], cup[2], cup[3], cup[0]]), GOLD_DARK, 2.0, true)
	if not lit:
		draw_line(at + Vector2(0, -6), at + Vector2(0, -12), Color(0.15, 0.1, 0.06), 2.0)
		return
	var flicker := 1.0 + 0.08 * sin(_t * 9.0 + at.x)
	for layer in [[Color(1.0, 0.45, 0.1, 0.35), 1.6], [Color(1.0, 0.62, 0.15), 1.0], [Color(1.0, 0.93, 0.6), 0.55]]:
		var k: float = float(layer[1]) * flicker
		var flame := PackedVector2Array()
		for i in 13:
			var a := TAU * i / 12.0
			var r := 7.0 * k
			var y := -cos(a) * r * (2.2 if cos(a) > 0.0 else 1.0)
			flame.append(at + Vector2(sin(a) * r * 0.75, y - 12.0 - r))
		draw_colored_polygon(flame, layer[0])


## One skill on the lampstand: a medallion, ringed by what can be done with it, and its name.
func _node(n: Dictionary) -> void:
	var id := str(n["id"])
	var at: Vector2 = n["pos"]
	var learned := Game.has_perk(id)
	var can := Game.why_not(id) == ""
	var fill := Color(0.12, 0.09, 0.06)
	var rim := Color(Ui.BRONZE.r, Ui.BRONZE.g, Ui.BRONZE.b, 0.7)
	if learned:
		draw_circle(at, NODE_R + 9.0, Color(1.0, 0.75, 0.3, 0.18))
		fill = GOLD_MID
		rim = GOLD_LIGHT
	elif can:
		rim = Ui.GOLD.lerp(Color.WHITE, 0.3 + 0.3 * sin(_t * 4.0))
	if id == selected:
		draw_arc(at, NODE_R + 6.0, 0.0, TAU, 32, Color(1.0, 0.95, 0.8), 2.5, true)
	elif id == _hover:
		draw_arc(at, NODE_R + 5.0, 0.0, TAU, 32, Color(1.0, 0.95, 0.8, 0.5), 2.0, true)
	draw_circle(at, NODE_R, fill)
	draw_arc(at, NODE_R, 0.0, TAU, 32, rim, 3.0 if can or learned else 2.0, true)
	# Only the skill's picture: dark on the gold of one learned, gold on one that can be learned
	# now, dim on one still closed.
	var s: Dictionary = Skills.find(id)["skill"]
	var ink := Ui.INK if learned else (Ui.GOLD if can else Color(Ui.MUTED.r, Ui.MUTED.g, Ui.MUTED.b, 0.75))
	Icons.draw(self, str(s.get("icon", "")), at, NODE_R * 0.66, ink, fill)


## What the skill under the mouse is: its name, tier and cost, whether it can be learned, and
## what it does, on a card beside it.
func _card(n: Dictionary) -> void:
	var id := str(n["id"])
	var s: Dictionary = Skills.find(id)["skill"]
	var tier := int(s["tier"])
	var cost := int(Skills.COST[tier])
	var why := Game.why_not(id)
	var status := "Learned" if Game.has_perk(id) else ("Can be learned now" if why == "" else why)
	var head := Ui.font("bold")
	var body := Ui.font("regular")
	var small := Ui.font("italic")
	var width := 300.0
	var text := str(s["text"])
	if s.has("ref"):
		text += "  (%s)" % s["ref"]
	var info := "%s  ·  %d point%s  ·  %s" % [Skills.TIER_NAMES[tier], cost, "" if cost == 1 else "s", status]
	var info_h := small.get_multiline_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, width, 14).y
	var text_h := body.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, 15).y
	var h := 14.0 + 24.0 + info_h + 8.0 + text_h + 12.0
	var w := width + 24.0
	var at: Vector2 = n["pos"]
	var x := at.x + NODE_R + 14.0
	if x + w > size.x - 4.0:
		x = at.x - NODE_R - 14.0 - w
	var y := clampf(at.y - 30.0, 0.0, maxf(0.0, size.y - h))
	var box := Rect2(x, y, w, h)
	draw_rect(box, Color(0.06, 0.045, 0.03, 0.96))
	draw_rect(box, Ui.BRONZE, false, 1.5)
	var p := Vector2(x + 12.0, y + 14.0 + 17.0)
	draw_string(head, p, str(s["name"]), HORIZONTAL_ALIGNMENT_LEFT, width, 18, Ui.GOLD)
	p.y += 10.0
	draw_multiline_string(small, p + Vector2(0, 12.0), info, HORIZONTAL_ALIGNMENT_LEFT, width, 14, -1, Ui.GOLD.lerp(Ui.PARCHMENT, 0.5) if why == "" else Ui.MUTED)
	p.y += info_h + 8.0
	draw_multiline_string(body, p + Vector2(0, 13.0), text, HORIZONTAL_ALIGNMENT_LEFT, width, 15, -1, Ui.PARCHMENT)


## The skill under a point, or "".
func node_at(p: Vector2) -> String:
	for n in nodes:
		if (n["pos"] as Vector2).distance_to(p) <= NODE_R + 6.0:
			return str(n["id"])
	return ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = node_at(event.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hover != "" else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := node_at(event.position)
		if id != "":
			picked.emit(id)
			accept_event()


