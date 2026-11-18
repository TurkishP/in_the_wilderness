extends Node
## The day: where the sun or the moon stands at the hour, and the light, sky and haze that go
## with it. A day in the game lasts six hours of play (Game.DAY_SECONDS); the hour is Game.clock.
##
## The sun rises due east at six, stands NOON_HEIGHT degrees up in the south at noon (the camps
## lie near 29 degrees north) and sets due west at eighteen. By night the same light is the
## moon, crossing the same arc twelve hours behind, dim and blue. Around sunrise and sunset the
## sky and the haze turn warm. The pillar that guides the camp is cloud by day and fire by
## night (Exodus 13:21-22), and at night it lights the tents round it.

const CloudScript := preload("res://scripts/cloud_pillar.gd")

const NOON_HEIGHT := 68.0
const DAY := {"top": Color(0.24, 0.47, 0.84), "horizon": Color(0.87, 0.81, 0.69), "ground": Color(0.6, 0.5, 0.36), "fog": Color(0.87, 0.79, 0.65)}
const DUSK := {"top": Color(0.3, 0.36, 0.62), "horizon": Color(0.98, 0.62, 0.4), "ground": Color(0.5, 0.38, 0.3), "fog": Color(0.93, 0.66, 0.48)}
const NIGHT := {"top": Color(0.015, 0.025, 0.07), "horizon": Color(0.06, 0.085, 0.15), "ground": Color(0.04, 0.04, 0.06), "fog": Color(0.07, 0.09, 0.15)}

var world
var held := false        # something else is setting the light: the title screen, a debug picture
var night := 0.0         # 0 by day .. 1 in the dead of night
var to_light := Vector3.UP   # the way to the sun, or by night the moon
var _sky_hour := -99.0   # the hour the sky was last colored for
var _fire: OmniLight3D   # the light the pillar of fire gives


## How high the sun stands: 1 at noon, 0 at six and at eighteen, below 0 by night.
static func sun_height(hour: float) -> float:
	return sin(PI * (hour - 6.0) / 12.0)


## Sets the light for `hour` (0..24). The sky's colors are only touched when they have changed
## enough to see, since each change makes the engine light the scene from the sky afresh.
func apply(hour: float, at_once: bool = false) -> void:
	if held or world == null or world.sun == null:
		return
	var h := sun_height(hour)
	var along := PI * fposmod(hour - 6.0, 12.0) / 12.0      # along the arc, east to west
	var top := deg_to_rad(NOON_HEIGHT)
	to_light = Vector3(cos(along), sin(along) * sin(top), sin(along) * cos(top))
	# Never quite on the horizon, where every shadow would run on for ever.
	to_light.y = maxf(to_light.y, 0.06)
	to_light = to_light.normalized()
	var sun: DirectionalLight3D = world.sun
	sun.basis = Basis.looking_at(-to_light, Vector3.UP)
	var lift := smoothstep(0.0, 0.3, absf(h))
	if h >= 0.0:
		sun.light_color = Color(1.0, 0.6, 0.36).lerp(Color(1.0, 0.96, 0.88), smoothstep(0.0, 0.45, h))
		sun.light_energy = lerpf(0.05, 1.1, lift)
	else:
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = lerpf(0.03, 0.24, lift)
	night = smoothstep(0.05, -0.25, h)
	CloudScript.burn(night)
	if world.home != null and is_instance_valid(world.home) and world.home.door_light != null:
		world.home.door_light.light_energy = lerpf(0.8, 0.12, night)
		world.home.door_light.light_color = Color(1.0, 0.92, 0.8).lerp(Color(0.6, 0.7, 1.0), night)
	_light_the_pillar()
	if not at_once and absf(hour - _sky_hour) < 0.03:
		return
	_sky_hour = hour
	var day := smoothstep(-0.2, 0.3, h)
	var glow := exp(-pow(h / 0.2, 2.0)) * 0.75
	var env: Environment = world.environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = _shade("top", day, glow)
	sky.sky_horizon_color = _shade("horizon", day, glow)
	sky.ground_horizon_color = _shade("horizon", day, glow)
	sky.ground_bottom_color = _shade("ground", day, glow)
	# The sky lights the ground; a dark sky is helped along so the night can still be seen in.
	env.ambient_light_energy = lerpf(2.2, 0.55, day)
	if world.weather != null:
		world.weather.set_still_color(_shade("fog", day, glow))


func _shade(key: String, day: float, glow: float) -> Color:
	return (NIGHT[key] as Color).lerp(DAY[key], day).lerp(DUSK[key], glow)


## By night the pillar is fire and gives light to the camp.
func _light_the_pillar() -> void:
	var pillar = world.camp.guide if world.camp != null else null
	if pillar == null or not is_instance_valid(pillar):
		_fire = null
		return
	if _fire == null or not is_instance_valid(_fire) or _fire.get_parent() != pillar:
		_fire = OmniLight3D.new()
		_fire.light_color = Color(1.0, 0.62, 0.3)
		_fire.omni_range = 150.0
		_fire.omni_attenuation = 0.6
		_fire.position = Vector3(0, 30.0, 0)
		_fire.shadow_enabled = false
		pillar.add_child(_fire)
	_fire.light_energy = 5.0 * night
	_fire.visible = night > 0.01 and pillar.visible
