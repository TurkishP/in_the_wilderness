extends CharacterBody3D
## Third-person player: movement, camera, thirst, melee weapons, the sling and the bow.

const ProjectileScript := preload("res://scripts/projectile.gd")
const HumanScript := preload("res://scripts/human.gd")
const WALK := 6.0
const SPRINT := 9.5
const JUMP := 6.5
const GRAVITY := 20.0
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
			jump()
	var speed := SPRINT if _sprinting else WALK
	if Game.thirst <= 0.0:
		speed *= 0.6
	if _aiming_bow:
		speed *= 0.5
	velocity.x = move_toward(velocity.x, dir.x * speed, 50.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 50.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
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
	if flat.length() > LIMIT:
		flat = flat.normalized() * LIMIT
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
	_sling_cd -= delta
	_edge_warn -= delta
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
	_update_bow()

	if _sprinting:
		Game.stamina = maxf(0.0, Game.stamina - STAMINA_SPRINT * delta)
		if Game.stamina <= 0.0:
			_tired = true
			Game.say("You are out of breath. Walk for a while.")
	else:
		var regain := (STAMINA_WALK if _moving else STAMINA_REST) + Game.total("stamina")
		Game.stamina = minf(Game.max_stamina, Game.stamina + regain * delta)
	if _tired and Game.stamina >= STAMINA_RECOVER:
		_tired = false

	# Thirst: the heat and running dry the scout out; a headcloth or a robe slows it.
	var heat: float = float(world.stage.get("heat", 1.0))
	var rate := 0.3 * heat
	if _sprinting:
		rate += 0.45
	Game.thirst = clampf(Game.thirst - (rate - Game.total("thirst")) * delta, 0.0, 100.0)
	if Game.thirst <= 0.0:
		Game.hp -= 2.0 * delta
		if _thirst_warned < 2:
			_thirst_warned = 2
			Game.say("You are parched. Find water or you will not last.")
	elif Game.thirst < 25.0:
		if _thirst_warned < 1:
			_thirst_warned = 1
			Game.say("Your throat is dry. Press Q to drink.")
	else:
		_thirst_warned = 0

	var resting: bool = global_position.distance_to(world.camp_pos) < world.camp_radius
	if resting and world.raid != null and not world.raid.active:
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
func melee() -> void:
	if dead or not Game.bow().is_empty():
		return
	if body.busy() or body.sheathed:
		if body.sheathed and not body.busy():
			body.stow(false)
		_attack_waiting = body.sheathed or _attack_waiting
		return
	if combo < 0:
		_begin_blow(0)
	elif combo < body.BLOWS.size() - 1:
		_combo_next = true


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
	_blow_hand = blow_hand(step)
	_blow_speed = Game.swing_speed(Game.weapon_in("hand_" + _blow_hand))
	body.rotation.y = yaw
	body.attack(step, _blow_hand, _blow_speed)


func _update_combo(delta: float) -> void:
	if _attack_waiting and not body.busy() and not body.sheathed:
		_attack_waiting = false
		if combo < 0:
			_begin_blow(0)
	if combo < 0:
		return
	_combo_t += delta
	var m: Dictionary = body.BLOWS[combo]
	if not _hit_done and _combo_t >= float(m["hit"]) / _blow_speed:
		_hit_done = true
		_land_blow(combo)
	if _combo_next and _hit_done and _combo_t >= float(m["chain"]) / _blow_speed:
		_begin_blow(combo + 1)
	elif _combo_t >= float(m["length"]) / _blow_speed:
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
func _land_blow(step: int) -> void:
	var hand := "hand_" + _blow_hand
	var fwd := forward()
	var length := reach(Game.kind(Game.weapon_in(hand)))
	var arc := 0.2 if step == 0 else -0.1
	var damage: float = Game.melee_power(hand) * BLOW_POWER[step]
	for e in get_tree().get_nodes_in_group("enemy"):
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist <= length + float(e.radius) and (dist < 1.0 or fwd.dot(to / dist) > arc):
			e.take_damage(damage, self)


## Puts the weapons on the back or the belt, or takes them in hand again.
func toggle_sheathe() -> void:
	if dead or combo >= 0 or body.busy():
		return
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
	body.rotation.y = yaw
	body.sling_start()


func _update_sling(delta: float) -> void:
	if not _slinging:
		return
	_sling_t += delta
	if not Input.is_action_pressed("sling"):
		_sling_let_go = true
	_show_aim(_stone_origin(), STONE_SPEED)
	if _sling_let_go and _sling_t >= body.WHIRL_TIME:
		_slinging = false
		_aim.visible = false
		body.sling_release()
		_sling_cd = body.RELEASE + body.THROW_TIME + 0.05
		_throw_stone()


func _throw_stone() -> void:
	await get_tree().create_timer(body.RELEASE, false).timeout
	if not is_inside_tree() or dead or not Game.use_ammo("stones"):
		return
	_launch(_stone_origin(), STONE_SPEED, Game.sling_power(), false)


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
	body.rotation.y = yaw
	body.bow_draw()


func _update_bow() -> void:
	if not _aiming_bow:
		return
	_show_aim(body.left_hand_point(), ARROW_SPEED)
	if not Input.is_action_pressed("attack"):
		loose_arrow()


## Lets the arrow go. Returns how far the bow was drawn.
func loose_arrow() -> float:
	if not _aiming_bow:
		return 0.0
	_aiming_bow = false
	_aim.visible = false
	var amount: float = body.bow_loose()
	if not Game.use_ammo("arrows"):
		return amount
	var power := 0.35 + 0.65 * amount
	_launch(body.left_hand_point(), ARROW_SPEED * (0.55 + 0.45 * amount), Game.bow_power() * power, true)
	return amount


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


func _launch(origin: Vector3, speed: float, damage: float, arrow: bool) -> void:
	var shot := ProjectileScript.new()
	shot.world = world
	shot.from_player = true
	shot.damage = damage
	shot.arrow = arrow
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
	Game.hurt_player(amount)
	world.hud.flash_hurt()
	if Game.hp <= 0.0:
		_die()


func _die() -> void:
	if dead:
		return
	dead = true
	Game.hp = 0.0
	body.die()
	world.on_player_died()


func revive(at: Vector3) -> void:
	dead = false
	body.revive()
	velocity = Vector3.ZERO
	global_position = at
