extends Node3D
## Builds and runs one stage: terrain, camp, main objectives, raids and side quests.
##
## Debug arguments (after `--` on the command line):
##   --selftest             run the logic checks without a window and exit 0 or 1
##   --stage=N              start a throwaway game at stage N
##   --auto                 never show dialogs (each picks its first option)
##   --shot=PATH            save a screenshot to PATH and exit
##   --frames=N --yaw=DEG --pitch=DEG --arm=M   screenshot timing and camera (arm: camera distance)
##   --tp=X,Z | obj | exit | enemy | raid   move the player there first (--back=M metres short)
##   --raid                 start a raid at once
##   --finish               complete the stage's objectives at once
##   --skip=N               complete the first N objectives
##   --rich                 start with silver, bronze and a spare dagger
##   --menu=shop|smith|gear|pause|creator|map   open that menu (--face and --turn=N for the creator)
##   --look=sex:1,hair:2    set the player's appearance
##   --equip=ITEM_ID        equip a piece of gear

const TerrainScript := preload("res://scripts/terrain.gd")
const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const NpcScript := preload("res://scripts/npc.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const InteractScript := preload("res://scripts/interactable.gd")
const RaidScript := preload("res://scripts/raid_director.gd")
const QuestScript := preload("res://scripts/quests.gd")
const HudScript := preload("res://scripts/hud.gd")
const HumanScript := preload("res://scripts/human.gd")
const SceneryScript := preload("res://scripts/scenery.gd")
const RegionScript := preload("res://data/region.gd")
const CampScript := preload("res://scripts/camp.gd")
const CloudScript := preload("res://scripts/cloud_pillar.gd")
const TalkScript := preload("res://data/talk.gd")

const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]

var hud
var player
var terrain
var scenery
var raid
var quests
var stage := {}
var stage_root: Node3D
var rng := RandomNumberGenerator.new()
var look_rng := RandomNumberGenerator.new()   # appearance of camp people; separate so it never shifts the layout
var camp
var camp_pos := Vector3.ZERO      # the middle of the camp
var camp_radius := 48.0           # how far out the tents reach
var plaza := Vector3.ZERO         # the middle of the gathering ground
var villagers: Array = []
var obj := {}
var obj_index := -1
var obj_count := 0
var obj_need := 1
var obj_pos := Vector3.ZERO
var obj_nodes: Array = []
var stage_done := false
var exit_node: Node3D
var snapshot := {}
var args := {}
var _obj_closed := false
var _failing := false
var _water_jars


func _ready() -> void:
	Game.setup_input()
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = str(a).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_build_sky()
	hud = HudScript.new()
	hud.world = self
	hud.auto = args.has("auto") or args.has("selftest")
	hud.no_capture = args.has("shot") or args.has("selftest")
	add_child(hud)

	Game.new_game()
	if args.has("selftest"):
		Game.save_path = "user://selftest_save.json"
		load_stage()
		_selftest()
		return
	if args.has("stage"):
		Game.save_path = "user://debug_save.json"
		Game.stage_index = clampi(int(args["stage"]) - 1, 0, Game.stage_count() - 1)
		Game.look_set = true   # debug runs skip the character creator
	elif Game.has_save():
		Game.load_game()
	load_stage()
	if args.has("finish"):
		while not stage_done:
			_finish_current_objective()
	for i in int(args.get("skip", "0")):
		_finish_current_objective()
	if args.has("look"):
		# --look=sex:1,hair:2,outfit:1  sets the player's appearance and skips the creator
		for pair in str(args["look"]).split(","):
			var kv: PackedStringArray = pair.split(":")
			Game.look[kv[0]] = int(kv[1])
		Game.look_changed.emit()
	if args.has("equip"):
		Game.equip(Game.add_item(str(args["equip"])))
	if args.has("rich"):
		Game.silver = 400
		Game.bronze = 6
		Game.add_item("dagger")
	match str(args.get("menu", "")):
		"shop":
			hud.open_shop()
		"smith":
			hud.open_smith()
		"gear":
			hud.open_inventory()
		"pause":
			hud.open_pause()
		"map":
			hud.open_map()
		"creator":
			hud.open_creator()
			if args.has("face"):
				hud._creator_toggle_view()
			for i in int(args.get("turn", "0")):
				player.turn_in_creator()
	if args.has("shot"):
		_shot()


func _build_sky() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.24, 0.47, 0.84)
	sm.sky_horizon_color = Color(0.87, 0.81, 0.69)
	sm.ground_bottom_color = Color(0.6, 0.5, 0.36)
	sm.ground_horizon_color = Color(0.87, 0.81, 0.69)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.87, 0.79, 0.65)
	# Thin haze: the mountains two kilometres off fade but stay in view.
	env.fog_density = 0.00045
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


# ================================================================ stage setup

func load_stage() -> void:
	if stage_root != null:
		remove_child(stage_root)
		stage_root.queue_free()
	stage_root = Node3D.new()
	add_child(stage_root)
	stage = Game.stage()
	rng.seed = int(stage["seed"])
	look_rng.seed = int(stage["seed"]) * 31 + 7
	Game.begin_stage()
	snapshot = Game.snapshot()
	Game.save_game()
	stage_done = false
	exit_node = null
	_failing = false
	obj_index = -1

	terrain = TerrainScript.new()
	stage_root.add_child(terrain)
	terrain.setup(stage)
	_build_camp()
	scenery = SceneryScript.new()
	stage_root.add_child(scenery)
	scenery.build(stage, rng, terrain, camp_radius + 8.0)
	hud.show_stage(terrain)

	player = PlayerScript.new()
	player.world = self
	stage_root.add_child(player)
	player.global_position = plaza_point(0.0, 13.0) + Vector3(0, 0.5, 0)

	_spawn_wildlife()
	quests = QuestScript.new()
	quests.world = self
	stage_root.add_child(quests)
	quests.setup(stage["quests"])
	raid = RaidScript.new()
	raid.world = self
	stage_root.add_child(raid)
	raid.setup(stage["raid"])
	_next_objective()

	# A new journey starts in the character creator; the stage introduction follows it.
	if Game.look_set:
		_show_intro()
	else:
		hud.open_creator(_show_intro)


func _show_intro() -> void:
	var intro := "[i]%s  (%s)\n%s[/i]\n\n%s" % [stage["place"], stage["ref"], stage["when"], stage["intro"]]
	hud.dialog("Stage %d:  %s" % [Game.stage_index + 1, stage["name"]], intro, [["Set out", Callable()]])


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.surface_y(x, z), z)


## Compass name for a direction on the map. North is -Z, east is +X.
func compass(x: float, z: float) -> String:
	var i := int(round(atan2(x, -z) / (TAU / 8.0)))
	return COMPASS[posmod(i, 8)]


func spawn_enemy(kind: String, pos: Vector3, mult: float, opts: Dictionary = {}):
	var o := opts.duplicate()
	if not o.has("name"):
		var foe: String = str(stage.get("foe", "Desert"))
		if kind == "raider":
			o["name"] = foe + " raider"
		elif kind == "slinger":
			o["name"] = foe + " slinger"
	if not o.has("tier"):
		o["tier"] = int(stage["tier"])
	var e = EnemyScript.new()
	e.world = self
	e.setup(kind, mult, o)
	stage_root.add_child(e)
	e.global_position = pos + Vector3(0, 0.3, 0)
	e.home = pos
	return e


func spawn_npc(npc_name: String, role: String, pos: Vector3, color: Color, opts: Dictionary = {}):
	var n = NpcScript.new()
	n.world = self
	n.setup(npc_name, role, color, opts)
	stage_root.add_child(n)
	n.global_position = pos
	# Face the middle of the gathering ground.
	n.rotation.y = atan2(pos.x - plaza.x, pos.z - plaza.z)
	return n


func spawn_pickup(kind: String, payload: Variant, pos: Vector3, label: String = "", color: Color = Color.WHITE):
	var p = PickupScript.new()
	p.world = self
	p.setup(kind, payload, label, color)
	stage_root.add_child(p)
	p.global_position = Vector3(pos.x, terrain.surface_y(pos.x, pos.z) + 0.1, pos.z)
	return p


func _interactable(label: String, pos: Vector3, radius: float, callback: Callable):
	var it = InteractScript.new()
	it.label = label
	it.interact_radius = radius
	it.callback = callback
	stage_root.add_child(it)
	it.global_position = pos
	return it


func _solid_box(node: Node3D, size: Vector3, offset: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = offset
	sb.add_child(cs)
	node.add_child(sb)


func _tent(pos: Vector3, angle: float, color: Color) -> void:
	var t := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(3.6, 2.6, 4.4)
	t.mesh = pm
	t.material_override = Game.mat(color)
	stage_root.add_child(t)
	t.global_position = pos + Vector3(0, 1.3, 0)
	t.rotation.y = angle
	_solid_box(t, Vector3(3.0, 2.6, 4.2), Vector3.ZERO)


func _build_camp() -> void:
	camp = CampScript.new()
	camp.world = self
	stage_root.add_child(camp)
	camp.build(Game.stage_index, rng)
	camp_radius = camp.radius()
	if Game.stage_index < 2:
		camp.stand_cloud(float(stage.get("heading", 150.0)))
	plaza = camp.plaza

	# The main fire, in the middle of the gathering ground.
	var fire := Game.mesh_cyl(0.0, 0.5, 1.1, Color(1.0, 0.5, 0.1), 3.0)
	stage_root.add_child(fire)
	fire.global_position = plaza + Vector3(0, 0.55, 0)
	for i in 7:
		var st := Game.mesh_sphere(0.25, Color(0.35, 0.32, 0.3))
		stage_root.add_child(st)
		st.global_position = plaza + Vector3(sin(TAU * i / 7.0) * 0.85, 0.1, cos(TAU * i / 7.0) * 0.85)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.25)
	glow.light_energy = 2.0
	glow.omni_range = 9.0
	stage_root.add_child(glow)
	glow.global_position = plaza + Vector3(0, 1.4, 0)

	for i in 4:
		var jar := Game.mesh_cyl(0.28, 0.4, 0.9, Color(0.66, 0.42, 0.3))
		stage_root.add_child(jar)
		jar.global_position = plaza + Vector3(5.5 + (i % 2) * 0.9, 0.45, -4.5 + (i / 2) * 0.9)
	_water_jars = _interactable("", plaza + Vector3(6.0, 0.5, -4.0), 3.2, _use_water_jars)
	_refresh_water_jars()

	spawn_npc("Captain of the scouts", "captain", plaza + Vector3(0, 0, -8.0), Color(0.3, 0.38, 0.5))
	spawn_npc("Caravan trader", "merchant", plaza + Vector3(-8.5, 0, -3.5), Color(0.6, 0.3, 0.25))
	spawn_npc("Camp craftsman", "smith", plaza + Vector3(-8.5, 0, 2.5), Color(0.4, 0.35, 0.3))
	var anvil := Game.mesh_box(Vector3(0.9, 0.6, 0.6), Color(0.3, 0.3, 0.32))
	stage_root.add_child(anvil)
	anvil.global_position = plaza + Vector3(-10.2, 0.3, 2.5)
	_people()


## A point on the gathering ground, given relative to its middle.
func plaza_point(x: float, z: float) -> Vector3:
	return ground(plaza.x + x, plaza.z + z)


## The ordinary people of the camp: those sitting by the fire or at their work, and men,
## women and children on foot among the tents.
func _people() -> void:
	villagers = []
	var robes := [Color(0.72, 0.6, 0.42), Color(0.5, 0.42, 0.34), Color(0.62, 0.36, 0.26), Color(0.4, 0.42, 0.5),
		Color(0.8, 0.74, 0.6), Color(0.46, 0.48, 0.3), Color(0.56, 0.3, 0.32), Color(0.34, 0.36, 0.44)]
	for i in camp.spots.size():
		var s: Dictionary = camp.spots[i]
		var who: String = s["who"]
		var old := look_rng.randf() < 0.3
		var opts := {"solid": false, "sex": 0 if who == "man" else 1}
		if old:
			opts["hair_color"] = 4
		var n = spawn_npc(_title(who, opts["sex"], old), "villager", s["pos"], robes[i % robes.size()], opts)
		n.data = {"who": who, "work": s["work"]}
		n.face(s["look_at"])
		n.settle(str(s["pose"]), bool(s["seat"]))
		villagers.append(n)
	var walkers := ["man", "woman", "child", "man", "woman", "child", "man", "woman", "child", "man", "woman", "child"]
	for i in walkers.size():
		var start: int = camp.random_node(rng)
		if start < 0:
			break
		var who: String = walkers[i]
		var sex := look_rng.randi() % 2 if who == "child" else (0 if who == "man" else 1)
		var old := who != "child" and look_rng.randf() < 0.2
		var opts := {"solid": false, "sex": sex}
		var pace := look_rng.randf_range(1.1, 1.5)
		if who == "child":
			opts.merge({"scale": look_rng.randf_range(0.55, 0.68), "beard": 0, "head": 0, "outfit": 0})
			pace = look_rng.randf_range(1.9, 2.8)
		if old:
			opts["hair_color"] = 4
			pace *= 0.8
		var n = spawn_npc(_title(who, sex, old), "villager", camp.node_position(start), robes[(i + 3) % robes.size()], opts)
		n.data = {"who": who, "work": ""}
		n.start_walking(camp, start, pace, int(stage["seed"]) * 100 + i)
		villagers.append(n)


func _title(who: String, sex: int, old: bool) -> String:
	if who == "child":
		return "A girl" if sex == 1 else "A boy"
	if who == "woman":
		return "An old woman" if old else "A woman"
	return "An old man" if old else "A man"


## A villager says the next thing on their mind. They go through everything they have to say
## before repeating themselves.
func _talk(npc) -> void:
	var lines: Array = npc.data.get("lines", [])
	if lines.is_empty():
		lines = TalkScript.lines_for(Game.stage_index, str(npc.data["who"]), str(npc.data.get("work", "")))
		for i in range(lines.size() - 1, 0, -1):
			var j := Game.rng.randi() % (i + 1)
			var keep = lines[i]
			lines[i] = lines[j]
			lines[j] = keep
	var line: String = lines.pop_back()
	npc.data["lines"] = lines
	if not npc.settled:
		npc.face(player.global_position)
	hud.dialog(npc.npc_name, "\"%s\"" % line)


func _refresh_water_jars() -> void:
	_water_jars.label = "Fill your waterskin" if Game.camp_has_water else "The water jars are empty"


func _use_water_jars(_node) -> void:
	if Game.camp_has_water:
		Game.refill_water()
		Game.say("You drink deeply and fill your waterskin.")
	else:
		Game.say("The jars are dry. The camp needs water.")


func _palm(pos: Vector3) -> void:
	var trunk := Game.mesh_cyl(0.16, 0.24, 6.0, Color(0.45, 0.34, 0.22))
	stage_root.add_child(trunk)
	trunk.global_position = pos + Vector3(0, 3.0, 0)
	for i in 6:
		var leaf := Game.mesh_box(Vector3(0.5, 0.08, 2.8), Color(0.25, 0.5, 0.22))
		stage_root.add_child(leaf)
		leaf.global_position = pos + Vector3(0, 6.0, 0)
		leaf.rotation = Vector3(0.45, TAU * i / 6.0, 0)
		leaf.translate_object_local(Vector3(0, 0, -1.3))


func _site_label(text: String, pos: Vector3) -> void:
	var l := Game.label3d(text, 64, Color(1.0, 0.95, 0.8))
	stage_root.add_child(l)
	l.global_position = pos + Vector3(0, 5.0, 0)


func _site_spring(pos: Vector3, title: String) -> void:
	var pool := Game.mesh_cyl(5.0, 5.0, 0.16, Color(0.2, 0.5, 0.6), 0.25)
	stage_root.add_child(pool)
	pool.global_position = pos + Vector3(0, 0.25, 0)
	for i in 9:
		var a := TAU * i / 9.0
		var st := Game.mesh_sphere(rng.randf_range(0.5, 0.9), Color(0.5, 0.45, 0.4))
		stage_root.add_child(st)
		st.global_position = pos + Vector3(sin(a) * 5.3, 0.2, cos(a) * 5.3)
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		_palm(ground(pos.x + sin(a) * 8.0, pos.z + cos(a) * 8.0))
	_site_label(title, pos)


func _site_cairn(pos: Vector3, title: String) -> void:
	var y := 0.0
	for i in 5:
		var s := 1.6 - i * 0.26
		var st := Game.mesh_box(Vector3(s, 0.6, s), Color(0.5, 0.46, 0.42).darkened(i * 0.04))
		stage_root.add_child(st)
		st.global_position = pos + Vector3(0, y + 0.3, 0)
		st.rotation.y = i * 0.5
		y += 0.6
	_site_label(title, pos)


func _site_warcamp(pos: Vector3, title: String) -> void:
	for i in 3:
		var a := TAU * i / 3.0 + 1.0
		_tent(ground(pos.x + sin(a) * 9.0, pos.z + cos(a) * 9.0), a, Color(0.28, 0.2, 0.2))
	var pole := Game.mesh_cyl(0.07, 0.07, 6.0, Color(0.3, 0.22, 0.15))
	stage_root.add_child(pole)
	pole.global_position = pos + Vector3(0, 3.0, 0)
	var flag := Game.mesh_box(Vector3(1.6, 1.0, 0.05), Color(0.6, 0.1, 0.1))
	stage_root.add_child(flag)
	flag.global_position = pos + Vector3(0.85, 5.3, 0)
	_site_label(title, pos)


func _cage(pos: Vector3) -> void:
	var cage := Node3D.new()
	stage_root.add_child(cage)
	cage.global_position = pos
	for cx in [-0.9, 0.9]:
		for cz in [-0.9, 0.9]:
			var post := Game.mesh_cyl(0.07, 0.07, 2.2, Color(0.35, 0.25, 0.16))
			post.position = Vector3(cx, 1.1, cz)
			cage.add_child(post)
	var roof := Game.mesh_box(Vector3(2.1, 0.1, 2.1), Color(0.35, 0.25, 0.16))
	roof.position.y = 2.2
	cage.add_child(roof)
	var captive = spawn_npc("", "villager", pos, Color(0.7, 0.62, 0.5), {"solid": false, "scale": 0.9})
	var it = _interactable("Free the captive", pos + Vector3(0, 0.5, 0), 3.4, _free_captive)
	it.set_meta("cage", cage)
	it.set_meta("captive", captive)
	obj_nodes.append(it)


func _free_captive(it) -> void:
	it.enabled = false
	var cage: Node3D = it.get_meta("cage")
	var captive: Node3D = it.get_meta("captive")
	if is_instance_valid(cage):
		cage.queue_free()
	if is_instance_valid(captive):
		captive.queue_free()
	obj_count += 1
	Game.say("\"The LORD bless you!\"  Captives freed: %d/%d" % [obj_count, obj_need])
	if obj_count >= obj_need:
		_complete_objective()


func _spawn_wildlife() -> void:
	var wild: Dictionary = stage["wild"]
	var mult: float = float(stage["mult"])
	for kind in wild:
		for i in int(wild[kind]):
			var a := rng.randf() * TAU
			var r := rng.randf_range(camp_radius + 18.0, 195.0)
			spawn_enemy(str(kind), ground(sin(a) * r, cos(a) * r), mult)


func _spawn_guards(guards: Dictionary, cx: float, cz: float) -> void:
	var mult: float = float(stage["mult"])
	for kind in guards:
		for i in int(guards[kind]):
			var p := ground(cx + rng.randf_range(-10.0, 10.0), cz + rng.randf_range(-10.0, 10.0))
			spawn_enemy(str(kind), p, mult)


# ================================================================ main objectives

func _next_objective() -> void:
	obj_index += 1
	obj_nodes.clear()
	obj_count = 0
	_obj_closed = false
	var list: Array = stage["objectives"]
	if obj_index >= list.size():
		_finish_stage()
		return
	obj = list[obj_index]
	obj_need = int(obj.get("count", 1))
	var ang := rng.randf() * TAU
	if obj.has("bearing"):
		ang = PI - deg_to_rad(float(obj["bearing"]))      # bearings run clockwise from north; ang 0 is south
	var dist: float = float(obj.get("dist", 0.0))
	var cx := sin(ang) * dist
	var cz := cos(ang) * dist
	obj_pos = ground(cx, cz)
	var mult: float = float(stage["mult"])
	match str(obj["type"]):
		"reach":
			if str(obj.get("site", "cairn")) == "spring":
				_site_spring(obj_pos, str(obj["label"]))
			else:
				_site_cairn(obj_pos, str(obj["label"]))
		"collect":
			var spread: float = float(obj.get("spread", 28.0))
			for i in obj_need:
				var p := ground(cx + rng.randf_range(-spread, spread), cz + rng.randf_range(-spread, spread))
				spawn_pickup("objective", 0, p, str(obj["item"]), obj["color"])
		"boss":
			var names: Array = obj.get("names", [obj.get("boss", "Chief")])
			obj_need = names.size()
			_site_warcamp(obj_pos, "")
			for i in names.size():
				var p := ground(cx + (i - (names.size() - 1) * 0.5) * 5.0, cz + 3.0)
				var e = spawn_enemy("boss", p, mult, {
					"boss": true, "name": names[i],
					"scale": obj.get("scale", 1.35), "hp_mult": obj.get("hp_mult", 1.0), "drop": obj.get("drop", ""),
				})
				obj_nodes.append(e)
		"defend":
			raid.force(obj_need)
		"rescue":
			_site_warcamp(obj_pos, str(obj["label"]))
			for i in obj_need:
				_cage(ground(cx + (i - (obj_need - 1) * 0.5) * 5.0, cz - 5.0))
	_spawn_guards(obj.get("guards", {}), cx, cz)


func objective_text() -> String:
	if stage_done:
		return "The cloud has lifted. Follow the pillar of cloud when you are ready."
	var t := str(obj.get("text", ""))
	if obj_need > 1:
		t += "   %d/%d" % [obj_count, obj_need]
	return t


func on_objective_pickup() -> void:
	obj_count += 1
	if obj_count >= obj_need:
		_complete_objective()
	else:
		Game.say("%s  %d/%d" % [obj["item"], obj_count, obj_need])


func on_enemy_died(e) -> void:
	if not stage_done and str(obj.get("type", "")) == "boss" and obj_nodes.has(e):
		obj_count += 1
		if obj_count >= obj_need:
			_complete_objective()


func on_raid_cleared() -> void:
	if not stage_done and str(obj.get("type", "")) == "defend":
		obj_count += 1
		if obj_count >= obj_need:
			_complete_objective()


func _complete_objective() -> void:
	if _obj_closed:
		return
	_obj_closed = true
	match str(obj.get("unlock", "")):
		"water":
			Game.camp_has_water = true
			Game.refill_water()
			_refresh_water_jars()
		"workshop":
			Game.workshop = true
			camp.raise_tabernacle()
	var reward := int(25.0 * float(stage["mult"]))
	Game.silver += reward
	hud.dialog(str(obj["text"]), "%s\n\n[i]The camp gives you %d silver.[/i]" % [obj["done"], reward], [["Continue", _next_objective]])


func _finish_stage() -> void:
	stage_done = true
	raid.stopped = true
	obj = {}
	var ang := rng.randf() * TAU
	var pos := ground(sin(ang) * (camp_radius + 38.0), cos(ang) * (camp_radius + 38.0))
	camp.lift_cloud()
	var cloud = CloudScript.new()
	stage_root.add_child(cloud)
	cloud.global_position = pos
	cloud.build(155.0, 4.0, 11.5, 11)
	exit_node = _interactable("Follow the pillar of cloud", pos + Vector3(0, 0.5, 0), 9.0, _use_exit)
	Game.say("The cloud has lifted from the camp.")


func _use_exit(_node) -> void:
	hud.dialog("The cloud moves on", str(stage["outro"]), [["Journey on", _advance], ["Stay a while longer", Callable()]])


func _advance() -> void:
	if Game.stage_index >= Game.stage_count() - 1:
		hud.dialog("Forty years", "You were a %s when you crossed the sea. You have buried your parents in the wilderness and raised your children under the cloud.\n\nThe Jordan is in front of you.\n\n[i]Raids driven off: %d[/i]" % ["girl" if int(Game.look.get("sex", 0)) == 1 else "boy", Game.raids_survived],
			[["Begin a new journey", new_journey]])
		return
	Game.stage_index += 1
	load_stage()


func new_journey() -> void:
	Game.new_game()
	load_stage()


func quit_game() -> void:
	get_tree().quit()


# ================================================================ camp, death, markers

func damage_camp(amount: float) -> void:
	Game.camp_hp = maxf(0.0, Game.camp_hp - amount)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(raid) and not raid.active:
		Game.camp_hp = minf(100.0, Game.camp_hp + 2.0 * delta)
	if Game.camp_hp <= 0.0 and not _failing:
		_failing = true
		hud.dialog("The camp is overrun", "The raiders break through the tents before anyone can stop them.", [["Try this stage again", _retry]])
		return
	if not stage_done and not _obj_closed and str(obj.get("type", "")) == "reach":
		if player.global_position.distance_to(obj_pos) < 9.0:
			_complete_objective()


func _retry() -> void:
	Game.restore(snapshot)
	load_stage()


func on_player_died() -> void:
	var lost := int(Game.silver * 0.25)
	Game.silver -= lost
	hud.dialog("You fall", "Others find you and carry you back to the tents. Some of your silver is gone.\n\n[i]You lose %d silver.[/i]" % lost, [["Rise", _respawn]])


func _respawn() -> void:
	Game.hp = Game.max_hp * 0.6
	Game.thirst = maxf(Game.thirst, 60.0)
	player.revive(plaza_point(0.0, 10.0) + Vector3(0, 0.5, 0))


func get_markers() -> Array:
	var out: Array = []
	if not is_instance_valid(player):
		return out
	var gold := Color(1.0, 0.9, 0.55)
	if player.global_position.distance_to(camp_pos) > camp_radius + 12.0:
		out.append({"pos": camp_pos + Vector3(0, 4, 0), "text": "Camp", "color": Color(0.8, 0.95, 1.0)})
	if stage_done:
		if is_instance_valid(exit_node):
			out.append({"pos": exit_node.global_position + Vector3(0, 6, 0), "text": "Pillar of cloud", "color": Color.WHITE})
	else:
		match str(obj.get("type", "")):
			"reach", "collect", "rescue":
				out.append({"pos": obj_pos + Vector3(0, 4, 0), "text": str(obj.get("label", obj["text"])), "color": gold})
			"boss":
				for e in obj_nodes:
					if is_instance_valid(e) and not e.dead:
						out.append({"pos": e.global_position + Vector3(0, 4, 0), "text": e.display_name, "color": gold})
	if is_instance_valid(raid) and raid.active:
		out.append({"pos": raid.centroid() + Vector3(0, 3, 0), "text": "Raiders", "color": Color(1.0, 0.45, 0.35)})
	return out


## Everything the minimap marks: [{pos, kind}]. Kinds: camp, objective, exit, raider, wild, giver, item.
func get_map_points() -> Array:
	var out: Array = [{"pos": camp_pos, "kind": "camp"}]
	if stage_done:
		if is_instance_valid(exit_node):
			out.append({"pos": exit_node.global_position, "kind": "exit"})
	else:
		match str(obj.get("type", "")):
			"reach", "collect", "rescue":
				out.append({"pos": obj_pos, "kind": "objective"})
			"boss":
				for e in obj_nodes:
					if is_instance_valid(e) and not e.dead:
						out.append({"pos": e.global_position, "kind": "objective"})
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e.is_boss:
			out.append({"pos": e.global_position, "kind": "raider" if e.is_raider else "wild"})
	for p in get_tree().get_nodes_in_group("pickup"):
		if p.kind == "quest" or p.kind == "objective":
			out.append({"pos": p.global_position, "kind": "item"})
	if is_instance_valid(quests):
		for q in quests.list:
			if q["status"] == "new" or q["status"] == "ready":
				out.append({"pos": q["npc"].global_position, "kind": "giver"})
	return out


func npc_interact(npc) -> void:
	match str(npc.role):
		"giver":
			quests.talk_giver(npc.quest)
		"child":
			quests.talk_child(npc)
		"witness":
			quests.talk_witness(npc)
		"suspect":
			quests.talk_suspect(npc)
		"merchant":
			hud.open_shop()
		"smith":
			hud.open_smith()
		"villager":
			_talk(npc)
		"captain":
			var t := objective_text()
			if is_instance_valid(raid) and raid.active:
				t = "Raiders are on us. Get between them and the tents."
			hud.dialog(npc.npc_name, "%s\n\nThe people here have troubles of their own. Speak to anyone marked with a  !  and help where you can." % t)


# ================================================================ debug: screenshot and self-test

func _shot() -> void:
	if args.has("raid"):
		raid.start_raid()
	if args.has("tp"):
		var target := Vector3.ZERO
		var back := float(args.get("back", "14"))
		match str(args["tp"]):
			"obj":
				target = obj_pos
			"exit":
				target = exit_node.global_position
			"enemy":
				target = get_tree().get_nodes_in_group("enemy")[int(args.get("n", "0"))].global_position
			"raid":
				target = raid.centroid()
			_:
				var parts: PackedStringArray = str(args["tp"]).split(",")
				target = Vector3(float(parts[0]), 0, float(parts[1]))
				back = 0.0
		# Stand `back` metres short of the target, on the camp side, looking at it.
		var away := Vector3(target.x, 0, target.z).normalized() * back
		player.global_position = ground(target.x - away.x, target.z - away.z) + Vector3(0, 0.5, 0)
		if back > 0.0:
			player.yaw = atan2(-away.x, -away.z)
	if args.has("yaw"):
		player.yaw = deg_to_rad(float(args["yaw"]))
	if args.has("pitch"):
		player.pitch = deg_to_rad(float(args["pitch"]))
	if args.has("arm"):
		player._arm.spring_length = float(args["arm"])     # a long arm gives an overview from above
	for i in int(args.get("frames", "90")):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(str(args["shot"]))
	get_tree().quit()


func _finish_current_objective() -> void:
	match str(obj.get("type", "")):
		"boss":
			for e in obj_nodes.duplicate():
				if is_instance_valid(e):
					e.take_damage(1e9)
		"collect":
			for i in obj_need:
				on_objective_pickup()
		"defend":
			for i in obj_need:
				on_raid_cleared()
		"rescue":
			for it in obj_nodes.duplicate():
				if is_instance_valid(it):
					it.interact()
		"reach":
			_complete_objective()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _selftest() -> void:
	var fails: Array = []
	var check := func(ok: bool, what: String) -> void:
		if not ok:
			fails.append(what)
			print("FAIL  ", what)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Gear: buying, equipping, strengthening.
	check.call(is_equal_approx(Game.melee_power(), 12.0), "the staff starts at 12 damage")
	check.call(player.body.weapon_kind == "staff", "the player starts with the staff in hand")
	Game.silver = 1000
	Game.bronze = 50
	check.call(Game.try_buy("dagger"), "can buy a dagger")
	var dagger: Dictionary = Game.bag[Game.bag.size() - 1]
	Game.equip(dagger)
	check.call(is_equal_approx(Game.melee_power(), 18.0), "the dagger is equipped")
	check.call(player.body.weapon_kind == "dagger", "the equipped weapon shows in the hand")
	check.call(Game.bag.size() == 1 and Game.bag[0]["id"] == "staff", "the staff went back to the bag")
	check.call(Game.try_upgrade(dagger), "can strengthen the dagger")
	check.call(is_equal_approx(Game.melee_power(), 18.0 * 1.12), "+1 adds 12 percent")
	Game.try_upgrade(dagger)
	check.call(not Game.try_upgrade(dagger), "strengthening stops at +2 before the workshop")
	var before_sell := Game.silver
	Game.sell(Game.bag[0])
	check.call(Game.silver > before_sell and Game.bag.is_empty(), "can sell spare gear")
	check.call(Game.hurt_player(100.0) < 100.0, "armor blocks some damage")
	Game.hp = Game.max_hp

	# Figures and the character creator.
	var figures_ok := true
	for key in HumanScript.ORDER:
		var names: Array = HumanScript.OPTIONS[key]
		for v in names.size():
			for sex in 2:
				var l: Dictionary = Game.DEFAULT_LOOK.duplicate()
				l["sex"] = sex
				l[key] = v
				var fig = HumanScript.new()
				add_child(fig)
				fig.build(l)
				fig.set_weapon(["staff", "dagger", "sickle", "sword", "spear"][v % 5])
				fig.animate(0.016, 5.0)
				fig.swing()
				fig.whirl()
				if fig.skeleton == null or fig.weapon == null or fig.garments.size() < 4:
					figures_ok = false
				fig.queue_free()
	check.call(figures_ok, "every appearance option builds for both sexes")

	# The modelled character: clothes, hair, animation and how weapons are carried.
	var robed = HumanScript.new()
	add_child(robed)
	robed.build({"sex": 1, "brows": 1, "outfit": 2, "head": 0, "hair": 2})
	check.call(robed.garments.has("skirt_long") and robed.garments.has("cloak") and robed.garments.has("mantle"), "a robe and cloak is made of skirt, cloak and mantle")
	check.call(robed.head.get_child_count() == 1, "uncovered hair hangs on the head")
	robed.build({"sex": 1, "brows": 1, "outfit": 0, "head": 1, "hair": 2, "beard": 1})
	await get_tree().process_frame
	check.call(robed.head.get_child_count() == 0 and robed.garments.has("cap"), "a headcloth replaces the hair, and a woman gets no beard")
	check.call(not robed.garments.has("cloak") and robed.garments.has("skirt_short"), "a short tunic has no cloak")
	var anims: AnimationLibrary = HumanScript._libraries[1]
	check.call(anims.get_animation("Walk").loop_mode == Animation.LOOP_LINEAR and anims.get_animation("Sword_Attack").loop_mode == Animation.LOOP_NONE, "walk cycles loop and strikes do not")
	var bones: Skeleton3D = robed.skeleton
	var foot := bones.find_bone("foot_l")
	var standing: Vector3 = bones.get_bone_global_pose(foot).origin
	var foot_travel := 0.0
	for i in 20:
		robed.animate(0.05, 6.0)
		robed._tree.advance(0.05)
		foot_travel = maxf(foot_travel, bones.get_bone_global_pose(foot).origin.distance_to(standing))
	check.call(foot_travel > 0.25, "the legs move when the figure runs")
	robed.set_weapon("staff")
	var hand_idle: Basis = HumanScript.pose_basis(anims.get_animation("Idle"), bones, bones.find_bone("hand_r"), 0.0)
	check.call((hand_idle * robed.weapon.transform.basis).y.y > 0.95, "a staff is carried upright")
	robed.set_weapon("sword")
	var blade: Vector3 = (hand_idle * robed.weapon.transform.basis).y
	check.call(blade.z > 0.8 and blade.x < 0.0, "a sword at rest points forward and away from the body")
	robed.swing()
	check.call(not robed.weapon.transform.is_equal_approx(robed._carry), "a strike turns the weapon into the fist")
	robed.die()
	check.call(robed.dead, "a figure can fall")
	robed.queue_free()
	var probe := {"sex": 0, "beard": 1, "hair": 4}
	HumanScript.cycle(probe, "hair", 1)
	check.call(int(probe["hair"]) == 0, "options wrap round")
	HumanScript.cycle(probe, "sex", 1)
	check.call(int(probe["sex"]) == 1 and int(probe["beard"]) == 0, "choosing female clears the beard")
	Game.look["sex"] = 1
	Game.look["outfit"] = 1
	Game.look_changed.emit()
	check.call(int(player.body.look["sex"]) == 1 and player.body.garments.has("skirt_long"), "editing the look rebuilds the player figure")
	check.call(player.body.weapon_kind == "dagger", "the weapon stays in hand after a rebuild")
	Game.look = Game.DEFAULT_LOOK.duplicate()
	Game.look_changed.emit()
	check.call(quests.list[0]["npc"].figure.head != null, "camp people are human figures")

	# The creator panel itself, driven the way its buttons drive it.
	var creator_closed := [false]
	hud.auto = false
	hud.open_creator(func() -> void: creator_closed[0] = true)
	check.call(hud._creator.visible and get_tree().paused, "the creator opens and pauses the game")
	check.call(is_equal_approx(player._arm.spring_length, 2.9), "the camera moves in front of the figure")
	hud._creator_step("sex", 1)
	check.call(int(Game.look["sex"]) == 1 and hud._creator_values["sex"].text == "Female", "the Sex row switches to female")
	check.call(hud._creator_buttons["beard"][0].disabled, "the Beard row is locked for a woman")
	hud._creator_step("sex", 1)
	hud._creator_step("beard", 1)
	check.call(hud._creator_values["beard"].text == "Full" and int(player.body.look["beard"]) == 1, "the Beard row changes the figure")
	hud._creator_toggle_view()
	check.call(is_equal_approx(player._arm.spring_length, 0.85), "the face view moves the camera close")
	hud._creator_turn()
	hud._creator_random()
	check.call(int(Game.look["sex"]) == 0, "Randomize keeps the chosen sex")
	hud.close_creator()
	check.call(creator_closed[0] and Game.look_set and not get_tree().paused, "closing the creator resumes the game")
	check.call(is_equal_approx(player._arm.spring_length, player.ARM_LENGTH), "the camera returns behind the player")
	hud.auto = true
	Game.look = Game.DEFAULT_LOOK.duplicate()
	Game.look_changed.emit()

	# The land: real geography, seamless ground, scenery, and the two maps.
	check.call(RegionScript.elevation(RegionScript.to_km(28.539, 33.975)) > 2000.0, "the model puts Mount Sinai above 2000 m")
	check.call(RegionScript.sea_name(RegionScript.sea_at(RegionScript.to_km(31.4, 35.48))) == "Dead Sea", "the Dead Sea is where it should be")
	check.call(RegionScript.elevation(RegionScript.to_km(31.87, 35.44)) < -100.0, "Jericho lies below sea level")
	var seam := 0.0
	for i in terrain.size:
		var along: float = -terrain.HALF + i * terrain.CELL
		seam = maxf(seam, absf(terrain.heights[i] - terrain._far(along, -terrain.HALF)))
		seam = maxf(seam, absf(terrain.heights[i * terrain.size] - terrain._far(-terrain.HALF, along)))
	check.call(seam < 0.01, "the ground meets the backdrop without a step")
	var west_water := false
	for w in terrain.waters:
		var mid := Vector2.ZERO
		for p in w["outline"]:
			mid += p
		if mid.x / w["outline"].size() < 0.0 and float(w["y"]) < 0.0:
			west_water = true
	check.call(west_water, "at the first camp the Gulf of Suez lies to the west, below the camp")
	check.call(terrain.water_y(-285.0, 0.0) > -1e8 and terrain.water_y(-player.LIMIT, 0.0) < -1e8, "the shore is close by, just beyond where the scout can walk")
	check.call(obj_pos.x > 0.0 and obj_pos.z > 0.0, "Marah lies ahead to the south-east (%s)" % obj_pos)
	check.call(camp.guide != null and camp.guide.visible and camp.guide.position.z > 0.0, "the pillar of cloud stands by the camp on the way ahead")
	check.call(camp.guide.puffs > 150 and camp.guide.top > 130.0, "the pillar is a tall column of many billows (%d, %.0f m)" % [camp.guide.puffs, camp.guide.top])
	var all_years := true
	for st in Game.stage_count():
		if str(Game.Stages.LIST[st].get("year", "")) == "":
			all_years = false
	check.call(all_years and str(stage["year"]) == "Year 1", "every stage carries its year, and the first is Year 1")
	check.call(absf(terrain.surface_y(0.0, 0.0)) < 0.01 and absf(terrain.surface_y(8.0, -8.0)) < 0.05, "the camp stands on level ground")
	check.call(scenery.counts["grass"] > 200 and scenery.counts["bushes"] > 30 and scenery.counts["trees"] >= 3 and scenery.counts["rocks"] > 100,
		"the wilderness has grass, bushes, trees and rocks (%s)" % [scenery.counts])
	check.call(hud.minimap.has_picture(), "the minimap has a picture of the ground")
	var kinds := {}
	for m in get_map_points():
		kinds[m["kind"]] = true
	check.call(kinds.has("camp") and kinds.has("objective") and kinds.has("wild") and kinds.has("giver"), "the minimap marks the camp, the objective, wildlife and people needing help")
	check.call(hud.minimap.offset_of(Vector3(50, 0, 0), Vector3.ZERO).x > 0.0 and hud.minimap.offset_of(Vector3(0, 0, -50), Vector3.ZERO).y < 0.0, "on the minimap east is right and north is up")
	player.global_position = ground(0.0, 13.0) + Vector3(0, 0.2, 0)
	check.call(hud.minimap.coordinates().begins_with("29.60") or hud.minimap.coordinates().begins_with("29.61"), "the minimap reads the camp's latitude (%s)" % hud.minimap.coordinates())
	await get_tree().process_frame
	await get_tree().process_frame
	check.call(hud.minimap.draws > 0, "the minimap draws without errors")
	hud.auto = false
	hud.open_map()
	check.call(hud._map_panel.visible and get_tree().paused, "the region map opens")
	check.call(hud._region.route().size() == Game.stage_count() + 1, "the route passes through every camp")
	await get_tree().process_frame
	await get_tree().process_frame
	check.call(hud._region.draws > 0, "the region map draws without errors")
	hud.close_map()
	check.call(not hud._map_panel.visible and not get_tree().paused, "the region map closes")
	hud.auto = true

	# The camp: close-packed tents of several kinds, ways through it, and people at home in it.
	check.call(camp.tents.size() >= 40 and camp.kinds.size() >= 4, "the camp has many tents of several kinds (%d: %s)" % [camp.tents.size(), camp.kinds])
	var badly_placed := false
	var nearest_total := 0.0
	for i in camp.tents.size():
		var ti: Dictionary = camp.tents[i]
		var nearest := 1e9
		for j in camp.tents.size():
			if i != j:
				var tj: Dictionary = camp.tents[j]
				nearest = minf(nearest, (ti["pos"] as Vector2).distance_to(tj["pos"]) - float(ti["r"]) - float(tj["r"]))
		if nearest < camp.GAP - 0.01 or camp._reserved(ti["pos"], float(ti["r"])):
			badly_placed = true
		nearest_total += nearest
	check.call(not badly_placed, "no tent overlaps another or stands on the gathering ground")
	check.call(nearest_total / camp.tents.size() < 3.0, "the tents are pitched close together (%.1f m apart on average)" % (nearest_total / camp.tents.size()))
	print("tents stand %.1f m from their nearest neighbour on average" % (nearest_total / camp.tents.size()))
	check.call(camp.tabernacle == null and camp.plaza == Vector3.ZERO, "before Sinai there is no tabernacle and the fire is the middle of the camp")
	var linked := 0
	for i in camp.nodes.size():
		if camp.links[i].size() > 0:
			linked += 1
	check.call(linked > 40, "paths run through the camp (%d places, %d linked)" % [camp.nodes.size(), linked])
	var who_count := {}
	var seated := 0
	for v in villagers:
		who_count[v.data["who"]] = int(who_count.get(v.data["who"], 0)) + 1
		if v.settled:
			seated += 1
	check.call(int(who_count.get("man", 0)) >= 4 and int(who_count.get("woman", 0)) >= 4 and int(who_count.get("child", 0)) >= 3, "men, women and children live in the camp (%s)" % [who_count])
	check.call(seated == camp.spots.size() and seated >= 10, "people sit round the fire and kneel at their work (%d)" % seated)
	var sitter = villagers[1]
	var hips: float = sitter.figure.bone_position("pelvis").y
	check.call(sitter.figure.posed and hips < 0.75, "someone sitting by the fire has their hips low (%.2f m)" % hips)
	for v in villagers:
		if str(v.data["work"]) == "grind":
			var low := true
			for k in 12:
				v.figure._player.advance(0.5)
				if v.figure.bone_position("pelvis").y > 0.6:
					low = false
			check.call(low, "someone kneeling at work stays down")
	var works := {}
	for sp in camp.spots:
		works[sp["work"]] = true
	check.call(works.has("weave") and works.has("spin") and works.has("arms") and works.has("cook") and works.has("grind") and works.has("fire"), "people weave, spin, make weapons, grind and cook")
	var quote := char(34)
	var talker = villagers[villagers.size() - 1]
	var all_lines: Array = TalkScript.lines_for(0, str(talker.data["who"]))
	npc_interact(talker)
	var said: String = str(hud.last_dialog).trim_prefix(quote).trim_suffix(quote)
	check.call(all_lines.has(said), "a villager says something fitting the stage (%s)" % said)
	var heard := {said: true}
	for k in all_lines.size() - 1:
		npc_interact(talker)
		heard[hud.last_dialog] = true
	check.call(heard.size() == all_lines.size(), "a villager says everything once before repeating (%d of %d)" % [heard.size(), all_lines.size()])
	for v in villagers:
		if str(v.data["work"]) == "arms":
			npc_interact(v)
			var craft: String = str(hud.last_dialog).trim_prefix(quote).trim_suffix(quote)
			check.call(TalkScript.lines_for(0, "man", "arms").has(craft), "the weapon maker can be spoken to (%s)" % craft)
	var thin := ""
	for st in TalkScript.STAGES.size():
		for who in ["man", "woman", "child"]:
			if TalkScript.lines_for(st, who).size() < 12:
				thin += "%d/%s " % [st + 1, who]
	check.call(thin == "", "every stage has plenty for men, women and children to say %s" % thin)

	# World content.
	check.call(get_tree().get_nodes_in_group("enemy").size() == 18, "stage 1 wildlife spawned")
	check.call(player.global_position.y > -2.0 and player.global_position.y < 3.0, "the player stands on the ground")
	check.call(not Game.camp_has_water, "the camp starts stage 1 without water")

	# Combat and loot.
	var foe = spawn_enemy("raider", ground(30.0, 30.0), 1.0, {"drop": "linen"})
	check.call(foe._fig != null and foe._fig.weapon_kind == "sickle", "raiders are human figures holding a blade")
	foe.take_damage(10.0)
	check.call(not foe.dead and foe.hp < foe.max_hp, "an enemy takes damage")
	foe.take_damage(1e6)
	check.call(foe.dead, "an enemy dies")
	var found_item := false
	for p in get_tree().get_nodes_in_group("pickup"):
		if p.kind == "item" and str(p.payload) == "linen":
			found_item = true
			p.collect()
	check.call(found_item and Game.bag.size() == 1, "a forced drop can be picked up")

	# Real-time checks: the actual physics, input paths and AI, sped up six times.
	Engine.time_scale = 6.0
	raid.timer = 1e9
	var stood: Array = []
	for v in villagers:
		stood.append(v.global_position)
	await _wait(14.0)
	var walked := 0
	var through_tent := 0
	for i in villagers.size():
		var v = villagers[i]
		if v.settled:
			continue
		if v.global_position.distance_to(stood[i]) > 1.0:
			walked += 1
		for t in camp.tents:
			if Vector2(v.global_position.x, v.global_position.z).distance_to(t["pos"]) < float(t["r"]) * 0.5:
				through_tent += 1
	check.call(walked >= 8, "people walk about the camp (%d of 12 moved)" % walked)
	check.call(through_tent == 0, "nobody walks through a tent")
	var p0: Vector3 = ground(0.0, 13.0) + Vector3(0, 0.2, 0)
	player.global_position = p0
	player.yaw = PI          # face south, away from the tents
	player.pitch = -0.12
	await _wait(0.8)
	var dummy = spawn_enemy("boss", p0 + Vector3(0, 0, 2.2), 1.0)
	dummy.speed = 0.0
	dummy.dmg = 0.0
	player.melee()
	await _wait(0.6)
	check.call(is_equal_approx(dummy.hp, dummy.max_hp - Game.melee_power()), "a swing hits the enemy in front")
	await _wait(0.6)
	dummy.global_position = p0 + Vector3(-0.95, 0, 12.0)
	await _wait(0.3)
	var dummy_hp: float = dummy.hp
	player.sling()
	await _wait(1.2)
	check.call(is_equal_approx(dummy.hp, dummy_hp - Game.sling_power()), "a sling stone hits what the crosshair is on")
	player.yaw = 0.0
	player.melee()
	await _wait(0.6)
	check.call(is_equal_approx(dummy.hp, dummy_hp - Game.sling_power()), "a swing misses an enemy behind and far away")
	dummy.take_damage(1e9)

	var p1: Vector3 = ground(0.0, camp_radius + 30.0) + Vector3(0, 0.3, 0)   # outside the camp, so no resting
	player.global_position = p1
	await _wait(0.3)
	var silver0 := Game.silver
	spawn_pickup("silver", 5, player.global_position)
	await _wait(0.2)
	check.call(Game.silver == silver0 + 5, "walking over silver collects it")
	var thirst0 := Game.thirst
	var viper = spawn_enemy("snake", p1 + Vector3(1.0, 0, -1.0), 1.0)
	var hp0 := Game.hp
	await _wait(3.0)
	check.call(Game.hp < hp0, "an enemy beside the player bites")
	check.call(Game.thirst < thirst0, "thirst falls over time")
	var water0 := Game.water
	check.call(Game.drink() and Game.water == water0 - 1 and Game.thirst > thirst0 - 10.0, "drinking restores thirst")
	Game.hp = 0.5
	await _wait(3.0)
	check.call(not player.dead and Game.hp >= Game.max_hp * 0.5, "a fallen player is revived")
	check.call(player.global_position.distance_to(camp_pos) < 15.0, "the revived player is back in the camp")
	if is_instance_valid(viper):
		viper.take_damage(1e9)

	player.global_position = Vector3(-8.5, 0.2, -1.8)
	await _wait(0.3)
	check.call(player.focus != null and player.focus.role == "merchant", "standing by the trader offers the trade prompt")
	check.call(Game.prompt.begins_with("[E]"), "the prompt text is shown")
	player.focus.interact()
	check.call(hud.last_dialog.contains("silver"), "the trader opens the shop")

	# Side quests: accept all three (auto mode picks the first option).
	for q in quests.list:
		quests.talk_giver(q)
		check.call(q["status"] == "active", "quest accepted: %s" % q["title"])
	var silver_before := Game.silver
	var gather: Dictionary = quests.list[0]
	check.call(get_tree().get_nodes_in_group("pickup").size() >= int(gather["count"]), "gather items placed")
	for i in int(gather["count"]):
		quests.on_gather(0)
	check.call(gather["status"] == "ready", "gather quest is ready after collecting")
	quests.talk_giver(gather)
	check.call(gather["status"] == "done" and Game.silver > silver_before, "gather quest pays out")

	var lost: Dictionary = quests.list[1]
	var child = lost["child"]
	quests.talk_child(child)
	check.call(child.follow_target == player, "the lost child follows the player")
	child.global_position = lost["npc"].global_position + Vector3(2, 0, 2)
	await get_tree().process_frame
	await get_tree().process_frame
	check.call(lost["status"] == "ready", "the child reaching the parent readies the quest")
	var bag_before := Game.bag.size()
	quests.talk_giver(lost)
	check.call(lost["status"] == "done" and Game.bag.size() == bag_before + 1, "lost-child quest gives its item")

	var inv: Dictionary = quests.list[2]
	check.call(inv["nodes"].size() == 7, "investigation has 4 suspects and 3 witnesses")
	var culprits := 0
	for n in inv["nodes"]:
		if n.role == "suspect" and bool(n.data["culprit"]):
			culprits += 1
	check.call(culprits == 1, "exactly one culprit")
	quests.talk_suspect(inv["culprit"])
	check.call(inv["status"] == "done", "accusing the culprit closes the case")

	# Raids.
	raid.start_raid()
	check.call(raid.active and raid.raiders.size() == 3, "first raid has 3 raiders")
	player.global_position = ground(0.0, 150.0) + Vector3(0, 0.3, 0)
	Game.hp = 1e6
	await _wait(40.0)
	check.call(Game.camp_hp < 100.0, "raiders left alone reach the camp and damage it")
	check.call(Game.camp_hp > 0.0, "the camp holds for a while")
	Game.hp = Game.max_hp
	Engine.time_scale = 1.0
	for e in raid.raiders.duplicate():
		e.take_damage(1e9)
	await get_tree().process_frame
	await get_tree().process_frame
	check.call(not raid.active and raid.cleared == 1 and Game.raids_survived == 1, "a raid is counted as driven off")
	raid.start_raid()
	check.call(raid.raiders.size() == 3, "second raid size")
	raid.count = 5
	raid.start_raid()
	check.call(raid.raiders.size() > 6, "later raids are larger")
	Game.camp_hp = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check.call(Game.camp_hp >= 100.0 and Game.stage_index == 0, "a fallen camp restarts the stage")

	# Every stage builds and can be completed.
	for i in Game.stage_count():
		Game.stage_index = i
		var load_started := Time.get_ticks_msec()
		load_stage()
		print("stage %2d built in %4d ms   tents %d %s   paths %d   people %d" % [i + 1, Time.get_ticks_msec() - load_started, camp.tents.size(), camp.kinds, camp.nodes.size(), villagers.size()])
		if i == 2:
			check.call(camp.tabernacle == null and camp.has_court, "at Sinai the ground for the tabernacle is marked out but it is not yet raised")
		if i == 3:
			check.call(camp.tabernacle != null and camp.cloud.visible and absf(camp.COURT.x - 45.7) < 0.01 and absf(camp.COURT.y - 22.85) < 0.01,
				"from Paran on the tabernacle stands under the cloud, its court 100 by 50 cubits")
			var in_court := 0
			for v in villagers:
				if absf(v.global_position.x) < camp.COURT.x * 0.5 and absf(v.global_position.z) < camp.COURT.y * 0.5:
					in_court += 1
			check.call(in_court == 0 and camp.plaza.z > 20.0, "the gathering ground lies south of the court and nobody stands inside it")
		await get_tree().physics_frame
		await get_tree().process_frame
		var steps := 0
		while not stage_done and steps < 8:
			_finish_current_objective()
			steps += 1
			await get_tree().process_frame
		check.call(stage_done, "stage %d can be completed" % (i + 1))
		check.call(is_instance_valid(exit_node), "stage %d shows the pillar of cloud" % (i + 1))
		if i == 0:
			check.call(Game.camp_has_water, "finding Marah fills the camp jars")
			check.call(not camp.guide.visible, "the pillar of cloud moves on from the first camp when the stage is done")
		if i == 1:
			check.call(camp.tabernacle == null and camp.guide != null, "at Rephidim there is still no tabernacle, only the cloud")
		if i >= 3:
			check.call(not camp.cloud.visible, "stage %d: the cloud lifts from the tent when it is time to set out" % (i + 1))
		if i == 2:
			check.call(Game.max_plus() == 5, "the workshop unlocks +5")
			check.call(camp.tabernacle != null, "the tabernacle is raised at Sinai once the wood is in")
			var peak := 0.0
			var peak_at := Vector2.ZERO
			for kx in range(-14, 15):
				for kz in range(-14, 15):
					var y: float = terrain.surface_y(kx * 50.0, kz * 50.0)
					if y > peak:
						peak = y
						peak_at = Vector2(kx * 50.0, kz * 50.0)
			check.call(peak > 25.0 and peak_at.x > 0.0 and peak_at.y > 0.0, "at Sinai a mountain stands to the south-east of the camp (%.0f m high at %s)" % [peak, peak_at])
		if i == 7:
			var south_sea := false
			for w in terrain.waters:
				if str(w["name"]) == "Gulf of Aqaba":
					south_sea = true
			check.call(south_sea, "near Elath the Gulf of Aqaba is in view")
		if i == 8:
			var deep := 0.0
			for w in terrain.waters:
				if str(w["name"]) == "Dead Sea":
					deep = float(w["y"])
			check.call(deep < -40.0, "from Moab the Dead Sea lies far below (%.0f m)" % deep)
	exit_node.interact()
	check.call(Game.stage_index == 0 and not stage_done, "the ending starts a new journey")

	# Stage flow and save file.
	Game.stage_index = 1
	load_stage()
	_finish_current_objective()
	_finish_current_objective()
	exit_node.interact()
	check.call(Game.stage_index == 2, "the pillar of cloud leads to the next stage")
	Game.silver = 77
	Game.look["hair"] = 3
	Game.look["sex"] = 1
	Game.look_set = true
	Game.save_game()
	Game.new_game()
	check.call(not Game.look_set and int(Game.look["hair"]) == 0, "a new journey resets the look")
	check.call(Game.load_game() and Game.stage_index == 2 and Game.silver == 77, "save and load round-trip")
	check.call(Game.look_set and int(Game.look["hair"]) == 3 and int(Game.look["sex"]) == 1, "the look is saved with the game")

	print("SELFTEST %s  (%d failed)" % ["OK" if fails.is_empty() else "FAILED", fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)
