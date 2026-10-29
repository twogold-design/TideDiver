extends SceneTree
## Actual local controls, joint poses and movement measured in physics frames.
const Ocean = preload("res://scripts/ocean_config.gd")
const CALM := Vector3(400, -20, 400)
const ACTIONS = ["swim_left", "swim_right", "swim_forward", "swim_back", "ascend", "descend", "boost", "stealth"]
const JOINT_PATHS = {"leg_left":"LegLeft", "leg_right":"LegRight", "knee_left":"LegLeft/KneeLeft", "knee_right":"LegRight/KneeRight", "arm_left":"ArmLeft", "arm_right":"ArmRight"}

class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var game: Node
var rig: Node3D
var memory: MemoryProgression
var joints: Dictionary = {}
var neutral_pose: Dictionary = {}
var checks: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		printerr("FAIL: main scene could not load")
		quit(1)
		return
	game = scene.instantiate()
	memory = MemoryProgression.new()
	memory.persistence_enabled = false
	game.progress = memory
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	# The fixture supplies Input actions and headings; captured desktop mouse events
	# must not replace those headings while the real physics frames are measured.
	game.set_process_unhandled_input(false)
	await physics_frame
	await process_frame
	game.start_dive(false, false)
	rig = game.player.get_child(0)
	for label in JOINT_PATHS:
		var joint: Node3D = rig.get_node_or_null(JOINT_PATHS[label])
		if joint != null:
			joints[label] = joint
	_check(joints.size() == 6, "The actual diver has articulated hips, knees and both arm joints")
	if joints.size() == 6:
		neutral_pose = _joint_transforms(rig)
		var progress_before: Dictionary = memory._save_data().duplicate(true)
		await _test_directional_poses()
		await _test_smooth_release_and_diagonal()
		await _test_heading_and_collision()
		await _test_pause_and_gm_freeze()
		await _test_current_idle()
		await _test_lifecycle_resets()
		_check(memory._save_data() == progress_before and memory.saves == 0, "Swimming animation and GM tests do not mutate or save durable progress")
	_release_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver directional diver motion (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_directional_poses() -> void:
	var left: Dictionary = await _sample(["swim_left"])
	var left_aim: Vector3 = _launch_direction()
	var right: Dictionary = await _sample(["swim_right"])
	var right_aim: Vector3 = _launch_direction()
	var forward: Dictionary = await _sample(["swim_forward"])
	var backward: Dictionary = await _sample(["swim_back"])
	_check(left.pose.rig.z > 0.15 and right.pose.rig.z < -0.15 and absf(left.pose.rig.z + right.pose.rig.z) < 0.02, "Left and right controls produce mirrored visible body banks")
	_check(left.pose.leg_left.y > 0.10 and left.pose.leg_right.y > 0.10 and right.pose.leg_left.y < -0.10 and right.pose.leg_right.y < -0.10, "Both fins scull sideways in opposite directions for left and right swimming")
	_check(left.pose.arm_left.distance_to(right.pose.arm_left) > 0.10, "The balancing arm visibly changes its sculling pose with lateral direction")
	_check(backward.pose.rig.x > 0.12 and absf(forward.pose.rig.x) < 0.04, "Reverse swimming visibly lifts the chest instead of reusing the forward pose")
	var forward_bend: float = forward.pose.knee_left.x + forward.pose.knee_right.x
	var reverse_bend: float = backward.pose.knee_left.x + backward.pose.knee_right.x
	_check(reverse_bend < forward_bend - 0.30 and backward.pose.leg_left.y < -0.08 and backward.pose.leg_right.y > 0.08, "Reverse swimming uses deeper synchronized knee bends and outward fin sweeps")
	_check(forward.pose.leg_left.x * forward.pose.leg_right.x < 0 and backward.pose.leg_left.x * backward.pose.leg_right.x > 0, "Forward flutter alternates the fins while reverse strokes move them together")
	var unchanged_speed: bool = true
	var motion_diagnostics := PackedStringArray()
	var samples: Dictionary = {"left":left,"right":right,"forward":forward,"backward":backward}
	for direction: String in samples:
		var sample: Dictionary = samples[direction]
		motion_diagnostics.append("%s displacement=%s elapsed=%.6f yaw=%.6f collisions=%d" % [direction,sample.displacement,sample.elapsed,sample.yaw,sample.collisions])
	for sample in [left, right, forward, backward]:
		unchanged_speed = unchanged_speed and absf(sample.displacement.length() / sample.elapsed - 6.2) < 0.03 and sample.collisions == 0
	_check(unchanged_speed and left.displacement.x < -3 and right.displacement.x > 3 and forward.displacement.z < -3 and backward.displacement.z > 3, "The new poses preserve the original four movement directions and 6.2 metre swimming speed: " + "; ".join(motion_diagnostics))
	_check(left_aim.length() > 0.9 and left_aim.distance_to(right_aim) < 0.001 and left.yaw == 0 and right.yaw == 0, "Body banking leaves actual launched-hook aim and the camera heading unchanged: left aim=%s yaw=%.6f; right aim=%s yaw=%.6f" % [left_aim,left.yaw,right_aim,right.yaw])

func _test_smooth_release_and_diagonal() -> void:
	var held: Dictionary = await _sample(["swim_left"])
	_release_actions()
	await _advance_frames(1)
	var first_bank: float = absf(rig.rotation.z)
	await _advance_frames(45)
	_check(first_bank > 0.03 and first_bank < absf(held.pose.rig.z), "Releasing a lateral key begins a smooth return instead of snapping the body straight")
	_check(absf(rig.rotation.z) < 0.01 and absf(rig.rotation.x) < 0.01 and absf(joints.leg_left.rotation.y) < 0.02 and absf(joints.leg_right.rotation.y) < 0.02 and game.diver_motion.motion_input.length() < 0.01, "Released body banking and lateral leg sweeps settle back to idle")
	var diagonal: Dictionary = await _sample(["swim_forward", "swim_right", "ascend", "boost"], 48)
	_check(diagonal.bounded and game.diver_motion.motion_input.is_finite() and game.diver_motion.motion_input.length() <= 1.001, "Mixed diagonal and boosted poses remain finite and within natural joint angles throughout the stroke")
	_check(absf(diagonal.displacement.length() / diagonal.elapsed - 11.5) < 0.04 and diagonal.displacement.x > 4 and diagonal.displacement.y > 4 and diagonal.displacement.z < -4, "Diagonal sprinting retains normalized input and the original boosted speed")
	_check(diagonal.pose.rig.z < -0.08 and absf(diagonal.pose.leg_left.y) > 0.05, "Diagonal movement blends a lateral bank and fin stroke into the forward animation")

func _test_heading_and_collision() -> void:
	var turned: Dictionary = await _sample(["swim_left"], 30, CALM, PI / 2)
	var ray: Vector3 = game.camera.project_ray_normal(root.get_visible_rect().size * 0.5)
	_check(turned.displacement.z > 3 and absf(turned.displacement.x) < 0.02 and turned.pose.rig.z > 0.15 and game.diver_motion.motion_input.x < -0.9, "With a quarter-turn view, left swimming moves in the camera's local direction and keeps its local pose")
	_check(absf(game.yaw - PI / 2) < 0.001 and ray.x < -0.9 and absf(ray.z) < 0.02, "Directional animation does not rotate the aiming camera away from its existing heading")
	var wall := StaticBody3D.new()
	wall.position = CALM + Vector3(2, 0, 0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 8, 8)
	collision.shape = shape
	wall.add_child(collision)
	game.add_child(wall)
	await physics_frame
	var blocked: Dictionary = await _sample(["swim_right"], 45)
	_check(blocked.collisions > 0 and game.player.position.x < wall.position.x - 0.60 and blocked.displacement.x < 1.3, "The unchanged diver physics body still stops at solid scenery while a side stroke is active")
	_check(blocked.pose.rig.z < -0.15 and blocked.pose.leg_left.y < -0.10, "An obstructed active control retains its swimming intent without moving through the wall")
	wall.free()
	await physics_frame

func _test_pause_and_gm_freeze() -> void:
	await _sample(["swim_back", "swim_left"])
	game.toggle_pause()
	var paused_pose: Dictionary = _joint_transforms(rig)
	var phase_before: float = game.diver_motion.phase
	var input_before: Vector3 = game.diver_motion.motion_input
	var position_before: Vector3 = game.player.position
	await _advance_frames(20)
	_check(game.state == "paused" and _joint_transforms(rig) == paused_pose and game.diver_motion.phase == phase_before and game.diver_motion.motion_input == input_before and game.player.position == position_before, "Pause freezes the entire real rig, animation phase and body position")
	game.toggle_pause()
	game.open_gm_menu()
	var gm_pose: Dictionary = _joint_transforms(rig)
	Input.action_press("swim_right")
	await _advance_frames(20)
	_release_actions()
	_check(game.gm_menu_open and game.state == "paused" and _joint_transforms(rig) == gm_pose and game.diver_motion.phase == phase_before and game.player.position == position_before, "The GM menu freezes every real rig joint despite held movement controls")
	game.close_gm_menu()

func _test_current_idle() -> void:
	var point := Vector3(Ocean.canyon_center_x(-250), -50, -250)
	var drifting: Dictionary = await _sample([], 30, point)
	_check(drifting.displacement.z > 0.25 and game.drift_current.z > 0.75 and game.diver_motion.motion_input.length() < 0.001, "The actual current moves an idle diver without inventing reverse control input")
	_check(absf(drifting.pose.rig.x) < 0.02 and absf(drifting.pose.rig.z) < 0.02 and absf(drifting.pose.leg_left.y) < 0.02 and absf(drifting.pose.leg_right.y) < 0.02, "Passive drift keeps the idle body and fins instead of triggering reverse-swim poses")

func _test_lifecycle_resets() -> void:
	await _sample(["swim_back", "swim_left"])
	game.state = "dock"
	game.start_dive(true, false)
	_check(_is_reset() and game.entry_active, "Beginning boat entry clears the previous swimming pose and stroke phase")
	await _advance_frames(12)
	_check(_is_reset() and game.entry_active, "The boat-entry animation does not advance old directional joint motion")
	game._update_entry(3.2)
	await _sample(["swim_left"])
	game.open_gm_menu()
	game.gm_select_dive_site(game.Ocean.site_index("amber_reef"), true)
	_check(_is_reset() and not game.entry_active and game.state == "dive", "GM transfer clears the old motion before showing the new dive location")
	await _sample(["swim_back", "swim_right"])
	game.state = "dock"
	game.start_dive(false, false)
	_check(_is_reset() and game.player.position == Vector3(0, -6, 14), "A fresh dive begins at its original spawn with no stale directional pose")

func _sample(actions: Array, frames: int = 30, start: Vector3 = CALM, heading: float = 0) -> Dictionary:
	_release_actions()
	game.set_physics_process(false)
	game.state = "dive"
	game.entry_active = false
	game.player.position = start
	game.player.velocity = Vector3.ZERO
	game.player.rotation = Vector3(0, heading, 0)
	game.yaw = heading
	game.pitch = -0.12
	game.oxygen = 100
	game.hurt_cooldown = 0
	game.poison_timer = 0
	game.shot_cooldown = 0
	game._clear_projectiles()
	game.diver_motion.reset()
	for action in actions:
		Input.action_press(action)
	var clock_before: float = game.clock
	var result: Dictionary = await _advance_frames(frames)
	result.displacement = game.player.position - start
	result.elapsed = game.clock - clock_before
	result.pose = _pose()
	result.yaw = game.yaw
	_release_actions()
	return result

func _advance_frames(count: int) -> Dictionary:
	await process_frame
	game.set_physics_process(true)
	await physics_frame
	var collisions: int = 0
	var bounded: bool = true
	for frame in range(count):
		await physics_frame
		collisions += game.player.get_slide_collision_count()
		for joint: Node3D in [rig] + joints.values():
			var angle: Vector3 = joint.rotation
			bounded = bounded and angle.is_finite() and joint.position.is_finite() and absf(angle.x) < 1.35 and absf(angle.y) < 1.35 and absf(angle.z) < 1.35
	game.set_physics_process(false)
	return {"collisions":collisions, "bounded":bounded}

func _pose() -> Dictionary:
	var pose: Dictionary = {"rig":rig.rotation}
	for label in joints:
		pose[label] = joints[label].rotation
	return pose

func _joint_transforms(node: Node) -> Dictionary:
	var transforms: Dictionary = {}
	if node is Node3D:
		transforms[str(node.get_path())] = node.transform
	for child in node.get_children():
		transforms.merge(_joint_transforms(child))
	return transforms

func _is_reset() -> bool:
	return game.diver_motion.motion_input.is_zero_approx() and absf(game.diver_motion.phase) < 0.001 and _joint_transforms(rig) == neutral_pose

func _launch_direction() -> Vector3:
	game.shoot()
	var direction: Vector3 = game.projectiles[0].velocity.normalized() if not game.projectiles.is_empty() else Vector3.ZERO
	game._clear_projectiles()
	return direction

func _release_actions() -> void:
	for action in ACTIONS:
		Input.action_release(action)
