extends CharacterBody3D
## Third-person player: movement, camera, thirst, staff and sling.

const ProjectileScript := preload("res://scripts/projectile.gd")
const WALK := 6.0
const SPRINT := 9.5
const JUMP := 6.5
const GRAVITY := 20.0
const LIMIT := 205.0
const SENS := 0.0026

var world
var yaw := 0.0
var pitch := -0.2
var pivot: Node3D
var cam: Camera3D
var body: Node3D
var hand: Node3D
var dead := false
var focus: Node = null
var _melee_cd := 0.0
var _sling_cd := 0.0
var _sprinting := false
var _thirst_warned := 0
var _edge_warn := 0.0


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

	body = Node3D.new()
	add_child(body)
	var robe := Game.mesh_capsule(0.36, 1.5, Color(0.8, 0.72, 0.56))
	robe.position.y = 0.75
	body.add_child(robe)
	var head := Game.mesh_sphere(0.21, Color(0.72, 0.52, 0.38))
	head.position.y = 1.62
	body.add_child(head)
	var cloth := Game.mesh_sphere(0.24, Color(0.9, 0.86, 0.75))
	cloth.position = Vector3(0, 1.68, 0.05)
	cloth.scale = Vector3(1.0, 0.8, 1.0)
	body.add_child(cloth)
	var sash := Game.mesh_cyl(0.37, 0.37, 0.12, Color(0.25, 0.35, 0.55))
	sash.position.y = 0.85
	body.add_child(sash)
	hand = Node3D.new()
	hand.position = Vector3(0.48, 1.0, -0.1)
	body.add_child(hand)
	var staff := Game.mesh_cyl(0.03, 0.04, 1.8, Color(0.42, 0.28, 0.16))
	staff.position.y = 0.25
	hand.add_child(staff)

	pivot = Node3D.new()
	pivot.position = Vector3(0, 1.7, 0)
	pivot.rotation = Vector3(pitch, yaw, 0.0)
	add_child(pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = 5.4
	arm.margin = 0.3
	arm.collision_mask = 1
	arm.position = Vector3(0.95, 0.25, 0)
	# Keeps the camera in place while a dialog pauses the game.
	arm.process_mode = Node.PROCESS_MODE_ALWAYS
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 900.0
	arm.add_child(cam)
	cam.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * SENS
		pitch = clampf(pitch - event.relative.y * SENS, -1.2, 0.7)


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	_sprinting = false
	if not dead and not Game.ui_open:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = Basis(Vector3.UP, yaw) * Vector3(iv.x, 0.0, iv.y)
		_sprinting = Input.is_action_pressed("sprint") and iv.length() > 0.1 and Game.thirst > 0.0
		if is_on_floor() and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
	var speed := SPRINT if _sprinting else WALK
	if Game.thirst <= 0.0:
		speed *= 0.6
	velocity.x = move_toward(velocity.x, dir.x * speed, 50.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 50.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if dir.length() > 0.1:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 12.0 * delta)

	# Keep the player inside the playable area and above the ground.
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
	_melee_cd -= delta
	_sling_cd -= delta
	_edge_warn -= delta
	if dead:
		Game.prompt = ""
		return

	var heat: float = float(world.stage.get("heat", 1.0))
	var rate := 0.3 * heat
	if _sprinting:
		rate += 0.45
	Game.thirst = maxf(0.0, Game.thirst - rate * delta)
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
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("attack"):
			melee()
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


func forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)


## Swings the staff or blade: hits every enemy in a short arc in front.
func melee() -> void:
	if _melee_cd > 0.0 or dead:
		return
	_melee_cd = 0.55
	body.rotation.y = yaw
	var tw := create_tween()
	tw.tween_property(hand, "rotation:x", -1.7, 0.1)
	tw.tween_property(hand, "rotation:x", 0.0, 0.25)
	await get_tree().create_timer(0.12, false).timeout
	if not is_inside_tree() or dead:
		return
	var fwd := forward()
	for e in get_tree().get_nodes_in_group("enemy"):
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist <= 2.6 + float(e.radius) and (dist < 1.0 or fwd.dot(to / dist) > 0.2):
			e.take_damage(Game.melee_power(), self)


## Slings a stone at whatever the crosshair is on.
func sling() -> void:
	if _sling_cd > 0.0 or dead:
		return
	_sling_cd = 0.9
	body.rotation.y = yaw
	var origin := global_position + Vector3(0, 1.5, 0) + forward() * 0.6
	var from := cam.global_position
	var target := from - cam.global_transform.basis.z * 90.0
	var q := PhysicsRayQueryParameters3D.create(from, target, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		if p.distance_to(from) > 6.5:
			target = p
	var shot := ProjectileScript.new()
	shot.world = world
	shot.from_player = true
	shot.damage = Game.sling_power()
	shot.velocity = (target - origin).normalized() * 40.0
	world.stage_root.add_child(shot)
	shot.global_position = origin


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
	body.rotation.x = -PI * 0.5
	world.on_player_died()


func revive(at: Vector3) -> void:
	dead = false
	body.rotation.x = 0.0
	velocity = Vector3.ZERO
	global_position = at
