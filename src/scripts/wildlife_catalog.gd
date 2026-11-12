extends RefCounted
## Stable discovery IDs: huntable fish and named ornamental residents share one field guide.
const Fish = preload("res://scripts/fish_catalog.gd")
const FISH_HABITATS := [
	"潮溪湾近岸、各潜点浅水区", "近岸礁区、外海巡游水域", "深水沙坡与峡谷", "开放水域与散游鱼群",
	"礁石与珊瑚外围", "礁石及沉船外围", "外海开阔水域", "各潜点岩洞与石缝",
	"外海礁区", "各潜点海床的岩石边缘", "外礁与珊瑚外围", "岩礁与沉船外围", "沙坡和沉船外缘", "外海开阔水域",
]
const FISH_REWARDS := [25,25,50,25,50,50,80,80,80,80,25,50,25,80]
const ORNAMENTAL := [
	{"id":"reef_clown","name":"小丑鱼","reward":25,"habitat":"琥珀珊瑚礁的海葵丛","description":"成对在海葵附近穿梭。放慢速度，让它留在视野中央。"},
	{"id":"reef_chromis","name":"蓝绿雀鲷","reward":25,"habitat":"琥珀珊瑚礁的珊瑚上方","description":"蓝绿色小鱼在珊瑚上方结成松散的小群。"},
	{"id":"reef_butterfly","name":"蝴蝶鱼","reward":50,"habitat":"琥珀珊瑚礁的沙道与珊瑚边缘","description":"留意侧扁的鱼身，在珊瑚之间持续跟随观察。"},
	{"id":"reef_tang","name":"蓝吊","reward":50,"habitat":"琥珀珊瑚礁的外侧珊瑚带","description":"明亮的蓝色身影沿着珊瑚带巡游，是适合静观的礁鱼。"},
	{"id":"reef_anthias","name":"金花鲈","reward":25,"habitat":"琥珀珊瑚礁的珊瑚上方","description":"暖色的小鱼在礁顶散开又聚拢，给珊瑚花园添上一层流动的颜色。"},
	{"id":"marine_ShoreCrab","name":"岸蟹","reward":25,"habitat":"近岸、沉船外围及月贝环礁海床","description":"贴着海床移动的小住客。观察时留意石边和沙地之间的空隙。"},
	{"id":"marine_SeaUrchin","name":"海胆","reward":25,"habitat":"六个潜点的海床","description":"圆形的棘刺轮廓藏在海底细节中，停下来更容易发现。"},
	{"id":"marine_SeaCucumber","name":"海参","reward":25,"habitat":"近岸、峡谷、南潮石林及月贝环礁","description":"沿着沙地缓慢活动的海床住客，容易和地面的颜色混在一起。"},
	{"id":"marine_CleanerShrimp","name":"清洁虾","reward":50,"habitat":"近岸、峡谷、沉船、珊瑚礁及环礁","description":"小巧的身体和细长触须在岩石边若隐若现，适合靠近后稳定观察。"},
	{"id":"marine_Seahorse","name":"海马","reward":50,"habitat":"近岸、琥珀珊瑚礁及月贝环礁","description":"竖直的小小身影悬在海床上方，在海草和珊瑚附近仔细寻找。"},
	{"id":"marine_Cuttlefish","name":"乌贼","reward":50,"habitat":"峡谷、沉船、珊瑚礁、石林及环礁","description":"舒展的腕足和柔软的外形随水摆动，观察时保持平稳跟随。"},
	{"id":"marine_GreenTurtle","name":"绿海龟","reward":80,"habitat":"琥珀珊瑚礁及月贝环礁","description":"宽大的前鳍缓缓划水，绕开它的去路，在一旁观察。"},
	{"id":"sand_ray","name":"埋沙鳐鱼","reward":80,"habitat":"月贝环礁的月光沙台附近","description":"平时伏在沙下，靠近后会扬起细沙游走。静潜能让观察更从容。"},
	{"id":"thresher_shark","name":"长尾鲨","reward":80,"habitat":"双门遗迹的潮流大峡谷，偶尔出现","description":"修长的尾部在峡谷水流中划出弧线，远远跟随也能完成观察。"},
	{"id":"lightning_clam","name":"闪电贝","reward":80,"habitat":"琥珀珊瑚礁沙道边的独立石洞","description":"红橙色触须围着双瓣贝壳，留意外套膜边缘扫过的蓝白闪带。"},
]
static var _entries: Array[Dictionary] = []
static var _by_id: Dictionary = {}

static func _prepare() -> void:
	if not _entries.is_empty():
		return
	for kind in range(Fish.SPECIES.size()):
		var fish: Dictionary = Fish.SPECIES[kind]
		var record := {"id":fish.id,"name":fish.name,"reward":FISH_REWARDS[kind],"habitat":FISH_HABITATS[kind],"description":fish.hint,"catchable":true,"kind":kind}
		_entries.append(record)
		_by_id[record.id] = record
	for source: Dictionary in ORNAMENTAL:
		var record: Dictionary = source.duplicate(true)
		record["catchable"] = false
		record["kind"] = -1
		_entries.append(record)
		_by_id[record.id] = record

static func entries() -> Array[Dictionary]:
	_prepare()
	return _entries

static func entry(id: String) -> Dictionary:
	_prepare()
	return _by_id.get(id,{})
