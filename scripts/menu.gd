extends CanvasLayer
## The menu: one framed page over the dimmed game, its sections down the left side.
##
##   The Journey     where the story stands: each stage's introduction (shown once as a dialog
##                   when the stage begins, and kept here to read again), and what lies ahead
##   The Scout       level and experience, and the four stats with the points to put into them
##   How to Play     the controls and the rules
##   Saved Journeys  every save, newest first; any of them can be gone back to
##   Settings        sound, mouse and picture
##
## Esc opens it in the game (hud.open_pause). The title screen opens the same page with only
## the sections that make sense there (open() with `back` or `on_load`).

const Ui := preload("res://scripts/ui.gd")
const Stages := preload("res://data/stages.gd")

const Skills := preload("res://data/skills.gd")
const LampstandScript := preload("res://scripts/lampstand.gd")
const SECTIONS := [["journey", "The Journey"], ["scout", "The Scout"], ["skills", "Skills"], ["how", "How to Play"], ["saves", "Saved Journeys"], ["settings", "Settings"]]
const CONTROLS := [
	["W  A  S  D", "Move"],
	["Shift", "Sprint"],
	["Space", "Jump. Against a rock or a ledge within reach, climb onto it"],
	["Left mouse", "Strike; press again during a blow for the next, up to three. With a bow, hold to draw and release to shoot"],
	["Hold left mouse", "Once the skill is learned: a sword's long thrust, an axe's heavy cleave, a knife or spear thrown"],
	["Right mouse", "Hold to whirl the sling, release to throw. The ring shows where the stone will land"],
	["R", "Put your weapons away, or take them up"],
	["F", "Battle stance: alert, knees bent, the weapon held ready. Taken on its own when you fight, and left when all is quiet; F again or R to stand at ease"],
	["E", "Talk, or use what is in front of you"],
	["Q", "Drink from your waterskin"],
	["I  or  Tab", "Your bag and what you wear"],
	["M", "The map"],
	["Esc", "This menu"],
]
const RULES := [
	"A day lasts six hours of play: the hour is shown under the map. Thirst runs out about three times a day, faster under the midday sun and when running, slower by night, in the tent, or under a headcloth or robe.",
	"Under 30 thirst your breath is short: the most stamina you can have shrinks. At nothing, your health drains until you drink. Sprinting tires you; walk to get your breath back. Rest inside the camp to heal.",
	"Each sling stone and arrow is used up when shot. Gather stones from stony ground, or buy them from the trader.",
	"Heavier weapons swing more slowly. The craftsman in the camp makes weapons and armour stronger, for silver and bronze.",
	"What falls from an enemy lies where it fell: silver, bronze, gear, and now and then something rare. Champions and chiefs carry the best.",
	"Enemies defeated and tasks done bring experience. Each level gives points for Strength, Dexterity, Intelligence and Luck, spent under The Scout.",
	"Each kind of weapon grows better with use: blows that land and enemies felled with it raise its skill, and each rise gives a point to spend in its tree, under Skills.",
	"The journey is saved only when you sleep in your own tent. Raiders go for the camp: if the camp falls, the stage starts again.",
]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var hud
var section := "journey"
var limited := false          # opened from the title screen: no journey to show or leave
var _back := Callable()       # title: what to do when the menu closes
var _on_load := Callable()    # title: what to do with a chosen save (its path)
var _root: Control
var _tabs := {}               # section -> Button
var _where: Label
var _head: Label
var _page: VBoxContainer
var _scroll: ScrollContainer
var _game_only: Array = []    # controls hidden when opened from the title
var _resume: Button
var _stage_shown := -1        # which stage The Journey shows (-1 = the current one)
var _setting_rows := {}
var _syncing := false
var _armed: Button            # a button pressed once that asks to be pressed again
var _armed_text := ""
var _tree_shown := ""          # the weapon tree the Skills page shows
var _skill_shown := ""         # and the skill chosen on it


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Ui.theme()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var frame := Ui.framed(24.0)
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -600
	frame.offset_right = 600
	frame.offset_top = -360
	frame.offset_bottom = 360
	_root.add_child(frame)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	frame.get_child(0).add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	left.add_child(Ui.label("IN THE WILDERNESS", 21, Ui.GOLD, "display"))
	_where = Ui.label("", 16, Ui.MUTED, "italic")
	_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_where)
	left.add_child(Ui.rule())
	for s in SECTIONS:
		var tab := _button(str(s[1]), show_section.bind(str(s[0])), 20)
		_tabs[s[0]] = tab
		left.add_child(tab)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(gap)
	var look := _button("Change how you look", _change_look, 17)
	var anew := _button("Begin a new journey", Callable(), 17)
	anew.pressed.connect(_ask_twice.bind(anew, "Lose this journey?  Press again", _new_journey))
	var quit := _button("Quit the game", Callable(), 17)
	quit.pressed.connect(_ask_twice.bind(quit, "Unsaved steps are lost.  Press again", _quit))
	for b in [look, anew, quit]:
		left.add_child(b)
		_game_only.append(b)
	_game_only.append(_tabs["journey"])
	_game_only.append(_tabs["scout"])
	_game_only.append(_tabs["skills"])
	left.add_child(Ui.rule())
	_resume = _button("Resume   (Esc)", close, 20)
	left.add_child(_resume)

	var line := ColorRect.new()
	line.color = Color(Ui.BRONZE.r, Ui.BRONZE.g, Ui.BRONZE.b, 0.45)
	line.custom_minimum_size.x = 1
	columns.add_child(line)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	_head = Ui.heading("", 30)
	right.add_child(_head)
	right.add_child(Ui.rule())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 12)
	_scroll.add_child(_page)


func is_open() -> bool:
	return _root.visible


## Opens the menu at `at`. From the title screen, pass `back` (run when the menu closes) and,
## to let a save be picked, `on_load` (called with the save's path).
func open(at: String = "journey", back: Callable = Callable(), on_load: Callable = Callable()) -> void:
	if hud.auto:
		return
	hud._panel.visible = false
	hud._cbs.clear()
	_back = back
	_on_load = on_load
	limited = back.is_valid() or on_load.is_valid()
	for c in _game_only:
		(c as Control).visible = not limited
	_resume.text = "Back   (Esc)" if limited else "Resume   (Esc)"
	_stage_shown = -1
	if limited:
		_where.text = "Forty years from the Red Sea to the Jordan"
		if at == "journey":
			at = "saves"
	else:
		var st: Dictionary = Game.stage()
		_where.text = "%s  ·  Stage %d of %d\n%s" % [st.get("year", ""), Game.stage_index + 1, Game.stage_count(), st["name"]]
	_root.visible = true
	hud._set_open(true)
	Game.play_sound("page")
	show_section(at)


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	hud._set_open(false)
	Game.block_input()
	if _back.is_valid():
		var back := _back
		_back = Callable()
		back.call()


func show_section(at: String) -> void:
	section = at
	_disarm()
	for key in _tabs:
		var tab: Button = _tabs[key]
		if key == at:
			tab.add_theme_stylebox_override("normal", Ui.theme().get_stylebox("pressed", "Button"))
			tab.add_theme_color_override("font_color", Ui.GOLD)
		else:
			tab.remove_theme_stylebox_override("normal")
			tab.remove_theme_color_override("font_color")
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	_setting_rows.clear()
	for s in SECTIONS:
		if s[0] == at:
			_head.text = str(s[1]).to_upper()
	match at:
		"journey":
			_journey()
		"scout":
			_scout()
		"skills":
			_skills()
		"how":
			_how()
		"saves":
			_saves()
		"settings":
			_settings()
	_scroll.scroll_vertical = 0


# ---------------------------------------------------------------- the sections

func _journey() -> void:
	var now: int = Game.stage_index
	var shown := now if _stage_shown < 0 else clampi(_stage_shown, 0, now)
	var st: Dictionary = Stages.LIST[shown]
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", 12)
	var earlier := _button("<  Earlier", _turn_to.bind(shown - 1), 16)
	earlier.disabled = shown <= 0
	var later := _button("Later  >", _turn_to.bind(shown + 1), 16)
	later.disabled = shown >= now
	var which := Ui.label("Stage %d of %d" % [shown + 1, Game.stage_count()], 17, Ui.MUTED)
	which.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	which.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pager.add_child(earlier)
	pager.add_child(which)
	pager.add_child(later)
	_page.add_child(pager)
	_page.add_child(Ui.label("%s  ·  %s" % [st.get("year", ""), st["name"]], 27, Ui.GOLD, "bold"))
	_page.add_child(_wrapped("%s   (%s)\n%s" % [st["place"], st["ref"], st["when"]], 17, Ui.MUTED, "italic"))
	_page.add_child(_story(str(st["intro"])))
	_page.add_child(Ui.rule())
	if shown == now:
		_page.add_child(Ui.label("What lies ahead", 21, Ui.GOLD, "bold"))
		_page.add_child(_wrapped(str(hud.world.objective_text()), 19))
		var quests: String = hud._quests.text
		if quests.strip_edges() != "":
			_page.add_child(Ui.label("Asked of you in the camp", 21, Ui.GOLD, "bold"))
			_page.add_child(_wrapped(quests.strip_edges(), 18))
	else:
		_page.add_child(_wrapped(str(st["outro"]), 19, Ui.MUTED, "italic"))


func _turn_to(stage_index: int) -> void:
	_stage_shown = stage_index
	show_section("journey")


## Level, experience, and the stats: each with what it does now and a button to raise it.
func _scout() -> void:
	_page.add_child(Ui.label("Level %d" % Game.level, 27, Ui.GOLD, "bold"))
	var need: int = Game.xp_needed(Game.level)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	bar.max_value = need
	bar.value = Game.xp
	var fill := StyleBoxFlat.new()
	fill.bg_color = Ui.GOLD.darkened(0.15)
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.5)
	back.border_color = Color(Ui.BRONZE.r, Ui.BRONZE.g, Ui.BRONZE.b, 0.6)
	back.set_border_width_all(1)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	_page.add_child(bar)
	_page.add_child(_wrapped("%d of %d experience toward level %d.   Health %d.   Experience comes from enemies defeated, tasks done and what is asked of you in the camp." % [Game.xp, need, Game.level + 1, int(round(Game.max_hp))], 16, Ui.MUTED, "italic"))
	_page.add_child(Ui.rule())
	var left_over: int = Game.stat_points
	_page.add_child(Ui.label("%d points to spend" % left_over if left_over != 1 else "1 point to spend", 21, Ui.GOLD if left_over > 0 else Ui.MUTED, "bold"))
	for key in Game.STAT_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var name_label := Ui.label(str(Game.STAT_LABELS[key]), 21, Ui.PARCHMENT, "bold")
		name_label.custom_minimum_size.x = 150
		row.add_child(name_label)
		var value := Ui.label(str(int(Game.stats[key])), 24, Ui.GOLD, "bold")
		value.custom_minimum_size.x = 44
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		var more := _button("+", _raise.bind(str(key)), 20)
		more.custom_minimum_size.x = 44
		more.alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.disabled = left_over <= 0
		row.add_child(more)
		row.add_child(_wrapped(Game.stat_effect(str(key)), 16, Ui.MUTED))
		_page.add_child(row)
	_page.add_child(Ui.rule())
	_page.add_child(_wrapped("Each level gives %d points and %d more health. A point once given cannot be taken back." % [Game.POINTS_PER_LEVEL, int(Game.HP_PER_LEVEL)], 16, Ui.MUTED, "italic"))


## The weapon skill trees: one tab per weapon family with its skill and points, then its skills
## tier by tier, each with what it does and a button to learn it.
func _skills() -> void:
	if _tree_shown == "":
		# Open on the tree of the weapon in hand, or the first with points to spend.
		_tree_shown = Game.tree_of(Game.kind(Game.weapon_in("hand_r")))
		for tree in Skills.ORDER:
			if int(Game.skill_points.get(tree, 0)) > 0:
				_tree_shown = tree
				break
		if _tree_shown == "":
			_tree_shown = "staff"
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for tree in Skills.ORDER:
		var points := int(Game.skill_points.get(tree, 0))
		var b := _button("%s  %d%s" % [Skills.TREES[tree]["name"], Game.skill_step(tree), ("  +%d" % points) if points > 0 else ""], _show_tree.bind(tree), 16)
		if tree == _tree_shown:
			b.add_theme_stylebox_override("normal", Ui.theme().get_stylebox("pressed", "Button"))
			b.add_theme_color_override("font_color", Ui.GOLD)
		elif points > 0:
			b.add_theme_color_override("font_color", Ui.GOLD.lightened(0.2))
		tabs.add_child(b)
	_page.add_child(tabs)
	var t: Dictionary = Skills.TREES[_tree_shown]
	_page.add_child(Ui.label("%s  ·  %s" % [t["name"], t["title"]], 27, Ui.GOLD, "bold"))
	var step := Game.skill_step(_tree_shown)
	var have := int(Game.skill_xp.get(_tree_shown, 0))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.show_percentage = false
	if step < Skills.MAX_STEPS:
		bar.min_value = Skills.xp_for_step(step)
		bar.max_value = Skills.xp_for_step(step + 1)
		bar.value = have
	else:
		bar.max_value = 1
		bar.value = 1
	var fill := StyleBoxFlat.new()
	fill.bg_color = Ui.GOLD.darkened(0.15)
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.5)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	_page.add_child(bar)
	var points := int(Game.skill_points.get(_tree_shown, 0))
	var progress := "Skill %d of %d." % [step, Skills.MAX_STEPS]
	if step < Skills.MAX_STEPS:
		progress += "   %d of %d toward the next." % [have - Skills.xp_for_step(step), Skills.xp_for_step(step + 1) - Skills.xp_for_step(step)]
	_page.add_child(_wrapped("%s   %s   %d spent in this tree." % [progress, "1 point to spend." if points == 1 else "%d points to spend." % points, Game.spent_in(_tree_shown)], 17, Ui.GOLD if points > 0 else Ui.PARCHMENT))
	# The tree as the lampstand: basic skills on its foot, the capstone in its top lamp.
	if Skills.find(_skill_shown).is_empty() or str(Skills.find(_skill_shown)["tree"]) != _tree_shown:
		_skill_shown = _first_to_show(_tree_shown)
	var stand = LampstandScript.new()
	stand.tree = _tree_shown
	stand.selected = _skill_shown
	stand.picked.connect(_pick_skill)
	_page.add_child(stand)
	_page.add_child(_wrapped("Hover over a skill to see what it does; click it to choose it.   %s   %s" % [t["idea"], t["weapons"]], 15, Ui.MUTED, "italic"))
	_page.add_child(_skill_card(_skill_shown))
	_page.add_child(Ui.rule())
	_page.add_child(_wrapped("A weapon learns by being used: %d for a blow that lands (a stone or arrow that strikes counts the same), %d for an enemy felled, %d for a champion or chief. Every step of its skill gives this tree a point. Levels give stat points, not these. A point once spent stays spent." % [Skills.BLOW, Skills.KILL, Skills.GREAT_KILL], 15, Ui.MUTED, "italic"))


func _show_tree(tree: String) -> void:
	_tree_shown = tree
	_skill_shown = ""
	show_section("skills")


func _pick_skill(id: String) -> void:
	_skill_shown = id
	show_section("skills")


## The skill to show first on a tree: one that can be learned now, else the lowest not yet learned.
func _first_to_show(tree: String) -> String:
	var skills: Array = Skills.TREES[tree]["skills"]
	for s in skills:
		if Game.why_not(str(s["id"])) == "":
			return str(s["id"])
	for s in skills:
		if not Game.has_perk(str(s["id"])):
			return str(s["id"])
	return str(skills[skills.size() - 1]["id"])


## The chosen skill: its name, tier and cost, what it does, and the button to learn it.
func _skill_card(id: String) -> Control:
	var s: Dictionary = Skills.find(id)["skill"]
	var tier := int(s["tier"])
	var cost := int(Skills.COST[tier])
	var card := Ui.framed(16.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var learned := Game.has_perk(id)
	box.add_child(Ui.label(str(s["name"]), 24, Ui.GOLD, "bold"))
	var where := "%s   ·   %d point%s" % [Skills.TIER_NAMES[tier], cost, "" if cost == 1 else "s"]
	if s.has("ref"):
		where += "   ·   %s" % s["ref"]
	box.add_child(_wrapped(where, 15, Ui.MUTED, "italic"))
	box.add_child(_wrapped(str(s["text"]), 18))
	var why := Game.why_not(id)
	var act := _button("Learned" if learned else ("Learn  (%d point%s)" % [cost, "" if cost == 1 else "s"] if why == "" else why), _learn.bind(id), 17)
	act.disabled = why != ""
	act.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	act.custom_minimum_size.x = 260
	box.add_child(act)
	return card


func _learn(id: String) -> void:
	if Game.learn(id):
		Game.play_sound("find", null, -6.0, 1.3)
		show_section("skills")


func _raise(stat_name: String) -> void:
	if Game.spend_point(stat_name):
		show_section("scout")


func _how() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 9)
	for row in CONTROLS:
		var key := Ui.label(str(row[0]), 18, Ui.GOLD, "bold")
		key.custom_minimum_size.x = 150
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(key)
		grid.add_child(_wrapped(str(row[1]), 18))
	_page.add_child(grid)
	_page.add_child(Ui.rule())
	for line in RULES:
		_page.add_child(_wrapped(str(line), 18))


func _saves() -> void:
	_page.add_child(_wrapped("The journey is saved each time you sleep in your own tent. The last %d mornings are kept, and you can go back to any of them." % Game.MAX_SAVES, 17, Ui.MUTED, "italic"))
	var saves: Array = Game.list_saves()
	if saves.is_empty():
		_page.add_child(_wrapped("No journey saved yet.", 20))
		return
	for i in saves.size():
		var s: Dictionary = saves[i]
		var st: Dictionary = Stages.LIST[int(s["stage_index"])]
		var row := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(Ui.INK_LIGHT.r, Ui.INK_LIGHT.g, Ui.INK_LIGHT.b, 0.85)
		box.border_color = Color(Ui.BRONZE.r, Ui.BRONZE.g, Ui.BRONZE.b, 0.5)
		box.border_width_bottom = 1
		box.set_corner_radius_all(3)
		box.set_content_margin_all(12)
		row.add_theme_stylebox_override("panel", box)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		row.add_child(h)
		var what := VBoxContainer.new()
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.add_theme_constant_override("separation", 2)
		h.add_child(what)
		what.add_child(Ui.label("%s  ·  %s%s" % [st.get("year", ""), st["name"], "     (latest)" if i == 0 else ""], 20, Ui.GOLD, "bold"))
		var goals: int = (st["objectives"] as Array).size()
		what.add_child(Ui.label("%s  ·  %d of %d tasks done  ·  %d silver  ·  %s played" % [st["place"], mini(int(s["obj_done"]), goals), goals, int(s["silver"]), _hours(float(s["played"]))], 15, Ui.MUTED))
		var when := Ui.label(_date(float(s["saved_at"])), 16)
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(when)
		var load_button := _button("Load", Callable(), 17)
		load_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if limited:
			load_button.pressed.connect(_load.bind(str(s["path"])))
		else:
			load_button.pressed.connect(_ask_twice.bind(load_button, "Sure?  Press again", _load.bind(str(s["path"]))))
		h.add_child(load_button)
		_page.add_child(row)


func _settings() -> void:
	for row in [["master", "Master volume", 0.0, 1.0, 0.05], ["music", "Music volume", 0.0, 1.0, 0.05], ["effects", "Effects volume", 0.0, 1.0, 0.05],
			["sensitivity", "Mouse sensitivity", 0.3, 2.5, 0.05], ["fov", "Field of view", 55.0, 100.0, 1.0]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		var l := Ui.label(str(row[1]), 19)
		l.custom_minimum_size.x = 230
		h.add_child(l)
		var slider := HSlider.new()
		slider.min_value = float(row[2])
		slider.max_value = float(row[3])
		slider.step = float(row[4])
		slider.custom_minimum_size = Vector2(360, 26)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_NONE
		h.add_child(slider)
		var shown := Ui.label("", 19, Ui.GOLD)
		shown.custom_minimum_size.x = 70
		h.add_child(shown)
		slider.value_changed.connect(_on_setting.bind(str(row[0])))
		_setting_rows[row[0]] = [slider, shown]
		_page.add_child(h)
	_page.add_child(Ui.rule())
	for row in [["invert_y", "Invert mouse up and down"], ["fullscreen", "Full screen"], ["vsync", "V-Sync"], ["shadows", "Shadows"]]:
		var box := CheckBox.new()
		box.text = str(row[1])
		box.add_theme_font_size_override("font_size", 19)
		box.focus_mode = Control.FOCUS_NONE
		box.toggled.connect(_on_setting.bind(str(row[0])))
		_setting_rows[row[0]] = [box, null]
		_page.add_child(box)
	var defaults := _button("Back to the defaults", _settings_defaults, 17)
	defaults.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_page.add_child(defaults)
	_sync_settings()


func _on_setting(value: Variant, key: String) -> void:
	if _syncing:
		return
	Game.set_setting(key, value)
	_sync_settings()


func _settings_defaults() -> void:
	for key in Game.DEFAULT_SETTINGS:
		Game.settings[key] = Game.DEFAULT_SETTINGS[key]
	Game.apply_settings()
	Game.save_settings()
	_sync_settings()


## Shows the current values on the sliders and boxes.
func _sync_settings() -> void:
	_syncing = true
	for key in _setting_rows:
		var row: Array = _setting_rows[key]
		var value: Variant = Game.settings[key]
		if row[0] is CheckBox:
			(row[0] as CheckBox).button_pressed = bool(value)
		else:
			(row[0] as HSlider).value = float(value)
			var shown: Label = row[1]
			match key:
				"master", "music", "effects":
					shown.text = "%d%%" % int(round(float(value) * 100.0))
				"sensitivity":
					shown.text = "%.2fx" % float(value)
				"fov":
					shown.text = "%d°" % int(value)
	_syncing = false


# ---------------------------------------------------------------- what the buttons do

func _load(path: String) -> void:
	if limited:
		var picked := _on_load
		_back = Callable()
		close()
		if picked.is_valid():
			picked.call(path)
	else:
		close()
		hud.world.load_checkpoint(path)


func _change_look() -> void:
	close()
	hud.open_creator()


func _new_journey() -> void:
	close()
	hud.world.new_journey()


func _quit() -> void:
	hud.world.quit_game()


## A step that cannot be undone asks to be pressed twice: the first press changes the button's
## words to `question`, the second does it.
func _ask_twice(button: Button, question: String, action: Callable) -> void:
	if _armed == button:
		_disarm()
		action.call()
		return
	_disarm()
	_armed = button
	_armed_text = button.text
	button.text = question
	button.add_theme_color_override("font_color", Ui.DANGER)
	button.add_theme_color_override("font_hover_color", Ui.DANGER)


func _disarm() -> void:
	if _armed != null and is_instance_valid(_armed):
		_armed.text = _armed_text
		_armed.remove_theme_color_override("font_color")
		_armed.remove_theme_color_override("font_hover_color")
	_armed = null


# ---------------------------------------------------------------- pieces

func _button(text: String, action: Callable, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func() -> void: Game.play_sound("click"))
	if action.is_valid():
		b.pressed.connect(action)
	return b


func _wrapped(text: String, size: int, color: Color = Ui.PARCHMENT, which: String = "regular") -> Label:
	var l := Ui.label(text, size, color, which)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Story text, with [i] and [b] as the stage texts use them.
func _story(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["normal_font_size", "italics_font_size", "bold_font_size"]:
		r.add_theme_font_size_override(key, 20)
	r.add_theme_constant_override("line_separation", 5)
	return r


static func _hours(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	return "%d h %02d min" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d min" % minutes


## A save's moment in the player's own time: "14 Nov 2026, 22:31".
static func _date(unix: float) -> String:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)
	return "%d %s %d,  %02d:%02d" % [d["day"], MONTHS[int(d["month"]) - 1], d["year"], d["hour"], d["minute"]]
