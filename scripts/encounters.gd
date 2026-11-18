extends Node
## Meetings out in the wilds, picked from data/encounters.gd: the beasts of the region, a band of
## fighting men of another people, and now and then a caravan of traders with rare goods. One at
## a time, and only once the scout is well beyond the tents (Encounters.FAR). An encounter the
## scout walks far from (Encounters.LEAVE) is left behind and goes; the next comes later.

const Encounters := preload("res://data/encounters.gd")
const TerrainScript := preload("res://scripts/terrain.gd")
const CreatureScript := preload("res://scripts/creature.gd")

var world
var stopped := false   # the self-test holds encounters back while it tests other things
## The encounter under way, or {}: kind ("beasts", "band" or "caravan"), members (its nodes), and
## for a caravan its trader, stock (a trader grid) and title.
var active := {}
var wait := 0.0        # seconds more of wandering in the wilds before the next one
var rng := RandomNumberGenerator.new()


func setup() -> void:
	rng.randomize()
	wait = rng.randf_range(Encounters.FIRST[0], Encounters.FIRST[1])
	stopped = world.args.has("selftest")


## True once the scout is far enough from the camp to meet things.
func out_in_wilds() -> bool:
	var p: Vector3 = world.player.global_position
	return Vector2(p.x - world.camp_pos.x, p.z - world.camp_pos.z).length() > world.camp_radius + Encounters.FAR


func _process(delta: float) -> void:
	var player = world.player
	if not is_instance_valid(player):
		return
	if not active.is_empty():
		_watch(delta)
		return
	if stopped or player.indoors or player.dead or not out_in_wilds():
		return
	wait -= delta
	if wait <= 0.0:
		var sum := 0.0
		for k in Encounters.KINDS:
			sum += float(Encounters.KINDS[k])
		var roll := rng.randf() * sum
		for k in Encounters.KINDS:
			roll -= float(Encounters.KINDS[k])
			if roll <= 0.0:
				if not start(k):
					start("beasts")
				break


## Starts an encounter: "beasts", "band" or "caravan", or one animal or people by name ("lion",
## "Edomite"). `near` puts it a few steps in front of the scout (for pictures and tests). False
## if nothing of that kind belongs to this stage.
func start(what: String, near: bool = false) -> bool:
	if what == "caravan":
		_start_caravan(near)
		return true
	var beast := _line(Encounters.BEASTS, "kind", what, "beasts")
	if not beast.is_empty():
		_start_beasts(beast, near)
		return true
	var band := _line(Encounters.BANDS, "people", what, "band")
	if not band.is_empty():
		_start_band(band, near)
		return true
	return false


## The line of `table` whose `key` is `what`; or, when `what` is `any`, one picked by weight among
## those for this stage. {} if there is none.
func _line(table: Array, key: String, what: String, any: String) -> Dictionary:
	var pool: Array = []
	var sum := 0.0
	for line in table:
		if str(line[key]) == what:
			return line
		var stages: Array = line["stages"]
		if Game.land_index() >= int(stages[0]) and Game.land_index() <= int(stages[1]):
			pool.append(line)
			sum += float(line["weight"])
	if what != any:
		return {}
	var roll := rng.randf() * sum
	for line in pool:
		roll -= float(line["weight"])
		if roll <= 0.0:
			return line
	return {}


## A spot `dist` ahead of the scout (or behind, for something creeping up), a little to one side,
## kept on the map and out of the camp.
func _place(dist: float, behind: bool, near: bool) -> Vector3:
	var player = world.player
	var f: Vector3 = player.forward()
	var ang := atan2(f.x, f.z) + rng.randf_range(-0.6, 0.6) + (PI if behind else 0.0)
	var at: Vector3 = player.global_position + Vector3(sin(ang), 0.0, cos(ang)) * dist
	var limit := TerrainScript.HALF - 25.0
	at.x = clampf(at.x, -limit, limit)
	at.z = clampf(at.z, -limit, limit)
	var off := Vector2(at.x - world.camp_pos.x, at.z - world.camp_pos.z)
	var keep_out: float = world.camp_radius + 20.0
	if not near and off.length() < keep_out:
		off = off.normalized() * keep_out
		at = Vector3(world.camp_pos.x + off.x, 0.0, world.camp_pos.z + off.y)
	return world.ground(at.x, at.z)


func _toward(at: Vector3) -> String:
	var p: Vector3 = world.player.global_position
	return world.compass(at.x - p.x, at.z - p.z)


func _start_beasts(line: Dictionary, near: bool) -> void:
	var kind := str(line["kind"])
	var stalker := bool(Game.Enemies.ENEMIES[kind].get("stalk", false))
	var at := _place(9.0 if near else (26.0 if stalker else 34.0), stalker and not near, near)
	var n := rng.randi_range(int(line["count"][0]), int(line["count"][1]))
	var members: Array = []
	for i in n:
		var off := Vector3.ZERO if i == 0 else Vector3(rng.randf_range(-3.5, 3.5), 0.0, rng.randf_range(-3.5, 3.5))
		members.append(world.spawn_enemy(kind, world.ground(at.x + off.x, at.z + off.z), float(world.stage["mult"]), {"hunting": bool(line["hunt"])}))
	active = {"kind": "beasts", "members": members}
	Game.say(str(line["say"]) % _toward(at))


func _start_band(line: Dictionary, near: bool) -> void:
	var people := str(line["people"])
	var at := _place(9.0 if near else 38.0, false, near)
	var n := rng.randi_range(int(Encounters.BAND_SIZE[0]), int(Encounters.BAND_SIZE[1]))
	var members: Array = []
	var opts := {"people": people, "hunting": true}
	if rng.randf() < Encounters.BAND_CHAMPION:
		members.append(world.spawn_enemy("champion", at, float(world.stage["mult"]), opts))
	for i in n:
		var kind := "slinger" if i == n - 1 and n >= 3 else "raider"
		var p: Vector3 = world.ground(at.x + rng.randf_range(-4.0, 4.0), at.z + rng.randf_range(-4.0, 4.0))
		members.append(world.spawn_enemy(kind, p, float(world.stage["mult"]), opts))
	active = {"kind": "band", "members": members}
	Game.say("A band of %s men is coming at you from the %s." % [people, _toward(at)])


func _start_caravan(near: bool) -> void:
	var at := _place(9.0 if near else 30.0, false, near)
	var peoples: Array = Encounters.CARAVAN["peoples"]
	var people := str(peoples[rng.randi() % peoples.size()])
	var robe := [Color(0.42, 0.3, 0.5), Color(0.6, 0.22, 0.16), Color(0.25, 0.32, 0.5)][rng.randi() % 3] as Color
	var members: Array = []
	var trader = world.spawn_npc("%s trader" % people, "caravan", at, robe, {"sash_color": Color(0.85, 0.7, 0.25)})
	trader.face(world.player.global_position)
	members.append(trader)
	# Their pack donkeys stand beside them, and two men with spears keep watch.
	var side: Vector3 = trader.global_basis.x
	var back: Vector3 = -trader.global_basis.z
	for i in 2:
		var d = CreatureScript.new()
		world.stage_root.add_child(d)
		d.build("donkey", Color(0.55, 0.52, 0.48).darkened(rng.randf() * 0.2))
		var p: Vector3 = at + side * (2.2 if i == 0 else -2.4) - back * (1.2 + i * 1.6)
		d.global_position = world.ground(p.x, p.z)
		d.rotation.y = trader.rotation.y + rng.randf_range(-0.5, 0.5) + PI * 0.5
		members.append(d)
	for i in 2:
		var p: Vector3 = at + side * (3.6 if i == 0 else -3.8) + back * 1.5
		var guard = world.spawn_npc("%s guard" % people, "guard", world.ground(p.x, p.z), robe.darkened(0.25))
		guard.face(world.player.global_position)
		guard.remove_from_group("interactable")
		guard.figure.set_hands("spear", "none")
		members.append(guard)
	active = {"kind": "caravan", "members": members, "trader": trader, "stock": _stock(), "title": "%s caravan" % people}
	Game.say("A caravan of %s traders has stopped to the %s. They carry rare goods." % [people, _toward(at)])


## A caravan's goods: a few rare finds, each of its kind.
func _stock() -> Array:
	var tier: int = int(world.stage["tier"])
	var ids: Array = []
	var want := rng.randi_range(int(Encounters.CARAVAN["rare"][0]), int(Encounters.CARAVAN["rare"][1]))
	for i in 20:
		if ids.size() >= want:
			break
		var id := Game.roll_table("rare", tier)
		if id != "" and not ids.has(id):
			ids.append(id)
	var grid: Array = []
	for id in ids:
		Game.place(grid, Game.TRADER_GRID, Game.new_item(id))
	return grid


## The caravan's trader is spoken to.
func trade() -> void:
	if str(active.get("kind", "")) == "caravan":
		world.hud.open_caravan(active["stock"], str(active["title"]))


func _watch(delta: float) -> void:
	var alive: Array = (active["members"] as Array).filter(func(n) -> bool: return is_instance_valid(n) and not bool(n.get("dead") == true))
	if alive.is_empty():
		_end(false)
		return
	if str(active["kind"]) == "caravan":
		for n in alive:
			if n is CreatureScript:
				n.animate(delta, 0.0)
	# Left behind: the scout is far from what is left of it.
	var mid := Vector3.ZERO
	for n in alive:
		mid += (n as Node3D).global_position
	mid /= alive.size()
	var p: Vector3 = world.player.global_position
	if Vector2(mid.x - p.x, mid.z - p.z).length() > Encounters.LEAVE:
		for n in alive:
			n.queue_free()
		_end(true)


func _end(_left: bool) -> void:
	active = {}
	wait = rng.randf_range(Encounters.GAP[0], Encounters.GAP[1])


## Where the caravan's trader stands, for the markers and the map; null if there is none.
func trader_node():
	if str(active.get("kind", "")) == "caravan" and is_instance_valid(active["trader"]):
		return active["trader"]
	return null
