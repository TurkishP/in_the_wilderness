extends Node
## Global state and rules, autoloaded as "Game".

signal toast(text: String)
signal look_changed   # the player's appearance was edited
signal gear_changed   # equipped gear changed
signal settings_changed

const Items := preload("res://data/items.gd")
const Stages := preload("res://data/stages.gd")
const Enemies := preload("res://data/enemies.gd")
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
	"master": 0.8, "music": 0.55, "sensitivity": 1.0, "invert_y": false, "fov": 70.0,
	"fullscreen": false, "vsync": true, "shadows": true,
}

var save_path := "user://save.json"
var stage_index := 0
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_setup_audio()
	load_settings()
	new_game()


func new_game() -> void:
	stage_index = 0
	silver = 15
	bronze = 0
	max_water = 3
	raids_survived = 0
	workshop = false
	look = DEFAULT_LOOK.duplicate()
	look_set = false
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


func stage() -> Dictionary:
	return Stages.LIST[stage_index]


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
	return 100.0 + 10.0 * stage_index


func say(text: String) -> void:
	toast.emit(text)


# ---------------------------------------------------------------- input

func setup_input() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_E, "drink": KEY_Q, "sheathe": KEY_R,
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
		"thirst", "stamina":
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
	return FIST_DAMAGE if w.is_empty() else stat(w, "damage")


## How fast a weapon swings: a 1.5 kg weapon at normal speed, lighter ones quicker, heavier slower.
func swing_speed(inst: Dictionary) -> float:
	if inst.is_empty():
		return 1.3
	return clampf(sqrt(1.5 / maxf(0.1, float(item_def(inst).get("weight", 1.5)))), 0.6, 1.5)


func sling_power() -> float:
	return stat(equipped.get("sling", {}), "damage")


func bow_power() -> float:
	return stat(bow(), "damage")


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

## Whether `inst` can be worn in `slot` at all.
func slot_accepts(slot: String, inst: Dictionary) -> bool:
	var s: String = item_def(inst)["slot"]
	match slot:
		"hand_r", "hand_l":
			return s == "hand"
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


func price(inst: Dictionary) -> int:
	return int(item_def(inst)["price"])


## Buys something into the bag. False if it costs too much or will not fit.
func try_buy(id: String) -> bool:
	var cost: int = int(Items.ITEMS[id]["price"])
	if silver < cost or not can_take(id):
		return false
	silver -= cost
	add_item(id)
	return true


func sell_value(inst: Dictionary) -> int:
	var d := item_def(inst)
	if d.has("stack"):
		return 0
	var base: int = int(d["price"])
	if base <= 0:
		base = int(d["tier"]) * 60
	return int(base * 0.35 * (1.0 + 0.25 * int(inst["plus"])))


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
	}


func restore(s: Dictionary) -> void:
	stage_index = clampi(int(s.get("stage_index", 0)), 0, stage_count() - 1)
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
	bag = _grid_list(s.get("bag", []), bag_grid(), spill)
	chest = _grid_list(s.get("chest", []), chest_grid(), [])
	if s.has("stones"):
		take_ammo("stones", int(s["stones"]))
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
	return FileAccess.file_exists(save_path)


## Writes the save file. The game is saved only by sleeping in the scout's own tent; `progress`
## is where the stage stood then ({obj_done, hp, thirst, water}), so loading picks it up there.
func save_game(progress: Dictionary = {}) -> void:
	var data := snapshot()
	data["resume"] = progress
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func load_game() -> bool:
	if not has_save():
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	restore(data)
	return true


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
	var music := AudioServer.get_bus_index("Music")
	if music >= 0:
		AudioServer.set_bus_volume_db(music, linear_to_db(maxf(0.0001, float(settings["music"]))))
		AudioServer.set_bus_mute(music, float(settings["music"]) <= 0.001)
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


## The music has a bus of its own so its volume can be set apart from the rest.
func _setup_audio() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Music")
		AudioServer.set_bus_send(i, "Master")
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_music.finished.connect(func() -> void: _music_wait = rng.randf_range(MUSIC_GAP.x, MUSIC_GAP.y))
	_music_next = rng.randi() % MUSIC.size()
	# No music for headless runs (the self-test).
	_music_wait = -1.0 if DisplayServer.get_name() == "headless" else 2.0


## Plays the pieces in turn, with a quiet stretch between them.
func _process(delta: float) -> void:
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
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 10
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	return l
