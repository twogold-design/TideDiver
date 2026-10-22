extends SceneTree
## Real layout workflow with player persistence replaced before scene startup.
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
var purchased_uid: int = -1
func _init() -> void:
	call_deferred("_run")
func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
func _snapshot() -> String:
	return JSON.stringify(progress._save_data())
func _key(code: Key, ctrl: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	game._unhandled_input(event)
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
	game.smoke_mode = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	_test_entry_and_cancel()
	_test_commit_and_undo()
	_test_mouse_layout()
	_test_tables_and_guests()
	_test_default_reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver free layout flow (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
func _test_entry_and_cancel() -> void:
	game.open_restaurant()
	game.enter_layout()
	_check(not game.layout_mode, "Unclean old shop rejects layout entry")
	progress.coins = 800
	game.renovate_shop("clean")
	game.renovate_shop("kitchen")
	game.renovate_shop("tables")
	progress.inventory.orange = 3
	progress.furniture_items()
	var before := _snapshot()
	var saves_before: int = progress.saves
	game.enter_layout()
	_check(game.layout_mode and game.layout_work != progress and not game.layout_work.persistence_enabled, "Layout creates an isolated nonpersistent draft")
	game.buy_layout_furniture("lamp")
	var uid: int = game.layout_selected
	_check(uid >= 100 and game.layout_placing and game.layout_work.coins == progress.coins - 40, "Furniture purchase belongs to draft and begins placement")
	_check(game.place_layout_at(5.42,4.4), "Valid lamp placement succeeds")
	var lamp: Dictionary = game.layout_work.furniture_by_uid(uid)
	_check(lamp.x == 5.5 and lamp.z == 4.5, "Main placement uses half-unit snapping")
	game.color_selected_furniture()
	game.set_layout_style("floor",2)
	game.set_layout_style("wall",1)
	game.sell_goods("orange",1)
	game.renovate_shop("sign")
	game.change_menu("orange",1)
	game.start_service()
	game.start_dive()
	_check(_snapshot() == before and progress.saves == saves_before and game.state == "restaurant", "Draft changes and blocked management actions leave player state and saves untouched")
	game.cancel_layout()
	_check(not game.layout_mode and game.layout_work == null and _snapshot() == before, "Cancel discards furniture, cost, styles and every draft mutation")
	_check(game.restaurant_node._placed_tables.size() == 2, "Cancel rebuilds original actual 3D tables")
func _test_commit_and_undo() -> void:
	var money_before: int = progress.coins
	var saves_before: int = progress.saves
	game.enter_layout()
	game.buy_layout_furniture("lamp")
	purchased_uid = game.layout_selected
	_check(game.place_layout_at(5.5,4.5), "Purchased lamp can be placed again after cancelling previous draft")
	game.color_selected_furniture()
	game.set_layout_style("floor",2)
	game.set_layout_style("wall",1)
	game.select_furniture(1)
	game.begin_move_furniture()
	var original: Dictionary = game.layout_work.furniture_by_uid(1).duplicate(true)
	_check(not game.place_layout_at(0,1) and not game.layout_reason.is_empty(), "Main blocks placement in central entrance and explains why")
	_check(game.layout_work.furniture_by_uid(1) == original, "Rejected move keeps original table transform")
	_key(KEY_R)
	_check(game.layout_rotation == 1 and game.layout_work.furniture_by_uid(1).rotation == 0, "Rotating a pending move changes preview without committing original table")
	_check(game.place_layout_at(-3.5,2.5), "Moved and rotated table is accepted at a legal position")
	_check(progress.furniture_by_uid(1).z == -0.5 and progress.coins == money_before, "Draft table movement and shopping do not touch true layout or coins")
	game.save_layout()
	_check(not game.layout_mode and progress.coins == money_before - 40 and progress.saves == saves_before + 1, "Save commits furniture cost and one persistence event exactly once")
	_check(progress.floor_style == 2 and progress.wall_style == 1 and progress.furniture_by_uid(purchased_uid).color == 1, "Saved styles and furniture color survive draft transfer")
	_check(progress.furniture_by_uid(1).z == 2.5 and progress.furniture_by_uid(1).rotation == 1, "Saved actual table transform matches edited layout")
	game.save_layout()
	_check(progress.coins == money_before - 40 and progress.saves == saves_before + 1, "Repeated save outside edit does not charge or persist twice")
	var committed := _snapshot()
	game.enter_layout()
	game.select_furniture(purchased_uid)
	_key(KEY_DELETE)
	_check(not game.layout_work.furniture_by_uid(purchased_uid).placed and progress.furniture_by_uid(purchased_uid).placed, "Delete stores only draft furniture")
	_key(KEY_Z,true)
	_check(game.layout_work.furniture_by_uid(purchased_uid).placed, "Ctrl+Z restores last storage operation")
	game.begin_move_furniture()
	_key(KEY_ESCAPE)
	_check(game.layout_mode and not game.layout_placing, "First Escape cancels pending placement while retaining draft")
	_key(KEY_ESCAPE)
	_check(not game.layout_mode and progress.furniture_by_uid(purchased_uid).placed, "Second Escape discards draft and exits editor")
	_check(_snapshot() == committed, "Cancelling a later draft does not undo a previously saved purchase or layout")
func _test_tables_and_guests() -> void:
	game.enter_layout()
	for uid in [1,2]:
		game.select_furniture(uid)
		game.store_selected_furniture()
	game.save_layout()
	_check(progress.seats() == 0 and game.restaurant_node._placed_tables.is_empty(), "Storing both tables removes real service seats and visible tables")
	game.change_menu("orange",1)
	game.start_service()
	_check(game.state == "restaurant" and not game.service_block_reason().is_empty(), "Zero-table restaurant cannot open despite having food and renovations")
	game.enter_layout()
	game.select_furniture(1)
	_check(game.layout_placing, "Selecting stored table begins placement without a second purchase")
	_check(game.place_layout_at(-3.5,2.5), "Stored table can be returned to its customized location")
	game.save_layout()
	_check(progress.seats() == 1 and progress.can_open(), "One placed table is sufficient for opening")
	game.start_service()
	_check(game.state == "service", "Main service starts with a single custom table")
	game._spawn_customer()
	game._spawn_customer()
	_check(game.orders.size() == 1 and game.restaurant_node._customers.size() == 1, "Single actual table limits simultaneous orders and 3D customers")
	var order: Dictionary = game.orders[0]
	var person: Node3D = game.restaurant_node._customers[order.id]
	var table: Dictionary = progress.placed_tables()[0]
	var angle: float = float(table.rotation) * PI / 2.0
	var expected := Vector3(table.x,0,table.z) + Vector3(0,0,1.4).rotated(Vector3.UP,angle)
	_check(person.position.is_equal_approx(expected) and is_equal_approx(person.rotation.y,angle), "Actual guest follows customized table position and ninety-degree rotation")
	game.enter_layout()
	_check(not game.layout_mode and game.state == "service", "Restaurant service blocks layout editing")
	game.finish_service()
	game.summary_visible = false
	game.hud.rebuild()
func _test_default_reset() -> void:
	var before := _snapshot()
	game.enter_layout()
	game.reset_layout_draft()
	_check(game.layout_work.seats() == 2 and not game.layout_work.furniture_by_uid(purchased_uid).placed, "Reset returns owned gift tables and stores extra purchased lamp")
	_check(game.layout_work.coins == progress.coins and game.layout_work.furniture_items().size() == progress.furniture_items().size(), "Reset neither buys, refunds nor destroys furniture ownership")
	_check(game.layout_work.floor_style == 2 and game.layout_work.wall_style == 1 and game.layout_work.furniture_by_uid(purchased_uid).color == 1, "Reset keeps selected room styles and furniture color")
	game.undo_layout()
	_check(game.layout_work.seats() == 1 and game.layout_work.furniture_by_uid(purchased_uid).placed, "Reset can be undone back to personalized draft")
	game.cancel_layout()
	_check(_snapshot() == before, "Cancelling after reset and undo leaves player progression byte-equivalent")
func _mouse_click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	game._layout_input(event)
func _project_floor(x: float, z: float) -> Vector2:
	return game.camera.unproject_position(game.restaurant_node.to_global(Vector3(x,0.08,z)))
func _test_mouse_layout() -> void:
	var before := _snapshot()
	game.enter_layout()
	game._physics_process(0.0)
	_check(game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Editing switches real camera to orthographic layout view")
	game.buy_layout_furniture("rug")
	var rug_uid: int = game.layout_selected
	var point := _project_floor(-3.5,2.5)
	_check(game.LAYOUT_AREA.has_point(point), "Projected test floor position lies within actual editable viewport")
	var returned: Variant = game._layout_point(point)
	_check(returned is Vector3 and returned.is_equal_approx(Vector3(-3.5,0.08,2.5)), "Camera projection and floor ray restore the intended snapped coordinates")
	var draft_before_panel := JSON.stringify(game.layout_work._save_data())
	_mouse_click(Vector2(100,300))
	_check(game.layout_placing and JSON.stringify(game.layout_work._save_data()) == draft_before_panel, "Clicking sidebar coordinates cannot place or change selected furniture")
	_mouse_click(point)
	_check(not game.layout_placing and game.layout_work.furniture_by_uid(rug_uid).placed, "Screen-coordinate mouse click places rug under actual table")
	_mouse_click(point)
	_check(game.layout_selected == 1, "Clicking overlapped rug and table prioritizes solid table selection")
	_key(KEY_G)
	_check(game.layout_placing, "G key begins moving the mouse-selected table")
	var moved_point := _project_floor(-3.5,1.5)
	_mouse_click(moved_point)
	_check(not game.layout_placing and game.layout_work.furniture_by_uid(1).z == 1.5, "Projected mouse placement moves selected table to intended floor cell")
	_check(progress.furniture_by_uid(1).z == 2.5, "Mouse movement still affects only draft geometry")
	game.cancel_layout()
	_check(_snapshot() == before and progress.furniture_by_uid(rug_uid).is_empty(), "Cancelling mouse placement discards rug purchase and restores committed geometry")
