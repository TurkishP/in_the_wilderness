extends Node
## Sends raids against the camp at random intervals. Each raid in a stage is larger and
## stronger than the one before, and each stage starts from a higher base.

var world
var cfg := {}
var raiders: Array = []
var active := false
var stopped := false
var count := 0      # raids started this stage
var cleared := 0    # raids driven off this stage
var forced := 0     # raids still owed to a "defend" objective; these come faster
var timer := 0.0


func setup(c: Dictionary) -> void:
	cfg = c
	timer = _interval() + 15.0


func _interval() -> float:
	var iv: Array = cfg["interval"]
	var t: float = world.rng.randf_range(float(iv[0]), float(iv[1]))
	return t * 0.3 if forced > 0 else t


## A "defend" objective asks for n raids; bring the next one forward.
func force(n: int) -> void:
	forced = n
	timer = minf(timer, 10.0)


func _process(delta: float) -> void:
	if stopped:
		return
	if active:
		var alive: Array = []
		for e in raiders:
			if is_instance_valid(e) and not e.dead:
				alive.append(e)
		raiders = alive
		if raiders.is_empty():
			_cleared()
	else:
		timer -= delta
		if timer <= 0.0:
			start_raid()


func start_raid() -> void:
	active = true
	count += 1
	var size: int = int(cfg["size"]) + int(floor((count - 1) * 0.7))
	var mult: float = float(world.stage["mult"]) * (1.0 + 0.12 * (count - 1))
	var ang: float = world.rng.randf() * TAU
	var far: float = float(world.camp_radius) + 62.0
	var ox := sin(ang) * far
	var oz := cos(ang) * far
	for i in size:
		var kind: String = cfg["kind"]
		if bool(cfg.get("slingers", false)) and i % 3 == 2:
			kind = "slinger"
		var p: Vector3 = world.ground(ox + world.rng.randf_range(-7.0, 7.0), oz + world.rng.randf_range(-7.0, 7.0))
		raiders.append(world.spawn_enemy(kind, p, mult, {"raider": true}))
	Game.say("Raid! %s are coming from the %s." % [cfg["label"], world.compass(ox, oz)])


func _cleared() -> void:
	active = false
	cleared += 1
	Game.raids_survived += 1
	forced = maxi(0, forced - 1)
	timer = _interval()
	var reward := int(8.0 * float(world.stage["mult"]) * (1.0 + 0.25 * (count - 1)))
	Game.silver += reward
	Game.say("The raid is driven off. The camp gives you %d silver." % reward)
	world.on_raid_cleared()


func centroid() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for e in raiders:
		if is_instance_valid(e) and not e.dead:
			sum += e.global_position
			n += 1
	return sum / float(maxi(n, 1))
