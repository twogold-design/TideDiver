extends RefCounted
class_name Progression
## Inventory, equipment and restaurant bookkeeping. Saves stay inside the project.

const Layout = preload("res://scripts/layout_rules.gd")
const FishCatalog = preload("res://scripts/fish_catalog.gd")
const SAVE_PATH := "res://saves/progress.json"
const MAX_UPGRADE_LEVEL := 3
const MAX_COINS := 999999999
const MAX_DAYS := 999999
const MAX_FISH := 999999999
const MAX_ITEMS := 1000000
const MAX_DEPTH := 100000.0
const UPGRADE_BASE_COSTS := {"tank": 80, "bag": 70, "spear": 110}
const GOODS := {
	"orange": FishCatalog.SPECIES[0],
	"blue": FishCatalog.SPECIES[1],
	"lantern": FishCatalog.SPECIES[2],
	"pearl": {"name": "月光珍珠", "value": 28},
	"chest": {"name": "沉船宝藏", "value": 90},
	"sardine": FishCatalog.SPECIES[3],
	"puffer": FishCatalog.SPECIES[4],
	"lionfish": FishCatalog.SPECIES[5],
	"tuna": FishCatalog.SPECIES[6],
	"moray": FishCatalog.SPECIES[7],
	"reef_shark": FishCatalog.SPECIES[8],
}
const RECIPES := {
	"orange": {"name": "香煎橘鳍鱼", "price": 42, "cook_time": 3.0},
	"blue": {"name": "海盐青背鱼", "price": 72, "cook_time": 4.0},
	"lantern": {"name": "深海灯笼鱼料理", "price": 120, "cook_time": 5.0},
}
const RENOVATIONS := {
	"clean": {"name": "清理与修复", "cost": 40, "requires": [], "description": "清除杂物，修复地面与墙面"},
	"kitchen": {"name": "基础厨房", "cost": 100, "requires": ["clean"], "description": "安装料理台与炉灶，开业必需"},
	"tables": {"name": "基础桌椅", "cost": 70, "requires": ["clean"], "description": "设置两组桌椅，开业必需"},
	"sign": {"name": "海岸招牌", "cost": 80, "requires": ["kitchen", "tables"], "description": "点亮门头，每场顾客 +2"},
	"expansion": {"name": "增设雅座", "cost": 140, "requires": ["tables"], "description": "赠2套餐桌，座位上限增至4位"},
	"decor": {"name": "海洋软装", "cost": 110, "requires": ["sign"], "description": "耐心+8秒，小费+10%，赠品入收纳"},
}

var save_path: String = SAVE_PATH
var persistence_enabled: bool = true
var coins: int = 0
var day: int = 1
var tank_level: int = 0
var bag_level: int = 0
var spear_level: int = 0
var total_fish: int = 0
var best_depth: float = 0.0
var inventory: Dictionary = {"orange": 0, "blue": 0, "lantern": 0, "pearl": 0, "chest": 0, "sardine": 0, "puffer": 0, "lionfish": 0, "tuna": 0, "moray": 0, "reef_shark": 0}
var renovation: Dictionary = {"clean": false, "kitchen": false, "tables": false, "sign": false, "expansion": false, "decor": false}
var restaurant_runs: int = 0
var total_served: int = 0
var total_lost: int = 0
var restaurant_income: int = 0
var last_service_day: int = 0
var service_active: bool = false
var service_stock: Dictionary = {"orange": 0, "blue": 0, "lantern": 0}
var service_pending: Array[String] = []
var service_stats: Dictionary = {"earned": 0, "served": 0, "lost": 0}
var last_service_result: Dictionary = {}
var recovery_notice: String = ""
var furnishings: Array = []
var recycled_gifts: Array[int] = []
var floor_style: int = 0
var wall_style: int = 0
var next_furniture_uid: int = 100

func oxygen_max() -> float:
	return 100.0 + 25.0 * tank_level

func capacity() -> int:
	return 12 + 4 * bag_level

func spear_damage() -> int:
	return 1 + spear_level

func upgrade_cost(kind: String) -> int:
	var level := _upgrade_level(kind)
	return -1 if level < 0 or level >= MAX_UPGRADE_LEVEL else int(UPGRADE_BASE_COSTS[kind]) * (level + 1)

func buy_upgrade(kind: String) -> bool:
	var cost := upgrade_cost(kind)
	if service_active or cost < 0 or coins < cost:
		return false
	coins -= cost
	match kind:
		"tank": tank_level += 1
		"bag": bag_level += 1
		"spear": spear_level += 1
	save_game()
	return true

## Consumes the cargo array; use explicit goods IDs or legacy canonical names.
func complete_dive(cargo: Array, rescued: bool, depth: float) -> Dictionary:
	if service_active:
		return {"earned": 0, "count": 0, "rescued": rescued, "day": day, "stored": {}}
	var sale_value: int = 0
	var item_count: int = 0
	var fish_count: int = 0
	var stored: Dictionary = {}
	for entry in cargo:
		var id := _cargo_id(entry)
		if id.is_empty():
			continue
		item_count += 1
		sale_value = mini(MAX_COINS, sale_value + int(GOODS[id].value))
		if FishCatalog.has_id(id):
			fish_count += 1
		if not rescued and int(inventory.get(id, 0)) < MAX_ITEMS:
			inventory[id] = int(inventory.get(id, 0)) + 1
			stored[id] = int(stored.get(id, 0)) + 1
	cargo.clear()
	var earned: int = int(float(sale_value * 35) / 100.0) if rescued else 0
	coins = mini(MAX_COINS, coins + earned)
	total_fish = mini(MAX_FISH, total_fish + fish_count)
	if is_finite(depth):
		best_depth = maxf(best_depth, clampf(depth, 0.0, MAX_DEPTH))
	day = mini(MAX_DAYS, day + 1)
	save_game()
	return {"earned": earned, "count": item_count, "rescued": rescued, "day": day, "stored": stored}

func _cargo_id(entry: Variant) -> String:
	if not entry is Dictionary:
		return ""
	if entry.has("id"):
		return str(entry.id) if GOODS.has(entry.id) else ""
	if GOODS.has(entry.get("kind", "")):
		return str(entry.kind)
	for id in GOODS:
		if entry.get("name", "") == GOODS[id].name:
			return id
	return ""

func inventory_total() -> int:
	var amount: int = 0
	for id in GOODS:
		amount += int(inventory.get(id, 0))
	return amount

func sell(id: String, amount: int) -> int:
	if service_active or not GOODS.has(id) or amount <= 0 or amount > int(inventory.get(id, 0)):
		return 0
	var earned: int = amount * int(GOODS[id].value)
	if coins + earned > MAX_COINS:
		return 0
	inventory[id] -= amount
	coins += earned
	save_game()
	return earned

func sell_valuables() -> int:
	if service_active:
		return 0
	var earned: int = int(inventory.pearl) * 28 + int(inventory.chest) * 90
	if earned <= 0 or coins + earned > MAX_COINS:
		return 0
	inventory.pearl = 0
	inventory.chest = 0
	coins += earned
	save_game()
	return earned

func renovation_reason(id: String) -> String:
	if not RENOVATIONS.has(id):
		return "未知装修项目"
	if renovation[id]:
		return "已完成"
	if service_active:
		return "营业结束后可装修"
	for required in RENOVATIONS[id].requires:
		if not renovation[required]:
			return "先完成：" + str(RENOVATIONS[required].name)
	if coins < int(RENOVATIONS[id].cost):
		return "还需 %d G" % (int(RENOVATIONS[id].cost) - coins)
	return ""

func renovate(id: String) -> bool:
	if not renovation_reason(id).is_empty():
		return false
	coins -= int(RENOVATIONS[id].cost)
	renovation[id] = true
	furniture_items()
	save_game()
	return true

func can_open() -> bool:
	return renovation.clean and renovation.kitchen and renovation.tables and seats() > 0

func seats() -> int:
	return mini(4 if renovation.expansion else 2, placed_tables().size())

func guest_limit() -> int:
	return 4 + (2 if renovation.sign else 0) + (2 if renovation.expansion else 0)

func patience() -> float:
	return 32.0 if renovation.decor else 24.0

func next_goal() -> String:
	for id in ["clean", "kitchen", "tables"]:
		if not renovation[id]:
			return "筹资 %d G · %s" % [RENOVATIONS[id].cost, RENOVATIONS[id].name]
	if seats() == 0:
		return "进入自由布置，摆放至少一张餐桌再开业"
	if inventory.orange + inventory.blue + inventory.lantern == 0 and not service_active:
		return "再次下潜，留下海鱼作为料理食材"
	if restaurant_runs == 0:
		return "准备至少一份料理，迎接首次营业"
	for id in ["sign", "expansion", "decor"]:
		if not renovation[id]:
			return "筹资 %d G · %s" % [RENOVATIONS[id].cost, RENOVATIONS[id].name]
	return "海岸餐厅已焕然一新 · 继续潜水与经营"

func begin_service(plan: Dictionary) -> bool:
	if not can_open() or service_active or last_service_day == day:
		return false
	var total: int = 0
	for id in plan:
		if not RECIPES.has(id) or not _is_integer(plan[id]) or plan[id] < 0 or plan[id] > inventory[id]:
			return false
		total += int(plan[id])
	if total <= 0:
		return false
	for id in RECIPES:
		service_stock[id] = int(plan.get(id, 0))
		inventory[id] -= service_stock[id]
	service_pending.clear()
	service_stats = {"earned": 0, "served": 0, "lost": 0}
	service_active = true
	last_service_day = day
	last_service_result = {}
	save_game()
	return true

func allocate_dish() -> String:
	if not service_active or int(service_stats.served) + int(service_stats.lost) + service_pending.size() >= guest_limit():
		return ""
	for id in RECIPES:
		if service_stock[id] > 0:
			service_stock[id] -= 1
			service_pending.append(id)
			save_game()
			return id
	return ""

func record_served(id: String, quality_bonus: int = 0) -> int:
	if not service_active or not RECIPES.has(id) or not service_pending.has(id):
		return 0
	service_pending.erase(id)
	var earned: int = int(RECIPES[id].price)
	if renovation.decor:
		earned += int(float(earned) / 10.0)
	earned += int(float(RECIPES[id].price)*clampi(quality_bonus,0,25)/100.0)
	coins = mini(MAX_COINS, coins + earned)
	service_stats.earned += earned
	service_stats.served += 1
	total_served = mini(MAX_FISH, total_served + 1)
	restaurant_income = mini(MAX_COINS, restaurant_income + earned)
	save_game()
	return earned

## Pass the dish ID for out-of-order departures. No argument consumes the oldest order.
func record_lost(id: String = "") -> void:
	if not service_active or service_pending.is_empty():
		return
	if id.is_empty():
		id = service_pending[0]
	if not service_pending.has(id):
		return
	service_pending.erase(id)
	service_stats.lost += 1
	total_lost = mini(MAX_FISH, total_lost + 1)
	save_game()

## Pending ledger is authoritative; caller count is accepted for compatibility.
func end_service(_pending_count: int = 0, reviews: Dictionary = {}, culinary: Dictionary = {}) -> Dictionary:
	if not service_active:
		return last_service_result.duplicate(true)
	var lost: int = service_pending.size()
	service_stats.lost += lost
	total_lost = mini(MAX_FISH, total_lost + lost)
	service_pending.clear()
	var returned: int = 0
	for id in RECIPES:
		returned += int(service_stock[id])
		inventory[id] = mini(MAX_ITEMS, int(inventory[id]) + int(service_stock[id]))
		service_stock[id] = 0
	last_service_result = {"earned": int(service_stats.earned), "served": int(service_stats.served), "lost": int(service_stats.lost), "returned": returned}
	if not reviews.is_empty():
		last_service_result["reviews"] = _read_counts(reviews,{"satisfied":0,"okay":0,"lost":0},guest_limit())
	if not culinary.is_empty():
		last_service_result["culinary"] = _read_counts(culinary,{"excellent":0,"matched":0,"cold":0,"bonus":0},MAX_COINS)
	service_active = false
	restaurant_runs = mini(MAX_DAYS, restaurant_runs + 1)
	save_game()
	return last_service_result.duplicate(true)

func _save_data() -> Dictionary:
	furniture_items()
	return {"version": 4, "coins": coins, "day": day, "tank_level": tank_level, "bag_level": bag_level, "spear_level": spear_level,
		"total_fish": total_fish, "best_depth": best_depth, "inventory": inventory, "renovation": renovation,
		"restaurant_runs": restaurant_runs, "total_served": total_served, "total_lost": total_lost,
		"restaurant_income": restaurant_income, "last_service_day": last_service_day, "service_active": service_active,
		"service_stock": service_stock, "service_pending": service_pending, "service_stats": service_stats, "last_service_result": last_service_result, "furnishings": furnishings, "recycled_gifts":recycled_gifts, "floor_style":floor_style, "wall_style":wall_style, "next_furniture_uid":next_furniture_uid}

func _allowed_save_path() -> bool:
	if not (save_path.begins_with("res://saves/") or save_path.begins_with("res://tests/temp/")):
		return false
	var relative := save_path.trim_prefix("res://")
	return not relative.contains("..") and not relative.contains("\\") and not relative.contains(":") and relative.ends_with(".json")

func save_game() -> void:
	if not persistence_enabled:
		return
	if not _allowed_save_path():
		push_warning("Tide Diver: refused a save path outside project saves/tests.")
		return
	var destination := ProjectSettings.globalize_path(save_path)
	if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
		push_warning("Tide Diver: could not create save directory.")
		return
	var temporary := destination + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("Tide Diver: could not write save.")
		return
	file.store_string(JSON.stringify(_save_data(), "\t"))
	file.flush()
	file.close()
	# Keep only a parseable prior generation as backup.
	if _read_save(destination) is Dictionary:
		if DirAccess.copy_absolute(destination, destination + ".bak") != OK:
			push_warning("Tide Diver: could not update save backup.")
	if DirAccess.rename_absolute(temporary, destination) != OK:
		push_warning("Tide Diver: could not replace save atomically.")

## Reset only after the player's confirmation. Both save generations belong to the new run.
func reset_game() -> bool:
	var fresh = get_script().new()
	var data: Dictionary = fresh._save_data().duplicate(true)
	if persistence_enabled:
		if not _allowed_save_path():
			return false
		var destination: String = ProjectSettings.globalize_path(save_path)
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
			return false
		var temporary: String = destination + ".tmp"
		var file := FileAccess.open(temporary,FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(JSON.stringify(data,"\t"))
		file.flush()
		var write_error: Error = file.get_error()
		file.close()
		if write_error != OK:
			return false
		# Replace the fallback first: an old backup must never resurrect the previous run.
		if DirAccess.copy_absolute(temporary,destination + ".bak") != OK:
			return false
		if DirAccess.rename_absolute(temporary,destination) != OK:
			return false
	_apply_save_data(data)
	recovery_notice = ""
	return true

func _read_save(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1048576:
		return null
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(contents) != OK or not parser.data is Dictionary:
		return null
	return parser.data

func load_game() -> void:
	if not persistence_enabled:
		return
	if not _allowed_save_path():
		return
	var data: Variant = _read_save(save_path)
	if data == null:
		data = _read_save(save_path + ".bak")
		if data != null:
			recovery_notice = "存档异常，已从上一份备份恢复。"
		elif FileAccess.file_exists(save_path):
			recovery_notice = "存档无法读取，已使用默认进度。"
	if data == null:
		return
	_apply_save_data(data)
	if service_active:
		var result := end_service(service_pending.size())
		recovery_notice += "上次营业已安全结束：退回 %d 份未分配食材；已接订单记为流失，当日不可重复营业。" % result.returned

func _apply_save_data(data: Variant) -> void:
	if not data is Dictionary:
		return
	coins = _safe_int(data.get("coins"), 0, MAX_COINS, coins)
	day = _safe_int(data.get("day"), 1, MAX_DAYS, day)
	tank_level = _safe_int(data.get("tank_level"), 0, MAX_UPGRADE_LEVEL, tank_level)
	bag_level = _safe_int(data.get("bag_level"), 0, MAX_UPGRADE_LEVEL, bag_level)
	spear_level = _safe_int(data.get("spear_level"), 0, MAX_UPGRADE_LEVEL, spear_level)
	total_fish = _safe_int(data.get("total_fish"), 0, MAX_FISH, total_fish)
	var saved_depth: Variant = data.get("best_depth")
	if (saved_depth is float or saved_depth is int) and is_finite(float(saved_depth)):
		best_depth = clampf(float(saved_depth), 0.0, MAX_DEPTH)
	inventory = _read_counts(data.get("inventory"), GOODS, MAX_ITEMS)
	var flags: Variant = data.get("renovation", {})
	for id in RENOVATIONS:
		renovation[id] = flags is Dictionary and flags.get(id) is bool and flags.get(id) == true
		for required in RENOVATIONS[id].requires:
			if not renovation[required]:
				renovation[id] = false
	_load_layout(data)
	restaurant_runs = _safe_int(data.get("restaurant_runs"), 0, MAX_DAYS, 0)
	total_served = _safe_int(data.get("total_served"), 0, MAX_FISH, 0)
	total_lost = _safe_int(data.get("total_lost"), 0, MAX_FISH, 0)
	restaurant_income = _safe_int(data.get("restaurant_income"), 0, MAX_COINS, 0)
	last_service_day = _safe_int(data.get("last_service_day"), 0, day, 0)
	service_active = data.get("service_active") is bool and data.get("service_active") == true
	service_stock = _read_counts(data.get("service_stock"), RECIPES, MAX_ITEMS)
	service_stats = _read_counts(data.get("service_stats"), {"earned": 0, "served": 0, "lost": 0}, MAX_COINS)
	service_stats.served = mini(int(service_stats.served), guest_limit())
	service_stats.lost = mini(int(service_stats.lost), guest_limit() - int(service_stats.served))
	service_pending.clear()
	var pending: Variant = data.get("service_pending", [])
	if pending is Array:
		for id in pending:
			if id is String and RECIPES.has(id) and service_pending.size() + int(service_stats.served) + int(service_stats.lost) < guest_limit():
				service_pending.append(id)
	last_service_result = {}
	if data.get("last_service_result") is Dictionary and not data.last_service_result.is_empty():
		last_service_result = _read_counts(data.last_service_result, {"earned": 0, "served": 0, "lost": 0, "returned": 0}, MAX_COINS)
		if data.last_service_result.get("reviews") is Dictionary:
			last_service_result["reviews"] = _read_counts(data.last_service_result.reviews,{"satisfied":0,"okay":0,"lost":0},guest_limit())
		if data.last_service_result.get("culinary") is Dictionary:
			last_service_result["culinary"] = _read_counts(data.last_service_result.culinary,{"excellent":0,"matched":0,"cold":0,"bonus":0},MAX_COINS)
	if not service_active:
		service_stock = _read_counts({}, RECIPES, MAX_ITEMS)
		service_pending.clear()
	else:
		last_service_day = day

func _read_counts(data: Variant, keys: Dictionary, maximum: int) -> Dictionary:
	var result: Dictionary = {}
	for id in keys:
		result[id] = _safe_int(data.get(id), 0, maximum, 0) if data is Dictionary else 0
	return result

func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func _safe_int(value: Variant, minimum: int, maximum: int, fallback: int) -> int:
	if not _is_integer(value):
		return fallback
	return int(clampf(float(value), float(minimum), float(maximum)))

func _upgrade_level(kind: String) -> int:
	match kind:
		"tank": return tank_level
		"bag": return bag_level
		"spear": return spear_level
	return -1



const GIFT_FURNITURE := {
	1:{"kind":"table","x":-3.5,"z":-0.5,"requires":"tables"},
	2:{"kind":"table","x":3.5,"z":-0.5,"requires":"tables"},
	3:{"kind":"table","x":-3.5,"z":3.5,"requires":"expansion"},
	4:{"kind":"table","x":3.5,"z":3.5,"requires":"expansion"},
	5:{"kind":"plant","x":-5.5,"z":1.5,"requires":"decor"},
	6:{"kind":"plant","x":5.5,"z":1.5,"requires":"decor"},
	7:{"kind":"rug","x":-3.5,"z":-0.5,"requires":"decor"},
	8:{"kind":"rug","x":3.5,"z":-0.5,"requires":"decor"},
}

func furniture_items() -> Array:
	for existing in furnishings:
		if existing.get("variant", "" ) not in Layout.variant_ids(str(existing.kind)):
			existing.variant = "basic"
	# Existing entries, including deliberately stored gifts, are never overwritten.
	for uid in GIFT_FURNITURE:
		var gift: Dictionary = GIFT_FURNITURE[uid]
		if not renovation[gift.requires] or uid in recycled_gifts:
			continue
		var exists: bool = false
		for item in furnishings:
			if int(item.uid) == uid:
				exists = true
				break
		if exists:
			continue
		var item: Dictionary = {"uid":uid,"kind":gift.kind,"variant":"basic","x":gift.x,"z":gift.z,"rotation":0,"color":0,"placed":false}
		furnishings.append(item)
		# Decorative gifts stay in storage until the player chooses their position.
		if gift.kind == "table":
			_place_gift_table(item)
	return furnishings

func _place_gift_table(item: Dictionary) -> bool:
	if _table_count(int(item.uid)) >= _table_limit():
		return false
	var origin := Vector2(float(item.x),float(item.z))
	var candidates: Array[Vector2] = [origin]
	for zi in range(int(ceil(Layout.MIN_Z/Layout.GRID)),int(floor(Layout.MAX_Z/Layout.GRID))+1):
		for xi in range(int(ceil(Layout.MIN_X/Layout.GRID)),int(floor(Layout.MAX_X/Layout.GRID))+1):
			candidates.append(Vector2(xi*Layout.GRID,zi*Layout.GRID))
	candidates.sort_custom(func(a: Vector2,b: Vector2): return a.distance_squared_to(origin) < b.distance_squared_to(origin))
	for point in candidates:
		for rotation in [0,1]:
			if Layout.validate(furnishings,int(item.uid),point.x,point.y,rotation).is_empty():
				item.x = point.x
				item.z = point.y
				item.rotation = rotation
				item.placed = true
				return true
	return false

func furniture_by_uid(uid: int) -> Dictionary:
	for item in furniture_items():
		if int(item.uid) == uid:
			return item
	return {}

func _table_limit() -> int:
	return 4 if renovation.expansion else 2

func _table_count(exclude_uid: int = -1) -> int:
	var count: int = 0
	for item in furnishings:
		if item.kind == "table" and item.placed and int(item.uid) != exclude_uid:
			count += 1
	return count

func placed_tables() -> Array:
	var result: Array = []
	for item in furniture_items():
		if item.kind == "table" and item.placed:
			result.append(item)
	return result

func buy_furniture(kind: String, variant: String = "basic") -> int:
	if service_active or not renovation.clean or not Layout.CATALOG.has(kind) or variant not in Layout.variant_ids(kind) or furnishings.size() >= 1024:
		return -1
	var cost: int = int(Layout.variant_data(kind,variant).cost)
	if coins < cost or next_furniture_uid >= 999999999:
		return -1
	furniture_items()
	var uid: int = next_furniture_uid
	next_furniture_uid += 1
	furnishings.append({"uid":uid,"kind":kind,"variant":variant,"x":0.0,"z":0.0,"rotation":0,"color":0,"placed":false})
	coins -= cost
	save_game()
	return uid

func placement_reason(uid: int, x: float, z: float, rotation: int) -> String:
	if service_active:
		return "营业结束后可布置"
	if not renovation.clean:
		return "先完成清理与修复"
	var item := furniture_by_uid(uid)
	if item.is_empty():
		return "找不到这件家具"
	if item.kind == "table" and _table_count(uid) >= _table_limit():
		return "已达到当前桌位上限，先收纳一张桌或增设雅座"
	return Layout.validate(furnishings,uid,x,z,rotation)

func place_furniture(uid: int, x: float, z: float, rotation: int) -> bool:
	if not placement_reason(uid,x,z,rotation).is_empty():
		return false
	var item := furniture_by_uid(uid)
	var point: Vector2 = Layout.snap_position(x,z)
	item.x = point.x
	item.z = point.y
	item.rotation = rotation
	item.placed = true
	save_game()
	return true

func store_furniture(uid: int) -> bool:
	if service_active or not renovation.clean:
		return false
	var item := furniture_by_uid(uid)
	if item.is_empty() or not item.placed:
		return false
	item.placed = false
	save_game()
	return true

func furniture_refund(uid: int) -> int:
	var item := furniture_by_uid(uid)
	if item.is_empty():
		return 0
	return ceili(float(Layout.variant_data(item.kind,item.variant).cost)*0.5)

func recycle_furniture(uid: int) -> int:
	if service_active or not renovation.clean:
		return 0
	var refund: int = furniture_refund(uid)
	if refund <= 0 or coins > MAX_COINS-refund:
		return 0
	for index in range(furnishings.size()):
		if int(furnishings[index].uid) != uid:
			continue
		furnishings.remove_at(index)
		if GIFT_FURNITURE.has(uid):
			recycled_gifts.append(uid)
		coins += refund
		save_game()
		return refund
	return 0

func recolor_furniture(uid: int, color: int) -> bool:
	if service_active or not renovation.clean or color < 0 or color > 2:
		return false
	var item := furniture_by_uid(uid)
	if item.is_empty():
		return false
	item.color = color
	save_game()
	return true

func set_room_style(surface: String, style: int) -> bool:
	if service_active or not renovation.clean or style < 0 or style > 2 or surface not in ["floor","wall"]:
		return false
	if surface == "floor":
		floor_style = style
	else:
		wall_style = style
	save_game()
	return true

func reset_layout() -> void:
	if service_active or not renovation.clean:
		return
	furniture_items()
	for item in furnishings:
		item.placed = false
	for item in furnishings:
		var uid: int = int(item.uid)
		if GIFT_FURNITURE.has(uid) and renovation[GIFT_FURNITURE[uid].requires]:
			var gift: Dictionary = GIFT_FURNITURE[uid]
			item.x = gift.x
			item.z = gift.z
			item.rotation = 0
			item.placed = true
	save_game()

func _load_layout(data: Dictionary) -> void:
	floor_style = _safe_int(data.get("floor_style"),0,2,0)
	wall_style = _safe_int(data.get("wall_style"),0,2,0)
	next_furniture_uid = _safe_int(data.get("next_furniture_uid"),100,999999998,100)
	recycled_gifts = []
	var retired: Variant = data.get("recycled_gifts",[])
	if retired is Array:
		for value in retired:
			if not _is_integer(value):
				continue
			var uid := int(value)
			if GIFT_FURNITURE.has(uid) and renovation[GIFT_FURNITURE[uid].requires] and uid not in recycled_gifts:
				recycled_gifts.append(uid)
	furnishings = []
	var raw: Variant = data.get("furnishings", [])
	var seen: Dictionary = {}
	if raw is Array:
		for entry in raw:
			if furnishings.size() >= 1024:
				break
			if not entry is Dictionary or not _is_integer(entry.get("uid")) or not entry.get("kind") is String:
				continue
			var uid: int = _safe_int(entry.uid,0,999999998,0)
			if uid <= 0 or seen.has(uid) or uid in recycled_gifts or not Layout.CATALOG.has(entry.kind):
				continue
			if uid < 100 and (not GIFT_FURNITURE.has(uid) or not renovation[GIFT_FURNITURE[uid].requires] or entry.kind != GIFT_FURNITURE[uid].kind):
				continue
			seen[uid] = true
			var numeric: bool = (entry.get("x") is float or entry.get("x") is int) and (entry.get("z") is float or entry.get("z") is int)
			var finite: bool = numeric and is_finite(float(entry.x)) and is_finite(float(entry.z)) and absf(float(entry.x)) < 1000.0 and absf(float(entry.z)) < 1000.0
			var point: Vector2 = Layout.snap_position(float(entry.x),float(entry.z)) if finite else Vector2.ZERO
			var rotation: int = _safe_int(entry.get("rotation"),0,3,0)
			var item: Dictionary = {"uid":uid,"kind":entry.kind,"variant":entry.get("variant", "basic") if entry.get("variant", "basic") in Layout.variant_ids(entry.kind) else "basic","x":point.x,"z":point.y,"rotation":rotation,"color":_safe_int(entry.get("color"),0,2,0),"placed":false}
			furnishings.append(item)
			var wants_placed: bool = entry.get("placed") is bool and entry.placed == true
			if finite and renovation.clean and wants_placed and Layout.validate(furnishings,uid,point.x,point.y,rotation).is_empty() and (item.kind != "table" or _table_count() < _table_limit()):
				item.placed = true
			if uid >= 100:
				next_furniture_uid = maxi(next_furniture_uid,uid + 1)
	furniture_items()
