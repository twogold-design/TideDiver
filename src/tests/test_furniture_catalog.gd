extends SceneTree
## Variant pricing, legacy migration and expanded layout; fixtures stay in tests/temp.
const P = preload("res://scripts/progression.gd")
const Rules = preload("res://scripts/layout_rules.gd")
const Art = preload("res://scripts/furniture_art.gd")
const TEST_PATH := "res://tests/temp/furniture_catalog_v4.json"
const EXPECTED := {
	"table":[["旧木双人桌",70],["浅蓝藤椅圆桌",160],["柚木条纹餐桌",320]],
	"plant":[["陶盆海岸绿植",25],["木箱组合花草",65],["陶缸棕榈",130]],
	"rug":[["椰纤迎宾垫",30],["条纹户外地毯",90],["沙色海蓝地毯",180]],
	"lamp":[["船用提灯",40],["木杆悬挂渔灯",110],["双灯船桅庭院灯",220]],
	"shelf":[["木制碗碟架",55],["百叶门餐具柜",140],["冰鲜海产展示柜",280]],
	"bench":[["漂木长凳",60],["条纹坐垫长椅",125],["藤编沙发茶几",240]],
	"parasol":[["浅蓝帆布伞",85],["海蓝条纹大伞",165],["卷帘木架凉棚",290]],
	"coastal":[["今日鲜鱼黑板",35],["渔获木箱浮球",90],["小木船陈列台",210]],
}
var failures: int = 0
var checks: int = 0
func _init() -> void:
	_test_prices_and_purchase()
	_test_expanded_geometry()
	_test_legacy_and_invalid_variants()
	_test_disk_roundtrip()
	_test_model_bounds()
	print("%s: Tide Diver furniture catalog (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _mesh_bounds(node: Node3D, transform: Transform3D, result: Array) -> void:
	var local: Transform3D = transform * node.transform
	if node is MeshInstance3D:
		var box: AABB = local * (node as MeshInstance3D).get_aabb()
		result.append(box)
	for child: Node in node.get_children():
		if child is Node3D:
			_mesh_bounds(child, local, result)

func _test_model_bounds() -> void:
	# Replacing assets must not silently overlap neighbors in existing saved layouts.
	for kind: String in EXPECTED:
		for variant: String in ["basic", "comfort", "premium"]:
			var model: Node3D = Art.build({"uid":100, "kind":kind, "variant":variant, "color":0})
			var bounds: Array = []
			_mesh_bounds(model, Transform3D.IDENTITY, bounds)
			var valid: bool = not bounds.is_empty()
			var size: Vector2 = Rules.footprint(kind, 0)
			for box: AABB in bounds:
				valid = valid and box.position.x >= -size.x * 0.5 - 0.001 and box.end.x <= size.x * 0.5 + 0.001 and box.position.z >= -size.y * 0.5 - 0.001 and box.end.z <= size.y * 0.5 + 0.001
			_check(valid, "Actual harbor model stays within its saved placement footprint: " + kind + "/" + variant)
			model.free()
func _new() -> RefCounted:
	var p = P.new()
	p.persistence_enabled = false
	p.renovation.clean = true
	return p
func _test_prices_and_purchase() -> void:
	for kind in EXPECTED:
		_check(Rules.variant_ids(kind) == ["basic","comfort","premium"], "Each furniture category exposes all three tiers: " + kind)
		for index in range(3):
			var variant: String = ["basic","comfort","premium"][index]
			var name: String = EXPECTED[kind][index][0]
			var price: int = EXPECTED[kind][index][1]
			var data: Dictionary = Rules.variant_data(kind,variant)
			_check(data.name == name and data.cost == price and not data.description.is_empty(), "Specified name/price/description: " + kind + "/" + variant)
			var p = _new()
			p.coins = price - 1
			_check(p.buy_furniture(kind,variant) == -1 and p.coins == price - 1 and p.furniture_items().is_empty(), "Insufficient funds fail without mutation: " + kind + "/" + variant)
			p.coins = price
			var uid: int = p.buy_furniture(kind,variant)
			var item: Dictionary = p.furniture_by_uid(uid)
			_check(uid >= 100 and p.coins == 0 and item.kind == kind and item.variant == variant and not item.placed, "Purchase charges selected tier and stores exact identity: " + kind + "/" + variant)
			_check(Rules.item_name(item) == name and p.place_furniture(uid,-8.0,4.0,0) and p.coins == 0, "Variant label and free placement work: " + kind + "/" + variant)
	var p = _new()
	p.coins = 1000
	_check(p.buy_furniture("table","invalid") == -1 and p.buy_furniture("invalid","basic") == -1 and p.coins == 1000, "Invalid purchases never silently charge a different tier")
	var basic: int = p.buy_furniture("table")
	_check(p.furniture_by_uid(basic).variant == "basic" and p.coins == 930, "Existing single-argument purchase remains basic-compatible")
	_check(Rules.variant_data("table","invalid").name == "旧木双人桌" and Rules.variant_data("invalid").is_empty(), "Catalog display safely handles invalid category and variant")
	_check(Rules.item_name({"kind":"lamp"}) == "船用提灯", "Legacy item labels default to basic tier")
func _test_expanded_geometry() -> void:
	var p = _new()
	p.coins = 1000
	var table: int = p.buy_furniture("table","premium")
	_check(Rules.MIN_X == -10.3 and Rules.MAX_X == 10.3 and Rules.MAX_Z == 9.4 and Rules.MIN_Z == -2.45, "Expanded room uses agreed dimensions")
	_check(p.place_furniture(table,9.0,7.5,0), "Premium table fits new far-right/back edge outside old room")
	_check(p.place_furniture(table,-9.0,7.5,0), "Premium table fits new far-left/back edge")
	_check(not p.place_furniture(table,100.0,7.5,0) and not p.place_furniture(table,9.5,7.5,0), "Distant and footprint-overflow positions remain invalid")
	_check(not p.place_furniture(table,0.0,4.0,0), "Central aisle remains protected for solids")
	var plant: int = p.buy_furniture("plant","comfort")
	_check(p.place_furniture(plant,1.0,4.0,0), "Plant touching new 0.6-meter half-aisle is valid")
	_check(not p.place_furniture(plant,0.5,4.0,0), "Plant encroaching new aisle remains invalid")
	var rug: int = p.buy_furniture("rug","premium")
	_check(p.place_furniture(rug,0.0,7.5,0), "Rug can cross aisle in expanded rear area")
	_check(Rules.footprint("table",0) == Vector2(2.5,3.8) and Rules.footprint("table",1) == Vector2(3.8,2.5), "All table tiers retain standard and rotated footprints")
	p.renovation.kitchen = true
	p.renovation.tables = true
	p.furniture_items()
	_check(p.seats() == 2, "Bigger floor does not bypass base two-seat operating limit")
	p.renovation.expansion = true
	p.furniture_items()
	_check(p.seats() == 4, "Expansion still caps operating seats at four")
func _test_legacy_and_invalid_variants() -> void:
	var p = _new()
	var flags: Dictionary = {"clean":true,"kitchen":true,"tables":true,"sign":true,"expansion":true,"decor":true}
	p._apply_save_data({"version":3,"coins":222,"renovation":flags,"furnishings":[
		{"uid":100,"kind":"lamp","x":-5.5,"z":4.5,"rotation":1,"color":2,"placed":true},
		{"uid":101,"kind":"shelf","variant":"bad","x":8.0,"z":7.0,"rotation":0,"color":1,"placed":false},
		{"uid":102,"kind":"plant","variant":{},"x":7.0,"z":7.0,"rotation":0,"color":0,"placed":false},
	]})
	_check(p.coins == 222 and p.furniture_by_uid(100).variant == "basic" and p.furniture_by_uid(100).placed and p.furniture_by_uid(100).color == 2, "V3 missing variant migrates to basic without losing layout or money")
	_check(p.furniture_by_uid(101).variant == "basic" and p.furniture_by_uid(102).variant == "basic", "Unknown and wrong-type saved variants downgrade to basic")
	var all_gifts_basic: bool = true
	for item in p.furniture_items():
		if item.uid < 100:
			all_gifts_basic = all_gifts_basic and item.variant == "basic"
	_check(all_gifts_basic and p.seats() == 4, "Legacy renovation gifts remain basic and preserve seating")
	var old = _new()
	old._apply_save_data({"version":1,"coins":500,"tank_level":2})
	_check(old.coins == 500 and old.tank_level == 2 and old.furniture_items().is_empty(), "V1 diving saves remain compatible")
	old._apply_save_data({"version":2,"renovation":flags})
	_check(old.furniture_items().size() == 8 and old.furniture_by_uid(1).variant == "basic", "V2 restaurant saves receive basic defaults")
func _clear_fixture() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
func _test_disk_roundtrip() -> void:
	_clear_fixture()
	var p = _new()
	p.coins = 5000
	p.save_path = TEST_PATH
	p.persistence_enabled = true
	var identities: Dictionary = {}
	for kind in EXPECTED:
		for variant in ["basic","comfort","premium"]:
			var uid: int = p.buy_furniture(kind,variant)
			identities[uid] = {"kind":kind,"variant":variant}
	var lamp_uid: int = 111
	_check(p.furniture_by_uid(lamp_uid).kind == "lamp" and p.place_furniture(lamp_uid,9.0,8.5,1), "Roundtrip fixture includes furniture in expanded room")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	_check(saved.version == 4 and saved.furnishings.size() == 24, "V4 writes all twenty-four purchased variants")
	var loaded = P.new()
	loaded.save_path = TEST_PATH
	loaded.load_game()
	for uid in identities:
		var item: Dictionary = loaded.furniture_by_uid(uid)
		_check(item.kind == identities[uid].kind and item.variant == identities[uid].variant, "Disk reload preserves kind and variant for UID " + str(uid))
	_check(loaded.coins == p.coins and loaded.furniture_by_uid(lamp_uid).placed and loaded.furniture_by_uid(lamp_uid).x == 9.0 and loaded.furniture_by_uid(lamp_uid).z == 8.5, "Disk reload preserves money and expanded-edge placement")
	_clear_fixture()
