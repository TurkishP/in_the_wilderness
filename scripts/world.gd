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
##   --menu=shop|trade|smith|gear|chest|lid|settings|pause|saves|how|scout|creator|map   open that menu
##                          (scout with --level=N: as a scout of that level)
##                          (--face and --turn=N for the creator; lid: the chest open, no screen)
##   --look=sex:1,hair:2    set the player's appearance
##   --equip=ID,ID          put on gear (--arrows=N adds arrows)
##   --aim=sling|bow        hold the sling going round, or the bow drawn (screenshots)
##   --blow=N --view=DEG    strike N blows of the combo and stop in the middle of the last one,
##                          with the camera swung DEG round the figure (screenshots)
##   --tip=N                point at the Nth thing in the bag to show what it does (screenshots)
##   --home                 start inside the scout's own tent
##   --hour=H               set the hour of the day (0-24) for a picture: --hour=18.2 is sunset
##   --title                show the title screen (with --shot: a picture of it; --pick=new|load|saves
##                          presses that button first)
##   --wind=KIND [--at=F]   a gust of dust wind of that kind (weather.gd), F of the way through
##   --clean --sun=ELEV,AZ  no interface or player, and a low warm sun, for pictures
##   --sheathe              start with the weapon put away

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
const EffectsScript := preload("res://scripts/effects.gd")
const DaylightScript := preload("res://scripts/daylight.gd")
const UiScript := preload("res://scripts/ui.gd")
const RegionScript := preload("res://data/region.gd")
const CampScript := preload("res://scripts/camp.gd")
const CloudScript := preload("res://scripts/cloud_pillar.gd")
const TalkScript := preload("res://data/talk.gd")
const HomeScript := preload("res://scripts/home.gd")
const CreatureScript := preload("res://scripts/creature.gd")
const TitleScript := preload("res://scripts/title.gd")
const WeatherScript := preload("res://scripts/weather.gd")
const EncounterScript := preload("res://scripts/encounters.gd")
const PlacesScript := preload("res://scripts/places.gd")
## The inside of the scout's tent stands here, far from the stage and high above it.
const HOME_AT := Vector3(1500.0, 900.0, 1500.0)

const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
const CUP := 40.0          # thirst a cup of water quenches

var hud
var player
var terrain
var scenery
var raid
var encounters                    # meetings out in the wilds (encounters.gd)
var places                        # the land's special places (places.gd)
var walk_limit := 205.0           # how far from the middle the scout may walk (a place may widen it)
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
var home                          # the inside of the scout's own tent (home.gd)
var water_spots: Array = []       # the barrels and cups about the camp
var stone_spots: Array = []       # stony patches where sling stones can be picked up
var environment: Environment      # the sky, light and haze (the dust wind thickens the haze)
var sun: DirectionalLight3D
var sun_angles := Vector3.ZERO
var weather                       # the dust wind (weather.gd)
var fx                            # dust, hit bursts and the hit pause (effects.gd)
var daylight                      # the sun, the moon and the light of the hour (daylight.gd)
var title                         # the title screen while it shows (title.gd)


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
	fx = EffectsScript.new()
	fx.world = self
	add_child(fx)
	daylight = DaylightScript.new()
	daylight.world = self
	add_child(daylight)
	weather = WeatherScript.new()
	add_child(weather)
	weather.setup(self)

	Game.new_game()
	if args.has("selftest"):
		Game.save_dir = "user://selftest_saves"
		Game.save_path = "user://selftest_save.json"
		Game.clear_saves()
		load_stage()
		_selftest()
		return
	# A normal start shows the title screen; debug runs go straight in.
	if args.has("title") or not (args.has("stage") or args.has("auto") or args.has("shot")):
		_show_title()
		if args.has("shot"):
			for i in int(args.get("frames", "120")):
				await get_tree().process_frame
				if i == 30 and args.has("pick") and title != null:
					# --pick=new or --pick=load: press that button, then go on taking the picture
					if str(args["pick"]) == "saves":
						title._saves()
					else:
						title._choose(str(args["pick"]) == "load")
			get_viewport().get_texture().get_image().save_png(str(args["shot"]))
			get_tree().quit()
		return
	if args.has("stage"):
		Game.save_dir = "user://debug_saves"
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
		# --equip=bronze_spear,hide_shield  puts these on (debug)
		for id in str(args["equip"]).split(","):
			var inst := Game.add_item(id)
			if not inst.is_empty():
				Game.equip(inst)
		if args.has("arrows"):
			Game.take_ammo("arrows", int(args["arrows"]))
	if args.has("battle"):
		# --battle: in battle mode from the start (debug)
		player.set_battle(true, false)
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
		"trade":
			hud.open_shop()
		"chest", "lid":
			# --menu=lid stands at the chest with the lid open, without the chest screen
			enter_home()
			Game.place(Game.chest, Game.chest_grid(), Game.new_item("bronze_shield"))
			Game.place(Game.chest, Game.chest_grid(), Game.new_item("stones", 0, 25))
			player.global_position = home.chest.global_position + home.chest.global_basis.z * 1.9 + Vector3(0, 0.3, 0)
			if str(args["menu"]) == "lid":
				var to: Vector3 = home.chest.global_position - player.global_position
				player.yaw = atan2(-to.x, -to.z)
				player.pitch = -0.35
				home.open_lid(true)
			else:
				_open_chest()
		"settings":
			hud.open_settings()
		"pause":
			hud.open_pause()
		"saves", "how", "scout", "skills":
			if str(args["menu"]) == "skills":
				# --menu=skills: a scout who has used the staff and the sling a while
				Game.skill_xp = {"staff": Game.Skills.xp_for_step(4) + 30, "sling": Game.Skills.xp_for_step(2) + 12, "sword": 9}
				Game.skill_points = {"staff": 2, "sling": 2}
				Game.perks = {"walking_staff": true, "drive_back": true}
			if args.has("level"):
				# --level=N: as a scout of that level would look, with points still to spend
				Game.level = int(args["level"])
				Game.xp = Game.xp_needed(Game.level) * 2 / 5
				Game.stat_points = 4
				Game.stats = {"str": 6, "dex": 4, "int": 3, "luck": 2}
			hud.menu.open(str(args["menu"]))
			if args.has("hover"):
				# --hover=stomp: the Skills page as if the mouse were over that skill
				for c in hud.menu._page.get_children():
					if c.has_method("node_at"):
						c._hover = str(args["hover"])
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
	environment = env
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = bool(Game.settings["shadows"])
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
	Game.settings_changed.connect(func() -> void: sun.shadow_enabled = bool(Game.settings["shadows"]))
	sun_angles = sun.rotation_degrees


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
	# A save made in the tent picks the stage up where it was left. Trying a stage again after
	# the camp falls goes back to the same point. The game is not saved here: only in the tent.
	var resume: Dictionary = Game.resume
	Game.resume = {}
	# Walking back into an earlier land (Game.visiting), or coming back from one, keeps the
	# scout's health, thirst and water as they are; only a new stage starts them afresh.
	var away := Game.visiting >= 0
	if not away and not bool(resume.get("returning", false)):
		Game.begin_stage()
	if not away:
		snapshot = Game.snapshot()
		snapshot["resume"] = resume
	stage_done = false
	exit_node = null
	_failing = false
	obj_index = -1

	terrain = TerrainScript.new()
	stage_root.add_child(terrain)
	walk_limit = PlayerScript.LIMIT
	places = PlacesScript.new()
	places.world = self
	terrain.setup(stage, places.plan)
	# Each stage has a prevailing wind, mostly from the north-west, that the gusts blow near.
	weather.reset(0.785 + (int(stage["seed"]) % 7 - 3) * 0.12)
	if away:
		_build_old_camp()
	else:
		_build_camp()
	scenery = SceneryScript.new()
	stage_root.add_child(scenery)
	scenery.avoid = places.keep_clear()
	scenery.build(stage, rng, terrain, camp_radius + 8.0)
	fx.sand = stage["sand"]
	if args.has("hour"):
		Game.clock = clampf(float(args["hour"]), 0.0, 23.99)
	hud.show_stage(terrain)

	player = PlayerScript.new()
	player.world = self
	stage_root.add_child(player)
	player.global_position = plaza_point(0.0, 13.0) + Vector3(0, 0.5, 0)

	_spawn_wildlife()
	stage_root.add_child(places)
	places.build()
	if args.has("place"):
		_go_to_place(str(args["place"]))
	quests = null
	raid = null
	if not away:
		quests = QuestScript.new()
		quests.world = self
		stage_root.add_child(quests)
		quests.setup(stage["quests"])
		raid = RaidScript.new()
		raid.world = self
		stage_root.add_child(raid)
		raid.setup(stage["raid"])
	encounters = EncounterScript.new()
	encounters.world = self
	stage_root.add_child(encounters)
	encounters.setup()
	if args.has("encounter"):
		# Debug: --encounter=wolf (or lion, Edomite, band, caravan...) meets it straight away.
		encounters.start.call_deferred(str(args["encounter"]), true)
	_scatter_stones()

	if away:
		obj = {}
		Game.say("You have walked back to %s. Go back to the camp from the map (M)." % stage["place"])
		return
	if resume.is_empty():
		_next_objective()
	else:
		_resume_stage(resume)
		return

	# A new journey starts in the character creator; the stage introduction follows it. Each
	# stage is introduced once: begun again (the camp fell), it only names itself. The
	# introduction can be read again in the menu, under The Journey.
	if not Game.look_set:
		hud.open_creator(_show_intro)
	elif Game.intro_seen < Game.stage_index:
		_show_intro()
	else:
		Game.say("Stage %d:  %s" % [Game.stage_index + 1, stage["name"]])


## Picks a saved stage up again: the objectives already done count as done (their effects on
## the camp included, without paying again), and the scout wakes in the tent.
func _resume_stage(resume: Dictionary) -> void:
	var list: Array = stage["objectives"]
	var done := clampi(int(resume.get("obj_done", 0)), 0, list.size())
	for i in done:
		match str(list[i].get("unlock", "")):
			"water":
				Game.camp_has_water = true
			"workshop":
				Game.workshop = true
				if camp.tabernacle == null:
					camp.raise_tabernacle()
	_refresh_water_jars()
	obj_index = done - 1
	_next_objective()
	if bool(resume.get("returning", false)):
		# Back from an earlier land: the side quests already finished stay finished, and the
		# scout comes in at the camp's edge (or, carried back after falling, wakes in the tent).
		for i in resume.get("quests_done", []):
			if int(i) < quests.list.size():
				quests.list[int(i)]["status"] = "done"
				quests.list[int(i)]["npc"].set_mark("")
		if bool(resume.get("to_tent", false)):
			enter_home()
		Game.say("Back in the camp.")
		return
	Game.hp = clampf(float(resume.get("hp", Game.max_hp)), 1.0, Game.max_hp)
	Game.thirst = clampf(float(resume.get("thirst", 100.0)), 0.0, 100.0)
	Game.water = clampi(int(resume.get("water", Game.max_water)), 0, Game.max_water)
	enter_home()
	hud.dialog("Stage %d:  %s" % [Game.stage_index + 1, stage["name"]], "[i]%s  (%s)[/i]\n\nYou wake in your tent.\n\n%s" % [stage["place"], stage["ref"], objective_text()], [["Get up", Callable()]])


func _show_intro() -> void:
	Game.intro_seen = maxi(Game.intro_seen, Game.stage_index)
	var intro := "[i]%s  (%s)\n%s[/i]\n\n%s" % [stage["place"], stage["ref"], stage["when"], stage["intro"]]
	hud.dialog("Stage %d:  %s" % [Game.stage_index + 1, stage["name"]], intro, [["Set out", Callable()]])


# ================================================================ walking back to earlier lands

## True when the scout may set out for an earlier stage's land: in the camp, with a stage behind,
## and no raid or fight on.
func can_travel_back() -> bool:
	if Game.visiting >= 0 or Game.stage_index <= 0 or player.indoors or player.dead or player.in_fight():
		return false
	if is_instance_valid(raid) and raid.active:
		return false
	var p: Vector3 = player.global_position
	return Vector2(p.x - camp_pos.x, p.z - camp_pos.z).length() < camp_radius + 6.0


## Debug: --place=elim stands the scout a little way off a place of this land, looking at it.
func _go_to_place(id: String) -> void:
	for e in places.list:
		if str(e["def"]["id"]) == id:
			var at: Vector3 = e["at"]
			var off: Vector3 = -(e["dir"] as Vector3) * (18.0 + float(e["def"].get("radius", 14.0)) * 0.6)
			player.global_position = ground(at.x + off.x, at.z + off.z) + Vector3(0, 0.6, 0)
			var to: Vector3 = at - player.global_position
			player.yaw = atan2(-to.x, -to.z)
			Game.places_seen[id] = true


## Walks back into the land of earlier stage `i`. How far the current stage has got is kept, and
## it is picked up again on the return.
func travel_back(i: int) -> void:
	if i < 0 or i >= Game.stage_index or not can_travel_back():
		return
	var done: Array = []
	if is_instance_valid(quests):
		for q in quests.list:
			if q["status"] == "done":
				done.append(int(q["index"]))
	Game.away_from = {"obj_done": obj_index, "quests_done": done}
	Game.visiting = i
	load_stage()


## Back to the camp from an earlier land, from anywhere outside a fight. `to_tent`: carried back
## after falling, the scout wakes in the tent.
func return_to_camp(to_tent: bool = false) -> void:
	if Game.visiting < 0:
		return
	Game.visiting = -1
	Game.resume = Game.away_from.duplicate()
	Game.resume["returning"] = true
	Game.resume["to_tent"] = to_tent
	Game.away_from = {}
	load_stage()


## Where the camp stood when Israel was here. The tents have gone; cold fire rings, the ash of
## the cooking fires and, once there was a tabernacle, the stake holes of its court are left.
func _build_old_camp() -> void:
	camp = null
	camp_pos = Vector3.ZERO
	camp_radius = 48.0
	plaza = ground(0.0, 0.0)
	villagers = []
	water_spots = []
	var orng := RandomNumberGenerator.new()
	orng.seed = int(stage["seed"]) * 7 + 1
	for i in 16:
		var a := orng.randf() * TAU
		var r := orng.randf_range(5.0, 42.0)
		var at := ground(sin(a) * r, cos(a) * r)
		var ash := Game.mesh_cyl(0.55, 0.6, 0.03, Color(0.2, 0.18, 0.17))
		stage_root.add_child(ash)
		ash.global_position = at + Vector3(0, 0.015, 0)
		for k in 6:
			var st := Game.mesh_sphere(0.13, Color(0.33, 0.3, 0.28), "stone")
			stage_root.add_child(st)
			st.global_position = at + Vector3(sin(TAU * k / 6.0) * 0.62, 0.06, cos(TAU * k / 6.0) * 0.62)
	if Game.visiting >= 2:
		var hx := CampScript.COURT.x * 0.5
		var hz := CampScript.COURT.y * 0.5
		var x := -hx
		while x <= hx:
			for z in [-hz, hz]:
				_stake_hole(Vector3(x, 0.0, z - 22.0))
			x += 2.5
		var z2 := -hz
		while z2 <= hz:
			for x2 in [-hx, hx]:
				_stake_hole(Vector3(x2, 0.0, z2 - 22.0))
			z2 += 2.5


func _stake_hole(at: Vector3) -> void:
	var hole := Game.mesh_cyl(0.07, 0.07, 0.04, Color(0.16, 0.13, 0.11))
	stage_root.add_child(hole)
	hole.global_position = ground(at.x, at.z) + Vector3(0, 0.01, 0)


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.surface_y(x, z), z)


## Compass name for a direction on the map. North is -Z, east is +X.
func compass(x: float, z: float) -> String:
	var i := int(round(atan2(x, -z) / (TAU / 8.0)))
	return COMPASS[posmod(i, 8)]


func spawn_enemy(kind: String, pos: Vector3, mult: float, opts: Dictionary = {}):
	var o := opts.duplicate()
	if not o.has("people"):
		o["people"] = str(stage.get("foe", "Desert"))
	if not o.has("tier"):
		o["tier"] = int(stage["tier"])
	var e = EnemyScript.new()
	e.world = self
	e.setup(kind, mult, o)
	stage_root.add_child(e)
	if scenery != null:
		pos = scenery.clear_of(pos, float(e.radius) + 0.3)
		pos.y = maxf(pos.y, terrain.surface_y(pos.x, pos.z))
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
	if scenery != null:
		pos = scenery.clear_of(pos)
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
	var bs := BoxShape3D.new()
	bs.size = size
	_solid_shape(node, bs, offset)


## Makes `node` solid with `shape`, its middle `offset` from the node: walked round, stood on.
func _solid_shape(node: Node3D, shape: Shape3D, offset: Vector3 = Vector3.ZERO) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	sb.add_child(cs)
	node.add_child(sb)


func _solid_pole(node: Node3D, radius: float, height: float, offset: Vector3 = Vector3.ZERO) -> void:
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	_solid_shape(node, cyl, offset)


func _tent(pos: Vector3, angle: float, color: Color) -> void:
	var t := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(3.6, 2.6, 4.4)
	t.mesh = pm
	t.material_override = Game.mat(color, "hair")
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
	var fire := Game.mesh_cyl(0.0, 0.5, 1.1, Color(1.0, 0.5, 0.1), "", 3.0)
	stage_root.add_child(fire)
	fire.global_position = plaza + Vector3(0, 0.55, 0)
	for i in 7:
		var st := Game.mesh_sphere(0.25, Color(0.35, 0.32, 0.3), "stone")
		stage_root.add_child(st)
		st.global_position = plaza + Vector3(sin(TAU * i / 7.0) * 0.85, 0.1, cos(TAU * i / 7.0) * 0.85)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.25)
	glow.light_energy = 2.0
	glow.omni_range = 9.0
	stage_root.add_child(glow)
	glow.global_position = plaza + Vector3(0, 1.4, 0)

	for i in 4:
		var jar := Game.mesh_cyl(0.28, 0.4, 0.9, Color(0.66, 0.42, 0.3), "clay")
		stage_root.add_child(jar)
		jar.global_position = plaza + Vector3(5.5 + (i % 2) * 0.9, 0.45, -4.5 + (i / 2) * 0.9)
	_water_jars = _interactable("", plaza + Vector3(6.0, 0.5, -4.0), 3.2, _use_water_jars)
	_refresh_water_jars()

	spawn_npc("Captain of the scouts", "captain", plaza + Vector3(0, 0, -8.0), Color(0.3, 0.38, 0.5))
	spawn_npc("Caravan trader", "merchant", plaza + Vector3(-8.5, 0, -3.5), Color(0.6, 0.3, 0.25))
	spawn_npc("Camp craftsman", "smith", plaza + Vector3(-8.5, 0, 2.5), Color(0.4, 0.35, 0.3))
	var anvil := Game.mesh_box(Vector3(0.9, 0.6, 0.6), Color(0.3, 0.3, 0.32), "stone")
	stage_root.add_child(anvil)
	anvil.global_position = plaza + Vector3(-10.2, 0.3, 2.5)
	_people()

	# Barrels, and jugs with cups, about the camp.
	water_spots = []
	for w in camp.waters:
		var wp: Vector3 = w["pos"]
		var spot = _interactable("", ground(wp.x, wp.z) + Vector3(0, 0.6, 0), 2.2, _use_water_spot)
		spot.set_meta("kind", str(w["kind"]))
		water_spots.append(spot)
	_refresh_water_jars()

	# The scout's own tent: its door is in the camp, its inside stands far off.
	_interactable("Enter your tent", camp.home_door + Vector3(0, 0.5, 0), 2.4, enter_home)
	home = HomeScript.new()
	stage_root.add_child(home)
	home.position = HOME_AT
	home.build({"sleep": _sleep, "chest": _open_chest, "drink": _home_drink, "leave": leave_home})


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
	for spot in water_spots:
		if str(spot.get_meta("kind")) == "barrel":
			spot.label = "Draw water from the barrel" if Game.camp_has_water else "The barrel is empty"
		else:
			spot.label = "Drink a cup of water" if Game.camp_has_water else "The jug is empty"


func _use_water_jars(_node) -> void:
	if Game.camp_has_water:
		Game.refill_water()
		Game.say("You drink deeply and fill your waterskin.")
	else:
		Game.say("The jars are dry. The camp needs water.")


## A barrel fills the waterskin and quenches thirst; a cup from the jug only quenches it.
func _use_water_spot(node) -> void:
	if not Game.camp_has_water:
		Game.say("There is no water in the camp yet.")
		return
	if str(node.get_meta("kind")) == "barrel":
		Game.refill_water()
		Game.say("You drink from the dipper and fill your waterskin.")
	elif Game.thirst >= 99.0:
		Game.say("You are not thirsty.")
	else:
		Game.sip(CUP)
		Game.say("You drink a cup of water.")


# ================================================================ the scout's own tent

## Goes into the tent: the player is moved to its inside, which stands apart from the stage.
func enter_home(_node = null) -> void:
	player.indoors = true
	player.velocity = Vector3.ZERO
	player.global_position = home.entry()
	player.yaw = home.entry_yaw()
	player.body.rotation.y = player.yaw
	player._arm.spring_length = player.ARM_INDOORS


func leave_home(_node = null) -> void:
	player.indoors = false
	player.velocity = Vector3.ZERO
	player.global_position = camp.home_door + Vector3(0, 0.3, 0)
	player.yaw = camp.home_facing
	player.body.rotation.y = player.yaw
	player._arm.spring_length = player.ARM_LENGTH


## Sleeping in the tent restores health and breath and saves the game: the only way to save.
func _sleep(_node = null) -> void:
	Game.hp = Game.max_hp
	Game.stamina = Game.max_stamina
	Game.sleep_to_morning()
	daylight.apply(Game.clock, true)
	Game.save_game(checkpoint())
	hud.dialog("Your tent", "You lie down and sleep until the morning. You wake rested.\n\n[i]Your journey is saved here. If you fall or quit, you can come back to this morning.[/i]", [["Get up", Callable()]])


## Where the stage stands now, to be saved with the game.
func checkpoint() -> Dictionary:
	return {"obj_done": obj_index, "hp": Game.hp, "thirst": Game.thirst, "water": Game.water}


## The lid swings up, the chest is shown beside the bag, and the lid shuts when it is closed.
func _open_chest(_node = null) -> void:
	var to: Vector3 = home.chest.global_position - player.global_position
	player.yaw = atan2(-to.x, -to.z)
	player.body.rotation.y = player.yaw
	home.open_lid(true)
	if not hud.auto:
		await get_tree().create_timer(0.35).timeout
	hud.open_chest(func() -> void: home.open_lid(false))


func _home_drink(_node = null) -> void:
	if Game.camp_has_water:
		Game.refill_water()
		Game.say("You drink from your jar and fill your waterskin.")
	else:
		Game.say("Your jar is dry. The camp needs water.")


## The title screen, over the stage-less world: a new journey, or the saved one.
func _show_title() -> void:
	hud.visible = false
	hud.title_up = true
	title = TitleScript.new()
	add_child(title)
	title.open(self)
	title.chosen.connect(_leave_title)


## `load_save`: go on from a save (the one at `path`, or the newest) instead of starting anew.
func _leave_title(load_save: bool, path: String = "") -> void:
	title.queue_free()
	title = null
	hud.title_up = false
	hud.visible = true
	Game.new_game()
	if load_save:
		Game.load_game(path)
	load_stage()
	# A journey picked up straight into the stage, with no dialog to close, takes hold of the
	# mouse here; otherwise closing the dialog does.
	if not Game.ui_open:
		hud._set_open(false)


## Goes back to a save, made when the scout slept in the tent: the one at `path`, or the last.
func load_checkpoint(path: String = "") -> void:
	if Game.load_game(path):
		load_stage()


# ================================================================ sling stones

## Stony patches out in the wilderness where sling stones can be gathered with E. Each holds a
## few; once emptied it is gone.
func _scatter_stones() -> void:
	stone_spots = []
	var srng := RandomNumberGenerator.new()
	srng.seed = int(stage["seed"]) * 17 + 3
	var tries := 0
	while stone_spots.size() < 30 and tries < 400:
		tries += 1
		var ang := srng.randf() * TAU
		var d := srng.randf_range(camp_radius + 4.0, 185.0)
		var x := sin(ang) * d
		var z := cos(ang) * d
		if terrain.water_y(x, z) > terrain.surface_y(x, z) - 0.2:
			continue
		var spot = _interactable("", ground(x, z) + Vector3(0, 0.3, 0), 2.3, _gather_stones)
		spot.set_meta("left", 3 + srng.randi() % 4)
		spot.label = "Gather sling stones (%d)" % int(spot.get_meta("left"))
		for k in 7:
			var r := srng.randf_range(0.05, 0.11)
			var pebble := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = r
			ball.height = r * 1.4
			ball.radial_segments = 6
			ball.rings = 3
			pebble.mesh = ball
			pebble.material_override = Game.mat(Color(0.62, 0.58, 0.52).darkened(srng.randf() * 0.25), "stone")
			spot.add_child(pebble)
			pebble.position = Vector3(srng.randf_range(-0.45, 0.45), -0.27, srng.randf_range(-0.45, 0.45))
			pebble.rotation.y = srng.randf() * TAU
		stone_spots.append(spot)


func _gather_stones(node) -> void:
	var left := int(node.get_meta("left"))
	var n := Game.take_stones(left)
	if n <= 0:
		Game.say("Your bag is full.")
		return
	left -= n
	n += Game.take_stones(int(Game.perk("stone_gatherer")))
	Game.say("+%d sling stones. You carry %d." % [n, Game.stones()])
	if left <= 0:
		stone_spots.erase(node)
		node.queue_free()
	else:
		node.set_meta("left", left)
		node.label = "Gather sling stones (%d)" % left


func _palm(pos: Vector3) -> void:
	var trunk := Game.mesh_cyl(0.16, 0.24, 6.0, Color(0.45, 0.34, 0.22), "wood")
	stage_root.add_child(trunk)
	trunk.global_position = pos + Vector3(0, 3.0, 0)
	_solid_pole(trunk, 0.22, 6.0)
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
	var pool := Game.mesh_cyl(5.0, 5.0, 0.16, Color(0.2, 0.5, 0.6), "", 0.25)
	stage_root.add_child(pool)
	pool.global_position = pos + Vector3(0, 0.25, 0)
	for i in 9:
		var a := TAU * i / 9.0
		var size := rng.randf_range(0.5, 0.9)
		var st := Game.mesh_sphere(size, Color(0.5, 0.45, 0.4), "stone")
		stage_root.add_child(st)
		st.global_position = pos + Vector3(sin(a) * 5.3, 0.2, cos(a) * 5.3)
		var ball := SphereShape3D.new()
		ball.radius = size
		_solid_shape(st, ball)
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		_palm(ground(pos.x + sin(a) * 8.0, pos.z + cos(a) * 8.0))
	_site_label(title, pos)


func _site_cairn(pos: Vector3, title: String) -> void:
	var y := 0.0
	for i in 5:
		var s := 1.6 - i * 0.26
		var st := Game.mesh_box(Vector3(s, 0.6, s), Color(0.5, 0.46, 0.42).darkened(i * 0.04), "stone")
		stage_root.add_child(st)
		st.global_position = pos + Vector3(0, y + 0.3, 0)
		st.rotation.y = i * 0.5
		# Each stone of the cairn can be climbed onto, up to its top.
		_solid_box(st, Vector3(s, 0.6, s), Vector3.ZERO)
		y += 0.6
	_site_label(title, pos)


func _site_warcamp(pos: Vector3, title: String) -> void:
	for i in 3:
		var a := TAU * i / 3.0 + 1.0
		_tent(ground(pos.x + sin(a) * 9.0, pos.z + cos(a) * 9.0), a, Color(0.28, 0.2, 0.2))
	var pole := Game.mesh_cyl(0.07, 0.07, 6.0, Color(0.3, 0.22, 0.15), "wood")
	stage_root.add_child(pole)
	pole.global_position = pos + Vector3(0, 3.0, 0)
	_solid_pole(pole, 0.1, 6.0)
	var flag := Game.mesh_box(Vector3(1.6, 1.0, 0.05), Color(0.6, 0.1, 0.1), "cloth")
	stage_root.add_child(flag)
	flag.global_position = pos + Vector3(0.85, 5.3, 0)
	_site_label(title, pos)


func _cage(pos: Vector3) -> void:
	var cage := Node3D.new()
	stage_root.add_child(cage)
	cage.global_position = pos
	for cx in [-0.9, 0.9]:
		for cz in [-0.9, 0.9]:
			var post := Game.mesh_cyl(0.07, 0.07, 2.2, Color(0.35, 0.25, 0.16), "wood")
			post.position = Vector3(cx, 1.1, cz)
			cage.add_child(post)
			_solid_pole(post, 0.09, 2.2)
	var roof := Game.mesh_box(Vector3(2.1, 0.1, 2.1), Color(0.35, 0.25, 0.16), "wood")
	roof.position.y = 2.2
	cage.add_child(roof)
	_solid_box(roof, Vector3(2.1, 0.12, 2.1), Vector3.ZERO)
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
	# Where men raid the camp, a champion or two of theirs is out in the wilds with a few
	# followers. They are worth finding: see "champion" in data/drops.gd.
	if str((stage.get("raid", {}) as Dictionary).get("kind", "")) == "raider":
		for i in 1 + Game.land_index() / 4:
			var a := rng.randf() * TAU
			var r := rng.randf_range(120.0, 185.0)
			var at := Vector2(sin(a) * r, cos(a) * r)
			spawn_enemy("champion", ground(at.x, at.y), mult)
			for k in 2:
				spawn_enemy("raider", ground(at.x + rng.randf_range(-5.0, 5.0), at.y + rng.randf_range(-5.0, 5.0)), mult)


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
				# With several bosses, the last of them to fall leaves the drop (see on_enemy_died).
				var e = spawn_enemy("boss", p, mult, {
					"boss": true, "name": names[i],
					"scale": obj.get("scale", 1.35), "hp_mult": obj.get("hp_mult", 1.0), "drop": obj.get("drop", "") if names.size() == 1 else "",
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
	if Game.visiting >= 0:
		return "Walking in the land of stage %d, %s. Go back to the camp from the map (M)." % [Game.visiting + 1, stage["name"]]
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
		var drop := str(obj.get("drop", ""))
		if obj_count >= obj_need and obj_need > 1 and drop != "" and not Game.was_found(drop):
			spawn_pickup("item", drop, e.global_position + Vector3(0.8, 0.0, 0.0))
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
	var learned := Game.gain_xp(int(60.0 * float(stage["mult"])))
	hud.dialog(str(obj["text"]), "%s\n\n[i]The camp gives you %d silver. You gain %d experience.[/i]" % [obj["done"], reward, learned], [["Continue", _next_objective]])


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
	Game.stop_music()
	get_tree().quit()


# ================================================================ camp, death, markers

func damage_camp(amount: float) -> void:
	Game.camp_hp = maxf(0.0, Game.camp_hp - amount)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	# The day goes by: six hours of play to the day (this stops while a menu holds the game).
	Game.advance_clock(delta)
	daylight.apply(Game.clock)
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
	hud.dialog("You fall", "Others find you and carry you back to your tent. Some of your silver is gone.\n\n[i]You lose %d silver.[/i]" % lost, [["Rise", _respawn]])


func _respawn() -> void:
	Game.hp = Game.max_hp * 0.6
	Game.thirst = maxf(Game.thirst, 60.0)
	if Game.visiting >= 0:
		# Fallen in an earlier land: carried all the way back to the camp.
		return_to_camp(true)
		return
	player.revive(home.bedside())
	player.indoors = true
	player._arm.spring_length = player.ARM_INDOORS


func get_markers() -> Array:
	var out: Array = []
	if not is_instance_valid(player) or player.indoors:
		return out
	var gold := Color(1.0, 0.9, 0.55)
	if player.global_position.distance_to(camp_pos) > camp_radius + 12.0:
		out.append({"pos": camp_pos + Vector3(0, 4, 0), "text": "Old campsite" if Game.visiting >= 0 else "Camp", "color": Color(0.8, 0.95, 1.0)})
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
	if is_instance_valid(encounters) and encounters.trader_node() != null:
		out.append({"pos": encounters.trader_node().global_position + Vector3(0, 3.2, 0), "text": "Caravan", "color": Color(1.0, 0.8, 0.4)})
	return out


## Everything the minimap marks: [{pos, kind}]. Kinds: camp, objective, exit, raider, wild, giver, item, trader.
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
	if places != null:
		for e in places.list:
			if e.has("at") and Game.places_seen.has(str(e["def"]["id"])):
				out.append({"pos": e["at"], "kind": "place"})
	if is_instance_valid(quests):
		for q in quests.list:
			if q["status"] == "new" or q["status"] == "ready":
				out.append({"pos": q["npc"].global_position, "kind": "giver"})
	if is_instance_valid(encounters) and encounters.trader_node() != null:
		out.append({"pos": encounters.trader_node().global_position, "kind": "trader"})
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
		"caravan":
			encounters.trade()
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
	if args.has("home"):
		enter_home()
	if args.has("sheathe"):
		player.body.sheathe(true)
	if args.has("yaw"):
		player.yaw = deg_to_rad(float(args["yaw"]))
		player.body.rotation.y = player.yaw
	if args.has("pitch"):
		player.pitch = deg_to_rad(float(args["pitch"]))
	if args.has("arm"):
		player._arm.spring_length = float(args["arm"])     # a long arm gives an overview from above
	if args.has("wind"):
		# --wind=KIND: a gust of that kind (weather.gd), caught near its height
		weather.start(str(args["wind"]))
		weather._t = float(weather.gust["length"]) * float(args.get("at", "0.45"))
		for d in weather._devils:
			d["age"] = 3.0
	if args.has("clean"):
		# --clean: no interface and no player, for pictures of the land
		hud.visible = false
		player.body.visible = false
	if args.has("sun"):
		daylight.held = true
		# --sun=ELEVATION,AZIMUTH in degrees: a low warm sun for pictures
		var parts: PackedStringArray = str(args["sun"]).split(",")
		sun.rotation_degrees = Vector3(-float(parts[0]), float(parts[1]), 0.0)
		sun.light_color = Color(1.0, 0.82, 0.6)
		sun.light_energy = 1.3
	if args.has("aim"):
		# --aim=sling or --aim=bow: hold the button, so the sling goes round or the bow is drawn
		if str(args["aim"]) == "bow":
			Input.action_press("attack")
			player.draw_bow()
		else:
			Input.action_press("sling")
			player.sling()
	if args.has("tip"):
		# --tip=N: point at the Nth thing in the bag, to show what it does
		await get_tree().process_frame
		var it: Dictionary = Game.bag[clampi(int(args["tip"]), 0, Game.bag.size() - 1)]
		var inv = hud.inventory
		inv._layout()
		get_viewport().warp_mouse(inv._bag_at + (Vector2(int(it["x"]), int(it["y"])) + Vector2(Game.item_size(it)) * 0.5) * inv.CELL)
		await get_tree().process_frame
		inv._update_tip()
		inv.queue_redraw()
	for i in int(args.get("frames", "90")):
		await get_tree().process_frame
	if args.has("blow"):
		# --blow=N: strike the first N blows of the combo and stop in the middle of the last one.
		# --view=DEG then swings the camera round the figure, which keeps facing the way it strikes.
		var table: Array = HumanScript.blows(Game.kind(Game.weapon_in("hand_r")))
		var last := clampi(int(args["blow"]), 1, table.size()) - 1
		for i in 600:
			if int(player.combo) >= last:
				break
			player.melee()
			await get_tree().process_frame
		player.yaw += deg_to_rad(float(args.get("view", "0")))
		var until: float = (float(table[last]["hit"]) + 0.06) / float(player._blow_speed)
		for i in 600:
			if int(player.combo) != last or float(player._combo_t) >= until:
				break
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
	check.call(Game.stones() == Game.START_STONES and Game.bag.size() == 2, "the scout starts with ten sling stones, five to a place")
	check.call(player.body.garments.has("top_short") and player.body.garments.has("skirt_short") and player.body.garments.has("sash"), "the scout starts in tunic, kilt and girdle")
	Game.silver = 1000
	Game.bronze = 50
	check.call(Game.try_buy("dagger"), "can buy a dagger")
	var dagger: Dictionary = Game.bag[Game.bag.size() - 1]
	check.call(dagger["id"] == "dagger" and Game.item_size(dagger) == Vector2i(1, 2), "a dagger takes two places in the bag")
	check.call(Game.equip(dagger), "can equip the dagger")
	check.call(is_equal_approx(Game.melee_power(), 18.0), "the dagger is equipped")
	check.call(player.body.weapon_kind == "dagger", "the equipped weapon shows in the hand")
	var staff_back: Array = Game.bag.filter(func(it): return it["id"] == "staff")
	check.call(staff_back.size() == 1 and Game.index_in(Game.bag, dagger) < 0, "the staff went back to the bag")
	check.call(Game.try_upgrade(dagger), "can strengthen the dagger")
	check.call(is_equal_approx(Game.melee_power(), 18.0 * 1.12), "+1 adds 12 percent")
	Game.try_upgrade(dagger)
	check.call(not Game.try_upgrade(dagger), "strengthening stops at +2 before the workshop")
	var before_sell := Game.silver
	check.call(Game.sell(staff_back[0]) and Game.silver > before_sell, "can sell spare gear")
	check.call(Game.hurt_player(100.0) < 100.0, "clothes stop some damage")
	Game.hp = Game.max_hp

	# Both hands, shields, bows, garments and what they give.
	var short_sword := Game.add_item("short_sword")
	check.call(not Game.equip(short_sword, "hand_l") and Game.equipped["hand_l"].is_empty(), "a sword does not go in the left hand")
	var left_sickle := Game.add_item("sickle_sword")
	check.call(Game.equip(left_sickle, "hand_l") and player.body.offhand_kind == "sickle", "a sickle sword goes in the left hand")
	check.call(player.blow_hand(0) == "r" and player.blow_hand(1) == "l" and player.blow_hand(2) == "r", "with a blade in each hand the second blow is the left hand's")
	var right_dagger: Dictionary = Game.equipped["hand_r"]
	check.call(Game.equip(short_sword, "hand_r") and Game.equipped["hand_l"].is_empty() and Game.index_in(Game.bag, left_sickle) >= 0,
		"a sword in the right hand is fought with alone: the left hand's blade goes into the bag")
	check.call(Game.equip(left_sickle, "hand_l") and Game.equipped["hand_r"].is_empty() and Game.equipped["hand_l"] == left_sickle,
		"and a blade put in the left hand takes the sword out of the right")
	Game.equip(right_dagger, "hand_r")
	var defense0 := Game.defense()
	check.call(Game.equip(Game.add_item("hide_shield")) and Game.equipped["hand_l"]["id"] == "hide_shield" and player.body.offhand_kind == "shield", "a shield goes in the left hand")
	check.call(is_equal_approx(Game.defense(), defense0 + 7.0) and player.body.offhand.get_parent() == player.body._arm_l, "the shield adds defense and is strapped to the forearm")
	check.call(Game.equip(Game.add_item("hunting_bow")) and Game.equipped["hand_l"].is_empty() and Game.equipped["hand_r"]["id"] == "hunting_bow", "a bow takes both hands")
	check.call(player.body.offhand_kind == "bow" and player.body.weapon_kind == "none", "the bow is held in the left hand")
	check.call(Game.bag.any(func(it): return it["id"] == "dagger") and Game.bag.any(func(it): return it["id"] == "hide_shield"), "what both hands held went back to the bag")
	Game.bag.clear()    # a dress is two places wide and four high: it needs room
	check.call(Game.equip(Game.add_item("dress")) and Game.equipped["bottom"].is_empty() and Game.equipped["top"]["id"] == "dress", "a dress takes the place of top and bottom")
	check.call(player.body.garments.has("skirt_long") and not player.body.garments.has("skirt_short"), "the figure wears the dress")
	check.call(Game.equip(Game.add_item("bronze_helmet")) and player.body.garments.has("helmet"), "a helmet is worn on the head")
	var health0 := Game.max_hp
	check.call(Game.equip(Game.add_item("carnelian_beads")) and is_equal_approx(Game.max_hp, health0 + 8.0) and player.body.garments.has("necklace"), "a carnelian necklace is worn and adds health")
	check.call(Game.swing_speed(Game.new_item("dagger")) > Game.swing_speed(Game.new_item("short_sword")) and Game.swing_speed(Game.new_item("short_sword")) > Game.swing_speed(Game.new_item("bronze_mace")), "heavier weapons swing slower")
	var kinds_of_gear := {}
	for id in Game.Items.ITEMS:
		kinds_of_gear[str(Game.Items.ITEMS[id]["kind"])] = true
	check.call(kinds_of_gear.has("spear") and kinds_of_gear.has("bow") and kinds_of_gear.has("shield") and kinds_of_gear.has("axe") and kinds_of_gear.has("mace"), "there are spears, bows, shields, axes and maces")
	var grid_probe: Array = []
	check.call(Game.place(grid_probe, Vector2i(2, 4), Game.new_item("staff")) == 0 and Game.place(grid_probe, Vector2i(2, 4), Game.new_item("spear")) == 0 and Game.place(grid_probe, Vector2i(2, 4), Game.new_item("dagger")) == 1, "a full grid takes nothing more")
	var heap: Array = []
	check.call(Game.place(heap, Vector2i(2, 1), Game.new_item("stones", 0, 12)) == 2 and Game.ammo_count("stones", heap) == 10, "stones stack five to a place")
	for slot in Game.equipped:
		Game.equipped[slot] = {}
	for pair in [["hand_r", dagger], ["sling", Game.new_item("wool_sling")], ["top", Game.new_item("linen_tunic")], ["bottom", Game.new_item("linen_kilt")], ["belt", Game.new_item("rope_girdle")]]:
		Game.equipped[pair[0]] = pair[1]
	Game.bag.clear()
	Game.take_stones(Game.START_STONES)
	Game._gear_changed()
	check.call(player.body.weapon_kind == "dagger" and player.body.offhand == null and player.body.garments.has("skirt_short"), "taking things off shows on the figure")

	# What things are made of: every surface has its texture, cloth is woven, the grain of wood
	# runs along the piece, and the camp's tents and poles are made of them.
	var surfaces_ok := true
	for surface in Game.SURFACES:
		var made: StandardMaterial3D = Game.mat(Color(0.5, 0.4, 0.3), surface)
		if not made.uv1_triplanar or not made.normal_enabled or (made.albedo_texture == null and made.detail_albedo == null):
			surfaces_ok = false
	check.call(surfaces_ok, "every surface has a texture laid on by position")
	var canvas: StandardMaterial3D = Game.mat(Color(0.8, 0.7, 0.5), "cloth")
	check.call(canvas.detail_enabled and canvas.detail_albedo.get_width() == 64 and canvas.detail_normal != null and canvas.uv2_triplanar and canvas.albedo_texture != null, "tent cloth is woven and banded")
	var beam_part := Game.mesh_box(Vector3(2.0, 0.1, 0.3), Color(0.4, 0.28, 0.17), "wood")
	var post_part := Game.mesh_cyl(0.05, 0.05, 2.0, Color(0.4, 0.28, 0.17), "wood")
	var beam: StandardMaterial3D = beam_part.material_override
	var post: StandardMaterial3D = post_part.material_override
	check.call(beam.uv1_scale.x < beam.uv1_scale.y and post.uv1_scale.y < post.uv1_scale.x and beam != post, "the grain of wood runs along the piece")
	beam_part.free()
	post_part.free()
	check.call(Game.mat(Color(0.5, 0.4, 0.3)).albedo_texture == null and Game.mat(Color(0.5, 0.4, 0.3), "clay") == Game.mat(Color(0.5, 0.4, 0.3), "clay"), "plain materials stay plain, and equal ones are shared")
	var woven := 0
	var timbered := 0
	for part in camp.find_children("*", "MeshInstance3D", true, false):
		var of_what: StandardMaterial3D = part.material_override as StandardMaterial3D
		if of_what == null:
			continue
		if of_what.detail_enabled and part.mesh is PrismMesh:
			woven += 1
		if of_what.albedo_texture == Game._texture("fibre"):
			timbered += 1
	check.call(woven >= 20 and timbered >= 20, "the camp's tents are of woven cloth and its poles of wood (%d and %d)" % [woven, timbered])

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
	robed.animate(0.1, 0.0)
	check.call(not robed.weapon.transform.is_equal_approx(robed._carry), "a strike turns the weapon into the fist")
	robed.sheathe(true)
	check.call(robed.weapon.get_parent() == robed._hip and robed.sheathed, "a sword is put away at the belt")
	robed.set_weapon("staff")
	check.call(robed.weapon.get_parent() == robed._back, "a staff put away goes on the back, and stays there when gear changes")
	robed.sheathe(false)
	check.call(robed.weapon.get_parent() == robed.hand_r, "a weapon taken up is back in the hand")
	robed.whirl()
	check.call(robed._sling.visible and robed.weapon.get_parent() == robed._back, "the staff goes on the back while the sling is whirled")
	for i in 50:
		robed.animate(0.02, 0.0)
	check.call(not robed._sling.visible and robed.weapon.get_parent() == robed.hand_r, "after the throw the sling is put away and the staff is in hand again")
	robed.set_hands("sword", "shield")
	check.call(robed.offhand.get_parent() == robed._arm_l, "a shield is strapped to the left forearm")
	robed.sheathe(true)
	check.call(robed.offhand.get_parent() == robed._back and robed.weapon.get_parent() == robed._hip, "put away, the shield goes on the back and the sword at the belt")
	robed.sheathe(false)
	# The overhead chop: at the moment it lands the blade points forward and down.
	var chopper = HumanScript.new()
	add_child(chopper)
	chopper.build({"sex": 0})
	chopper.set_hands("sword", "none")
	chopper.attack(0, "r", 1.0)
	for i in int(round(float(HumanScript.BLOWS[0]["hit"]) * 60.0)):
		chopper.animate(1.0 / 60.0, 0.0)
		chopper._tree.advance(1.0 / 60.0)
	var hand_now: Transform3D = chopper.skeleton.global_transform * chopper.skeleton.get_bone_global_pose(chopper.skeleton.find_bone("hand_r"))
	var cut: Vector3 = (hand_now.basis * chopper._strike.basis.y).normalized()
	check.call(cut.z < -0.3 and cut.y < 0.2, "blow A brings the blade down in front (%s)" % cut)
	# The whole body goes into a blow made standing still: every clip turns the hips, bends the
	# knees and keeps the feet where they stand (only the front foot steps, in the last blow).
	var rig: Skeleton3D = chopper.skeleton
	var rest_pose: Animation = HumanScript._libraries[0].get_animation("Idle")
	var hips_bone := rig.find_bone("pelvis")
	var toes_r := rig.find_bone("ball_r")
	var toes_l := rig.find_bone("ball_l")
	var hips_stood: Transform3D = HumanScript.pose_transform(rest_pose, rig, hips_bone, 0.0)
	var toes_r_stood: Vector3 = HumanScript.pose_transform(rest_pose, rig, toes_r, 0.0).origin
	var toes_l_stood: Vector3 = HumanScript.pose_transform(rest_pose, rig, toes_l, 0.0).origin
	var blows_ok := true
	var blow_note := ""
	for clip_name in ["Blow_A_R", "Blow_B_R", "Blow_C_R", "Blow_A_L", "Blow_B_L", "Blow_C_L"]:
		var clip: Animation = HumanScript._libraries[0].get_animation(clip_name)
		var hip_turn := 0.0
		var hip_drop := 0.0
		var slip := 0.0
		var t := 0.0
		while t <= clip.length:
			var hips_now: Transform3D = HumanScript.pose_transform(clip, rig, hips_bone, t, rest_pose)
			hip_turn = maxf(hip_turn, absf(angle_difference(atan2(-hips_stood.basis.x.z, hips_stood.basis.x.x), atan2(-hips_now.basis.x.z, hips_now.basis.x.x))))
			hip_drop = maxf(hip_drop, hips_stood.origin.y - hips_now.origin.y)
			slip = maxf(slip, HumanScript.pose_transform(clip, rig, toes_r, t, rest_pose).origin.distance_to(toes_r_stood))
			if not clip_name.contains("_C_"):
				slip = maxf(slip, HumanScript.pose_transform(clip, rig, toes_l, t, rest_pose).origin.distance_to(toes_l_stood))
			t += 1.0 / 60.0
		if hip_turn < 0.2 or hip_drop < 0.05 or slip > 0.01:
			blows_ok = false
			blow_note += " %s: turn %.2f drop %.3f slip %.3f" % [clip_name, hip_turn, hip_drop, slip]
	check.call(blows_ok, "each blow turns the hips, bends the knees and keeps the feet planted" + blow_note)
	# Standing, the hips go into the blow; on the run the legs keep running.
	chopper.attack(2, "r", 1.0)
	check.call(chopper._legs == "blow", "a figure standing still puts its legs into a blow")
	for i in int(round(float(HumanScript.BLOWS[2]["hit"]) * 60.0)):
		chopper.animate(1.0 / 60.0, 0.0)
		chopper._tree.advance(1.0 / 60.0)
	var hips_struck: Vector3 = rig.get_bone_global_pose(hips_bone).origin
	check.call(hips_stood.origin.y - hips_struck.y > 0.08 and hips_struck.z - hips_stood.origin.z > 0.08, "the hips drop and drive forward with the blow (%s to %s)" % [hips_stood.origin, hips_struck])
	for i in 30:
		chopper.animate(1.0 / 60.0, 6.0)
	chopper.attack(0, "r", 1.0)
	check.call(chopper._legs == "", "a figure on the run strikes with the upper body only")
	chopper.queue_free()
	# Off the ground: the jump pose, the downward blow with the knees drawn up, and the landing.
	var leaper = HumanScript.new()
	add_child(leaper)
	leaper.build({"sex": 0})
	leaper.set_hands("sword", "none")
	var limbs: Skeleton3D = leaper.skeleton
	var knee_l := limbs.find_bone("calf_l")
	var knee_r := limbs.find_bone("calf_r")
	var knee_stood: float = limbs.get_bone_global_pose(knee_l).origin.y
	for i in 24:
		leaper.animate(1.0 / 60.0, 0.0, true)
		leaper._tree.advance(1.0 / 60.0)
	check.call(limbs.get_bone_global_pose(knee_l).origin.y - knee_stood > 0.08, "off the ground a knee comes up (%.2f)" % (limbs.get_bone_global_pose(knee_l).origin.y - knee_stood))
	leaper.attack(0, "r", 1.0)
	check.call(leaper._legs == "air" and str((leaper._first_blow["r"] as AnimationNodeAnimation).animation) == "Blow_Air_R", "the first blow off the ground is the downward one")
	for i in int(round(float(HumanScript.BLOWS[0]["hit"]) * 0.8 * 60.0)):
		leaper.animate(1.0 / 60.0, 0.0, true)
		leaper._tree.advance(1.0 / 60.0)
	var grip_now: Transform3D = limbs.global_transform * limbs.get_bone_global_pose(limbs.find_bone("hand_r"))
	var down_cut: Vector3 = (grip_now.basis * leaper._strike.basis.y).normalized()
	check.call(down_cut.z < -0.3 and down_cut.y < 0.0, "it brings the blade down in front (%s)" % down_cut)
	var hips_in_air: Vector3 = limbs.get_bone_global_pose(hips_bone).origin
	check.call(limbs.get_bone_global_pose(knee_r).origin.z - hips_in_air.z > 0.15 and limbs.get_bone_global_pose(knee_l).origin.z - hips_in_air.z > 0.15, "with both knees drawn up in front of the hips")
	leaper.animate(1.0 / 60.0, 0.0, false)
	check.call(leaper._land_left > 0.0 and leaper._legs == "", "coming down from a jump, the legs take the landing")
	for i in 8:
		leaper._tree.advance(1.0 / 60.0)
		leaper.animate(1.0 / 60.0, 0.0, false)
	check.call(hips_stood.origin.y - limbs.get_bone_global_pose(hips_bone).origin.y > 0.1, "the hips sink as the knees give (%.2f)" % (hips_stood.origin.y - limbs.get_bone_global_pose(hips_bone).origin.y))
	check.call(limbs.get_bone_global_pose(toes_r).origin.distance_to(toes_r_stood) < 0.03 and limbs.get_bone_global_pose(toes_l).origin.distance_to(toes_l_stood) < 0.03, "and the feet are back where they stand")
	leaper.attack(0, "r", 1.0)
	check.call(str((leaper._first_blow["r"] as AnimationNodeAnimation).animation) == "Blow_A_R" and leaper._legs == "blow", "back on the ground the first blow is the usual one")
	leaper.queue_free()
	robed.set_hands("none", "bow")
	robed.bow_draw()
	for i in 40:
		robed.animate(1.0 / 60.0, 0.0)
		robed._tree.advance(1.0 / 60.0)
	check.call(robed.drawing and robed._arrow.visible and robed.draw_amount > 0.9, "drawing the bow nocks an arrow and pulls it back")
	check.call(robed.bow_loose() > 0.9 and not robed.drawing, "and the arrow is let go")
	robed.die()
	check.call(robed.dead, "a figure can fall")
	robed.queue_free()
	var probe := {"sex": 0, "beard": 1, "hair": 4}
	HumanScript.cycle(probe, "hair", 1)
	check.call(int(probe["hair"]) == 0, "options wrap round")
	HumanScript.cycle(probe, "sex", 1)
	check.call(int(probe["sex"]) == 1 and int(probe["beard"]) == 0, "choosing female clears the beard")
	Game.look["sex"] = 1
	Game.look["cloth"] = 6
	Game.look_changed.emit()
	check.call(int(player.body.look["sex"]) == 1 and player.body.garments.has("skirt_short"), "editing the look rebuilds the player figure in what is equipped")
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
	var guardians := 0
	for e in places.list:
		guardians += e["guards"].size()
	check.call(get_tree().get_nodes_in_group("enemy").size() - guardians == 18, "stage 1 wildlife spawned, besides the guardians of its places")
	var animals := {}
	for e in get_tree().get_nodes_in_group("enemy"):
		if e._beast != null:
			animals[e.kind] = e._beast
	check.call(animals.has("snake") and animals["snake"]._segments.size() == 16 and animals["snake"]._head != null, "a viper is a modelled body of many pieces with a head")
	check.call(not animals.has("scorpion") or animals["scorpion"]._legs.size() == 8, "a scorpion has eight legs")
	var jackal = CreatureScript.new()
	add_child(jackal)
	jackal.build("beast", Color(0.6, 0.48, 0.3))
	var leg0: float = jackal._legs[0]["node"].rotation.x
	for i in 10:
		jackal.animate(0.05, 6.0)
	check.call(jackal._legs.size() == 4 and absf(jackal._legs[0]["node"].rotation.x - leg0) > 0.05, "a running jackal moves its legs")
	jackal.queue_free()
	check.call(not Game.has_save(), "starting a stage does not save the game")
	check.call(camp.waters.size() >= 6 and stone_spots.size() >= 20, "the camp has water stations (%d) and the wilderness has stony ground (%d)" % [camp.waters.size(), stone_spots.size()])
	var kinds_of_water := {}
	for w in camp.waters:
		kinds_of_water[w["kind"]] = true
	check.call(kinds_of_water.has("barrel") and kinds_of_water.has("cups"), "there are water barrels and jugs with cups")
	check.call(player.global_position.y > -2.0 and player.global_position.y < 3.0, "the player stands on the ground")
	check.call(not Game.camp_has_water, "the camp starts stage 1 without water")

	# Combat and loot.
	var foe = spawn_enemy("raider", ground(30.0, 30.0), 1.0, {"drop": "linen"})
	check.call(foe._fig != null and HumanScript.is_weapon(foe._fig.weapon_kind), "raiders are human figures holding a weapon (%s)" % foe._fig.weapon_kind)
	var arms := {}
	var dress := {}
	for people in Game.Enemies.PEOPLES:
		for i in 12:
			var man: Dictionary = Game.Enemies.soldier(people, "raider", false, Game.rng)
			arms["%s %s" % [man["right"], man.get("left", "none")]] = true
			dress[str(man["wear"]) + str(man["head"])] = true
	check.call(arms.size() >= 6 and dress.size() >= 10, "the soldiers of each people are armed and dressed in their own ways (%d sets of arms, %d dresses)" % [arms.size(), dress.size()])
	# What falls: every enemy has a line in the drop table, and everything named there exists.
	var drops_ok := true
	for enemy_kind in Game.Enemies.ENEMIES:
		drops_ok = drops_ok and Game.Drops.DROPS.has(enemy_kind)
	for enemy_kind in Game.Drops.DROPS:
		for line in Game.Drops.DROPS[enemy_kind]:
			drops_ok = drops_ok and (not line.has("item") or Game.Items.ITEMS.has(line["item"])) and (not line.has("table") or Game.Drops.TABLES.has(line["table"]))
	for table in Game.Drops.TABLES:
		for entry in Game.Drops.TABLES[table]:
			drops_ok = drops_ok and Game.Items.ITEMS.has(entry[0]) and Game.rarity(Game.new_item(entry[0])) > 0
	check.call(drops_ok, "every enemy has a drop list, and everything in the lists is a real item")
	var fell := {"rare": 0, "legendary": 0, "plain": 0, "skins": 0}
	for i in 400:
		for d in Game.roll_drops("champion", 5, 1.0):
			if d[0] == "item":
				fell[["plain", "rare", "legendary"][Game.rarity(Game.new_item(d[1]))]] += 1
		for d in Game.roll_drops("jackal", 2, 1.0):
			fell["skins"] += 1 if d[1] is String and d[1] == "jackal_pelt" else 0
	check.call(fell["rare"] > 60 and fell["legendary"] == 0 and fell["skins"] > 120, "champions sometimes drop rare weapons but never legendary ones; jackals leave pelts (%s)" % [fell])
	var boss_drops: Array = []
	for st in Game.Stages.LIST:
		for o in st["objectives"]:
			if o.has("drop"):
				boss_drops.append(str(o["drop"]))
	check.call(boss_drops.has("chieftains_blade") and boss_drops.has("bashan_blade") and boss_drops.has("kings_khopesh") and Game.Drops.LEGENDARY_SOURCES.size() == 7
		and Game.Drops.LEGENDARY_SOURCES.keys().all(func(id): return Game.rarity(Game.new_item(id)) == 2), "each legendary has one source; three are the bosses' certain drops")
	check.call(Game.roll_table("rare", 0) == "" and Game.roll_table("rare", 2) != "", "the best finds wait for the later stages")
	Game.record_find("bashan_blade")
	check.call(Game.was_found("bashan_blade") and Game.snapshot()["found"].has("bashan_blade"), "a legendary once found is remembered, in the save too")
	Game.found = {}
	var pelt := Game.add_item("jackal_pelt")
	check.call(not Game.equip(pelt) and Game.sell_value(pelt) == 9, "spoils cannot be worn, only sold")
	Game.remove_from(Game.bag, pelt)
	var champ = spawn_enemy("champion", ground(38.0, 30.0), 1.0, {"people": "Canaanite"})
	check.call(champ.display_name == "Canaanite champion" and champ.max_hp > foe.max_hp * 2.0 and champ._fig.garments.has("helmet"), "a champion is a stronger, better-armed man of his people (%s)" % champ.display_name)
	champ.queue_free()
	var king = spawn_enemy("boss", ground(34.0, 30.0), 1.0, {"boss": true, "people": "Amorite"})
	check.call(king._fig.garments.has("crown") and king._fig.offhand_kind == "shield" and king.display_name == "Amorite king", "an Amorite king wears a crown and carries a shield (%s)" % king.display_name)
	king.queue_free()
	foe.take_damage(10.0)
	check.call(not foe.dead and foe.hp < foe.max_hp, "an enemy takes damage")
	foe.take_damage(1e6)
	check.call(foe.dead, "an enemy dies")
	var found_item := false
	for p in get_tree().get_nodes_in_group("pickup"):
		if p.kind == "item" and str(p.payload) == "linen":
			found_item = true
			p.collect()
	check.call(found_item and Game.bag.any(func(it): return it["id"] == "linen"), "a forced drop can be picked up")

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
	# A dummy without armour or shield, so every blow counts in full.
	dummy.armor = 0.0
	dummy.shield_hp = 0
	player.melee()
	await _wait(0.6)
	check.call(is_equal_approx(dummy.hp, dummy.max_hp - Game.melee_power()), "a swing hits the enemy in front")
	await _wait(0.6)
	dummy.global_position = p0 + Vector3(-0.95, 0, 12.0)
	await _wait(0.3)
	var dummy_hp: float = dummy.hp
	var stones0 := Game.stones()
	Input.action_press("sling")
	player.sling()
	await _wait(1.5)
	check.call(player._slinging and player.body.whirling() and player._aim.visible, "holding the button keeps the sling going round and shows where it will land")
	check.call(player.aim_on_target, "the landing mark turns red on the enemy in the crosshair")
	Input.action_release("sling")
	await _wait(1.2)
	check.call(not player._slinging and not player._aim.visible, "letting go throws")
	check.call(is_equal_approx(dummy.hp, dummy_hp - Game.sling_power()), "a sling stone hits what the crosshair is on")
	check.call(Game.stones() == stones0 - 1, "each throw uses up a stone")
	Game.remove_ammo(Game.bag, "stones", 999)
	player.sling()
	await _wait(0.2)
	check.call(not player.body.busy(), "with no stones left the sling cannot be thrown")
	Game.take_stones(stones0)
	player.yaw = 0.0
	player.melee()
	await _wait(0.9)
	check.call(is_equal_approx(dummy.hp, dummy_hp - Game.sling_power()), "a swing misses an enemy behind and far away")

	# Three presses in a row make the three blows of a combo, each harder than the last.
	player.yaw = PI
	dummy.global_position = p0 + Vector3(0, 0, 2.2)
	await _wait(0.3)
	dummy_hp = dummy.hp
	player.melee()
	await _wait(0.1)
	player.melee()
	await _wait(0.5)
	check.call(player.combo == 1, "pressing again during the first blow leads into the second")
	player.melee()
	await _wait(1.6)
	var combo_damage: float = Game.melee_power() * (PlayerScript.BLOW_POWER[0] + PlayerScript.BLOW_POWER[1] + PlayerScript.BLOW_POWER[2])
	check.call(is_equal_approx(dummy.hp, dummy_hp - combo_damage), "a full combo lands all three blows (%.1f of %.1f)" % [dummy_hp - dummy.hp, combo_damage])
	check.call(player.combo == -1, "the combo ends after the third blow")

	# Jumping: the scout takes the jump pose, strikes downward in the air, and lands.
	check.call(player.is_on_floor() and not player.in_air(), "the scout stands on the ground")
	player.jump()
	await _wait(0.2)
	check.call(player.in_air() and float(player.body._air) > 0.5, "a jump puts the scout in the jump pose (%.2f)" % float(player.body._air))
	player.melee()
	check.call(str(player.body._legs) == "air", "a blow begun in the air is the jump attack")
	await _wait(1.2)
	check.call(not player.in_air() and float(player.body._air) < 0.05 and player.combo == -1, "and the scout comes down again")

	# Putting the weapon away, and drawing it to strike.
	player.toggle_sheathe()
	await _wait(0.6)
	check.call(player.body.sheathed and player.body.weapon.get_parent() == player.body._hip, "R puts the dagger away at the belt")
	dummy.global_position = p0 + Vector3(0, 0, 2.2)     # the blows before drove it back
	dummy_hp = dummy.hp
	player.melee()
	await _wait(1.4)
	check.call(not player.body.sheathed and dummy.hp < dummy_hp, "attacking with the weapon put away draws it and strikes")

	# The bow: hold to draw, let go to loose; each arrow is used up.
	var bow_inst := Game.add_item("hunting_bow")
	Game.equip(bow_inst)
	Game.take_ammo("arrows", 20)
	dummy.global_position = p0 + Vector3(-0.95, 0, 12.0)
	await _wait(0.3)
	dummy_hp = dummy.hp
	Input.action_press("attack")
	player.draw_bow()
	await _wait(1.0)
	check.call(player.body.drawing and player.body.draw_amount > 0.95 and player._aim.visible, "holding attack with a bow draws it fully")
	Input.action_release("attack")
	await _wait(0.8)
	check.call(is_equal_approx(dummy.hp, dummy_hp - Game.bow_power()) and Game.arrows() == 19, "a fully drawn arrow hits for the bow's damage (%.1f)" % (dummy_hp - dummy.hp))
	Game.equip(Game.bag.filter(func(it): return it["id"] == "dagger")[0])
	Game.remove_ammo(Game.bag, "arrows", 999)
	Game.remove_from(Game.bag, bow_inst)
	dummy.take_damage(1e9)

	# Stamina: sprinting spends it, walking wins it back.
	player.global_position = ground(0.0, camp_radius + 30.0) + Vector3(0, 0.3, 0)
	player.yaw = PI
	Game.thirst = 80.0
	Game.stamina = Game.max_stamina
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(2.0)
	check.call(Game.stamina < Game.max_stamina - 20.0, "sprinting uses up stamina (%.0f)" % Game.stamina)
	await _wait(4.0)
	check.call(player._tired and not player._sprinting, "out of stamina, the scout cannot sprint")
	Input.action_release("sprint")
	var breath := Game.stamina
	await _wait(2.0)
	check.call(Game.stamina > breath + 5.0, "walking slowly brings stamina back (%.0f -> %.0f)" % [breath, Game.stamina])
	Input.action_release("move_forward")

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
	check.call(player.indoors and player.global_position.distance_to(home.bedside()) < 2.0, "the revived player wakes in their own tent")
	leave_home()
	check.call(not player.indoors and player.global_position.distance_to(camp.home_door) < 2.0, "leaving the tent comes out at its door in the camp")
	if is_instance_valid(viper):
		viper.take_damage(1e9)

	# Water about the camp: none until Marah is found, then barrels fill the skin and cups quench.
	var cups = null
	var barrel = null
	for spot in water_spots:
		if str(spot.get_meta("kind")) == "cups":
			cups = spot
		else:
			barrel = spot
	Game.thirst = 30.0
	cups.interact()
	check.call(is_equal_approx(Game.thirst, 30.0) and cups.prompt_text() == "The jug is empty", "with no water in the camp the jugs are empty")
	Game.camp_has_water = true
	_refresh_water_jars()
	cups.interact()
	check.call(is_equal_approx(Game.thirst, 30.0 + CUP), "a cup of water quenches thirst")
	Game.water = 0
	barrel.interact()
	check.call(Game.water == Game.max_water and is_equal_approx(Game.thirst, 100.0), "a water barrel fills the waterskin")
	Game.camp_has_water = false
	_refresh_water_jars()

	# The bag: a grid of places; stones stack five to a place; a bigger bag has more places.
	var keep_bag: Array = Game.bag.duplicate()
	Game.bag.clear()
	check.call(Game.take_stones(500) == Game.places() * 5 and not Game.can_take("stones"), "stones fill the bag, five to a place (%d)" % Game.stones())
	Game.silver = 1000
	check.call(not Game.try_buy("dagger") and not Game.try_buy_stones(), "a full bag takes nothing more")
	stone_spots[0].interact()
	check.call(Game.stones() == Game.places() * 5, "stony ground cannot overfill the bag")
	check.call(Game.try_buy_pack("shoulder_bag") and Game.places() == 50 and Game.bag_grid() == Vector2i(10, 5), "the next bag has more places")
	Game.bag.clear()
	var patch = stone_spots[0]
	var in_patch := int(patch.get_meta("left"))
	patch.interact()
	check.call(Game.stones() == in_patch, "gathering at stony ground picks up its stones (%d)" % in_patch)
	var loot := Game.add_item("linen")
	Game.take_stones(500)
	var drop = spawn_pickup("item", "leather", player.global_position + Vector3(0.5, 0, 0))
	await _wait(0.3)
	check.call(is_instance_valid(drop) and not Game.bag.any(func(it): return it["id"] == "leather"), "gear on the ground is left there when the bag is full")
	Game.remove_ammo(Game.bag, "stones", 999)
	await _wait(0.6)
	check.call(not is_instance_valid(drop) and Game.bag.any(func(it): return it["id"] == "leather"), "and picked up once there is room")

	# The tent: the chest keeps things, and sleeping is the one way to save.
	enter_home()
	check.call(player.indoors and player.global_position.distance_to(HOME_AT) < 6.0, "going into the tent leads inside it")
	await _wait(0.3)
	check.call(player.global_position.y > HOME_AT.y - 1.0, "inside the tent the scout stands on its floor")
	Game.take_stones(12)
	var heap_in_bag: Dictionary = Game.bag.filter(func(it): return it["id"] == "stones")[0]
	var heap_count := int(heap_in_bag["count"])
	check.call(Game.store(loot) and Game.store(heap_in_bag), "gear and stones can be put in the chest")
	check.call(Game.index_in(Game.chest, loot) >= 0 and Game.index_in(Game.bag, loot) < 0 and Game.ammo_count("stones", Game.chest) == heap_count, "and they are in it")
	check.call(Game.unstore(loot) and Game.index_in(Game.bag, loot) >= 0, "and taken out again")
	Game.store(loot)
	# The chest screen: the lid opens, the bag is on the left and the chest on the right.
	hud.auto = false
	_open_chest()
	await _wait(0.6)
	var screen = hud.inventory
	check.call(screen.visible and screen.mode == "chest" and get_tree().paused, "using the chest opens it beside the bag")
	await get_tree().create_timer(0.5).timeout
	check.call(home.lid_hinge.rotation.x < -1.5, "the lid of the chest swings open (%.2f)" % home.lid_hinge.rotation.x)
	screen._layout()
	var in_chest: Dictionary = Game.chest[Game.index_in(Game.chest, loot)]
	var spot_px: Vector2 = screen._right_at + (Vector2(int(in_chest["x"]), int(in_chest["y"])) + Vector2(0.5, 0.5)) * screen.CELL
	screen.quick(spot_px)
	check.call(Game.index_in(Game.bag, loot) >= 0, "right-clicking in the chest takes it into the bag")
	screen.close()
	check.call(not get_tree().paused and not screen.visible, "closing the chest goes back to the game")
	await get_tree().create_timer(0.5).timeout
	check.call(absf(home.lid_hinge.rotation.x) < 0.05, "and the lid shuts")
	Game.store(loot)
	# The gear screen: pick something up and drop it on a slot to wear it.
	var cap := Game.add_item("leather_cap")
	hud.open_inventory()
	screen._layout()
	screen.click(screen._bag_at + (Vector2(int(cap["x"]), int(cap["y"])) + Vector2(1.0, 1.0)) * screen.CELL)
	check.call(is_same(screen.held, cap), "clicking an item in the bag picks it up")
	screen.click(screen._slot_rect("head").get_center())
	check.call(screen.held.is_empty() and is_same(Game.equipped["head"], cap) and player.body.garments.has("cap"), "dropping it on the head slot wears it")
	check.call(screen.describe(cap).contains("Defense"), "hovering shows what it does")
	screen.quick(screen._slot_rect("head").get_center())
	check.call(Game.equipped["head"].is_empty() and Game.index_in(Game.bag, cap) >= 0, "right-clicking a slot takes it off into the bag")
	screen.close()
	Game.remove_from(Game.bag, cap)
	hud.auto = true
	Game.hp = 10.0
	_sleep()
	check.call(Game.has_save() and is_equal_approx(Game.hp, Game.max_hp), "sleeping in the tent heals and saves the game")
	var slept_at := obj_index
	Game.bag = keep_bag
	Game.chest.clear()
	leave_home()

	# Waking where the game was saved.
	_finish_current_objective()
	Game.load_game()
	load_stage()
	check.call(obj_index == slept_at and player.indoors, "loading the save wakes the scout in the tent at the same point of the stage")
	check.call(Game.chest.size() == 2 and Game.ammo_count("stones", Game.chest) == heap_count and Game.pack == "shoulder_bag", "the chest and the bag are kept in the save")
	Game.chest.clear()
	Game.bag = keep_bag
	Game.pack = "pouch"
	leave_home()

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

	# The staff takes both hands: its blows are its own, and the left fist stays on the shaft.
	check.call(Game.is_two_handed(Game.new_item("staff")), "a staff takes both hands")
	Game.restore({"stage_index": 0, "equipped": {"hand_r": {"id": "staff", "plus": 0}, "hand_l": {"id": "hide_shield", "plus": 0}}, "bag": []})
	check.call(Game.equipped["hand_l"].is_empty() and Game.bag.any(func(it): return it["id"] == "hide_shield"), "a shield saved beside a staff goes into the bag")
	Game.restore({"stage_index": 0, "equipped": {"hand_r": {"id": "short_sword", "plus": 0}, "hand_l": {"id": "dagger", "plus": 0}}, "bag": []})
	check.call(Game.equipped["hand_l"].is_empty() and Game.bag.any(func(it): return it["id"] == "dagger"), "a blade saved in the left hand beside a sword goes into the bag")
	Game.new_game()
	var staffer = HumanScript.new()
	add_child(staffer)
	staffer.build({"sex": 0})
	staffer.set_hands("staff", "none")
	staffer.attack(0, "r", 1.0)
	check.call(str((staffer._blow_nodes["r"][0] as AnimationNodeAnimation).animation) == "Blow_A_R_staff", "a staff strikes with its own two-handed blow")
	check.call(not Game.has_perk("stomp") and player.combo_length() == 1, "and has just the one, a thrust with the butt, until the stomp is learned")
	for i in int(round(float(HumanScript.blows("staff")[0]["hit"]) * 60.0)):
		staffer.animate(1.0 / 60.0, 0.0)
		staffer._tree.advance(1.0 / 60.0)
	var sk: Skeleton3D = staffer.skeleton
	var right_hand: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r"))
	var left_hand: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_l"))
	var hold: Vector3 = right_hand * staffer._strike.origin
	var shaft: Vector3 = (right_hand.basis * staffer._strike.basis.y).normalized()
	var off: Vector3 = left_hand * staffer._strike_l.origin - hold
	var gap := (off - shaft * off.dot(shaft)).length()
	check.call(gap < 0.15 * staffer.scale.x + 0.02, "at the blow both fists are on the staff (%.0f cm apart from the shaft)" % (gap * 100.0))
	var butt_end: Vector3 = hold - shaft * HumanScript.STAFF_BUTT
	var fist_now: Vector3 = right_hand * (staffer._strike.origin + staffer._strike.basis.y.normalized() * HumanScript.STAFF_SLIDE)
	check.call(shaft.z > 0.6 and shaft.y > 0.2 and butt_end.z < fist_now.z - 0.8, "it strikes with the butt, driven forward from near the top of the staff (the top points %s)" % shaft.snappedf(0.01))
	var left_now: Vector3 = left_hand * staffer._strike_l.origin
	check.call(left_now.y < fist_now.y - 0.05 and (left_now - fist_now).length() > 0.25, "the right hand above the left, well apart (%.0f cm)" % ((left_now - fist_now).length() * 100.0))
	# Every other kind of weapon has blows of its own, in its own time.
	var styles_ok := true
	var style_note := ""
	for kind in ["dagger", "sickle", "axe", "club", "mace", "spear", "spear_long"]:
		for side in ["R", "L"]:
			for letter in ["A", "B", "C"]:
				var name := HumanScript.blow_clip(letter, side.to_lower(), kind)
				if not staffer._player.has_animation(name) or name == "Blow_%s_%s" % [letter, side]:
					styles_ok = false
					style_note += " " + name
	check.call(styles_ok, "daggers, sickle swords, axes, clubs, maces and spears each have their own blows" + style_note)
	check.call(HumanScript.blows("dagger")[0]["hit"] < HumanScript.blows("sword")[0]["hit"] and HumanScript.blows("axe")[0]["hit"] > HumanScript.blows("sword")[0]["hit"], "a dagger strikes sooner than a sword, an axe later")
	check.call(HumanScript.blows("spear")[0]["arc"] > 0.6 and HumanScript.blows("bludgeon")[2]["arc"] < 0.0, "a thrust reaches straight ahead, a wide swing to the sides")
	for kind in ["spear", "dagger"]:
		var thruster = HumanScript.new()
		add_child(thruster)
		thruster.build({"sex": 0})
		thruster.set_hands(kind, "none")
		thruster.attack(0, "r", 1.0)
		for i in int(round(float(HumanScript.blows(kind)[0]["hit"]) * 60.0)):
			thruster.animate(1.0 / 60.0, 0.0)
			thruster._tree.advance(1.0 / 60.0)
		var t_sk: Skeleton3D = thruster.skeleton
		var t_hand: Transform3D = t_sk.global_transform * t_sk.get_bone_global_pose(t_sk.find_bone("hand_r"))
		var point: Vector3 = (t_hand.basis * thruster._strike.basis.y).normalized()
		check.call(str((thruster._blow_nodes["r"][0] as AnimationNodeAnimation).animation) == "Blow_A_R_" + kind and point.z < -0.85 and absf(point.y) < 0.35,
			"a %s's first blow is a thrust: at the blow its point is straight ahead (%s)" % [kind, point.snappedf(0.01)])
		thruster.queue_free()
	staffer.queue_free()

	# The dust wind: many kinds of gust, no two alike; dust, grit and haze; not seen in the tent.
	var still_fog: float = environment.fog_density
	var kinds_seen := {}
	var gusts_seen := {}
	for i in 30:
		weather.start()
		var g: Dictionary = weather.gust
		kinds_seen[g["kind"]] = true
		gusts_seen["%s/%d/%d/%s" % [g["kind"], int(float(g["dir"]) * 10.0), int(float(g["speed"])), (g["color"] as Color).to_html()]] = true
	check.call(kinds_seen.size() >= 5 and gusts_seen.size() >= 28, "gusts of dust wind come in many kinds (%d) and no two alike (%d of 30)" % [kinds_seen.size(), gusts_seen.size()])
	weather.start("squall")
	weather._t = float(weather.gust["length"]) * 0.5
	weather._process(0.016)
	check.call(weather.strength > 0.3 and weather._parts["streaks"].emitting and weather._parts["debris"].emitting and environment.fog_density > still_fog * 3.0 and weather._lens.visible,
		"a squall blows dust, grit and haze across the land (strength %.2f)" % weather.strength)
	weather.start("devils")
	weather._t = float(weather.gust["length"]) * 0.5
	for d in weather._devils:
		d["age"] = 3.0
	weather._process(0.016)
	check.call(weather._devils.size() == 3 and weather._devils.all(func(d): return (d["node"] as Node3D).visible), "dust devils wander over the land")
	player.indoors = true
	weather._process(0.016)
	check.call(weather._parts.values().all(func(ps): return is_zero_approx((ps as GPUParticles3D).amount_ratio)) and not weather._lens.visible, "inside the tent the dust is not seen")
	player.indoors = false
	weather.stop()
	check.call(is_equal_approx(environment.fog_density, still_fog) and weather.gust.is_empty(), "when the wind drops the air clears")

	# The title screen: a view of the mountain, and the choice of a new or the saved journey.
	var title_screen = TitleScript.new()
	add_child(title_screen)
	title_screen.open(self)
	check.call(title_screen.mountain.mesh.get_faces().size() > 30000 and title_screen._height(TitleScript.SUMMIT.x, TitleScript.SUMMIT.z) > 500.0, "the title screen shows a high mountain")
	check.call(title_screen.buttons.has("new") and title_screen.buttons["load"].disabled == not Game.has_save(), "the title offers a new journey, and the saved one only if there is one")
	check.call(not is_equal_approx(environment.fog_density, still_fog), "the title has its own evening light")
	title_screen.close()
	title_screen.queue_free()
	player.cam.current = true
	check.call(is_equal_approx(environment.fog_density, still_fog), "and the stage's light comes back after it")

	# ---- Solid things: rocks stop the scout, and a low one can be jumped onto.
	if player.indoors:
		leave_home()
	Game.hp = Game.max_hp
	check.call(scenery.counts["solid"] > 40, "rocks, big bushes and trees are solid (%d of them)" % scenery.counts["solid"])
	var boulder: Array = []
	var low_rock: Array = []
	for s in scenery._solids:
		var rise: float = float(s[3]) - terrain.surface_y(float(s[0]), float(s[1]))
		if Vector2(float(s[0]), float(s[1])).length() > 185.0:
			continue      # beyond where the scout may go
		if boulder.is_empty() and float(s[2]) > 1.6 and rise > 1.7:
			boulder = s
		if low_rock.is_empty() and float(s[2]) > 0.75 and float(s[2]) < 1.3 and rise > 0.45 and rise < 0.9:
			low_rock = s
	check.call(not boulder.is_empty() and not low_rock.is_empty(), "the stage has boulders and lower rocks")
	if not boulder.is_empty():
		var rock_mid := Vector3(float(boulder[0]), 0.0, float(boulder[1]))
		player.global_position = ground(rock_mid.x, rock_mid.z + float(boulder[2]) + 1.8) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		player.yaw = 0.0           # facing north (-Z), toward the boulder
		await _wait(0.3)
		Input.action_press("move_forward")
		await _wait(1.3)
		Input.action_release("move_forward")
		var from_mid := Vector2(player.global_position.x - rock_mid.x, player.global_position.z - rock_mid.z).length()
		var above: float = player.global_position.y - terrain.surface_y(player.global_position.x, player.global_position.z)
		check.call(from_mid > float(boulder[2]) * 0.4 or above > 0.5, "the scout cannot walk into a boulder (stopped %.1f m from the middle of one %.1f m across)" % [from_mid, float(boulder[2]) * 2.0])
	if not low_rock.is_empty():
		var rock_mid := Vector3(float(low_rock[0]), 0.0, float(low_rock[1]))
		player.global_position = ground(rock_mid.x, rock_mid.z + float(low_rock[2]) + 1.2) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		player.yaw = 0.0
		await _wait(0.4)
		Input.action_press("move_forward")
		await _wait(0.1)
		player.jump()
		await _wait(0.22)
		Input.action_release("move_forward")
		var on_rock := false
		for i in 12:
			await _wait(0.1)
			var up: float = player.global_position.y - terrain.surface_y(player.global_position.x, player.global_position.z)
			on_rock = on_rock or (player.is_on_floor() and up > 0.25)
		check.call(on_rock, "the scout can jump onto a rock and stand on it")

	# ---- What a blow does besides its damage: dust, sound, and the enemy driven back.
	player.global_position = ground(0.0, 13.0) + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	player.yaw = PI
	await _wait(0.5)
	Game.sounds_played.clear()
	var bursts_before: int = fx.bursts
	player.jump()
	await _wait(1.0)
	check.call(fx.bursts > bursts_before and Game.sounds_played.has("land"), "landing from a jump raises dust and is heard")
	var struck = spawn_enemy("raider", player.global_position + player.forward() * 2.0, 1.0)
	struck.speed = 0.0
	struck.dmg = 0.0
	await _wait(0.3)
	var stood_at: Vector3 = struck.global_position
	bursts_before = fx.bursts
	player.melee()
	await _wait(1.7)
	check.call(struck.hp < struck.max_hp and Game.sounds_played.has("hit_flesh") and fx.bursts > bursts_before, "a blow that lands is heard and throws up grit")
	var driven: float = Vector2(struck.global_position.x - stood_at.x, struck.global_position.z - stood_at.z).length()
	check.call(driven > 0.05 and driven < 0.8, "and drives the enemy back a step (%.2f m)" % driven)
	struck.queue_free()
	for sound in Game.SOUND_TAKES:
		for take in int(Game.SOUND_TAKES[sound]):
			if not ResourceLoader.exists("res://assets/sounds/%s_%d.wav" % [sound, take + 1]):
				check.call(false, "the sound %s_%d is there" % [sound, take + 1])
	check.call(Game.SOUND_TAKES.size() >= 15, "the game has its sounds: swings, blows, the sling and bow, landings, finds, the anvil")

	# ---- The staff: through every blow the shaft stays outside the body, both hands on it.
	var staff_man = HumanScript.new()
	add_child(staff_man)
	staff_man.build({"sex": 0})
	staff_man.set_hands("staff", "none")
	staff_man._tree.active = false
	var staff_bones: Skeleton3D = staff_man.skeleton
	var place := func(bone: String) -> Vector3: return staff_bones.get_bone_global_pose(staff_bones.find_bone(bone)).origin
	var deepest := 0.0
	var loosest := 0.0
	for swing_name in ["Blow_A_R_staff", "Blow_Air_R_staff"]:
		var at := 0.0
		while at <= float(staff_man._player.get_animation(swing_name).length):
			staff_man._player.play(swing_name)
			staff_man._player.seek(at, true)
			staff_man._player.pause()
			await get_tree().process_frame
			var fist_r: Transform3D = staff_bones.get_bone_global_pose(staff_bones.find_bone("hand_r"))
			var hollow: Vector3 = fist_r * staff_man._strike.origin
			var runs: Vector3 = (fist_r.basis * staff_man._strike.basis.y).normalized()
			var butt: Vector3 = hollow - runs * HumanScript.STAFF_BUTT
			var tip: Vector3 = hollow + runs * HumanScript.STAFF_TIP
			deepest = maxf(deepest, float(HumanScript.shaft_depth(HumanScript.body_parts(place), butt, tip)[0]))
			var left_hollow: Vector3 = staff_bones.get_bone_global_pose(staff_bones.find_bone("hand_l")) * staff_man._strike_l.origin
			loosest = maxf(loosest, Geometry3D.get_closest_point_to_segment(left_hollow, butt, tip).distance_to(left_hollow))
			at += 0.02
	check.call(deepest < 0.012, "through every staff blow the shaft stays outside the body (%.0f mm in at the worst)" % (deepest * 1000.0))
	check.call(loosest < 0.08, "and the left hand stays on the shaft (%.0f mm off at the worst)" % (loosest * 1000.0))
	var kilt: MeshInstance3D = staff_bones.get_node_or_null("skirt_short")
	check.call(kilt != null and kilt.material_override is ShaderMaterial, "clothes are woven cloth")
	staff_man.queue_free()

	# ---- Saves: each sleep leaves its own, and an earlier one can be gone back to.
	Game.clear_saves()
	Game.silver = 11
	Game.save_game({"obj_done": 0})
	Game.silver = 22
	Game.save_game({"obj_done": 0})
	var kept: Array = Game.list_saves()
	check.call(kept.size() == 2 and int(kept[0]["silver"]) == 22 and int(kept[1]["silver"]) == 11, "each sleep leaves a save of its own, the newest first (%d saves)" % kept.size())
	check.call(Game.load_game(str(kept[1]["path"])) and Game.silver == 11, "an earlier save can be gone back to")
	for i in Game.MAX_SAVES + 3:
		Game.save_game()
	check.call(Game.list_saves().size() == Game.MAX_SAVES, "only the last %d saves are kept" % Game.MAX_SAVES)
	Game.clear_saves()

	# ---- The menu's pages, and the introduction shown once.
	var pages_ok := true
	hud.menu.limited = false
	for page_name in ["journey", "how", "saves", "settings"]:
		hud.menu.show_section(page_name)
		pages_ok = pages_ok and hud.menu._page.get_child_count() >= 2
	check.call(pages_ok, "the menu has its pages: the journey, how to play, saved journeys, settings")
	check.call(hud.get_child(0).theme == UiScript.theme() and UiScript.font("display") != UiScript.font(), "menus and text share one look and their own fonts")
	Game.intro_seen = Game.stage_index - 1
	_show_intro()
	check.call(Game.intro_seen == Game.stage_index and Game.snapshot()["intro_seen"] == Game.stage_index, "a stage's introduction is shown once, and that is remembered in the save")

	# ---- The smith forges as well as strengthens.
	Game.new_game()
	Game.silver = 200
	Game.bronze = 6
	var can_make: Array = Game.forge_list(2)
	check.call(can_make.size() >= 3 and can_make.all(func(r) -> bool: return int(Game.Items.ITEMS[r["item"]]["tier"]) <= 2), "the smith forges what the camp's craft has reached (%d things at first)" % can_make.size())
	var first_make: Dictionary = can_make[0]
	check.call(Game.try_forge(first_make) and Game.silver == 200 - int(first_make["silver"]) and Game.bronze == 6 - int(first_make["bronze"]) and not Game.bag_item(str(first_make["item"])).is_empty(), "forging takes silver and bronze and puts the new arm in the bag")
	Game.bronze = 0
	check.call(not Game.try_forge(first_make), "without bronze he cannot forge")
	var shoeing := {}
	for r in Game.forge_list(3):
		if r.has("needs"):
			shoeing = r
	Game.bronze = 5
	check.call(not shoeing.is_empty() and not Game.can_forge(shoeing), "to shoe a staff he needs a staff from the bag")
	Game.add_item("staff")
	check.call(Game.try_forge(shoeing) and Game.bag_item("staff").is_empty() and not Game.bag_item("shod_staff").is_empty(), "and the old staff goes into the new one")
	Game.new_game()

	# ---- The day: six hours of play to the day, the sun on its arc, and thirst that follows it.
	Game.clock = 23.0
	Game.day = 4
	Game.advance_clock(Game.DAY_SECONDS / 24.0 * 2.0)
	check.call(is_equal_approx(Game.clock, 1.0) and Game.day == 5, "two hours of the day pass in half an hour of play, and midnight starts the next day (%s)" % Game.clock_text())
	check.call(is_equal_approx(Game.DAY_SECONDS, 6.0 * 3600.0), "a day lasts six hours of play")
	Game.clock = 12.0
	daylight.apply(Game.clock, true)
	var noon_light: float = sun.light_energy
	var noon_dir: Vector3 = -sun.global_basis.z
	check.call(noon_dir.y < -0.85 and noon_dir.z < -0.2 and daylight.night < 0.01, "at noon the sun stands high in the south (light running %s)" % noon_dir.snappedf(0.01))
	Game.clock = 6.5
	daylight.apply(Game.clock, true)
	var morning_dir: Vector3 = -sun.global_basis.z
	check.call(morning_dir.x < -0.7 and morning_dir.y > -0.4 and sun.light_energy < noon_light, "in the morning it is low in the east and weaker (light running %s)" % morning_dir.snappedf(0.01))
	Game.clock = 17.5
	daylight.apply(Game.clock, true)
	check.call((-sun.global_basis.z).x > 0.7, "and in the evening low in the west")
	Game.clock = 0.5
	daylight.apply(Game.clock, true)
	var sky := environment.sky.sky_material as ProceduralSkyMaterial
	check.call(daylight.night > 0.95 and sun.light_energy < 0.3 and sky.sky_top_color.get_luminance() < 0.1, "at night the sky is dark and only the moon gives light")
	Game.clock = 12.0
	daylight.apply(Game.clock, true)
	var by_day: float = Game.thirst_rate(false, false)
	var running: float = Game.thirst_rate(true, false)
	var in_shade: float = Game.thirst_rate(false, true)
	Game.clock = 0.5
	var by_night: float = Game.thirst_rate(false, false)
	var through_day: float = (by_day * 12.0 + by_night * 12.0) * Game.DAY_SECONDS / 24.0
	check.call(through_day > 260.0 and through_day < 340.0, "thirst runs from full to nothing about three times a day (%.0f points a day)" % through_day)
	check.call(by_day > by_night * 1.4 and in_shade < by_day and running > by_day, "faster under the sun than at night or in a tent, and faster running")
	var robe := Game.add_item("long_robe")
	Game.equip(robe)
	check.call(Game.thirst_rate(false, false) < by_night, "a robe against the heat slows it")
	Game.unequip("top")
	Game.remove_from(Game.bag, robe)
	Game.equip(Game.bag_item("linen_tunic"))
	Game.equip(Game.bag_item("linen_kilt"))
	Game.thirst = 100.0
	check.call(is_equal_approx(Game.stamina_cap(), Game.max_stamina), "with water in you, all your breath is there")
	Game.thirst = 15.0
	check.call(Game.stamina_cap() < Game.max_stamina * 0.8 and Game.stamina_cap() > Game.max_stamina * Game.DRY_STAMINA_MIN, "under 30 thirst the most stamina you can have shrinks (%.0f)" % Game.stamina_cap())
	Game.stamina = Game.max_stamina
	Game.hp = Game.max_hp
	await _wait(0.3)
	check.call(Game.stamina <= Game.stamina_cap() + 0.01 and is_equal_approx(Game.hp, Game.max_hp), "stamina is held under it, and health is untouched while there is any thirst left")
	check.call(hud._stamina.cap < 0.8, "the stamina bar shows the part out of reach")
	Game.thirst = 0.0
	await _wait(1.0)
	check.call(Game.hp < Game.max_hp - 0.2, "with no thirst left at all, health drains (%.1f of %.0f)" % [Game.hp, Game.max_hp])
	Game.thirst = 100.0
	Game.hp = Game.max_hp
	Game.clock = 21.0
	Game.day = 2
	Game.sleep_to_morning()
	check.call(is_equal_approx(Game.clock, 6.0) and Game.day == 3, "sleeping takes you to the next morning")
	Game.clock = 14.25
	var day_snap: Dictionary = Game.snapshot()
	Game.new_game()
	Game.restore(day_snap)
	check.call(is_equal_approx(Game.clock, 14.25) and Game.day == 3, "the day and the hour are kept in the save")
	Game.new_game()

	# ---- Experience, levels and the four stats.
	Game.new_game()
	check.call(Game.level == 1 and Game.xp == 0 and Game.stat_points == 0, "a new scout starts at level 1")
	var lv_hp: float = Game.max_hp
	Game.gain_xp(Game.xp_needed(1) + 5)
	check.call(Game.level == 2 and Game.xp == 5 and Game.stat_points == Game.POINTS_PER_LEVEL and is_equal_approx(Game.max_hp, lv_hp + Game.HP_PER_LEVEL) and is_equal_approx(Game.hp, Game.max_hp),
		"enough experience makes a level: points to spend, more health, and wounds healed (level %d, %d points)" % [Game.level, Game.stat_points])
	var lv_blow: float = Game.melee_power()
	check.call(Game.spend_point("str") and is_equal_approx(Game.melee_power(), lv_blow * (1.0 + Game.STR_DAMAGE)), "strength makes blows harder")
	Game.spend_point("dex")
	Game.spend_point("luck")
	check.call(Game.stat_points == 0 and not Game.spend_point("int"), "points are spent one at a time and run out")
	check.call(is_equal_approx(Game.dodge_chance(), Game.DEX_DODGE) and is_equal_approx(Game.drop_bonus(), Game.LUCK_DROPS), "dexterity avoids blows and luck finds more")
	Game.stats["dex"] = 100
	var lv_landed := 0
	for i in 200:
		Game.hp = Game.max_hp
		player.take_damage(1.0)
		if Game.hp < Game.max_hp:
			lv_landed += 1
	check.call(lv_landed > 70 and lv_landed < 150, "a nimble scout slips many blows but never all (%d of 200 landed)" % lv_landed)
	Game.hp = Game.max_hp
	Game.stats["dex"] = 0
	Game.stats["int"] = 10
	var lv_dagger := Game.new_item("dagger")
	var lv_list_price: int = int(Game.Items.ITEMS["dagger"]["price"])
	check.call(Game.gain_xp(10) == 13 and Game.price(lv_dagger) < lv_list_price and Game.sell_value(lv_dagger) > int(lv_list_price * 0.35), "intelligence learns faster and bargains better (a dagger for %d, not %d)" % [Game.price(lv_dagger), lv_list_price])
	Game.stats["int"] = 0
	var lv_pelts := [0, 0]
	for lucky in 2:
		Game.stats["luck"] = 25 * lucky
		for i in 3000:
			for d in Game.roll_drops("jackal", 2, 1.0):
				lv_pelts[lucky] += 1
	Game.stats["luck"] = 0
	check.call(lv_pelts[1] > lv_pelts[0] * 1.12 and lv_pelts[1] < lv_pelts[0] * 1.4, "luck makes enemies drop a little more (%d against %d in 3000)" % [lv_pelts[1], lv_pelts[0]])
	var lv_got := [0]
	var lv_count := func(n: int) -> void: lv_got[0] += n
	Game.xp_gained.connect(lv_count)
	var lv_prey = spawn_enemy("jackal", player.global_position + Vector3(3, 0, 0), 1.0)
	lv_prey.take_damage(1e9)
	Game.xp_gained.disconnect(lv_count)
	check.call(lv_got[0] == int(round(float(Game.Enemies.ENEMIES["jackal"]["xp"]) * float(stage["mult"]))), "defeating an enemy gives its experience, more in the later stages (%d)" % lv_got[0])
	Game.level = 7
	Game.xp = 33
	Game.stat_points = 2
	Game.stats = {"str": 3, "dex": 1, "int": 2, "luck": 4}
	var lv_snap: Dictionary = Game.snapshot()
	Game.new_game()
	Game.restore(lv_snap)
	check.call(Game.level == 7 and Game.xp == 33 and Game.stat_points == 2 and int(Game.stats["luck"]) == 4 and int(Game.stats["str"]) == 3, "level, experience and stats are kept in the save")
	Game.hp = 41.0
	Game.thirst = 62.4
	await get_tree().process_frame
	await get_tree().process_frame
	# (Health and thirst move a little between the bar being drawn and this check: compare loosely.)
	check.call(hud._hp.label == "Health" and absf(float(hud._hp.value_text.get_slice(" / ", 0)) - Game.hp) < 2.0 and hud._hp.value_text.ends_with(" / %d" % int(round(Game.max_hp))) and hud._hp.ratio < 0.5
		and absf(float(hud._thirst.value_text.get_slice(" / ", 0)) - Game.thirst) < 2.0 and hud._thirst.value_text.ends_with(" / 100")
		and hud._stamina.value_text.contains("/") and hud._xp.label == "Level 7" and hud._xp.value_text.begins_with("33 / ") and hud._points.visible and hud._points.text.begins_with("2 points"),
		"health, thirst, stamina and experience are bars with their numbers written in them (%s | %s | %s %s)" % [hud._hp.value_text, hud._thirst.value_text, hud._xp.label, hud._xp.value_text])
	check.call(hud._thirst.pips == Game.water and hud._thirst.pips_max == Game.max_water, "the drinks left in the waterskin are marked after the thirst bar")
	check.call(not Game.equipped["sling"].is_empty() and hud._stones.visible and hud._stones.text == "Stones %d" % Game.stones(), "with a sling equipped the stones are counted on screen (%s)" % hud._stones.text)
	var lv_sling: Dictionary = Game.equipped["sling"]
	Game.unequip("sling")
	await get_tree().process_frame
	await get_tree().process_frame
	check.call(not hud._stones.visible, "and with no sling or bow, no ammunition is shown")
	Game.equip(lv_sling)
	check.call(Game.places() == 40 and Game.Items.PACK_ORDER.find(Game.pack) == 0, "the first bag holds 40 places")
	hud.menu.show_section("scout")
	check.call(hud.menu._page.get_child_count() >= 8, "the menu has a page for the scout's level and stats")
	Game.new_game()

	# A save from before the bag had places still loads: old slots, counted stones.
	Game.restore({"stage_index": 1, "silver": 40, "equipped": {"melee": {"id": "dagger", "plus": 1}, "sling": {"id": "braided_sling", "plus": 0},
		"armor": {"id": "cloak", "plus": 0}}, "bag": [{"id": "leather", "plus": 0}, {"id": "staff", "plus": 0}], "stones": 7, "chest": [{"id": "linen", "plus": 1}], "chest_stones": 3})
	check.call(Game.equipped["hand_r"]["id"] == "dagger" and int(Game.equipped["hand_r"]["plus"]) == 1 and Game.equipped["sling"]["id"] == "braided_sling", "an old save keeps its weapon and sling")
	check.call(Game.equipped["top"]["id"] == "linen_tunic" and Game.equipped["bottom"]["id"] == "linen_kilt", "an old save's travel cloak becomes tunic and kilt")
	check.call(Game.stones() == 7 and Game.ammo_count("stones", Game.chest) == 3 and Game.bag.any(func(it): return it["id"] == "leather") and Game.chest.size() == 2, "an old save's stones and gear are laid out in the bag and the chest")
	Game.new_game()

	# Out in the wilds: the beasts of the region, bands of other peoples, and the caravans.
	for k in ["wolf", "hyena", "leopard", "lion", "bear"]:
		var wb = spawn_enemy(k, player.global_position + Vector3(25, 0, 25), 1.0)
		check.call(wb._beast != null and wb._beast._jaw != null and Game.Drops.DROPS.has(k) and int(Game.Enemies.ENEMIES[k]["xp"]) > 0,
			"the %s is a four-legged animal with a jaw that bites, worth experience, with spoils to drop" % k)
		wb.queue_free()
	for line in encounters.Encounters.BEASTS:
		check.call(Game.Enemies.ENEMIES.has(str(line["kind"])), "the encounter table's %s is a known animal" % line["kind"])
	for line in encounters.Encounters.BANDS:
		check.call(Game.Enemies.PEOPLES.has(str(line["people"])), "the encounter table's %s are a known people" % line["people"])
	for people in ["Edomite", "Moabite"]:
		var sol: Dictionary = Game.Enemies.soldier(people, "raider", false, rng)
		var chief_dress: Dictionary = Game.Enemies.soldier(people, "boss", true, rng)
		check.call(sol.has("right") and sol.has("wear") and chief_dress.has("wear"), "the %s fighting men and their chief are dressed and armed" % people)
	var ed = spawn_enemy("raider", player.global_position + Vector3(25, 0, -25), 1.0, {"people": "Edomite"})
	check.call(ed.display_name.begins_with("Edomite"), "a man of a band is named by his people (%s)" % ed.display_name)
	ed.queue_free()

	# A hurt hyena runs off; a leopard creeps up low, then springs; a bear is hard to drive back.
	var hy = spawn_enemy("hyena", player.global_position + Vector3(4, 0, 0), 1.0)
	hy.take_damage(hy.max_hp * 0.7)
	for i in 25:
		await get_tree().physics_frame
	check.call(hy._fleeing and hy.global_position.distance_to(player.global_position) > 4.5, "a hurt hyena runs off (%.1f m)" % hy.global_position.distance_to(player.global_position))
	hy.queue_free()
	var cat = spawn_enemy("leopard", player.global_position + Vector3(18, 0, 0), 1.0, {"hunting": true})
	for i in 30:
		await get_tree().physics_frame
	check.call(cat._stalking and cat._beast.crouch > 0.5 and Vector2(cat.velocity.x, cat.velocity.z).length() < cat.speed * 0.5,
		"a leopard creeps up low and slow (crouch %.2f)" % cat._beast.crouch)
	cat.global_position = player.global_position + Vector3(5, 0.3, 0)
	for i in 3:
		await get_tree().physics_frame
	check.call(not cat._stalking and cat._spring > 0.0, "and springs when it is close")
	cat.queue_free()
	var bear = spawn_enemy("bear", player.global_position + Vector3(2.5, 0, 0), 1.0)
	bear.take_damage(1.0, player)
	check.call(bear._knock.length() < 1.0, "a bear is hard to drive back")
	bear.queue_free()

	# Encounters come only far from the camp, in sight, and go once left behind.
	var enc_back: Vector3 = player.global_position
	encounters.stopped = false
	encounters.wait = 0.0
	for i in 3:
		await get_tree().process_frame
	check.call(encounters.active.is_empty(), "nothing is met in or near the camp")
	player.global_position = ground(camp_pos.x + camp_radius + 120.0, camp_pos.z)
	for i in 3:
		await get_tree().process_frame
	check.call(not encounters.active.is_empty(), "wandering far from the camp brings an encounter")
	if not encounters.active.is_empty():
		var em: Node3D = encounters.active["members"][0]
		var ed0 := em.global_position.distance_to(player.global_position)
		check.call(ed0 > 15.0 and ed0 < 60.0, "it comes into sight, not on top of the scout (%.0f m)" % ed0)
	player.global_position = ground(camp_pos.x - camp_radius - 180.0, camp_pos.z)
	for i in 3:
		await get_tree().process_frame
	check.call(encounters.active.is_empty() and encounters.wait > 30.0, "an encounter left behind goes, and the next comes later")
	encounters.stopped = true
	for k in ["lion", "Edomite", "band"]:
		check.call(encounters.start(k, true) and not encounters.active.is_empty(), "a %s can be met" % k)
		for n in encounters.active["members"]:
			n.queue_free()
		encounters.active = {}
	check.call(not encounters.start("tiger", true), "nothing is met that does not belong to the region")

	# A caravan: rare goods at a price, gone once bought.
	player.global_position = ground(camp_pos.x + camp_radius + 120.0, camp_pos.z)
	encounters.start("caravan", true)
	var car: Dictionary = encounters.active
	var car_stock: Array = car["stock"]
	check.call(car_stock.size() >= 2 and car_stock.all(func(it): return Game.rarity(it) >= 1 and Game.price(it) > 0), "a caravan sells only rare and legendary finds, at a price (%d)" % car_stock.size())
	check.call(is_instance_valid(car["trader"]) and car["trader"].prompt_text().begins_with("Trade") and get_markers().any(func(m): return m["text"] == "Caravan")
		and get_map_points().any(func(m): return m["kind"] == "trader"), "its trader can be traded with, and is marked on the screen and the map")
	check.call(car["members"].size() == 5 and car["members"].filter(func(n): return n is CreatureScript).size() == 2, "the trader comes with two pack donkeys and two guards")
	var deal: Dictionary = car_stock[0]
	Game.silver = Game.price(deal) + 5
	hud.inventory.open("trade", 1, Callable(), {"stock": car_stock, "title": car["title"]})
	hud.inventory._buy(deal)
	check.call(Game.silver == 5 and Game.index_in(car_stock, deal) < 0 and Game.bag.any(func(it): return it["id"] == deal["id"]), "buying from it takes the silver, and the piece is gone from its goods")
	hud.inventory.close()
	check.call(Game.price(Game.new_item("khopesh")) == Game.Encounters.price_of(3, 1) and Game.price(Game.new_item("elders_staff")) == Game.Encounters.price_of(4, 2), "rare and legendary pieces are priced by their tier")
	for n in car["members"]:
		if is_instance_valid(n):
			n.queue_free()
	encounters.active = {}
	player.global_position = enc_back
	Game.new_game()

	# The weapon skill trees: learned by use, spent tier by tier, kept in the save.
	Game.new_game()
	await get_tree().process_frame
	var skl = Game.Skills
	check.call(skl.xp_for_step(1) == 20 and skl.xp_for_step(2) == 55 and skl.xp_for_step(12) == 1230, "each step of a skill needs 15 more than the last")
	check.call(Game.train("staff", 19) == 0 and Game.train("staff", 1) == 1 and int(Game.skill_points["staff"]) == 1 and Game.skill_step("staff") == 1, "using a weapon raises its skill, and each step gives its tree a point")
	check.call(Game.tree_of("mace") == "club" and Game.tree_of("spear_long") == "spear" and Game.tree_of("bow") == "bow" and Game.tree_of("none") == "", "every weapon trains its own tree")
	check.call(Game.why_not("ward_off").begins_with("Opens"), "tier II is closed until two points are spent in the tree")
	check.call(Game.learn("walking_staff") and not Game.learn("drive_back") and int(Game.skill_points["staff"]) == 0, "a skill costs the tree's points")
	Game.skill_points["staff"] = 20
	for id in ["drive_back", "ward_off", "against_wolves", "stomp", "heavy_stomp", "steady_guard"]:
		check.call(Game.learn(id), "the staff's %s can be learned in turn" % id)
	check.call(Game.spent_in("staff") == 9 and Game.why_not("shepherd").contains("level"), "the capstone also waits for level %d" % skl.CAPSTONE_LEVEL)
	Game.level = skl.CAPSTONE_LEVEL
	check.call(Game.why_not("shepherd") == "", "and then opens")
	var sk_snap: Dictionary = Game.snapshot()
	Game.new_game()
	Game.restore(sk_snap)
	check.call(Game.has_perk("stomp") and int(Game.skill_points["staff"]) == 12 and int(Game.skill_xp["staff"]) == 20, "skills, points and use are kept in the save")
	check.call(player.combo_length() == 2 and player.blow_table(0)["chain"] < 100.0 and player.body._player.has_animation("Blow_B_R_staff"), "with the stomp learned, the staff's thrust goes on into the stomp")
	# The stomp knocks down what is near and dazes it; a blow that lands trains the staff.
	var sk_near: Array = []
	for k in 2:
		var j = spawn_enemy("jackal", player.global_position + Vector3(1.6 if k == 0 else -1.6, 0.0, 0.8), 1.0)
		j.speed = 0.0
		sk_near.append(j)
	var sk_before := int(Game.skill_xp.get("staff", 0))
	player._stomp(player.blow_table(1), "staff")
	check.call(sk_near.all(func(j): return j.dead or (j._daze > 1.0 and j._down and j.hp < j.max_hp)), "the stomp strikes, knocks down and dazes everything near")
	check.call(int(Game.skill_xp["staff"]) >= sk_before + 1, "and teaches the staff")
	for j in sk_near:
		if is_instance_valid(j) and not j.dead:
			j.last_tree = "staff"
			j.take_damage(1e9, player)
	check.call(int(Game.skill_xp["staff"]) >= sk_before + 1 + 5, "felling an enemy teaches the weapon that did it")
	# Armour and shields count; wounds, slows and broken swings work.
	check.call(absf(Game.Enemies.armour_of({"wear": [["vest", Game.Enemies.BRONZE]], "head": [["helmet", Game.Enemies.BRONZE]]}) - 0.26) < 0.001 and Game.Enemies.armour_of({"wear": [["skirt_short", "cloth"]], "head": []}) == 0.0, "bronze scale and a helmet stop part of a blow")
	var sk_man = spawn_enemy("raider", player.global_position + Vector3(0, 0, -6), 1.0)
	sk_man.speed = 0.0
	sk_man.dmg = 0.0
	sk_man.armor = 0.0
	sk_man.shield_hp = 2
	var sk_to: Vector3 = player.global_position - sk_man.global_position
	sk_man._vis.rotation.y = atan2(-sk_to.x, -sk_to.z)
	var sk_hp: float = sk_man.hp
	sk_man.take_damage(10.0, player)
	check.call(absf(sk_hp - sk_man.hp - 6.0) < 0.01 and sk_man.on_shield, "a shield turned to the blow stops part of it (%.1f)" % (sk_hp - sk_man.hp))
	sk_man._vis.rotation.y += PI
	sk_hp = sk_man.hp
	sk_man.take_damage(10.0, player)
	check.call(absf(sk_hp - sk_man.hp - 10.0) < 0.01, "but not a blow from behind")
	Game.perks["shield_splitter"] = true
	sk_man._vis.rotation.y -= PI
	sk_man.take_damage(1.0, player)
	sk_man.split_shield()
	sk_man.take_damage(1.0, player)
	check.call(sk_man.split_shield() and sk_man.shield_hp == 0, "two axe blows on a shield split it")
	sk_hp = sk_man.hp
	sk_man.bleed(6.0, 0.4)
	for i in 40:
		await get_tree().physics_frame
	check.call(absf(sk_hp - sk_man.hp - 6.0) < 0.6, "a bleeding wound goes on hurting (%.1f)" % (sk_hp - sk_man.hp))
	sk_man.slow(0.5, 2.0)
	sk_man._windup = 0.3
	sk_man.interrupt()
	check.call(sk_man._slow > 1.0 and sk_man._slow_f == 0.5 and sk_man._windup < 0.0, "a struck enemy can be slowed and its swing broken off")
	sk_man.queue_free()
	# The sword's fourth cut, and throwing a knife that is then picked up again.
	var sk_sword := Game.add_item("short_sword")
	Game.equip(sk_sword)
	Game.perks["fourth_cut"] = true
	check.call(player.combo_length() == 4 and player.blow_table(2)["chain"] < 100.0 and str(player.blow_table(3).get("letter", "")) == "D" and player.body._player.has_animation("Blow_D_R"), "the Fourth Cut adds a rising cut to the sword's combo")
	var sk_knife := Game.add_item("dagger")
	Game.equip(sk_knife)
	Game.perks["thrown_knife"] = true
	player._throw_weapon("hand_r", Game.weapon_in("hand_r"), "dagger")
	check.call(Game.weapon_in("hand_r").is_empty(), "a thrown knife leaves the hand")
	var sk_lying: Array = []
	for i in 240:
		await get_tree().physics_frame
		sk_lying = get_tree().get_nodes_in_group("pickup").filter(func(pk): return pk.payload is Dictionary and str(pk.payload["id"]) == "dagger")
		if not sk_lying.is_empty():
			break
	check.call(sk_lying.size() == 1, "and lies where it falls")
	if not sk_lying.is_empty():
		player.global_position = sk_lying[0].global_position + Vector3(0, 0.3, 0)
		for i in 4:
			await get_tree().process_frame
		check.call(Game.kind(Game.weapon_in("hand_r")) == "dagger", "walking over it puts it back in the hand")
	hud.menu.show_section("skills")
	var sk_stand: Array = hud.menu._page.get_children().filter(func(c): return c.has_method("node_at"))
	if sk_stand.size() == 1:
		sk_stand[0]._layout()
		var sk_nodes: Array = sk_stand[0].nodes
		check.call(sk_nodes.size() == 8 and sk_nodes[0]["pos"].y > sk_nodes[2]["pos"].y and sk_nodes[2]["pos"].y > sk_nodes[5]["pos"].y and sk_nodes[5]["pos"].y > sk_nodes[7]["pos"].y,
			"the Skills page draws each tree as the lampstand: basic skills on its foot, the capstone in its top lamp")
		sk_stand[0].picked.emit("ward_off")
		check.call(hud.menu._skill_shown == "ward_off", "clicking a skill on it shows that skill")
	else:
		check.call(false, "the Skills page has the lampstand")
	Game.new_game()

	# Things to stand on: the camp's barrels, jars and baskets are solid, and hold the scout up.
	var bt_round: Array = camp.find_children("*", "StaticBody3D", true, false).filter(func(b): return (b.get_child(0) as CollisionShape3D).shape is CylinderShape3D)
	check.call(bt_round.size() >= 10, "the camp's barrels, jars and baskets are solid (%d)" % bt_round.size())
	if not bt_round.is_empty():
		var bt_jar: StaticBody3D = bt_round[0]
		var bt_top: Vector3 = bt_jar.global_position + Vector3(0, (bt_jar.get_child(0).shape as CylinderShape3D).height * 0.5, 0)
		var bt_back: Vector3 = player.global_position
		player.global_position = bt_top + Vector3(0, 0.25, 0)
		player.velocity = Vector3.ZERO
		for i in 40:
			await get_tree().physics_frame
		check.call(player.is_on_floor() and player.global_position.y > bt_top.y - 0.15, "the scout can stand on top of a jar or barrel (%.2f above its top)" % (player.global_position.y - bt_top.y))
		player.global_position = bt_back

	# Battle mode: the stance comes in with the weapon held ready, and goes again.
	player.refresh_gear()
	await get_tree().process_frame
	player.set_battle(false)
	check.call(player.body._player.has_animation("Guard_staff") and player.body._player.has_animation("Guard_sword") and str((player.body._guard_clips[1] as AnimationNodeAnimation).animation) == "Guard_staff",
		"each way of fighting has a battle stance, and the staff in hand takes the staff's")
	player.set_battle(true, false)
	for i in 30:
		await get_tree().process_frame
	check.call(player.body.battle and player.body._guard > 0.9 and player.body.weapon.transform.origin.distance_to(player.body._strike.origin) < 0.05,
		"in battle mode the scout stands ready, the staff gripped in both hands (%.2f)" % player.body._guard)
	player.toggle_sheathe()
	check.call(not player.battle, "putting the weapon away stands the scout at ease")
	for i in 30:
		await get_tree().process_frame
	player.toggle_sheathe()
	for i in 30:
		await get_tree().process_frame
	player.melee()
	check.call(player.battle and player._battle_auto, "striking puts the scout in battle mode")
	player._calm = player.BATTLE_CALM
	player._calm_check = 1.0
	player.combo = -1
	await get_tree().process_frame
	check.call(not player.battle, "and when all is quiet again it is left")
	for i in 40:
		await get_tree().process_frame

	# Walking back to the land of an earlier stage, and coming back to the camp as it was left.
	Game.new_game()
	Game.look_set = true
	Game.stage_index = 1
	load_stage()
	await get_tree().process_frame
	var wb_obj: int = obj_index
	Game.hp = 37.0
	quests.list[0]["status"] = "done"
	check.call(can_travel_back(), "from the camp of stage 2 the scout can walk back to stage 1's land")
	travel_back(0)
	await get_tree().process_frame
	check.call(Game.visiting == 0 and stage["name"] == Game.Stages.LIST[0]["name"] and camp == null and quests == null and raid == null and objective_text().contains("Go back to the camp"),
		"walking back loads the earlier land, with no camp, quests, raids or missions")
	check.call(is_equal_approx(Game.hp, 37.0) and Game.snapshot()["stage_index"] == 1, "health is as it was, and the journey is still at stage 2")
	check.call(not can_travel_back(), "and from there the scout cannot go further back")
	return_to_camp()
	await get_tree().process_frame
	check.call(Game.visiting == -1 and stage["name"] == Game.Stages.LIST[1]["name"] and camp != null and obj_index == wb_obj and quests.list[0]["status"] == "done" and absf(Game.hp - 37.0) < 1.0,
		"coming back finds the camp as it was left, finished side quests still finished (health %.1f)" % Game.hp)

	# Of several bosses (the five kings of Midian), only the last to fall leaves the legendary.
	obj = {"type": "boss", "text": "Test", "done": "Test", "drop": "kings_khopesh"}
	obj_need = 2
	obj_count = 0
	obj_nodes = []
	_obj_closed = true
	var wb_kings: Array = []
	for k in 2:
		var king_e = spawn_enemy("boss", player.global_position + Vector3(8.0 + k * 3.0, 0.0, 8.0), 1.0, {"boss": true, "name": "King"})
		obj_nodes.append(king_e)
		wb_kings.append(king_e)
	var wb_count := func() -> int: return get_tree().get_nodes_in_group("pickup").filter(func(pk): return pk.kind == "item" and str(pk.payload) == "kings_khopesh").size()
	wb_kings[0].take_damage(1e9)
	var wb_first: int = wb_count.call()
	wb_kings[1].take_damage(1e9)
	check.call(wb_first == 0 and wb_count.call() == 1, "of several kings, only the last to fall leaves the legendary sword")
	obj = {}
	_obj_closed = false
	Game.new_game()

	# Special places of stages 1 to 3: where they lie, resting, finding, clearing, remembered.
	Game.new_game()
	Game.look_set = true
	Game.stage_index = 0
	load_stage()
	await get_tree().process_frame
	var pl_ids: Array = places.list.map(func(e): return str(e["def"]["id"]))
	check.call(pl_ids.has("elim") and pl_ids.has("shore") and places.list.all(func(e): return e.has("at") and Vector2(e["at"].x, e["at"].z).length() <= walk_limit),
		"stage 1 has Elim and the shore of the crossing, both within reach (%s)" % str(pl_ids))
	var pl_shore: Dictionary = places.list.filter(func(e): return str(e["def"]["id"]) == "shore")[0]
	check.call(walk_limit > PlayerScript.LIMIT and pl_shore["guards"].size() == 5 and pl_shore["guards"].any(func(g): return g.unique and g.display_name == "The scarred old hyena"),
		"the shore lies beyond the usual bounds, guarded by scavengers and a scarred old hyena")
	Game.water = 0
	Game.thirst = 30.0
	places._drink()
	check.call(Game.water == Game.max_water and Game.thirst >= 99.0, "a rest place fills the waterskin")
	var pl_elim: Dictionary = places.list.filter(func(e): return str(e["def"]["id"]) == "elim")[0]
	player.global_position = pl_elim["at"] + Vector3(2.0, 0.6, 2.0)
	for i in 30:
		await get_tree().process_frame
	check.call(Game.places_seen.has("elim"), "coming to a place names it, and marks it on the map")
	for g in pl_shore["guards"]:
		if is_instance_valid(g) and not g.dead:
			g.take_damage(1e9)
	for i in 30:
		await get_tree().process_frame
	var pl_reward: bool = get_tree().get_nodes_in_group("pickup").any(func(pk): return pk.kind == "item" and str(pk.payload) == "khopesh")
	check.call(Game.places_done.has("shore") and pl_reward, "a place cleared of its guardians leaves its reward")
	load_stage()
	await get_tree().process_frame
	var pl_shore2: Dictionary = places.list.filter(func(e): return str(e["def"]["id"]) == "shore")[0]
	check.call(pl_shore2["guards"].is_empty(), "and stays cleared")
	Game.stage_index = 1
	load_stage()
	await get_tree().process_frame
	var pl_hill: Dictionary = places.list.filter(func(e): return str(e["def"]["id"]) == "raised_hands")[0]
	var pl_xp: int = Game.xp
	player.global_position = pl_hill["at"] + Vector3(1.0, 0.6, 1.0)
	for i in 30:
		await get_tree().process_frame
	var pl_gain: int = Game.xp - pl_xp
	player.global_position = ground(0.0, 13.0) + Vector3(0, 0.6, 0)
	for i in 10:
		await get_tree().process_frame
	player.global_position = pl_hill["at"] + Vector3(1.0, 0.6, 1.0)
	for i in 30:
		await get_tree().process_frame
	check.call(pl_gain > 0 and Game.xp - pl_xp == pl_gain and Game.places_done.has("raised_hands"), "a landmark gives its experience once (%d)" % pl_gain)
	check.call(places.list.size() == 3, "stage 2 has its three places")
	Game.stage_index = 2
	load_stage()
	await get_tree().process_frame
	var pl3: Array = places.list.map(func(e): return str(e["def"]["id"]))
	var pl_ledge: Array = places.list.filter(func(e): return str(e["def"]["id"]) == "leopard_ledge")
	check.call(pl3.size() == 3 and not pl_ledge.is_empty() and pl_ledge[0]["guards"].any(func(g): return g.unique and g.kind == "leopard"),
		"stage 3 has the bounds, the brook and the grey leopard's ledge (%s)" % str(pl3))
	var pl_snap: Dictionary = Game.snapshot()
	check.call(pl_snap["places_done"].has("shore") and pl_snap["places_seen"].has("elim"), "places seen and cleared are kept in the save")
	Game.new_game()

	# Settings, music and the bars in the corner.
	Game.settings["music"] = 0.3
	Game.apply_settings()
	check.call(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.3)) < 0.01, "the music volume setting turns the music down")
	Game.settings["music"] = Game.DEFAULT_SETTINGS["music"]
	Game.apply_settings()
	check.call(ResourceLoader.exists(Game.MUSIC[0]) and ResourceLoader.exists(Game.MUSIC[1]), "the background music is there")
	hud._stats.text = "Facing a very long way round to the south-south-west, and further still than that"
	await get_tree().process_frame
	check.call(hud._hp.size.x < 390.0 and hud._stamina.size.x < 390.0, "the bars keep their width whatever the text beside them says (%.0f)" % hud._hp.size.x)

	print("SELFTEST %s  (%d failed)" % ["OK" if fails.is_empty() else "FAILED", fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)
