extends RefCounted
## Order quality is earned through preparation, a timing action and plating.
const SEASONINGS := ["清爽","香煎","香辣"]
const PREP_TIME := 4.0
const HOT_WINDOW := 8.0

static func quality(order: Dictionary) -> int:
	if float(order.get("ready_age",0)) > HOT_WINDOW:
		return 0
	return int(order.get("prepped",false)) + (2 if order.get("heat_result","") == "perfect" else 0) + int(order.get("plated",false))

static func matches(order: Dictionary) -> bool:
	return int(order.get("seasoning",-1)) == int(order.get("preference",-2))

static func bonus_percent(order: Dictionary) -> int:
	var score: int = quality(order)
	return score*5 + (5 if score >= 2 and matches(order) else 0)

static func heat_fraction(order: Dictionary) -> float:
	return clampf(1.0-float(order.get("cook_left",0))/maxf(0.1,float(order.get("cook_total",1))),0,1)

static func quality_label(order: Dictionary) -> String:
	if float(order.get("ready_age",0)) > HOT_WINDOW:
		return "已凉 · 无品质加成"
	var score: int = quality(order)
	return ["家常","用心","精致","拿手","招牌"][clampi(score,0,4)]
