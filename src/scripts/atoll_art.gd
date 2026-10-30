extends RefCounted
## Broken limestone rim, lagoon sand, scattered shell beds and rooted vegetation.
const Ocean = preload("res://scripts/ocean_config.gd")
const Geology = preload("res://scripts/ocean_geology.gd")
const Coral = preload("res://scripts/coral_garden.gd")
const Life = preload("res://scripts/reef_life.gd")
const Plants = preload("res://scripts/reef_vegetation.gd")

static func build(parent: Node3D) -> Node3D:
	var atoll := Node3D.new()
	atoll.name = "NaturalAtoll"
	parent.add_child(atoll)
	var random := RandomNumberGenerator.new()
	random.seed = 835241
	var positions := PackedVector3Array()
	var meshes: Array[Mesh] = [Geology.rock_mesh(3),Life.mesh("Scallop"),Life.shell_valve_mesh(),Coral._coral_mesh(1),Coral._coral_mesh(2),Plants._plant_mesh(0),Plants._plant_mesh(1)]
	for kind in range(7):
		var poses: Array[Transform3D] = []
		var colors: Array[Color] = []
		var count: int = [38,44,32,24,18,90,30][kind]
		for index in range(count):
			var angle: float = random.randf_range(-PI,PI)
			# Leave a broad southern sand channel into the lagoon.
			if absf(wrapf(angle-PI*.5,-PI,PI))<.48:
				angle = PI*.5+random.randf_range(.55,1.2)
			var rim: float = 30.0+sin(angle*3+.8)*4.0+cos(angle*5)*2.0
			var radius: float = rim+random.randf_range(-3.5,3.5)
			if kind in [1,2]:
				radius = random.randf_range(13.0,26.0)
			elif kind == 5:
				radius = random.randf_range(18.0,38.0)
			var x: float = cos(angle)*radius
			var z: float = sin(angle)*radius
			var world: Vector3 = parent.global_position+Vector3(x,0,z)
			world.y = Ocean.seabed_height(world.x,world.z)
			var normal := Vector3(Ocean.seabed_height(world.x-.5,world.z)-Ocean.seabed_height(world.x+.5,world.z),1,Ocean.seabed_height(world.x,world.z-.5)-Ocean.seabed_height(world.x,world.z+.5)).normalized()
			var yaw: float = random.randf_range(-PI,PI)
			var basis := Basis(Quaternion(Vector3.UP,normal))*Basis(Vector3.UP,yaw)
			var size: Vector3
			var tint: Color
			var root: Vector3 = world-parent.global_position
			match kind:
				0:
					size = Vector3(random.randf_range(2.2,4.4),random.randf_range(.8,1.7),random.randf_range(2.2,3.8))
					root += normal*size.y*.2
					tint = Color("b4b6a1").lerp(Color("b0c3b9"),random.randf())
				1,2:
					var scale: float = random.randf_range(.28,.77)
					size = Vector3.ONE*scale
					basis *= Basis(Vector3.RIGHT,random.randf_range(-.25,.15))
					tint = Color("c5b6a4").lerp(Color("bca7aa"),random.randf())
				3,4:
					size = Vector3.ONE*random.randf_range(.32,.70)
					tint = Coral.PALETTE[random.randi_range(0,Coral.PALETTE.size()-1)]
				_:
					basis = Basis(Vector3.UP,yaw)
					size = Vector3.ONE*random.randf_range(.45,.85)
					tint = Color("9bb9a0").lerp(Color("b8c59b"),random.randf())
			poses.append(Transform3D(basis*Basis.from_scale(size),root))
			colors.append(tint)
			positions.append(world)
		var material: Material = Geology.rock_material() if kind == 0 else (Coral.material() if kind in [3,4] else Life.material())
		if kind in [5,6]:
			material = Plants.shared_material()
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = meshes[kind]
		batch.instance_count = poses.size()
		for index in range(poses.size()):
			batch.set_instance_transform(index,poses[index])
			batch.set_instance_color(index,colors[index])
		var visual := MultiMeshInstance3D.new()
		visual.name = ["LimestoneRim","LivingShellBeds","ScatteredValves","EncrustedCoral","SeaFans","LagoonGrass","RibbonAlgae"][kind]
		if kind in [5,6]:
			visual.set_meta("harvestable_plant",true)
		if kind in [5,6]:
			visual.set_meta("harvestable_plant",true)
		visual.multimesh = batch
		visual.material_override = material
		visual.visibility_range_end = 165.0
		visual.visibility_range_end_margin = 15.0
		visual.extra_cull_margin = .8
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		atoll.add_child(visual)
	atoll.set_meta("roots",positions)
	atoll.set_meta("natural_lagoon",true)
	atoll.set_meta("draw_batches",7)
	return atoll
