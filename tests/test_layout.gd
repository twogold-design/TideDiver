extends SceneTree
const P = preload("res://scripts/progression.gd")
const Rules = preload("res://scripts/layout_rules.gd")
const TEST_PATH := "res://tests/temp/layout_v3.json"
var checks: int = 0
var failures: int = 0
func _init() -> void:
	_test_gifts_and_seating()
	_test_purchase_and_styles()
	_test_geometry()
	_test_service_lock()
	_test_sanitization_and_migration()
	_test_disk_roundtrip()
	print("%s: Tide Diver layout (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
func _new(full: bool = false) -> RefCounted:
	var p = P.new()
	p.persistence_enabled = false
	if full:
		for id in p.RENOVATIONS:
			p.renovation[id] = true
	return p
func _test_gifts_and_seating() -> void:
	var p = _new()
	_check(p.furniture_items().is_empty() and p.seats() == 0 and not p.can_open(), "Fresh shop has no furniture or seats")
	p.coins = 210
	p.renovate("clean")
	p.renovate("kitchen")
	p.renovate("tables")
	_check(p.coins == 0 and p.furniture_items().size() == 2 and p.seats() == 2 and p.can_open(), "Existing 210G opening route grants two placed tables")
	_check(p.furniture_by_uid(1).x == -3.5 and p.furniture_by_uid(1).z == -0.5 and p.furniture_by_uid(2).x == 3.5, "Gift tables use agreed default coordinates")
	p.furniture_items()
	_check(p.furniture_items().size() == 2, "Repeated gift synchronization does not duplicate items")
	_check(p.store_furniture(1) and p.seats() == 1 and p.can_open(), "One remaining table permits service")
	_check(p.store_furniture(2) and p.seats() == 0 and not p.can_open(), "Storing all tables disables opening")
	p.inventory.orange = 1
	_check(not p.begin_service({"orange":1}), "Restaurant cannot serve with zero placed tables")
	p.furniture_items()
	_check(not p.furniture_by_uid(1).placed and not p.furniture_by_uid(2).placed, "Gift synchronization respects deliberately stored furniture")
	p.reset_layout()
	_check(p.seats() == 2 and p.can_open(), "Reset restores existing gift tables for reopening")
	var direct = _new(true)
	_check(direct.seats() == 4 and direct.furniture_items().size() == 8, "Direct renovation flags lazily generate four tables and decor gifts")
	for item in direct.furniture_items():
		_check(Rules.validate(direct.furnishings,item.uid,item.x,item.z,item.rotation).is_empty(), "Every default gift fits the agreed room geometry")
func _test_purchase_and_styles() -> void:
	var p = _new()
	p.coins = 1000
	_check(p.buy_furniture("plant") == -1 and not p.set_room_style("floor",1), "Cleaning required before purchasing or styling")
	p.renovation.clean = true
	_check(p.buy_furniture("invalid") == -1 and p.coins == 1000, "Unknown furniture cannot consume money")
	var uid: int = p.buy_furniture("plant")
	_check(uid == 100 and p.coins == 975 and not p.furniture_by_uid(uid).placed, "Purchased furniture receives a unique ID and enters storage")
	_check(p.place_furniture(uid,-5.26,0.24,0) and p.furniture_by_uid(uid).x == -5.5 and p.furniture_by_uid(uid).z == 0.0, "Placement snaps to a half-meter grid")
	_check(p.coins == 975 and p.place_furniture(uid,-5.0,0.0,1) and p.coins == 975, "Placement and movement never charge again")
	_check(p.recolor_furniture(uid,2) and p.furniture_by_uid(uid).color == 2 and not p.recolor_furniture(uid,3), "Furniture color accepts only three variants")
	_check(p.set_room_style("floor",2) and p.set_room_style("wall",1) and p.floor_style == 2 and p.wall_style == 1, "Floor and wall styles are independent")
	_check(not p.set_room_style("ceiling",1) and not p.set_room_style("wall",-1), "Unknown surfaces and invalid styles rejected")
	p.coins = 0
	_check(p.buy_furniture("table") == -1, "Unaffordable furniture purchase fails atomically")
	var full = _new(true)
	full.coins = 100
	var extra: int = full.buy_furniture("table")
	_check(not full.place_furniture(extra,-3.5,-0.5,0), "Placed-table count respects expansion ceiling")
	full.store_furniture(1)
	_check(full.place_furniture(extra,-3.5,-0.5,0) and full.seats() == 4, "Purchased table can replace a stored gift table")
	full.recolor_furniture(1,2)
	full.set_room_style("floor",1)
	var count_before: int = full.furniture_items().size()
	full.reset_layout()
	_check(full.furniture_items().size() == count_before and not full.furniture_by_uid(extra).placed and full.furniture_by_uid(1).placed and full.coins == 30, "Reset stores extras without deleting furniture or charging")
	_check(full.furniture_by_uid(1).color == 2 and full.floor_style == 1, "Resetting layout preserves chosen colors and room style")
func _test_geometry() -> void:
	var p = _new(true)
	_check(not p.placement_reason(1,0,0,0).is_empty(), "Solid table cannot obstruct central entrance aisle")
	_check(not p.place_furniture(1,-6.0,0,0), "Footprint exceeding room edge is rejected")
	_check(not p.place_furniture(1,3.5,-0.5,0), "Solid furniture cannot overlap another solid")
	_check(p.place_furniture(1,-3.5,-0.5,1) and p.furniture_by_uid(1).rotation == 1, "Quarter-turn rotation swaps rectangular footprint")
	_check(Rules.footprint("table",1) == Vector2(3.8,2.5), "Rotated footprint uses catalog dimensions")
	_check(p.place_furniture(7,0,0,0), "Rug may span the central aisle")
	_check(not p.place_furniture(8,0.5,0,0), "Rugs cannot overlap each other")
	_check(p.place_furniture(7,-3.5,-0.5,0), "Rug may lie under solid furniture")
	_check(not p.place_furniture(5,NAN,0,0) and not p.place_furniture(5,0,INF,0) and not p.place_furniture(5,-5.5,1.5,4), "Nonfinite coordinates and invalid rotations fail")
	_check(not p.place_furniture(999,-5.5,0,0) and not p.store_furniture(999), "Unknown furniture IDs fail safely")
	p.store_furniture(1)
	_check(p.place_furniture(1,-3.5,-0.5,0), "First table clears lower room boundary")
	_check(p.place_furniture(3,-3.5,3.5,0), "Last table exactly touches the rear room boundary")
func _test_service_lock() -> void:
	var p = _new(true)
	p.inventory.orange = 1
	p.coins = 1000
	_check(p.begin_service({"orange":1}), "Service fixture opens with valid layout")
	var before: Array = p.furniture_items().duplicate(true)
	_check(p.buy_furniture("lamp") == -1 and not p.place_furniture(1,-3.5,-0.5,1) and not p.store_furniture(1), "Active service blocks purchase, movement and storage")
	_check(not p.recolor_furniture(1,2) and not p.set_room_style("floor",2), "Active service blocks color and room-style edits")
	p.reset_layout()
	_check(p.furniture_items() == before and p.coins == 1000, "Active service reset is a no-op")
	p.end_service()
	_check(p.store_furniture(1), "Layout editing resumes after service")
func _test_sanitization_and_migration() -> void:
	var p = _new()
	var flags: Dictionary = {"clean":true,"kitchen":true,"tables":true,"sign":true,"expansion":true,"decor":true}
	p._apply_save_data({"version":2,"coins":123,"day":7,"renovation":flags,"inventory":{"blue":3}})
	_check(p.coins == 123 and p.day == 7 and p.inventory.blue == 3 and p.furniture_items().size() == 8 and p.seats() == 4, "V2 migration preserves economy and generates default furniture")
	var legacy = _new()
	legacy._apply_save_data({"version":1,"coins":88,"tank_level":2})
	_check(legacy.coins == 88 and legacy.tank_level == 2 and legacy.furniture_items().is_empty(), "V1 migration keeps diving progress without inventing renovations")
	var raw: Array = [
		{"uid":1,"kind":"table","x":-3.5,"z":-0.5,"rotation":0,"color":2,"placed":false},
		{"uid":2,"kind":"table","x":0,"z":0,"rotation":0,"color":0,"placed":true},
		{"uid":100,"kind":"plant","x":-5.5,"z":0,"rotation":0,"color":1,"placed":true},
		{"uid":101,"kind":"lamp","x":-5.5,"z":0,"rotation":0,"color":9,"placed":true},
		{"uid":102,"kind":"shelf","x":1.0e300,"z":0,"rotation":99,"color":0,"placed":true},
		{"uid":103,"kind":"rug","x":NAN,"z":0,"rotation":0,"color":0,"placed":true},
		{"uid":100,"kind":"plant","x":3,"z":0,"rotation":0,"color":0,"placed":true},
		{"uid":104,"kind":"unknown","x":0,"z":0,"rotation":0,"color":0,"placed":true},
		{"uid":9,"kind":"table","x":-3,"z":0,"rotation":0,"color":0,"placed":true},
	]
	p._apply_save_data({"version":3,"renovation":flags,"furnishings":raw,"floor_style":99,"wall_style":-2,"next_furniture_uid":100})
	_check(not p.furniture_by_uid(1).placed and p.furniture_by_uid(1).color == 2, "V3 loading preserves deliberately stored gift and its color")
	_check(not p.furniture_by_uid(2).placed and not p.furniture_by_uid(101).placed, "Invalid aisle and overlapping placements become stored items")
	_check(not p.furniture_by_uid(102).placed and is_finite(p.furniture_by_uid(102).x) and not p.furniture_by_uid(103).placed, "Huge/nonfinite positions are sanitized into safe storage")
	_check(p.furniture_by_uid(104).is_empty() and p.furniture_by_uid(9).is_empty() and p.furniture_items().size() == 12, "Unknown kinds, reserved IDs and duplicate IDs are discarded")
	_check(p.floor_style == 2 and p.wall_style == 0 and p.next_furniture_uid >= 104, "Styles are bounded and next UID cannot collide")
	for item in p.placed_tables():
		_check(Rules.validate(p.furniture_items(),item.uid,item.x,item.z,item.rotation).is_empty(), "Sanitized placed tables satisfy geometry rules")
func _clear_fixture() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
func _test_disk_roundtrip() -> void:
	_clear_fixture()
	var p = _new(true)
	p.save_path = TEST_PATH
	p.persistence_enabled = true
	p.store_furniture(1)
	p.recolor_furniture(2,2)
	p.set_room_style("floor",1)
	p.set_room_style("wall",2)
	p.coins = 100
	var uid: int = p.buy_furniture("lamp")
	p.place_furniture(uid,-5.5,4.5,0)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	_check(saved.version == 3 and FileAccess.file_exists(TEST_PATH + ".bak"), "V3 layout data uses existing atomic-save and backup mechanism")
	var restored = P.new()
	restored.save_path = TEST_PATH
	restored.load_game()
	_check(restored.seats() == 3 and not restored.furniture_by_uid(1).placed and restored.furniture_by_uid(2).color == 2, "Disk restart preserves stored gifts and colors")
	_check(restored.floor_style == 1 and restored.wall_style == 2 and restored.furniture_by_uid(uid).placed and restored.coins == 60, "Disk restart preserves purchased furniture, placement, styles and purchase cost")
	_check(restored.next_furniture_uid > uid and restored.furniture_items().size() == 9, "Disk restart retains unique purchase identity without duplicating gifts")
	_clear_fixture()
