extends RefCounted
## Static character details. Animated joints remain separate Node3Ds.
const Art = preload("res://scripts/furniture_art.gd")

static func cloth(color: Color) -> Material:
	return Art._mat(color, 2, 0.88)

static func loft(parent: Node3D, profiles: Array[Vector3], material: Material) -> MeshInstance3D:
	# Profiles are (height, half width, half depth), from bottom to top.
	const SEGMENTS: int = 32
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row: int in range(profiles.size()):
		var p: Vector3 = profiles[row]
		var before: Vector3 = profiles[maxi(0, row - 1)]
		var after: Vector3 = profiles[mini(profiles.size() - 1, row + 1)]
		var slope: Vector3 = (after - before) / maxf(after.x - before.x, 0.001)
		for i: int in range(SEGMENTS):
			var angle: float = TAU * float(i) / SEGMENTS
			vertices.append(Vector3(sin(angle) * p.y, p.x, cos(angle) * p.z))
			var normal := Vector3(sin(angle) / p.y, -sin(angle) * sin(angle) * slope.y / p.y - cos(angle) * cos(angle) * slope.z / p.z, cos(angle) / p.z)
			normals.append(normal.normalized())
			if row < profiles.size() - 1:
				var a: int = row * SEGMENTS + i
				var b: int = row * SEGMENTS + (i + 1) % SEGMENTS
				indices.append_array(PackedInt32Array([a, a + SEGMENTS, b, b, a + SEGMENTS, b + SEGMENTS]))
	for row: int in [0, profiles.size() - 1]:
		var first: int = vertices.size()
		var p: Vector3 = profiles[row]
		var normal: Vector3 = Vector3.DOWN if row == 0 else Vector3.UP
		vertices.append(Vector3(0, p.x, 0))
		normals.append(normal)
		for i: int in range(SEGMENTS):
			vertices.append(vertices[row * SEGMENTS + i])
			normals.append(normal)
		for i: int in range(SEGMENTS):
			var a: int = first + 1 + i
			var b: int = first + 1 + (i + 1) % SEGMENTS
			indices.append_array(PackedInt32Array([first, a, b] if row == 0 else [first, b, a]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return Art._mesh(parent, mesh, Vector3.ZERO, material)

static func tube(parent: Node3D, points: Array[Vector3], radius: float, material: Material) -> void:
	for i: int in range(points.size() - 1):
		Art._bar(parent, points[i], points[i + 1], radius, material)
	for point: Vector3 in points:
		Art._sphere(parent, point, Vector3.ONE * radius, material)

static func batch_joints(root: Node3D) -> void:
	for child: Node in root.get_children():
		if child is Node3D and not child is MeshInstance3D:
			batch_joints(child)
	Art._merge_geometry(root)
