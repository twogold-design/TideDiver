extends SceneTree
## Bulk sales use canonical fish identities and preserve every cooking ingredient.
const P = preload("res://scripts/progression.gd")
const Fish = preload("res://scripts/fish_catalog.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	var saves := 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func run() -> void:
	test_batch()
	test_rejections()
	await test_ui()
	print("%s: Tide Diver non-cooking fish sale (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)

func test_batch() -> void:
	var progress := MemoryProgression.new()
	progress.coins = 17
	var expected_value := 0
	var expected_count := 0
	for id: String in P.GOODS:
		progress.inventory[id] = 3
		if Fish.has_id(id) and not P.RECIPES.has(id):
			expected_value += int(P.GOODS[id].value)*3
			expected_count += 3
	var before: Dictionary = progress.inventory.duplicate()
	var quote: Dictionary = progress.non_cooking_fish_sale()
	check(quote.count == expected_count and quote.value == expected_value, "Quote covers every stocked non-cooking fish at canonical prices")
	check(progress.saves == 0 and progress.inventory == before and progress.coins == 17, "Quoting is read-only")
	check(progress.sell_non_cooking_fish() == expected_value and progress.coins == expected_value+17, "Batch credits the exact total once")
	for id: String in P.GOODS:
		var wanted := 0 if Fish.has_id(id) and not P.RECIPES.has(id) else 3
		check(progress.inventory[id] == wanted, "Bulk sale correctly retains or sells "+id)
	check(progress.saves == 1, "One completed batch causes exactly one durable save")
	check(progress.sell_non_cooking_fish() == 0 and progress.saves == 1 and progress.coins == expected_value+17, "Repeated sale cannot award duplicate coins or save again")
	var restored := MemoryProgression.new()
	restored._apply_save_data(progress._save_data())
	check(restored.coins == progress.coins and restored.inventory == progress.inventory, "Sold fish and preserved ingredients survive save serialization")
	progress.gm_infinite_coins = true
	progress.inventory.barracuda = 2
	var old_coins: int = progress.coins
	check(progress.sell_non_cooking_fish() == int(P.GOODS.barracuda.value)*2 and progress.coins == old_coins+int(P.GOODS.barracuda.value)*2, "GM infinite spending still records actual fish sale income")

func test_rejections() -> void:
	var progress := MemoryProgression.new()
	progress.inventory.orange = 2
	progress.inventory.pearl = 3
	progress.inventory.chest = 1
	progress.inventory.seagrass = 4
	var before: Dictionary = progress.inventory.duplicate()
	check(progress.non_cooking_fish_sale().count == 0 and progress.sell_non_cooking_fish() == 0 and progress.inventory == before and progress.saves == 0, "Ingredients and non-fish alone are never sold")
	progress.inventory.sardine = 3
	progress.inventory.barracuda = 2
	before = progress.inventory.duplicate()
	progress.service_active = true
	check(progress.sell_non_cooking_fish() == 0 and progress.inventory == before and progress.coins == 0 and progress.saves == 0, "An active service rejects batch sales without any mutation")
	progress.service_active = false
	var total: int = progress.non_cooking_fish_sale().value
	progress.coins = P.MAX_COINS-total+1
	check(progress.sell_non_cooking_fish() == 0 and progress.inventory == before and progress.coins == P.MAX_COINS-total+1 and progress.saves == 0, "Coin cap rejection is atomic across all fish kinds")
	progress.coins -= 1
	check(progress.sell_non_cooking_fish() == total and progress.coins == P.MAX_COINS and progress.saves == 1, "A sale landing exactly on the coin cap succeeds")

func sale_button(game: Node) -> Button:
	for button: Button in game.hud.restaurant_ui.buttons:
		if button.text == "一键出售不可烹饪鱼类":
			return button
	return null

func test_ui() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var progress := MemoryProgression.new()
	progress.persistence_enabled = false
	game.progress = progress
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.smoke_mode = true
	await physics_frame
	game.open_restaurant()
	var button: Button = sale_button(game)
	check(button != null and button.disabled, "Restaurant exposes the requested shortcut and disables it for empty stock")
	progress.inventory.orange = 4
	progress.inventory.blue = 3
	progress.inventory.lantern = 2
	progress.inventory.barracuda = 2
	progress.inventory.pearl = 5
	game.menu_plan = {"orange":2,"blue":1,"lantern":1}
	game.preparation = {"orange":{"count":2,"left":0.0,"seasoning":0}}
	var menu_before: Dictionary = game.menu_plan.duplicate(true)
	var preparation_before: Dictionary = game.preparation.duplicate(true)
	game.hud.rebuild()
	button = sale_button(game)
	check(button != null and not button.disabled, "Stocked non-cooking fish enable the real UI action")
	var saves_before: int = progress.saves
	if button != null:
		button.pressed.emit()
	check(progress.inventory.barracuda == 0 and progress.coins == 190 and progress.saves == saves_before+1, "Pressing the actual warehouse button sells the two barracudas")
	check(game.menu_plan == menu_before and game.preparation == preparation_before and progress.inventory.orange == 4 and progress.inventory.blue == 3 and progress.inventory.lantern == 2 and progress.inventory.pearl == 5, "Recipe stock, planned dishes, prepared food and pearls remain unchanged")
	check(game.notice.contains("2") and game.notice.contains("190"), "Sale feedback reports quantity and proceeds")
	button = sale_button(game)
	check(button != null and button.disabled, "Warehouse refresh immediately disables the emptied batch action")
	var valuable_button: Button
	for other: Button in game.hud.restaurant_ui.buttons:
		if other.text == "仅出售珍珠与宝藏":
			valuable_button = other
	check(valuable_button != null and not valuable_button.disabled, "The separate pearl and treasure action remains available")
	progress.inventory.barracuda = 1
	var inventory_before: Dictionary = progress.inventory.duplicate()
	game.layout_mode = true
	game.sell_non_cooking_fish()
	check(progress.inventory == inventory_before and progress.coins == 190, "Layout mode cannot invoke bulk fish selling")
	game.layout_mode = false
	game.return_to_dock()
	game.sell_non_cooking_fish()
	check(progress.inventory == inventory_before and progress.coins == 190, "Outside the restaurant the sale callback does nothing")
	game.open_restaurant()
	game.mobile_controls = true
	game.hud.rebuild()
	await process_frame
	await process_frame
	button = sale_button(game)
	check(button != null and button.is_visible_in_tree() and button.has_meta("layout_anchor") and game.hud.restaurant_ui._mobile_actions.is_empty(), "Mobile restaurant preserves the original batch-sale action without pagination")
	if button != null:
		button.pressed.emit()
	check(progress.inventory.barracuda == 0 and progress.coins == 285, "The mobile action uses the same protected sale callback")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
