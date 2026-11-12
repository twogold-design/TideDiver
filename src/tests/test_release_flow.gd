extends SceneTree
## Release build: safe first departure, ordinary economy and no developer controls.
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void: pass
	func save_game() -> void: pass

var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + description)

func _f1() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F1
	key.pressed = true
	game._unhandled_input(key)

func _has_debug_properties(value: Object) -> bool:
	for property: Dictionary in value.get_property_list():
		if str(property.name).begins_with("gm_"):
			return true
	return false

func _check_buttons(controls: Array) -> void:
	for control: Node in controls:
		if control is Button:
			check(not control.text.contains("GM") and not control.text.contains("无限"),"Release button has no developer control: " + control.text)

func _run() -> void:
	if preload("res://scripts/build_mode.gd").GM_ENABLED:
		printerr("FAIL: release_flow must run against the generated release staging project")
		quit(1)
		return
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.smoke_mode = true
	await physics_frame
	check(not game.BuildMode.GM_ENABLED,"Release gameplay uses the disabled build-time constant")
	game.open_gm_menu()
	game.gm_select_dive_site(4,true)
	game.toggle_gm_infinite_air()
	check(not game.gm_menu_open and not game.gm_infinite_air and game.state == "dock","Direct calls cannot enable release GM menus, free air or teleportation")
	_check_buttons(game.hud.buttons)
	_f1()
	check(game.state == "dock" and not game.entry_active,"F1 does not open a developer menu or begin a dive")
	game.entry_site_index = 5
	game.entry_rng.seed = 20261110
	game.start_dive()
	check(game.entry_site_index == 0 and game.dive_origin == Vector3.ZERO,"Day one starts at the fixed sheltered cove regardless of RNG or a previous site")
	check(game.Ocean.DIVE_SITES[0].name == "潮溪湾近岸","First destination displays the requested name")
	check(game.entry_active and game.boat.position == Vector3(0,.3,14) and game.player.position == Vector3(0,2.4,17.5),"The boat and animated entry share the fixed coastal origin")
	_f1()
	check(game.state == "dive" and game.entry_active,"F1 does not pause or teleport during entry")
	game.entry_active = false
	game.gm_infinite_air = true # Even direct flag manipulation cannot enable release powers.
	game.oxygen = 60
	game._consume_air(10)
	check(game.oxygen == 50,"Normal diving consumes the real cylinder reserve")
	game.hurt_cooldown = 0
	game.take_hunt_damage(12,true,"石头鱼")
	check(game.oxygen == 38 and game.poison_timer == 6,"Release encounters still damage the diver and apply poison")
	game._update_hunting_status(1)
	check(is_equal_approx(game.oxygen,36.5),"Poison continues to consume cylinder reserve")
	game.finish_dive()
	check(game.progress.day == 2 and game.state == "dock","Returning from the first dive advances normal progression")
	var previous := 0
	var visited := {}
	for departure in range(8):
		game.state = "dock"
		game.start_dive(false)
		check(game.entry_site_index != previous,"Later departures keep the existing non-repeating destination selection")
		previous = game.entry_site_index
		visited[previous] = true
	check(visited.size() > 1,"Later dives offer more than the initial sheltered destination")
	game.state = "dock"
	game.progress.coins = 0
	game.open_restaurant()
	game.toggle_gm_infinite_coins()
	check(not game.progress.gm_infinite_coins,"Direct calls cannot enable release free spending")
	game.progress.gm_infinite_coins = true
	_check_buttons(game.hud.restaurant_ui.buttons)
	_f1()
	check(game.progress.coins == 0 and not game.progress.renovate("clean"),"F1 cannot make restaurant purchases free")
	game.progress.coins = 100
	check(game.progress.spend_coins(40) and game.progress.coins == 60,"Ordinary purchases deduct their exact cost")
	check(not game.progress.spend_coins(61) and game.progress.coins == 60,"Unaffordable purchases do not change the balance")
	var legacy = MemoryProgression.new()
	legacy._apply_save_data({"day":1,"coins":0,"gm_infinite_coins":true,"gm_infinite_air":true})
	check(not legacy.can_afford(1) and not legacy.gm_infinite_coins,"Legacy save flags cannot re-enable release developer powers")
	game.state = "dock"
	game.progress = legacy
	game.progress.persistence_enabled = false
	game.start_dive(false)
	check(game.entry_site_index == 0 and game.dive_origin == Vector3.ZERO,"Reloading a first-day save still starts at the sheltered cove")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver release flow (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)
