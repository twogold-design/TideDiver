class_name RestaurantPerson
extends Node3D
## Small articulated actor. advance(delta) is the only clock; there is no _process,
## Timer, Tween or TIME shader, so the restaurant can pause every gesture exactly.

const Feedback = preload("res://scripts/customer_feedback.gd")
static var _materials: Dictionary = {}
static var _sphere_mesh: SphereMesh
static var _limb_mesh: CylinderMesh
static var _font: SystemFont

var identity: int = 0
var is_chef: bool = false
var state: String = "waiting"
var patience_ratio: float = 1.0
var reaction: String = ""
var reaction_age: float = 0.0
var elapsed: float = 0.0
var walking: bool = false
var cooking_count: int = 0
var ready_count: int = 0
var _seat: int = 0
var _live_feedback: Dictionary = {}
var _torso: Node3D
var _head: Node3D
var _status: Label3D
var _bubble: MeshInstance3D
var _badge: MeshInstance3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_elbow: Node3D
var _right_elbow: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_knee: Node3D
var _right_knee: Node3D
var _eyes: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _mouth: Node3D
var _knife: Node3D
var _spoon: Node3D
var _reaction_message: String = ""
var _dish: Node3D
var _fork: Node3D
var _last_feedback: String = ""
var _last_tint: Color = Color.TRANSPARENT

func _mat(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key: String = color.to_html() + str(glow)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.12)
	mat.roughness = 0.82
	if glow > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	_materials[key] = mat
	return mat

func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color)
	node.position = pos
	parent.add_child(node)
	return node

func _ball(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radius = 1.0
		_sphere_mesh.height = 2.0
		_sphere_mesh.radial_segments = 20
		_sphere_mesh.rings = 10
	var node: MeshInstance3D = _mesh(parent, _sphere_mesh, pos, color)
	node.scale = size
	return node

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = size
	return _mesh(parent, shape, pos, color)

func _link(parent: Node3D, start: Vector3, finish: Vector3, radius: float, color: Color) -> MeshInstance3D:
	if _limb_mesh == null:
		_limb_mesh = CylinderMesh.new()
		_limb_mesh.top_radius = 1.0
		_limb_mesh.bottom_radius = 1.0
		_limb_mesh.height = 1.0
		_limb_mesh.radial_segments = 12
	var node: MeshInstance3D = _mesh(parent, _limb_mesh, (start + finish) * 0.5, color)
	node.scale = Vector3(radius, start.distance_to(finish), radius)
	var direction: Vector3 = (finish - start).normalized()
	if absf(direction.dot(Vector3.UP)) < 0.999:
		node.quaternion = Quaternion(Vector3.UP, direction)
	return node

func _joint(parent: Node3D, joint_name: String, pos: Vector3) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = joint_name
	node.position = pos
	parent.add_child(node)
	return node

func setup(actor_id: int, shirt: Color, chef: bool = false) -> void:
	identity = actor_id
	is_chef = chef
	var skins: Array[Color] = [Color("d9aa80"), Color("aa7657"), Color("edc6a0"), Color("c89673")]
	var skin: Color = skins[posmod(identity, skins.size())]
	var ink: Color = Color("344a49")
	_torso = _joint(self, "Torso", Vector3(0, 1.28 if chef else 1.15, 0))
	_ball(_torso, Vector3.ZERO, Vector3(0.35, 0.46, 0.26), shirt)
	if chef:
		_box(_torso, Vector3(0, -0.13, -0.255), Vector3(0.50, 0.63, 0.035), Color("83a392"))
		for x: float in [-0.17, 0.17]:
			_link(_torso, Vector3(x, 0.33, -0.18), Vector3(x, -0.12, -0.27), 0.024, Color("c4c9ad"))
		_box(_torso, Vector3(0, -0.22, -0.28), Vector3(0.28, 0.16, 0.02), Color("6c8e7d"))
	else:
		_link(_torso, Vector3(-0.14, 0.30, -0.18), Vector3(0.14, 0.30, -0.18), 0.023, shirt.lightened(0.18))
	_head = _joint(self, "Head", Vector3(0, 1.95 if chef else 1.82, -0.03))
	_ball(_head, Vector3.ZERO, Vector3(0.28, 0.33, 0.27), skin)
	_ball(_head, Vector3(0, 0.18, 0.04), Vector3(0.29, 0.19, 0.26), Color("574a3c") if identity % 2 else Color("a3855e"))
	_ball(_head, Vector3(0, -0.025, -0.275), Vector3(0.045, 0.055, 0.055), skin.darkened(0.06))
	for side: float in [-1.0, 1.0]:
		_ball(_head, Vector3(side * 0.28, 0, 0), Vector3(0.055, 0.085, 0.06), skin)
		var eye: MeshInstance3D = _ball(_head, Vector3(side * 0.10, 0.055, -0.257), Vector3(0.029, 0.037, 0.019), ink)
		eye.name = "EyeLeft" if side < 0 else "EyeRight"
		_eyes.append(eye)
		var brow: Node3D = _joint(_head, "BrowLeft" if side < 0 else "BrowRight", Vector3(side * 0.10, 0.135, -0.24))
		_link(brow, Vector3(-0.045, 0, 0), Vector3(0.045, 0, 0), 0.012, ink)
		_brows.append(brow)
		_ball(_head, Vector3(side * 0.17, -0.065, -0.225), Vector3(0.043, 0.023, 0.012), skin.lerp(Color("dd927d"), 0.26))
	_mouth = _joint(_head, "Mouth", Vector3(0, -0.13, -0.25))
	_link(_mouth, Vector3(-0.065, 0.024, 0), Vector3(0, 0, -0.014), 0.010, Color("84594b"))
	_link(_mouth, Vector3(0, 0, -0.014), Vector3(0.065, 0.024, 0), 0.010, Color("84594b"))
	if chef:
		_ball(_head, Vector3(0, 0.39, 0.02), Vector3(0.31, 0.10, 0.28), Color("ded4b9"))
		for i: int in range(3):
			_ball(_head, Vector3(float(i - 1) * 0.15, 0.53, 0.02), Vector3(0.23, 0.20, 0.23), Color("e7ddc4"))
	_left_arm = _arm(-1.0, shirt, skin)
	_right_arm = _arm(1.0, shirt, skin)
	_left_elbow = _left_arm.get_node("Elbow") as Node3D
	_right_elbow = _right_arm.get_node("Elbow") as Node3D
	_left_leg = _leg(-1.0, ink)
	_right_leg = _leg(1.0, ink)
	_left_knee = _left_leg.get_node("Knee") as Node3D
	_right_knee = _right_leg.get_node("Knee") as Node3D
	var hand: Node3D = _right_elbow.get_node("Hand") as Node3D
	_knife = _joint(hand, "ChefKnife", Vector3(0, -0.03, -0.02))
	_box(_knife, Vector3(0, 0, -0.10), Vector3(0.045, 0.05, 0.16), Color("756048"))
	_box(_knife, Vector3(0, 0.02, -0.26), Vector3(0.025, 0.13, 0.21), Color("aab9af"))
	_knife.visible = false
	_spoon = _joint(hand, "ChefSpoon", Vector3.ZERO)
	_link(_spoon, Vector3.ZERO, Vector3(0, 0, -0.31), 0.018, Color("af8554"))
	_ball(_spoon, Vector3(0, 0, -0.33), Vector3(0.055, 0.022, 0.075), Color("af8554"))
	_spoon.visible = false
	_fork = _joint(hand, "TastingFork", Vector3.ZERO)
	_link(_fork, Vector3(0, 0, 0), Vector3(0, 0, -0.23), 0.012, Color("b6c6b5"))
	for x: float in [-0.024, 0, 0.024]:
		_link(_fork, Vector3(x, 0, -0.19), Vector3(x, 0, -0.27), 0.006, Color("b6c6b5"))
	_fork.visible = false
	_dish = _joint(_torso, "HeldDish", Vector3(-0.10, 0.25, -0.54))
	_ball(_dish, Vector3.ZERO, Vector3(0.27, 0.035, 0.23), Color("d8d4bc"))
	_ball(_dish, Vector3(0, 0.06, 0), Vector3(0.17, 0.05, 0.10), Color("cc8d5e"))
	_ball(_dish, Vector3(0.13, 0.06, 0.08), Vector3(0.055, 0.04, 0.07), Color("789456"))
	_dish.visible = false
	_build_feedback()
	_apply_pose()

func _arm(side: float, shirt: Color, skin: Color) -> Node3D:
	var shoulder: Node3D = _joint(_torso, "LeftShoulder" if side < 0 else "RightShoulder", Vector3(side * 0.31, 0.23, 0))
	_ball(shoulder, Vector3.ZERO, Vector3.ONE * 0.115, shirt)
	_link(shoulder, Vector3.ZERO, Vector3(0, -0.29, 0), 0.10, shirt)
	var elbow: Node3D = _joint(shoulder, "Elbow", Vector3(0, -0.29, 0))
	_ball(elbow, Vector3.ZERO, Vector3.ONE * 0.095, skin)
	_link(elbow, Vector3.ZERO, Vector3(0, -0.29, 0), 0.075, skin)
	var hand: Node3D = _joint(elbow, "Hand", Vector3(0, -0.31, 0))
	_ball(hand, Vector3.ZERO, Vector3(0.085, 0.10, 0.065), skin)
	return shoulder

func _leg(side: float, ink: Color) -> Node3D:
	var hip: Node3D = _joint(self, "LeftHip" if side < 0 else "RightHip", Vector3(side * 0.17, 0.88 if is_chef else 0.79, 0))
	_link(hip, Vector3.ZERO, Vector3(0, -0.40, 0), 0.11, Color("506772"))
	var knee: Node3D = _joint(hip, "Knee", Vector3(0, -0.40, 0))
	_link(knee, Vector3.ZERO, Vector3(0, -0.39, 0), 0.09, Color("506772"))
	_ball(knee, Vector3(0, -0.36, -0.07), Vector3(0.12, 0.09, 0.19), ink)
	return hip

func _build_feedback() -> void:
	var height: float = 3.05 if is_chef else 2.65
	var panel_mesh: QuadMesh = QuadMesh.new()
	panel_mesh.size = Vector2(3.8, 1.05 if is_chef else 0.64)
	_bubble = _mesh(self, panel_mesh, Vector3(0, height, 0), Color("23484b"))
	_bubble.name = "FeedbackBubble"
	var panel_mat: StandardMaterial3D = StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.07, 0.17, 0.18, 0.92)
	panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	panel_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	panel_mat.no_depth_test = true
	panel_mat.render_priority = 1
	_bubble.material_override = panel_mat
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	_status = Label3D.new()
	_status.name = "Status"
	_status.font = _font
	_status.font_size = 42
	_status.pixel_size = 0.0105
	_status.position = Vector3(0, height, 0)
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.no_depth_test = true
	_status.render_priority = 2
	_status.outline_size = 1
	_status.outline_modulate = Color("163638")
	add_child(_status)
	_badge = _ball(self, Vector3(0, height - 0.44, 0), Vector3.ONE * 0.065, Color("d3ba77"))
	_badge.name = "Badge"

func update_order(order: Dictionary) -> void:
	state = str(order.get("state", "waiting"))
	_seat = int(order.get("seat", 0))
	var maximum: float = maxf(float(order.get("max_patience", 38.0)), 0.001)
	patience_ratio = clampf(float(order.get("patience", maximum)) / maximum, 0.0, 1.0)
	set_meta("state", state)
	set_meta("patience_ratio", patience_ratio)
	_live_feedback = Feedback.live(order)
	set_meta("feedback", _live_feedback.duplicate())
	_update_feedback()

func update_kitchen(cooking: int, ready: int, waiting: int) -> void:
	cooking_count = cooking
	ready_count = ready
	state = "cooking" if cooking > 0 else ("ready" if ready > 0 else "idle")
	set_meta("state", state)
	set_meta("waiting_orders", waiting)
	_update_feedback()

func start_reaction(outcome: String, message: String = "") -> void:
	_reaction_message = _wrap_message(message.replace("，", "\n"))
	(_bubble.mesh as QuadMesh).size = Vector2(3.8, 1.05)
	reaction = outcome if outcome in ["satisfied", "okay", "lost"] else "okay"
	reaction_age = 0.0
	walking = false
	set_meta("reaction", reaction)
	_update_feedback()
	_apply_pose()

func advance(delta: float) -> void:
	if delta <= 0:
		return
	elapsed += delta
	if not reaction.is_empty():
		reaction_age += delta
	_apply_pose()
	_update_feedback()

func _feedback(message: String, tint: Color) -> void:
	if message != _last_feedback:
		_status.text = message
		_last_feedback = message
	if tint != _last_tint:
		_status.modulate = tint
		_badge.material_override = _mat(tint, 0.18)
		_last_tint = tint

func _update_feedback() -> void:
	var cream: Color = Color("f2d99d")
	var mint: Color = Color("a9d9c6")
	var coral: Color = Color("f0a48b")
	if not reaction.is_empty():
		if reaction == "lost":
			_feedback(_reaction_message if not _reaction_message.is_empty() else "等太久啦…\n下次再来吧", coral)
		elif reaction_age < 1.3:
			_feedback("好鲜！慢慢品尝" if reaction == "satisfied" else "嗯，味道不错", cream)
		else:
			_feedback(_reaction_message if not _reaction_message.is_empty() else ("谢谢招待！\n下次还来" if reaction == "satisfied" else "谢谢，下次见"), mint)
		return
	if is_chef:
		if state == "cooking":
			_feedback("主厨 · 料理 %d 份\n%s" % [cooking_count, "有 %d 份待上菜" % ready_count if ready_count > 0 else ("切配准备中" if fposmod(elapsed, 4.0) < 2.0 else "留意火候～")], cream)
		elif state == "ready":
			_feedback("出锅啦！\n%d 份料理等上桌" % ready_count, mint)
		else:
			_feedback("潮间厨房\n备料就绪" if int(get_meta("waiting_orders", 0)) == 0 else "收到新订单\n等你安排制作", cream)
		return
	var mood: String = str(_live_feedback.get("mood", "satisfied"))
	var short_text: String = "等得好久…" if mood == "lost" else ("有点饿啦" if mood == "okay" else ("请帮我上菜" if state == "ready" else ("好香，期待" if state == "cooking" else "期待鲜鱼")))
	_feedback("%d · %s" % [_seat + 1, short_text], coral if mood == "lost" else (cream if mood == "okay" else mint))

func _wrap_message(text: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n"):
		var remaining: String = line
		while remaining.length() > 8:
			lines.append(remaining.substr(0, 8))
			remaining = remaining.substr(8)
		lines.append(remaining)
	return "\n".join(lines)
func _apply_pose() -> void:
	if _torso == null:
		return
	var phase: float = elapsed * 1.8 + float(identity) * 1.31
	var breath: float = sin(phase) * 0.012
	var stand: bool = is_chef or not reaction.is_empty()
	_torso.position = Vector3(0, (1.28 if stand else 1.15) + breath, 0)
	_torso.rotation = Vector3.ZERO
	_torso.scale = Vector3(1, 1 + breath * 0.6, 1)
	_left_arm.rotation = Vector3(0.18 if stand else 1.15, 0, -0.12)
	_right_arm.rotation = Vector3(0.18 if stand else 1.15, 0, 0.12)
	_left_elbow.rotation = Vector3(0.18 if stand else 0.70, 0, 0)
	_right_elbow.rotation = Vector3(0.18 if stand else 0.70, 0, 0)
	_left_leg.position.y = 0.88 if stand else 0.79
	_right_leg.position.y = 0.88 if stand else 0.79
	_left_leg.rotation = Vector3(0 if stand else PI / 2, 0, 0)
	_right_leg.rotation = Vector3(0 if stand else PI / 2, 0, 0)
	_left_knee.rotation = Vector3(0 if stand else -PI / 2, 0, 0)
	_right_knee.rotation = Vector3(0 if stand else -PI / 2, 0, 0)
	_head.rotation = Vector3(0, sin(phase * 0.35) * 0.07, sin(phase * 0.55) * 0.035)
	_mouth.rotation.z = 0
	_knife.visible = is_chef and state == "cooking" and fposmod(elapsed, 4.0) < 2.0
	_spoon.visible = is_chef and state == "cooking" and not _knife.visible
	_dish.visible = (is_chef and state == "ready") or (not reaction.is_empty() and reaction != "lost" and reaction_age < 1.3)
	_fork.visible = not reaction.is_empty() and reaction != "lost" and reaction_age < 1.3
	if is_chef:
		if state == "cooking":
			var chop: float = sin(elapsed * 8.8)
			_torso.rotation.x = -0.09
			_torso.rotation.y = sin(elapsed * 0.7) * 0.10
			_left_arm.rotation.x = 1.31
			_left_elbow.rotation.x = 0.72
			_right_arm.rotation.x = 1.33 + chop * 0.22
			_right_elbow.rotation.x = 0.83 - chop * 0.30
			if not _knife.visible:
				_right_arm.rotation.x = 1.35 + cos(elapsed * 4.0) * 0.09
				_right_arm.rotation.y = sin(elapsed * 4.0) * 0.25
				_right_elbow.rotation.x = 0.78 + sin(elapsed * 4.0) * 0.11
			_head.rotation.x = -0.18
		elif state == "ready":
			_left_arm.rotation.x = 1.25
			_left_elbow.rotation.x = 0.94
			_right_arm.rotation = Vector3(2.30, 0, 0.45 + sin(elapsed * 5) * 0.14)
			_right_elbow.rotation.x = 0.45
			_head.rotation.x = sin(elapsed * 2) * 0.08
		else:
			_left_arm.rotation.x = 0.75 + sin(phase * 0.5) * 0.12
			_left_elbow.rotation.x = 0.75
			_right_arm.rotation.x = 0.75 - sin(phase * 0.5) * 0.12
			_right_elbow.rotation.x = 0.75
	elif not reaction.is_empty():
		if reaction == "lost":
			_torso.rotation.x = -0.08
			_head.rotation.x = -0.16
			_head.rotation.y = sin(elapsed * 5.0) * 0.20
			_mouth.rotation.z = PI
		elif reaction_age < 1.3:
			_torso.rotation.x = -0.08
			_left_arm.rotation = Vector3(1.30, 0, -0.18)
			_left_elbow.rotation.x = 0.90
			_right_arm.rotation = Vector3(1.72 + sin(reaction_age * 5) * 0.12, 0, 0.12)
			_right_elbow.rotation.x = 1.00 + sin(reaction_age * 5) * 0.30
			_head.rotation.x = -0.16 + sin(reaction_age * 5) * 0.10
		else:
			_right_arm.rotation = Vector3(2.65, 0, 0.35 + sin(elapsed * 7) * 0.20)
			_right_elbow.rotation.x = 0.15
			_head.rotation.x = sin(elapsed * 3.5) * 0.09
		if walking:
			var step: float = sin(elapsed * 7.5)
			_left_leg.rotation.x = step * 0.34
			_right_leg.rotation.x = -step * 0.34
			_left_knee.rotation.x = minf(0, -step * 0.25)
			_right_knee.rotation.x = minf(0, step * 0.25)
			_torso.position.y += absf(step) * 0.035
			if reaction == "lost":
				_left_arm.rotation.x = -step * 0.28
				_right_arm.rotation.x = step * 0.28
	else:
		var urgent: bool = patience_ratio <= 0.25
		if state == "waiting":
			_torso.rotation.x = -0.035
			_head.rotation.y = sin(elapsed * 0.9) * 0.13
			_right_arm.rotation.x += sin(elapsed * 2.2) * 0.09
		elif state == "cooking":
			_head.rotation.y = sin(elapsed * 0.6) * 0.18
			_left_elbow.rotation.x += sin(elapsed * 1.5) * 0.10
			_right_knee.rotation.x += sin(elapsed * 2.6) * 0.10
		if state == "ready" or urgent:
			var wave: float = fposmod(elapsed + float(identity) * 0.41, 3.1)
			if wave < (2.4 if urgent else 1.8):
				_right_arm.rotation = Vector3(2.55, 0, 0.38 + sin(elapsed * 7.0) * 0.23)
				_right_elbow.rotation.x = 0.32
			_head.rotation.x = sin(elapsed * 2.8) * 0.065
		if patience_ratio <= 0.5 and not urgent:
			_left_knee.rotation.x += sin(elapsed * 4.0) * 0.08
			_head.rotation.y += sin(elapsed * 1.4) * 0.10
		if urgent:
			_mouth.rotation.z = PI
			_left_knee.rotation.x += sin(elapsed * 7.0) * 0.12
			_torso.rotation.y = sin(elapsed * 1.7) * 0.06
	_head.position = _torso.position + _torso.basis * Vector3(0, 0.67, -0.03)
	var blink: float = 0.11 if fposmod(elapsed + float(identity) * 0.39, 4.1) < 0.13 else 1.0
	for eye: Node3D in _eyes:
		eye.scale.y = 0.037 * blink
	for i: int in range(_brows.size()):
		var side: float = -1.0 if i == 0 else 1.0
		_brows[i].rotation.z = side * (-0.22 if _mouth.rotation.z > 1 else 0.08)
