extends CharacterBody3D
## Third-person player: movement, camera, thirst, melee weapons, the sling and the bow.

const ProjectileScript := preload("res://scripts/projectile.gd")
const HumanScript := preload("res://scripts/human.gd")
const WALK := 6.0
const SPRINT := 9.5
const JUMP := 6.5
const GRAVITY := 20.0
## Walking into something no higher than STEP_UP, the scout steps onto it; jumping against
## something whose top is within CLIMB_UP of the feet, the scout scrambles up onto it.
const STEP_UP := 0.5
const CLIMB_UP := 1.5
const SCRAMBLE := 5.0
const LIMIT := 205.0
const SENS := 0.0026
const ARM_LENGTH := 5.4
const ARM_INDOORS := 2.5
const ARM_OFFSET := Vector3(0.95, 0.25, 0)
## Stamina: sprinting spends it, walking slowly wins it back, standing still a little faster.
## Once it runs out you cannot sprint again until RECOVER of it has come back.
const STAMINA_SPRINT := 20.0
const STAMINA_WALK := 6.0
const STAMINA_REST := 10.0
const STAMINA_RECOVER := 30.0
## Damage of each blow of the combo (A, B, C), times the weapon's damage.
const BLOW_POWER := [1.0, 1.1, 1.4]
## Sling stones and arrows: how fast they leave, and how fast they drop.
const STONE_SPEED := 40.0
const ARROW_SPEED := 62.0
const SHOT_DROP := 5.0
const CHARGE_TIME := 0.4   # attack held this long makes a charged blow (or a throw)

var world
var yaw := 0.0
var pitch := -0.2
var pivot: Node3D
var cam: Camera3D
var body: Node3D          # the human figure
var dead := false
var indoors := false      # inside the player's own tent, which stands apart from the stage
var focus: Node = null
var combo := -1           # the blow of the combo in progress (0, 1, 2), or -1
var _arm: SpringArm3D
var _combo_t := 0.0
var _combo_next := false  # attack was pressed again during the blow: the next one follows
var _hit_done := false
var _blow_hand := "r"     # the hand making the blow in progress
var _blow_speed := 1.0
var _attack_waiting := false   # attack pressed while the weapon was put away: strike once it is drawn
var _sling_cd := 0.0
var _slinging := false    # the sling is going round; it is let go when the button is released
var _sling_t := 0.0
var _sling_let_go := false
var _aiming_bow := false
var _sprinting := false
var _jumping := false     # off the ground because of a jump, not a step down
var _air_t := 0.0         # seconds since the feet left the ground
var _moving := false
var _swished := false      # the blow under way has made its sound
var _stride := 0.0         # seconds since a running foot last kicked up dust
var _shake := 0.0          # how hard the camera is being jolted, 0..1
var _tired := false
var _thirst_warned := 0
var _edge_warn := 0.0
var _creator_view := ""   # "", "body" or "face" while the character creator is open
var _creator_turn := 0.0
var _worn_key := ""
var _aim: Node3D          # where a stone or arrow would come down: a ring and a dotted arc
var _aim_ring: MeshInstance3D
var _aim_dots: Array = []
var aim_point := Vector3.ZERO   # where the marker is now
var aim_on_target := false      # the marker is on an enemy
# The weapon skills (data/skills.gd) in play:
var _charging := false     # attack is held at the start of a blow that can be charged
var _charge_t := 0.0
var _charged := false      # the blow under way was held long enough
var _throwing := false     # the blow under way throws the weapon instead
var _haste := 0.0          # the next blow is this much quicker (Cleave Onward, Shepherd)
var _riposte := 0.0        # seconds in which a sword blow ripostes
var _twice := 0.0          # seconds in which the next blow strikes twice (Blade of the Pharaohs)
var _streak := 0           # kills in quick succession (Captain of Thousands)
var _streak_t := 0.0
var _ranks := 0            # club blows landed (Breaker of Ranks)
var _brace_cd := 0.0
var _quick_stone := 0.0    # seconds in which the sling needs no wind-up (Second Stone)
var _draw_t := 0.0         # seconds the bow has been drawn
var _slip := 0.0           # seconds of a quick step back (Slip Away)
## Battle mode: the figure stands alert with its weapon held ready (HumanScript `battle`).
## Taken with F, or on its own when the scout fights or is struck; a stance taken on its own is
## left after BATTLE_CALM quiet seconds with no enemy within BATTLE_NEAR metres.
const BATTLE_CALM := 10.0
const BATTLE_NEAR := 18.0
var battle := false
var _battle_auto := false
var _calm := 0.0
var _calm_check := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.5
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	body = HumanScript.new()
	add_child(body)
	rebuild_figure()
	Game.look_changed.connect(rebuild_figure)
	Game.gear_changed.connect(refresh_gear)

	pivot = Node3D.new()
	pivot.position = Vector3(0, 1.7, 0)
	pivot.rotation = Vector3(pitch, yaw, 0.0)
	add_child(pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = ARM_LENGTH
	_arm.margin = 0.3
	_arm.collision_mask = 1
	_arm.position = ARM_OFFSET
	# Keeps the camera in place while a dialog pauses the game.
	_arm.process_mode = Node.PROCESS_MODE_ALWAYS
	_arm.add_excluded_object(get_rid())
	pivot.add_child(_arm)
	cam = Camera3D.new()
	cam.fov = float(Game.settings["fov"])
	cam.far = 6000.0
	_arm.add_child(cam)
	cam.current = true
	Game.settings_changed.connect(func() -> void: cam.fov = float(Game.settings["fov"]))
	_make_aim()


## Rebuilds the figure from the saved appearance and what is worn. Called when the creator
## changes something, or a garment is put on or taken off.
func rebuild_figure() -> void:
	_worn_key = str(Game.worn_pieces()) + str(Game.head_pieces())
	# The figure keeps animating while the game is paused, so it is alive in the character creator.
	body.build(Game.look, {"always_animate": true, "wear": Game.worn_pieces(), "head_wear": Game.head_pieces()})
	_show_hands()


## Called when equipment changes: new clothes rebuild the figure; otherwise only the hands change.
func refresh_gear() -> void:
	if str(Game.worn_pieces()) + str(Game.head_pieces()) != _worn_key:
		rebuild_figure()
	else:
		_show_hands()


## Shows what each hand holds. A bow takes both hands and is held in the left.
func _show_hands() -> void:
	var r: Dictionary = Game.equipped["hand_r"]
	var l: Dictionary = Game.equipped["hand_l"]
	if Game.kind(r) == "bow":
		body.set_hands("none", "bow", Color(0, 0, 0, 0), _tint(r))
	else:
		body.set_hands(Game.kind(r), Game.kind(l), _tint(r), _tint(l))


func _tint(inst: Dictionary) -> Color:
	return Color(0, 0, 0, 0) if inst.is_empty() else Game.item_def(inst).get("color", Color(0, 0, 0, 0))


## Moves the camera in front of the figure while the character creator is open.
## view: "body", "face", or "" to return to normal play.
func set_creator_view(view: String) -> void:
	_creator_view = view
	match view:
		"body":
			_arm.spring_length = 2.9
			_arm.position = Vector3(0.75, -0.75, 0)
			pivot.rotation = Vector3(0.0, yaw, 0.0)
		"face":
			_arm.spring_length = 0.85
			_arm.position = Vector3(0.2, -0.07, 0)
			pivot.rotation = Vector3(0.0, yaw, 0.0)
		_:
			_creator_turn = 0.0
			_arm.spring_length = ARM_INDOORS if indoors else ARM_LENGTH
			_arm.position = ARM_OFFSET
			pivot.rotation = Vector3(pitch, yaw, 0.0)
			body.rotation.y = yaw
			return
	# The camera sits south of the player looking north, so turn the figure to face it.
	body.rotation.y = yaw + PI + _creator_turn


func turn_in_creator() -> void:
	_creator_turn = fposmod(_creator_turn + PI * 0.5, TAU)
	set_creator_view(_creator_view)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := SENS * float(Game.settings["sensitivity"])
		var flip := -1.0 if bool(Game.settings["invert_y"]) else 1.0
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens * flip, -1.2, 0.7)


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	_sprinting = false
	_moving = false
	if not dead and not Game.ui_open:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = Basis(Vector3.UP, yaw) * Vector3(iv.x, 0.0, iv.y)
		_moving = iv.length() > 0.1
		_sprinting = Input.is_action_pressed("sprint") and _moving and Game.thirst > 0.0 and not _tired and Game.stamina > 0.0
		if is_on_floor() and Input.is_action_just_pressed("jump"):
			if not _slip_away():
				jump()
	var speed := SPRINT if _sprinting else WALK
	if Game.thirst <= 0.0:
		speed *= 0.6
	if _aiming_bow:
		speed *= 0.5
	if _slip > 0.0:
		_slip -= delta
	else:
		velocity.x = move_toward(velocity.x, dir.x * speed, 50.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, 50.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var falling := -velocity.y
	var was_up := not is_on_floor()
	move_and_slide()
	if was_up and is_on_floor() and (_air_t > 0.25 or falling > 5.0) and not indoors:
		# Coming down: dust flies out from under the feet, more the harder the landing.
		var hard := clampf(falling / 8.0, 0.5, 1.6)
		world.fx.dust(global_position, hard)
		Game.play_sound("land", global_position, -6.0 + 6.0 * hard)
	elif _sprinting and is_on_floor() and not indoors:
		_stride += delta
		if _stride > 0.3:
			_stride = 0.0
			world.fx.dust(global_position - dir * 0.3, 0.3)
	if _moving and is_on_wall() and not indoors:
		_mount(dir)
	if _slinging or _aiming_bow:
		body.rotation.y = yaw     # face the mark while aiming
	elif dir.length() > 0.1:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 12.0 * delta)
	# The figure takes its jump pose at once after a jump, but only after a moment when the
	# ground simply drops away, so a step down or a bump does not throw its arms up.
	if is_on_floor():
		_air_t = 0.0
		if velocity.y <= 0.0:
			_jumping = false
	else:
		_air_t += delta
	if not dead:
		body.animate(delta, Vector2(velocity.x, velocity.z).length(), in_air())

	# Keep the player inside the playable area and above the ground.
	if indoors:
		return
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > world.walk_limit:
		flat = flat.normalized() * world.walk_limit
		global_position.x = flat.x
		global_position.z = flat.y
		if _edge_warn <= 0.0:
			_edge_warn = 6.0
			Game.say("Nothing but sand that way. The camp is behind you.")
	var ground_y: float = world.terrain.surface_y(global_position.x, global_position.z)
	if global_position.y < ground_y - 3.0:
		global_position.y = ground_y + 1.0
		velocity.y = 0.0


func _process(delta: float) -> void:
	pivot.rotation = Vector3(pitch, yaw, 0.0)
	# A jolt dies away quickly; squared, so that light ones stay light.
	_shake = maxf(0.0, _shake - delta * 3.5)
	cam.h_offset = randf_range(-1.0, 1.0) * _shake * _shake * 0.14
	cam.v_offset = randf_range(-1.0, 1.0) * _shake * _shake * 0.14
	_sling_cd -= delta
	_edge_warn -= delta
	_riposte -= delta
	_twice -= delta
	_brace_cd -= delta
	_quick_stone -= delta
	_streak_t -= delta
	if _streak_t <= 0.0:
		_streak = 0
	if dead:
		Game.prompt = ""
		combo = -1
		_attack_waiting = false
		_slinging = false
		_aiming_bow = false
		_aim.visible = false
		return
	_update_combo(delta)
	_update_sling(delta)
	_update_bow(delta)
	_update_battle(delta)

	if _sprinting:
		Game.stamina = maxf(0.0, Game.stamina - STAMINA_SPRINT * delta)
		if Game.stamina <= 0.0:
			_tired = true
			Game.say("You are out of breath. Walk for a while.")
	else:
		var regain := (STAMINA_WALK if _moving else STAMINA_REST) + Game.total("stamina")
		if _style("hand_r") == "staff":
			regain *= 1.0 + Game.perk("walking_staff")
		Game.stamina = minf(Game.stamina_cap(), Game.stamina + regain * delta)
	# A dry scout has less breath to draw on (Game.stamina_cap).
	Game.stamina = minf(Game.stamina, Game.stamina_cap())
	if _tired and Game.stamina >= STAMINA_RECOVER:
		_tired = false

	# Thirst comes on slowly: about three times through the bar in a day, faster under the sun
	# and when running, slower by night, indoors and under a headcloth or a robe (Game.thirst_rate).
	Game.thirst = clampf(Game.thirst - Game.thirst_rate(_sprinting, indoors, float(world.stage.get("heat", 1.0))) * delta, 0.0, 100.0)
	if Game.thirst <= 0.0:
		Game.hp -= Game.PARCHED_DAMAGE * delta
		if _thirst_warned < 2:
			_thirst_warned = 2
			Game.say("You are parched. Find water or you will not last.")
	elif Game.thirst < Game.DRY_BELOW:
		if _thirst_warned < 1:
			_thirst_warned = 1
			Game.say("Your throat is dry and your breath is short. Press Q to drink.")
	else:
		_thirst_warned = 0

	var resting: bool = global_position.distance_to(world.camp_pos) < world.camp_radius
	if resting and world.raid != null and not world.raid.active and Game.thirst > 0.0:
		Game.hp = minf(Game.max_hp, Game.hp + 4.0 * delta)
	if Game.hp <= 0.0:
		_die()
		return

	_update_focus()
	if Game.input_blocked():
		return
	if Input.is_action_just_pressed("interact") and focus != null:
		focus.interact()
		return
	if Input.is_action_just_pressed("drink"):
		if Game.drink():
			Game.say("You drink. %d left in the waterskin." % Game.water)
		elif Game.water <= 0:
			Game.say("Your waterskin is empty.")
		else:
			Game.say("You are not thirsty yet.")
	if Input.is_action_just_pressed("sheathe"):
		toggle_sheathe()
	if Input.is_action_just_pressed("battle"):
		set_battle(not battle, false)
		Game.say("Ready for battle." if battle else "At ease.")
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("attack"):
			if Game.bow().is_empty():
				melee()
			else:
				draw_bow()
		if Input.is_action_just_pressed("sling"):
			sling()


func _update_focus() -> void:
	focus = null
	var best := 1e9
	for it in get_tree().get_nodes_in_group("interactable"):
		var d: float = global_position.distance_to(it.global_position)
		if d < float(it.interact_radius) and d < best and it.prompt_text() != "":
			best = d
			focus = it
	Game.prompt = "[E]  %s" % focus.prompt_text() if focus != null else ""


## Held up by a rock, a crate or the like while moving `dir`: steps onto it if it is low, or,
## when already off the ground, scrambles up if its top is within reach.
func _mount(dir: Vector3) -> void:
	var into := -get_wall_normal()
	into.y = 0.0
	if into.length() < 0.3 or into.normalized().dot(dir.normalized()) < 0.5:
		return
	var grounded := is_on_floor()
	var reach := STEP_UP if grounded else CLIMB_UP
	# Look down onto whatever is in the way, from above the highest top that can be reached.
	var from := global_position + into.normalized() * 0.75 + Vector3(0, reach + 0.3, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, reach + 0.2, 0), 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["collider"] == world.terrain or (hit["normal"] as Vector3).y < 0.6:
		return
	var rise: float = (hit["position"] as Vector3).y - global_position.y
	if rise < 0.12:
		return
	if grounded:
		velocity.y = sqrt(2.0 * GRAVITY * (rise + 0.12))
	elif velocity.y < SCRAMBLE:
		velocity.y = SCRAMBLE
		_jumping = true


## Leaves the ground. Call only when standing on it.
func jump() -> void:
	velocity.y = JUMP
	_jumping = true


## Off the ground in a way that shows: jumping, or falling for more than a moment.
func in_air() -> bool:
	return not is_on_floor() and (_jumping or _air_t > 0.25)


func forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)


# ---------------------------------------------------------------- melee

## Attack: the first press strikes (drawing the weapon first if it is put away); pressing again
## during a blow chains the next one, up to three: A, B, C.
## True while an enemy that has seen the scout is near: no travelling then.
func in_fight() -> bool:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e.dead and e.seen and e.global_position.distance_to(global_position) < BATTLE_NEAR:
			return true
	return false


## Into battle mode or out of it. `auto`: taken on its own, so it is left again when all is quiet.
func set_battle(on: bool, auto: bool = true) -> void:
	if on and battle and not _battle_auto:
		return
	battle = on
	_battle_auto = on and auto
	_calm = 0.0
	body.battle = on
	if on and body.sheathed and not body.busy():
		body.stow(false)


## A stance taken on its own is left once nothing has happened for a while and no enemy is near.
func _update_battle(delta: float) -> void:
	if not battle or not _battle_auto:
		return
	_calm_check -= delta
	if _calm_check <= 0.0:
		_calm_check = 0.5
		for e in get_tree().get_nodes_in_group("enemy"):
			if not e.dead and e.global_position.distance_to(global_position) < BATTLE_NEAR:
				_calm = 0.0
				return
	if combo >= 0 or _slinging or _aiming_bow:
		_calm = 0.0
	_calm += delta
	if _calm >= BATTLE_CALM:
		set_battle(false)


func melee() -> void:
	if dead or not Game.bow().is_empty():
		return
	if not battle:
		set_battle(true)
	if body.busy() or body.sheathed:
		if body.sheathed and not body.busy():
			body.stow(false)
		_attack_waiting = body.sheathed or _attack_waiting
		return
	if combo < 0:
		_begin_blow(0)
		# Held, a sword thrusts further, an axe comes down harder, a knife or spear is thrown.
		_charging = _can_charge() and not in_air()
		_charge_t = 0.0
	elif combo < combo_length() - 1:
		_combo_next = true


## The weapon style of what is in `hand` ("sword", "staff", ...); a bare fist counts as a sword.
func _style(hand: String) -> String:
	return HumanScript.style_of(Game.kind(Game.weapon_in(hand)))


func _can_charge() -> bool:
	match _style("hand_" + _blow_hand):
		"sword":
			return Game.has_perk("long_point")
		"axe":
			return Game.has_perk("heavy_cleave")
		"dagger":
			return Game.has_perk("thrown_knife")
		"spear":
			return Game.has_perk("hurl_spear")
	return false


## How many blows a combo has with what is in hand: three; one with a staff, two once its stomp
## is learned; four with a sword once the Fourth Cut is.
func combo_length() -> int:
	var kind := Game.kind(Game.weapon_in("hand_" + blow_hand(0)))
	match HumanScript.style_of(kind):
		"staff":
			return 2 if Game.has_perk("stomp") else 1
		"sword":
			if kind != "none" and Game.has_perk("fourth_cut"):
				return 4
	return mini(3, HumanScript.blows(kind).size())


## Blow `step` of the combo, as the weapon making it makes it (HumanScript.STYLES), with what the
## weapon's skills change: a combo that goes on where it used to end, and quicker recovery.
func blow_table(step: int) -> Dictionary:
	var kind := Game.kind(Game.weapon_in("hand_" + blow_hand(step)))
	var style := HumanScript.style_of(kind)
	var list: Array = HumanScript.blows(kind)
	var m: Dictionary
	if step >= 3 and style == "sword" and kind != "none":
		m = HumanScript.FOURTH_CUT.duplicate()
	else:
		m = (list[mini(step, list.size() - 1)] as Dictionary).duplicate()
	if step < combo_length() - 1 and float(m["chain"]) > 100.0:
		m["chain"] = float(m["hit"]) + 0.12
	var sooner := 0.0
	match style:
		"sword":
			sooner = Game.perk("measured_breath")
		"bludgeon":
			sooner = Game.perk("heavy_hand")
		"spear":
			sooner = Game.perk("quick_recovery")
	if sooner > 0.0:
		var hit := float(m["hit"])
		if float(m["chain"]) < 100.0:
			m["chain"] = hit + (float(m["chain"]) - hit) * (1.0 - sooner)
		m["length"] = hit + (float(m["length"]) - hit) * (1.0 - sooner)
	return m


## Which hand makes blow `step`. With a weapon in each hand, B is the left hand's; otherwise the
## hand that holds a weapon makes every blow.
func blow_hand(step: int) -> String:
	var right := not Game.weapon_in("hand_r").is_empty()
	var left := not Game.weapon_in("hand_l").is_empty()
	if step == 1:
		return "l" if left else "r"
	return "r" if right or not left else "l"


func _begin_blow(step: int) -> void:
	combo = step
	_combo_t = 0.0
	_combo_next = false
	_hit_done = false
	_swished = false
	_charged = false
	_throwing = false
	_charging = false
	_blow_hand = blow_hand(step)
	_blow_speed = Game.swing_speed(Game.weapon_in("hand_" + _blow_hand)) * _quickness(_style("hand_" + _blow_hand))
	body.rotation.y = yaw
	body.attack(step, _blow_hand, _blow_speed)


## How much quicker the skills make a blow of `style` land (1 = as it is).
func _quickness(style: String) -> float:
	var k := 1.0 + _haste
	_haste = 0.0
	match style:
		"dagger":
			k += Game.perk("quick_hands")
		"sickle":
			k += Game.perk("royal_edge")
		"axe":
			k += Game.perk("woodsman")
		"sword":
			k += Game.perk("captain") * _streak
	return k


func _update_combo(delta: float) -> void:
	if _attack_waiting and not body.busy() and not body.sheathed:
		_attack_waiting = false
		if combo < 0:
			_begin_blow(0)
	if combo < 0:
		return
	var m: Dictionary = blow_table(combo)
	if _charging:
		_charge_t += delta
		if Input.is_action_pressed("attack") and not Game.ui_open:
			# Drawn back and held there, gathering, until the button is let go.
			var hold_at := maxf(0.0, float(m["hit"]) - 0.16)
			if _combo_t >= hold_at:
				_combo_t = hold_at
				body.set_blow_speed(0.0, float(m["length"]) - _combo_t)
				return
		else:
			_charging = false
			_charged = _charge_t >= CHARGE_TIME
			if _charged:
				var style := _style("hand_" + _blow_hand)
				_throwing = style == "dagger" or style == "spear"
				if style == "axe":
					_blow_speed *= 0.85
			body.set_blow_speed(_blow_speed, float(m["length"]) - _combo_t)
	_combo_t += delta * _blow_speed
	if not _swished and _combo_t >= float(m["hit"]) - 0.13:
		# The weapon is heard cutting the air just before it lands.
		_swished = true
		var held := Game.weapon_in("hand_" + _blow_hand)
		if not held.is_empty():
			Game.play_sound("swing_heavy" if Game.weight(held) >= 1.4 else "swing", global_position + Vector3(0, 1.2, 0), 0.0, _blow_speed)
	if not _hit_done and _combo_t >= float(m["hit"]):
		_hit_done = true
		_land_blow(combo)
	if _combo_next and _hit_done and _combo_t >= float(m["chain"]):
		_begin_blow(combo + 1)
	elif _combo_t >= float(m["length"]):
		combo = -1


## How far a weapon reaches: spears and staffs furthest, a fist least.
static func reach(kind: String) -> float:
	match kind:
		"spear_long":
			return 3.6
		"spear", "staff":
			return 3.2
		"dagger":
			return 2.2
		"none", "shield", "bow":
			return 1.8
	return 2.6


## Hits every enemy the blow reaches in front of the scout. The sweeping blows cover a wider arc.
## What the weapon's skills add (data/skills.gd) is worked in here and in _strike.
func _land_blow(step: int) -> void:
	var hand := "hand_" + _blow_hand
	var held := Game.weapon_in(hand)
	var kind := Game.kind(held)
	var style := HumanScript.style_of(kind)
	var tree := Game.tree_of(kind)
	var fwd := forward()
	var m: Dictionary = blow_table(step)
	if bool(m.get("stomp", false)):
		_stomp(m, tree)
		return
	if _throwing:
		_throw_weapon(hand, held, tree)
		return
	var length := reach(kind)
	if style == "spear":
		length += Game.perk("long_reach")
	if _charged and style == "sword":
		length += Game.perk("long_point")
	var arc := float(m.get("arc", 0.2 if step == 0 else -0.1))
	if step == 1 and ((style == "sword" and Game.has_perk("wide_sweep")) or (style == "axe" and Game.has_perk("wide_chop"))):
		arc = -1.0
	var damage: float = Game.melee_power(hand) * float(m.get("power", BLOW_POWER[mini(step, 2)])) * _blow_bonus(style, step)
	if style == "dagger" and _blow_hand == "r" and Game.kind(Game.weapon_in("hand_l")) == "dagger":
		damage += Game.melee_power("hand_l") * Game.perk("second_knife")
	var hits: Array = []
	var behind: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist <= length + float(e.radius) and (dist < 1.0 or fwd.dot(to / dist) > arc):
			hits.append(e)
		elif style == "spear" and dist > 0.5 and dist <= length + Game.perk("skewer") + float(e.radius) and fwd.dot(to / dist) > 0.9:
			behind.append(e)
	if not hits.is_empty() and not behind.is_empty() and Game.has_perk("skewer"):
		# Skewer: the thrust goes on into the one behind. Through Both: the lunge, through them all.
		behind.sort_custom(func(a, b) -> bool: return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
		hits.append_array(behind if step == 2 and Game.has_perk("through_both") else behind.slice(0, 1))
	if step == 2 and style == "spear":
		damage *= 1.0 + Game.perk("through_both")
	var twice := _twice > 0.0
	_twice = 0.0
	for e in hits:
		_strike(e, damage, step, style, tree)
		if twice and is_instance_valid(e) and not e.dead:
			_strike(e, damage, step, style, tree)
		world.fx.impact(e.global_position + Vector3(0, float(e.height) * 0.6, 0), e.global_position - global_position + fwd, float(m.get("power", 1.0)) >= 1.3)
	var struck := hits.size()
	if struck > 0:
		Game.train(tree, Game.Skills.BLOW)
		_after_landing(style, step)
		# A blow that lands is heard and felt: its sound by what struck, the game held still for
		# an instant, and the camera jolted; the last blow of the three hardest.
		var sound := "punch"
		if kind in ["staff", "club", "mace"]:
			sound = "hit_wood"
		elif kind != "none":
			sound = "hit_blade"
		var heavy := float(m.get("power", 1.0)) >= 1.3
		Game.play_sound(sound, global_position + fwd * 1.2 + Vector3(0, 1.2, 0), 0.0, 0.9 if heavy else 1.0)
		Game.play_sound("hit_flesh", global_position + fwd * 1.2 + Vector3(0, 1.2, 0), -4.0)
		world.fx.hit_stop(0.09 if heavy else 0.05)
		shake(0.75 if heavy else 0.45)


## What a blow of `style` is worth beyond its weapon's damage (1 = no more).
func _blow_bonus(style: String, step: int) -> float:
	var k := 1.0
	if step == 2 and style == "sword":
		k += Game.perk("third_cut")
	if step == 2 and style == "sickle":
		k += Game.perk("crescent_edge")
	if _charged and style == "axe":
		k += Game.perk("heavy_cleave")
	if style == "sword":
		k += Game.perk("captain") * _streak
		if _riposte > 0.0:
			k += Game.perk("riposte")
			_riposte = 0.0
	return k


## One enemy struck by a blow of `style`: the weapon's skills that judge the enemy, the damage,
## then what the blow does to it besides.
func _strike(e, damage: float, step: int, style: String, tree: String) -> void:
	var dmg := damage
	var great: bool = e.is_boss or e.kind == "anak"
	var knock := 1.0
	match style:
		"dagger":
			if not e.seen and Game.has_perk("unseen_blade"):
				dmg *= Game.perk("unseen_blade")
			elif e.from_behind(global_position):
				dmg *= 1.0 + Game.perk("low_strike")
			if Game.has_perk("finishing_stab") and not great and e.hp < e.max_hp * Game.perk("finishing_stab"):
				dmg = maxf(dmg, e.hp * 10.0 + 1.0)
		"spear":
			if not e.struck_once:
				dmg *= 1.0 + Game.perk("first_strike")
			knock = maxf(1.0, Game.perk("keep_away"))
		"axe":
			if e.hp > e.max_hp * 0.5:
				dmg *= 1.0 + Game.perk("deep_bite")
			if step == 2 and Game.has_perk("felling_blow"):
				if great:
					dmg *= 1.5
				elif e.hp < e.max_hp * Game.perk("felling_blow"):
					dmg = maxf(dmg, e.hp * 10.0 + 1.0)
		"bludgeon":
			if e.armor >= 0.1:
				dmg *= 1.0 + Game.perk("bone_crusher")
			if step == 0:
				knock = maxf(1.0, Game.perk("stunning_blow"))
		"staff":
			if e.soldier.is_empty():
				dmg *= maxf(1.0, Game.perk("against_wolves"))
			knock = maxf(1.0, Game.perk("drive_back"))
		"sword":
			if step == 3:
				knock = Game.perk("fourth_cut")
	e.struck_once = true
	e.last_tree = tree
	e.take_damage(dmg, self, knock)
	if e.dead:
		_on_kill(style)
		return
	match style:
		"sickle":
			if step == 0:
				if Game.has_perk("hook_pull"):
					e.interrupt()
					e.pull_toward(global_position, 1.0)
				if Game.has_perk("hooked_shield"):
					e.open_shield(Game.perk_time("hooked_shield"))
				if Game.has_perk("disarm") and Game.rng.randf() < Game.perk("disarm") and e.disarm():
					Game.say("You tear the weapon from his hand.")
				if Game.has_perk("pharaohs"):
					_twice = Game.perk_time("pharaohs")
			elif step == 1 and Game.has_perk("reaping_sweep"):
				e.slow(Game.perk("reaping_sweep"), Game.perk_time("reaping_sweep"))
		"bludgeon":
			if step == 0 and Game.has_perk("stunning_blow"):
				e.interrupt()
			if step == 2 and Game.has_perk("daze"):
				e.daze(Game.perk_time("daze"))
			if Game.has_perk("cripple"):
				e.slow(1.0 - Game.perk("cripple"), Game.perk_time("cripple"))
		"staff":
			if Game.has_perk("ward_off"):
				e.interrupt()
		"dagger":
			if step == 2 and Game.has_perk("open_vein"):
				e.bleed(dmg * Game.perk("open_vein"), Game.perk_time("open_vein"))
		"axe":
			if Game.has_perk("rending_cut"):
				e.bleed(dmg * Game.perk("rending_cut"), Game.perk_time("rending_cut"))
			if Game.has_perk("armour_breaker"):
				e.break_armour(Game.perk_time("armour_breaker"))
			if Game.has_perk("shield_splitter") and e.split_shield():
				Game.say("The shield splits apart.")


## After a blow of `style` has landed on something: the skills that work on everything near.
func _after_landing(style: String, step: int) -> void:
	if style == "staff" and step == 0 and Game.has_perk("shepherd"):
		Game.stamina = minf(Game.stamina_cap(), Game.stamina + 5.0)
		_haste = maxf(_haste, Game.perk("shepherd"))
	if style != "bludgeon":
		return
	if step == 0 and Game.has_perk("ground_shake"):
		for e in _enemies_within(Game.perk("ground_shake")):
			e.take_damage(0.0, self, 1.5)
	if Game.has_perk("breaker_of_ranks"):
		_ranks += 1
		if _ranks % int(Game.perk("breaker_of_ranks")) == 0:
			for e in _enemies_within(3.0):
				e.daze(Game.perk_time("breaker_of_ranks"), true)
			world.fx.dust(global_position + forward(), 1.2)
			shake(0.9)


func _enemies_within(metres: float) -> Array:
	return get_tree().get_nodes_in_group("enemy").filter(func(e) -> bool:
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		return to.length() <= metres + float(e.radius))


## An enemy has fallen to a blow of `style`.
func _on_kill(style: String) -> void:
	if style != "sword":
		return
	if Game.has_perk("cleave_onward"):
		_haste = maxf(_haste, Game.perk("cleave_onward"))
	if Game.has_perk("captain"):
		_streak = mini(_streak + 1, 3)
		_streak_t = Game.perk_time("captain")


## The stomp (Stomp, Heavy Stomp): the staff's butt driven into the ground. Everything near is
## struck, knocked off its feet (a heavy beast or a chief only reels), and dazed.
func _stomp(m: Dictionary, tree: String) -> void:
	var radius := maxf(Game.perk("stomp"), Game.perk("heavy_stomp"))
	var dazed := Game.perk_time("stomp") * (2.0 if Game.has_perk("heavy_stomp") else 1.0)
	var damage: float = Game.melee_power("hand_r") * float(m["power"])
	var landed := 0
	for e in _enemies_within(radius):
		e.last_tree = tree
		e.struck_once = true
		e.take_damage(damage, self, 1.6)
		if not e.dead:
			e.daze(dazed, not bool(e.def.get("heavy", false)))
		landed += 1
	# The ground shakes: dust thrown up in a ring, a heavy thud, the view jolted.
	var at := global_position + forward() * 0.35
	world.fx.dust(at, 1.5)
	for i in 8:
		var a := TAU * i / 8.0
		world.fx.dust(at + Vector3(cos(a), 0.0, sin(a)) * radius * 0.6, 0.6)
	Game.play_sound("land", at, 6.0, 0.55)
	Game.play_sound("hit_wood", at, 0.0, 0.6)
	world.fx.hit_stop(0.08)
	shake(1.0)
	if landed > 0:
		Game.train(tree, Game.Skills.BLOW)


## The charged blow of a knife or a spear (Thrown Knife, Hurl the Spear): it leaves the hand and
## flies where the crosshair points, and lies where it falls until the scout walks over it.
func _throw_weapon(hand: String, held: Dictionary, tree: String) -> void:
	if held.is_empty():
		return
	var spear := Game.kind(held) in ["spear", "spear_long"]
	var damage: float = Game.melee_power(hand) * (Game.perk("hurl_spear") if spear else Game.perk("thrown_knife"))
	var origin: Vector3 = body.hand_point() if hand == "hand_r" else body.left_hand_point()
	Game.equipped[hand] = {}
	Game._gear_changed()
	var shot := ProjectileScript.new()
	shot.world = world
	shot.from_player = true
	shot.damage = damage
	shot.tree = tree
	shot.carry = held
	shot.carry_hand = hand
	shot.drop = SHOT_DROP
	shot.velocity = (_aim_target(origin) - origin).normalized() * (30.0 if spear else 26.0)
	world.stage_root.add_child(shot)
	shot.global_position = origin
	Game.play_sound("swing_heavy" if spear else "swing", origin, 0.0, 0.85)


## Slip Away: jump during a stab steps back out of reach instead. False if it does not apply.
func _slip_away() -> bool:
	if combo < 0 or not Game.has_perk("slip_away") or _style("hand_" + _blow_hand) != "dagger":
		return false
	combo = -1
	var back := -forward()
	back.y = 0.0
	velocity = back.normalized() * 8.5 + Vector3(0.0, 3.0, 0.0)
	_slip = 0.3
	return true


## Brace: an enemy coming at a scout who stands still with a spear is struck before it can swing.
func brace_against(e) -> void:
	if not Game.has_perk("brace") or _brace_cd > 0.0 or dead or _moving or combo >= 0 or body.busy() or body.sheathed:
		return
	var held := Game.weapon_in("hand_r")
	if HumanScript.style_of(Game.kind(held)) != "spear":
		return
	var to: Vector3 = e.global_position - global_position
	to.y = 0.0
	if to.length() > reach(Game.kind(held)) + Game.perk("long_reach") + float(e.radius) or forward().dot(to.normalized()) < 0.3:
		return
	_brace_cd = Game.perk_time("brace")
	body.rotation.y = yaw
	body.attack(0, "r", 2.0)
	e.last_tree = "spear"
	e.take_damage(Game.melee_power("hand_r"), self, maxf(1.0, Game.perk("keep_away")))
	if not e.dead:
		e.interrupt()
	Game.train("spear", Game.Skills.BLOW)
	Game.play_sound("hit_blade", e.global_position + Vector3(0, 1.2, 0))


## Jolts the camera: 0.3 a light knock, 1 the hardest.
func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.0)


## Puts the weapons on the back or the belt, or takes them in hand again. Putting them away ends
## battle mode.
func toggle_sheathe() -> void:
	if dead or combo >= 0 or body.busy():
		return
	if not body.sheathed:
		set_battle(false)
	body.stow(not body.sheathed)


# ---------------------------------------------------------------- the sling and the bow

## Starts whirling the sling. It goes round for as long as the button is held, and is let go
## when the button is released (after one turn at least). Each throw uses up a stone.
func sling() -> void:
	if _sling_cd > 0.0 or dead or combo >= 0 or body.busy() or _slinging:
		return
	if Game.equipped["sling"].is_empty():
		_sling_cd = 0.6
		Game.say("You have no sling. Put one on in your inventory (I).")
		return
	if Game.stones() <= 0:
		_sling_cd = 0.6
		Game.say("You have no stones left. Gather some from stony ground with E.")
		return
	_slinging = true
	_sling_t = 0.0
	_sling_let_go = false
	if not battle:
		set_battle(true)
	body.rotation.y = yaw
	body.sling_start()


func _update_sling(delta: float) -> void:
	if not _slinging:
		return
	_sling_t += delta
	if not Input.is_action_pressed("sling"):
		_sling_let_go = true
	_show_aim(_stone_origin(), _stone_speed())
	# Quick Whirl shortens the turns before it can be let go; Second Stone needs none just after a throw.
	var whirl: float = body.WHIRL_TIME * (1.0 - Game.perk("quick_whirl"))
	if _quick_stone > 0.0:
		whirl = 0.0
	if _sling_let_go and _sling_t >= whirl:
		_slinging = false
		_aim.visible = false
		body.sling_release()
		_sling_cd = body.RELEASE + body.THROW_TIME + 0.05
		if Game.has_perk("second_stone"):
			_sling_cd = body.RELEASE + 0.1
			_quick_stone = Game.perk_time("second_stone")
		_throw_stone(_sling_t)


func _stone_speed() -> float:
	return STONE_SPEED * (1.0 + Game.perk("long_cast"))


## Lets the stone go, `whirled` seconds after the sling began to turn.
func _throw_stone(whirled: float = 0.0) -> void:
	await get_tree().create_timer(body.RELEASE, false).timeout
	if not is_inside_tree() or dead or not Game.use_ammo("stones"):
		return
	Game.play_sound("sling_throw", global_position + Vector3(0, 1.6, 0))
	var damage: float = Game.sling_power() * (1.0 + Game.perk("smooth_stones"))
	if Game.has_perk("hairs_breadth") and whirled >= Game.perk_time("hairs_breadth"):
		damage *= Game.perk("hairs_breadth")
	_launch(_stone_origin(), _stone_speed(), damage, false)


func _stone_origin() -> Vector3:
	return body.hand_point() + forward() * 0.3


## Draws the bow (attack with a bow in hand). It stays drawn while the button is held and looses
## when it is released; the further it was drawn, the harder the arrow flies.
func draw_bow() -> void:
	if dead or combo >= 0 or _aiming_bow or (body.busy() and not body.sheathed):
		return
	if Game.arrows() <= 0:
		Game.say("You have no arrows. The trader sells them.")
		return
	_aiming_bow = true
	_draw_t = 0.0
	if not battle:
		set_battle(true)
	body.rotation.y = yaw
	body.bow_draw()


func _update_bow(delta: float) -> void:
	if not _aiming_bow:
		return
	_draw_t += delta
	_show_aim(body.left_hand_point(), ARROW_SPEED)
	if not Input.is_action_pressed("attack"):
		loose_arrow()


## Lets the arrow go. Returns how far the bow was drawn.
func loose_arrow() -> float:
	if not _aiming_bow:
		return 0.0
	_aiming_bow = false
	_aim.visible = false
	var amount: float = minf(1.0, body.bow_loose() * (1.0 + Game.perk("steady_draw")))
	if not Game.use_ammo("arrows"):
		return amount
	var power := 0.35 + 0.65 * amount
	var damage: float = Game.bow_power() * power * (1.0 + Game.perk("keen_eye"))
	# Power Draw: held at full draw a while. Volley: a full draw loosed high.
	var full_for := _draw_t - HumanScript.DRAW_TIME / (1.0 + Game.perk("steady_draw"))
	if Game.has_perk("power_draw") and full_for >= Game.perk_time("power_draw"):
		damage *= 1.0 + Game.perk("power_draw")
	var origin: Vector3 = body.left_hand_point()
	var volley: bool = Game.has_perk("volley") and amount >= 0.99 and (_aim_target(origin) - origin).normalized().y > 0.3
	Game.play_sound("bow_twang", global_position + Vector3(0, 1.5, 0), -8.0 + 8.0 * amount)
	var speed := ARROW_SPEED * (0.55 + 0.45 * amount)
	_launch(origin, speed, damage, true, volley)
	if Game.has_perk("quick_nock"):
		_second_arrow(speed, damage)
	return amount


## Quick Nock: another arrow a moment after the first, if there is one.
func _second_arrow(speed: float, damage: float) -> void:
	await get_tree().create_timer(0.18, false).timeout
	if not is_inside_tree() or dead or not Game.use_ammo("arrows"):
		return
	Game.play_sound("bow_twang", global_position + Vector3(0, 1.5, 0), -4.0)
	_launch(body.left_hand_point(), speed, damage, true)


## Where the crosshair points: what it is on, or a point far off.
func _aim_target(origin: Vector3) -> Vector3:
	var from := cam.global_position
	var target := from - cam.global_transform.basis.z * 90.0
	var q := PhysicsRayQueryParameters3D.create(from, target, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		if p.distance_to(from) > 6.5 and p.distance_to(origin) > 2.0:
			target = p
	return target


func _launch(origin: Vector3, speed: float, damage: float, arrow: bool, volley: bool = false) -> void:
	var shot := ProjectileScript.new()
	shot.world = world
	shot.from_player = true
	shot.damage = damage
	shot.arrow = arrow
	# What the sling's or the bow's skills give the shot.
	shot.tree = "bow" if arrow else "sling"
	if arrow:
		shot.pierce = Game.perk("through_gap")
		shot.pin = Game.has_perk("pinning_shot")
		shot.recover = Game.perk("gather_arrows")
		shot.volley = volley
	else:
		shot.stun_head = Game.has_perk("stunning_stone")
		shot.recover = Game.perk("thrifty")
	shot.drop = SHOT_DROP
	shot.velocity = (_aim_target(origin) - origin).normalized() * speed
	world.stage_root.add_child(shot)
	shot.global_position = origin


# ---------------------------------------------------------------- the aim marker

func _make_aim() -> void:
	_aim = Node3D.new()
	_aim.top_level = true
	add_child(_aim)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.95, 0.75, 0.85)
	m.no_depth_test = true
	m.render_priority = 1
	_aim_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.32
	ring.outer_radius = 0.42
	ring.rings = 24
	ring.ring_segments = 6
	_aim_ring.mesh = ring
	_aim_ring.material_override = m.duplicate()
	_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim.add_child(_aim_ring)
	var dot := SphereMesh.new()
	dot.radius = 0.045
	dot.height = 0.09
	dot.radial_segments = 6
	dot.rings = 3
	var dm := m.duplicate()
	dm.albedo_color = Color(1.0, 0.95, 0.75, 0.55)
	for i in 18:
		var d := MeshInstance3D.new()
		d.mesh = dot
		d.material_override = dm
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aim.add_child(d)
		_aim_dots.append(d)
	_aim.visible = false


## Follows the flight a stone or arrow would take from `origin` and marks where it comes down:
## a dotted arc and a ring, red when it would strike an enemy.
func _show_aim(origin: Vector3, speed: float) -> void:
	var v := (_aim_target(origin) - origin).normalized() * speed
	var p := origin
	var space := get_world_3d().direct_space_state
	var path: Array = [p]
	var end := p
	var normal := Vector3.UP
	aim_on_target = false
	var step := 1.0 / 30.0
	for i in 150:
		var nv := v + Vector3.DOWN * SHOT_DROP * step
		var np := p + (v + nv) * 0.5 * step
		var q := PhysicsRayQueryParameters3D.create(p, np, 1 | 2)
		var hit := space.intersect_ray(q)
		var enemy := _enemy_on(p, np)
		if enemy or not hit.is_empty():
			end = np if hit.is_empty() else hit["position"]
			normal = Vector3.UP if hit.is_empty() else hit["normal"]
			aim_on_target = enemy or (not hit.is_empty() and hit["collider"] != null and (hit["collider"] as Node).is_in_group("enemy"))
			path.append(end)
			break
		p = np
		v = nv
		end = p
		path.append(p)
	aim_point = end
	_aim.visible = true
	_aim.global_transform = Transform3D.IDENTITY
	var up := normal if normal.length() > 0.5 else Vector3.UP
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	# The ring grows with distance so it stays easy to see far off.
	var size := maxf(1.0, cam.global_position.distance_to(end) / 10.0)
	_aim_ring.global_transform = Transform3D(Basis(x, up, x.cross(up)).scaled(Vector3(size, 1.0, size)), end + up * 0.05)
	var col := Color(1.0, 0.35, 0.25, 0.9) if aim_on_target else Color(1.0, 0.95, 0.75, 0.85)
	(_aim_ring.material_override as StandardMaterial3D).albedo_color = col
	for i in _aim_dots.size():
		var d: MeshInstance3D = _aim_dots[i]
		var k := int(float(i + 1) / (_aim_dots.size() + 1) * (path.size() - 1))
		d.visible = path.size() > 4 and k > 0 and k < path.size() - 1
		if d.visible:
			d.global_position = path[k]


func _enemy_on(a: Vector3, b: Vector3) -> bool:
	for e in get_tree().get_nodes_in_group("enemy"):
		if ProjectileScript.hits(a, b, e.global_position, float(e.radius), float(e.height)):
			return true
	return false


# ---------------------------------------------------------------- health

func take_damage(amount: float, _src = null) -> void:
	if dead:
		return
	var held_style := _style("hand_r")
	if Game.rng.randf() < Game.dodge_chance():
		# Dexterity: the blow is slipped altogether. A sword answers it (Riposte); a sickle
		# sword hooks the attacker's weapon and staggers him (Turn the Blade).
		Game.say("You slip the blow.")
		Game.play_sound("swing", global_position + Vector3(0, 1.2, 0), -6.0, 1.2)
		if held_style == "sword" and Game.has_perk("riposte"):
			_riposte = Game.perk_time("riposte")
		if held_style == "sickle" and Game.has_perk("turn_blade") and is_instance_valid(_src) and _src.has_method("daze"):
			_src.daze(Game.perk_time("turn_blade"))
		return
	if held_style == "bludgeon":
		amount *= 1.0 - Game.perk("unbroken")
	if held_style == "staff" and Game.has_perk("steady_guard") and _src is Node3D:
		var to: Vector3 = (_src as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() > 0.05 and (-body.global_basis.z).dot(to.normalized()) > 0.3:
			amount *= 1.0 - Game.perk("steady_guard")
	Game.hurt_player(amount)
	if not battle:
		set_battle(true)
	world.hud.flash_hurt()
	Game.play_sound("hurt", global_position + Vector3(0, 1.2, 0))
	shake(0.6)
	if Game.hp <= 0.0:
		_die()


func _die() -> void:
	if dead:
		return
	set_battle(false)
	dead = true
	Game.hp = 0.0
	body.die()
	world.on_player_died()


func revive(at: Vector3) -> void:
	dead = false
	body.revive()
	velocity = Vector3.ZERO
	global_position = at
