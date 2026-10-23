extends RefCounted
## Feedback follows actual order state and remaining patience; it never changes prices.
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
	if fraction <= 0.5:
		return {"mood":"okay","text":"味道不错，就是等得有点久。"}
	return {"mood":"satisfied","text":"鲜美又及时，下次还来！"}
