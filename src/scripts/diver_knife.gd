extends RefCounted
## Left-hand utility knife; the right hand keeps the harpoon grip.
const Art = preload("res://scripts/furniture_art.gd")
const Loot = preload("res://scripts/loot_catalog.gd")
const COOLDOWN := .65
var remaining := 0.0
var model: Node3D
var arm: Node3D
var slice_sound: AudioStreamWAV

func setup(rig: Node3D) -> void:
	arm = rig.get_node("ArmLeft")
	model = Node3D.new()
	model.name = "HarvestKnife"
	arm.add_child(model)
	model.position = Vector3(-.25,-.18,-.57)
	var steel: Material = Art._mat(Color("d3ebe7"),0,.23,.7)
	Art._box(model,Vector3.ZERO,Vector3(.075,.065,.22),Art._mat(Color("243b3d")),.015)
	Art._box(model,Vector3(0,0,-.12),Vector3(.15,.045,.035),steel,.008)
	Art._box(model,Vector3(0,0,-.29),Vector3(.085,.018,.30),steel,.005)
	var tip := CylinderMesh.new()
	tip.top_radius = 0
	tip.bottom_radius = .045
	tip.height = .14
	tip.radial_segments = 4
	var mesh := MeshInstance3D.new()
	mesh.mesh = tip
	mesh.material_override = steel
	mesh.position.z = -.51
	mesh.rotation.x = -PI/2
	mesh.scale.z = .25
	model.add_child(mesh)
	model.visible = false
	slice_sound = _sound()

func reset() -> void:
	remaining = 0
	if is_instance_valid(model):
		model.visible = false

func advance(game: Node, delta: float) -> void:
	remaining = maxf(0,remaining-delta)
	model.visible = game.state == "dive" and not game.entry_active
	if remaining > 0:
		var swing: float = sin((1.0-remaining/COOLDOWN)*PI)
		arm.rotation.y += swing*1.2
		arm.rotation.x -= swing*.45
		model.rotation.z = swing*-.45
	else:
		model.rotation = Vector3.ZERO

func swing(game: Node) -> void:
	if game.state != "dive" or game.entry_active or game.gm_menu_open or remaining>0:
		return
	remaining = COOLDOWN
	if not game.muted:
		game.sound_player.stream = slice_sound
		game.sound_player.play()
	var plant: Dictionary = game.reef_plants.target(game)
	if plant.is_empty():
		game.tell("面向附近的海草或海藻，3 米内右键收割",2.0)
		return
	var info: Dictionary = Loot.pickup_info("seagrass")
	if game.weight()+int(info.weight)>game.progress.capacity():
		game._show_capacity_warning(info,"未能收割")
		return
	if not game.reef_plants.cut(plant):
		return
	game.cargo.append(info)
	game._show_loot_feedback("海草收割成功",[info],0.0)
	game._pickup_feedback("seagrass",plant.position)
	for i in range(7):
		var fragment := MeshInstance3D.new()
		var blade := BoxMesh.new()
		blade.size = Vector3(.045,.16,.025)
		fragment.mesh = blade
		fragment.material_override = Art._mat(Color("8fc184"))
		fragment.position = plant.position
		game.ocean_root.add_child(fragment)
		var angle: float = float(i)*2.399
		game.effects.append({"node":fragment,"life":.8,"velocity":Vector3(sin(angle)*.6,.3+float(i%3)*.2,cos(angle)*.6),"gravity":0.0})

func _sound() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(6615*2)
	var random := RandomNumberGenerator.new()
	random.seed = 5921
	var filtered := 0.0
	for i in range(6615):
		var time: float = float(i)/22050.0
		filtered = lerpf(filtered,random.randf_range(-1,1),.18)
		var envelope: float = sin(minf(time/.3,1)*PI)*exp(-time*7)
		bytes.encode_s16(i*2,int(filtered*envelope*26000))
	wav.data = bytes
	return wav
