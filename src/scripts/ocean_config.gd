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
const CANYON_CENTER := Vector3(-210,0,-230)
const CANYON_CURRENT_SPEED := 2.2
const CANYON_HALF_LENGTH := 145.0
const CANYON_FLOOR_HALF_WIDTH := 14.0
const CANYON_BANK_HALF_WIDTH := 46.0
const COASTAL_RADIUS := 68.0
const EXPLORATION_NAMES := [
	["海草沙坡", "浅礁贝床"], ["岩岸断层", "外围遗迹"],
	["幽光苔坡", "深蓝花圃"], ["散落货舱", "断桅遗物"],
	["珊瑚外礁", "海扇长廊"], ["外缘石柱", "沙谷石门"],
	["外环贝床", "月光沙台"]
]
const ZONES := [
	{"id":"twin_gates","name":"双门遗迹 · 潮流大峡谷","center":Vector3(-210,-52,-230),"radius":70.0,"core_radius":42.0,"fish_kind":2},
	{"id":"lantern_garden","name":"幽蓝灯园","center":Vector3(35,-82,-360),"radius":70.0,"core_radius":44.0,"fish_kind":2},
	{"id":"merchant_wreck","name":"远航沉船","center":Vector3(310,-52,-130),"radius":74.0,"core_radius":46.0,"fish_kind":1},
	{"id":"amber_reef","name":"琥珀珊瑚礁","center":Vector3(-180,-29,135),"radius":68.0,"core_radius":40.0,"fish_kind":0},
	{"id":"southern_spires","name":"南潮石林","center":Vector3(-45,-52,300),"radius":72.0,"core_radius":44.0,"fish_kind":1},
	{"id":"pearl_atoll","name":"月贝环礁","center":Vector3(245,-32,240),"radius":70.0,"core_radius":42.0,"fish_kind":1},
]

# Boat origins keep the stern jump on the open-water approach to each landmark.
const DIVE_SITES := [
	{"name":"潮汐湾近岸", "origin":Vector3(0,0,0)},
	{"name":"双门遗迹 · 潮流大峡谷", "origin":Vector3(-210,0,-290)},
	{"name":"幽蓝灯园", "origin":Vector3(35,0,-420)},
	{"name":"远航沉船", "origin":Vector3(310,0,-190)},
	{"name":"琥珀珊瑚礁", "origin":Vector3(-180,0,75)},
	{"name":"南潮石林", "origin":Vector3(-45,0,240)},
	{"name":"月贝环礁", "origin":Vector3(245,0,180)},
]

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
		point.y = seabed_height(point.x,point.z)
		result.append({"name":EXPLORATION_NAMES[site_index][branch],"position":point})
	return result

static func exploration_area_for_position(point: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	var best: float = INF
	for area: Dictionary in exploration_areas():
		var distance: float = Vector2(point.x-area.center.x,point.z-area.center.z).length()
		if distance <= float(area.radius)+12.0 and distance < best:
			nearest = area
			best = distance
	return nearest

static func canyon_center_x(z: float) -> float:
	return CANYON_CENTER.x + 5.0*sin((z-CANYON_CENTER.z)*0.045)

static func current_velocity(point: Vector3) -> Vector3:
	var along: float = absf(point.z-CANYON_CENTER.z)
	var across: float = absf(point.x-canyon_center_x(point.z))
	var longitudinal: float = 1.0-smoothstep(100.0,CANYON_HALF_LENGTH,along)
	var lateral: float = 1.0-smoothstep(16.0,44.0,across)
	var depth: float = smoothstep(25.0,45.0,-point.y)
	if longitudinal <= 0 or lateral <= 0 or depth <= 0:
		return Vector3.ZERO
	if point.y < seabed_height(point.x,point.z)+0.7:
		return Vector3.ZERO
	var bend: float = 5.0*0.045*cos((point.z-CANYON_CENTER.z)*0.045)
	return Vector3(bend,0,1).normalized()*CANYON_CURRENT_SPEED*longitudinal*lateral*depth

static func terrain_vertex_height(x: float, z: float) -> float:
	var r: float = Vector2(x,z).length()
	var height: float = -25.0 - 43.0 * smoothstep(35.0,240.0,r)
	height += 4.0*sin(x*0.023)*cos(z*0.019) + 2.6*sin((x+z)*0.041)
	# A winding canyon cuts across the continental shelf, then opens northward.
	var channel: float = x - 78.0*sin(z*0.010)
	height -= 25.0*exp(-pow(channel/30.0,2.0))*smoothstep(40.0,190.0,r)
	height -= 15.0*exp(-Vector2(x-35.0,z+360.0).length_squared()/6400.0)
	height += 24.0*exp(-Vector2(x+180.0,z-135.0).length_squared()/7800.0)
	var atoll_radius: float = Vector2(x-245.0,z-240.0).length()
	height += 22.0*exp(-pow((atoll_radius-28.0)/31.0,2.0))
	# Low stone ridges around the southern gorge, never a perimeter cage.
	height += 11.0*sin(x*0.075)*exp(-Vector2(x+45.0,z-300.0).length_squared()/4900.0)
	# A deep, navigable gorge is local to the twin-gate dive site.
	var canyon_along: float = 1.0-smoothstep(95.0,CANYON_HALF_LENGTH,absf(z-CANYON_CENTER.z))
	var canyon_across: float = 1.0-smoothstep(CANYON_FLOOR_HALF_WIDTH,CANYON_BANK_HALF_WIDTH,absf(x-canyon_center_x(z)))
	height -= 52.0*canyon_along*canyon_across
	return clampf(height,-118.0,-17.0)

## Exact interpolation of the two triangles used in each terrain mesh cell.
## Ray-cast collision and this API agree, including between grid vertices.
static func seabed_height(x: float, z: float) -> float:
	var x0: float = floor(x/TERRAIN_STEP)*TERRAIN_STEP
	var z0: float = floor(z/TERRAIN_STEP)*TERRAIN_STEP
	var u: float = (x-x0)/TERRAIN_STEP
	var v: float = (z-z0)/TERRAIN_STEP
	var a: float = terrain_vertex_height(x0,z0)
	var b: float = terrain_vertex_height(x0+TERRAIN_STEP,z0)
	var c: float = terrain_vertex_height(x0,z0+TERRAIN_STEP)
	if u+v <= 1.0:
		return a+(b-a)*u+(c-a)*v
	var d: float = terrain_vertex_height(x0+TERRAIN_STEP,z0+TERRAIN_STEP)
	return d+(c-d)*(1.0-u)+(b-d)*(1.0-v)

static func pickup_points() -> Array:
	var result: Array = []
	for zone_index in range(ZONES.size()):
		var zone: Dictionary = ZONES[zone_index]
		var center: Vector3 = zone.center
		var relic: String = ["sea_glass","ancient_coin","amber_shard","conch","sea_glass","ancient_coin"][zone_index]
		for spec: Dictionary in [{"kind":"pearl","x":-9.0,"z":25.0},{"kind":relic,"x":9.0,"z":29.0},{"kind":"chest","x":2.0,"z":35.0}]:
			var x: float = center.x+float(spec.x)
			var z: float = center.z+float(spec.z)
			result.append({"kind":spec.kind,"position":Vector3(x,seabed_height(x,z)+1.0,z)})
		# Stations stand clear of landmarks at fish depth, with a shallower route tank.
		var ox: float = center.x-14.0
		var oz: float = center.z+32.0
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
			var kind: String = ["sea_glass","ancient_coin","amber_shard","conch","pearl","sea_glass","ancient_coin"][site] if branch == 0 else ("conch" if site == 0 else "chest")
			result.append({"kind":kind,"position":point,"site_index":site,"exploration":true,"name":points[branch].name})
		var station: Vector3 = area.center + Vector3(0,0,-float(area.radius)*0.72)
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
	point.y = maxf(point.y,seabed_height(point.x,point.z)+10.0)
	return point

static func hazard_home(zone_index: int) -> Vector3:
	var center: Vector3 = ZONES[clampi(zone_index,0,ZONES.size()-1)].center
	var point: Vector3 = center+Vector3(23,0,31)
	point.y = maxf(point.y,seabed_height(point.x,point.z)+12.0)
	return point
