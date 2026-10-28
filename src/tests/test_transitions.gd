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
		var tail_a := a.find_child("Tail",true,false) as Node3D
		var tail_b := b.find_child("Tail",true,false) as Node3D
		_check(tail_a != null and tail_b != null,"Both species instances retain an animated tail")
		var independent: bool = tail_a != null and tail_b != null
		for joint_name: String in ["Tail","Motion","BodyFlex","Jaw"]:
			var joint_a := a.find_child(joint_name,true,false) as Node3D
			var joint_b := b.find_child(joint_name,true,false) as Node3D
			if joint_a == null and joint_b == null:
				continue
			if joint_a == null or joint_b == null:
				independent = false
				continue
			var original: Transform3D = joint_b.transform
			joint_a.rotation.y += 0.7
			joint_a.position += Vector3(0.1,0.2,-0.3)
			joint_a.scale *= Vector3(1.1,0.9,1.2)
			independent = independent and joint_a != joint_b and joint_b.transform == original
		a.scale = Vector3.ONE * 1.5
		_check(independent and b.scale == Vector3.ONE,"Fish tails, body motion, jaws and armour remain independent")
		a.free()
		b.free()
	var game = load("res://scenes/main.tscn").instantiate()
	game.progress = MemoryProgression.new()
	game.progress.persistence_enabled = false
	game.muted = true
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
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
