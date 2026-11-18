extends Node
## Global state and rules, autoloaded as "Game".

signal toast(text: String)
signal look_changed   # the player's appearance was edited
signal gear_changed   # equipped gear changed
signal settings_changed
signal xp_gained(amount: int)
signal leveled(level: int)

const Items := preload("res://data/items.gd")
const Stages := preload("res://data/stages.gd")
const Enemies := preload("res://data/enemies.gd")
const Drops := preload("res://data/drops.gd")
const Forge := preload("res://data/forge.gd")
const Encounters := preload("res://data/encounters.gd")
const Skills := preload("res://data/skills.gd")
## Which way each kind of weapon is used: the same table as HumanScript.STYLE_OF (kept here as
## well, since the Game autoload does not load the figure's script).
const STYLE_OF_KIND := {"dagger": "dagger", "sickle": "sickle", "sword_short": "sword", "sword": "sword", "sword_long": "sword",
	"axe": "axe", "club": "bludgeon", "mace": "bludgeon", "spear": "spear", "spear_long": "spear", "staff": "staff"}
## The short sounds (made by tools/make_effects.py): name -> how many takes of it there are.
const SOUND_TAKES := {"swing": 3, "swing_heavy": 2, "hit_flesh": 3, "hit_blade": 3, "hit_wood": 2, "punch": 2, "hurt": 2,
	"sling_throw": 2, "bow_twang": 2, "thock": 2, "land": 2, "fall": 2, "coin": 2, "find": 1, "anvil": 2, "click": 1, "page": 1}
## The scout's four stats. Each level gives POINTS_PER_LEVEL points to put into them, and
## HP_PER_LEVEL more health. What a point does:
##   str   STR_DAMAGE more damage with hand weapons and fists
##   dex   DEX_DODGE more chance to avoid a blow altogether (at most DODGE_MAX), and DEX_AIM more
##         damage with the sling and the bow
##   int   INT_XP more experience from everything, and prices INT_TRADE better with the trader,
##         buying and selling (at most TRADE_MAX)
##   luck  enemies drop things LUCK_DROPS more often (at most DROPS_MAX more)
const STAT_ORDER := ["str", "dex", "int", "luck"]
const STAT_LABELS := {"str": "Strength", "dex": "Dexterity", "int": "Intelligence", "luck": "Luck"}
const POINTS_PER_LEVEL := 3
const HP_PER_LEVEL := 4.0
const STR_DAMAGE := 0.03
const DEX_DODGE := 0.015
const DODGE_MAX := 0.45
const DEX_AIM := 0.02
const INT_XP := 0.03
const INT_TRADE := 0.01
const TRADE_MAX := 0.25
const LUCK_DROPS := 0.01
const DROPS_MAX := 0.25
## The day. One day in the game lasts DAY_SECONDS of play (six hours), so an hour of the day
## passes in a quarter of an hour.
const DAY_SECONDS := 21600.0
## Thirst. The scout loses THIRST_PER_DAY points of it in a day (the bar is 100, so it runs dry
## about three times a day if nothing is drunk): THIRST_SUN times as fast by day out under the
## sun, THIRST_SHADE times by night or indoors, and THIRST_RUN times faster again while
## sprinting. What is worn against the heat slows it: an item's "thirst" number times
## THIRST_GEAR is the share it takes off, up to THIRST_GEAR_MAX in all.
## Under DRY_BELOW the most stamina the scout can have shrinks, down to DRY_STAMINA_MIN of the
## usual at nothing; at nothing, health goes at PARCHED_DAMAGE a second.
const THIRST_PER_DAY := 300.0
const THIRST_SUN := 1.25
const THIRST_SHADE := 0.75
const THIRST_RUN := 1.5
const THIRST_GEAR := 4.0
const THIRST_GEAR_MAX := 0.6
const DRY_BELOW := 30.0
const DRY_STAMINA_MIN := 0.4
const PARCHED_DAMAGE := 0.4
const RARITY_NAMES := ["", "Rare", "Legendary"]
const RARITY_COLORS := [Color(1, 1, 1), Color(0.45, 0.68, 1.0), Color(1.0, 0.62, 0.15)]
const PLUS_POWER := 0.12     # each +1 adds this much damage
const PLUS_ARMOR := 0.15     # each +1 adds this much defense
const DEFENSE_HALF := 40.0   # with this much defense, half of every blow is stopped
const MAX_BLOCK := 0.75
const FIST_DAMAGE := 5.0
const START_STONES := 10
const STONE_BUNDLE := 10     # the trader sells sling stones by the handful
const STONE_PRICE := 4
const ARROW_BUNDLE := 20
const ARROW_PRICE := 8
const TRADER_GRID := Vector2i(14, 10)
const SETTINGS_PATH := "user://settings.cfg"
const MUSIC := ["res://assets/music/wilderness_1.ogg", "res://assets/music/wilderness_2.ogg"]
const MUSIC_GAP := Vector2(25.0, 50.0)   # quiet seconds between pieces
## Indices into the option tables of human.gd.
const DEFAULT_LOOK := {
	"sex": 0, "skin": 2, "face": 0, "eyes": 1, "brows": 0, "hair": 0, "hair_color": 0,
	"beard": 0, "head": 1, "outfit": 0, "cloth": 1, "sash": 0,
}
const DEFAULT_SETTINGS := {
	"master": 0.8, "music": 0.55, "effects": 0.8, "sensitivity": 1.0, "invert_y": false, "fov": 70.0,
	"fullscreen": false, "vsync": true, "shadows": true,
}

## Every time the scout sleeps a new save is written into `save_dir`; the newest MAX_SAVES are
## kept. `save_path` is where the one save of older versions was, still read if it is there.
const MAX_SAVES := 12
var save_dir := "user://saves"
var save_path := "user://save.json"
var xp := 0                # experience toward the next level
var level := 1
var stat_points := 0       # points not yet put into a stat
var stats := {"str": 0, "dex": 0, "int": 0, "luck": 0}
## The weapon skill trees (data/skills.gd): experience in each weapon family, the points each tree
## has not spent yet, and the skills learned (id -> true).
## The legendary weapons found this journey (id -> true): each exists once.
var found := {}
## Special places (data/places.gd ids): seen at least once, and done (a landmark's passage read
## or a lair or ruin cleared, so it is not guarded or rewarded again).
var places_seen := {}
var places_done := {}
var skill_xp := {}
var skill_points := {}
var perks := {}
var clock := 7.0           # the hour of the day, 0..24
var day := 1               # which day of the journey it is
var played := 0.0          # seconds of this journey spent playing
var intro_seen := -1       # the last stage whose introduction has been shown
var stage_index := 0
## Walking in the land of an earlier stage (its index), or -1 when in the current stage's land.
## Never saved: a journey is always picked up in the camp. `away_from` holds how far the current
## stage had got when the scout walked back, for the return.
var visiting := -1
var away_from := {}
var silver := 0
var bronze := 0
var hp := 100.0
var max_hp := 100.0
var thirst := 100.0
var water := 3
var max_water := 3
var stamina := 100.0
var max_stamina := 100.0
## Things carried in the bag: {id, plus, x, y, count}. x, y is the top-left place it takes.
var bag: Array = []
## What is worn and wielded: slot (Items.EQUIP_SLOTS) -> item, or {} when nothing is there.
## A two-handed weapon is kept in hand_r; a one-piece garment in top.
var equipped := {}
var pack := "pouch"         # what the scout carries things in; sets the size of the bag grid
var chest: Array = []       # what is kept in the chest in the scout's own tent, laid out the same way
## Where the journey stood when it was saved in the tent, for picking it up again:
## {obj_done, hp, thirst, water}. Empty when starting a stage afresh.
var resume := {}
var raids_survived := 0
var look := {}            # the player's appearance
var look_set := false     # false until the player has been through the character creator
var workshop := false   # Bezalel's workshop stands: gear can go to +5
var camp_hp := 100.0
var camp_has_water := true
var ui_open := false
var prompt := ""
var settings := DEFAULT_SETTINGS.duplicate()
var rng := RandomNumberGenerator.new()
var _block_frame := -1
var _mats := {}
var _music: AudioStreamPlayer
var _music_next := 0
var _music_wait := -1.0
var sounds_played := {}     # name -> how often it has been asked for (the tests read this)
var _voices: Array = []     # players for sounds that come from a place in the world
var _flat: Array = []       # players for sounds that do not (menus, things picked up)
var _voice_next := 0
var _last_take := {}
var _save_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_setup_audio()
	load_settings()
	new_game()


func new_game() -> void:
	stage_index = 0
	visiting = -1
	away_from = {}
	silver = 15
	bronze = 0
	max_water = 3
	raids_survived = 0
	workshop = false
	look = DEFAULT_LOOK.duplicate()
	look_set = false
	played = 0.0
	intro_seen = -1
	clock = 7.0
	day = 1
	xp = 0
	level = 1
	stat_points = 0
	stats = {"str": 0, "dex": 0, "int": 0, "luck": 0}
	skill_xp = {}
	skill_points = {}
	perks = {}
	found = {}
	places_seen = {}
	places_done = {}
	bag = []
	pack = "pouch"
	chest = []
	resume = {}
	equipped = {}
	for slot in Items.EQUIP_SLOTS:
		equipped[slot] = {}
	for pair in [["hand_r", "staff"], ["sling", "wool_sling"], ["top", "linen_tunic"], ["bottom", "linen_kilt"], ["belt", "rope_girdle"]]:
		equipped[pair[0]] = new_item(pair[1])
	take_ammo("stones", START_STONES)
	begin_stage()


## The stage whose land the scout is in: the current one, or an earlier one walked back to.
func stage() -> Dictionary:
	return Stages.LIST[land_index()]


func land_index() -> int:
	return visiting if visiting >= 0 else stage_index


func stage_count() -> int:
	return Stages.LIST.size()


## Resets the per-stage values. The scout grows up over the forty years: +10 health per stage.
func begin_stage() -> void:
	var s := stage()
	max_hp = base_hp() + total("hp")
	hp = max_hp
	thirst = float(s.get("start_thirst", 100.0))
	water = mini(max_water, int(s.get("start_water", max_water)))
	stamina = max_stamina
	camp_hp = 100.0
	camp_has_water = bool(s.get("camp_water", true))


func base_hp() -> float:
	return 100.0 + 10.0 * stage_index + HP_PER_LEVEL * (level - 1)


# ---------------------------------------------------------------- the day, thirst and breath

## Moves the day on by `delta` seconds of play.
func advance_clock(delta: float) -> void:
	clock += delta * 24.0 / DAY_SECONDS
	while clock >= 24.0:
		clock -= 24.0
		day += 1


func sun_is_up() -> bool:
	return clock >= 6.0 and clock < 18.0


## "Day 3, 14:20".
func clock_text() -> String:
	var minutes := int(clock * 60.0) % 1440
	return "Day %d, %02d:%02d" % [day, minutes / 60, minutes % 60]


## Sleeping takes the scout to six the next morning.
func sleep_to_morning() -> void:
	if clock >= 6.0:
		day += 1
	clock = 6.0


## Points of thirst lost in a second of play. `heat` is the stage's (1 = an ordinary desert
## day); it tells only by day and out of doors.
func thirst_rate(sprinting: bool, indoors: bool, heat: float = 1.0) -> float:
	var rate := THIRST_PER_DAY / DAY_SECONDS
	if sun_is_up() and not indoors:
		rate *= THIRST_SUN + 0.25 * (heat - 1.0)
	else:
		rate *= THIRST_SHADE
	if sprinting:
		rate *= THIRST_RUN
	return rate * (1.0 - minf(THIRST_GEAR_MAX, total("thirst") * THIRST_GEAR))


## The most stamina the scout can have now: all of it, or less when dry.
func stamina_cap() -> float:
	if thirst >= DRY_BELOW:
		return max_stamina
	return max_stamina * lerpf(DRY_STAMINA_MIN, 1.0, thirst / DRY_BELOW)


# ---------------------------------------------------------------- experience, levels and stats

## Experience needed to go from `at_level` to the next.
func xp_needed(at_level: int) -> int:
	var n := at_level - 1
	return 80 + 45 * n + 6 * n * n


## Adds experience (more of it for an intelligent scout) and levels up as often as it reaches.
## Returns what was actually gained.
func gain_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	var gained := int(round(amount * (1.0 + INT_XP * int(stats["int"]))))
	xp += gained
	xp_gained.emit(gained)
	while xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		stat_points += POINTS_PER_LEVEL
		max_hp += HP_PER_LEVEL
		hp = max_hp
		say("Level %d.  You have %d points to spend: press Esc, The Scout." % [level, stat_points])
		play_sound("find", null, 0.0, 0.8)
		leveled.emit(level)
	return gained


## Puts one unspent point into a stat. False if there is none to spend.
func spend_point(stat_name: String) -> bool:
	if stat_points <= 0 or not stats.has(stat_name):
		return false
	stat_points -= 1
	stats[stat_name] = int(stats[stat_name]) + 1
	return true


# ---------------------------------------------------------------- the weapon skill trees

## The tree a weapon of `kind` trains: its style's, or "bow"; "" for a bare fist or a shield.
func tree_of(kind: String) -> String:
	if kind == "bow":
		return "bow"
	if kind in ["none", "shield", ""]:
		return ""
	return Skills.tree_of_style(str(STYLE_OF_KIND.get(kind, "sword")))


## How many steps a weapon's skill has reached.
func skill_step(tree: String) -> int:
	var have := int(skill_xp.get(tree, 0))
	var n := 0
	while n < Skills.MAX_STEPS and have >= Skills.xp_for_step(n + 1):
		n += 1
	return n


## Use teaches: adds `amount` to a weapon family's skill, and a point to its tree for every step
## it rises. Returns the points gained.
func train(tree: String, amount: int) -> int:
	if tree == "" or not Skills.TREES.has(tree) or amount <= 0:
		return 0
	var before := skill_step(tree)
	skill_xp[tree] = int(skill_xp.get(tree, 0)) + amount
	var gained := skill_step(tree) - before
	if gained > 0:
		skill_points[tree] = int(skill_points.get(tree, 0)) + gained
		say("%s skill rises to %d.  A point to spend in its tree: press Esc, Skills." % [Skills.TREES[tree]["name"], skill_step(tree)])
		play_sound("find", null, -4.0, 1.2)
	return gained


## What felling an enemy of `kind` teaches the weapon that did it.
func train_kill(tree: String, kind: String) -> int:
	return train(tree, Skills.GREAT_KILL if kind in ["champion", "boss", "anak"] else Skills.KILL)


func has_perk(id: String) -> bool:
	return perks.has(id)


## A learned skill's number ("v" in data/skills.gd); 0 if it is not learned.
func perk(id: String) -> float:
	if not perks.has(id):
		return 0.0
	return float((Skills.find(id)["skill"] as Dictionary).get("v", 1.0))


## A learned skill's time ("t"); 0 if it is not learned.
func perk_time(id: String) -> float:
	if not perks.has(id):
		return 0.0
	return float((Skills.find(id)["skill"] as Dictionary).get("t", 0.0))


## Points spent in a tree.
func spent_in(tree: String) -> int:
	var n := 0
	for s in Skills.TREES[tree]["skills"]:
		if perks.has(str(s["id"])):
			n += int(Skills.COST[int(s["tier"])])
	return n


## Why a skill cannot be learned now, or "" if it can.
func why_not(id: String) -> String:
	var f := Skills.find(id)
	if f.is_empty():
		return "Unknown"
	if perks.has(id):
		return "Learned"
	var tree: String = f["tree"]
	var tier := int(f["skill"]["tier"])
	if spent_in(tree) < int(Skills.OPENS[tier]):
		return "Opens at %d points spent here" % int(Skills.OPENS[tier])
	if tier == 4 and level < Skills.CAPSTONE_LEVEL:
		return "Opens at level %d" % Skills.CAPSTONE_LEVEL
	if int(skill_points.get(tree, 0)) < int(Skills.COST[tier]):
		return "Needs %d point%s" % [int(Skills.COST[tier]), "" if int(Skills.COST[tier]) == 1 else "s"]
	return ""


## Learns a skill with the tree's points. False if it cannot be learned now.
func learn(id: String) -> bool:
	if why_not(id) != "":
		return false
	var f := Skills.find(id)
	var tree: String = f["tree"]
	skill_points[tree] = int(skill_points.get(tree, 0)) - int(Skills.COST[int(f["skill"]["tier"])])
	perks[id] = true
	return true


## The chance that a blow aimed at the scout misses altogether.
func dodge_chance() -> float:
	return minf(DODGE_MAX, DEX_DODGE * int(stats["dex"]))


## How much better the trader's prices are for the scout, 0..TRADE_MAX.
func trade_bonus() -> float:
	return minf(TRADE_MAX, INT_TRADE * int(stats["int"]))


## How much more often enemies drop things, 0..DROPS_MAX.
func drop_bonus() -> float:
	return minf(DROPS_MAX, LUCK_DROPS * int(stats["luck"]))


## What a stat is doing for the scout now, in words, for the menu.
func stat_effect(stat_name: String) -> String:
	match stat_name:
		"str":
			return "Blows with hand weapons and fists do %d%% more damage." % int(round(STR_DAMAGE * int(stats["str"]) * 100.0))
		"dex":
			return "You avoid %d%% of the blows aimed at you. Sling and bow do %d%% more damage." % [int(round(dodge_chance() * 100.0)), int(round(DEX_AIM * int(stats["dex"]) * 100.0))]
		"int":
			return "You gain %d%% more experience. The trader's prices are %d%% better, buying and selling." % [int(round(INT_XP * int(stats["int"]) * 100.0)), int(round(trade_bonus() * 100.0))]
		"luck":
			return "Enemies drop things %d%% more often." % int(round(drop_bonus() * 100.0))
	return ""


func say(text: String) -> void:
	toast.emit(text)


# ---------------------------------------------------------------- input

func setup_input() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_E, "drink": KEY_Q, "sheathe": KEY_R, "battle": KEY_F,
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)
	var buttons := {"attack": MOUSE_BUTTON_LEFT, "sling": MOUSE_BUTTON_RIGHT}
	for action in buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var mb := InputEventMouseButton.new()
			mb.button_index = buttons[action]
			InputMap.action_add_event(action, mb)


## Called when a panel closes, so the key or click that closed it does not also act in the world.
func block_input() -> void:
	_block_frame = Engine.get_process_frames() + 1


func input_blocked() -> bool:
	return ui_open or Engine.get_process_frames() <= _block_frame


# ---------------------------------------------------------------- items

func new_item(id: String, plus: int = 0, count: int = 1) -> Dictionary:
	return {"id": id, "plus": plus, "x": 0, "y": 0, "count": count}


func item_def(inst: Dictionary) -> Dictionary:
	return Items.ITEMS[inst["id"]]


func item_name(inst: Dictionary) -> String:
	var n: String = item_def(inst)["name"]
	if item_def(inst).has("stack"):
		return "%s (%d)" % [n, int(inst.get("count", 1))]
	var plus: int = int(inst.get("plus", 0))
	return n if plus == 0 else "%s +%d" % [n, plus]


## One of the item's numbers (Items: damage, defense, hp, thirst, stamina), with its strengthening.
func stat(inst: Dictionary, key: String) -> float:
	if inst.is_empty():
		return 0.0
	var v := float(item_def(inst).get(key, 0.0))
	var plus: int = int(inst.get("plus", 0))
	if key == "damage":
		v *= 1.0 + PLUS_POWER * plus
	elif key == "defense":
		v *= 1.0 + PLUS_ARMOR * plus
	return v


func weight(inst: Dictionary) -> float:
	if inst.is_empty():
		return 0.0
	return float(item_def(inst).get("weight", 0.0)) * int(inst.get("count", 1))


## A short line of what the item does, for menus.
func item_desc(inst: Dictionary) -> String:
	var parts: Array = []
	for key in Items.STAT_NAMES:
		var v := stat(inst, key)
		if v != 0.0:
			parts.append("%s %s" % [str(Items.STAT_NAMES[key]).to_lower(), stat_text(key, v)])
	parts.append("%.1f kg" % weight(inst))
	return ", ".join(parts)


func stat_text(key: String, v: float) -> String:
	match key:
		"thirst":
			return "%d%% slower" % int(round(v * THIRST_GEAR * 100.0))
		"stamina":
			return "%+.2f/s" % v if absf(v) < 0.1 else "%+.1f/s" % v
		"hp":
			return "%+d" % int(round(v))
	return "%d" % int(round(v))


func item_size(inst: Dictionary) -> Vector2i:
	var s: Array = item_def(inst)["size"]
	return Vector2i(int(s[0]), int(s[1]))


func is_two_handed(inst: Dictionary) -> bool:
	return not inst.is_empty() and int(item_def(inst).get("hands", 1)) == 2


func kind(inst: Dictionary) -> String:
	return "none" if inst.is_empty() else str(item_def(inst).get("kind", "none"))


## Equipped totals of one stat.
func total(key: String) -> float:
	var sum := 0.0
	for slot in equipped:
		sum += stat(equipped[slot], key)
	return sum


func equipped_weight() -> float:
	var sum := 0.0
	for slot in equipped:
		sum += weight(equipped[slot])
	return sum


func bag_weight() -> float:
	var sum := 0.0
	for it in bag:
		sum += weight(it)
	return sum


## The weapon a hand holds, or {} for an empty hand or a shield.
func weapon_in(hand: String) -> Dictionary:
	var inst: Dictionary = equipped.get(hand, {})
	if inst.is_empty() or kind(inst) == "shield" or kind(inst) == "bow":
		return {}
	return inst


## The bow held in both hands, or {}.
func bow() -> Dictionary:
	var inst: Dictionary = equipped.get("hand_r", {})
	return inst if kind(inst) == "bow" else {}


## Damage of a blow with the weapon in `hand` ("" = whichever hand holds one, right first).
func melee_power(hand: String = "") -> float:
	if hand == "":
		hand = "hand_r" if not weapon_in("hand_r").is_empty() else "hand_l"
	var w := weapon_in(hand)
	return (FIST_DAMAGE if w.is_empty() else stat(w, "damage")) * (1.0 + STR_DAMAGE * int(stats["str"]))


## How fast a weapon swings: a 1.5 kg weapon at normal speed, lighter ones up to a fifth quicker,
## heavier ones up to a fifth slower (most of a blow is the body moving, whatever the weapon). A
## bare fist is quicker still.
func swing_speed(inst: Dictionary) -> float:
	if inst.is_empty():
		return 1.5
	return clampf(pow(1.5 / maxf(0.1, float(item_def(inst).get("weight", 1.5))), 0.35), 0.8, 1.2)


func sling_power() -> float:
	return stat(equipped.get("sling", {}), "damage") * (1.0 + DEX_AIM * int(stats["dex"]))


func bow_power() -> float:
	return stat(bow(), "damage") * (1.0 + DEX_AIM * int(stats["dex"]))


## Defense from everything worn and held.
func defense() -> float:
	return total("defense")


## The share of each blow that defense stops.
func armor_block() -> float:
	var d := defense()
	return minf(MAX_BLOCK, d / (d + DEFENSE_HALF))


# ---------------------------------------------------------------- grids: the bag, the chest, the trader
# A grid is a list of items, each covering a rectangle of places starting at its x, y.

func bag_grid() -> Vector2i:
	var g: Array = Items.PACKS[pack]["grid"]
	return Vector2i(int(g[0]), int(g[1]))


func chest_grid() -> Vector2i:
	return Vector2i(int(Items.CHEST_GRID[0]), int(Items.CHEST_GRID[1]))


func rect_of(inst: Dictionary) -> Rect2i:
	return Rect2i(Vector2i(int(inst.get("x", 0)), int(inst.get("y", 0))), item_size(inst))


func index_in(list: Array, inst: Dictionary) -> int:
	for i in list.size():
		if is_same(list[i], inst):
			return i
	return -1


func remove_from(list: Array, inst: Dictionary) -> bool:
	var i := index_in(list, inst)
	if i < 0:
		return false
	list.remove_at(i)
	return true


## The item covering `cell`, or {}.
func item_at(list: Array, cell: Vector2i) -> Dictionary:
	for it in list:
		if rect_of(it).has_point(cell):
			return it
	return {}


## The items overlapping `rect`, except `ignore`.
func items_in(list: Array, rect: Rect2i, ignore: Dictionary = {}) -> Array:
	var out: Array = []
	for it in list:
		if not is_same(it, ignore) and rect_of(it).intersects(rect):
			out.append(it)
	return out


func fits(list: Array, grid: Vector2i, size: Vector2i, at: Vector2i, ignore: Dictionary = {}) -> bool:
	if at.x < 0 or at.y < 0 or at.x + size.x > grid.x or at.y + size.y > grid.y:
		return false
	return items_in(list, Rect2i(at, size), ignore).is_empty()


## The first free place for something of `size`, row by row, or (-1, -1).
func free_spot(list: Array, grid: Vector2i, size: Vector2i) -> Vector2i:
	for y in grid.y - size.y + 1:
		for x in grid.x - size.x + 1:
			if fits(list, grid, size, Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Puts `inst` somewhere in a grid: ammo first tops up stacks of its kind, then takes free places.
## Returns how much of it did not fit (0 when all of it went in).
func place(list: Array, grid: Vector2i, inst: Dictionary) -> int:
	var d := item_def(inst)
	if d.has("stack"):
		var left: int = int(inst.get("count", 1))
		var cap: int = int(d["stack"])
		for it in list:
			if left <= 0:
				break
			if it["id"] == inst["id"] and int(it["count"]) < cap:
				var n := mini(left, cap - int(it["count"]))
				it["count"] = int(it["count"]) + n
				left -= n
		while left > 0:
			var spot := free_spot(list, grid, item_size(inst))
			if spot.x < 0:
				break
			var n := mini(left, cap)
			list.append({"id": inst["id"], "plus": 0, "x": spot.x, "y": spot.y, "count": n})
			left -= n
		return left
	var at := free_spot(list, grid, item_size(inst))
	if at.x < 0:
		return 1
	inst["x"] = at.x
	inst["y"] = at.y
	list.append(inst)
	return 0


## Whether one of `id` would fit in the bag now.
func can_take(id: String) -> bool:
	var probe := new_item(id)
	var d: Dictionary = Items.ITEMS[id]
	if d.has("stack"):
		for it in bag:
			if it["id"] == id and int(it["count"]) < int(d["stack"]):
				return true
	return free_spot(bag, bag_grid(), item_size(probe)).x >= 0


## Puts a new item in the bag. Returns it, or {} if there was no room.
func add_item(id: String, plus: int = 0) -> Dictionary:
	var inst := new_item(id, plus)
	if place(bag, bag_grid(), inst) > 0:
		return {}
	return inst


## How many places of the bag are taken, and how many it has.
func used_places() -> int:
	var n := 0
	for it in bag:
		var s := item_size(it)
		n += s.x * s.y
	return n


func places() -> int:
	var g := bag_grid()
	return g.x * g.y


func ammo_count(id: String, list: Variant = null) -> int:
	var from: Array = bag if list == null else list
	var n := 0
	for it in from:
		if it["id"] == id:
			n += int(it["count"])
	return n


func stones() -> int:
	return ammo_count("stones")


func arrows() -> int:
	return ammo_count("arrows")


## Picks up as many of `count` as there is room for. Returns how many were taken.
func take_ammo(id: String, count: int) -> int:
	if count <= 0:
		return 0
	return count - place(bag, bag_grid(), new_item(id, 0, count))


func take_stones(count: int) -> int:
	return take_ammo("stones", count)


## Uses up one stone or arrow from the bag, from the smallest stack. False if there is none.
func use_ammo(id: String) -> bool:
	var best: Dictionary = {}
	for it in bag:
		if it["id"] == id and (best.is_empty() or int(it["count"]) < int(best["count"])):
			best = it
	if best.is_empty():
		return false
	best["count"] = int(best["count"]) - 1
	if int(best["count"]) <= 0:
		remove_from(bag, best)
	return true


## Takes up to `count` of an ammo kind out of a list (for moving it elsewhere). Returns how many.
func remove_ammo(list: Array, id: String, count: int) -> int:
	var got := 0
	for it in list.duplicate():
		if got >= count:
			break
		if it["id"] != id:
			continue
		var n := mini(count - got, int(it["count"]))
		it["count"] = int(it["count"]) - n
		got += n
		if int(it["count"]) <= 0:
			remove_from(list, it)
	return got


## Moves a whole item from the bag into the chest, anywhere it fits. False if the chest is full.
func store(inst: Dictionary) -> bool:
	return _move(inst, bag, chest, chest_grid())


## And back from the chest into the bag.
func unstore(inst: Dictionary) -> bool:
	return _move(inst, chest, bag, bag_grid())


func _move(inst: Dictionary, from: Array, to: Array, grid: Vector2i) -> bool:
	if index_in(from, inst) < 0:
		return false
	remove_from(from, inst)
	var had := int(inst.get("count", 1))
	var left := place(to, grid, inst)
	if left > 0:
		inst["count"] = left
		from.append(inst)
	return left < had


## The next bag the trader sells, or "" if the scout has the biggest.
func next_pack() -> String:
	var i: int = Items.PACK_ORDER.find(pack)
	return Items.PACK_ORDER[i + 1] if i + 1 < Items.PACK_ORDER.size() else ""


## A bigger bag: everything carried moves into it, in the same places.
func try_buy_pack(id: String) -> bool:
	var price: int = int(Items.PACKS[id]["price"])
	if silver < price or Items.PACK_ORDER.find(id) <= Items.PACK_ORDER.find(pack):
		return false
	silver -= price
	pack = id
	return true


func try_buy_ammo(id: String) -> bool:
	var price := STONE_PRICE if id == "stones" else ARROW_PRICE
	var count := STONE_BUNDLE if id == "stones" else ARROW_BUNDLE
	if silver < price or not can_take(id):
		return false
	silver -= price
	take_ammo(id, count)
	return true


func try_buy_stones() -> bool:
	return try_buy_ammo("stones")


# ---------------------------------------------------------------- equipment

## Swords and spears are fought with alone, in the right hand: never in the left, and while one is
## in the right the left holds no other weapon (a shield or a bow, or nothing).
const LONE_WEAPONS := ["sword", "sword_short", "sword_long", "spear", "spear_long"]


## Whether `inst` is a weapon for the left hand to fight with (not a shield or a bow).
func _second_weapon(inst: Dictionary) -> bool:
	return not inst.is_empty() and not kind(inst) in ["none", "shield", "bow"]


## Whether `inst` can be worn in `slot` at all.
func slot_accepts(slot: String, inst: Dictionary) -> bool:
	var s: String = item_def(inst)["slot"]
	if s == "loot":
		return false      # spoils are only carried and sold
	match slot:
		"hand_r":
			return s == "hand"
		"hand_l":
			return s == "hand" and not LONE_WEAPONS.has(kind(inst))
		"top":
			return s == "top" or s == "body"
		_:
			return s == slot


## Where an item goes when it is equipped without saying where: weapons to the right hand,
## shields to the left, a dress or robe in place of top and bottom.
func default_slot(inst: Dictionary) -> String:
	var s: String = item_def(inst)["slot"]
	match s:
		"hand":
			if kind(inst) == "shield" and not is_two_handed(equipped["hand_r"]):
				return "hand_l"
			return "hand_r"
		"body":
			return "top"
	return s


## Puts `inst` on in `slot`. Returns what had to come off to make room for it (the caller puts
## those somewhere), or null if it cannot go there.
func wear(inst: Dictionary, slot: String) -> Variant:
	if slot == "" or not slot_accepts(slot, inst):
		return null
	if is_two_handed(inst):
		slot = "hand_r"
	var off: Array = []
	for s in _clashes(inst, slot):
		if not equipped[s].is_empty():
			off.append(equipped[s])
			equipped[s] = {}
	equipped[slot] = inst
	_gear_changed()
	return off


## The slots that must be emptied for `inst` to go in `slot`.
func _clashes(inst: Dictionary, slot: String) -> Array:
	var out: Array = [slot]
	if is_two_handed(inst):
		out.append("hand_l")
	if slot == "hand_l" and is_two_handed(equipped["hand_r"]):
		out.append("hand_r")
	if slot == "hand_r" and LONE_WEAPONS.has(kind(inst)) and _second_weapon(equipped["hand_l"]):
		out.append("hand_l")
	if slot == "hand_l" and _second_weapon(inst) and LONE_WEAPONS.has(kind(equipped["hand_r"])):
		out.append("hand_r")
	if item_def(inst)["slot"] == "body":
		out.append("bottom")
	if slot == "bottom" and not equipped["top"].is_empty() and item_def(equipped["top"])["slot"] == "body":
		out.append("top")
	return out


## Takes off what is in `slot` and returns it ({} if nothing was there).
func take_off(slot: String) -> Dictionary:
	var inst: Dictionary = equipped.get(slot, {})
	equipped[slot] = {}
	if not inst.is_empty():
		_gear_changed()
	return inst


## Equips an item from the bag. What comes off goes into the bag; if it will not fit, nothing
## changes and false is returned.
func equip(inst: Dictionary, slot: String = "") -> bool:
	if index_in(bag, inst) < 0:
		return false
	if slot == "":
		slot = default_slot(inst)
	if not slot_accepts(slot, inst):
		return false
	var keep_bag := bag.duplicate()
	var keep_eq := equipped.duplicate()
	remove_from(bag, inst)
	var off: Variant = wear(inst, slot)
	for it in off:
		if place(bag, bag_grid(), it) > 0:
			bag = keep_bag
			equipped = keep_eq
			_gear_changed()
			return false
	return true


## Takes off what is in `slot` into the bag. False if the bag has no room for it.
func unequip(slot: String) -> bool:
	var inst: Dictionary = equipped.get(slot, {})
	if inst.is_empty() or free_spot(bag, bag_grid(), item_size(inst)).x < 0:
		return false
	place(bag, bag_grid(), take_off(slot))
	return true


func _gear_changed() -> void:
	max_hp = base_hp() + total("hp")
	hp = minf(hp, max_hp)
	gear_changed.emit()


## The clothing pieces the scout's equipment shows: [[piece, color], ...] (see Items "wear").
func worn_pieces() -> Array:
	var out: Array = []
	for slot in ["top", "bottom", "belt", "neck"]:
		var inst: Dictionary = equipped.get(slot, {})
		if not inst.is_empty():
			out.append_array(item_def(inst).get("wear", []))
	return out


func head_pieces() -> Array:
	var inst: Dictionary = equipped.get("head", {})
	return [] if inst.is_empty() else item_def(inst).get("wear", [])


# ---------------------------------------------------------------- the trader and the craftsman

## Gear can be strengthened to +2 at first, and to +5 once Bezalel's workshop stands (stage 3).
func max_plus() -> int:
	return 5 if workshop or stage_index >= 3 else 2


func can_strengthen(inst: Dictionary) -> bool:
	return not inst.is_empty() and (stat(inst, "damage") > 0.0 or stat(inst, "defense") > 0.0)


func upgrade_cost(inst: Dictionary) -> Dictionary:
	var tier: int = int(item_def(inst)["tier"])
	var plus: int = int(inst["plus"])
	return {"silver": 15 * tier * (plus + 1), "bronze": plus + 1}


func can_upgrade(inst: Dictionary) -> bool:
	if not can_strengthen(inst) or int(inst["plus"]) >= max_plus():
		return false
	var c := upgrade_cost(inst)
	return silver >= int(c["silver"]) and bronze >= int(c["bronze"])


func try_upgrade(inst: Dictionary) -> bool:
	if not can_upgrade(inst):
		return false
	var c := upgrade_cost(inst)
	silver -= int(c["silver"])
	bronze -= int(c["bronze"])
	inst["plus"] = int(inst["plus"]) + 1
	_gear_changed()
	return true


## What the smith can forge at this stage: the lines of data/forge.gd within `tier_cap`.
func forge_list(tier_cap: int) -> Array:
	var out: Array = []
	for r in Forge.RECIPES:
		if Items.ITEMS.has(r["item"]) and int(Items.ITEMS[r["item"]]["tier"]) <= tier_cap:
			out.append(r)
	return out


## The first item in the bag with this id ({} if there is none).
func bag_item(id: String) -> Dictionary:
	for it in bag:
		if it["id"] == id:
			return it
	return {}


func can_forge(recipe: Dictionary) -> bool:
	if silver < int(recipe["silver"]) or bronze < int(recipe["bronze"]):
		return false
	if recipe.has("needs"):
		# What he works from leaves the bag, which makes the room for what comes back.
		return not bag_item(str(recipe["needs"])).is_empty()
	return can_take(str(recipe["item"]))


## The smith makes the thing: the silver, the bronze and whatever he works from are spent, and
## the new piece goes into the bag. False if something is lacking or the bag is full.
func try_forge(recipe: Dictionary) -> bool:
	if not can_forge(recipe):
		return false
	if recipe.has("needs"):
		remove_from(bag, bag_item(str(recipe["needs"])))
		if not can_take(str(recipe["item"])):
			add_item(str(recipe["needs"]))
			return false
	silver -= int(recipe["silver"])
	bronze -= int(recipe["bronze"])
	add_item(str(recipe["item"]))
	return true


## What the trader has at this stage: the newest gear and the gear just before it.
func shop_stock(tier_cap: int) -> Array:
	var out: Array = []
	for id in Items.ITEMS:
		var d: Dictionary = Items.ITEMS[id]
		var t: int = int(d["tier"])
		if int(d["price"]) > 0 and t <= tier_cap and t >= tier_cap - 1:
			out.append(id)
	return out


## The trader's goods laid out in a grid, biggest first so they pack well.
func shop_grid(tier_cap: int) -> Array:
	var ids := shop_stock(tier_cap)
	ids.sort_custom(func(a, b) -> bool:
		var sa := item_size(new_item(a))
		var sb := item_size(new_item(b))
		return sa.x * sa.y > sb.x * sb.y)
	var out: Array = []
	for id in ids:
		place(out, TRADER_GRID, new_item(id))
	return out


## What the trader asks of this scout: the listed price, less for one who bargains well. Rare
## and legendary finds have no listed price: a caravan asks Encounters.price_of for them.
func price(inst: Dictionary) -> int:
	var d := item_def(inst)
	var base: int = int(d["price"])
	if base <= 0 and rarity(inst) > 0:
		base = Encounters.price_of(int(d["tier"]), rarity(inst))
	return int(ceil(base * (1.0 - trade_bonus())))


## Buys something into the bag. False if it costs too much or will not fit.
func try_buy(id: String) -> bool:
	var cost: int = price(new_item(id))
	if silver < cost or not can_take(id):
		return false
	silver -= cost
	add_item(id)
	return true


func sell_value(inst: Dictionary) -> int:
	var d := item_def(inst)
	if d.has("stack"):
		return 0
	if d.has("worth"):
		return int(round(int(d["worth"]) * (1.0 + trade_bonus())))
	var base: int = int(d["price"])
	if base <= 0:
		base = int(d["tier"]) * 60
	return int(base * 0.35 * (1.0 + 0.25 * int(inst["plus"])) * (1.0 + trade_bonus()))


func sell(inst: Dictionary) -> bool:
	if index_in(bag, inst) < 0 or sell_value(inst) <= 0:
		return false
	silver += sell_value(inst)
	remove_from(bag, inst)
	return true


func waterskin_price() -> int:
	return 40 + 35 * (max_water - 3)


func try_buy_waterskin() -> bool:
	var cost := waterskin_price()
	if max_water >= 6 or silver < cost:
		return false
	silver -= cost
	max_water += 1
	water += 1
	return true


## A legendary weapon is in the scout's hands: it will not be found again this journey.
func record_find(id: String) -> void:
	if Items.ITEMS.has(id) and int(Items.ITEMS[id].get("rarity", 0)) == 2:
		found[id] = true


## True if this legendary has already been found this journey.
func was_found(id: String) -> bool:
	return found.has(id)


## 0 common, 1 rare, 2 legendary (Items "rarity").
func rarity(inst: Dictionary) -> int:
	return int(item_def(inst).get("rarity", 0))


## What an enemy of `kind` leaves when it falls, rolled from data/drops.gd: a list of
## [pickup kind, payload] ("silver"/"bronze" with a number, "item" with an item id).
func roll_drops(kind: String, tier_cap: int, mult: float) -> Array:
	var out: Array = []
	for line in Drops.DROPS.get(kind, []):
		# A lucky scout finds a little more.
		if rng.randf() >= float(line.get("chance", 1.0)) * (1.0 + drop_bonus()):
			continue
		if line.has("silver"):
			var n := int(rng.randi_range(int(line["silver"][0]), int(line["silver"][1])) * (0.6 + 0.4 * mult))
			if n > 0:
				out.append(["silver", n])
		if line.has("bronze"):
			out.append(["bronze", rng.randi_range(int(line["bronze"][0]), int(line["bronze"][1]))])
		if line.has("item"):
			out.append(["item", str(line["item"])])
		if bool(line.get("gear", false)):
			var id := roll_drop(tier_cap)
			if id != "":
				out.append(["item", id])
		if line.has("table"):
			var found := roll_table(str(line["table"]), tier_cap)
			if found != "":
				out.append(["item", found])
	return out


## One thing from a Drops table, by weight, among those of at most one tier above `tier_cap`.
func roll_table(table: String, tier_cap: int) -> String:
	var pool: Array = []
	var sum := 0.0
	for entry in Drops.TABLES.get(table, []):
		if int(Items.ITEMS[entry[0]]["tier"]) <= tier_cap + 1:
			pool.append(entry)
			sum += float(entry[1])
	var at := rng.randf() * sum
	for entry in pool:
		at -= float(entry[1])
		if at <= 0.0:
			return str(entry[0])
	return ""


## Picks a random piece of gear a raider might carry at this tier. "" if nothing fits.
func roll_drop(tier_cap: int) -> String:
	var pool := shop_stock(tier_cap)
	if pool.is_empty():
		return ""
	return pool[rng.randi() % pool.size()]


# ---------------------------------------------------------------- player values

func drink() -> bool:
	if water <= 0 or thirst > 92.0:
		return false
	water -= 1
	thirst = minf(100.0, thirst + 45.0)
	return true


func refill_water() -> void:
	water = max_water
	thirst = 100.0


## A cup of water drunk on the spot: quenches thirst without filling the waterskin.
func sip(amount: float) -> void:
	thirst = minf(100.0, thirst + amount)


## Applies defense and returns the damage actually taken.
func hurt_player(amount: float) -> float:
	var taken := amount * (1.0 - armor_block())
	hp = maxf(0.0, hp - taken)
	return taken


# ---------------------------------------------------------------- save

func snapshot() -> Dictionary:
	return {
		"stage_index": stage_index, "silver": silver, "bronze": bronze,
		"max_water": max_water, "raids_survived": raids_survived, "workshop": workshop,
		"bag": bag.duplicate(true), "equipped": equipped.duplicate(true),
		"look": look.duplicate(), "look_set": look_set,
		"pack": pack, "chest": chest.duplicate(true),
		"played": played, "intro_seen": intro_seen,
		"xp": xp, "level": level, "stat_points": stat_points, "stats": stats.duplicate(),
		"skill_xp": skill_xp.duplicate(), "skill_points": skill_points.duplicate(), "perks": perks.keys(), "found": found.keys(),
		"places_seen": places_seen.keys(), "places_done": places_done.keys(),
		"clock": clock, "day": day,
	}


func restore(s: Dictionary) -> void:
	stage_index = clampi(int(s.get("stage_index", 0)), 0, stage_count() - 1)
	visiting = -1
	away_from = {}
	silver = int(s.get("silver", 0))
	bronze = int(s.get("bronze", 0))
	max_water = int(s.get("max_water", 3))
	raids_survived = int(s.get("raids_survived", 0))
	workshop = bool(s.get("workshop", false))
	look = DEFAULT_LOOK.duplicate()
	var saved_look: Dictionary = s.get("look", {})
	for key in look:
		if saved_look.has(key):
			look[key] = int(saved_look[key])
	look_set = bool(s.get("look_set", false))
	played = float(s.get("played", 0.0))
	clock = clampf(float(s.get("clock", 7.0)), 0.0, 23.999)
	day = maxi(1, int(s.get("day", 1)))
	xp = int(s.get("xp", 0))
	level = maxi(1, int(s.get("level", 1)))
	stat_points = int(s.get("stat_points", 0))
	stats = {"str": 0, "dex": 0, "int": 0, "luck": 0}
	var saved_stats: Dictionary = s.get("stats", {})
	for key in stats:
		stats[key] = int(saved_stats.get(key, 0))
	skill_xp = {}
	skill_points = {}
	perks = {}
	var saved_xp: Dictionary = s.get("skill_xp", {})
	var saved_points: Dictionary = s.get("skill_points", {})
	for tree in Skills.ORDER:
		if saved_xp.has(tree):
			skill_xp[tree] = int(saved_xp[tree])
		if saved_points.has(tree):
			skill_points[tree] = int(saved_points[tree])
	for id in s.get("perks", []):
		if not Skills.find(str(id)).is_empty():
			perks[str(id)] = true
	found = {}
	for id in s.get("found", []):
		found[str(id)] = true
	places_seen = {}
	places_done = {}
	for id in s.get("places_seen", []):
		places_seen[str(id)] = true
	for id in s.get("places_done", []):
		places_done[str(id)] = true
	# A save from before introductions were remembered has seen its own stage's.
	intro_seen = int(s.get("intro_seen", stage_index))
	pack = str(s.get("pack", "pouch"))
	if not Items.PACKS.has(pack):
		pack = "pouch"
	resume = s.get("resume", {}).duplicate()
	var eq: Dictionary = s.get("equipped", {})
	equipped = {}
	for slot in Items.EQUIP_SLOTS:
		equipped[slot] = {}
		var it: Variant = eq.get(slot, {})
		if typeof(it) == TYPE_DICTIONARY and Items.ITEMS.has(str(it.get("id", ""))):
			equipped[slot] = _item_from(it)
	var spill: Array = []
	if eq.has("melee"):
		# A save from before the bag had places: melee, sling and armor slots, and counted stones.
		equipped = {}
		for slot in Items.EQUIP_SLOTS:
			equipped[slot] = {}
		for pair in [["melee", "hand_r"], ["sling", "sling"], ["armor", "top"]]:
			var old: Variant = eq.get(pair[0], {})
			if typeof(old) == TYPE_DICTIONARY and Items.ITEMS.has(str(old.get("id", ""))):
				equipped[pair[1]] = _item_from(old)
		if equipped["top"].is_empty() or equipped["top"]["id"] == "cloak":
			equipped["top"] = new_item("linen_tunic")
		equipped["bottom"] = new_item("linen_kilt")
		equipped["belt"] = new_item("rope_girdle")
	var lone_r := LONE_WEAPONS.has(kind(equipped["hand_r"]))
	if (is_two_handed(equipped["hand_r"]) and not equipped["hand_l"].is_empty()) 			or LONE_WEAPONS.has(kind(equipped["hand_l"])) or (lone_r and _second_weapon(equipped["hand_l"])):
		# Saved before this weapon took both hands, or before swords and spears were held alone:
		# what the left hand held goes into the bag.
		spill.append(equipped["hand_l"])
		equipped["hand_l"] = {}
	bag = _grid_list(s.get("bag", []), bag_grid(), spill)
	chest = _grid_list(s.get("chest", []), chest_grid(), [])
	for it in spill.duplicate():
		if place(bag, bag_grid(), it) == 0:
			spill.erase(it)
	if eq.has("melee"):
		# Stones were counted, not laid out; saves from before stones existed get the starting ten.
		take_ammo("stones", int(s.get("stones", START_STONES)))
		place(chest, chest_grid(), new_item("stones", 0, int(s.get("chest_stones", 0))))
	for it in spill:
		place(chest, chest_grid(), it)
	begin_stage()
	look_changed.emit()
	gear_changed.emit()


func _item_from(it: Dictionary) -> Dictionary:
	return {"id": str(it["id"]), "plus": int(it.get("plus", 0)), "x": int(it.get("x", -1)), "y": int(it.get("y", -1)), "count": int(it.get("count", 1))}


## Lays saved items out in a grid. Items from an old save have no place yet and are put wherever
## they fit; what does not fit at all goes into `spill`.
func _grid_list(list: Array, grid: Vector2i, spill: Array) -> Array:
	var out: Array = []
	var later: Array = []
	for raw in list:
		if typeof(raw) != TYPE_DICTIONARY or not Items.ITEMS.has(str(raw.get("id", ""))):
			continue
		var it := _item_from(raw)
		if fits(out, grid, item_size(it), Vector2i(int(it["x"]), int(it["y"]))):
			out.append(it)
		else:
			later.append(it)
	for it in later:
		if place(out, grid, it) > 0:
			spill.append(it)
	return out


func has_save() -> bool:
	return not list_saves().is_empty()


## Every save there is, newest first, for the menus: {path, saved_at (unix seconds), stage_index,
## obj_done, silver, played}. A save of an older version (one file, no date inside) is listed
## with the time the file was written.
func list_saves() -> Array:
	var paths: Array = []
	var dir := DirAccess.open(save_dir)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".json"):
				paths.append(save_dir.path_join(file))
	if FileAccess.file_exists(save_path):
		paths.append(save_path)
	var out: Array = []
	for path in paths:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		out.append({
			"path": path,
			"saved_at": float(data.get("saved_at", FileAccess.get_modified_time(path))),
			"stage_index": clampi(int(data.get("stage_index", 0)), 0, stage_count() - 1),
			"obj_done": int((data.get("resume", {}) as Dictionary).get("obj_done", 0)),
			"silver": int(data.get("silver", 0)),
			"played": float(data.get("played", 0.0)),
		})
	out.sort_custom(func(a, b) -> bool:
		if a["saved_at"] != b["saved_at"]:
			return a["saved_at"] > b["saved_at"]
		return str(a["path"]) > str(b["path"]))
	return out


## What the newest save holds, without loading it ({} if there is none), for the title screen.
func peek_save() -> Dictionary:
	var saves := list_saves()
	if saves.is_empty():
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(saves[0]["path"]))
	return data if typeof(data) == TYPE_DICTIONARY else {}


## Writes a new save. The game is saved only by sleeping in the scout's own tent; `progress`
## is where the stage stood then ({obj_done, hp, thirst, water}), so loading picks it up there.
## Older saves stay, so an earlier morning can be gone back to; beyond MAX_SAVES the oldest go.
func save_game(progress: Dictionary = {}) -> void:
	var data := snapshot()
	data["resume"] = progress
	data["saved_at"] = Time.get_unix_time_from_system()
	DirAccess.make_dir_recursive_absolute(save_dir)
	_save_count += 1
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var f := FileAccess.open(save_dir.path_join("save_%s_%03d.json" % [stamp, _save_count % 1000]), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
	var saves := list_saves()
	for i in range(MAX_SAVES, saves.size()):
		DirAccess.remove_absolute(str(saves[i]["path"]))


## Loads the save at `path`, or the newest one if no path is given.
func load_game(path: String = "") -> bool:
	if path == "":
		var saves := list_saves()
		if saves.is_empty():
			return false
		path = saves[0]["path"]
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	restore(data)
	return true


## Removes every save (the tests start from none).
func clear_saves() -> void:
	for s in list_saves():
		DirAccess.remove_absolute(str(s["path"]))


# ---------------------------------------------------------------- settings and music

func load_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for key in settings:
			settings[key] = cfg.get_value("settings", key, settings[key])
	apply_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.save(SETTINGS_PATH)


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	save_settings()


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(settings["master"]))))
	for bus in [["Music", "music"], ["Effects", "effects"]]:
		var i := AudioServer.get_bus_index(bus[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(0.0001, float(settings[bus[1]]))))
			AudioServer.set_bus_mute(i, float(settings[bus[1]]) <= 0.001)
	AudioServer.set_bus_mute(0, float(settings["master"]) <= 0.001)
	if DisplayServer.get_name() != "headless":
		var full: bool = bool(settings["fullscreen"])
		var mode := DisplayServer.window_get_mode()
		if full and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not full and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(settings["vsync"]) else DisplayServer.VSYNC_DISABLED)
	settings_changed.emit()


## Music and sound effects have buses of their own, so their volumes can be set apart.
func _setup_audio() -> void:
	for bus in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_music.finished.connect(func() -> void: _music_wait = rng.randf_range(MUSIC_GAP.x, MUSIC_GAP.y))
	_music_next = rng.randi() % MUSIC.size()
	for i in 10:
		var v := AudioStreamPlayer3D.new()
		v.bus = "Effects"
		v.unit_size = 6.0
		v.max_distance = 70.0
		add_child(v)
		_voices.append(v)
	for i in 4:
		var v := AudioStreamPlayer.new()
		v.bus = "Effects"
		v.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(v)
		_flat.append(v)
	# No music for headless runs (the self-test).
	_music_wait = -1.0 if DisplayServer.get_name() == "headless" else 2.0


## Plays one of the short sounds (SOUND_TAKES): at `at` in the world if a place is given, or
## plainly, as the menus' sounds are. Each time a different take is picked and its pitch is
## shifted a little, so the same sound twice does not sound the same.
func play_sound(sound: String, at: Variant = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sounds_played[sound] = int(sounds_played.get(sound, 0)) + 1
	if not SOUND_TAKES.has(sound) or DisplayServer.get_name() == "headless":
		return
	var takes: int = SOUND_TAKES[sound]
	var take := 1 + randi() % takes
	if takes > 1 and take == int(_last_take.get(sound, 0)):
		take = take % takes + 1
	_last_take[sound] = take
	var path := "res://assets/sounds/%s_%d.wav" % [sound, take]
	if not ResourceLoader.exists(path):
		return
	_voice_next += 1
	if at is Vector3:
		var v: AudioStreamPlayer3D = _voices[_voice_next % _voices.size()]
		v.stream = load(path)
		v.pitch_scale = pitch * randf_range(0.93, 1.07)
		v.volume_db = volume_db
		v.global_position = at
		v.play()
	else:
		var v: AudioStreamPlayer = _flat[_voice_next % _flat.size()]
		v.stream = load(path)
		v.pitch_scale = pitch * randf_range(0.97, 1.03)
		v.volume_db = volume_db
		v.play()


## Plays the pieces in turn, with a quiet stretch between them.
func _process(delta: float) -> void:
	played += delta      # this node stops while the game is paused, so menus do not count
	if _music_wait < 0.0:
		return
	_music_wait -= delta
	if _music_wait > 0.0:
		return
	_music_wait = -1.0
	var path: String = MUSIC[_music_next % MUSIC.size()]
	_music_next += 1
	if ResourceLoader.exists(path):
		_music.stream = load(path)
		_music.play()


func music_playing() -> bool:
	return _music != null and _music.playing


func stop_music() -> void:
	_music_wait = -1.0
	if _music != null:
		_music.stop()
		_music.stream = null


func _exit_tree() -> void:
	stop_music()


# ---------------------------------------------------------------- mesh helpers

## What a thing is made of. A material of one of these has a texture and its relief laid over
## its color. They are laid on by position (triplanar), so any mesh can take one without
## texture coordinates of its own, and the pattern has the same size on a tent as on a cup.
##   cloth   tent cloth: a coarse weave, unevenly banded like the strips it is sewn from
##   hair    the dark goat-hair cloth of the long tents: coarser and rougher
##   linen   fine cloth: hangings, bedding, banners
##   basket  plaited reed and palm: baskets and mats
##   wood    with the grain running along the piece
##   clay    fired pots and jars
##   stone
##   metal   beaten bronze, gold and silver
const SURFACES := ["cloth", "hair", "linen", "basket", "wood", "clay", "stone", "metal"]

var _textures := {}


## A plain material of `color`, or one made of `surface` (see SURFACES). `grain` is the axis of
## the mesh (0, 1 or 2 for x, y, z) that the grain of wood runs along.
func mat(color: Color, surface: String = "", emit: float = 0.0, alpha: float = 1.0, grain: int = 1) -> StandardMaterial3D:
	var key := "%s|%s%d|%.2f|%.2f" % [color.to_html(), surface, grain if surface == "wood" else 0, emit, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = 0.95
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if SURFACES.has(surface):
		_lay(m, surface, grain)
	_mats[key] = m
	return m


## Lays the texture of a surface on a material. The textures darken what they cover a little,
## so the color is lifted by as much to keep the thing the color it was given.
func _lay(m: StandardMaterial3D, surface: String, grain: int) -> void:
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 6.0
	m.normal_enabled = true
	var lift := 1.0
	match surface:
		"cloth", "hair", "linen", "basket":
			# The weave is a small tile repeated closely. It is the detail layer, which has a
			# scale of its own; under it broad uneven bands run level along the cloth.
			m.detail_enabled = true
			m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
			m.detail_albedo = _texture("weave")
			m.detail_normal = _texture("weave_relief")
			m.uv2_triplanar = true
			m.uv2_triplanar_sharpness = 6.0
			# Tiles to the metre; a tile is two threads each way.
			m.uv2_scale = Vector3.ONE * float({"cloth": 26.0, "hair": 17.0, "linen": 46.0, "basket": 10.0}[surface])
			m.normal_scale = float({"cloth": 0.8, "hair": 1.1, "linen": 0.45, "basket": 1.4}[surface])
			m.roughness = 1.0
			lift = 1.1
			if surface != "basket":
				m.albedo_texture = _texture("bands_deep" if surface == "hair" else "bands")
				m.uv1_scale = Vector3(0.12, 0.6, 0.12)
				lift = 1.2
		"wood":
			# One noise, drawn out along the piece and squeezed across it.
			var scale := Vector3.ONE * 6.5
			scale[clampi(grain, 0, 2)] = 0.8
			m.albedo_texture = _texture("fibre")
			m.normal_texture = _texture("fibre_relief")
			m.normal_scale = 0.9
			m.uv1_scale = scale
			m.roughness = 0.85
			lift = 1.2
		"clay":
			m.albedo_texture = _texture("speckle")
			m.normal_texture = _texture("speckle_relief")
			m.normal_scale = 0.35
			m.uv1_scale = Vector3.ONE * 4.0
			m.roughness = 0.9
			lift = 1.08
		"stone":
			m.albedo_texture = _texture("rough")
			m.normal_texture = _texture("speckle_relief")
			m.normal_scale = 1.2
			m.uv1_scale = Vector3.ONE * 1.8
			m.roughness = 1.0
			lift = 1.15
		"metal":
			m.albedo_texture = _texture("speckle")
			m.normal_texture = _texture("speckle_relief")
			m.normal_scale = 0.3
			m.uv1_scale = Vector3.ONE * 7.0
			m.metallic = 0.35
			m.roughness = 0.5
			lift = 1.08
	var c := m.albedo_color
	m.albedo_color = Color(minf(c.r * lift, 1.0), minf(c.g * lift, 1.0), minf(c.b * lift, 1.0), c.a)


## The textures the surfaces are made from, each built the first time it is wanted.
func _texture(id: String) -> Texture2D:
	if not _textures.has(id):
		match id:
			"weave", "weave_relief":
				_make_weave()
			"bands":
				_textures[id] = _noise(11, 0.02, 0.82)
			"bands_deep":
				_textures[id] = _noise(12, 0.02, 0.7)
			"fibre":
				_textures[id] = _noise(21, 0.035, 0.6)
			"fibre_relief":
				_textures[id] = _noise(21, 0.035, 0.0, 5.0)
			"speckle":
				_textures[id] = _noise(31, 0.07, 0.84)
			"rough":
				_textures[id] = _noise(31, 0.07, 0.68)
			"speckle_relief":
				_textures[id] = _noise(31, 0.07, 0.0, 4.0)
	return _textures[id]


## A tile of smooth noise that repeats without a seam: shades of grey from `low` to white, or,
## given `relief`, the same noise as a normal map of that strength.
func _noise(seed_value: int, frequency: float, low: float, relief: float = 0.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	if relief > 0.0:
		t.as_normal_map = true
		t.bump_strength = relief
	else:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(low, low, low))
		ramp.set_color(1, Color(1, 1, 1))
		t.color_ramp = ramp
	t.noise = n
	return t


## Woven cloth as a tile of two threads by two, in plain weave: each thread passes over one
## and under the next. Made as how bright each point is, and as the relief of the threads.
func _make_weave() -> void:
	var n := 64
	var half := n / 2
	var shade := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	var relief := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var across_upright := cos(((float(x % half) + 0.5) / half - 0.5) * PI)   # 1 on the middle of an upright thread
			var across_level := cos(((float(y % half) + 0.5) / half - 0.5) * PI)     # 1 on the middle of a level one
			var upright_on_top := ((x / half) + (y / half)) % 2 == 0
			var h := 0.0
			if upright_on_top:
				h = maxf(across_upright * (0.6 + 0.4 * across_level), across_level * 0.4)
			else:
				h = maxf(across_level * (0.6 + 0.4 * across_upright), across_upright * 0.4)
			var v := 0.78 + 0.22 * h
			shade.set_pixel(x, y, Color(v, v, v))
			relief.set_pixel(x, y, Color(h, h, h))
	shade.generate_mipmaps()
	relief.bump_map_to_normal_map(6.0)
	relief.generate_mipmaps(true)
	_textures["weave"] = ImageTexture.create_from_image(shade)
	_textures["weave_relief"] = ImageTexture.create_from_image(relief)


## A box. Made of wood, its grain runs along its longest side.
func mesh_box(size: Vector3, color: Color, surface: String = "", emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat(color, surface, emit, 1.0, size.max_axis_index())
	return mi


func mesh_sphere(radius: float, color: Color, surface: String = "", emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.material_override = mat(color, surface, emit)
	return mi


## A cylinder or cone standing on its end. Made of wood, its grain runs from end to end.
func mesh_cyl(top: float, bottom: float, height: float, color: Color, surface: String = "", emit: float = 0.0, alpha: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = mat(color, surface, emit, alpha)
	return mi


func mesh_capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 12
	c.rings = 4
	mi.mesh = c
	mi.material_override = mat(color)
	return mi


func label3d(text: String, size: int = 48, color: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = preload("res://scripts/ui.gd").font("bold")
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 10
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	return l
