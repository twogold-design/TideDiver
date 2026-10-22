class_name RestaurantArt
extends Node3D
## A cutaway coastal restaurant. All geometry is local to this node.

const TABLE_POSITIONS: Array[Vector3] = [Vector3(-3.5, 0, -0.5), Vector3(3.5, 0, -0.5), Vector3(-3.5, 0, 3.5), Vector3(3.5, 0, 3.5)]
const CREAM: Color = Color("efdfbd")
const WOOD: Color = Color("ba865b")
const MINT: Color = Color("75aa98")
const INK: Color = Color("344f50")
var _room: Node3D
var _people: Node3D
var _customers: Dictionary = {}
var _materials: Dictionary = {}
var _renovation: Dictionary = {}
var _clock: float = 0.0
var _font: SystemFont
var _styles: Dictionary = {}
var _placed_tables: Array[Dictionary] = []
var _furniture_nodes: Dictionary = {}
var _ready_plates: Dictionary = {}
var _preview: Node3D
var _preview_key: String = ""
var _grid: Node3D
var _selection: Node3D
var _selected_uid: int = -1

func _material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key: String = color.to_html() + ":" + str(glow)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if glow > 0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	_materials[key] = material
	return material

func _mesh(parent: Node3D, shape: Mesh, pos: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = shape
	node.material_override = _material(color, glow)
	node.position = pos
	parent.add_child(node)
	return node

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = size
	return _mesh(parent, shape, pos, color, glow)

func _sphere(parent: Node3D, pos: Vector3, size: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var shape: SphereMesh = SphereMesh.new()
	shape.radius = 1.0
	shape.height = 2.0
	shape.radial_segments = 10
	shape.rings = 5
	var node: MeshInstance3D = _mesh(parent, shape, pos, color, glow)
	node.scale = size
	return node

func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top: float = -1.0) -> MeshInstance3D:
	var shape: CylinderMesh = CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = radius if top < 0 else top
	shape.height = height
	shape.radial_segments = 12
	return _mesh(parent, shape, pos, color)

func _bar(parent: Node3D, start: Vector3, end: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = _cylinder(parent, (start + end) * 0.5, radius, start.distance_to(end), color)
	var direction: Vector3 = (end - start).normalized()
	if absf(direction.dot(Vector3.UP)) < 0.999:
		node.quaternion = Quaternion(Vector3.UP, direction)
	return node

func _text(parent: Node3D, text: String, pos: Vector3, size: int = 46, pixel: float = 0.012, color: Color = CREAM) -> Label3D:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 2
	label.outline_modulate = Color(0.12, 0.22, 0.22, 0.75)
	label.position = pos
	parent.add_child(label)
	return label

func _plant(parent: Node3D, pos: Vector3, size: float = 1.0) -> void:
	_cylinder(parent, pos + Vector3(0, 0.22 * size, 0), 0.27 * size, 0.44 * size, Color("c98869"), 0.37 * size)
	_cylinder(parent, pos + Vector3(0, 0.44 * size, 0), 0.37 * size, 0.07 * size, Color("dfae87"))
	for i: int in range(7):
		var angle: float = float(i) * 2.399
		var leaf: MeshInstance3D = _sphere(parent, pos + Vector3(cos(angle) * 0.22 * size, (0.81 + float(i % 3) * 0.12) * size, sin(angle) * 0.22 * size), Vector3(0.14, 0.51, 0.08) * size, Color("518f73") if i % 2 else Color("7fab7f"))
		leaf.rotation = Vector3(sin(angle) * 0.35, angle, cos(angle) * 0.35)

func _palm(parent: Node3D, pos: Vector3, size: float) -> void:
	var crown: Vector3 = pos + Vector3(size * 0.25, size * 2.8, 0)
	_bar(parent, pos, crown, size * 0.15, Color("ab8c63"))
	for i: int in range(7):
		var angle: float = float(i) * TAU / 7.0
		var leaf: MeshInstance3D = _sphere(parent, crown + Vector3(cos(angle) * size * 0.8, 0, sin(angle) * size * 0.8), Vector3(size * 0.32, size * 0.08, size * 1.1), Color("648d6e") if i % 2 else Color("91ad78"))
		leaf.rotation = Vector3(0.25, -angle + PI / 2, 0)
	for i: int in range(3):
		_sphere(parent, crown + Vector3(float(i - 1) * 0.25, -0.18, 0.16), Vector3.ONE * 0.23, Color("8c7553"))

func rebuild(renovation: Dictionary, furnishings: Array = [], styles: Dictionary = {}) -> void:
	_styles = styles.duplicate(true)
	_placed_tables.clear()
	_furniture_nodes.clear()
	clear_layout_preview()
	_renovation = renovation.duplicate(true)
	if is_instance_valid(_room):
		remove_child(_room)
		_room.queue_free()
	_room = Node3D.new()
	_room.name = "RestaurantShell"
	add_child(_room)
	if not is_instance_valid(_people):
		_people = Node3D.new()
		_people.name = "RestaurantCustomers"
		add_child(_people)
	var clean: bool = bool(renovation.get("clean", false))
	_build_shore()
	_build_shell(clean)
	if not clean:
		_build_clutter()
	if bool(renovation.get("kitchen", false)):
		_build_kitchen()
	if not furnishings.is_empty():
		for value: Variant in furnishings:
			if value is Dictionary:
				var item: Dictionary = value
				if bool(item.get("placed", false)):
					_add_furniture(item)
	else:
		if bool(renovation.get("tables", false)):
			_build_table(0)
			_build_table(1)
		if bool(renovation.get("expansion", false)):
			_build_table(2)
			_build_table(3)
		if bool(renovation.get("decor", false)):
			for i: int in range(2):
				_add_furniture({"uid": 5 + i, "kind":"plant", "x":-5.5 if i == 0 else 5.5,"z":1.5,"rotation":0,"color":0,"placed":true})
				_add_furniture({"uid": 7 + i, "kind":"rug", "x":TABLE_POSITIONS[i].x,"z":TABLE_POSITIONS[i].z,"rotation":0,"color":0,"placed":true})
	if bool(renovation.get("sign", false)):
		_build_sign()
	if bool(renovation.get("decor", false)):
		_build_decor()
	var warm_light: OmniLight3D = OmniLight3D.new()
	warm_light.position = Vector3(0, 4.0, -0.8)
	warm_light.light_color = Color("ffe1b4")
	warm_light.light_energy = 0.5 if clean else 0.23
	warm_light.omni_range = 13
	warm_light.shadow_enabled = false
	_room.add_child(warm_light)
	var selected: int = _selected_uid
	_selected_uid = -1
	highlight_furniture(selected)

func _build_shore() -> void:
	_box(_room, Vector3(0, -0.65, 1), Vector3(43, 0.7, 37), Color("d9c499"))
	_box(_room, Vector3(0, -0.63, -29), Vector3(150, 0.2, 35), Color("77b9b7"))
	for i: int in range(7):
		_box(_room, Vector3(float(i % 2) * 4, -0.51, -13.0 - float(i) * 1.9), Vector3(42 - i * 3, 0.025, 0.12), Color("b6d6c5"))
	_palm(_room, Vector3(-10.5, -0.3, -5.5), 1.65)
	_palm(_room, Vector3(11.0, -0.3, -7.0), 1.35)
	for i: int in range(10):
		var p: Vector3 = Vector3(sin(float(i) * 4.1) * 17, -0.25, 7.5 + cos(float(i) * 2.8) * 8)
		_sphere(_room, p, Vector3(0.4 + float(i % 3) * 0.2, 0.2, 0.3), Color("b8b8a0"))
	# A front deck, steps and low maritime rope posts.
	_box(_room, Vector3(0, -0.16, 7.05), Vector3(14.3, 0.28, 3.2), Color("9b805d"))
	for i: int in range(20):
		_box(_room, Vector3(-6.85 + float(i) * 0.72, 0.005, 7.05), Vector3(0.69, 0.045, 3.2), Color("b99a71"))
	_box(_room, Vector3(0, -0.29, 9), Vector3(4, 0.16, 0.8), Color("ba9c76"))
	for x: float in [-6.7, 6.7]:
		for z: float in [6.0, 8.4]:
			_cylinder(_room, Vector3(x, 0.5, z), 0.10, 1.0, Color("9a7d59"))
		_bar(_room, Vector3(x, 0.8, 6.0), Vector3(x, 0.8, 8.4), 0.035, Color("ded2ad"))

func _build_shell(clean: bool) -> void:
	var floors: Array[Color] = [WOOD, Color("c5b893"), Color("779a91")]
	var walls: Array[Color] = [CREAM, Color("bbd3bd"), Color("dfb19a")]
	var floor_color: Color = floors[clampi(int(_styles.get("floor", 0)), 0, 2)] if clean else Color("827b68")
	var wall_color: Color = walls[clampi(int(_styles.get("wall", 0)), 0, 2)] if clean else Color("b1ac91")
	_box(_room, Vector3(0, -0.20, 0), Vector3(14.2, 0.4, 11.0), Color("86745b"))
	for i: int in range(20):
		var x: float = -6.65 + float(i) * 0.70
		var color: Color = floor_color.lightened(float(i % 4) * 0.025)
		if not clean and i % 5 == 1:
			_box(_room, Vector3(x, 0.015, -2.5), Vector3(0.66, 0.06, 4.6), color.darkened(0.2))
			_box(_room, Vector3(x, 0.015, 3.0), Vector3(0.66, 0.06, 3.6), color)
		else:
			_box(_room, Vector3(x, 0.015, 0), Vector3(0.67, 0.06, 10.8), color)
	_box(_room, Vector3(0, 2.2, -5.35), Vector3(14.1, 4.4, 0.24), wall_color)
	_box(_room, Vector3(0, 0.7, -5.17), Vector3(14, 1.4, 0.10), MINT if clean else Color("798b78"))
	_box(_room, Vector3(0, 1.43, -5.10), Vector3(14, 0.11, 0.12), Color("dcc8a1"))
	for x: float in [-7.0, 7.0]:
		_box(_room, Vector3(x, 0.55, 0), Vector3(0.18, 1.1, 10.8), wall_color)
		_box(_room, Vector3(x, 1.15, 0), Vector3(0.25, 0.12, 10.8), floor_color)
		_box(_room, Vector3(x, 2.3, -5.3), Vector3(0.27, 4.6, 0.4), floor_color)
	_box(_room, Vector3(0, 4.4, -5.25), Vector3(14.6, 0.24, 0.5), floor_color)
	# Back wall windows have blue panes and mint timber frames.
	for x: float in [-4.4, 4.4]:
		_box(_room, Vector3(x, 2.8, -5.18), Vector3(2.7, 1.8, 0.12), Color("80b8b9") if clean else Color("889c92"))
		for side: float in [-1.0, 1.0]:
			_box(_room, Vector3(x + side * 1.4, 2.8, -5.04), Vector3(0.12, 2.0, 0.15), MINT)
			_box(_room, Vector3(x, 2.8 + side * 0.96, -5.04), Vector3(2.9, 0.12, 0.15), MINT)
		_box(_room, Vector3(x, 2.8, -5.02), Vector3(0.09, 1.9, 0.15), CREAM)
		_box(_room, Vector3(x, 2.8, -5.02), Vector3(2.7, 0.08, 0.15), CREAM)
		_box(_room, Vector3(x, 1.8, -4.92), Vector3(3, 0.12, 0.42), WOOD)
	if not clean:
		for i: int in range(9):
			var mark: MeshInstance3D = _box(_room, Vector3(-6 + float(i) * 1.5, 0.5 + float(i % 3) * 0.17, -5.095), Vector3(0.5, 0.03, 0.02), Color("5e7066"))
			mark.rotation.z = sin(float(i) * 2) * 0.4
		var shutter: MeshInstance3D = _box(_room, Vector3(-4.4, 2.8, -4.88), Vector3(3.0, 0.22, 0.12), Color("8c8062"))
		shutter.rotation.z = 0.23
		_text(_room, "待修复", Vector3(0, 2.7, -5.10), 48, 0.012, Color("7f826d"))

func _build_clutter() -> void:
	for i: int in range(7):
		var p: Vector3 = Vector3(-4.7 + float(i % 4) * 2.4, 0.24, -2 + floorf(float(i) / 4.0) * 4)
		var crate: MeshInstance3D = _box(_room, p, Vector3(0.95, 0.45 + float(i % 2) * 0.4, 0.8), Color("97886a"))
		crate.rotation.y = float(i) * 0.7
		_box(_room, p + Vector3(0, 0.35, 0), Vector3(1, 0.08, 0.12), Color("b19a75"))
	for i: int in range(11):
		var plank: MeshInstance3D = _box(_room, Vector3(sin(float(i) * 7.3) * 5.3, 0.10 + float(i % 3) * 0.05, cos(float(i) * 3.2) * 4), Vector3(1.4 + float(i % 3) * 0.4, 0.08, 0.22), Color("88765b"))
		plank.rotation.y = float(i) * 1.1
	for i: int in range(5):
		_sphere(_room, Vector3(5.5 - float(i % 2) * 0.6, 0.30, -3.0 + float(i) * 0.7), Vector3(0.4, 0.32, 0.42), Color("687d70"))

func _build_kitchen() -> void:
	# A compact rear kitchen leaves the seating area unobstructed.
	_box(_room, Vector3(0, 0.72, -3.75), Vector3(11.5, 1.4, 1.8), MINT)
	_box(_room, Vector3(0, 1.47, -3.75), Vector3(11.8, 0.16, 1.95), Color("e2d1ad"))
	for i: int in range(6):
		var x: float = -4.7 + float(i) * 1.88
		_box(_room, Vector3(x, 0.72, -2.83), Vector3(1.7, 1.1, 0.035), Color("8eb7a2"))
		_box(_room, Vector3(x, 1.05, -2.78), Vector3(0.32, 0.055, 0.055), Color("d1bd87"))
	# Stove, burners, pot, cutting board and preparation tools.
	_box(_room, Vector3(-2.7, 1.59, -3.65), Vector3(2.0, 0.1, 1.3), INK)
	for x: float in [-3.2, -2.25]:
		for z: float in [-3.95, -3.32]:
			_cylinder(_room, Vector3(x, 1.66, z), 0.25, 0.03, Color("72847b"))
	_cylinder(_room, Vector3(-3.2, 1.91, -3.95), 0.32, 0.48, Color("bdc3ae"))
	_cylinder(_room, Vector3(-3.2, 2.16, -3.95), 0.34, 0.055, Color("d5d5ba"))
	_sphere(_room, Vector3(-3.2, 2.22, -3.95), Vector3(0.08, 0.06, 0.08), INK)
	# Sink is a dark basin edged in pale metal with a curved angular tap.
	_box(_room, Vector3(3.8, 1.59, -3.72), Vector3(1.8, 0.07, 1.25), Color("c6d2c4"))
	_box(_room, Vector3(3.8, 1.64, -3.72), Vector3(1.5, 0.02, 0.96), Color("6b9595"))
	_bar(_room, Vector3(3.8, 1.6, -4.3), Vector3(3.8, 2.25, -4.3), 0.065, Color("c8d5c3"))
	_bar(_room, Vector3(3.8, 2.25, -4.3), Vector3(3.8, 2.25, -3.92), 0.065, Color("c8d5c3"))
	_box(_room, Vector3(0.2, 1.59, -3.55), Vector3(1.3, 0.09, 0.8), Color("c99465"))
	_box(_room, Vector3(0.6, 1.68, -3.62), Vector3(0.42, 0.025, 0.10), Color("d5dbcc"))
	_box(_room, Vector3(0.28, 1.68, -3.62), Vector3(0.25, 0.04, 0.10), INK)
	for i: int in range(3):
		_cylinder(_room, Vector3(1.35 + float(i) * 0.33, 1.77, -4.18), 0.11, 0.35, Color("ddba7e") if i % 2 else Color("b97959"))
	# Open wall shelf, dishes, kitchen label, apron-clad chef.
	_box(_room, Vector3(0, 3.25, -4.82), Vector3(4.0, 0.13, 0.7), WOOD)
	for i: int in range(4):
		_cylinder(_room, Vector3(-1.3 + float(i) * 0.55, 3.4, -4.8), 0.22, 0.2, CREAM)
	_text(_room, "COASTAL KITCHEN", Vector3(0, 2.65, -5.07), 30, 0.01, INK)
	var chef: Node3D = _person(-1, Color("f2e7c8"), true)
	chef.position = Vector3(-0.3, 0, -2.23)
	chef.rotation.y = PI
	_room.add_child(chef)

func _build_table(seat: int) -> void:
	_add_furniture({"uid":seat + 1,"kind":"table","x":TABLE_POSITIONS[seat].x,"z":TABLE_POSITIONS[seat].z,"rotation":0,"color":0,"placed":true})

func _add_furniture(item: Dictionary) -> void:
	var kind: String = str(item.get("kind", ""))
	var seat: int = -1
	if kind == "table" and _placed_tables.size() < (4 if bool(_renovation.get("expansion", false)) else 2):
		seat = _placed_tables.size()
		_placed_tables.append(item.duplicate(true))
	var model: Node3D = _furniture_model(_room, item, seat)
	_furniture_nodes[int(item.get("uid", -1))] = model

func _furniture_model(parent: Node3D, item: Dictionary, seat: int = -1) -> Node3D:
	var group: Node3D = Node3D.new()
	group.name = "Furniture_%d" % int(item.get("uid", -1))
	group.position = Vector3(float(item.get("x", 0)), 0, float(item.get("z", 0)))
	group.rotation.y = float(posmod(int(item.get("rotation", 0)), 4)) * PI / 2.0
	group.set_meta("uid", int(item.get("uid", -1)))
	group.set_meta("kind", str(item.get("kind", "")))
	parent.add_child(group)
	var palette: Array[Color] = [Color("c29a6a"), Color("79b4a3"), Color("d88d78")]
	var tint: Color = palette[clampi(int(item.get("color", 0)), 0, 2)]
	var kind: String = str(item.get("kind", ""))
	match kind:
		"table":
			_table_model(group, seat, tint)
		"plant":
			_plant(group, Vector3(0, 0.05, 0), 0.90)
			_cylinder(group, Vector3(0, 0.24, 0), 0.26, 0.40, tint, 0.34)
			_cylinder(group, Vector3(0, 0.45, 0), 0.35, 0.06, tint.lightened(0.15))
		"rug":
			_box(group, Vector3(0, 0.082, 0), Vector3(2.8, 0.025, 3.2), tint.darkened(0.20))
			_box(group, Vector3(0, 0.098, 0), Vector3(2.52, 0.009, 2.92), tint)
			for side: float in [-1.0, 1.0]:
				_box(group, Vector3(0, 0.107, side * 1.27), Vector3(2.35, 0.01, 0.10), CREAM)
				for i: int in range(10):
					_box(group, Vector3(-1.2 + float(i) * 0.267, 0.075, side * 1.57), Vector3(0.05, 0.016, 0.06), CREAM)
			var diamond: MeshInstance3D = _box(group, Vector3(0, 0.108, 0), Vector3(0.60, 0.012, 0.60), tint.darkened(0.25))
			diamond.rotation.y = PI / 4
		"lamp":
			_cylinder(group, Vector3(0, 0.10, 0), 0.30, 0.12, tint.darkened(0.35))
			_cylinder(group, Vector3(0, 1.1, 0), 0.045, 2.05, tint.darkened(0.30))
			_cylinder(group, Vector3(0, 2.15, 0), 0.38, 0.48, tint.lightened(0.15), 0.23)
			_sphere(group, Vector3(0, 1.94, 0), Vector3.ONE * 0.14, Color("ffe2a5"), 0.7)
			var light: OmniLight3D = OmniLight3D.new()
			light.position = Vector3(0, 1.95, 0)
			light.light_color = Color("ffddb0")
			light.light_energy = 0.20
			light.omni_range = 3.8
			group.add_child(light)
		"shelf":
			for x: float in [-0.83, 0.83]:
				_box(group, Vector3(x, 0.95, 0), Vector3(0.12, 1.85, 0.75), tint)
			_box(group, Vector3(0, 0.95, -0.35), Vector3(1.7, 1.85, 0.06), tint.darkened(0.12))
			for y: float in [0.16, 0.90, 1.83]:
				_box(group, Vector3(0, y, 0), Vector3(1.78, 0.10, 0.80), tint.lightened(0.08))
			for i: int in range(4):
				_box(group, Vector3(-0.55 + float(i) * 0.18, 0.48, -0.05), Vector3(0.13, 0.53 + float(i % 2) * 0.12, 0.42), MINT if i % 2 else Color("d5b37f"))
			_cylinder(group, Vector3(0.42, 1.20, 0), 0.17, 0.48, CREAM, 0.12)
			_sphere(group, Vector3(-0.39, 1.18, -0.04), Vector3(0.22, 0.21, 0.15), Color("a5b9af"))
	return group

func _table_model(group: Node3D, seat: int, tint: Color) -> void:
	_cylinder(group, Vector3(0, 1.28, 0), 1.10, 0.16, tint.lightened(0.10))
	_cylinder(group, Vector3(0, 0.64, 0), 0.16, 1.2, tint.darkened(0.25))
	_cylinder(group, Vector3(0, 0.10, 0), 0.52, 0.12, tint.darkened(0.25))
	# Complete table and chair group stays inside the 2.5 x 3.8 m footprint.
	for side: float in [-1.0, 1.0]:
		var z: float = side * 1.40
		_box(group, Vector3(0, 0.7, z), Vector3(0.95, 0.13, 0.80), tint)
		_box(group, Vector3(0, 1.2, z + side * 0.34), Vector3(0.95, 0.85, 0.12), tint)
		for x: float in [-0.35, 0.35]:
			for offset: float in [-0.28, 0.28]:
				_box(group, Vector3(x, 0.35, z + offset), Vector3(0.09, 0.7, 0.09), tint.darkened(0.25))
	_cylinder(group, Vector3(0.45, 1.43, 0), 0.10, 0.25, Color("bc805c"))
	_sphere(group, Vector3(0.45, 1.65, 0), Vector3(0.19, 0.20, 0.16), Color("789d68"))
	_cylinder(group, Vector3(-0.3, 1.41, 0.65), 0.12, 0.25, CREAM)
	if seat >= 0:
		_box(group, Vector3(0.5, 1.49, 0.55), Vector3(0.30, 0.30, 0.035), CREAM)
		_text(group, str(seat + 1), Vector3(0.5, 1.49, 0.58), 32, 0.006, INK)
func _build_sign() -> void:
	# Sign rests above the rear wall, so it never masks guests or interaction space.
	_box(_room, Vector3(0, 4.75, -5.1), Vector3(7.5, 1.4, 0.25), Color("466f66"))
	for y: float in [4.04, 5.46]:
		_box(_room, Vector3(0, y, -5.0), Vector3(7.7, 0.10, 0.15), Color("ddbd7e"))
	_text(_room, "TIDE TABLE", Vector3(0, 5.00, -4.93), 64, 0.012, Color("ffe8ac"))
	_text(_room, "潮 间 食 堂", Vector3(0, 4.45, -4.92), 37, 0.012, Color("f1dfb5"))
	for x: float in [-3.45, 3.45]:
		_sphere(_room, Vector3(x, 4.75, -4.87), Vector3.ONE * 0.11, Color("ffe2a0"), 1.1)
	var glow: OmniLight3D = OmniLight3D.new()
	glow.position = Vector3(0, 4.7, -3.9)
	glow.light_color = Color("ffd393")
	glow.light_energy = 0.45
	glow.omni_range = 5
	_room.add_child(glow)

func _build_decor() -> void:
	# Interior decorations are placed furniture; only terrace plants stay fixed.
	_plant(_room, Vector3(-5.0, 0.05, 7), 1.15)
	_plant(_room, Vector3(5.0, 0.05, 7), 1.15)
	# Two slender posts support a gentle light string above the open room.
	for x: float in [-6.8, 6.8]:
		_cylinder(_room, Vector3(x, 2.0, 4.8), 0.065, 4.0, Color("947250"))
	var previous: Vector3 = Vector3(-6.8, 4.0, 4.8)
	for i: int in range(1, 17):
		var f: float = float(i) / 16.0
		var current: Vector3 = Vector3(-6.8 + 13.6 * f, 4.0 - sin(f * PI) * 0.65, 4.8)
		_bar(_room, previous, current, 0.018, INK)
		if i % 2 == 0:
			_bar(_room, current, current + Vector3(0, -0.15, 0), 0.02, INK)
			_sphere(_room, current + Vector3(0, -0.23, 0), Vector3(0.09, 0.12, 0.09), Color("ffdc99"), 1.0)
		previous = current
	# A framed maritime print and a life ring on the wall.
	_box(_room, Vector3(6.3, 2.9, -5.0), Vector3(0.7, 1.35, 0.10), WOOD)
	_box(_room, Vector3(6.3, 2.9, -4.93), Vector3(0.56, 1.18, 0.025), Color("d4d9bd"))
	_sphere(_room, Vector3(6.3, 2.85, -4.90), Vector3(0.20, 0.11, 0.025), Color("779f9c"))
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.32
	ring_mesh.outer_radius = 0.53
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 8
	var ring: MeshInstance3D = _mesh(_room, ring_mesh, Vector3(-6.3, 2.9, -4.9), Color("e8b18a"))
	ring.rotation.x = PI / 2
	_text(_room, "FRESH FROM THE TIDE", Vector3(0, 3.8, -5.06), 28, 0.008, Color("6a8c7f"))

func _person(identity: int, shirt: Color, chef: bool = false) -> Node3D:
	var person: Node3D = Node3D.new()
	var skin_colors: Array[Color] = [Color("d9aa80"), Color("aa7657"), Color("edc6a0"), Color("c89673")]
	var skin: Color = skin_colors[posmod(identity, skin_colors.size())]
	var torso: MeshInstance3D = _sphere(person, Vector3(0, 1.15, 0), Vector3(0.36, 0.48, 0.27), shirt)
	torso.name = "Torso"
	var head: MeshInstance3D = _sphere(person, Vector3(0, 1.82, -0.03), Vector3(0.28, 0.33, 0.27), skin)
	head.name = "Head"
	_sphere(person, Vector3(0, 2.00, 0.01), Vector3(0.29, 0.19, 0.26), Color("574a3c") if identity % 2 else Color("a3855e"))
	for side: float in [-1.0, 1.0]:
		_sphere(person, Vector3(side * 0.10, 1.86, -0.28), Vector3(0.028, 0.035, 0.018), INK)
		if chef:
			_bar(person, Vector3(side * 0.18, 0.87, 0), Vector3(side * 0.19, 0.18, 0), 0.11, Color("4c6260"))
		else:
			_bar(person, Vector3(side * 0.18, 0.80, 0), Vector3(side * 0.18, 0.75, -0.48), 0.12, Color("526974"))
			_bar(person, Vector3(side * 0.18, 0.75, -0.48), Vector3(side * 0.18, 0.15, -0.48), 0.10, Color("526974"))
		_sphere(person, Vector3(side * 0.18, 0.12, -0.56), Vector3(0.13, 0.10, 0.21), INK)
		_bar(person, Vector3(side * 0.30, 1.35, 0), Vector3(side * 0.40, 1.37, -0.42), 0.10, shirt)
		_sphere(person, Vector3(side * 0.40, 1.37, -0.48), Vector3.ONE * 0.10, skin)
	if chef:
		_box(person, Vector3(0, 1.00, -0.26), Vector3(0.51, 0.62, 0.025), Color("8caea0"))
		_cylinder(person, Vector3(0, 2.19, 0), 0.31, 0.19, CREAM)
		_sphere(person, Vector3(0, 2.34, 0), Vector3(0.37, 0.24, 0.31), Color("f2e7cb"))
	else:
		var status: Label3D = _text(person, "", Vector3(0, 2.65, 0), 29, 0.012, CREAM)
		status.name = "Status"
		status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		status.no_depth_test = false
		var badge: MeshInstance3D = _sphere(person, Vector3(0, 2.32, 0), Vector3.ONE * 0.07, Color("e9c97f"), 0.3)
		badge.name = "Badge"
	return person

func set_customers(orders: Array) -> void:
	if not is_instance_valid(_people):
		_people = Node3D.new()
		_people.name = "RestaurantCustomers"
		add_child(_people)
	var present: Dictionary = {}
	for value: Variant in orders:
		if not value is Dictionary:
			continue
		var order: Dictionary = value
		var identity: int = int(order.get("id", -1))
		var seat: int = int(order.get("seat", -1))
		if identity < 0 or seat < 0 or seat >= _placed_tables.size():
			continue
		present[identity] = true
		var person: Node3D
		if _customers.has(identity):
			person = _customers[identity] as Node3D
		else:
			var shirts: Array[Color] = [Color("d58d72"), Color("77a59b"), Color("d6bd72"), Color("8e9eb9"), Color("b49aa7")]
			person = _person(identity, shirts[posmod(identity, shirts.size())])
			person.name = "Guest%d" % identity
			_people.add_child(person)
			_customers[identity] = person
		var table: Dictionary = _placed_tables[seat]
		var table_rotation: float = float(posmod(int(table.get("rotation", 0)), 4)) * PI / 2.0
		person.position = Vector3(float(table.get("x", 0)), 0, float(table.get("z", 0))) + Vector3(0, 0, 1.40).rotated(Vector3.UP, table_rotation)
		person.rotation.y = table_rotation
		person.set_meta("seat", seat)
		person.set_meta("state", str(order.get("state", "waiting")))
		var status: Label3D = person.get_node("Status") as Label3D
		var state: String = str(order.get("state", "waiting"))
		var dish: String = str(order.get("dish", "orange"))
		status.text = "%d · %s" % [seat + 1, "待制作" if state == "waiting" else ("制作中" if state == "cooking" else "待上菜")]
		status.modulate = Color("ffdf9c") if state == "waiting" else (Color("b5e4d4") if state == "cooking" else Color("fff2c9"))
		var badge: MeshInstance3D = person.get_node("Badge") as MeshInstance3D
		badge.material_override = _material(status.modulate, 0.3)
		# Pass plates live beside customers, independently of their table transform.
		var existing: Node3D = _ready_plates.get(identity) as Node3D
		if state == "ready" and not is_instance_valid(existing):
			var plate: Node3D = Node3D.new()
			plate.name = "ReadyPlate_%d" % identity
			_people.add_child(plate)
			_ready_plates[identity] = plate
			plate.position = Vector3(-1.0 + float(seat) * 0.75, 1.61, -3.05)
			_cylinder(plate, Vector3.ZERO, 0.31, 0.04, CREAM)
			_sphere(plate, Vector3(0, 0.10, 0), Vector3(0.20, 0.08, 0.12), Color("d98c62") if dish == "orange" else (Color("95b7a8") if dish == "blue" else Color("cb94a8")))
			_sphere(plate, Vector3(0.16, 0.09, 0.1), Vector3(0.07, 0.06, 0.09), Color("80a968"))
		elif state == "ready" and is_instance_valid(existing):
			existing.position = Vector3(-1.0 + float(seat) * 0.75, 1.61, -3.05)
		elif is_instance_valid(existing):
			_people.remove_child(existing)
			existing.queue_free()
			_ready_plates.erase(identity)
	for identity: Variant in _customers.keys():
		if not present.has(identity):
			var person: Node3D = _customers[identity] as Node3D
			_people.remove_child(person)
			person.queue_free()
			_customers.erase(identity)
			var plate: Node3D = _ready_plates.get(identity) as Node3D
			if is_instance_valid(plate):
				_people.remove_child(plate)
				plate.queue_free()
			_ready_plates.erase(identity)

func animate(delta: float) -> void:
	_clock += delta
	for identity: Variant in _customers:
		var person: Node3D = _customers[identity] as Node3D
		var torso: Node3D = person.get_node("Torso") as Node3D
		var head: Node3D = person.get_node("Head") as Node3D
		var phase: float = _clock * 1.6 + float(identity) * 1.3
		torso.scale.y = 0.48 * (1.0 + sin(phase) * 0.012)
		head.rotation.z = sin(phase * 0.6) * 0.035




func _footprint(kind: String) -> Vector2:
	match kind:
		"table": return Vector2(2.5, 3.8)
		"rug": return Vector2(2.8, 3.2)
		"shelf": return Vector2(1.8, 0.8)
	return Vector2(0.8, 0.8)

func _overlay_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _outline(parent: Node3D, size: Vector2, color: Color, fill: bool = true) -> void:
	var border: StandardMaterial3D = _overlay_material(color, 0.95)
	if fill:
		var area: MeshInstance3D = _box(parent, Vector3(0, 0.115, 0), Vector3(size.x, 0.008, size.y), color)
		area.material_override = _overlay_material(color, 0.12)
		area.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side: float in [-1.0, 1.0]:
		var a: MeshInstance3D = _box(parent, Vector3(side * size.x * 0.5, 0.13, 0), Vector3(0.045, 0.015, size.y + 0.045), color)
		a.material_override = border
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var b: MeshInstance3D = _box(parent, Vector3(0, 0.13, side * size.y * 0.5), Vector3(size.x + 0.045, 0.015, 0.045), color)
		b.material_override = border
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ghost(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif node is Light3D:
		(node as Light3D).visible = false
	elif node is Label3D:
		(node as Label3D).visible = false
	for child: Node in node.get_children():
		_ghost(child, material)

func set_layout_preview(kind: String, pos: Vector3, rotation: int, color: int, valid: bool) -> void:
	var key: String = "%s|%.4f|%.4f|%d|%d|%s" % [kind, pos.x, pos.z, posmod(rotation, 4), color, str(valid)]
	if key == _preview_key and is_instance_valid(_preview):
		return
	clear_layout_preview()
	_preview_key = key
	_preview = Node3D.new()
	_preview.name = "LayoutPreview"
	_preview.position = Vector3(pos.x, 0, pos.z)
	_preview.rotation.y = float(posmod(rotation, 4)) * PI / 2.0
	add_child(_preview)
	var tint: Color = Color("6ce7b1") if valid else Color("ff776f")
	var model: Node3D = _furniture_model(_preview, {"uid":-999,"kind":kind,"x":0,"z":0,"rotation":0,"color":color})
	_ghost(model, _overlay_material(tint, 0.27))
	_outline(_preview, _footprint(kind), tint)

func clear_layout_preview() -> void:
	_preview_key = ""
	if is_instance_valid(_preview):
		remove_child(_preview)
		_preview.queue_free()
	_preview = null

func set_layout_grid(enabled: bool) -> void:
	if not is_instance_valid(_grid):
		if not enabled:
			return
		_grid = Node3D.new()
		_grid.name = "LayoutGrid"
		add_child(_grid)
		var grid_mat: StandardMaterial3D = _overlay_material(Color("e7f3d3"), 0.33)
		for i: int in range(-12, 13):
			var line: MeshInstance3D = _box(_grid, Vector3(float(i) * 0.5, 0.075, 1.475), Vector3(0.012, 0.008, 7.85), CREAM)
			line.material_override = grid_mat
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i: int in range(-4, 11):
			var line: MeshInstance3D = _box(_grid, Vector3(0, 0.075, float(i) * 0.5), Vector3(12.6, 0.008, 0.012), CREAM)
			line.material_override = grid_mat
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var bounds: Node3D = Node3D.new()
		bounds.position = Vector3(0, 0, 1.475)
		_grid.add_child(bounds)
		_outline(bounds, Vector2(12.6, 7.85), Color("d8e7c5"), false)
		var corridor: MeshInstance3D = _box(_grid, Vector3(0, 0.083, 1.475), Vector3(1.6, 0.008, 7.85), Color("e8bf73"))
		corridor.name = "ClearCentralAisle"
		corridor.material_override = _overlay_material(Color("e8bf73"), 0.17)
		corridor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for side: float in [-1.0, 1.0]:
			for i: int in range(10):
				var dash: MeshInstance3D = _box(_grid, Vector3(side * 0.8, 0.095, -2.15 + float(i) * 0.76), Vector3(0.025, 0.008, 0.38), Color("e8bf73"))
				dash.material_override = _overlay_material(Color("e8bf73"), 0.65)
				dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid.visible = enabled
	if not enabled:
		clear_layout_preview()
		highlight_furniture(-1)

func highlight_furniture(uid: int) -> void:
	if _selected_uid == uid and (uid < 0 or is_instance_valid(_selection)):
		return
	_selected_uid = uid
	if is_instance_valid(_selection):
		remove_child(_selection)
		_selection.queue_free()
	_selection = null
	if not _furniture_nodes.has(uid):
		return
	var model: Node3D = _furniture_nodes[uid] as Node3D
	if not is_instance_valid(model):
		return
	_selection = Node3D.new()
	_selection.name = "FurnitureSelection"
	_selection.position = model.position
	_selection.rotation = model.rotation
	add_child(_selection)
	_outline(_selection, _footprint(str(model.get_meta("kind", ""))), Color("ffe08b"), false)

