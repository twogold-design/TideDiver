extends SceneTree
const FishArt = preload("res://scripts/fish_art.gd")
var checks := 0

class MemoryProgression extends "res://scripts/progression.gd":
	func load_game() -> void:
		pass
	func save_game() -> void:
		pass

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error(message)
		quit(1)

func _run() -> void:
	for kind in range(10):
		var a := FishArt.build(kind)
		var b := FishArt.build(kind)
		var mesh_a: MeshInstance3D = a.find_children("*","MeshInstance3D",true,false)[0]
		var mesh_b: MeshInstance3D = b.find_children("*","MeshInstance3D",true,false)[0]
		_check(mesh_a.mesh == mesh_b.mesh,"Species geometry is shared")
		var tail_a: Node3D = a.get_node("Tail")
		var tail_b: Node3D = b.get_node("Tail")
		var original := tail_b.transform
		tail_a.rotation.y += 0.7
		a.scale = Vector3.ONE * 1.5
		_check(tail_b.transform == original and b.scale == Vector3.ONE,"Fish animations and armour remain independent")
		a.free()
		b.free()
	var game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	root.add_child(game)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	var room_id: int = game.restaurant_node._room.get_instance_id()
	game.open_restaurant()
	_check(game.restaurant_node._room.get_instance_id() == room_id,"Entering the restaurant preserves the prepared room")
	game.progress.renovation.clean = true
	game.progress.renovation.kitchen = true
	game.open_restaurant()
	_check(game.restaurant_node._room.get_instance_id() != room_id,"Renovations still update the room")
	var chef_id: int = game.restaurant_node._chef.get_instance_id()
	room_id = game.restaurant_node._room.get_instance_id()
	game.return_to_dock()
	game.open_restaurant()
	_check(game.restaurant_node._room.get_instance_id() == room_id and game.restaurant_node._chef.get_instance_id() == chef_id,"Repeat visits reuse room and chef")
	game.return_to_dock()
	game.fish[0].alive = false
	game.fish[0].hp = 0
	game.fish[0].node.visible = false
	game.start_dive(false,false,0)
	_check(game.fish.size() == game.fish_population_count(),"New dive preserves the full population")
	for fish: Dictionary in game.fish:
		_check(fish.alive and fish.hp == game.FishData.SPECIES[fish.kind].hp,"New dive resets fish health and catch state")
	var first: int = game.effects.size()
	game._spawn_entry_water()
	_check(game.effects.size()-first == 42,"All splash droplets remain present")
	_check(game.effects[first].node.mesh == game.effects[first+4].node.mesh,"Droplets reuse geometry")
	_check(game.effects[first].node != game.effects[first+4].node,"Droplet motion remains independent")
	_check(is_equal_approx(preload("res://assets/audio/dive_splash.wav").get_length(),1.2),"Original splash duration is preserved")
	game.free()
	await process_frame
	await process_frame
	print("PASS: Tide Diver transitions (%d checks)." % checks)
	quit()
