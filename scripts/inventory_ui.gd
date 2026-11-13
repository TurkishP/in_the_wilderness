extends Control
## The inventory screens. On the left the bag, a grid of places where bigger things take more of
## them; on the right either what the scout wears and wields ("gear"), the chest in the tent
## ("chest"), or the trader's goods ("trade").
##
## Click an item to pick it up and click again to put it down: on a free place, on another item to
## swap them, or on an equipment slot to wear it. Right-click is the quick way: equip or take off,
## move between bag and chest, buy or sell. Hovering shows what an item does.

const Items := preload("res://data/items.gd")
const CELL := 44.0
const PAD := 26.0
const GAP := 56.0
const HEAD := 70.0   # room for the title above the grids
## Border colors by tier, from plain to rare.
const TIER_COLORS := [Color(0.55, 0.53, 0.5), Color(0.6, 0.58, 0.55), Color(0.85, 0.83, 0.78), Color(0.5, 0.82, 0.45),
	Color(0.45, 0.65, 1.0), Color(1.0, 0.8, 0.3), Color(1.0, 0.5, 0.2)]
## Where the equipment slots sit on the right, in places: [x, y, w, h].
const DOLL := {
	"head": [2.5, 0.5, 2, 2], "neck": [5.0, 1.0, 1, 1],
	"hand_r": [0.0, 3.0, 2, 4], "top": [2.5, 3.0, 2, 3], "hand_l": [5.0, 3.0, 2, 4],
	"belt": [2.5, 6.4, 2, 1], "bottom": [2.5, 7.9, 2, 2], "sling": [5.5, 7.9, 1, 2],
}

var mode := ""
var held: Dictionary = {}        # the item picked up, following the mouse
var message := ""                # a line at the bottom: what just happened or why not
var _from := {}                  # where `held` came from: {"list", "x", "y"} or {"slot"}
var _trader: Array = []
var _on_close := Callable()
var _font: Font
var _panel := Rect2()
var _bag_at := Vector2.ZERO
var _right_at := Vector2.ZERO
var _tip: PanelContainer
var _tip_text: RichTextLabel
var _footer: HBoxContainer
var _style: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.09, 0.07, 0.05, 0.96)
	_style.border_color = Color(0.75, 0.6, 0.35)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(8)
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 10)
	add_child(_footer)
	_tip = PanelContainer.new()
	var tip_style := _style.duplicate()
	tip_style.bg_color = Color(0.05, 0.04, 0.03, 0.97)
	tip_style.set_content_margin_all(12)
	_tip.add_theme_stylebox_override("panel", tip_style)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_text = RichTextLabel.new()
	_tip_text.bbcode_enabled = true
	_tip_text.fit_content = true
	_tip_text.scroll_active = false
	_tip_text.custom_minimum_size = Vector2(300, 0)
	_tip_text.add_theme_font_size_override("normal_font_size", 16)
	_tip_text.add_theme_font_size_override("bold_font_size", 18)
	_tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_text)
	_tip.visible = false
	add_child(_tip)
	visible = false


## Opens one of the screens. `on_close` runs when it closes.
func open(screen: String, tier: int = 1, on_close: Callable = Callable()) -> void:
	mode = screen
	held = {}
	message = ""
	_on_close = on_close
	if mode == "trade":
		_trader = Game.shop_grid(tier)
	visible = true
	_refresh_footer()
	queue_redraw()


func close() -> void:
	if not visible:
		return
	if not held.is_empty():
		_put_back()
	visible = false
	_tip.visible = false
	var done := _on_close
	_on_close = Callable()
	if done.is_valid():
		done.call()


# ---------------------------------------------------------------- layout

func _right_size() -> Vector2:
	match mode:
		"chest":
			return Vector2(Game.chest_grid()) * CELL
		"trade":
			return Vector2(Game.TRADER_GRID) * CELL
	return Vector2(7.0 * CELL + 290.0, 10.0 * CELL)


func _layout() -> void:
	var bag := Vector2(Game.bag_grid()) * CELL
	var right := _right_size()
	var w := PAD * 2.0 + maxf(bag.x, 420.0) + GAP + right.x
	var h := PAD * 2.0 + HEAD + maxf(bag.y + 190.0, right.y) + 60.0
	var view := get_viewport_rect().size
	_panel = Rect2(((view - Vector2(w, h)) * 0.5).floor(), Vector2(w, h))
	_bag_at = _panel.position + Vector2(PAD, PAD + HEAD)
	_right_at = _panel.position + Vector2(PAD + maxf(bag.x, 420.0) + GAP, PAD + HEAD)
	_footer.position = Vector2(_panel.position.x + PAD, _panel.end.y - PAD - 40.0)


func _slot_rect(slot: String) -> Rect2:
	var d: Array = DOLL[slot]
	return Rect2(_right_at + Vector2(d[0], d[1]) * CELL, Vector2(d[2], d[3]) * CELL)


## The grid under a point: {where, list, grid, at} or {}.
func _grid_at(p: Vector2) -> Dictionary:
	var grids: Array = [["bag", Game.bag, Game.bag_grid(), _bag_at]]
	if mode == "chest":
		grids.append(["chest", Game.chest, Game.chest_grid(), _right_at])
	elif mode == "trade":
		grids.append(["trade", _trader, Game.TRADER_GRID, _right_at])
	for g in grids:
		var r := Rect2(g[3], Vector2(g[2]) * CELL)
		if r.has_point(p):
			return {"where": g[0], "list": g[1], "grid": g[2], "at": g[3]}
	return {}


func _cell(at: Vector2, p: Vector2) -> Vector2i:
	return Vector2i(((p - at) / CELL).floor())


## The place an item held at the mouse would go: it is centered on the pointer.
func _drop_cell(at: Vector2, size: Vector2i, p: Vector2) -> Vector2i:
	return _cell(at, p - Vector2(size) * CELL * 0.5 + Vector2(CELL, CELL) * 0.5)


func _slot_at(p: Vector2) -> String:
	if mode != "gear":
		return ""
	for slot in DOLL:
		if _slot_rect(slot).has_point(p):
			return slot
	return ""


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		queue_redraw()
		_update_tip()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			quick(event.position)
		accept_event()
		_refresh_footer()
		queue_redraw()
		_update_tip()


## A left click: pick up, put down, swap, wear, buy or sell.
func click(p: Vector2) -> void:
	message = ""
	var g := _grid_at(p)
	if not g.is_empty():
		var list: Array = g["list"]
		if g["where"] == "trade":
			if held.is_empty():
				_buy(Game.item_at(list, _cell(g["at"], p)))
			else:
				_sell_held()
			return
		if held.is_empty():
			var it := Game.item_at(list, _cell(g["at"], p))
			if not it.is_empty():
				Game.remove_from(list, it)
				_pick(it, {"list": g["where"], "x": it["x"], "y": it["y"]})
		else:
			_drop(list, g["grid"], g["where"], _drop_cell(g["at"], Game.item_size(held), p))
		return
	var slot := _slot_at(p)
	if slot == "":
		return
	if held.is_empty():
		var it := Game.take_off(slot)
		if it.is_empty() and slot == "hand_l" and Game.is_two_handed(Game.equipped["hand_r"]):
			it = Game.take_off("hand_r")
			slot = "hand_r"
		if not it.is_empty():
			_pick(it, {"slot": slot})
	else:
		_wear_held(slot)


## A right click: the quick move for what is under the pointer.
func quick(p: Vector2) -> void:
	message = ""
	if not held.is_empty():
		return
	var g := _grid_at(p)
	if not g.is_empty():
		var it := Game.item_at(g["list"], _cell(g["at"], p))
		if it.is_empty():
			return
		match [mode, g["where"]]:
			["gear", "bag"]:
				if Game.item_def(it)["slot"] == "ammo":
					message = "%s are used from the bag." % Game.item_def(it)["name"]
				elif not Game.equip(it):
					message = "There is no room in your bag for what you would take off."
			["chest", "bag"]:
				if not Game.store(it):
					message = "The chest is full."
			["chest", "chest"]:
				if not Game.unstore(it):
					message = "Your bag is full."
			["trade", "bag"]:
				if Game.sell_value(it) <= 0:
					message = "The trader does not want that."
				else:
					message = "Sold %s for %d silver." % [Game.item_name(it), Game.sell_value(it)]
					Game.sell(it)
			["trade", "trade"]:
				_buy(it)
		return
	var slot := _slot_at(p)
	if slot != "" and not Game.equipped[slot].is_empty() and not Game.unequip(slot):
		message = "There is no room in your bag for it."


func _pick(it: Dictionary, from: Dictionary) -> void:
	held = it
	_from = from


## Puts the held item down at `at`. One item in the way is picked up in its place; a stack of the
## same ammo is topped up instead.
func _drop(list: Array, grid: Vector2i, where: String, at: Vector2i) -> void:
	var size := Game.item_size(held)
	if at.x < 0 or at.y < 0 or at.x + size.x > grid.x or at.y + size.y > grid.y:
		message = "It does not fit there."
		return
	var over := Game.items_in(list, Rect2i(at, size))
	var d := Game.item_def(held)
	if over.size() == 1 and d.has("stack") and over[0]["id"] == held["id"]:
		var other: Dictionary = over[0]
		var n := mini(int(held["count"]), int(d["stack"]) - int(other["count"]))
		other["count"] = int(other["count"]) + n
		held["count"] = int(held["count"]) - n
		if int(held["count"]) <= 0:
			held = {}
		return
	if over.size() > 1:
		message = "Something is in the way."
		return
	held["x"] = at.x
	held["y"] = at.y
	list.append(held)
	held = {}
	if over.size() == 1:
		var other: Dictionary = over[0]
		Game.remove_from(list, other)
		_pick(other, {"list": where, "x": other["x"], "y": other["y"]})


## Wears the held item in `slot`. What it replaces is picked up; anything else it pushes off
## (a bow needs both hands, a dress both top and bottom) goes into the bag.
func _wear_held(slot: String) -> void:
	if not Game.slot_accepts(slot, held):
		message = "%s does not go there." % Game.item_def(held)["name"]
		return
	var target := "hand_r" if Game.is_two_handed(held) else slot
	var off: Array = []
	for s in Game._clashes(held, target):
		if not Game.equipped[s].is_empty():
			off.append(Game.equipped[s])
	if off.size() > 1:
		var probe := Game.bag.duplicate()
		for it in off.slice(1):
			if Game.place(probe, Game.bag_grid(), it.duplicate()) > 0:
				message = "There is no room in your bag for what you would take off."
				return
	var item := held
	held = {}
	var removed: Array = Game.wear(item, slot)
	for i in removed.size():
		if i == 0:
			_pick(removed[0], {"list": "bag"})
		else:
			Game.place(Game.bag, Game.bag_grid(), removed[i])


func _buy(it: Dictionary) -> void:
	if it.is_empty():
		return
	if Game.silver < Game.price(it):
		message = "You cannot afford the %s." % Game.item_def(it)["name"].to_lower()
	elif not Game.can_take(str(it["id"])):
		message = "Your bag has no room for it."
	elif Game.try_buy(str(it["id"])):
		message = "Bought: %s." % Game.item_def(it)["name"]


func _sell_held() -> void:
	var value := Game.sell_value(held)
	if value <= 0:
		message = "The trader does not want that."
		return
	Game.silver += value
	message = "Sold %s for %d silver." % [Game.item_name(held), value]
	held = {}


## Returns the held item to where it came from, or anywhere it fits.
func _put_back() -> void:
	var it := held
	held = {}
	if _from.has("slot"):
		var slot: String = _from["slot"]
		if Game.equipped[slot].is_empty() and Game.slot_accepts(slot, it):
			var off: Array = Game.wear(it, slot)
			for o in off:
				Game.place(Game.bag, Game.bag_grid(), o)
			return
	var list: Array = Game.chest if _from.get("list", "") == "chest" else Game.bag
	var grid: Vector2i = Game.chest_grid() if _from.get("list", "") == "chest" else Game.bag_grid()
	if _from.has("x") and Game.fits(list, grid, Game.item_size(it), Vector2i(int(_from["x"]), int(_from["y"]))):
		it["x"] = int(_from["x"])
		it["y"] = int(_from["y"])
		list.append(it)
	elif Game.place(list, grid, it) > 0 and Game.place(Game.bag, Game.bag_grid(), it) > 0:
		Game.place(Game.chest, Game.chest_grid(), it)


# ---------------------------------------------------------------- the trader's extras

func _refresh_footer() -> void:
	for c in _footer.get_children():
		_footer.remove_child(c)
		c.queue_free()
	if mode == "trade":
		_button("Buy %d sling stones  (%d silver)" % [Game.STONE_BUNDLE, Game.STONE_PRICE], func() -> void: _buy_ammo("stones"), Game.silver >= Game.STONE_PRICE)
		_button("Buy %d arrows  (%d silver)" % [Game.ARROW_BUNDLE, Game.ARROW_PRICE], func() -> void: _buy_ammo("arrows"), Game.silver >= Game.ARROW_PRICE)
		var next := Game.next_pack()
		if next != "":
			var p: Dictionary = Items.PACKS[next]
			_button("%s  %dx%d  (%d silver)" % [p["name"], p["grid"][0], p["grid"][1], p["price"]], func() -> void: _buy_pack(next), Game.silver >= int(p["price"]))
		if Game.max_water < 6:
			_button("Larger waterskin  (%d silver)" % Game.waterskin_price(), _buy_waterskin, Game.silver >= Game.waterskin_price())
	_button("Close", close, true)


func _button(text: String, cb: Callable, enabled: bool) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 36)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.pressed.connect(func() -> void:
		message = ""
		cb.call()
		if visible:
			_refresh_footer()
			queue_redraw())
	_footer.add_child(b)


func _buy_ammo(id: String) -> void:
	if not Game.can_take(id):
		message = "Your bag has no room for them."
	elif Game.try_buy_ammo(id):
		message = "You now carry %d %s." % [Game.ammo_count(id), "sling stones" if id == "stones" else "arrows"]


func _buy_pack(id: String) -> void:
	if Game.try_buy_pack(id):
		message = "Your new %s has %d places." % [Items.PACKS[id]["name"].to_lower(), Game.places()]


func _buy_waterskin() -> void:
	if Game.try_buy_waterskin():
		message = "Your waterskin now holds %d drinks." % Game.max_water


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_layout()
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.35))
	draw_style_box(_style, _panel)
	var titles := {"gear": "Your gear", "chest": "Your chest", "trade": "Caravan trader"}
	_text(_panel.position + Vector2(PAD, PAD + 26.0), str(titles.get(mode, "")), 26, Color(1.0, 0.85, 0.5))
	var pack: Dictionary = Items.PACKS[Game.pack]
	_text(_bag_at + Vector2(0, -8), "%s  —  %d of %d places" % [pack["name"], Game.used_places(), Game.places()], 16, Color(0.9, 0.85, 0.75))
	_grid(Game.bag, Game.bag_grid(), _bag_at)
	var y := _bag_at.y + Game.bag_grid().y * CELL + 30.0
	_text(Vector2(_bag_at.x, y), "Silver %d     Bronze %d" % [Game.silver, Game.bronze], 17, Color(1.0, 0.92, 0.7))
	_text(Vector2(_bag_at.x, y + 24.0), "Sling stones %d     Arrows %d     Bag weight %.1f kg" % [Game.stones(), Game.arrows(), Game.bag_weight()], 16)
	var hint := {
		"gear": "Click to pick up and put down. Drop on a slot to wear it.\nRight-click: equip, or take off into the bag.",
		"chest": "Click to pick up and put down.\nRight-click: move between bag and chest.",
		"trade": "Click the trader's goods to buy. Right-click your own to sell,\nor drop them on the trader's side.",
	}
	_text(Vector2(_bag_at.x, y + 54.0), str(hint.get(mode, "")), 15, Color(0.75, 0.72, 0.66))
	match mode:
		"gear":
			_doll()
		"chest":
			_text(_right_at + Vector2(0, -8), "The chest  —  kept here for the whole journey", 16, Color(0.9, 0.85, 0.75))
			_grid(Game.chest, Game.chest_grid(), _right_at)
		"trade":
			_text(_right_at + Vector2(0, -8), "For sale  —  hover to see the price", 16, Color(0.9, 0.85, 0.75))
			_grid(_trader, Game.TRADER_GRID, _right_at)
	if message != "":
		_text(Vector2(_panel.position.x + PAD, _footer.position.y - 14.0), message, 17, Color(1.0, 0.75, 0.55))
	_draw_held()


func _text(at: Vector2, s: String, size: int = 16, color: Color = Color.WHITE) -> void:
	var lines := s.split("\n")
	for i in lines.size():
		draw_string(_font, at + Vector2(0, i * (size + 4)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _grid(list: Array, grid: Vector2i, at: Vector2) -> void:
	draw_rect(Rect2(at, Vector2(grid) * CELL), Color(0.03, 0.025, 0.02, 0.9))
	for gy in grid.y:
		for gx in grid.x:
			draw_rect(Rect2(at + Vector2(gx, gy) * CELL, Vector2(CELL, CELL)).grow(-1.0), Color(0.16, 0.13, 0.1, 0.85))
	if not held.is_empty() and Rect2(at, Vector2(grid) * CELL).has_point(get_local_mouse_position()) and not is_same(list, _trader):
		# Shows where the held item would go, green if it can.
		var size := Game.item_size(held)
		var c := _drop_cell(at, size, get_local_mouse_position())
		var ok := c.x >= 0 and c.y >= 0 and c.x + size.x <= grid.x and c.y + size.y <= grid.y and Game.items_in(list, Rect2i(c, size)).size() <= 1
		draw_rect(Rect2(at + Vector2(c) * CELL, Vector2(size) * CELL), Color(0.3, 0.8, 0.3, 0.25) if ok else Color(0.9, 0.2, 0.15, 0.25))
	var mouse := get_local_mouse_position()
	for it in list:
		var r := Rect2(at + Vector2(int(it["x"]), int(it["y"])) * CELL, Vector2(Game.item_size(it)) * CELL)
		_tile(r, it, held.is_empty() and r.has_point(mouse))


## One item: a tile with a border in its tier's color, its picture and, for ammo, how many.
func _tile(r: Rect2, it: Dictionary, lit: bool) -> void:
	var tier := clampi(int(Game.item_def(it).get("tier", 1)), 0, TIER_COLORS.size() - 1)
	draw_rect(r.grow(-2.0), Color(0.3, 0.25, 0.18, 0.95) if lit else Color(0.2, 0.17, 0.13, 0.95))
	draw_rect(r.grow(-2.0), TIER_COLORS[tier], false, 1.5)
	_icon(r.grow(-6.0), it)
	if Game.item_def(it).has("stack"):
		draw_string(_font, r.end - Vector2(18.0, 6.0), str(int(it["count"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	elif int(it.get("plus", 0)) > 0:
		draw_string(_font, r.position + Vector2(5.0, 16.0), "+%d" % int(it["plus"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4))


func _doll() -> void:
	var mouse := get_local_mouse_position()
	var two: bool = Game.is_two_handed(Game.equipped["hand_r"])
	var whole: bool = not Game.equipped["top"].is_empty() and Game.item_def(Game.equipped["top"])["slot"] == "body"
	for slot in DOLL:
		var r := _slot_rect(slot)
		var accepts := not held.is_empty() and Game.slot_accepts(slot, held)
		draw_rect(r, Color(0.03, 0.025, 0.02, 0.9))
		draw_rect(r, Color(0.45, 0.7, 0.4) if accepts else Color(0.45, 0.38, 0.28), false, 1.5)
		_text(r.position + Vector2(2, -5), str(Items.SLOT_NAMES[slot]), 13, Color(0.8, 0.75, 0.65))
		var it: Dictionary = Game.equipped[slot]
		if not it.is_empty():
			_tile(r, it, held.is_empty() and r.has_point(mouse))
		elif (slot == "hand_l" and two) or (slot == "bottom" and whole):
			var shown: Dictionary = Game.equipped["hand_r"] if slot == "hand_l" else Game.equipped["top"]
			_icon(r.grow(-8.0), shown, 0.3)
	# The scout's numbers, next to the slots.
	var x := _right_at.x + 7.6 * CELL
	var y := _right_at.y + 18.0
	var lines: Array = [
		["Health", "%d / %d" % [int(Game.hp), int(Game.max_hp)]],
		["Damage", _damage_line()],
		["Defense", "%d  (stops %d%%)" % [int(round(Game.defense())), int(round(Game.armor_block() * 100.0))]],
		["Thirst regen", Game.stat_text("thirst", Game.total("thirst"))],
		["Stamina regen", Game.stat_text("stamina", Game.total("stamina"))],
		["Sling", "%d damage" % int(round(Game.sling_power())) if not Game.equipped["sling"].is_empty() else "none"],
		["Worn weight", "%.1f kg" % Game.equipped_weight()],
	]
	for l in lines:
		_text(Vector2(x, y), str(l[0]), 16, Color(0.8, 0.75, 0.65))
		_text(Vector2(x + 120.0, y), str(l[1]), 16)
		y += 27.0


func _damage_line() -> String:
	var bow := Game.bow()
	if not bow.is_empty():
		return "bow %d" % int(round(Game.stat(bow, "damage")))
	var parts: Array = []
	for hand in ["hand_r", "hand_l"]:
		var w := Game.weapon_in(hand)
		if not w.is_empty():
			parts.append("%s %d %s" % ["R" if hand == "hand_r" else "L", int(round(Game.stat(w, "damage"))), _speed_word(w)])
	return "  ".join(parts) if not parts.is_empty() else "fists %d" % int(Game.FIST_DAMAGE)


func _speed_word(w: Dictionary) -> String:
	var s := Game.swing_speed(w)
	if s >= 1.15:
		return "(quick)"
	if s <= 0.85:
		return "(slow)"
	return ""


func _draw_held() -> void:
	if held.is_empty():
		return
	var size := Vector2(Game.item_size(held)) * CELL
	var r := Rect2(get_local_mouse_position() - size * 0.5, size)
	_tile(r, held, true)


# ---------------------------------------------------------------- pictures

## A small picture of an item, drawn in `r`. `fade` dims it (for a slot taken by something else).
func _icon(r: Rect2, it: Dictionary, fade: float = 1.0) -> void:
	var d := Game.item_def(it)
	var col: Color = d.get("color", Color(0.7, 0.7, 0.7))
	col.a = fade
	var wood := Color(0.45, 0.3, 0.17, fade)
	var dark := Color(0.12, 0.09, 0.06, fade)
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var top := r.position.y
	var bottom := r.end.y
	match str(d.get("kind", "")):
		"dagger", "sword", "sword_short", "sword_long", "sickle":
			var guard := bottom - r.size.y * 0.28
			var bw := clampf(r.size.x * 0.14, 4.0, 7.0)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - bw, guard), Vector2(c.x + bw, guard), Vector2(c.x + bw, top + 10.0), Vector2(c.x, top), Vector2(c.x - bw, top + 10.0)]), col)
			draw_line(Vector2(c.x, guard), Vector2(c.x, top + 4.0), col.lightened(0.35), 1.0)
			if d["kind"] == "sickle":
				draw_arc(Vector2(c.x + bw * 2.2, top + 12.0), bw * 2.2, PI, PI * 1.9, 10, col, bw * 1.4)
			draw_line(Vector2(c.x - 13.0, guard), Vector2(c.x + 13.0, guard), col.darkened(0.2), 5.0)
			draw_line(Vector2(c.x, guard), Vector2(c.x, bottom - 3.0), wood, 6.0)
			draw_circle(Vector2(c.x, bottom - 3.0), 4.0, col.darkened(0.2))
		"staff":
			draw_line(Vector2(c.x, bottom), Vector2(c.x, top + 12.0), col, 6.0)
			draw_arc(Vector2(c.x + 8.0, top + 12.0), 8.0, PI, TAU, 10, col, 6.0)
		"spear", "spear_long":
			draw_line(Vector2(c.x, bottom), Vector2(c.x, top + 18.0), wood, 5.0)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - 7.0, top + 22.0), Vector2(c.x, top), Vector2(c.x + 7.0, top + 22.0)]), col if col.r > 0.6 else Color(0.7, 0.7, 0.72, fade))
		"club":
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - 3.0, bottom), Vector2(c.x + 3.0, bottom), Vector2(c.x + 9.0, top + 4.0), Vector2(c.x - 9.0, top + 4.0)]), col)
		"mace":
			draw_line(Vector2(c.x, bottom), Vector2(c.x, top + 14.0), wood, 5.0)
			draw_circle(Vector2(c.x, top + 13.0), 12.0, col)
		"axe":
			draw_line(Vector2(c.x - 6.0, bottom), Vector2(c.x - 6.0, top + 4.0), wood, 6.0)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - 6.0, top + 10.0), Vector2(c.x + r.size.x * 0.4, top + 2.0), Vector2(c.x + r.size.x * 0.4, top + 44.0), Vector2(c.x - 6.0, top + 34.0)]), col)
		"bow":
			var rad := r.size.y * 0.55
			var cx := r.position.x + rad * 0.35 + 6.0
			draw_arc(Vector2(cx + rad * 0.9, c.y), rad, PI * 0.68, PI * 1.32, 20, col, 5.0)
			draw_line(Vector2(cx + rad * 0.9 + rad * cos(PI * 0.68), c.y + rad * sin(PI * 0.68)), Vector2(cx + rad * 0.9 + rad * cos(PI * 1.32), c.y + rad * sin(PI * 1.32)), Color(0.9, 0.87, 0.8, fade), 1.5)
		"shield":
			draw_circle(c, s * 0.46, Color(0.75, 0.55, 0.3, fade).darkened(0.25))
			draw_circle(c, s * 0.41, col)
			draw_circle(c, s * 0.1, Color(0.85, 0.65, 0.35, fade))
		"cap", "helmet":
			var pts := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * 0.42 + Vector2(0, s * 0.12))
			draw_colored_polygon(pts, col)
			draw_line(c + Vector2(-s * 0.46, s * 0.12), c + Vector2(s * 0.46, s * 0.12), col.darkened(0.3), 5.0)
			if d["kind"] == "helmet":
				draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.12), col.lightened(0.3), 2.0)
		"necklace":
			for k in 9:
				var a := PI * 0.1 + PI * 0.8 * k / 8.0
				draw_circle(c + Vector2(cos(a), sin(a) * 0.8) * s * 0.36 - Vector2(0, s * 0.12), 3.0, col)
			draw_circle(c + Vector2(0, s * 0.3), 5.0, col.lightened(0.2))
		"belt":
			draw_rect(Rect2(r.position.x, c.y - 6.0, r.size.x, 12.0), col)
			draw_rect(Rect2(c.x - 7.0, c.y - 8.0, 14.0, 16.0), Color(0.85, 0.65, 0.35, fade), false, 3.0)
		"tunic", "armor":
			var w := r.size.x
			draw_colored_polygon(PackedVector2Array([
				Vector2(r.position.x + w * 0.3, top), Vector2(r.position.x + w * 0.7, top), Vector2(r.end.x, top + 18.0),
				Vector2(r.end.x - 9.0, top + 34.0), Vector2(r.position.x + w * 0.8, top + 26.0), Vector2(r.position.x + w * 0.8, bottom),
				Vector2(r.position.x + w * 0.2, bottom), Vector2(r.position.x + w * 0.2, top + 26.0), Vector2(r.position.x + 9.0, top + 34.0),
				Vector2(r.position.x, top + 18.0)]), col)
			draw_line(Vector2(c.x - 7.0, top + 2.0), Vector2(c.x, top + 12.0), dark, 2.0)
			draw_line(Vector2(c.x + 7.0, top + 2.0), Vector2(c.x, top + 12.0), dark, 2.0)
		"kilt", "skirt":
			draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 10.0, top + 4.0), Vector2(r.end.x - 10.0, top + 4.0), Vector2(r.end.x - 2.0, bottom), Vector2(r.position.x + 2.0, bottom)]), col)
			draw_line(Vector2(r.position.x + 10.0, top + 6.0), Vector2(r.end.x - 10.0, top + 6.0), dark, 3.0)
		"robe", "dress":
			var w := r.size.x
			draw_colored_polygon(PackedVector2Array([
				Vector2(r.position.x + w * 0.32, top), Vector2(r.position.x + w * 0.68, top), Vector2(r.end.x - 2.0, top + 22.0),
				Vector2(r.end.x - 9.0, top + 36.0), Vector2(r.position.x + w * 0.75, top + 28.0), Vector2(r.end.x - 2.0, bottom),
				Vector2(r.position.x + 2.0, bottom), Vector2(r.position.x + w * 0.25, top + 28.0), Vector2(r.position.x + 9.0, top + 36.0),
				Vector2(r.position.x + 2.0, top + 22.0)]), col)
		"sling":
			draw_line(Vector2(c.x - 5.0, top), Vector2(c.x - 2.0, bottom - 14.0), col, 2.0)
			draw_line(Vector2(c.x + 5.0, top), Vector2(c.x + 2.0, bottom - 14.0), col, 2.0)
			draw_circle(Vector2(c.x, bottom - 10.0), 8.0, col.darkened(0.3))
		"stones":
			for p in [Vector2(-7, 4), Vector2(6, 5), Vector2(0, -6)]:
				draw_circle(c + p, 7.0, col.darkened(0.1 * absf(p.x) / 7.0))
		"arrows":
			for k in 3:
				var x := c.x - 8.0 + k * 8.0
				draw_line(Vector2(x, bottom - 2.0), Vector2(x, top + 10.0), col, 2.0)
				draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, top + 12.0), Vector2(x, top + 2.0), Vector2(x + 4.0, top + 12.0)]), Color(0.65, 0.65, 0.68, fade))
				draw_line(Vector2(x - 3.0, bottom - 2.0), Vector2(x - 3.0, bottom - 12.0), Color(0.9, 0.87, 0.8, fade), 2.0)


# ---------------------------------------------------------------- what an item does

func _update_tip() -> void:
	var p := get_local_mouse_position()
	var it: Dictionary = {}
	var where := ""
	var g := _grid_at(p)
	if not g.is_empty():
		it = Game.item_at(g["list"], _cell(g["at"], p))
		where = g["where"]
	else:
		var slot := _slot_at(p)
		if slot != "":
			it = Game.equipped[slot]
			where = "slot"
	if not held.is_empty() or it.is_empty():
		_tip.visible = false
		return
	_tip_text.text = describe(it, where)
	_tip.visible = true
	_tip.reset_size()
	var view := get_viewport_rect().size
	var at := p + Vector2(20, 20)
	if at.x + _tip.size.x > view.x - 8.0:
		at.x = p.x - _tip.size.x - 12.0
	if at.y + _tip.size.y > view.y - 8.0:
		at.y = view.y - 8.0 - _tip.size.y
	_tip.position = at


## The tooltip text for an item: its numbers, where it goes and, at the trader, its price.
func describe(it: Dictionary, where: String = "") -> String:
	var d := Game.item_def(it)
	var tier := clampi(int(d.get("tier", 1)), 0, TIER_COLORS.size() - 1)
	var t := "[b][color=#%s]%s[/color][/b]\n" % [TIER_COLORS[tier].to_html(false), Game.item_name(it)]
	var where_text := {
		"hand": "Right or left hand", "head": "Head", "neck": "Neck", "belt": "Belt", "top": "Upper body",
		"bottom": "Lower body", "body": "Upper and lower body together", "sling": "Sling", "ammo": "Carried in the bag",
	}
	var slot_text: String = where_text.get(str(d["slot"]), "")
	if Game.is_two_handed(it):
		slot_text = "Both hands"
	elif d["kind"] == "shield":
		slot_text = "Shield, either hand"
	t += "[color=#bfb5a0]%s[/color]\n" % slot_text
	for key in Items.STAT_NAMES:
		var v := Game.stat(it, key)
		if v != 0.0:
			t += "%s  %s\n" % [Items.STAT_NAMES[key], Game.stat_text(key, v)]
	if d["slot"] == "hand" and Game.stat(it, "damage") > 0.0 and d["kind"] != "bow":
		var sp := Game.swing_speed(it)
		t += "Swing speed  %d%%\n" % int(round(sp * 100.0))
	if d["kind"] == "bow":
		t += "Shoots arrows. Hold the attack button to draw.\n"
	if d.has("stack"):
		t += "%d to a place\n" % int(d["stack"])
	var sz := Game.item_size(it)
	t += "[color=#bfb5a0]Weight %.2f kg     Size %d x %d[/color]" % [Game.weight(it), sz.x, sz.y]
	if mode == "trade":
		if where == "trade":
			var ok := Game.silver >= Game.price(it)
			t += "\n[color=#%s]Price %d silver[/color]" % ["ffd27a" if ok else "ff8060", Game.price(it)]
		elif where == "bag" and Game.sell_value(it) > 0:
			t += "\n[color=#ffd27a]Sells for %d silver[/color]" % Game.sell_value(it)
	return t
