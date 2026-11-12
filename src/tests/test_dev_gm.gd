extends SceneTree
## Development-only tools are opt-in, work with touch, and never persist switches.
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void: pass
	func save_game() -> void: pass
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	check(game.BuildMode.GM_ENABLED,"Source checkout enables developer tools")
	check(not game.gm_menu_open and not game.gm_infinite_air and not game.progress.gm_infinite_coins,"Developer switches default off")
	game.start_dive(false)
	check(game.entry_site_index == 0,"Normal first departure remains the sheltered cove")
	game.mobile_controls = true
	game.touch_input.held["ascend"] = true
	game.touch_input.movement = Vector2.UP
	game.open_gm_menu()
	check(game.state == "paused" and game.gm_menu_open and game.touch_input.held.is_empty() and game.touch_input.movement == Vector2.ZERO,"Opening GM pauses diving and releases every touch action")
	game.toggle_gm_infinite_air()
	check(game.gm_infinite_air and game.oxygen == game.progress.oxygen_max(),"Free air switch fills the cylinder")
	game.close_gm_menu()
	check(game.state == "dive" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"Closing GM preserves touch control without pointer lock")
	game._consume_air(25)
	check(game.oxygen == game.progress.oxygen_max(),"Developer free air prevents respiration consumption")
	game.hurt_cooldown = 0
	game.take_hunt_damage(12,true,"石头鱼")
	game._update_hunting_status(1)
	check(game.oxygen == game.progress.oxygen_max() and game.poison_timer > 0,"Free air preserves poison feedback without losing air")
	game.open_gm_menu()
	game.gm_select_dive_site(4,true)
	check(game.entry_site_index == 4 and game.gm_test_active and not game.entry_active and game._open_water(game.player.position),"GM reaches the selected stone forest at a valid viewpoint")
	game.open_gm_menu()
	game.toggle_gm_infinite_air()
	game.close_gm_menu()
	game.oxygen = 70
	game._consume_air(10)
	check(game.oxygen == 60,"Turning free air off restores consumption")
	game.finish_dive()
	game.open_restaurant()
	game.progress.coins = 0
	game.toggle_gm_infinite_coins()
	check(game.progress.gm_infinite_coins and game.progress.spend_coins(100) and game.progress.coins == 0,"Restaurant developer spending works without minting coins")
	check(not game.progress._save_data().has("gm_infinite_coins"),"Free-spending switch is not part of saved progress")
	game.progress.renovate("clean")
	game.enter_layout()
	check(game.layout_work.gm_infinite_coins,"Layout draft inherits the session switch")
	game.toggle_gm_infinite_coins()
	check(not game.progress.gm_infinite_coins and not game.layout_work.gm_infinite_coins,"Layout switch updates the durable model and temporary draft together")
	game.free()
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("%s: Developer GM (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)
