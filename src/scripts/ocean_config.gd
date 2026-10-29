extends RefCounted
class_name OceanConfig
## A kilometre-wide dive area. Scenery continues 200 metres past its boundary.
const X_MIN := -500.0
const X_MAX := 500.0
const Z_MIN := -500.0
const Z_MAX := 500.0
const Y_MIN := -120.0
const Y_MAX := -1.5
const FLOOR_Y := -120.0
const FLOOR_CENTER_Y := -123.0
const BOUNDS_MIN := Vector3(X_MIN,Y_MIN,Z_MIN)
const BOUNDS_MAX := Vector3(X_MAX,Y_MAX,Z_MAX)
const FLOOR_SIZE := Vector3(1400.0,6.0,1400.0)
const SURFACE_SIZE := Vector2(1400.0,1400.0)
const TERRAIN_EXTENT := 700.0
const TERRAIN_STEP := 4.0
const CANYON_TERRAIN_STEP := 2.0
const CANYON_CENTER := Vector3(-210,0,-230)
const CANYON_CURRENT_SPEED := 2.2
const CANYON_HALF_LENGTH := 225.0
const CANYON_BEND_AMPLITUDE := 26.0
const CANYON_BEND_FREQUENCY := 0.018
const CANYON_FLOOR_HALF_WIDTH := 14.0
const CANYON_BANK_HALF_WIDTH := 62.0
const COASTAL_RADIUS := 68.0
const EXPLORATION_NAMES := [
	["海草沙坡", "浅礁贝床"], ["岩岸断层", "外围遗迹"],
	["散落货舱", "断桅遗物"],
	["珊瑚外礁", "海扇长廊"], ["外缘石柱", "沙谷石门"],
	["外环贝床", "月光沙台"]
]
const ZONES := [
	{"id":"twin_gates","name":"双门遗迹 · 潮流大峡谷","center":Vector3(-210,-52,-230),"radius":70.0,"core_radius":42.0,"fish_kind":2},
	{"id":"merchant_wreck","name":"远航沉船","center":Vector3(310,-52,-130),"radius":74.0,"core_radius":46.0,"fish_kind":1},
	{"id":"amber_reef","name":"琥珀珊瑚礁","center":Vector3(-180,-29,135),"radius":68.0,"core_radius":40.0,"fish_kind":0},
	{"id":"southern_spires","name":"南潮石林","center":Vector3(-45,-52,300),"radius":72.0,"core_radius":44.0,"fish_kind":1},
	{"id":"pearl_atoll","name":"月贝环礁","center":Vector3(245,-32,240),"radius":70.0,"core_radius":42.0,"fish_kind":1},
]

# Boat origins keep the stern jump on the open-water approach to each landmark.
const DIVE_SITES := [
	{"id":"tidal_cove","name":"潮汐湾近岸", "origin":Vector3(0,0,0)},
	{"id":"twin_gates","name":"双门遗迹 · 潮流大峡谷", "origin":Vector3(-226,0,-290)},
	{"id":"merchant_wreck","name":"远航沉船", "origin":Vector3(310,0,-190)},
	{"id":"amber_reef","name":"琥珀珊瑚礁", "origin":Vector3(-180,0,75)},
	{"id":"southern_spires","name":"南潮石林", "origin":Vector3(-45,0,240)},
	{"id":"pearl_atoll","name":"月贝环礁", "origin":Vector3(245,0,180)},
]

static func site_index(id: String) -> int:
	for index in range(DIVE_SITES.size()):
		if DIVE_SITES[index].id == id:
			return index
	return -1

static func exploration_areas() -> Array:
	var result: Array = [{"id":"tidal_cove","name":"潮汐湾 · 近岸","center":Vector3(0,-22,0),"radius":COASTAL_RADIUS,"core_radius":42.0}]
	result.append_array(ZONES)
	return result

static func exploration_points(site_index: int) -> Array:
	if site_index < 0 or site_index >= DIVE_SITES.size():
		return []
	var area: Dictionary = exploration_areas()[site_index]
	var center: Vector3 = area.center
	var radius: float = area.radius
	var result: Array = []
	for branch in range(2):
		var side: float = -1.0 if branch == 0 else 1.0
		var point: Vector3 = center + Vector3(side*radius*0.82,0,-side*radius*0.18)
		if site_index == 1:
			# Discoveries sit inside the bends, reachable without crossing the island ridge.
			point.z = center.z + side * 52.0
			point.x = canyon_center_x(point.z) + side * 8.0
		point.y = seabed_height(point.x,point.z)
		result.append({"name":EXPLORATION_NAMES[site_index][branch],"position":point})
	return result

static func exploration_area_for_position(point: Vector3) -> Dictionary:
	if absf(point.z-CANYON_CENTER.z) <= CANYON_HALF_LENGTH and absf(point.x-canyon_center_x(point.z)) <= CANYON_BANK_HALF_WIDTH:
		return ZONES[0]
	var nearest: Dictionary = {}
	var best: float = INF
	for area: Dictionary in exploration_areas():
		var distance: float = Vector2(point.x-area.center.x,point.z-area.center.z).length()
		if distance <= float(area.radius)+12.0 and distance < best:
			nearest = area
			best = distance
	return nearest

static func canyon_center_x(z: float) -> float:
	return CANYON_CENTER.x + CANYON_BEND_AMPLITUDE*sin((z-CANYON_CENTER.z)*CANYON_BEND_FREQUENCY)

static func canyon_tangent(z: float) -> Vector3:
	var bend: float = CANYON_BEND_AMPLITUDE*CANYON_BEND_FREQUENCY*cos((z-CANYON_CENTER.z)*CANYON_BEND_FREQUENCY)
	return Vector3(bend,0,1).normalized()

static func current_velocity(point: Vector3) -> Vector3:
	var along: float = absf(point.z-CANYON_CENTER.z)
	var across: float = absf(point.x-canyon_center_x(point.z))
	var longitudinal: float = 1.0-smoothstep(CANYON_HALF_LENGTH-45.0,CANYON_HALF_LENGTH,along)
	var lateral: float = 1.0-smoothstep(12.0,28.0,across)
	var depth: float = smoothstep(25.0,45.0,-point.y)
	if longitudinal <= 0 or lateral <= 0 or depth <= 0:
		return Vector3.ZERO
	if point.y < seabed_height(point.x,point.z)+0.7:
		return Vector3.ZERO
	return canyon_tangent(point.z)*CANYON_CURRENT_SPEED*longitudinal*lateral*depth

static func terrain_vertex_height(x: float, z: float) -> float:
	# Fine canyon chunks meet coarse shelf chunks on the same straight edges.
	# Interpolate odd edge vertices so neither rendering nor collision has cracks.
	if is_zero_approx(fposmod(x + TERRAIN_EXTENT, 200.0)) and not is_zero_approx(fposmod(z, TERRAIN_STEP)):
		var base_z: float = floor(z / TERRAIN_STEP) * TERRAIN_STEP
		return lerpf(_terrain_height(x, base_z), _terrain_height(x, base_z + TERRAIN_STEP), (z - base_z) / TERRAIN_STEP)
	if is_zero_approx(fposmod(z + TERRAIN_EXTENT, 200.0)) and not is_zero_approx(fposmod(x, TERRAIN_STEP)):
		var base_x: float = floor(x / TERRAIN_STEP) * TERRAIN_STEP
		return lerpf(_terrain_height(base_x, z), _terrain_height(base_x + TERRAIN_STEP, z), (x - base_x) / TERRAIN_STEP)
	return _terrain_height(x, z)

static func terrain_step_at(x: float, z: float) -> float:
	return CANYON_TERRAIN_STEP if x >= -300.0 and x < -100.0 and z >= -500.0 and z < 100.0 else TERRAIN_STEP

static func _terrain_height(x: float, z: float) -> float:
	var r: float = Vector2(x,z).length()
	var height: float = -25.0 - 43.0 * smoothstep(35.0,240.0,r)
	height += 4.0*sin(x*0.023)*cos(z*0.019) + 2.6*sin((x+z)*0.041)
	# A winding canyon cuts across the continental shelf, then opens northward.
	var channel: float = x - 78.0*sin(z*0.010)
	height -= 25.0*exp(-pow(channel/30.0,2.0))*smoothstep(40.0,190.0,r)
	height -= 15.0*exp(-Vector2(x-35.0,z+360.0).length_squared()/6400.0)
	height += 24.0*exp(-Vector2(x+180.0,z-135.0).length_squared()/7800.0)
	var atoll_delta := Vector2(x-245.0,z-240.0)
	var atoll_radius: float = atoll_delta.length()
	var atoll_angle: float = atan2(atoll_delta.y,atoll_delta.x)
	var reef_radius: float = 30.0+sin(atoll_angle*3.0+.8)*4.0+cos(atoll_angle*5.0)*2.0
	var channel_angle: float = absf(wrapf(atoll_angle-PI*.5,-PI,PI))
	var reef_bank: float = smoothstep(.18,.55,channel_angle)
	height += 17.0*exp(-pow(atoll_radius/54.0,4.0))
	height += 7.0*exp(-pow((atoll_radius-reef_radius)/11.0,2.0))*reef_bank
	height -= 1.5*exp(-atoll_radius*atoll_radius/300.0)
	# Low stone ridges around the southern gorge, never a perimeter cage.
	height += 11.0*sin(x*0.075)*exp(-Vector2(x+45.0,z-300.0).length_squared()/4900.0)
	# A deep, navigable gorge is local to the twin-gate dive site.
	var canyon_along: float = 1.0-smoothstep(CANYON_HALF_LENGTH-65.0,CANYON_HALF_LENGTH,absf(z-CANYON_CENTER.z))
	var across: float = absf(x-canyon_center_x(z))
	var canyon_across: float = 1.0-smoothstep(CANYON_FLOOR_HALF_WIDTH,CANYON_BANK_HALF_WIDTH,across)
	height -= 52.0*canyon_along*canyon_across
	# Ease into the sediment floor instead of hard-clipping the slope at -118m;
	# a hard maximum creates a sawtooth lighting seam along diagonal grid cells.
	if height < -114.0:
		height = -118.0 + 4.0*exp((height+114.0)/4.0)
	height = minf(height,-17.0)
	# Two eroded island ridges grow out of the same collision mesh as the gorge.
	# The deep centre stays open, with broad mouths tapering into the original shelf.
	# Broad, unequal erosion scallops break up the two parallel walls. They fade
	# into the sandy channel and the crest, preserving the open swimming lanes.
	var bank_side: float = signf(x-canyon_center_x(z))
	var erosion: float = (sin(z*0.057+bank_side*1.9)*1.8 + sin(z*0.113-bank_side)*0.65)
	var wall_across: float = across + erosion*smoothstep(14.0,25.0,across)*(1.0-smoothstep(36.0,43.0,across))
	var ridge: float = smoothstep(22.0,43.0,wall_across)*(1.0-smoothstep(43.0,CANYON_BANK_HALF_WIDTH,across))
	var crest: float = 26.0 + 6.0*sin(z*0.047+x*0.031) + 3.0*cos(z*0.091-x*0.063)
	return lerpf(height,crest,ridge*canyon_along)

## Exact interpolation of the two triangles used in each terrain mesh cell.
## Ray-cast collision and this API agree, including between grid vertices.
static func seabed_height(x: float, z: float) -> float:
	var step: float = terrain_step_at(x,z)
	var x0: float = floor(x/step)*step
	var z0: float = floor(z/step)*step
	var u: float = (x-x0)/step
	var v: float = (z-z0)/step
	var a: float = terrain_vertex_height(x0,z0)
	var b: float = terrain_vertex_height(x0+step,z0)
	var c: float = terrain_vertex_height(x0,z0+step)
	if u+v <= 1.0:
		return a+(b-a)*u+(c-a)*v
	var d: float = terrain_vertex_height(x0+step,z0+step)
	return d+(c-d)*(1.0-u)+(b-d)*(1.0-v)

static func pickup_points() -> Array:
	var result: Array = []
	for zone_index in range(ZONES.size()):
		var zone: Dictionary = ZONES[zone_index]
		var center: Vector3 = zone.center
		var relic: String = ["sea_glass","amber_shard","conch","sea_glass","ancient_coin"][zone_index]
		for spec: Dictionary in [{"kind":"pearl","x":-9.0,"z":25.0},{"kind":relic,"x":9.0,"z":29.0},{"kind":"chest","x":2.0,"z":35.0}]:
			var x: float = center.x+float(spec.x)
			var z: float = center.z+float(spec.z)
			if zone_index == 0:
				x = canyon_center_x(z)+float(spec.x)
			var record := {"kind":spec.kind,"position":Vector3(x,seabed_height(x,z)+1.0,z)}
			if zone.id == "merchant_wreck":
				record["wreck_local"] = Vector3(-2.2,1.35,-19) if spec.kind == "pearl" else (Vector3(2.2,1.35,4) if spec.kind != "chest" else Vector3(1.8,1.35,20))
			result.append(record)
		# Stations stand clear of landmarks at fish depth, with a shallower route tank.
		var ox: float = center.x-14.0
		var oz: float = center.z+32.0
		if zone_index == 0:
			ox = canyon_center_x(oz)-10.0
		result.append({"kind":"oxygen","position":Vector3(ox,maxf(center.y,seabed_height(ox,oz)+9.0),oz)})
		for fraction: float in [0.28,0.54,0.78]:
			var route: Vector3 = center*fraction
			route.y = maxf(-18.0-fraction*18.0,seabed_height(route.x,route.z)+7.0)
			result.append({"kind":"oxygen","position":route})
	# Each wider area gains two outer discoveries and a northern loop air station.
	# Keep all original pickup ordering intact for existing saves and test fixtures.
	var areas: Array = exploration_areas()
	for site in range(areas.size()):
		var area: Dictionary = areas[site]
		var points: Array = exploration_points(site)
		for branch in range(points.size()):
			var point: Vector3 = points[branch].position + Vector3.UP
			var kind: String = ["sea_glass","ancient_coin","conch","pearl","sea_glass","ancient_coin"][site] if branch == 0 else ("conch" if site == 0 else "chest")
			result.append({"kind":kind,"position":point,"site_index":site,"exploration":true,"name":points[branch].name})
		var station: Vector3 = area.center + Vector3(0,0,-float(area.radius)*0.72)
		if site == 1:
			station.x = canyon_center_x(station.z)
		station.y = maxf(area.center.y,seabed_height(station.x,station.z)+8.0)
		result.append({"kind":"oxygen","position":station,"site_index":site,"exploration":true,"name":"外围补气点"})
	return result

static func zone_for_position(point: Vector3) -> Dictionary:
	# The enlarged gorge is a long corridor; its label follows both mouths without
	# moving the circular side discoveries or changing other exploration areas.
	if absf(point.z-CANYON_CENTER.z) <= CANYON_HALF_LENGTH and absf(point.x-canyon_center_x(point.z)) <= CANYON_BANK_HALF_WIDTH+12.0:
		return ZONES[0]
	var nearest: Dictionary = {}
	var best: float = INF
	for zone in ZONES:
		var center: Vector3 = zone.center
		var distance: float = Vector2(point.x-center.x,point.z-center.z).length()
		if distance < best and distance <= float(zone.radius)+12.0:
			nearest = zone
			best = distance
	return nearest

## Unobstructed southern landmark approaches; leave room for the swim envelope.
static func fish_home(zone_index: int, fish_index: int) -> Vector3:
	var zone: Dictionary = ZONES[clampi(zone_index,0,ZONES.size()-1)]
	var center: Vector3 = zone.center
	var point: Vector3
	if fish_index < 4:
		point = center+Vector3((float(fish_index)-1.5)*10.0,float(fish_index%2)*3.0,27.0+float(fish_index%2)*7.0)
	else:
		var angle: float = float(fish_index-4)*2.399963+float(zone_index)*0.47
		var reach: float = float(zone.radius)*(0.55+0.34*float(fish_index%4)/3.0)
		point = center+Vector3(sin(angle)*reach,float(fish_index%3-1)*3.0,cos(angle)*reach)
	if zone_index == 0:
		# Fish patrols remain in the water between the emergent banks.
		if fish_index >= 4:
			point.z = center.z + (-1.0 if fish_index%2 == 0 else 1.0)*(35.0+float(fish_index%5)*6.0)
		point.x = canyon_center_x(point.z)+(float(fish_index%4)-1.5)*5.0
	point.y = maxf(point.y,seabed_height(point.x,point.z)+10.0)
	return point

static func hazard_home(zone_index: int) -> Vector3:
	var center: Vector3 = ZONES[clampi(zone_index,0,ZONES.size()-1)].center
	var point: Vector3 = center+Vector3(23,0,31)
	if zone_index == 0:
		point.x = canyon_center_x(point.z)+12.0
	point.y = maxf(point.y,seabed_height(point.x,point.z)+12.0)
	return point
