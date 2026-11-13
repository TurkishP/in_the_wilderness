extends Node
## Side quests for the current stage. Three kinds:
##   gather       bring back N items scattered in the wilderness
##   lost         find a child out in the wilderness and lead them home
##   investigate  hear three witnesses, then accuse the one suspect who fits every clue

const SASHES := ["red", "blue", "white", "green"]
const SASH_COLORS := [Color(0.75, 0.15, 0.12), Color(0.15, 0.3, 0.7), Color(0.92, 0.92, 0.88), Color(0.2, 0.55, 0.25)]
const SIDES := ["north", "south", "east", "west"]
const SIDE_DIRS := [Vector2(0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0)]
const CARRIES := ["a waterskin", "a walking stick", "a basket", "a bundle of cloth"]
const BASE_REWARD := {"gather": 22.0, "lost": 30.0, "investigate": 36.0}

var world
var list: Array = []


func setup(defs: Array) -> void:
	var n := defs.size()
	for i in n:
		var q: Dictionary = (defs[i] as Dictionary).duplicate(true)
		q["index"] = i
		q["status"] = "new"
		q["progress"] = 0
		q["nodes"] = []
		var x := (float(i) - float(n - 1) * 0.5) * 6.0
		var pos: Vector3 = world.plaza_point(x, 5.0)
		var npc = world.spawn_npc(str(q["giver"]), "giver", pos, Color(0.5, 0.4, 0.58))
		npc.quest = q
		npc.set_mark("!")
		q["npc"] = npc
		list.append(q)


func reward_silver(q: Dictionary) -> int:
	return int(float(BASE_REWARD[q["type"]]) * float(world.stage["mult"]))


func _process(_delta: float) -> void:
	for q in list:
		if q["type"] == "lost" and q["status"] == "active" and q.get("found", false):
			var child = q["child"]
			var npc = q["npc"]
			if is_instance_valid(child) and child.global_position.distance_to(npc.global_position) < 7.0:
				child.follow_target = null
				q["status"] = "ready"
				npc.set_mark("?")
				Game.say("The child is home. Speak to %s." % str(q["giver"]).to_lower())


# ---------------------------------------------------------------- talking

func talk_giver(q: Dictionary) -> void:
	var giver: String = q["giver"]
	match str(q["status"]):
		"new":
			var offer := "%s\n\n[i]Reward: %d silver%s[/i]" % [q["ask"], reward_silver(q), _item_note(q)]
			world.hud.dialog(giver, offer, [["I will help.", accept.bind(q)], ["Not now.", Callable()]])
		"active":
			world.hud.dialog(giver, _progress_line(q))
		"ready":
			_complete(q, 1.0, "Thank you. I will not forget this.")
		_:
			world.hud.dialog(giver, "Peace to you. We have not forgotten what you did.")


func _item_note(q: Dictionary) -> String:
	if not q.has("reward_item"):
		return ""
	return " and a %s" % str(Game.Items.ITEMS[q["reward_item"]]["name"]).to_lower()


func accept(q: Dictionary) -> void:
	if q["status"] != "new":
		return
	q["status"] = "active"
	q["npc"].set_mark("")
	match str(q["type"]):
		"gather":
			_start_gather(q)
		"lost":
			_start_lost(q)
		"investigate":
			_start_investigation(q)
	Game.say("Quest accepted: %s" % q["title"])


func talk_child(npc) -> void:
	var q: Dictionary = npc.quest
	if q["status"] != "active":
		return
	if not q.get("found", false):
		q["found"] = true
		npc.follow_target = world.player
		world.hud.dialog(npc.npc_name, "You came! I could not find the way back. Please take me home.")
	else:
		world.hud.dialog(npc.npc_name, "I am right behind you.")


func talk_witness(npc) -> void:
	var q: Dictionary = npc.quest
	var i: int = int(npc.data["clue"])
	var heard: Array = q["heard"]
	heard[i] = true
	npc.set_mark("")
	world.hud.dialog(npc.npc_name, str(q["clues"][i]))


func talk_suspect(npc) -> void:
	var q: Dictionary = npc.quest
	if q["status"] != "active":
		return
	world.hud.dialog(npc.npc_name, "%s\n\n\"Why are you looking at me like that?\"" % npc.data["desc"],
		[["Accuse this one before the elder.", accuse.bind(q, npc)], ["Step back.", Callable()]])


func accuse(q: Dictionary, npc) -> void:
	if q["status"] != "active":
		return
	if bool(npc.data["culprit"]):
		_complete(q, 1.0, "The elders search the tent. %s\n\nThe matter is settled before the whole camp." % q["proof"])
	else:
		_complete(q, 0.3, "The elders search the tent and find nothing. You accused the wrong one, and by morning the real culprit has covered every trace.")


# ---------------------------------------------------------------- starting each kind

func _start_gather(q: Dictionary) -> void:
	var rng: RandomNumberGenerator = world.rng
	var ang := rng.randf() * TAU
	var count: int = int(q["count"])
	var cx := sin(ang) * 105.0
	var cz := cos(ang) * 105.0
	q["hint"] = world.compass(cx, cz)
	for i in count:
		var p: Vector3 = world.ground(cx + rng.randf_range(-30.0, 30.0), cz + rng.randf_range(-30.0, 30.0))
		world.spawn_pickup("quest", int(q["index"]), p, str(q["item"]), q["color"])


func _start_lost(q: Dictionary) -> void:
	var rng: RandomNumberGenerator = world.rng
	var ang := rng.randf() * TAU
	var dist := rng.randf_range(115.0, 155.0)
	var x := sin(ang) * dist
	var z := cos(ang) * dist
	q["hint"] = world.compass(x, z)
	var pos: Vector3 = world.ground(x, z)
	var child = world.spawn_npc(str(q["child"]), "child", pos, Color(0.6, 0.55, 0.4), {"scale": 0.62, "solid": false})
	child.quest = q
	child.set_mark("!")
	q["child"] = child
	q["nodes"].append(child)
	# Whatever kept the child from walking home is still nearby.
	var wild: Dictionary = world.stage["wild"]
	var kinds: Array = wild.keys()
	for i in 2:
		var kind: String = kinds[i % kinds.size()]
		var gp: Vector3 = world.ground(x + rng.randf_range(-9.0, 9.0), z + rng.randf_range(-9.0, 9.0))
		world.spawn_enemy(kind, gp, float(world.stage["mult"]))


func _start_investigation(q: Dictionary) -> void:
	var rng: RandomNumberGenerator = world.rng
	var a := rng.randi() % 4
	var b := rng.randi() % 4
	var c := rng.randi() % 4
	var a2 := (a + 1 + rng.randi() % 3) % 4
	var b2 := (b + 1 + rng.randi() % 3) % 4
	var c2 := (c + 1 + rng.randi() % 3) % 4
	# The first entry is the culprit. Each other suspect differs in exactly one trait,
	# so every clue rules out one person and all three are needed.
	var combos: Array = [[a, b, c], [a, b, c2], [a, b2, c], [a2, b, c]]
	q["clues"] = [
		"I saw someone slip away. All I can tell you is that the sash was %s." % SASHES[a],
		"Whoever it was went back toward the tents on the %s side of the camp." % SIDES[b],
		"It was dark, but the one I saw was carrying %s." % CARRIES[c],
	]
	q["heard"] = [false, false, false]
	var per_side := [0, 0, 0, 0]
	for i in combos.size():
		var t: Array = combos[i]
		var side: int = t[1]
		var dir: Vector2 = SIDE_DIRS[side]
		var across := Vector2(-dir.y, dir.x)
		var slot: int = per_side[side]
		per_side[side] = slot + 1
		var p2: Vector2 = dir * 12.0 + across * (float(slot) * 3.0 - 3.0)
		var who: String = "Man in a %s sash" % SASHES[t[0]]
		var npc = world.spawn_npc(who, "suspect", world.plaza_point(p2.x, p2.y), Color(0.45, 0.4, 0.33), {"sash_color": SASH_COLORS[t[0]]})
		npc.quest = q
		npc.data = {
			"culprit": i == 0,
			"desc": "A man in a %s sash, standing by the %s tents, carrying %s." % [SASHES[t[0]], SIDES[t[1]], CARRIES[t[2]]],
		}
		q["nodes"].append(npc)
		if i == 0:
			q["culprit"] = npc
	for i in 3:
		var wp: Vector3 = world.plaza_point(-5.0 + i * 5.0, -5.5)
		var w = world.spawn_npc("Witness", "witness", wp, Color(0.62, 0.5, 0.38))
		w.quest = q
		w.data = {"clue": i}
		w.set_mark("!")
		q["nodes"].append(w)


# ---------------------------------------------------------------- progress and reward

func on_gather(index: int) -> void:
	var q: Dictionary = list[index]
	if q["status"] != "active":
		return
	q["progress"] = int(q["progress"]) + 1
	var count: int = int(q["count"])
	if int(q["progress"]) >= count:
		q["status"] = "ready"
		q["npc"].set_mark("?")
		Game.say("You have all you need. Return to %s." % str(q["giver"]).to_lower())
	else:
		Game.say("%s  %d/%d" % [q["item"], q["progress"], count])


func _complete(q: Dictionary, factor: float, words: String) -> void:
	var silver := int(reward_silver(q) * factor)
	Game.silver += silver
	var text := "%s\n\n[i]You receive %d silver." % [words, silver]
	if factor >= 1.0 and q.has("reward_item"):
		var id := str(q["reward_item"])
		var inst := Game.add_item(id)
		if inst.is_empty():
			# No room in the bag: it is left at the scout's feet.
			world.spawn_pickup("item", id, world.player.global_position + Vector3(0.8, 0, 0.8))
			text += " You are given a %s, but your bag is full; it lies at your feet." % str(Game.Items.ITEMS[id]["name"]).to_lower()
		else:
			text += " You are given a %s. Press I to see it." % Game.item_name(inst).to_lower()
	text += "[/i]"
	q["status"] = "done"
	q["npc"].set_mark("")
	for n in q["nodes"]:
		if is_instance_valid(n):
			n.queue_free()
	q["nodes"] = []
	world.hud.dialog(str(q["giver"]), text)


func _progress_line(q: Dictionary) -> String:
	if q["status"] == "ready":
		return "Return to %s." % str(q["giver"]).to_lower()
	match str(q["type"]):
		"gather":
			return "%s %d/%d. Look to the %s of the camp." % [q["item"], q["progress"], q["count"], q["hint"]]
		"lost":
			if q.get("found", false):
				return "Lead the child back to the camp."
			return "Last seen heading %s." % q["hint"]
		_:
			var heard := 0
			for h in q["heard"]:
				if h:
					heard += 1
			return "Witnesses heard %d/3. Accuse the one who fits every clue." % heard


func tracker_text() -> String:
	var out := ""
	for q in list:
		var st: String = q["status"]
		if st == "active" or st == "ready":
			out += "%s\n   %s\n" % [q["title"], _progress_line(q)]
	return out
