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
const ZONES := [
	{"id":"twin_gates","name":"双门遗迹","center":Vector3(-210,-52,-230),"radius":42.0,"fish_kind":2},
	{"id":"lantern_garden","name":"幽蓝灯园","center":Vector3(35,-82,-360),"radius":44.0,"fish_kind":2},
	{"id":"merchant_wreck","name":"远航沉船","center":Vector3(310,-52,-130),"radius":46.0,"fish_kind":1},
	{"id":"amber_reef","name":"琥珀珊瑚礁","center":Vector3(-180,-29,135),"radius":40.0,"fish_kind":0},
	{"id":"southern_spires","name":"南潮石林","center":Vector3(-45,-52,300),"radius":44.0,"fish_kind":1},
	{"id":"pearl_atoll","name":"月贝环礁","center":Vector3(245,-32,240),"radius":42.0,"fish_kind":1},
]

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
	for zone in ZONES:
		var center: Vector3 = zone.center
		for spec: Dictionary in [{"kind":"pearl","x":-9.0,"z":25.0},{"kind":"pearl","x":9.0,"z":29.0},{"kind":"chest","x":2.0,"z":35.0}]:
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
	return result

static func zone_for_position(point: Vector3) -> Dictionary:
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
	var center: Vector3 = ZONES[clampi(zone_index,0,ZONES.size()-1)].center
	var column: int = posmod(fish_index,5)
	var row: int = clampi(int(float(fish_index)/5.0),0,4)
	var point: Vector3 = center+Vector3(float(column-2)*5.0,float(row-1)*3.0,25.0+float(row)*5.0)
	point.y = maxf(point.y,seabed_height(point.x,point.z)+10.0)
	return point

static func hazard_home(zone_index: int) -> Vector3:
	var center: Vector3 = ZONES[clampi(zone_index,0,ZONES.size()-1)].center
	var point: Vector3 = center+Vector3(23,0,31)
	point.y = maxf(point.y,seabed_height(point.x,point.z)+12.0)
	return point
