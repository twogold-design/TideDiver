extends SceneTree
## Isolated repeatable CPU timings; never opens a player's save.
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	for key in game.progress.renovation:
		game.progress.renovation[key] = true
	game.progress.coins = 12000
	game.open_restaurant()
	game.enter_layout()
	game.hud.restaurant_ui.layout_ui.set_category("soft")
	var timings := {}
	var started: int = Time.get_ticks_usec()
	for i in range(60):
		game.restaurant_node.set_layout_preview("soft",Vector3((i%12)*0.5,0,(i/12)*0.5),i%4,0,i%2 == 0,"premium")
	timings.preview_move_ms = (Time.get_ticks_usec()-started)/60000.0
	await process_frame
	started = Time.get_ticks_usec()
	for i in range(10):
		game.hud.rebuild()
	timings.shop_refresh_ms = (Time.get_ticks_usec()-started)/10000.0
	await process_frame
	started = Time.get_ticks_usec()
	for i in range(10):
		game._rebuild_restaurant()
	timings.room_refresh_ms = (Time.get_ticks_usec()-started)/10000.0
	print("LAYOUT_PROFILE " + JSON.stringify(timings))
	game.free()
	quit()
