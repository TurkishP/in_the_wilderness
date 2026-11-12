extends CanvasLayer
## All 2D interface: bars, objective, quest tracker, markers, toasts and the dialog panel.
##
## Every menu in the game is one dialog(): a title, some text and a list of options.
## The LAST option must always be the safe one (leave, close, not now), because Esc picks it.

const HumanScript := preload("res://scripts/human.gd")

var world
var auto := false         # test mode: a dialog picks its first option at once and never shows
var no_capture := false   # test mode: leave the mouse alone
var last_dialog := ""

var _hp: ProgressBar
var _thirst: ProgressBar
var _camp: ProgressBar
var _camp_label: Label
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
var _panel_style: StyleBoxFlat
var _creator: PanelContainer
var _creator_values := {}
var _creator_buttons := {}
var _creator_view_button: Button
var _creator_done := Callable()
var _creator_face := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	Game.toast.connect(_on_toast)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	left.position = Vector2(24, 20)
	left.add_theme_constant_override("separation", 4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	left.add_child(_text("Health", 15))
	_hp = _bar(Color(0.78, 0.22, 0.16))
	left.add_child(_hp)
	left.add_child(_text("Thirst", 15))
	_thirst = _bar(Color(0.22, 0.56, 0.86))
	left.add_child(_thirst)
	_stats = _text("", 17)
	left.add_child(_stats)
	_camp_label = _text("Camp under attack", 15, Color(1.0, 0.6, 0.5))
	left.add_child(_camp_label)
	_camp = _bar(Color(0.9, 0.65, 0.2))
	left.add_child(_camp)

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

	_quests = _text("", 16)
	_anchor(_quests, 1.0, 1.0, 0.0, 0.0, -400, -24, 20, 20)
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.05, 0.94)
	sb.border_color = Color(0.75, 0.6, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel_style = sb
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_title = _text("", 24, Color(1.0, 0.85, 0.5))
	v.add_child(_title)
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
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(270, 16)
	b.show_percentage = false
	b.max_value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_hp.value = Game.hp / Game.max_hp * 100.0
	_thirst.value = Game.thirst
	_hurt.color.a = move_toward(_hurt.color.a, 0.0, delta * 1.2)
	_prompt.text = "" if Game.ui_open else Game.prompt
	if world == null or world.stage.is_empty():
		return
	var facing := ""
	if is_instance_valid(world.player):
		var f: Vector3 = world.player.forward()
		facing = "    Facing %s" % world.compass(f.x, f.z)
	_stats.text = "Water %d/%d    Silver %d    Bronze %d%s" % [Game.water, Game.max_water, Game.silver, Game.bronze, facing]
	_stage.text = "Stage %d of %d   %s   (%s)" % [Game.stage_index + 1, Game.stage_count(), world.stage["name"], world.stage["ref"]]
	_objective.text = world.objective_text()
	_quests.text = world.quests.tracker_text() if is_instance_valid(world.quests) else ""
	var raid_on: bool = is_instance_valid(world.raid) and world.raid.active
	_camp.visible = raid_on
	_camp_label.visible = raid_on
	_camp.value = Game.camp_hp
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


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if _creator.visible:
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
	elif key == KEY_TAB:
		open_inventory()
	elif key == KEY_ESCAPE:
		open_pause()


# ---------------------------------------------------------------- menus

func open_pause() -> void:
	var text := "[b]Controls[/b]\nW A S D  move        Shift  sprint        Space  jump\nLeft mouse  strike        Right mouse  sling a stone at the crosshair\nE  talk or use        Q  drink        Tab  gear        Esc  this menu\n\nThirst falls as you travel and faster when you run. Rest inside the camp to heal.\nRaiders go for the camp. If the camp falls, the stage starts again."
	dialog("Paused", text, [
		["Change how you look", open_creator],
		["Start a new journey", _confirm_new],
		["Quit the game", world.quit_game],
		["Resume", Callable()],
	])


func _confirm_new() -> void:
	dialog("Start a new journey?", "Your saved progress will be replaced.", [
		["Yes, begin again from the Red Sea", world.new_journey],
		["No, keep going", Callable()],
	])


func open_inventory() -> void:
	var t := "Silver %d    Bronze %d    Health %d/%d\n\n[b]Equipped[/b]\n" % [Game.silver, Game.bronze, int(Game.hp), int(Game.max_hp)]
	for slot in Game.SLOTS:
		var inst: Dictionary = Game.equipped[slot]
		t += "%s:  %s  (%s)\n" % [str(slot).capitalize(), Game.item_name(inst), Game.item_desc(inst)]
	var options: Array = []
	if Game.bag.is_empty():
		t += "\nYour bag is empty."
	else:
		t += "\n[b]In your bag[/b] (%d)" % Game.bag.size()
		for inst in Game.bag.slice(0, 9):
			options.append(["Equip %s  (%s)" % [Game.item_name(inst), Game.item_desc(inst)], _equip.bind(inst)])
	options.append(["Close", Callable()])
	dialog("Your gear", t, options)


func _equip(inst: Dictionary) -> void:
	Game.equip(inst)
	open_inventory()


func open_shop() -> void:
	var options: Array = []
	for id in Game.shop_stock(int(world.stage["tier"])):
		var d: Dictionary = Game.Items.ITEMS[id]
		var price: int = int(d["price"])
		var desc := Game.power_text(str(d["slot"]), float(d["power"]))
		options.append(["Buy %s  (%s)  for %d silver" % [d["name"], desc, price], _buy.bind(id), Game.silver >= price])
	if Game.max_water < 6:
		var wp := Game.waterskin_price()
		options.append(["Buy a larger waterskin  (+1 drink)  for %d silver" % wp, _buy_waterskin, Game.silver >= wp])
	if not Game.bag.is_empty():
		options.append(["Sell spare gear", open_sell])
	options.append(["Leave", Callable()])
	dialog("Caravan trader", "\"Bronze, leather and slings. Fair weights and fair prices.\"\n\nYou have %d silver." % Game.silver, options)


func _buy(id: String) -> void:
	if Game.try_buy(id):
		Game.say("Bought: %s. Press Tab to equip it." % Game.Items.ITEMS[id]["name"])
	open_shop()


func _buy_waterskin() -> void:
	if Game.try_buy_waterskin():
		Game.say("Your waterskin now holds %d drinks." % Game.max_water)
	open_shop()


func open_sell() -> void:
	var options: Array = []
	for inst in Game.bag.slice(0, 9):
		options.append(["Sell %s for %d silver" % [Game.item_name(inst), Game.sell_value(inst)], _sell.bind(inst)])
	options.append(["Back", open_shop])
	dialog("Caravan trader", "\"Show me what you have.\"\n\nYou have %d silver." % Game.silver, options)


func _sell(inst: Dictionary) -> void:
	Game.sell(inst)
	if Game.bag.is_empty():
		open_shop()
	else:
		open_sell()


func open_smith() -> void:
	var cap := Game.max_plus()
	var options: Array = []
	for slot in Game.SLOTS:
		var inst: Dictionary = Game.equipped[slot]
		if int(inst["plus"]) >= cap:
			options.append(["%s cannot be made stronger here" % Game.item_name(inst), Callable(), false])
			continue
		var c := Game.upgrade_cost(inst)
		options.append(["Strengthen %s to +%d  for %d silver and %d bronze" % [Game.item_name(inst), int(inst["plus"]) + 1, c["silver"], c["bronze"]], _upgrade.bind(inst), Game.can_upgrade(inst)])
	options.append(["Leave", Callable()])
	var t := "\"Bring me silver for the work and bronze for the metal.\"\n\nYou have %d silver and %d bronze. Gear can be strengthened to +%d here." % [Game.silver, Game.bronze, cap]
	if cap < 5:
		t += " A proper workshop could do more."
	dialog("Camp craftsman", t, options)


func _upgrade(inst: Dictionary) -> void:
	if Game.try_upgrade(inst):
		Game.say("Strengthened: %s" % Game.item_name(inst))
	open_smith()


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
	Game.save_game()
	world.player.set_creator_view("")
	_set_open(false)
	Game.block_input()
	var done := _creator_done
	_creator_done = Callable()
	if done.is_valid():
		done.call()


func _refresh_creator() -> void:
	var female: bool = int(Game.look.get("sex", 0)) == 1
	for key in HumanScript.ORDER:
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
