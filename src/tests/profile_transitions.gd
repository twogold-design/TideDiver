extends SceneTree
## Repeatable transition timings with isolated in-memory progress.
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
	root.add_child(game)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	for site in [0,3,6]:
		game.state = "dock"
		var started: int = Time.get_ticks_usec()
		game.start_dive(false,false,site)
		print("TRANSITION_PROFILE dive_%d %.2f ms" % [site,(Time.get_ticks_usec()-started)/1000.0])
		started = Time.get_ticks_usec()
		game.muted = false
		game._play_splash()
		print("TRANSITION_PROFILE splash_audio %.2f ms" % ((Time.get_ticks_usec()-started)/1000.0))
		started = Time.get_ticks_usec()
		game._spawn_entry_water()
		print("TRANSITION_PROFILE splash_water %.2f ms" % ((Time.get_ticks_usec()-started)/1000.0))
		await process_frame
		game.state = "dock"
		started = Time.get_ticks_usec()
		game.open_restaurant()
		print("TRANSITION_PROFILE restaurant %.2f ms" % ((Time.get_ticks_usec()-started)/1000.0))
		await process_frame
	game.sound_player.stop()
	game.free()
	await process_frame
	await process_frame
	quit()
