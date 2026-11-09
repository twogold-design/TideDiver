extends SceneTree
## Catalog validation, durable first-discovery rewards and legacy saves.
const Catalog = preload("res://scripts/wildlife_catalog.gd")
const Progress = preload("res://scripts/progression.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	var saves := 0
	func save_game() -> void:
		saves += 1

var checks := 0
var failures := 0

func _init() -> void:
	_test_catalog()
	_test_rewards()
	_test_validation_and_migration()
	_test_unread_records()
	_test_persistence_and_reset()
	print("%s: Tide Diver wildlife catalog and discovery rewards (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+description)

func _test_catalog() -> void:
	var ids := {}
	var catchable := 0
	var complete := true
	for record: Dictionary in Catalog.entries():
		complete = complete and not ids.has(record.id) and not str(record.name).is_empty() and not str(record.habitat).is_empty() and not str(record.description).is_empty() and int(record.reward) > 0
		ids[record.id] = true
		catchable += 1 if record.catchable else 0
	_check(Catalog.entries().size() == 29 and ids.size() == 29 and catchable == 14, "The field guide contains fourteen huntable fish and fifteen named ornamental species")
	_check(complete, "Every unique catalog record has a name, habitat, description and a positive first-discovery reward")
	_check(Catalog.entry("not_a_species").is_empty() and Catalog.entry("moray").kind == 7 and not Catalog.entry("lightning_clam").catchable, "Catalog lookup keeps canonical fish IDs and excludes the clam from captures")

func _test_rewards() -> void:
	var p := MemoryProgression.new()
	var original_inventory: Dictionary = p.inventory.duplicate(true)
	var first: int = p.discover_species("orange","observed")
	_check(first == Catalog.entry("orange").reward and p.coins == first and p.has_discovery("orange") and p.discoveries.orange.method == "observed", "A first observation unlocks its record and credits the advertised reward")
	_check(p.saves == 1 and p.inventory == original_inventory and p.total_fish == 0, "Discovery immediately saves without inventing catches or inventory")
	_check(p.discover_species("orange","observed") == 0 and p.discover_species("orange","caught") == 0 and p.coins == first and p.saves == 1, "Repeated observation and later capture never pay or save a second reward")
	var caught: int = p.discover_species("moray","caught")
	_check(caught == Catalog.entry("moray").reward and p.discoveries.moray.method == "caught" and p.saves == 2, "One successful catch can unlock the same catalog with its capture acquisition method")
	_check(p.discover_species("lightning_clam","caught") == 0 and not p.has_discovery("lightning_clam") and p.saves == 2, "An ornamental animal cannot be unlocked by an impossible capture event")
	_check(p.discover_species("lightning_clam","observed") == Catalog.entry("lightning_clam").reward and p.has_discovery("lightning_clam"), "The ornamental clam can be unlocked by observation")
	var coins_before: int = p.coins
	_check(p.discover_species("unknown","observed") == 0 and p.discover_species("blue","invalid") == 0 and p.coins == coins_before and not p.has_discovery("blue"), "Unknown IDs and invalid acquisition methods are rejected")
	p.coins = Progress.MAX_COINS-7
	_check(p.discover_species("reef_clown","observed") == 7 and p.coins == Progress.MAX_COINS and p.has_discovery("reef_clown"), "A discovery near the coin cap credits only the available headroom")
	_check(p.discover_species("sand_ray","observed") == 0 and p.has_discovery("sand_ray") and p.coins == Progress.MAX_COINS, "A full wallet still unlocks the record exactly once without overflowing")
	p.coins -= 100
	_check(p.discover_species("sand_ray","observed") == 0 and p.coins == Progress.MAX_COINS-100, "Spending after a capped discovery cannot reclaim an already-consumed first reward")
	p.complete_dive([{"id":"orange"}],true,20)
	_check(p.has_discovery("moray") and p.has_discovery("lightning_clam"), "Rescue settlement does not erase discoveries earned during the dive")

func _test_validation_and_migration() -> void:
	var p := MemoryProgression.new()
	p._apply_save_data({"coins":120,"inventory":{"orange":3,"moray":1,"pearl":2}})
	_check(p.discoveries == {"orange":{"method":"caught","seen":true},"moray":{"method":"caught","seen":true}} and p.coins == 120 and p.saves == 0 and p.unread_discoveries() == 0, "Legacy fish inventory imports earlier captures as read without granting retroactive coins or writing on load")
	_check(p.discover_species("orange","observed") == 0 and p.coins == 120, "A migrated legacy capture cannot produce another first-discovery reward")
	p._apply_save_data({"coins":200,"inventory":{"blue":4},"discoveries":{"orange":{"method":"observed","reward":999999},"blue":{"method":"caught"},"unknown":{"method":"observed"},"reef_clown":{"method":"caught"},"moray":true,"stonefish":{"method":5},"tuna":{"method":"cheat"}}})
	_check(p.discoveries == {"orange":{"method":"observed","seen":true},"blue":{"method":"caught","seen":true}} and p.coins == 200 and p.unread_discoveries() == 0, "Loading accepts only known species and valid methods, strips injected fields and marks records without unread flags as read")
	p._apply_save_data({"coins":200,"inventory":{"blue":4},"discoveries":{}})
	_check(p.discoveries.is_empty(), "A current save's explicit empty field is not reinterpreted as a legacy save")
	p._apply_save_data({"discoveries":["orange","orange"]})
	_check(p.discoveries.is_empty(), "Malformed discovery containers and duplicate arrays do not create unlocks")
	p._apply_save_data({"discoveries":{"orange":{"method":"observed"}}})
	var saved: Dictionary = p._save_data().duplicate(true)
	var loaded := MemoryProgression.new()
	loaded._apply_save_data(saved)
	_check(loaded.discoveries == p.discoveries and loaded.coins == p.coins and loaded.discover_species("orange","caught") == 0, "A current save round trip preserves the consumed reward and acquisition method")

func _test_unread_records() -> void:
	var p := MemoryProgression.new()
	p.mark_discoveries_seen()
	_check(p.unread_discoveries() == 0 and p.saves == 0, "An empty guide has no unread items and marking it read causes no save")
	p.discover_species("orange","observed")
	p.discover_species("moray","caught")
	var coins: int = p.coins
	_check(p.unread_discoveries() == 2 and p.discoveries.orange.seen == false and p.discoveries.moray.seen == false, "New observations and captures both create unread records")
	p.discover_species("orange","caught")
	_check(p.unread_discoveries() == 2 and p.coins == coins and p.saves == 2, "Duplicate discoveries neither duplicate unread counts nor repeat payment or saving")
	var loaded := MemoryProgression.new()
	loaded._apply_save_data(p._save_data().duplicate(true))
	_check(loaded.unread_discoveries() == 2 and loaded.discoveries == p.discoveries, "Unread flags survive the ordinary save payload round trip")
	loaded.mark_discoveries_seen()
	_check(loaded.unread_discoveries() == 0 and loaded.saves == 1 and loaded.coins == coins and loaded.discoveries.moray.method == "caught", "Reading the guide marks all records read in one save without changing coins or acquisition methods")
	loaded.mark_discoveries_seen()
	loaded.discover_species("moray","observed")
	_check(loaded.saves == 1 and loaded.unread_discoveries() == 0, "Reopening a read guide or rediscovering a read species does not rearm its indicator")
	loaded._apply_save_data({"discoveries":{"orange":{"method":"observed","seen":false},"blue":{"method":"caught","seen":true},"moray":{"method":"caught","seen":"false"},"tuna":{"method":"observed","seen":0},"stonefish":{"method":"caught","seen":null}}})
	_check(loaded.unread_discoveries() == 1 and not loaded.discoveries.orange.seen and loaded.discoveries.blue.seen and loaded.discoveries.moray.seen and loaded.discoveries.tuna.seen and loaded.discoveries.stonefish.seen, "Only actual boolean flags are loaded; strings, numbers and null default to already read")

func _test_persistence_and_reset() -> void:
	var p := Progress.new()
	p.save_path = "res://tests/temp/bestiary_progress.json"
	for suffix: String in ["",".bak",".tmp"]:
		var file: String = ProjectSettings.globalize_path(p.save_path+suffix)
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	p.discover_species("moray","observed")
	var loaded := Progress.new()
	loaded.save_path = p.save_path
	loaded.load_game()
	_check(loaded.has_discovery("moray") and loaded.coins == Catalog.entry("moray").reward and loaded.unread_discoveries() == 1, "The real atomic JSON save retains the discovery, reward and unread indicator before returning from the dive")
	_check(loaded.discover_species("moray","caught") == 0, "Reloading the real save cannot pay the same reward twice")
	loaded.mark_discoveries_seen()
	var reread := Progress.new()
	reread.save_path = p.save_path
	reread.load_game()
	_check(reread.unread_discoveries() == 0 and reread.has_discovery("moray") and reread.coins == loaded.coins, "Marking the guide read persists to the actual JSON file")
	_check(loaded.reset_game() and loaded.discoveries.is_empty() and loaded.coins == 0 and loaded.unread_discoveries() == 0, "Confirmed new game clears all discovery records, unread indicators and earned coins")
	var fresh := Progress.new()
	fresh.save_path = p.save_path
	fresh.load_game()
	_check(fresh.discoveries.is_empty() and fresh.coins == 0 and fresh.discover_species("moray","caught") == Catalog.entry("moray").reward, "The new run can earn discovery rewards anew and old backup data stays reset")
	for suffix: String in ["",".bak",".tmp"]:
		var file: String = ProjectSettings.globalize_path(p.save_path+suffix)
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
