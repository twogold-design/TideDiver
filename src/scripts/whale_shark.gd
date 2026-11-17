extends Node3D
## One gentle giant in the open northern basin, independent of catchable fish.
const Ocean = preload("res://scripts/ocean_config.gd")
const Art = preload("res://scripts/whale_shark_art.gd")
const HABITAT_CENTER := Vector3(35.0, -70.0, -360.0)
const VIEW_DISTANCE := 155.0
const PATROL_RATE := 0.022
var spawned := false
var phase_offset := 0.0
var model: Node3D
var _world_origin := Vector3.ZERO

static func build(parent: Node3D) -> Node3D:
	var shark = load("res://scripts/whale_shark.gd").new()
	shark.name = "DeepWhaleShark"
	parent.add_child(shark)
	shark._world_origin = parent.global_position if parent.is_inside_tree() else parent.position
	shark.model = Art.build()
	shark.model.name = "WhaleSharkModel"
	shark.add_child(shark.model)
	shark.visible = false
	shark.set_meta("feature_name", "鲸鲨")
	shark.set_meta("ambient_only", true)
	shark.set_meta("no_collision", true)
	return shark

func begin_dive(seed_value: int) -> bool:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	phase_offset = random.randf_range(-PI, PI)
	spawned = true
	position = _route_point(0.0) - _world_origin
	rotation = Vector3.ZERO
	Art.animate(model, 0.0)
	visible = false
	return true

func animate(time: float, viewer: Vector3) -> void:
	if not spawned:
		visible = false
		return
	var point: Vector3 = _route_point(time)
	var forward: Vector3 = (_route_point(time + 0.2) - point).normalized()
	position = point - _world_origin
	if forward.length_squared() > 0.001:
		basis = Basis.looking_at(forward, Vector3.UP)
	Art.animate(model, time)
	visible = viewer.distance_squared_to(point) < VIEW_DISTANCE * VIEW_DISTANCE

func _route_point(time: float) -> Vector3:
	var phase: float = time * PATROL_RATE + phase_offset
	var point := HABITAT_CENTER + Vector3(cos(phase) * 38.0, 0, sin(phase) * 26.0)
	# Check the whole animal's footprint, including its wide fins and tail. The
	# basin is scenery-free; this envelope keeps the giant clear of its slopes.
	var highest_floor := -INF
	for x: float in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		for z: float in [-14.0, -7.0, 0.0, 7.0, 14.0]:
			highest_floor = maxf(highest_floor, Ocean.seabed_height(point.x + x, point.z + z))
	point.y = maxf(-74.0 + sin(phase * 2.0) * 1.5, highest_floor + 11.0)
	return point
