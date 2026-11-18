extends CanvasLayer
## All 2D interface: bars, objective, quest tracker, markers, toasts and the dialog panel.
##
## Every menu in the game is one dialog(): a title, some text and a list of options.
## The LAST option must always be the safe one (leave, close, not now), because Esc picks it.

const HumanScript := preload("res://scripts/human.gd")
const MinimapScript := preload("res://scripts/minimap.gd")
const RegionMapScript := preload("res://scripts/region_map.gd")
const InventoryScript := preload("res://scripts/inventory_ui.gd")
const MenuScript := preload("res://scripts/menu.gd")
const GaugeScript := preload("res://scripts/gauge.gd")
const Ui := preload("res://scripts/ui.gd")

var world
var auto := false         # test mode: a dialog picks its first option at once and never shows
var no_capture := false   # test mode: leave the mouse alone
var last_dialog := ""
var minimap: Control       # the round map in the top-right corner

var _hp: Control            # the bars (gauge.gd), each with its name and numbers inside it
var _thirst: Control       # ... with the drinks left in the waterskin as drops after it
var _stamina: Control
var _xp: Control           # the level, and the experience toward the next
var _points: Label         # "3 points to spend", while there are any
var _xp_note := ""         # "+20" for a moment after experience is gained
var _xp_note_left := 0.0
var _stones: Label
var _camp: Control         # the camp's strength, shown while it is raided
var _stats: Label
var _stage: Label
var _objective: Label
var _quests: Label
var _prompt: Label
var _toasts: VBoxContainer
var _markers: Control
var _marker_labels: Array = []
var _panel: PanelContainer
var _title: Label
var _body: RichTextLabel
var _rows: VBoxContainer
var _hurt: ColorRect
var _cbs: Array = []
var _open_frame := -1
var _auto_depth := 0
var _coords: Label
var _map_panel: PanelContainer
var _region: Control
var _map_note: Label
var _map_travel: HFlowContainer   # the ways to earlier lands, or back to the camp
var _panel_style: StyleBoxFlat
var _creator: PanelContainer
var _creator_values := {}
var _creator_buttons := {}
var _creator_view_button: Button
var _creator_done := Callable()
var _creator_face := false
var inventory               # the bag, gear, chest and trader screens (inventory_ui.gd)
var _left: VBoxContainer     # the bars and counts in the top-left corner
var menu                    # the pause menu: journey, how to play, saves, settings (menu.gd)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	Game.toast.connect(_on_toast)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Ui.theme()
	add_child(root)

	_hurt = ColorRect.new()
	_hurt.color = Color(0.7, 0.05, 0.02, 0.0)
	_hurt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt)

	_markers = Control.new()
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_markers)

	var left := VBoxContainer.new()
	_left = left
	left.position = Vector2(24, 20)
	left.add_theme_constant_override("separation", 4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	_hp = _gauge(left, Color(0.8, 0.2, 0.15), "heart", 36.0)
	_hp.warn_below = 0.3
	_thirst = _gauge(left, Color(0.2, 0.52, 0.86), "drop", 30.0)
	_thirst.warn_below = 0.25
	_stamina = _gauge(left, Color(0.82, 0.66, 0.16), "bolt", 30.0)
	_xp = _gauge(left, Color(0.55, 0.36, 0.7), "star", 26.0)
	_points = _text("", 15, Color(1.0, 0.88, 0.58))
	left.add_child(_points)
	Game.xp_gained.connect(func(amount: int) -> void:
		_xp_note = "+%d" % amount
		_xp_note_left = 2.0)
	_stones = _text("", 18)
	left.add_child(_stones)
	_stats = _text("", 17)
	left.add_child(_stats)
	_camp = _gauge(left, Color(0.88, 0.5, 0.16), "tent", 30.0)
	_camp.warn_below = 0.35

	var top := VBoxContainer.new()
	_anchor(top, 0.5, 0.5, 0.0, 0.0, -500, 500, 14, 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_stage = _text("", 16, Color(1.0, 0.9, 0.65))
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_stage)
	_objective = _text("", 22)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_objective)

	_toasts = VBoxContainer.new()
	_anchor(_toasts, 0.5, 0.5, 0.0, 0.0, -500, 500, 96, 96)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)

	minimap = MinimapScript.new()
	minimap.world = world
	var map_size: float = (minimap.RADIUS + minimap.MARGIN) * 2.0
	_anchor(minimap, 1.0, 1.0, 0.0, 0.0, -map_size - 20.0, -20.0, 14.0, 14.0 + map_size)
	root.add_child(minimap)
	_coords = _text("", 14, Color(1.0, 0.95, 0.8))
	_anchor(_coords, 1.0, 1.0, 0.0, 0.0, -map_size - 60.0, 20.0, 18.0 + map_size, 60.0 + map_size)
	_coords.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_coords)

	_quests = _text("", 16)
	_anchor(_quests, 1.0, 1.0, 0.0, 0.0, -400, -24, 76.0 + map_size, 76.0 + map_size)
	_quests.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_quests)

	_prompt = _text("", 22, Color(1.0, 0.95, 0.7))
	_anchor(_prompt, 0.5, 0.5, 1.0, 1.0, -400, 400, -170, -140)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_prompt)

	var cross := _text("+", 22, Color(1, 1, 1, 0.75))
	_anchor(cross, 0.5, 0.5, 0.5, 0.5, -10, 10, -16, 16)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(cross)

	_panel = PanelContainer.new()
	_anchor(_panel, 0.5, 0.5, 1.0, 1.0, -460, 460, -36, -36)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := Ui.panel_style(22.0)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel_style = sb
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_title = Ui.label("", 25, Ui.GOLD, "bold")
	v.add_child(_title)
	v.add_child(Ui.rule())
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(880, 0)
	_body.add_theme_font_size_override("normal_font_size", 19)
	_body.add_theme_font_size_override("italics_font_size", 19)
	_body.add_theme_font_size_override("bold_font_size", 19)
	v.add_child(_body)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	v.add_child(_rows)
	_panel.visible = false
	root.add_child(_panel)
	_build_creator(root)
	_build_map(root)
	menu = MenuScript.new()
	menu.hud = self
	add_child(menu)
	inventory = InventoryScript.new()
	root.add_child(inventory)


func _anchor(c: Control, l: float, r: float, t: float, b: float, ol: float, o_r: float, ot: float, ob: float) -> void:
	c.anchor_left = l
	c.anchor_right = r
	c.anchor_top = t
	c.anchor_bottom = b
	c.offset_left = ol
	c.offset_right = o_r
	c.offset_top = ot
	c.offset_bottom = ob


func _text(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# Read over sand and sky alike: a thin dark edge and a soft shadow under each letter.
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## One of the bars in the corner (gauge.gd), added to `parent`.
func _gauge(parent: Control, color: Color, emblem: String, height: float) -> Control:
	var g = GaugeScript.new()
	g.color = color
	g.emblem = emblem
	g.custom_minimum_size = Vector2(380, height)
	# Keep the bar its own width: the text lines in the same column change length.
	g.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(g)
	return g


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_hp.show_value(Game.hp, Game.max_hp, "Health", "%d / %d" % [int(ceil(Game.hp)), int(round(Game.max_hp))])
	_thirst.show_value(Game.thirst, 100.0, "Thirst", "%d / 100" % int(ceil(Game.thirst)))
	_thirst.pips = Game.water
	_thirst.pips_max = Game.max_water
	_stamina.show_value(Game.stamina, Game.max_stamina, "Stamina", "%d / %d" % [int(ceil(Game.stamina)), int(round(Game.stamina_cap()))])
	_stamina.cap = Game.stamina_cap() / Game.max_stamina
	_xp_note_left = maxf(0.0, _xp_note_left - delta)
	var need: int = Game.xp_needed(Game.level)
	_xp.show_value(Game.xp, need, "Level %d" % Game.level, "%d / %d%s" % [Game.xp, need, "   " + _xp_note if _xp_note_left > 0.0 else ""])
	_points.visible = Game.stat_points > 0
	_points.text = "%d points to spend  (Esc)" % Game.stat_points if Game.stat_points != 1 else "1 point to spend  (Esc)"
	# What there is to shoot, for whatever is in hand to shoot it with.
	var ammo: Array = []
	if not Game.equipped["sling"].is_empty():
		ammo.append("Stones %d" % Game.stones())
	if not Game.bow().is_empty():
		ammo.append("Arrows %d" % Game.arrows())
	_stones.text = "        ".join(ammo)
	_stones.visible = not ammo.is_empty()
	var short: bool = (not Game.equipped["sling"].is_empty() and Game.stones() == 0) or (not Game.bow().is_empty() and Game.arrows() == 0)
	_stones.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if short else Color.WHITE)
	_hurt.color.a = move_toward(_hurt.color.a, 0.0, delta * 1.2)
	_left.visible = not inventory.visible
	_quests.visible = not inventory.visible
	_prompt.text = "" if Game.ui_open else Game.prompt
	if world == null or world.stage.is_empty():
		return
	var inside: bool = is_instance_valid(world.player) and world.player.indoors
	minimap.visible = not inside
	_coords.visible = not inside
	var facing := ""
	if is_instance_valid(world.player):
		var f: Vector3 = world.player.forward()
		facing = "    Facing %s" % world.compass(f.x, f.z)
	_stats.text = facing.strip_edges()
	_stage.text = "%s   Stage %d of %d   %s   (%s)%s" % [world.stage.get("year", ""), Game.land_index() + 1, Game.stage_count(), world.stage["name"], world.stage["ref"], "   ·   walked back" if Game.visiting >= 0 else ""]
	_objective.text = world.objective_text()
	_quests.text = world.quests.tracker_text() if is_instance_valid(world.quests) else ""
	var raid_on: bool = is_instance_valid(world.raid) and world.raid.active
	_camp.visible = raid_on
	_camp.show_value(Game.camp_hp, 100.0, "Camp under attack", "%d / 100" % int(ceil(Game.camp_hp)))
	_coords.text = "%s\n%s    M: map\n%s" % [world.stage["place"], minimap.coordinates(), Game.clock_text()]
	_update_markers()


func _update_markers() -> void:
	var cam := get_viewport().get_camera_3d()
	var list: Array = world.get_markers() if cam != null else []
	while _marker_labels.size() < list.size():
		var l := _text("", 17)
		_markers.add_child(l)
		_marker_labels.append(l)
	var size := get_viewport().get_visible_rect().size
	for i in _marker_labels.size():
		var l: Label = _marker_labels[i]
		if i >= list.size():
			l.visible = false
			continue
		var m: Dictionary = list[i]
		var pos: Vector3 = m["pos"]
		var sp := cam.unproject_position(pos)
		if cam.is_position_behind(pos):
			sp = Vector2(size.x - sp.x, size.y)
		sp.x = clampf(sp.x, 90.0, size.x - 90.0)
		sp.y = clampf(sp.y, 150.0, size.y - 200.0)
		l.text = "%s  %dm" % [m["text"], int(cam.global_position.distance_to(pos))]
		l.add_theme_color_override("font_color", m["color"])
		l.position = sp - Vector2(l.size.x * 0.5, l.size.y)
		l.visible = true


func flash_hurt() -> void:
	_hurt.color.a = 0.35


func _on_toast(text: String) -> void:
	if auto:
		return
	var l := _text(text, 19, Color(1.0, 0.97, 0.85))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toasts.add_child(l)
	while _toasts.get_child_count() > 4:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


# ---------------------------------------------------------------- dialog panel

## options: [[label, Callable], ...] with an optional third element `enabled`.
## With no options the dialog gets a single "Continue".
func dialog(speaker: String, text: String, options: Array = []) -> void:
	last_dialog = text
	if options.is_empty():
		options = [["Continue", Callable()]]
	if auto:
		# Test mode: take the first usable option. Menus that reopen themselves stop after a few levels.
		if _auto_depth >= 3:
			return
		_auto_depth += 1
		for o in options:
			if o.size() > 2 and not bool(o[2]):
				continue
			var first: Callable = o[1]
			if first.is_valid():
				first.call()
			break
		_auto_depth -= 1
		return
	_cbs.clear()
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_title.text = speaker
	_body.text = text
	for i in options.size():
		var o: Array = options[i]
		var b := Button.new()
		b.text = "%d.   %s" % [i + 1, o[0]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = o.size() > 2 and not bool(o[2])
		b.pressed.connect(_choose.bind(i))
		_rows.add_child(b)
		_cbs.append(o[1] if not b.disabled else null)
	_panel.visible = true
	_open_frame = Engine.get_process_frames()
	_set_open(true)


func _choose(i: int) -> void:
	if i < 0 or i >= _cbs.size() or _cbs[i] == null:
		return
	var cb: Callable = _cbs[i]
	Game.play_sound("click")
	close_panel()
	if cb.is_valid():
		cb.call()


func close_panel() -> void:
	_panel.visible = false
	_cbs.clear()
	_set_open(false)
	Game.block_input()


func _set_open(open: bool) -> void:
	Game.ui_open = open
	get_tree().paused = open
	if not no_capture:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


## Clicking into the game while the mouse is free and nothing is open on screen takes hold of it
## again, for looking about and striking (after a save is loaded straight into the stage, or the
## window was left and come back to). That click only takes hold; it does not also strike.
func _unhandled_input(event: InputEvent) -> void:
	if no_capture or title_up or Game.ui_open:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.block_input()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if title_up and not menu.is_open():
		return
	if inventory.visible:
		get_viewport().set_input_as_handled()
		if key == KEY_ESCAPE or key == KEY_I or key == KEY_TAB or (key == KEY_E and inventory.mode == "chest"):
			inventory.close()
	elif menu.is_open():
		get_viewport().set_input_as_handled()
		if key == KEY_ESCAPE:
			menu.close()
	elif _map_panel.visible:
		get_viewport().set_input_as_handled()
		if key == KEY_M or key == KEY_ESCAPE or key == KEY_ENTER:
			close_map()
	elif _creator.visible:
		get_viewport().set_input_as_handled()
		if key == KEY_ESCAPE or key == KEY_ENTER:
			close_creator()
	elif _panel.visible:
		get_viewport().set_input_as_handled()
		if Engine.get_process_frames() == _open_frame:
			return
		if key >= KEY_1 and key <= KEY_9:
			_choose(key - KEY_1)
		elif key == KEY_ESCAPE or key == KEY_TAB:
			_choose(_cbs.size() - 1)
		elif (key == KEY_ENTER or key == KEY_SPACE or key == KEY_E) and _cbs.size() == 1:
			_choose(0)
	elif key == KEY_I or key == KEY_TAB:
		open_inventory()
	elif key == KEY_M:
		open_map()
	elif key == KEY_ESCAPE:
		open_pause()


# ---------------------------------------------------------------- menus

## The menu (menu.gd), opened at The Journey.
func open_pause() -> void:
	_panel.visible = false
	_cbs.clear()
	menu.open("journey")


func open_inventory() -> void:
	if auto or inventory.visible:
		return
	_panel.visible = false
	_cbs.clear()
	inventory.open("gear", 1, _inventory_closed)
	_set_open(true)


## The trader's goods beside the bag: click to buy, right-click your own things to sell.
func open_shop() -> void:
	last_dialog = "\"Bronze, leather and slings. Fair weights and fair prices.\"  You have %d silver." % Game.silver
	if auto:
		return
	_panel.visible = false
	_cbs.clear()
	inventory.open("trade", int(world.stage["tier"]), _inventory_closed)
	_set_open(true)


## A caravan's goods beside the bag: a few rare pieces, dear, each gone once bought. `stock` is
## the caravan's own grid, so what is bought stays bought.
func open_caravan(stock: Array, title: String) -> void:
	last_dialog = "\"Goods from Egypt and the lands of incense. You will not see their like again.\"  You have %d silver." % Game.silver
	if auto:
		return
	_panel.visible = false
	_cbs.clear()
	inventory.open("trade", int(world.stage["tier"]), _inventory_closed, {"stock": stock, "title": title})
	_set_open(true)


## The chest in the scout's own tent, beside the bag: what is left here stays for the whole
## journey. `on_close` runs when it is shut.
func open_chest(on_close: Callable = Callable()) -> void:
	if auto:
		if on_close.is_valid():
			on_close.call()
		return
	_panel.visible = false
	_cbs.clear()
	inventory.open("chest", 1, func() -> void:
		_inventory_closed()
		if on_close.is_valid():
			on_close.call())
	_set_open(true)


func _inventory_closed() -> void:
	_set_open(false)
	Game.block_input()


## The camp's smith: he makes what you carry stronger, and forges new arms from your bronze.
func open_smith() -> void:
	var t := "\"Bring me silver for the work and bronze for the metal.\"\n\nYou have [b]%d silver[/b] and [b]%d bronze[/b]." % [Game.silver, Game.bronze]
	dialog("Camp craftsman", t, [
		["Make what I carry stronger", _smith_improve.bind(0)],
		["Forge something new", _smith_forge.bind(0)],
		["Leave", Callable()],
	])


## Everything that can be made stronger: what is worn first, then what is in the bag.
func _smith_improve(page: int) -> void:
	var cap := Game.max_plus()
	var gear: Array = []
	for slot in Game.Items.EQUIP_SLOTS:
		if Game.can_strengthen(Game.equipped[slot]):
			gear.append(Game.equipped[slot])
	for it in Game.bag:
		if Game.can_strengthen(it):
			gear.append(it)
	var options: Array = []
	for inst in gear:
		if int(inst["plus"]) >= cap:
			options.append(["%s cannot be made stronger here" % Game.item_name(inst), Callable(), false])
			continue
		var c := Game.upgrade_cost(inst)
		var gain := "damage %d to %d" % [int(round(Game.stat(inst, "damage"))), int(round(Game.stat(inst, "damage") / (1.0 + Game.PLUS_POWER * int(inst["plus"])) * (1.0 + Game.PLUS_POWER * (int(inst["plus"]) + 1))))]
		if Game.stat(inst, "damage") <= 0.0:
			gain = "defense %d to %d" % [int(round(Game.stat(inst, "defense"))), int(round(Game.stat(inst, "defense") / (1.0 + Game.PLUS_ARMOR * int(inst["plus"])) * (1.0 + Game.PLUS_ARMOR * (int(inst["plus"]) + 1))))]
		options.append(["%s to +%d   (%s)   for %d silver, %d bronze" % [Game.item_name(inst), int(inst["plus"]) + 1, gain, c["silver"], c["bronze"]], _upgrade.bind(inst, page), Game.can_upgrade(inst)])
	var t := "\"Each working makes it bite deeper, or turn a harder blow.\"\n\nYou have [b]%d silver[/b] and [b]%d bronze[/b]. Gear can be made stronger up to +%d here." % [Game.silver, Game.bronze, cap]
	if cap < 5:
		t += " A proper workshop could do more."
	_smith_page("Make it stronger", t, options, page, _smith_improve)


## What he can forge at this stage (data/forge.gd).
func _smith_forge(page: int) -> void:
	var options: Array = []
	for r in Game.forge_list(int(world.stage["tier"])):
		var made := Game.new_item(str(r["item"]))
		var what := Game.item_desc(made)
		var cost := "%d silver, %d bronze" % [r["silver"], r["bronze"]]
		if r.has("needs"):
			cost += ", your %s" % str(Game.Items.ITEMS[r["needs"]]["name"]).to_lower()
		options.append(["%s   (%s)   for %s" % [Game.item_name(made), what, cost], _forge.bind(r, page), Game.can_forge(r)])
	var t := "\"I can make these with what the camp has. You bring the bronze.\"\n\nYou have [b]%d silver[/b] and [b]%d bronze[/b]. Bronze is taken from raiders." % [Game.silver, Game.bronze]
	_smith_page("Forge something new", t, options, page, _smith_forge)


## One page of a long list at the smith's: up to six lines, then More, and Back.
func _smith_page(heading: String, text: String, options: Array, page: int, again: Callable) -> void:
	var per := 6
	var pages := maxi(1, int(ceil(options.size() / float(per))))
	page = clampi(page, 0, pages - 1)
	var shown: Array = options.slice(page * per, page * per + per)
	if options.is_empty():
		text += "\n\n[i]There is nothing here for him to work on.[/i]"
	if pages > 1:
		shown.append(["More...   (page %d of %d)" % [page + 1, pages], again.bind((page + 1) % pages)])
	shown.append(["Back", open_smith])
	dialog("Camp craftsman:  %s" % heading, text, shown)


func _upgrade(inst: Dictionary, page: int = 0) -> void:
	if Game.try_upgrade(inst):
		Game.say("Strengthened: %s" % Game.item_name(inst))
		Game.play_sound("anvil")
	_smith_improve(page)


func _forge(recipe: Dictionary, page: int) -> void:
	if Game.try_forge(recipe):
		Game.say("Forged: %s. It is in your bag." % Game.Items.ITEMS[recipe["item"]]["name"])
		Game.play_sound("anvil")
	_smith_forge(page)


# ---------------------------------------------------------------- character creator

func _build_creator(root: Control) -> void:
	_creator = PanelContainer.new()
	_anchor(_creator, 1.0, 1.0, 0.5, 0.5, -600, -40, 0, 0)
	_creator.grow_vertical = Control.GROW_DIRECTION_BOTH
	_creator.add_theme_stylebox_override("panel", _panel_style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_creator.add_child(v)
	v.add_child(_text("Your scout", 26, Color(1.0, 0.85, 0.5)))
	v.add_child(_text("Choose how you look. You can change it later from the pause menu.", 15))
	for key in HumanScript.ORDER:
		if key == "outfit":
			continue    # the scout's clothes are what is equipped (inventory)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := _text(str(HumanScript.LABELS[key]), 18)
		name_label.custom_minimum_size.x = 150
		row.add_child(name_label)
		var prev := _small_button("<", _creator_step.bind(key, -1))
		row.add_child(prev)
		var value := _text("", 18, Color(1.0, 0.95, 0.75))
		value.custom_minimum_size.x = 230
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		var next := _small_button(">", _creator_step.bind(key, 1))
		row.add_child(next)
		v.add_child(row)
		_creator_values[key] = value
		_creator_buttons[key] = [prev, next]
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.add_child(_small_button("Randomize", _creator_random, 120))
	bottom.add_child(_small_button("Turn", _creator_turn, 80))
	_creator_view_button = _small_button("Look at face", _creator_toggle_view, 140)
	bottom.add_child(_creator_view_button)
	bottom.add_child(_small_button("Done", close_creator, 100))
	v.add_child(bottom)
	_creator.visible = false
	root.add_child(_creator)


func _small_button(text: String, callback: Callable, width: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 34)
	b.add_theme_font_size_override("font_size", 17)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b


## Opens the character creator. `done` runs when the player closes it.
func open_creator(done: Callable = Callable()) -> void:
	if auto:
		Game.look_set = true
		if done.is_valid():
			done.call()
		return
	_panel.visible = false
	_cbs.clear()
	_creator_done = done
	_creator_face = false
	_refresh_creator()
	_creator.visible = true
	_set_open(true)
	world.player.set_creator_view("body")


func close_creator() -> void:
	if not _creator.visible:
		return
	_creator.visible = false
	Game.look_set = true
	world.player.set_creator_view("")
	_set_open(false)
	Game.block_input()
	var done := _creator_done
	_creator_done = Callable()
	if done.is_valid():
		done.call()


func _refresh_creator() -> void:
	var female: bool = int(Game.look.get("sex", 0)) == 1
	for key in _creator_values:
		var value: Label = _creator_values[key]
		value.text = HumanScript.value_name(key, Game.look)
		var locked: bool = key == "beard" and female
		for b in _creator_buttons[key]:
			b.disabled = locked
	_creator_view_button.text = "Look at body" if _creator_face else "Look at face"


func _creator_step(key: String, step: int) -> void:
	HumanScript.cycle(Game.look, key, step)
	Game.look_changed.emit()
	_refresh_creator()


func _creator_random() -> void:
	Game.look = HumanScript.random_look(Game.rng, int(Game.look.get("sex", 0)))
	Game.look_changed.emit()
	_refresh_creator()


func _creator_turn() -> void:
	world.player.turn_in_creator()


func _creator_toggle_view() -> void:
	_creator_face = not _creator_face
	world.player.set_creator_view("face" if _creator_face else "body")
	_refresh_creator()


# ---------------------------------------------------------------- maps

## Called when a stage has been built: the minimap takes a new picture of the ground.
func show_stage(terrain) -> void:
	minimap.set_terrain(terrain)
	_region.stage_index = Game.stage_index


func _build_map(root: Control) -> void:
	_map_panel = PanelContainer.new()
	_anchor(_map_panel, 0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0)
	_map_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_map_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_map_panel.add_theme_stylebox_override("panel", _panel_style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_map_panel.add_child(v)
	v.add_child(_text("The journey", 24, Color(1.0, 0.85, 0.5)))
	_region = RegionMapScript.new()
	v.add_child(_region)
	_map_note = _text("", 15)
	v.add_child(_map_note)
	# Walking back to the lands of earlier stages, and returning (see open_map).
	_map_travel = HFlowContainer.new()
	_map_travel.add_theme_constant_override("h_separation", 8)
	_map_travel.add_theme_constant_override("v_separation", 6)
	v.add_child(_map_travel)
	v.add_child(_small_button("Close  (M)", close_map, 120))
	_map_panel.visible = false
	root.add_child(_map_panel)


## Opens the map of the whole journey.
func open_map() -> void:
	if auto or _panel.visible or _creator.visible:
		return
	_region.stage_index = Game.stage_index
	_region.queue_redraw()
	_map_note.text = "Camp %d of %d:  %s  (%s)\nCamp sites follow traditional identifications; several are debated." % [
		Game.stage_index + 1, Game.stage_count(), Game.Stages.LIST[Game.stage_index]["place"], Game.Stages.LIST[Game.stage_index]["ref"]]
	for c in _map_travel.get_children():
		_map_travel.remove_child(c)
		c.queue_free()
	if Game.visiting >= 0:
		_map_note.text = "You have walked back to the land of stage %d:  %s  (%s)." % [Game.visiting + 1, world.stage["place"], world.stage["ref"]]
		var back := _small_button("Return to the camp", _return_from_map, 240)
		back.disabled = world.player.in_fight()
		_map_travel.add_child(back)
		if back.disabled:
			_map_travel.add_child(_text("Not while enemies are on you.", 15))
	elif Game.stage_index > 0:
		if world.can_travel_back():
			_map_travel.add_child(_text("Walk back to an earlier land:", 15))
			for i in Game.stage_index:
				_map_travel.add_child(_small_button("%d.  %s" % [i + 1, Game.Stages.LIST[i]["name"]], _travel_from_map.bind(i), 220))
		else:
			_map_travel.add_child(_text("From your camp you can walk back to the lands of earlier stages.", 15))
	_map_panel.visible = true
	_set_open(true)


func _travel_from_map(i: int) -> void:
	close_map()
	world.travel_back(i)


func _return_from_map() -> void:
	close_map()
	world.return_to_camp()


func close_map() -> void:
	if not _map_panel.visible:
		return
	_map_panel.visible = false
	_set_open(false)
	Game.block_input()


# ---------------------------------------------------------------- settings
var title_up := false       # the title screen is showing: the game's keys do nothing


## The settings page of the menu, from the title screen (which passes what to do on leaving it)
## or anywhere else. Changes take effect at once and are kept.
func open_settings(back: Callable = Callable()) -> void:
	_panel.visible = false
	_cbs.clear()
	menu.open("settings", back)
