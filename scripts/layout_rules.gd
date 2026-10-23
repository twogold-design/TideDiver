extends RefCounted
class_name LayoutRules
## Authoritative placement footprints in room-local X/Z coordinates.
const CATALOG := {
	"table": {"name":"餐桌", "cost":70, "size":Vector2(2.5,3.8)},
	"plant": {"name":"绿植", "cost":25, "size":Vector2(0.8,0.8)},
	"rug": {"name":"地毯", "cost":30, "size":Vector2(2.8,3.2)},
	"lamp": {"name":"落地灯", "cost":40, "size":Vector2(0.8,0.8)},
	"shelf": {"name":"展示架", "cost":55, "size":Vector2(1.8,0.8)},
}
const VARIANTS := {
	"table": {
		"basic":{"name":"原木小圆桌","cost":70,"description":"轻巧圆桌搭配朴素木椅，适合海边小店"},
		"comfort":{"name":"橡木软座桌","cost":160,"description":"厚实橡木桌与软垫座椅，温暖舒适"},
		"premium":{"name":"大理石餐桌","cost":320,"description":"石纹桌面与精致桌脚，打造优雅用餐区"},
	},
	"plant": {
		"basic":{"name":"陶盆绿植","cost":25,"description":"素陶花盆与清新绿叶，点缀店内角落"},
		"comfort":{"name":"釉陶龟背竹","cost":65,"description":"亮釉陶盆与舒展的大叶龟背竹"},
		"premium":{"name":"黄铜盆景","cost":130,"description":"黄铜花器搭配层次分明的盆景"},
	},
	"rug": {
		"basic":{"name":"普通编织地毯","cost":30,"description":"简洁编织纹路，让地面更温馨"},
		"comfort":{"name":"羊毛地毯","cost":90,"description":"柔软厚实的羊毛地毯与细致包边"},
		"premium":{"name":"波斯纹样地毯","cost":180,"description":"丰富几何纹样与流苏，成为空间焦点"},
	},
	"lamp": {
		"basic":{"name":"布罩落地灯","cost":40,"description":"朴素布灯罩散发柔和暖光"},
		"comfort":{"name":"黄铜弧光灯","cost":110,"description":"黄铜弧形灯杆延伸出温暖阅读光"},
		"premium":{"name":"彩玻璃落地灯","cost":220,"description":"彩色玻璃灯罩呈现复古海岸风情"},
	},
	"shelf": {
		"basic":{"name":"松木开放架","cost":55,"description":"开放式松木层架，摆放日常收藏"},
		"comfort":{"name":"橡木玻璃柜","cost":140,"description":"橡木框架与玻璃柜门，整齐展示藏品"},
		"premium":{"name":"胡桃木陈列柜","cost":280,"description":"深色胡桃木与精致细节，珍藏海岸故事"},
	},
}
const MIN_X := -10.3
const MAX_X := 10.3
const MIN_Z := -2.45
const MAX_Z := 9.4
const AISLE_HALF_WIDTH := 0.6
const GRID := 0.5
const EPSILON := 0.0001

static func variant_ids(kind: String) -> Array:
	return VARIANTS[kind].keys() if VARIANTS.has(kind) else []

static func variant_data(kind: String, variant: String = "basic") -> Dictionary:
	if not VARIANTS.has(kind):
		return {}
	return VARIANTS[kind].get(variant, VARIANTS[kind].basic)

static func item_name(item: Dictionary) -> String:
	var data := variant_data(str(item.get("kind", "")), str(item.get("variant", "basic")))
	return str(data.get("name", "未知家具"))

static func snap_position(x: float, z: float) -> Vector2:
	return Vector2(snappedf(x, GRID), snappedf(z, GRID))

static func footprint(kind: String, rotation: int) -> Vector2:
	if not CATALOG.has(kind):
		return Vector2.ZERO
	var size: Vector2 = CATALOG[kind].size
	return Vector2(size.y, size.x) if rotation % 2 == 1 else size

static func bounds(item: Dictionary) -> Rect2:
	var size := footprint(str(item.kind), int(item.rotation))
	return Rect2(Vector2(float(item.x), float(item.z)) - size * 0.5, size)

static func _overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - EPSILON and a.end.x > b.position.x + EPSILON and a.position.y < b.end.y - EPSILON and a.end.y > b.position.y + EPSILON

static func validate(items: Array, uid: int, x: float, z: float, rotation: int) -> String:
	if not is_finite(x) or not is_finite(z) or rotation < 0 or rotation > 3:
		return "家具位置或旋转无效"
	var selected: Dictionary = {}
	for item in items:
		if int(item.uid) == uid:
			selected = item
			break
	if selected.is_empty() or not CATALOG.has(selected.kind):
		return "找不到这件家具"
	var point := snap_position(x, z)
	var candidate: Dictionary = {"kind": selected.kind, "rotation":rotation, "x":point.x, "z":point.y}
	var rect := bounds(candidate)
	if rect.position.x < MIN_X - EPSILON or rect.end.x > MAX_X + EPSILON or rect.position.y < MIN_Z - EPSILON or rect.end.y > MAX_Z + EPSILON:
		return "家具超出可布置地面"
	if selected.kind != "rug" and _overlaps(rect, Rect2(-AISLE_HALF_WIDTH, MIN_Z, AISLE_HALF_WIDTH * 2.0, MAX_Z - MIN_Z)):
		return "请留出中央入口通道"
	for other in items:
		if int(other.uid) == uid or not other.placed:
			continue
		if (selected.kind == "rug") != (other.kind == "rug"):
			continue
		if _overlaps(rect, bounds(other)):
			return "地毯不能相互重叠" if selected.kind == "rug" else "与其他家具重叠"
	return ""
