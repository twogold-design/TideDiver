extends RefCounted
class_name LayoutRules
## Authoritative placement footprints in room-local X/Z coordinates.
const CATALOG := {
	"table": {"name":"餐桌", "cost":70, "size":Vector2(2.5,3.8)},
	"plant": {"name":"绿植", "cost":25, "size":Vector2(0.8,0.8)},
	"rug": {"name":"地毯", "cost":30, "size":Vector2(2.8,3.2)},
	"lamp": {"name":"渔灯", "cost":40, "size":Vector2(0.8,0.8)},
	"shelf": {"name":"餐边柜", "cost":55, "size":Vector2(1.8,0.8)},
	"bench": {"name":"长椅", "cost":60, "size":Vector2(2.4,1.0)},
	"parasol": {"name":"遮阳", "cost":85, "size":Vector2(2.8,2.8)},
	"coastal": {"name":"渔港摆件", "cost":35, "size":Vector2(1.2,1.2)},
}
const VARIANTS := {
	"bench": {
		"basic":{"name":"漂木长凳","cost":60,"description":"风化木板、斜撑凳脚，渔港门口的歇脚处"},
		"comfort":{"name":"条纹坐垫长椅","cost":125,"description":"双色海蓝坐垫、浅蓝木靠背与帆布抱枕"},
		"premium":{"name":"藤编沙发茶几","cost":240,"description":"藤编双人沙发、亚麻坐垫与配套小茶几"},
	},
	"parasol": {
		"basic":{"name":"浅蓝帆布伞","cost":85,"description":"浅蓝帆布、木伞杆与绳结收边"},
		"comfort":{"name":"海蓝条纹大伞","cost":165,"description":"双色海蓝分片伞面、垂边与加固伞骨"},
		"premium":{"name":"卷帘木架凉棚","cost":290,"description":"木柱凉棚、帆布顶、卷帘和暖灯串"},
	},
	"coastal": {
		"basic":{"name":"今日鲜鱼黑板","cost":35,"description":"木框支架、今日鲜鱼菜单和手绘鱼形"},
		"comfort":{"name":"渔获木箱浮球","cost":90,"description":"渔获木箱、彩色浮球与盘好的缆绳"},
		"premium":{"name":"小木船陈列台","cost":210,"description":"小木船造型台面、冰鲜渔获与柠檬"},
	},
	"table": {
		"basic":{"name":"旧木双人桌","cost":70,"description":"旧木拼板双人桌，搭配交叉支架折叠椅"},
		"comfort":{"name":"浅蓝藤椅圆桌","cost":160,"description":"浅蓝木圆桌配藤编椅背，清爽通透"},
		"premium":{"name":"柚木条纹餐桌","cost":320,"description":"柚木拼板桌、双色海蓝软座与海边餐具"},
	},
	"plant": {
		"basic":{"name":"陶盆海岸绿植","cost":25,"description":"素陶盆、细枝绿叶与土面小石"},
		"comfort":{"name":"木箱组合花草","cost":65,"description":"板条木箱内的组合花草和小花"},
		"premium":{"name":"陶缸棕榈","cost":130,"description":"大陶缸、棕榈羽叶与底部卵石"},
	},
	"rug": {
		"basic":{"name":"椰纤迎宾垫","cost":30,"description":"粗织椰纤维、深色包边和迎宾字样"},
		"comfort":{"name":"条纹户外地毯","cost":90,"description":"双色海蓝条纹、防潮薄织面与整齐包边"},
		"premium":{"name":"沙色海蓝地毯","cost":180,"description":"人字编织、双层海蓝绳纹边、针脚与结穗"},
	},
	"lamp": {
		"basic":{"name":"船用提灯","cost":40,"description":"铁艺护笼、暖色灯芯和弧形提手"},
		"comfort":{"name":"木杆悬挂渔灯","cost":110,"description":"木立杆、金属挂钩与悬挂渔灯"},
		"premium":{"name":"双灯船桅庭院灯","cost":220,"description":"弧形锻铁灯架、链环铜灯、通风灯帽与绳结底座"},
	},
	"shelf": {
		"basic":{"name":"木制碗碟架","cost":55,"description":"开放木架，叠放餐盘、杯子和碗碟"},
		"comfort":{"name":"百叶门餐具柜","cost":140,"description":"百叶柜门、调料罐和台面餐具"},
		"premium":{"name":"冰鲜海产展示柜","cost":280,"description":"玻璃罩、碎冰鲜鱼、柠檬和今日鱼价牌"},
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
