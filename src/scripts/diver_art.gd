extends RefCounted
## The horizontal swimming rig faces -Z; legs retain their gameplay joint names.
const Art = preload("res://scripts/furniture_art.gd")
const Detail = preload("res://scripts/character_geometry.gd")

static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "DiverArt"
	var orange: Material = Detail.cloth(Color("e68446"))
	var dark: Material = Detail.cloth(Color("183741"))
	var rubber: Material = Art._mat(Color("142b31"), 0, 0.62)
	var yellow: Material = Art._mat(Color("eabe56"), 0, 0.38)
	var silver: Material = Art._mat(Color("b6c8c3"), 0, 0.28, 0.65)
	var skin: Material = Art._mat(Color("dfb08b"))
	var white: Material = Art._mat(Color("d7e6d8"), 0, 0.4)
	# Sculpted suit, contrasting side panels and raised seams.
	var body: MeshInstance3D = Detail.loft(root, [Vector3(-0.54, 0.28, 0.21), Vector3(-0.38, 0.33, 0.24), Vector3(0, 0.38, 0.26), Vector3(0.32, 0.40, 0.25), Vector3(0.53, 0.28, 0.19)], orange)
	body.rotation.x = -PI / 2
	for side: float in [-1.0, 1.0]:
		Art._sphere(root, Vector3(side * 0.32, 0, 0.10), Vector3(0.08, 0.23, 0.36), dark)
		Detail.tube(root, [Vector3(side * 0.29, -0.16, -0.34), Vector3(side * 0.23, -0.23, 0), Vector3(side * 0.22, -0.17, 0.41)], 0.013, yellow)
	Art._box(root, Vector3(0, -0.251, -0.02), Vector3(0.026, 0.014, 0.64), rubber, 0.005)
	Art._box(root, Vector3(0, -0.267, -0.24), Vector3(0.043, 0.018, 0.06), silver, 0.006)
	Art._sphere(root, Vector3(0, 0, 0.49), Vector3(0.29, 0.20, 0.19), dark)
	# Hood, mask seal, split lenses, visible eyes, regulator and straps.
	Art._sphere(root, Vector3(0, 0.02, -0.78), Vector3(0.32, 0.30, 0.34), dark)
	Art._sphere(root, Vector3(0, -0.005, -0.98), Vector3(0.24, 0.23, 0.15), skin)
	for side: float in [-1.0, 1.0]:
		Art._box(root, Vector3(side * 0.125, 0.095, -1.112), Vector3(0.235, 0.195, 0.08), rubber, 0.036)
		Art._box(root, Vector3(side * 0.125, 0.10, -1.157), Vector3(0.193, 0.148, 0.018), silver, 0.025)
		Art._box(root, Vector3(side * 0.125, 0.10, -1.17), Vector3(0.170, 0.126, 0.01), Art._mat(Color("508f98"), 0, 0.16), 0.022)
		Art._sphere(root, Vector3(side * 0.12, 0.10, -1.18), Vector3(0.041, 0.029, 0.009), white)
		Art._sphere(root, Vector3(side * 0.12, 0.10, -1.189), Vector3(0.015, 0.023, 0.008), rubber)
		Art._bar(root, Vector3(side * 0.16, 0.144, -1.184), Vector3(side * 0.09, 0.159, -1.184), 0.008, white)
		Detail.tube(root, [Vector3(side * 0.25, 0.10, -1.10), Vector3(side * 0.32, 0.10, -0.86), Vector3(side * 0.26, 0.10, -0.59)], 0.03, rubber)
		Art._box(root, Vector3(side * 0.30, 0.10, -0.98), Vector3(0.045, 0.085, 0.09), silver, 0.008)
	Art._sphere(root, Vector3(0, -0.04, -1.118), Vector3(0.046, 0.069, 0.06), skin)
	var regulator := Art._cylinder(root, Vector3(0, -0.14, -1.12), 0.105, 0.09, rubber)
	regulator.rotation.x = PI / 2
	var cap := Art._cylinder(root, Vector3(0, -0.14, -1.173), 0.08, 0.025, silver)
	cap.rotation.x = PI / 2
	for x: float in [-0.04, 0, 0.04]:
		Art._box(root, Vector3(x, -0.14, -1.19), Vector3(0.012, 0.075, 0.008), rubber, 0.003)
	# Rounded tank, harness, two retaining bands and valve block.
	Art._box(root, Vector3(0, 0.24, 0.04), Vector3(0.49, 0.13, 0.85), rubber)
	var tank := Art._cylinder(root, Vector3(0, 0.40, 0.04), 0.205, 0.78, yellow)
	tank.rotation.x = PI / 2
	for z: float in [-0.35, 0.43]:
		Art._sphere(root, Vector3(0, 0.40, z), Vector3(0.205, 0.205, 0.14), yellow)
	for z: float in [-0.19, 0.28]:
		var band := Art._cylinder(root, Vector3(0, 0.40, z), 0.212, 0.075, rubber)
		band.rotation.x = PI / 2
		for side: float in [-1.0, 1.0]:
			Detail.tube(root, [Vector3(side * 0.18, 0.34, z), Vector3(side * 0.37, 0.12, z), Vector3(side * 0.31, -0.15, z)], 0.034, dark)
			Art._box(root, Vector3(side * 0.33, 0.10, z), Vector3(0.07, 0.095, 0.10), silver, 0.012)
	Art._bar(root, Vector3(0, 0.40, -0.46), Vector3(0, 0.40, -0.61), 0.045, silver)
	Art._bar(root, Vector3(-0.08, 0.40, -0.60), Vector3(0.09, 0.40, -0.60), 0.033, silver)
	Art._sphere(root, Vector3(0.11, 0.40, -0.60), Vector3(0.035, 0.07, 0.07), rubber)
	Detail.tube(root, [Vector3(-0.07, 0.40, -0.60), Vector3(-0.35, 0.35, -0.59), Vector3(-0.51, 0.15, -0.78), Vector3(-0.48, -0.10, -1.03), Vector3(-0.26, -0.17, -1.14), Vector3(-0.09, -0.14, -1.14)], 0.033, rubber)
	# Articulated legs: knee guards, boots, shaped fins and longitudinal ribs.
	for side: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegLeft" if side < 0 else "LegRight"
		leg.position = Vector3(side * 0.23, 0, 0.47)
		root.add_child(leg)
		Art._sphere(leg, Vector3(0, 0, 0.30), Vector3(0.15, 0.15, 0.36), dark)
		var stripe_start := Vector3(side * 0.12, -0.03, 0.10)
		var stripe_end := Vector3(side * 0.10, -0.03, 0.72)
		var stripe_knee: Vector3 = stripe_start.lerp(stripe_end, (0.40 - 0.10) / (0.72 - 0.10))
		Art._bar(leg, stripe_start, stripe_knee, 0.019, orange)
		var knee: Node3D = _joint(leg, "KneeLeft" if side < 0 else "KneeRight", Vector3(0, 0, 0.40))
		var lower_parts: int = leg.get_child_count()
		Art._sphere(leg, Vector3(0, 0, 0.65), Vector3(0.115, 0.125, 0.28), dark)
		Art._sphere(leg, Vector3(0, -0.105, 0.40), Vector3(0.12, 0.05, 0.14), rubber)
		Art._bar(leg, stripe_knee, stripe_end, 0.019, orange)
		Art._sphere(leg, Vector3(0, -0.015, 0.87), Vector3(0.13, 0.105, 0.19), rubber)
		var fin := Detail.loft(leg, [Vector3(0.84, 0.11, 0.034), Vector3(0.98, 0.16, 0.032), Vector3(1.23, 0.235, 0.026), Vector3(1.43, 0.25, 0.019)], yellow)
		fin.rotation.x = PI / 2
		fin.position.y = -0.07
		for rib: float in [-1, -0.45, 0.45, 1]:
			Detail.tube(leg, [Vector3(rib * 0.11, -0.03, 0.87), Vector3(rib * 0.16, -0.03, 1.02), Vector3(rib * 0.23, -0.04, 1.41)], 0.013 if absf(rib) < 1 else 0.021, rubber)
		_move_parts(leg, knee, lower_parts)
		# Segmented sleeves and gloves follow the established harpoon grip.
		var arm: Node3D = _joint(root, "ArmLeft" if side < 0 else "ArmRight", Vector3(side * 0.33, -0.02, -0.29))
		var arm_parts: int = root.get_child_count()
		Art._bar(root, Vector3(side * 0.33, -0.02, -0.29), Vector3(side * 0.51, -0.16, -0.51), 0.12, orange)
		Art._sphere(root, Vector3(side * 0.51, -0.16, -0.51), Vector3.ONE * 0.12, dark)
		Art._bar(root, Vector3(side * 0.51, -0.16, -0.51), Vector3(side * 0.58, -0.20, -0.80), 0.09, dark)
		Art._sphere(root, Vector3(side * 0.58, -0.20, -0.86), Vector3(0.09, 0.08, 0.11), rubber)
		for finger: int in range(4):
			Art._sphere(root, Vector3(side * 0.58 + (finger - 1.5) * 0.038, -0.22, -0.94), Vector3(0.022, 0.035, 0.06), rubber)
		Art._sphere(root, Vector3(side * 0.49, -0.20, -0.88), Vector3(0.035, 0.05, 0.06), rubber)
		_move_parts(root, arm, arm_parts)
	var watch_parts: int = root.get_child_count()
	Art._box(root, Vector3(-0.57, -0.105, -0.71), Vector3(0.16, 0.06, 0.14), rubber, 0.02)
	Art._box(root, Vector3(-0.57, -0.069, -0.71), Vector3(0.11, 0.012, 0.09), Art._mat(Color("70cdbb")), 0.008)
	for i: int in range(3):
		Art._box(root, Vector3(-0.60 + i * 0.03, -0.059, -0.71), Vector3(0.012, 0.005, 0.05), rubber, 0.002)
	_move_parts(root, root.get_node("ArmLeft"), watch_parts)
	# Barrel, hand grip, line spool, elastic bands, and the actual muzzle alignment.
	var weapon_parts: int = root.get_child_count()
	Art._bar(root, Vector3(0.58, -0.18, -0.64), Vector3(0.58, -0.18, -1.52), 0.055, rubber)
	Art._bar(root, Vector3(0.58, -0.18, -0.90), Vector3(0.58, -0.35, -0.82), 0.045, dark)
	Art._bar(root, Vector3(0.58, -0.15, -1.05), Vector3(0.58, -0.15, -1.79), 0.013, silver)
	Art._bar(root, Vector3(0.58, -0.15, -1.79), Vector3(0.62, -0.15, -1.71), 0.011, silver)
	for side: float in [-1.0, 1.0]:
		Detail.tube(root, [Vector3(0.58 + side * 0.07, -0.18, -1.45), Vector3(0.58 + side * 0.08, -0.17, -1.10), Vector3(0.58, -0.15, -1.02)], 0.015, yellow)
	var reel := Art._cylinder(root, Vector3(0.58, -0.28, -1.09), 0.075, 0.075, yellow)
	reel.rotation.z = PI / 2
	_move_parts(root, root.get_node("ArmRight"), weapon_parts)
	Detail.batch_joints(root)
	return root

static func _joint(parent: Node3D, label: String, pivot: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.name = label
	joint.position = pivot
	parent.add_child(joint)
	return joint

static func _move_parts(parent: Node3D, joint: Node3D, first_part: int) -> void:
	# Build in the original frame, then preserve that pose without needing a live tree.
	var inverse: Transform3D = joint.transform.affine_inverse()
	for part: Node3D in parent.get_children().slice(first_part):
		var original: Transform3D = part.transform
		part.reparent(joint, false)
		part.transform = inverse * original
