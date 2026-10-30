extends SceneTree
## Fixed chest rewards, lossless partial claims, canonical economy and real pickups.
const Loot = preload("res://scripts/loot_catalog.gd")
const Art = preload("res://scripts/loot_art.gd")
const P = preload("res://scripts/progression.gd")
const Ocean = preload("res://scripts/ocean_config.gd")
const SEABED_ITEMS := ["sea_glass","ancient_coin","amber_shard","conch"]
class MemoryProgression extends "res://scripts/progression.gd":
	var saves := 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	_test_rewards_and_claims()
	_test_economy_and_distribution()
	await _test_actual_pickups()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("%s: Tide Diver varied seabed loot (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func _test_rewards_and_claims() -> void:
	var expected_value := 0
	var registered := true
	for id in Loot.ITEMS:
		var info: Dictionary = Loot.pickup_info(id)
		registered = registered and info.id == id and info.weight > 0 and info.value > 0 and P.GOODS[id] == Loot.ITEMS[id]
		expected_value += int(info.value)
	_check(registered and Loot.ITEMS.size() == 6 and expected_value == 683, "Seabed finds, the captain's treasure and harvested grass have canonical weights and sale values")
	var seen: Dictionary = {}
	var lengths: Dictionary = {}
	var valid := true
	for seed_value in range(256):
		var contents: Array[Dictionary] = Loot.roll_chest(seed_value)
		lengths[contents.size()] = true
		valid = valid and contents.size() >= 1 and contents.size() <= 3 and contents == Loot.roll_chest(seed_value)
		for reward: Dictionary in contents:
			seen[reward.id] = true
			valid = valid and reward == Loot.pickup_info(reward.id) and reward.id != "chest"
	_check(valid and lengths.size() == 3 and seen.size() == 6, "Fixed seeds reproducibly cover one-to-three rewards and every weighted pearl, relic and air outcome")
	var first: Array[Dictionary] = Loot.roll_chest(42)
	first[0].value = 999999
	_check(Loot.roll_chest(42)[0].value != 999999, "Reward rolls do not share mutable catalog or previous-roll dictionaries")
	var cached: Dictionary = {}
	var initial: Array = Loot.prepare_chest(cached,78231)
	_check(Loot.prepare_chest(cached,99881) == initial and cached.loot_seed == 78231, "Repeated chest preparation preserves its first seed and contents")
	var contents: Array = [Loot.pickup_info("conch"),Loot.pickup_info("sea_glass"),Loot.pickup_info("oxygen")]
	var chest: Dictionary = {"loot_seed":5,"loot_contents":contents.duplicate(true),"loot_remaining":contents.duplicate(true)}
	var claimed: Dictionary = Loot.claim_chest(chest,1,10.0)
	_check(claimed.cargo.size() == 1 and claimed.cargo[0].id == "sea_glass" and claimed.air == 10.0 and not claimed.complete, "A partial claim takes only what fits and only the missing air")
	_check(chest.loot_remaining.size() == 2 and chest.loot_remaining[0].id == "conch" and chest.loot_remaining[1].air == 25.0 and chest.loot_contents[2].air == 35.0, "The heavy reward and unused bottle air remain in the chest without altering its original roll")
	var waiting: Array = chest.loot_remaining.duplicate(true)
	claimed = Loot.claim_chest(chest,0,0.0)
	_check(claimed.cargo.is_empty() and claimed.air == 0.0 and chest.loot_remaining == waiting, "A full bag and full tank neither discard nor reroll any remaining reward")
	_check(Loot.prepare_chest(chest,11111) == waiting and chest.loot_seed == 5, "Changing a retry seed cannot reroll an opened, partially claimed chest")
	claimed = Loot.claim_chest(chest,2,25.0)
	_check(claimed.complete and claimed.cargo.size() == 1 and claimed.cargo[0].id == "conch" and claimed.air == 25.0, "A later claim collects the exact remaining shell and bottle air")
	claimed = Loot.claim_chest(chest,100,100.0)
	_check(claimed.complete and claimed.cargo.is_empty() and claimed.air == 0.0, "An exhausted reward cache cannot duplicate loot")
	var art: Node3D = Art.build("chest")
	_check(art.get_node_or_null("Lid") != null and not art.get_node("Contents").visible, "Chest art starts closed with a genuine lid joint and concealed contents")
	Art.set_chest_open(art)
	_check(art.get_node("Lid").rotation.x > 1.0 and art.get_node("Contents").visible, "Opening the chest lifts the same hinged lid and reveals its inner model")
	art.free()
	var meshes_shared := true
	for id in Loot.ITEMS:
		var a: Node3D = Art.build(id)
		var b: Node3D = Art.build(id)
		meshes_shared = meshes_shared and a.get_node("Relic").mesh == b.get_node("Relic").mesh and a.get_node("Relic").mesh.get_surface_count() > 0
		meshes_shared = meshes_shared and a.find_children("*","CollisionObject3D",true,false).is_empty()
		a.free()
		b.free()
	_check(meshes_shared, "Distinct collectible models reuse actual mesh resources and add no collision")

func _test_economy_and_distribution() -> void:
	var memory := MemoryProgression.new()
	memory.persistence_enabled = false
	memory._apply_save_data({"version":4,"day":7,"coins":99,"inventory":{"orange":2,"chest":1}})
	var old_compatible: bool = memory.inventory.orange == 2 and memory.inventory.chest == 1 and memory.day == 7 and memory.coins == 99
	for id in Loot.ITEMS:
		old_compatible = old_compatible and memory.inventory.get(id,-1) == 0
	_check(old_compatible and P.GOODS.chest.value == 90 and P.RECIPES.size() == 3, "V4 saves keep old fish, chest value and recipes while new collectible stock begins at zero")
	var cargo: Array = []
	for id in SEABED_ITEMS:
		cargo.append({"id":id,"value":999999})
	var result: Dictionary = memory.complete_dive(cargo,false,42)
	var stored: bool = result.count == 4 and memory.total_fish == 0 and cargo.is_empty()
	for id in SEABED_ITEMS:
		stored = stored and memory.inventory[id] == 1
	_check(stored and memory.inventory.orange == 2 and memory.inventory.chest == 1, "All four finds enter the ordinary warehouse without counting as fish or altering previous stock")
	var restored := MemoryProgression.new()
	restored.persistence_enabled = false
	restored._apply_save_data(memory._save_data().duplicate(true))
	_check(restored.inventory == memory.inventory and restored._save_data().version == 4, "The unchanged save format round-trips new collectible inventory")
	var value := 0
	for id in SEABED_ITEMS:
		value += restored.sell(id,1)
	_check(value == 187 and restored.coins == 286 and restored.inventory.orange == 2 and restored.inventory.chest == 1, "Selling the new finds pays canonical187G and leaves original fish and legacy treasure intact")
	_check(restored.sell("chest",1) == 90 and restored.inventory.chest == 0, "A chest stored by an older game can still be sold for its original90G")
	var rescued := MemoryProgression.new()
	rescued.persistence_enabled = false
	cargo.clear()
	for id in SEABED_ITEMS:
		cargo.append({"id":id,"value":999999})
	cargo.append({"id":"chest"})
	result = rescued.complete_dive(cargo,true,42)
	_check(result.earned == 96 and rescued.inventory_total() == 0 and rescued.total_fish == 0, "Rescue applies the existing35 percent rule to canonical collectible and legacy chest values")
	var points: Array = Ocean.pickup_points()
	var types: Dictionary = {}
	var valid := points.size() == 53
	for point: Dictionary in points:
		types[point.kind] = int(types.get(point.kind,0))+1
		valid = valid and not Loot.pickup_info(point.kind).is_empty() and point.position.y >= Ocean.seabed_height(point.position.x,point.position.z)+0.99
	for id in SEABED_ITEMS:
		valid = valid and types.has(id)
	_check(valid and types.get("chest",0) == 10 and types.get("oxygen",0) == 26 and types.get("pearl",0) > 0, "The remaining 53 outer-ocean points retain air stations, chests, pearls and all four finds")

func _test_actual_pickups() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var memory := MemoryProgression.new()
	memory.persistence_enabled = false
	game.progress = memory
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	game.start_dive(false,false)
	_check(game.pickups.size() == 65 and game.fish.size() == game.fish_population_count() and game.pickups[0].kind == "pearl" and game.pickups[9].kind == "oxygen" and game.pickups[10].kind == "oxygen", "The real ocean includes65 pickups, the expected huntable fish and the original first pearl and two indexed air stations")
	for id in SEABED_ITEMS:
		var selected: Dictionary = {}
		for item: Dictionary in game.pickups:
			if item.kind == id and item.active:
				selected = item
				break
		if selected.is_empty():
			_check(false,"An actual world collectible exists: "+id)
			continue
		game.cargo.clear()
		game.player.position = selected.node.position
		_check(game.context_hint() == "F  采集"+str(Loot.ITEMS[id].name),"The nearby collectible identifies itself before interaction: "+id)
		game.interact()
		_check(game.cargo.size() == 1 and game.cargo[0] == Loot.cargo_entry(id) and not selected.active and not selected.node.visible,"Actual F interaction collects the correct named, weighted and valued object: "+id)
		_check(game.loot_feedback_timer > 0.0 and game.loot_feedback_title == "采集成功" and game.loot_feedback.size() == 1 and game.loot_feedback[0].contains(str(Loot.ITEMS[id].name)),"Collecting the actual object shows its own named result card: "+id)
	var chest: Dictionary = {}
	for item: Dictionary in game.pickups:
		if item.kind == "chest" and item.active:
			chest = item
			break
	_check(not chest.is_empty() and chest.has("loot_remaining"), "An actual chest receives its fixed reward cache when spawned")
	if not chest.is_empty() and chest.has("loot_remaining"):
		var original: Array = chest.loot_remaining.duplicate(true)
		game.cargo = [{"id":"orange","weight":memory.capacity()}]
		game.oxygen = memory.oxygen_max()
		game.player.position = chest.node.position
		game.interact()
		game.interact()
		_check(chest.active and chest.node.visible and chest.loot_remaining == original and game.cargo.size() == 1, "Repeatedly opening a full-bag chest keeps every cached reward in the same visible chest")
		_check(chest.node.get_node("Lid").rotation.x > 1.0, "The real chest opens visibly even when its rewards must wait for space")
		game.cargo.clear()
		memory.tank_level = 3
		game.oxygen = 5.0
		var expected_cargo: Array = []
		var expected_air := 0.0
		for reward: Dictionary in original:
			if reward.id == "oxygen":
				expected_air += float(reward.air)
			else:
				expected_cargo.append(Loot.cargo_entry(reward.id))
		game.interact()
		_check(game.cargo == expected_cargo and is_equal_approx(game.oxygen,5.0+expected_air) and not chest.active and chest.node.visible and not chest.node.get_node("Contents").visible and chest.loot_remaining.is_empty(), "Making room claims the original rewards once, leaving an inactive, visibly opened empty chest")
		var collected: Array = game.cargo.duplicate(true)
		game.interact()
		_check(game.cargo == collected and memory.saves == 0, "Re-interacting cannot duplicate the opened chest or save transient loot state")
	_test_actual_feedback(game,memory)
	_test_actual_treasure(game,memory)
	game.free()
	await process_frame

func _test_actual_feedback(game: Node, memory: MemoryProgression) -> void:
	var chest: Dictionary = {}
	for item: Dictionary in game.pickups:
		if item.kind == "chest" and item.active:
			chest = item
			break
	_check(not chest.is_empty(),"An unclaimed real chest is available for controlled feedback interaction")
	if chest.is_empty():
		return
	# Supply known cached contents so the UI must describe exact claims and leftovers.
	chest.loot_contents = [Loot.pickup_info("sea_glass"),Loot.pickup_info("sea_glass"),Loot.pickup_info("oxygen")]
	chest.loot_remaining = chest.loot_contents.duplicate(true)
	chest.loot_opened = false
	game.player.position = chest.node.position
	game.cargo = [{"id":"orange","weight":memory.capacity()}]
	game.oxygen = memory.oxygen_max()
	_check(game.context_hint() == "F  打开沉船宝箱","A closed chest offers an opening interaction")
	game.interact()
	_check(game.loot_feedback.is_empty() and game.loot_feedback_note == "背包空间不足，剩余物品留在箱内" and game.context_hint() == "F  领取宝箱剩余物品","A full bag reports untouched rewards and offers retrieval from the opened chest")
	game.cargo.clear()
	game.oxygen = memory.oxygen_max()-10.0
	game.interact()
	_check(game.loot_feedback_title == "领取宝箱物品" and game.loot_feedback == ["海玻璃 ×2  ·  2 kg  ·  价值 48 G","应急气瓶  ·  气瓶量 +10.0"],"Actual chest feedback groups repeated loot and reports exact weight, sale value and granted air")
	_check(chest.active and chest.loot_remaining.size() == 1 and chest.loot_remaining[0].air == 25.0 and game.loot_feedback_note == "未用补气留在箱内，需要时可继续领取","The result explains residual bottle air retained in the same chest")
	var feedback_before: Array = game.loot_feedback.duplicate()
	var time_before: float = game.loot_feedback_timer
	game.toggle_pause()
	game._physics_process(2.0)
	_check(game.state == "paused" and game.loot_feedback_timer == time_before and game.loot_feedback == feedback_before,"Pausing freezes the current reward card without losing its contents")
	game.toggle_pause()
	game._physics_process(0.25)
	_check(game.state == "dive" and is_equal_approx(game.loot_feedback_timer,time_before-0.25),"Resuming advances the existing feedback timer")
	game.oxygen = memory.oxygen_max()-25.0
	game.player.position = chest.node.position
	game.interact()
	_check(game.loot_feedback == ["应急气瓶  ·  气瓶量 +25.0"] and game.loot_feedback_note.is_empty() and not chest.active,"The final claim describes only its actual remaining air and clears the residual note")
	var target: Dictionary = game.fish[0]
	game.cargo.clear()
	target.hp = 1
	target.alive = true
	target.armor = false
	game._hit_fish(target,100)
	_check(not target.alive and game.catch_timer > 0.0 and game.loot_feedback_timer == 0.0 and game.loot_feedback.is_empty(),"A real fish capture replaces the previous loot result card")
	var pearl: Dictionary = game.pickups[0]
	game.player.position = pearl.node.position
	game.interact()
	_check(game.catch_timer == 0.0 and game.loot_feedback_timer > 0.0 and game.loot_feedback_title == "采集成功","A later real pearl pickup replaces the fish capture card")
	game.finish_dive(false)
	_check(game.state == "dock" and game.loot_feedback_timer == 0.0 and game.loot_feedback.is_empty(),"Returning to shore clears transient reward feedback")
	game.start_dive(false,false)
	_check(game.loot_feedback_timer == 0.0 and game.loot_feedback_title.is_empty() and game.loot_feedback_note.is_empty(),"A fresh dive begins without a previous dive's result card")

func _test_actual_treasure(game: Node, memory: MemoryProgression) -> void:
	var treasures: Array = game.pickups.filter(func(item: Dictionary) -> bool: return item.kind == "captain_astrolabe")
	_check(treasures.size() == 1, "Each dive has exactly one special captain's treasure")
	if treasures.size() != 1:
		return
	var treasure: Dictionary = treasures[0]
	var wreck: Node3D = game.explorable_wreck
	_check(treasure.home.is_equal_approx(wreck.treasure_position()) and wreck.contains_point(treasure.home,0), "The captain's astrolabe is inside the wreck on the upper bridge chart table")
	var route: Array = wreck.get_meta("treasure_route",[])
	var traversable: bool = route.size() >= 5
	for index in range(1,route.size()):
		traversable = traversable and not game.player.test_move(Transform3D(Basis.IDENTITY,route[index-1]),route[index]-route[index-1])
	_check(traversable, "The actual diver can swim from the hold through the bridge to the special treasure")
	game.player.position = route[-1]
	game.cargo = [{"id":"orange","weight":memory.capacity()}]
	game.interact()
	_check(treasure.active and treasure.node.visible and game.cargo.size() == 1 and game.capacity_warning_timer > 0, "A full bag leaves the special treasure available and reports its weight")
	game.cargo.clear()
	game.interact()
	_check(game.cargo.size() == 1 and game.cargo[0] == Loot.pickup_info("captain_astrolabe") and not treasure.active and not treasure.node.visible, "Collecting the named special treasure grants its canonical 3kg and 480G item once")
	game.interact()
	_check(game.cargo.size() == 1, "A second interaction cannot duplicate the special treasure")
	game.finish_dive(false)
	_check(memory.inventory.get("captain_astrolabe",0) == 1, "Returning to shore stores the special treasure in the ordinary warehouse")
	var restored := MemoryProgression.new()
	restored.persistence_enabled = false
	restored._apply_save_data(memory._save_data().duplicate(true))
	_check(restored.inventory.get("captain_astrolabe",0) == 1 and restored.sell("captain_astrolabe",1) == 480, "The special treasure survives save reload and sells for its canonical value")
