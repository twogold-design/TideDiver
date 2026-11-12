extends SceneTree
## Test real spawns, collision clearance, catching, collecting and fresh-dive reset.
class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void: pass
	func save_game() -> void: pass

var game: Node
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func residents(site: String) -> Array:
	return game.fish.filter(func(item: Dictionary) -> bool: return item.get("habitat_site","") == site)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.smoke_mode = true
	await physics_frame
	game.start_dive(false)
	await physics_frame
	check(game.entry_site_index == 0,"The first departure still starts at the sheltered cove")
	check(game.fish.size() == 207 and game.fish_population_count() == 207,"Exactly twenty-four catchable residents augment the existing population")
	for site: String in ["tidal_cove","southern_spires"]:
		var added: Array = residents(site)
		var coastal: bool = site == "tidal_cove"
		check(added.size() == (10 if coastal else 14),"Expected resident count in " + site)
		var center: Vector3 = Vector3.ZERO if coastal else game.Ocean.ZONES[3].center
		var kinds := {}
		for i in range(added.size()):
			var fish: Dictionary = added[i]
			var data: Dictionary = game.FishData.SPECIES[fish.kind]
			kinds[fish.kind] = true
			check(data.behavior not in ["predator","ambush","venom"],"Added resident does not introduce an attack hazard")
			check(game._open_water(fish.home,float(data.radius)),"Fish home clears actual terrain and rock collisions")
			check(Vector2(fish.home.x-center.x,fish.home.z-center.z).length() < (68 if coastal else 72),"Resident stays within its intended dive site")
			check(fish.home.y <= -6 and fish.home.y >= game.Ocean.seabed_height(fish.home.x,fish.home.z)+3,"Resident has swimming clearance above the seabed")
			if coastal:
				check(fish.home.y >= -24,"New coastal hunting targets remain in shallow water")
			for j in range(i):
				check(fish.home.distance_to(added[j].home) > 9,"Residents stay separated rather than forming a dense cloud")
			game.cargo.clear()
			game._hit_fish(fish,99)
			check(not fish.alive and game.cargo.size() == 1 and game.cargo[0].id == data.id,"A resident can be caught through the normal damage and inventory flow")
		check(kinds.size() >= (6 if coastal else 7),"Local population contains the intended variety")
	var finds: Array = game.pickups.filter(func(item: Dictionary) -> bool: return item.get("coastal_activity",false))
	check(finds.size() == 4,"Four extra coastal finds use the real pickup system")
	var loot_kinds := {}
	for item: Dictionary in finds:
		loot_kinds[item.kind] = true
		game.cargo.clear()
		game.player.position = item.node.position + Vector3.UP*.5
		await physics_frame
		check(game.nearest_pickup() == item,"New coastal find is physically reachable")
		game.interact()
		check(not item.active and game.cargo.size() == 1 and game.cargo[0].id == item.kind,"New coastal find is collected via normal interaction")
	check(loot_kinds.size() == 4,"The cove has four distinct added collectible types")
	game.cargo.clear()
	game.state = "dock"
	game.start_dive(false,false,game.Ocean.site_index("southern_spires"))
	await physics_frame
	check(residents("tidal_cove").size() == 10 and residents("southern_spires").size() == 14,"Both habitats repopulate on a new dive without duplication")
	check(residents("tidal_cove").all(func(item: Dictionary) -> bool: return item.alive) and residents("southern_spires").all(func(item: Dictionary) -> bool: return item.alive),"Caught residents return healthy on the next dive")
	check(game.pickups.filter(func(item: Dictionary) -> bool: return item.get("coastal_activity",false) and item.active).size() == 4,"New dive restores all four coastal finds")
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1440,900)
		for site: String in ["tidal_cove","southern_spires"]:
			var focus: Vector3 = Vector3(25,-17,-5) if site == "tidal_cove" else Vector3(-45,-47,290)
			game.player.position = focus+Vector3(0,2,15)
			game.yaw = 0
			game.pitch = -.15
			game._update_swim_camera()
			game._animate_ocean(0)
			game._apply_underwater_lighting(-game.camera.position.y)
			game.hud.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../.runtime/"+site+"-enriched.png")
	game.free()
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("%s: Cove and spires ecology (%d checks)." % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)
