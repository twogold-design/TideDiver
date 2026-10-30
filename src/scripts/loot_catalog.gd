extends RefCounted
## Collectibles share the normal cargo and warehouse; chest contents stay local to a dive.
const ITEMS := {
	"sea_glass":{"id":"sea_glass","name":"海玻璃","value":24,"weight":1,"kind":"sea_glass"},
	"ancient_coin":{"id":"ancient_coin","name":"古硬币","value":48,"weight":1,"kind":"ancient_coin"},
	"amber_shard":{"id":"amber_shard","name":"琥珀碎片","value":75,"weight":1,"kind":"amber_shard"},
	"conch":{"id":"conch","name":"海螺","value":40,"weight":2,"kind":"conch"},
	"captain_astrolabe":{"id":"captain_astrolabe","name":"船长的星海罗盘","value":480,"weight":3,"kind":"captain_astrolabe"},
	"seagrass":{"id":"seagrass","name":"鲜海草","value":16,"weight":1,"kind":"seagrass"},
}
const COASTAL_KINDS := ["pearl","sea_glass","conch","ancient_coin","pearl","amber_shard","sea_glass"]
const CHEST_TABLE := [
	{"id":"pearl","chance":28}, {"id":"sea_glass","chance":20},
	{"id":"ancient_coin","chance":18}, {"id":"amber_shard","chance":12},
	{"id":"conch","chance":14}, {"id":"oxygen","chance":8},
]

static func pickup_info(kind: String) -> Dictionary:
	if ITEMS.has(kind):
		return ITEMS[kind].duplicate(true)
	match kind:
		"pearl": return {"id":"pearl","name":"月光珍珠","value":28,"weight":1,"kind":"pearl"}
		"chest", "treasure": return {"id":"chest","name":"沉船宝箱","value":90,"weight":3,"kind":"chest"}
		"oxygen", "air": return {"id":"oxygen","name":"应急气瓶","value":0,"weight":0,"kind":"oxygen","air":35.0}
	return {}

static func cargo_entry(kind: String) -> Dictionary:
	var info: Dictionary = pickup_info(kind)
	return {} if info.is_empty() or info.kind == "oxygen" else info

static func roll_chest(seed_value: int) -> Array[Dictionary]:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var result: Array[Dictionary] = []
	var count: int = random.randi_range(1,3)
	for index in range(count):
		var draw: int = random.randi_range(1,100)
		for reward: Dictionary in CHEST_TABLE:
			draw -= int(reward.chance)
			if draw <= 0:
				result.append(pickup_info(reward.id))
				break
	return result

static func prepare_chest(item: Dictionary, seed_value: int) -> Array:
	if not item.has("loot_remaining"):
		var contents: Array[Dictionary] = roll_chest(seed_value)
		item["loot_seed"] = seed_value
		item["loot_contents"] = contents.duplicate(true)
		item["loot_remaining"] = contents.duplicate(true)
		item["loot_opened"] = false
	return item.loot_remaining.duplicate(true)

static func claim_chest(item: Dictionary, free_weight: int, air_space: float) -> Dictionary:
	# A repeated interaction never rolls again. Each claimed entry leaves the cache once.
	if not item.has("loot_remaining"):
		prepare_chest(item,int(item.get("loot_seed",0)))
	item["loot_opened"] = true
	var remaining: Array[Dictionary] = []
	var cargo: Array[Dictionary] = []
	var space: int = maxi(0,free_weight)
	var missing_air: float = maxf(0.0,air_space)
	var air := 0.0
	for saved: Dictionary in item.loot_remaining:
		var kind: String = str(saved.get("id",""))
		var info: Dictionary = pickup_info(kind)
		if info.is_empty():
			remaining.append(saved.duplicate(true))
			continue
		if kind == "oxygen":
			var available: float = clampf(float(saved.get("air",35.0)),0.0,35.0)
			var used: float = minf(available,missing_air)
			air += used
			missing_air -= used
			if available > used + 0.00001:
				info.air = available - used
				remaining.append(info)
		elif int(info.weight) <= space:
			cargo.append(info)
			space -= int(info.weight)
		else:
			remaining.append(info)
	item["loot_remaining"] = remaining
	return {"cargo":cargo,"air":air,"remaining":remaining.duplicate(true),"complete":remaining.is_empty()}
