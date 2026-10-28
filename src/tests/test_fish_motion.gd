extends SceneTree
## Visual joints follow real behaviour without moving the hunting frame or durable state.
const Brain = preload("res://scripts/fish_brain.gd")
const Art = preload("res://scripts/fish_art.gd")
const FishData = preload("res://scripts/fish_catalog.gd")
const Storm = preload("res://scripts/storm_school.gd")
const Ocean = preload("res://scripts/ocean_config.gd")
const StonefishHabitat = preload("res://scripts/stonefish_habitat.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	var saves := 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var checks := 0
var failures := 0
var game: Node
var memory: MemoryProgression

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+description)

func _run() -> void:
	_test_rigs_and_hunting_frame()
	_test_stroke_wrap_continuity()
	await _test_storm_direction()
	game = load("res://scenes/main.tscn").instantiate()
	memory = MemoryProgression.new()
	memory.persistence_enabled = false
	game.progress = memory
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	game.start_dive(false,false)
	_test_real_swimming()
	_test_turn_and_continuity()
	_test_attack_poses()
	_test_animated_aim()
	_test_emergent_bank_avoidance()
	_check(memory.saves == 0,"Animation and storm inspection never write durable progress")
	_test_lifecycle()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver fish swimming and attack motion (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func _tail(item: Dictionary) -> Node3D:
	return item.node.get_node("Motion/Tail" if item.kind == 7 else "Motion/BodyFlex/Tail")

func _test_rigs_and_hunting_frame() -> void:
	for kind in range(9):
		var node: Node3D = Art.build(kind)
		var item: Dictionary = {"node":node,"kind":kind,"phase":0.2,"state":"charge","direction":Vector3.FORWARD,"hp":FishData.SPECIES[kind].hp}
		var before: Transform3D = node.transform
		Brain._animate_pose(item,0.1,float(FishData.SPECIES[kind].speed),Vector3.LEFT)
		_check(node.transform == before and item.hp == FishData.SPECIES[kind].hp and item.direction == Vector3.FORWARD and node.find_children("*","CollisionObject3D",true,false).is_empty(),"Articulated animation leaves the canonical hunting frame, health and collision unchanged: "+FishData.SPECIES[kind].id)
		_check(node.get_node("Motion").transform != Transform3D.IDENTITY and _tail(item) != null,"A real body rig and animated tail exist: "+FishData.SPECIES[kind].id)
		node.free()
	var grounded: Node3D = Art.build(9)
	_check(grounded.get_node_or_null("Motion") == null and grounded.get_node_or_null("Spines") != null and grounded.get_meta("harpoon_center") == Vector3(0,0.25,0),"Bottom-dwelling stonefish retain their grounded camouflage rig and precise targeting center")
	grounded.free()

func _test_storm_direction() -> void:
	var storm := Storm.new()
	storm.position = Storm.CENTER
	root.add_child(storm)
	await process_frame
	var batch: MultiMesh = storm.school.multimesh
	var min_dot := 1.0
	var constant_speed := true
	for time: float in [0.0,0.125,1.0,12.5,60.0]:
		storm.animate(time,Storm.CENTER)
		var before: Transform3D = storm.global_transform
		storm.animate(time+0.01,Storm.CENTER)
		var after: Transform3D = storm.global_transform
		for index in range(batch.instance_count):
			var local: Transform3D = batch.get_instance_transform(index)
			var movement: Vector3 = after*local.origin-before*local.origin
			var nose: Vector3 = -(before.basis*local.basis.z).normalized()
			min_dot = minf(min_dot,nose.dot(movement.normalized()))
			var radius: float = Vector2(local.origin.x,local.origin.z).length()
			constant_speed = constant_speed and absf(movement.length()/0.01-radius*0.24) < 0.01
	_check(batch.instance_count == 420 and storm.get_child_count() == 1 and min_dot > 0.999,"Every actual batched jackfish points along its world movement throughout the vortex orbit")
	_check(constant_speed,"Corrected storm facing preserves its original angular speed and circular tracks")
	storm.animate(0.5,Storm.CENTER)
	_check(is_equal_approx(storm.rotation.y,-0.12),"The jackfish vortex reverses its actual orbital rotation, keeping the original initial fish orientation")
	storm.free()

func _test_stroke_wrap_continuity() -> void:
	for boundary: float in [TAU,20.0*TAU]:
		var node: Node3D = Art.build(8)
		var item: Dictionary = {"node":node,"kind":8,"phase":0.0,"motion_phase":boundary-0.02,"state":"recover","direction":Vector3.FORWARD,"motion_recover":1.0}
		Brain._animate_pose(item,0.00001,4.8,Vector3.FORWARD)
		var fin: Node3D = node.get_node("Motion/BodyFlex/PectoralRight")
		var before: float = fin.rotation.z
		Brain._animate_pose(item,1.0/120.0,4.8,Vector3.FORWARD)
		_check(absf(fin.rotation.z-before) < 0.01,"Pectoral strokes stay continuous across phase boundary %.3f" % boundary)
		node.free()

func _disable_fish() -> void:
	for item: Dictionary in game.fish:
		item.alive = false
		item.node.visible = false

func _fixture(kind: int, point: Vector3) -> Dictionary:
	for item: Dictionary in game.fish:
		if item.kind != kind:
			continue
		item.alive = true
		item.node.visible = true
		item.node.transform = Transform3D(Basis.IDENTITY,point)
		item.home = point
		item.previous_position = point
		item.phase = 0.0
		item.state = "patrol"
		item.timer = 0.0
		item.attack_cooldown = 0.0
		item.alerted = false
		item.armor = false
		item.direction = Vector3.FORWARD
		item.hp = FishData.SPECIES[kind].hp
		for key: String in ["motion_activity","motion_phase","motion_bank","motion_windup","motion_charge","motion_recover"]:
			item.erase(key)
		return item
	_check(false,"Actual fish population contains kind %d" % kind)
	return {}

func _test_real_swimming() -> void:
	_disable_fish()
	game.player.position = Vector3(200,-12,250)
	var cadences: Dictionary = {}
	for kind in range(9):
		var item: Dictionary = _fixture(kind,Vector3(200,-12,200))
		item.state = "flee"
		item.timer = 10.0
		var start: Vector3 = item.node.position
		var first_tail := 0.0
		var changed_tail := false
		var changed_fin := false
		var last_fin := 0.0
		var phase_distance := 0.0
		var last_phase := 0.0
		for frame in range(45):
			game.clock += 1.0/60.0
			Brain.advance(game,item,1.0/60.0)
			phase_distance += wrapf(float(item.motion_phase)-last_phase,-PI,PI)
			last_phase = item.motion_phase
			if frame == 0:
				first_tail = _tail(item).rotation.y
			else:
				changed_tail = changed_tail or absf(_tail(item).rotation.y-first_tail) > 0.08
			if kind != 7:
				var fin: Node3D = item.node.get_node("Motion/BodyFlex/PectoralLeft")
				changed_fin = changed_fin or (frame > 0 and absf(fin.rotation.z-last_fin) > 0.001)
				last_fin = fin.rotation.z
		var expected: float = float(FishData.SPECIES[kind].speed)*1.65*0.75
		_check(absf(item.node.position.distance_to(start)-expected) < 0.003 and -item.node.basis.z.dot(item.direction) > 0.999,"Real fleeing displacement and nose direction retain the species speed: "+FishData.SPECIES[kind].id)
		_check(changed_tail and (changed_fin or kind == 7),"Live simulation drives continuous tail and pectoral strokes: "+FishData.SPECIES[kind].id)
		cadences[kind] = phase_distance
		item.alive = false
	_check(cadences[3] > cadences[2]+1.0 and cadences[6] > cadences[5]+1.0,"Fast sardines and tuna use visibly faster stroke cadences than lanternfish and lionfish")

func _test_turn_and_continuity() -> void:
	_disable_fish()
	game.player.position = Vector3(200,-12,250)
	var item: Dictionary = _fixture(1,Vector3(200,-12,200))
	item.phase = PI/2.0
	game.clock = 0.0
	Brain.advance(game,item,0.1)
	var rig: Node3D = item.node.get_node("Motion")
	_check(absf(rig.rotation.z) > 0.05 and absf(rig.rotation.z) < 0.4 and absf(item.node.rotation.z) < 0.001,"Turning banks the visual body while the root keeps its original upright hunting basis")
	var tail_before: float = _tail(item).rotation.y
	game.clock = 1234.0
	item.state = "flee"
	item.timer = 5.0
	Brain.advance(game,item,1.0/120.0)
	_check(absf(_tail(item).rotation.y-tail_before) < 0.06,"Changing to escape speed preserves tail phase even at a large world-clock value")
	item.alive = false

func _test_attack_poses() -> void:
	for kind: int in [7,8]:
		_disable_fish()
		game.player.position = Vector3(200,-12,200)
		game.oxygen = 100.0
		game.hurt_cooldown = 0.0
		var item: Dictionary = _fixture(kind,game.player.position+Vector3(0,0,-8))
		Brain.advance(game,item,0.1)
		var rig: Node3D = item.node.get_node("Motion")
		var jaw: Node3D = rig.get_node("Jaw")
		_check(item.state == "windup" and item.timer == 1.15 and rig.position.z > 0.0 and jaw.rotation.x < -0.04 and game.oxygen == 100.0,"Attack anticipation draws back and opens the jaw during the unchanged warning window: "+FishData.SPECIES[kind].id)
		for frame in range(60):
			Brain.advance(game,item,1.0/60.0)
		var windup_jaw: float = jaw.rotation.x
		item.timer = 0.01
		Brain.advance(game,item,0.02)
		var committed: Vector3 = item.direction
		for frame in range(12):
			Brain.advance(game,item,1.0/60.0)
		var charge_jaw: float = jaw.rotation.x
		_check(item.state == "charge" and rig.position.z < 0.0 and charge_jaw < windup_jaw-0.20 and item.direction == committed,"The actual lunge streams forward with a wider jaw while retaining its committed attack direction: "+FishData.SPECIES[kind].id)
		game.player.position = item.node.position+Vector3(0.2,0,0)
		Brain.advance(game,item,0.01)
		var damage: float = 12.0 if kind == 7 else 18.0
		_check(game.oxygen == 100.0-damage and item.state == "recover" and item.timer == 3.5 and item.attack_cooldown == 5.0,"Animated attack still applies one canonical contact hit and the original recovery/cooldown: "+FishData.SPECIES[kind].id)
		game.player.position = Vector3(200,-12,250)
		for frame in range(45):
			Brain.advance(game,item,1.0/60.0)
		_check(item.state == "recover" and jaw.rotation.x > charge_jaw+0.15 and game.oxygen == 100.0-damage,"Recovery settles the attack pose and closes its jaw without repeated damage: "+FishData.SPECIES[kind].id)

func _test_lifecycle() -> void:
	var item: Dictionary = game.fish[0]
	for candidate: Dictionary in game.fish:
		if candidate.alive and candidate.kind == 8:
			item = candidate
	var pose_before: Array = []
	for joint: Node3D in item.node.find_children("*","Node3D",true,false):
		pose_before.append(joint.transform)
	var root_before: Transform3D = item.node.transform
	var timer_before: float = item.timer
	var phase_before: float = item.motion_phase
	game.toggle_pause()
	game._physics_process(2.0)
	var pose_after: Array = []
	for joint: Node3D in item.node.find_children("*","Node3D",true,false):
		pose_after.append(joint.transform)
	_check(game.state == "paused" and pose_before == pose_after and item.node.transform == root_before and item.timer == timer_before and item.motion_phase == phase_before,"Pause freezes all swimming/attack joints, body motion and behaviour timers together")
	game.toggle_pause()
	item.alive = false
	Brain.advance(game,item,1.0)
	_check(item.motion_phase == phase_before and item.node.transform == root_before,"A captured fish cannot continue advancing its live rig")
	game.finish_dive(false)
	game.start_dive(false,false)
	var clean: bool = game.fish.size() == 167 and FishData.SPECIES.size() == 10
	for fish: Dictionary in game.fish:
		clean = clean and fish.alive and not fish.has("motion_phase") and fish.hp == FishData.SPECIES[fish.kind].hp
	_check(clean,"A new dive creates clean animation state while preserving all 167 catches and ten canonical species")

func _test_animated_aim() -> void:
	for kind: int in [7,8]:
		var all_hits := true
		for state: String in ["windup","charge","recover"]:
			_disable_fish()
			game.player.position = Vector3(200,-12,200)
			var item: Dictionary = _fixture(kind,game.player.position+Vector3(0,0,-12))
			item.state = state
			item.direction = Vector3.BACK
			item.node.look_at(game.player.position)
			var root_before: Transform3D = item.node.transform
			for frame in range(60):
				Brain._animate_pose(item,1.0/60.0,14.0 if state == "charge" else 0.1,Vector3.BACK)
			var torso: Node3D = item.node.get_node("Motion/Head" if kind == 7 else "Motion/BodyFlex/Body")
			game.camera.position = game.player.position+Vector3(0,0,7.5)
			game.camera.look_at(torso.global_position)
			game.shot_cooldown = 0.0
			game.yaw = 0.0
			all_hits = all_hits and game.target_fish() == item and item.node.transform == root_before
			var hp_before: int = item.hp
			game.shoot()
			for frame in range(50):
				game._update_projectiles(0.02)
			all_hits = all_hits and item.hp == hp_before-1
		_check(all_hits,"Aiming at the visible animated torso acquires and physically hits all three attack poses: "+FishData.SPECIES[kind].id)

func _test_emergent_bank_avoidance() -> void:
	_disable_fish()
	var z: float = Ocean.CANYON_CENTER.z
	var center: float = Ocean.canyon_center_x(z)
	var start := Vector3(center+20,-40,z)
	var beyond := Vector3(center+66,-40,z)
	_check(Ocean.seabed_height(center+43,z) > 0 and not Brain._wet_path(start,beyond,1.3),"A long crossing with underwater endpoints rejects the solid island ridge between them")
	game.player.position = Vector3(center,-40,z)
	var shark: Dictionary = _fixture(8,start)
	shark.state = "charge"
	shark.timer = 5.0
	shark.direction = Vector3.RIGHT
	Brain.advance(game,shark,3.0)
	_check(shark.node.position == start and shark.state == "recover" and shark.timer == 3.5,"A real long shark charge stops and recovers before crossing an emergent canyon bank")
	var shoreline := NAN
	for step in range(40,100):
		var x: float = center+float(step)*0.5
		if Ocean.seabed_height(x,z)+3.0 <= -5.0 and Ocean.seabed_height(x+2.8,z)+3.0 > -5.0:
			shoreline = x
			break
	_check(is_finite(shoreline),"The actual canyon contains a transition from swimmable water to dry island terrain")
	if is_finite(shoreline):
		shark.node.position = Vector3(shoreline,-5,z)
		shark.home = shark.node.position
		shark.state = "charge"
		shark.timer = 5.0
		shark.direction = Vector3.RIGHT
		var prior: Vector3 = shark.node.position
		Brain.advance(game,shark,0.2)
		_check(shark.node.position == prior and shark.node.position.y <= -5 and shark.state == "recover","A near-surface attack cannot invert height clamps and jump onto dry ground")
	var body := CylinderShape3D.new()
	body.radius = 1.05
	body.height = 0.54
	_check(not StonefishHabitat._safe_home(game,Vector3(center+43,Ocean.seabed_height(center+43,z)+0.035,z),body),"The rock-edge habitat rejects an above-water stonefish candidate")
	var all_submerged := true
	for fish: Dictionary in game.fish:
		if fish.kind == 9:
			all_submerged = all_submerged and fish.home.y <= -2.0
	_check(all_submerged,"All actual grounded stonefish remain completely underwater after island construction")
