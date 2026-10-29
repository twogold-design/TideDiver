extends RefCounted
## Water absorbs sunlight gradually. The diver lamp only illuminates nearby objects.
const Ocean = preload("res://scripts/ocean_config.gd")
const AMBIENT_ENERGY := 0.38
const SUN_ENERGY := 0.65
const FOG_ENERGY := 0.85
const LAMP_ENERGY := 0.35
const AMBIENT_COLOR := Color("b0c9cb")
const SUN_COLOR := Color("fff1d4")
const LAMP_COLOR := Color("a2ffe4")

static func profile(depth: float, location: Vector3 = Vector3.INF) -> Dictionary:
	var d: float = clampf(depth,0.0,140.0) if is_finite(depth) else 0.0
	var absorption: float = maxf(d-5.0,0.0)
	var blue_shift: float = smoothstep(5.0,110.0,d)
	var values := {
		"ambient_energy":0.045+(AMBIENT_ENERGY-0.045)*exp(-absorption*0.028),
		"sun_energy":SUN_ENERGY*exp(-absorption*0.030),
		"fog_energy":0.14+(FOG_ENERGY-0.14)*exp(-absorption*0.018),
		"ambient_color":AMBIENT_COLOR.lerp(Color("49687f"),blue_shift),
		"sun_color":SUN_COLOR.lerp(Color("6b9cbe"),blue_shift),
		"water_color":Color("14596b").lerp(Color("041426"),1.0-exp(-d*0.022)),
		"lamp_energy":LAMP_ENERGY+0.75*smoothstep(18.0,100.0,d),
		"lamp_color":LAMP_COLOR.lerp(Color("c6ebe8"),blue_shift)
	}
	# Diffuse blue fill makes the open canyon's near walls readable while the
	# distant bends still disappear into deep water. Fade at both mouths and banks.
	if location.is_finite():
		var along: float = absf(location.z-Ocean.CANYON_CENTER.z)
		var across: float = absf(location.x-Ocean.canyon_center_x(location.z))
		var fill: float = smoothstep(28.0,65.0,d)*(1.0-smoothstep(44.0,68.0,across))*(1.0-smoothstep(Ocean.CANYON_HALF_LENGTH-45.0,Ocean.CANYON_HALF_LENGTH+10.0,along))
		values.ambient_energy += 0.14*fill
		values.sun_energy += 0.08*fill
		values.fog_energy += 0.12*fill
		values.ambient_color = values.ambient_color.lerp(Color("7cabb2"),fill*.55)
		values.water_color = values.water_color.lerp(Color("103b4c"),fill*.65)
	return values

static func apply(environment: Environment, sun: DirectionalLight3D, lamp: OmniLight3D, values: Dictionary, immersion: float = 1.0) -> void:
	var blend: float = clampf(immersion,0.0,1.0)
	environment.ambient_light_energy = lerpf(AMBIENT_ENERGY,values.ambient_energy,blend)
	environment.ambient_light_color = AMBIENT_COLOR.lerp(values.ambient_color,blend)
	environment.fog_light_energy = lerpf(FOG_ENERGY,values.fog_energy,blend)
	sun.light_energy = lerpf(SUN_ENERGY,values.sun_energy,blend)
	sun.light_color = SUN_COLOR.lerp(values.sun_color,blend)
	lamp.light_energy = lerpf(LAMP_ENERGY,values.lamp_energy,blend)
	lamp.light_color = LAMP_COLOR.lerp(values.lamp_color,blend)
	lamp.omni_range = 12.0
	lamp.visible = blend > 0.01

static func reset(environment: Environment, sun: DirectionalLight3D, lamp: OmniLight3D) -> void:
	apply(environment,sun,lamp,profile(0.0),0.0)
	lamp.visible = false
	environment.fog_density = 0.0065
	environment.fog_light_color = Color("136675")
	environment.background_color = Color("126879")
