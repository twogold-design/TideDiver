extends SceneTree
## Real living-world integration with memory progress and a separate tests/temp fixture.
const P = preload("res://scripts/progression.gd")
const Ocean = preload("res://scripts/ocean_config.gd")
const TEST_PATH := "res://tests/temp/living_world.json"
class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1
var game: Node
var progress: MemoryProgression
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
	progress = MemoryProgression.new()
	progress.persistence_enabled = false
	game.progress = progress
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	_test_outer_ocean()
	_test_service_feedback_and_animation()
	_test_feedback_persistence()
	_test_next_service_and_new_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver living world (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
func _inside_ocean(point: Vector3) -> bool:
	return point.x >= Ocean.X_MIN and point.x <= Ocean.X_MAX and point.z >= Ocean.Z_MIN and point.z <= Ocean.Z_MAX and point.y >= Ocean.Y_MIN and point.y <= Ocean.Y_MAX
func _test_outer_ocean() -> void:
	game.start_dive()
	_check(game.fish.size() == game.fish_population_count() and game.pickups.size() == 11 + Ocean.pickup_points().size() and game.hazards.size() == 7 + Ocean.ZONES.size(), "Expanded playable ocean contains complete fish, pickup and hazard populations")
	for zone in Ocean.ZONES:
		var center: Vector3 = zone.center
		var nearby_fish: int = 0
		var nearby_pickups: int = 0
		for item in game.fish:
			if Vector2(item.home.x-center.x,item.home.z-center.z).length() <= float(zone.radius) + 8.0:
				nearby_fish += 1
		for item in game.pickups:
			if Vector2(item.home.x-center.x,item.home.z-center.z).length() <= float(zone.radius) + 8.0:
				nearby_pickups += 1
		_check(center.length() > 75 and nearby_fish >= 10 and nearby_pickups >= 4, "Outer destination has actual populated fish and accessible resources: " + str(zone.name))
		_check(Ocean.zone_for_position(center).get("name","") == zone.name, "Destination labels resolve at their actual centers: " + str(zone.name))
	var all_inside: bool = true
	for item in game.fish + game.pickups + game.hazards:
		all_inside = all_inside and _inside_ocean(item.home)
	_check(all_inside, "Every authored or spawned resource and hazard begins within playable bounds")
	for point in [Vector3(Ocean.X_MIN+2,-5,Ocean.Z_MIN+2),Vector3(Ocean.X_MAX-2,-5,Ocean.Z_MIN+2),Vector3(Ocean.X_MIN+2,-5,Ocean.Z_MAX-2),Vector3(Ocean.X_MAX-2,-5,Ocean.Z_MAX-2)]:
		var collision := KinematicCollision3D.new()
		var blocked: bool = game.player.test_move(Transform3D(Basis.IDENTITY,point),Vector3(0,-180,0),collision)
		_check(blocked and collision.get_normal().y > 0.3 and absf(collision.get_position().y-Ocean.seabed_height(collision.get_position().x,collision.get_position().z)) < 0.1, "Actual solid seabed covers expanded remote corner " + str(point))
	for point in [Vector3(Ocean.X_MIN-3,-4,0),Vector3(Ocean.X_MAX+3,-4,0),Vector3(0,-4,Ocean.Z_MIN-3),Vector3(0,-4,Ocean.Z_MAX+3)]:
		game.player.position = point
		game._update_dive(0.0)
		_check(_inside_ocean(game.player.position), "Actual diver movement clamps to shared expanded boundary from " + str(point))
	var remote: Dictionary = {}
	for item in game.pickups:
		if item.kind == "pearl" and absf(item.home.x) > 80:
			remote = item
			break
	_check(not remote.is_empty(), "A pearl can be selected in an outer-ocean destination")
	if not remote.is_empty():
		game.player.position = remote.node.position
		game._update_dive(0.0)
		game.interact()
		_check(game.cargo.size() == 1 and not remote.active, "Player can actually collect a remote pearl inside the shared bounds")
	var old_position: Vector3 = game.player.position
	var fish_before: Vector3 = game.fish[-1].node.position
	var clock_before: float = game.clock
	game.toggle_pause()
	game._physics_process(6.0)
	_check(game.player.position == old_position and game.fish[-1].node.position == fish_before and game.clock == clock_before, "Dive pause freezes remote-world simulation and player")
	game.toggle_pause()
	game.finish_dive(false)
func _capture_transforms(node: Node, result: Dictionary, prefix: String = "") -> void:
	var path: String = prefix + "/" + str(node.name)
	if node is Node3D:
		result[path] = node.transform
	for child in node.get_children():
		_capture_transforms(child,result,path)
func _people_pose() -> Dictionary:
	var result: Dictionary = {}
	if is_instance_valid(game.restaurant_node._people):
		_capture_transforms(game.restaurant_node._people,result)
	if is_instance_valid(game.restaurant_node._chef):
		_capture_transforms(game.restaurant_node._chef,result)
	if is_instance_valid(game.restaurant_node._reaction_root):
		_capture_transforms(game.restaurant_node._reaction_root,result)
	return result
func _chef_pose() -> Dictionary:
	var result: Dictionary = {}
	_capture_transforms(game.restaurant_node._chef,result)
	return result
func _test_service_feedback_and_animation() -> void:
	for id in progress.RENOVATIONS:
		progress.renovation[id] = true
	progress.inventory.orange = 5
	game.open_restaurant()
	game.change_menu("orange",4)
	game.start_service()
	game.service_spawn_time = 999.0
	for index in range(4):
		game._spawn_customer()
	_check(game.orders.size() == 4 and game.restaurant_node._customers.size() == 4, "Four live orders create four animated customers")
	var initial: Dictionary = game.orders[0]
	_check(initial.max_patience == progress.patience() and initial.patience == initial.max_patience, "Each order keeps initial patience for consistent mood thresholds")
	var idle_chef := _chef_pose()
	_check(game.restaurant_node._chef.state == "idle", "Chef stays idle while orders are waiting for player cooking input")
	var guest_before: Dictionary = {}
	_capture_transforms(game.restaurant_node._customers[initial.id],guest_before)
	game.restaurant_node.animate(0.35)
	var guest_after: Dictionary = {}
	_capture_transforms(game.restaurant_node._customers[initial.id],guest_after)
	_check(guest_after != guest_before, "Real customer skeletons visibly animate rather than remaining rigid")
	_check(_chef_pose() != idle_chef, "Idle chef has real breathing and preparation movement")
	var pose_before := _people_pose()
	game.cook_order(initial.id)
	game.restaurant_node.animate(0.2)
	var cooking_chef := _chef_pose()
	_check(game.restaurant_node._chef.state == "cooking" and cooking_chef != idle_chef, "Actual cooking order drives chef cutting and stirring pose")
	var cook_before: float = initial.cook_left
	var patience_before: float = initial.patience
	pose_before = _people_pose()
	var feedback_before: Array = game.service_feedback.duplicate(true)
	game.toggle_pause()
	game._physics_process(5.0)
	_check(initial.cook_left == cook_before and initial.patience == patience_before and _people_pose() == pose_before and game.service_feedback == feedback_before, "Service pause freezes cooking, patience, character poses and feedback")
	game.toggle_pause()
	var quick_id: int = initial.id
	game._update_service(3.01)
	game.restaurant_node.animate(0.2)
	_check(game.restaurant_node._chef.state == "ready" and _chef_pose() != cooking_chef, "Recipe completion switches actual chef pose to ready for serving")
	var money_before: int = progress.coins
	game.serve_order(quick_id)
	_check(progress.coins == money_before + 46 and game.service_reviews.satisfied == 1, "Timely service earns exactly one normal tipped payment and one satisfied review")
	_check(game.service_feedback.size() == 1 and game.service_feedback[0].id == quick_id and game.service_feedback[0].mood == "satisfied" and not str(game.service_feedback[0].text).is_empty(), "Positive feedback identifies the actually served customer")
	_check(game.restaurant_node._reactions.size() == 1 and game.restaurant_node._reactions[0].identity == quick_id and game.restaurant_node._reactions[0].outcome == "satisfied", "Serving creates the matching real customer reaction actor")
	var reviews_before: Dictionary = game.service_reviews.duplicate(true)
	game.serve_order(quick_id)
	_check(progress.coins == money_before + 46 and game.service_reviews == reviews_before and game.service_feedback.size() == 1, "Repeated serving cannot duplicate either income or feedback")
	var slow: Dictionary = game.orders[0]
	game.cook_order(slow.id)
	game._update_service(3.01)
	slow.patience = slow.max_patience * 0.4
	var live: Dictionary = game.customer_mood(slow)
	_check(live.mood == "okay" and not str(live.text).is_empty(), "Live customer message reflects low remaining patience")
	game.serve_order(slow.id)
	_check(game.service_reviews.okay == 1 and game.service_feedback[0].id == slow.id and game.service_feedback[0].mood == "okay" and progress.coins == money_before + 92, "Slow but successful service yields an okay review without altering recipe payment")
	var abandoned: Dictionary = game.orders[0]
	abandoned.patience = 0.01
	game._update_service(0.02)
	_check(game.service_reviews.lost == 1 and game.service_feedback[0].id == abandoned.id and game.service_feedback[0].mood == "lost", "Actual timeout yields a matching lost-customer feedback event")
	_check(progress.coins == money_before + 92 and progress.total_lost == 1, "Timed-out order pays nothing and records a single loss")
	var pose_with_reactions := _people_pose()
	game.toggle_pause()
	game._physics_process(7.0)
	_check(_people_pose() == pose_with_reactions, "Pause also freezes leaving-customer reactions")
	game.finish_service()
	_check(game.service_reviews == {"satisfied":1,"okay":1,"lost":2} and game.service_feedback.size() == 3, "Early close records its unfinished guest while recent-feedback list stays capped at three")
	_check(game.service_summary.reviews == game.service_reviews and game.service_summary.served == 2 and game.service_summary.lost == 2, "Bill retains the actual satisfied, okay and lost outcomes")
	var complete_reviews: Dictionary = game.service_reviews.duplicate(true)
	game.finish_service()
	_check(game.service_reviews == complete_reviews and progress.coins == money_before + 92, "Duplicate closing cannot create extra reviews or money")
func _clear_fixture() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
func _test_feedback_persistence() -> void:
	_clear_fixture()
	var saved = P.new()
	saved.persistence_enabled = false
	saved._apply_save_data(progress._save_data().duplicate(true))
	saved.save_path = TEST_PATH
	saved.persistence_enabled = true
	saved.save_game()
	var loaded = P.new()
	loaded.save_path = TEST_PATH
	loaded.load_game()
	_check(loaded.last_service_result.get("reviews",{}) == {"satisfied":1,"okay":1,"lost":2}, "Completed review counts survive actual isolated JSON save and reload")
	_check(loaded.coins == progress.coins and loaded.total_served == 2 and loaded.total_lost == 2, "Review persistence does not duplicate restaurant income or statistics")
	_clear_fixture()
func _test_next_service_and_new_game() -> void:
	game.summary_visible = false
	game.return_to_dock()
	game.start_dive()
	game.finish_dive(false)
	progress.inventory.orange = 2
	game.open_restaurant()
	game.change_menu("orange",-999)
	game.change_menu("orange",2)
	game.start_service()
	_check(game.service_feedback.is_empty() and game.service_reviews == {"satisfied":0,"okay":0,"lost":0}, "Starting another service clears previous feedback and review counters")
	_check(game.restaurant_node._reactions.is_empty() and game.restaurant_node._reacting_ids.is_empty(), "New service clears prior departing-customer reaction actors")
	game._spawn_customer()
	game.finish_service()
	_check(game.service_reviews.lost == 1 and game.service_feedback.size() == 1, "Fresh service can produce its own feedback independently")
	game.summary_visible = false
	game.return_to_dock()
	game.request_new_game()
	game.confirm_new_game()
	_check(game.state == "dock" and progress.day == 1 and progress.coins == 0 and not progress.persistence_enabled, "New game resets only the isolated memory progress")
	_check(game.service_feedback.is_empty() and game.service_reviews == {"satisfied":0,"okay":0,"lost":0} and game.service_summary.is_empty(), "New game removes all last-run feedback, review counts and bill state")
	_check(game.orders.is_empty() and game.restaurant_node._customers.is_empty(), "New game removes all old customer orders and characters")
	_check(game.restaurant_node._reactions.is_empty() and game.restaurant_node._reacting_ids.is_empty(), "New game clears all reaction actors and their duplicate-suppression IDs")
	_check(game.fish.size() == game.fish_population_count() and game.pickups.size() == 11 + Ocean.pickup_points().size() and game.hazards.size() == 7 + Ocean.ZONES.size() and game.cargo.is_empty(), "New game repopulates the expanded ocean without old harvested state")

