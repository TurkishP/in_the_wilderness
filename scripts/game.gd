extends Node
## Global state and rules, autoloaded as "Game".

signal toast(text: String)

const Items := preload("res://data/items.gd")
const Stages := preload("res://data/stages.gd")
const Enemies := preload("res://data/enemies.gd")
const SLOTS := ["melee", "sling", "armor"]
const PLUS_POWER := 0.12
const PLUS_ARMOR := 0.02

var save_path := "user://save.json"
var stage_index := 0
var silver := 0
var bronze := 0
var hp := 100.0
var max_hp := 100.0
var thirst := 100.0
var water := 3
var max_water := 3
var bag: Array = []
var equipped := {}
var raids_survived := 0
var workshop := false   # Bezalel's workshop stands: gear can go to +5
var camp_hp := 100.0
var camp_has_water := true
var ui_open := false
var prompt := ""
var rng := RandomNumberGenerator.new()
var _block_frame := -1
var _mats := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	new_game()


func new_game() -> void:
	stage_index = 0
	silver = 15
	bronze = 0
	max_water = 3
	raids_survived = 0
	workshop = false
	bag = []
	equipped = {
		"melee": {"id": "staff", "plus": 0},
		"sling": {"id": "wool_sling", "plus": 0},
		"armor": {"id": "cloak", "plus": 0},
	}
	begin_stage()


func stage() -> Dictionary:
	return Stages.LIST[stage_index]


func stage_count() -> int:
	return Stages.LIST.size()


## Resets the per-stage values. The scout grows up over the forty years: +10 health per stage.
func begin_stage() -> void:
	var s := stage()
	max_hp = 100.0 + 10.0 * stage_index
	hp = max_hp
	thirst = float(s.get("start_thirst", 100.0))
	water = mini(max_water, int(s.get("start_water", max_water)))
	camp_hp = 100.0
	camp_has_water = bool(s.get("camp_water", true))


func say(text: String) -> void:
	toast.emit(text)


# ---------------------------------------------------------------- input

func setup_input() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_E, "drink": KEY_Q,
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

func item_def(inst: Dictionary) -> Dictionary:
	return Items.ITEMS[inst["id"]]


func item_name(inst: Dictionary) -> String:
	var n: String = item_def(inst)["name"]
	var plus: int = int(inst["plus"])
	return n if plus == 0 else "%s +%d" % [n, plus]


func item_power(inst: Dictionary) -> float:
	var d := item_def(inst)
	var plus: int = int(inst["plus"])
	if d["slot"] == "armor":
		return float(d["power"]) + PLUS_ARMOR * plus
	return float(d["power"]) * (1.0 + PLUS_POWER * plus)


func power_text(slot: String, power: float) -> String:
	if slot == "armor":
		return "blocks %d%%" % int(round(power * 100.0))
	return "damage %d" % int(round(power))


func item_desc(inst: Dictionary) -> String:
	return power_text(str(item_def(inst)["slot"]), item_power(inst))


func melee_power() -> float:
	return item_power(equipped["melee"])


func sling_power() -> float:
	return item_power(equipped["sling"])


func armor_block() -> float:
	return item_power(equipped["armor"])


func add_item(id: String, plus: int = 0) -> Dictionary:
	var inst := {"id": id, "plus": plus}
	bag.append(inst)
	return inst


func equip(inst: Dictionary) -> void:
	var slot: String = item_def(inst)["slot"]
	var i := bag.find(inst)
	if i < 0:
		return
	bag.remove_at(i)
	bag.append(equipped[slot])
	equipped[slot] = inst


## Gear can be strengthened to +2 at first, and to +5 once Bezalel's workshop stands (stage 3).
func max_plus() -> int:
	return 5 if workshop or stage_index >= 3 else 2


func upgrade_cost(inst: Dictionary) -> Dictionary:
	var tier: int = int(item_def(inst)["tier"])
	var plus: int = int(inst["plus"])
	return {"silver": 15 * tier * (plus + 1), "bronze": plus + 1}


func can_upgrade(inst: Dictionary) -> bool:
	if int(inst["plus"]) >= max_plus():
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
	return true


func shop_stock(tier_cap: int) -> Array:
	var out: Array = []
	for slot in SLOTS:
		for id in Items.ITEMS:
			var d: Dictionary = Items.ITEMS[id]
			var t: int = int(d["tier"])
			if d["slot"] == slot and int(d["price"]) > 0 and t <= tier_cap and t >= tier_cap - 1:
				out.append(id)
	return out


func try_buy(id: String) -> bool:
	var price: int = int(Items.ITEMS[id]["price"])
	if silver < price:
		return false
	silver -= price
	add_item(id)
	return true


func sell_value(inst: Dictionary) -> int:
	var d := item_def(inst)
	var base: int = int(d["price"])
	if base <= 0:
		base = int(d["tier"]) * 60
	return int(base * 0.35 * (1.0 + 0.25 * int(inst["plus"])))


func sell(inst: Dictionary) -> void:
	var i := bag.find(inst)
	if i < 0:
		return
	silver += sell_value(inst)
	bag.remove_at(i)


func waterskin_price() -> int:
	return 40 + 35 * (max_water - 3)


func try_buy_waterskin() -> bool:
	var price := waterskin_price()
	if max_water >= 6 or silver < price:
		return false
	silver -= price
	max_water += 1
	water += 1
	return true


## Picks a random piece of gear a raider might carry at this tier. "" if nothing fits.
func roll_drop(tier_cap: int) -> String:
	var pool: Array = []
	for id in Items.ITEMS:
		var d: Dictionary = Items.ITEMS[id]
		var t: int = int(d["tier"])
		if int(d["price"]) > 0 and t <= tier_cap and t >= tier_cap - 1:
			pool.append(id)
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


## Applies armor and returns the damage actually taken.
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
	}


func restore(s: Dictionary) -> void:
	stage_index = clampi(int(s.get("stage_index", 0)), 0, stage_count() - 1)
	silver = int(s.get("silver", 0))
	bronze = int(s.get("bronze", 0))
	max_water = int(s.get("max_water", 3))
	raids_survived = int(s.get("raids_survived", 0))
	workshop = bool(s.get("workshop", false))
	bag = []
	for it in s.get("bag", []):
		if Items.ITEMS.has(str(it["id"])):
			bag.append({"id": str(it["id"]), "plus": int(it["plus"])})
	var eq: Dictionary = s.get("equipped", {})
	for slot in SLOTS:
		if eq.has(slot) and Items.ITEMS.has(str(eq[slot]["id"])):
			equipped[slot] = {"id": str(eq[slot]["id"]), "plus": int(eq[slot]["plus"])}
	begin_stage()


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save_game() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(snapshot()))
		f.close()


func load_game() -> bool:
	if not has_save():
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	restore(data)
	return true


# ---------------------------------------------------------------- mesh helpers

func mat(color: Color, emit: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [color.to_html(), emit, alpha]
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
	_mats[key] = m
	return m


func mesh_box(size: Vector3, color: Color, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat(color, emit)
	return mi


func mesh_sphere(radius: float, color: Color, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.material_override = mat(color, emit)
	return mi


func mesh_cyl(top: float, bottom: float, height: float, color: Color, emit: float = 0.0, alpha: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = mat(color, emit, alpha)
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
