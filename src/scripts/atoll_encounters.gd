extends RefCounted
## Recognizable, low-cost activity beds; resources use the normal pickup/harvest systems.
const Ocean = preload("res://scripts/ocean_config.gd")
const Life = preload("res://scripts/reef_life.gd")
const Coral = preload("res://scripts/coral_garden.gd")
const Plants = preload("res://scripts/reef_vegetation.gd")

static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "AtollActivities"
	parent.add_child(root)
	var points: Array = Ocean.atoll_activity_points()
	var random := RandomNumberGenerator.new()
	random.seed = 251105
	for index in range(points.size()):
		var cluster := Node3D.new()
		cluster.name = ["ShellBed","SeagrassGarden","RaySandbar"][index]
		cluster.position = root.to_local(points[index].position)
		cluster.set_meta("activity_name",points[index].name)
		root.add_child(cluster)
		if index==0:
			_batch(cluster,"ScallopBed",Life.mesh("Scallop"),Life.material(),24,random,Color("e4d7bc"),.40,.75,3.2,6.5)
			_batch(cluster,"OpenShells",Life.shell_valve_mesh(),Life.material(),12,random,Color("d8c1bb"),.45,.80,3.5,7.5)
		elif index==1:
			_batch(cluster,"HarvestableGrass",Plants._plant_mesh(0),Plants.shared_material(),24,random,Color("9bb77e"),.68,1.08,2.8,6.5,true)
			_batch(cluster,"HarvestableRibbonAlgae",Plants._plant_mesh(1),Plants.shared_material(),16,random,Color("8bb7a4"),.60,.95,4.0,7.0,true)
		else:
			# The central sand and surrounding ray approach remain open.
			_batch(cluster,"SandbarCoral",Coral._coral_mesh(1),Coral.material(),8,random,Color("c2a5c9"),.28,.48,4.0,6.0)
			_batch(cluster,"DriftShells",Life.mesh("Scallop"),Life.material(),14,random,Color("c4c1ab"),.28,.50,3.8,6.5)
	root.set_meta("activity_count",3)
	root.set_meta("harvestable_count",40)
	root.set_meta("draw_batches",6)
	root.set_meta("no_collision",true)
	return root

static func _batch(parent: Node3D, label: String, mesh: Mesh, material: Material, count: int, random: RandomNumberGenerator, color: Color, min_size: float, max_size: float, inner: float, outer: float, harvestable: bool=false) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = count
	for index in range(count):
		# Break up the ring into loose banks, leaving a clear two-metre east-west lane.
		var angle: float = float(index)*2.399963+random.randf_range(-.15,.15)
		var radius: float = random.randf_range(inner,outer)
		var local := Vector3(cos(angle)*radius,0,sin(angle)*radius)
		if absf(local.z)<1.5:
			local.z = 1.6 if local.z>=0 else -1.6
		var world: Vector3 = parent.to_global(local)
		world.y = Ocean.seabed_height(world.x,world.z)+.035
		var normal := Vector3(Ocean.seabed_height(world.x-.5,world.z)-Ocean.seabed_height(world.x+.5,world.z),1.0,Ocean.seabed_height(world.x,world.z-.5)-Ocean.seabed_height(world.x,world.z+.5)).normalized()
		var frame: Basis = Basis(Vector3.UP,angle) if harvestable else Basis(Quaternion(Vector3.UP,normal))*Basis(Vector3.UP,angle)
		frame = frame.scaled(Vector3.ONE*random.randf_range(min_size,max_size))
		batch.set_instance_transform(index,Transform3D(frame,parent.to_local(world)))
		batch.set_instance_color(index,color.lerp(Color("dfd4b9"),random.randf()*.15))
	var visual := MultiMeshInstance3D.new()
	visual.name = label
	visual.multimesh = batch
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = 95.0
	visual.visibility_range_end_margin = 12.0
	visual.extra_cull_margin = .8
	visual.set_meta("harvestable_plant",harvestable)
	parent.add_child(visual)
