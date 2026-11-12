extends Node3D
## Builds and runs one stage: terrain, camp, main objectives, raids and side quests.
##
## Debug arguments (after `--` on the command line):
##   --selftest             run the logic checks without a window and exit 0 or 1
##   --stage=N              start a throwaway game at stage N
##   --auto                 never show dialogs (each picks its first option)
##   --shot=PATH            save a screenshot to PATH and exit
##   --frames=N --yaw=DEG --pitch=DEG   screenshot timing and camera
##   --tp=X,Z | obj | exit | enemy | raid   move the player there first (--back=M metres short)
##   --raid                 start a raid at once
##   --finish               complete the stage's objectives at once
##   --skip=N               complete the first N objectives
##   --rich                 start with silver, bronze and a spare dagger
##   --menu=shop|smith|gear|pause|creator   open that menu (--face and --turn=N for the creator)
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

const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]

var hud
var player
var terrain
var raid
var quests
var stage := {}
var stage_root: Node3D
var rng := RandomNumberGenerator.new()
var look_rng := RandomNumberGenerator.new()   # appearance of camp people; separate so it never shifts the layout
var camp_pos := Vector3.ZERO
var camp_radius := 24.0
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
	env.fog_density = 0.003
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
	terrain.setup(int(stage["seed"]), stage["sand"])
	_build_camp()
	_scatter_props()

	player = PlayerScript.new()
	player.world = self
	stage_root.add_child(player)
	player.global_position = ground(0.0, 13.0) + Vector3(0, 0.5, 0)

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
	# Face the middle of the camp.
	n.rotation.y = atan2(pos.x, pos.z)
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
	var cloths := [Color(0.86, 0.8, 0.68), Color(0.62, 0.46, 0.33), Color(0.76, 0.63, 0.46), Color(0.5, 0.38, 0.3)]
	for i in 12:
		var ang := TAU * i / 12.0 + 0.26
		var r := 21.0 + rng.randf_range(-1.0, 2.5)
		if cos(ang) > 0.8:
			continue   # leave the south side open, where the player enters
		_tent(ground(sin(ang) * r, cos(ang) * r), ang, cloths[i % cloths.size()])

	var fire := Game.mesh_cyl(0.0, 0.5, 1.1, Color(1.0, 0.5, 0.1), 3.0)
	stage_root.add_child(fire)
	fire.global_position = Vector3(0, 0.55, 0)
	for i in 7:
		var st := Game.mesh_sphere(0.25, Color(0.35, 0.32, 0.3))
		stage_root.add_child(st)
		st.global_position = Vector3(sin(TAU * i / 7.0) * 0.85, 0.1, cos(TAU * i / 7.0) * 0.85)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.25)
	glow.light_energy = 2.0
	glow.omni_range = 9.0
	stage_root.add_child(glow)
	glow.global_position = Vector3(0, 1.4, 0)

	for i in 4:
		var jar := Game.mesh_cyl(0.28, 0.4, 0.9, Color(0.66, 0.42, 0.3))
		stage_root.add_child(jar)
		jar.global_position = Vector3(5.5 + (i % 2) * 0.9, 0.45, -4.5 + (i / 2) * 0.9)
	_water_jars = _interactable("", Vector3(6.0, 0.5, -4.0), 3.2, _use_water_jars)
	_refresh_water_jars()

	spawn_npc("Captain of the scouts", "captain", Vector3(0, 0, -8.0), Color(0.3, 0.38, 0.5))
	spawn_npc("Caravan trader", "merchant", Vector3(-8.5, 0, -3.5), Color(0.6, 0.3, 0.25))
	spawn_npc("Camp craftsman", "smith", Vector3(-8.5, 0, 2.5), Color(0.4, 0.35, 0.3))
	var anvil := Game.mesh_box(Vector3(0.9, 0.6, 0.6), Color(0.3, 0.3, 0.32))
	stage_root.add_child(anvil)
	anvil.global_position = Vector3(-10.2, 0.3, 2.5)
	var robes := [Color(0.7, 0.62, 0.5), Color(0.55, 0.5, 0.42), Color(0.72, 0.55, 0.42), Color(0.5, 0.45, 0.5)]
	for i in 8:
		var a := rng.randf_range(0.8, TAU - 0.8)   # keep clear of the south side, where the player enters
		var r := rng.randf_range(9.0, 15.0)
		spawn_npc("", "villager", Vector3(sin(a) * r, 0, cos(a) * r), robes[i % robes.size()], {"solid": false})


func _refresh_water_jars() -> void:
	_water_jars.label = "Fill your waterskin" if Game.camp_has_water else "The water jars are empty"


func _use_water_jars(_node) -> void:
	if Game.camp_has_water:
		Game.refill_water()
		Game.say("You drink deeply and fill your waterskin.")
	else:
		Game.say("The jars are dry. The camp needs water.")


func _scatter_props() -> void:
	var rock: Color = stage["rock"]
	for i in 110:
		var a := rng.randf() * TAU
		var r := rng.randf_range(36.0, 240.0)
		var s := rng.randf_range(0.6, 3.4)
		var size := Vector3(s * rng.randf_range(0.8, 1.6), s * rng.randf_range(0.5, 1.1), s * rng.randf_range(0.8, 1.6))
		var m := Game.mesh_box(size, rock.darkened(rng.randf_range(0.0, 0.25)))
		stage_root.add_child(m)
		m.global_position = ground(sin(a) * r, cos(a) * r) + Vector3(0, size.y * 0.3, 0)
		m.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		if s > 1.7:
			_solid_box(m, size, Vector3.ZERO)
	for i in 55:
		var a := rng.randf() * TAU
		var r := rng.randf_range(34.0, 230.0)
		_shrub(ground(sin(a) * r, cos(a) * r), rng.randf_range(0.7, 1.5))


func _shrub(pos: Vector3, s: float) -> void:
	var trunk := Game.mesh_cyl(0.07 * s, 0.11 * s, 1.5 * s, Color(0.36, 0.26, 0.18))
	stage_root.add_child(trunk)
	trunk.global_position = pos + Vector3(0, 0.75 * s, 0)
	var crown := Game.mesh_sphere(1.0 * s, Color(0.42, 0.5, 0.28))
	crown.scale = Vector3(1.0, 0.4, 1.0)
	stage_root.add_child(crown)
	crown.global_position = pos + Vector3(0, 1.6 * s, 0)


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
			var r := rng.randf_range(48.0, 195.0)
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
	var reward := int(25.0 * float(stage["mult"]))
	Game.silver += reward
	hud.dialog(str(obj["text"]), "%s\n\n[i]The camp gives you %d silver.[/i]" % [obj["done"], reward], [["Continue", _next_objective]])


func _finish_stage() -> void:
	stage_done = true
	raid.stopped = true
	obj = {}
	var ang := rng.randf() * TAU
	var pos := ground(sin(ang) * 60.0, cos(ang) * 60.0)
	var cloud := Game.mesh_cyl(8.0, 4.0, 160.0, Color(0.97, 0.97, 0.95), 0.4, 0.55)
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage_root.add_child(cloud)
	cloud.global_position = pos + Vector3(0, 80.0, 0)
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
	player.revive(ground(0.0, 10.0) + Vector3(0, 0.5, 0))


func get_markers() -> Array:
	var out: Array = []
	if not is_instance_valid(player):
		return out
	var gold := Color(1.0, 0.9, 0.55)
	if player.global_position.distance_to(camp_pos) > 45.0:
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

	var p1: Vector3 = ground(0.0, 42.0) + Vector3(0, 0.3, 0)   # outside the camp, so no resting
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
		load_stage()
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
		if i == 2:
			check.call(Game.max_plus() == 5, "the workshop unlocks +5")
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
