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
const MIN_X := -6.3
const MAX_X := 6.3
const MIN_Z := -2.45
const MAX_Z := 5.4
const GRID := 0.5
const EPSILON := 0.0001

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
	if selected.kind != "rug" and _overlaps(rect, Rect2(-0.8, MIN_Z, 1.6, MAX_Z - MIN_Z)):
		return "请留出中央入口通道"
	for other in items:
		if int(other.uid) == uid or not other.placed:
			continue
		if (selected.kind == "rug") != (other.kind == "rug"):
			continue
		if _overlaps(rect, bounds(other)):
			return "地毯不能相互重叠" if selected.kind == "rug" else "与其他家具重叠"
	return ""
