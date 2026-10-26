extends RefCounted
## Feedback follows patience, actual cooking decisions, temperature and guest preferences.
const Cuisine = preload("res://scripts/cuisine.gd")
static func live(order: Dictionary) -> Dictionary:
	var fraction: float = clampf(float(order.get("patience",0)) / maxf(1.0,float(order.get("max_patience",38))),0,1)
	if fraction <= 0.25:
		return {"mood":"lost","text":"等了好久，还没好吗？"}
	if fraction <= 0.5:
		return {"mood":"okay","text":"有点饿了，能快一点吗？"}
	match str(order.get("state","waiting")):
		"cooking": return {"mood":"satisfied","text":"闻起来好香，期待！"}
		"ready": return {"mood":"satisfied","text":"做好了吗？请帮我上菜！"}
	return {"mood":"satisfied","text":"今天的鲜鱼很不错！"}

static func outcome(order: Dictionary, closed: bool = false) -> Dictionary:
	if closed:
		return {"mood":"lost","text":"还没吃到就打烊了……"}
	var fraction: float = float(order.get("patience",0)) / maxf(1.0,float(order.get("max_patience",38)))
	if fraction <= 0:
		return {"mood":"lost","text":"等得太久了，下次再来吧。"}
	if float(order.get("ready_age",0)) > Cuisine.HOT_WINDOW:
		return {"mood":"okay","text":"菜有些凉了，趁热上桌会更好。"}
	if fraction <= 0.5:
		return {"mood":"okay","text":"味道不错，就是等得有点久。"}
	if Cuisine.quality(order) >= 3:
		if order.has("preference") and not Cuisine.matches(order):
			return {"mood":"satisfied","text":"火候很好，下次想吃%s口味。" % Cuisine.SEASONINGS[int(order.preference)]}
		return {"mood":"satisfied","text":"火候真好，摆盘也用心！" if order.get("plated",false) else "外香内嫩，主厨火候真好！"}
	if order.has("preference") and not Cuisine.matches(order):
		return {"mood":"satisfied","text":"鲜鱼不错，下次想吃%s口味。" % Cuisine.SEASONINGS[int(order.preference)]}
	if order.get("prepped",false):
		return {"mood":"satisfied","text":"入味又鲜嫩，备料很用心。"}
	return {"mood":"satisfied","text":"鲜美又及时，下次还来！"}
