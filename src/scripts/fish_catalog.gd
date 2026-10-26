extends RefCounted
## Shared species data. Index order is stable for fish spawning and visual variants.
const SPECIES: Array[Dictionary] = [
	{"id":"orange", "name":"橘鳍鱼", "value":18, "weight":1, "hp":1, "speed":1.7, "alert":5.0, "radius":1.05, "behavior":"calm", "hint":"近岸常见，适合练习瞄准"},
	{"id":"blue", "name":"青背鱼", "value":32, "weight":2, "hp":2, "speed":2.5, "alert":8.0, "radius":1.1, "behavior":"cautious", "hint":"容易警觉，靠近后迅速出手"},
	{"id":"lantern", "name":"灯笼鱼", "value":55, "weight":3, "hp":3, "speed":2.1, "alert":7.0, "radius":1.2, "behavior":"deep", "hint":"深水出没，留意返航气瓶量"},
	{"id":"sardine", "name":"银梭沙丁鱼", "value":24, "weight":1, "hp":1, "speed":4.4, "alert":9.0, "radius":0.6, "behavior":"school", "hint":"鱼群游速快，预判前进方向"},
	{"id":"puffer", "name":"星斑河豚", "value":48, "weight":2, "hp":3, "speed":1.6, "alert":7.0, "radius":0.85, "behavior":"armored", "hint":"膨胀时防御更强，等待收缩再猎捕"},
	{"id":"lionfish", "name":"赤鬃狮子鱼", "value":70, "weight":2, "hp":3, "speed":2.2, "alert":9.0, "radius":0.9, "behavior":"venom", "hint":"毒棘危险，保持距离猎捕"},
	{"id":"tuna", "name":"蓝鳍金枪鱼", "value":110, "weight":4, "hp":5, "speed":6.0, "alert":13.0, "radius":1.0, "behavior":"swift", "hint":"冲刺极快，升级鱼叉后更易猎捕"},
	{"id":"moray", "name":"岩纹海鳗", "value":100, "weight":3, "hp":4, "speed":3.7, "alert":10.0, "radius":0.8, "behavior":"ambush", "hint":"岩区伏击，接近时留意突袭"},
	{"id":"reef_shark", "name":"灰礁鲨", "value":180, "weight":6, "hp":8, "speed":4.8, "alert":16.0, "radius":1.3, "behavior":"predator", "hint":"会主动追击，准备好装备与逃生路线"},
]

static func has_id(id: String) -> bool:
	for species in SPECIES:
		if species.id == id:
			return true
	return false
