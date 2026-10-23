extends Node3D

const Art = preload("res://scripts/ocean_art.gd")
const Ocean = preload("res://scripts/ocean_config.gd")
const Feedback = preload("res://scripts/customer_feedback.gd")
const Progress = preload("res://scripts/progression.gd")
const Hud = preload("res://scripts/hud.gd")
const Restaurant = preload("res://scripts/restaurant_art.gd")
const Layout = preload("res://scripts/layout_rules.gd")
const FishData = preload("res://scripts/fish_catalog.gd")
const FishBrain = preload("res://scripts/fish_brain.gd")
const FISH_NAMES = ["橘鳍鱼","青背鱼","灯笼鱼","银梭沙丁鱼","星斑河豚","赤鬃狮子鱼","蓝鳍金枪鱼","岩纹海鳗","灰礁鲨"]
const OUTER_FISH_PER_ZONE = 24
const TRANSIT_SCHOOLS = 8
const TRANSIT_FISH_PER_SCHOOL = 9
const SPEAR_RANGE = 20.0
const SPEAR_COOLDOWN = 0.95
const FISH_VALUES = [18,32,55,24,48,70,110,100,180]
const FISH_WEIGHTS = [1,2,3,1,2,2,4,3,6]
var progress = Progress.new()
var state: String = "dock"
var player: CharacterBody3D
var camera: Camera3D
var environment: Environment
var hud: Node2D
var fish: Array = []
var pickups: Array = []
var hazards: Array = []
var effects: Array = []
var cargo: Array = []
var oxygen: float = 100.0
var catch_timer: float = 0.0
var catch_kind: int = 0
var hit_timer: float = 0.0
var entry_active: bool = false
var entry_time: float = 0.0
var entry_splashed: bool = false
const ENTRY_DURATION: float = 3.2
var depth_record: float = 0.0
var yaw: float = 0.0
var pitch: float = -0.12
var clock: float = 0.0
var shot_cooldown: float = 0.0
var hurt_cooldown: float = 0.0
var poison_timer: float = 0.0
var hunt_warning: String = ""
var hunt_warning_timer: float = 0.0
var notice: String = "潮汐湾的第一束晨光，正在等你。"
var notice_timer: float = 8.0
var last_result: Dictionary = {}
var rng = RandomNumberGenerator.new()
var capture_mode: bool = false
var capture_clock: float = 0.0
var capture_name: String = "gameplay"
var smoke_mode: bool = false
var sound_player: AudioStreamPlayer
var muted: bool = false
var restaurant_node: Node3D
var ocean_root: Node3D
var restaurant_tab: String = "renovation"
var menu_plan: Dictionary = {"orange":0,"blue":0,"lantern":0}
var orders: Array = []
var service_arrived: int = 0
var service_spawn_time: float = 0.0
var order_serial: int = 0
var service_summary: Dictionary = {}
var service_feedback: Array[Dictionary] = []
var service_reviews: Dictionary = {"satisfied":0,"okay":0,"lost":0}
var summary_visible: bool = false
var service_close_view: bool = false
var new_game_confirmation: bool = false
var new_game_error: String = ""
var layout_mode: bool = false
var layout_work: RefCounted
var layout_selected: int = -1
var layout_placing: bool = false
var layout_rotation: int = 0
var layout_cursor: Vector3 = Vector3.ZERO
var layout_reason: String = ""
var layout_history: Array = []
var layout_zoom: float = 31.0
var layout_panel_visible: bool = true
var layout_pan: Vector3 = Vector3.ZERO
var layout_panning: bool = false
const LAYOUT_AREA = Rect2(332,96,1100,708)

func _ready() -> void:
	rng.seed = 271828
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--capture") or arg == "--smoke":
			progress.persistence_enabled = false
	progress.load_game()
	service_summary = progress.last_service_result.duplicate(true)
	_setup_input()
	_setup_world()
	_spawn_population()
	restaurant_node = Restaurant.new()
	restaurant_node.position = Vector3(1800,0,0)
	add_child(restaurant_node)
	_rebuild_restaurant()
	restaurant_node.visible = false
	var layer = CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	layer.add_child(hud)
	_setup_sound()
	capture_mode = "--capture" in OS.get_cmdline_user_args() or "--capture-dock" in OS.get_cmdline_user_args() or "--capture-deep" in OS.get_cmdline_user_args()
	smoke_mode = "--smoke" in OS.get_cmdline_user_args()
	if capture_mode and not "--capture-dock" in OS.get_cmdline_user_args():
		start_dive(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.position = Vector3(0, -17, 12)
		pitch = -0.20
	if "--capture-deep" in OS.get_cmdline_user_args():
		player.position = Vector3(0,-40,0)
		capture_name = "deep"
	if "--capture-dock" in OS.get_cmdline_user_args():
		capture_name = "dock"
	if "--capture-furniture-closeup" in args or "--capture-furniture" in args or "--capture-layout" in args or "--capture-layout-custom" in args or "--capture-menu" in args or "--capture-restaurant" in args or "--capture-old-shop" in args or "--capture-service" in args or "--capture-bill" in args:
		capture_mode = true
		progress.coins = 650
		progress.inventory = {"orange":8,"blue":5,"lantern":3,"pearl":4,"chest":1}
		if "--capture-old-shop" in args:
			progress.coins = 0
			for id in progress.inventory:
				progress.inventory[id] = 0
		if not "--capture-old-shop" in args:
			for id in Progress.RENOVATIONS:
				progress.renovation[id] = true
		open_restaurant()
		capture_name = "restaurant_old" if "--capture-old-shop" in args else "restaurant"
		if "--capture-layout" in args or "--capture-layout-custom" in args:
			enter_layout()
			capture_name = "restaurant_layout"
			if "--capture-layout-custom" in args:
				select_furniture(1)
				rotate_layout()
				color_selected_furniture()
				set_layout_style("floor",1)
				set_layout_style("wall",1)
				buy_layout_furniture("lamp")
				place_layout_at(1.5,1.5)
				capture_name = "restaurant_layout_custom"
		if "--capture-furniture" in args or "--capture-furniture-closeup" in args:
			progress.coins = 3000
			enter_layout()
			for item in layout_work.furniture_items():
				item.placed = false
			var ids := ["basic","comfort","premium"]
			for i in range(3):
				var tx: float = [-7.0,-3.5,3.5][i]
				buy_layout_furniture("table",ids[i])
				place_layout_at(tx,-0.5)
				buy_layout_furniture("rug",ids[i])
				place_layout_at(tx,-0.5)
				buy_layout_furniture("shelf",ids[i])
				place_layout_at(-8.5+i*3.5,8.0)
				buy_layout_furniture("lamp",ids[i])
				place_layout_at(2.0+i*2.0,5.0)
				buy_layout_furniture("plant",ids[i])
				place_layout_at(8.0,-1.5+i*3.0)
			layout_selected = -1
			layout_reason = "十五款家具 / 三档质感 · 自由选择你的小店风格"
			_rebuild_restaurant()
			hud.rebuild()
			capture_name = "furniture_collection"
			if "--capture-furniture-closeup" in args:
				layout_panel_visible = false
				layout_zoom = 20
				layout_pan = Vector3(-1,0,-2.5)
				for item in layout_work.furniture_items():
					if item.kind == "rug":
						item.z = 3.5
				_rebuild_restaurant()
				hud.rebuild()
				capture_name = "furniture_detail"
		if "--capture-menu" in args:
			restaurant_tab = "menu"
			menu_plan = {"orange":2,"blue":2,"lantern":1}
			capture_name = "restaurant_menu"
			hud.rebuild()
		if "--capture-service" in args or "--capture-bill" in args:
			menu_plan = {"orange":1,"blue":2,"lantern":2}
			start_service()
			for i in range(4):
				_spawn_customer()
			if "--capture-bill" in args:
				for order in orders.duplicate():
					order.state = "ready"
					serve_order(order.id)
				finish_service()
				capture_name = "restaurant_bill"
			else:
				cook_order(orders[0].id)
				cook_order(orders[1].id)
				capture_name = "restaurant_service"
	if "--capture-return" in args:
		capture_mode = true
		start_dive(false)
		cargo = [{"id":"orange"},{"id":"blue"},{"id":"lantern"},{"id":"pearl"},{"id":"chest"}]
		finish_dive()
		capture_name = "return_inventory"
	if "--capture-new-game" in args:
		capture_mode = true
		capture_name = "new_game_confirmation"
		request_new_game()
	if "--capture-living-service" in args or "--capture-feedback-bill" in args:
		capture_mode = true
		capture_name = "living_service"
		service_close_view = true
		progress.coins = 650
		progress.inventory = {"orange":8,"blue":5,"lantern":3,"pearl":4,"chest":1}
		for id in Progress.RENOVATIONS:
			progress.renovation[id] = true
		open_restaurant()
		menu_plan = {"orange":4,"blue":2,"lantern":2}
		start_service()
		for i in range(4):
			_spawn_customer()
		orders[0].state = "ready"
		serve_order(orders[0].id)
		_spawn_customer()
		cook_order(orders[0].id)
		orders[1].patience = 7
		orders[2].state = "ready"
		orders[2].patience = 18
		restaurant_node.set_customers(orders)
		hud.rebuild()
		if "--capture-feedback-bill" in args:
			orders[2].patience = 10
			serve_order(orders[2].id)
			finish_service()
			capture_name = "feedback_bill"
	if "--capture-outer-ocean" in args:
		capture_mode = true
		capture_name = "outer_ocean"
		start_dive()
		player.position = Ocean.ZONES[0].center + Vector3(0,8,26)
		pitch = -0.20
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not progress.recovery_notice.is_empty():
		tell(progress.recovery_notice,12)
	if smoke_mode:
		call_deferred("_run_smoke")

func _setup_input() -> void:
	var bindings: Dictionary = {"swim_left": [KEY_A, KEY_LEFT], "swim_right": [KEY_D, KEY_RIGHT], "swim_forward": [KEY_W, KEY_UP], "swim_back": [KEY_S, KEY_DOWN], "descend": [KEY_Q], "ascend": [KEY_E], "boost": [KEY_SHIFT], "stealth": [KEY_CTRL]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in bindings[action]:
			var event = InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action, event)

func _setup_world() -> void:
	var world_env = WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("126879")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b0c9cb")
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("136675")
	environment.fog_light_energy = 0.85
	environment.fog_density = 0.0065
	world_env.environment = environment
	add_child(world_env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -28, 0)
	sun.light_color = Color("fff1d4")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	add_child(sun)
	ocean_root = Node3D.new()
	add_child(ocean_root)
	Art.build_world(ocean_root)
	var boat: Node3D = Art.create_boat()
	boat.position = Vector3(0, 0.3, 14)
	ocean_root.add_child(boat)
	player = CharacterBody3D.new()
	player.add_child(Art.create_diver())
	var collider = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.65
	collider.shape = shape
	player.add_child(collider)
	player.position = Vector3(0, -6, 14)
	add_child(player)
	camera = Camera3D.new()
	camera.fov = 66
	camera.far = 1100
	camera.current = true
	add_child(camera)
	var lamp = OmniLight3D.new()
	lamp.light_color = Color("a2ffe4")
	lamp.light_energy = 0.35
	lamp.omni_range = 12
	player.add_child(lamp)

func _spawn_population() -> void:
	for item in fish:
		item.node.queue_free()
	for item in pickups:
		item.node.queue_free()
	for item in hazards:
		item.node.queue_free()
	fish.clear()
	pickups.clear()
	hazards.clear()
	for i in range(33):
		var kind: int = i % 3
		var p = Vector3(rng.randf_range(-34, 34), -rng.randf_range(5 + kind * 12, 17 + kind * 15), rng.randf_range(-37, 27))
		if i < 5:
			kind = 0
			p = Vector3((i - 2) * 3.0, -7 - i * 0.6, 1 - i * 2.0)
		_add_fish(kind,p)
	var places: Array = [Vector3(3,-8,8),Vector3(-8,-16,0),Vector3(13,-22,-8),Vector3(-14,-29,-14),Vector3(7,-38,-22),Vector3(-5,-46,-29),Vector3(24,-48,7)]
	for p in places:
		_add_pickup(p, "pearl")
	_add_pickup(Vector3(1,-49,-25), "chest")
	_add_pickup(Vector3(-22,-34,-6), "chest")
	_add_pickup(Vector3(-5,-18,3), "oxygen")
	_add_pickup(Vector3(15,-37,-15), "oxygen")
	for i in range(7):
		var node = _jellyfish()
		var pos = Vector3(rng.randf_range(-25,25),rng.randf_range(-45,-22),rng.randf_range(-28,14))
		pos.y = maxf(pos.y,Ocean.seabed_height(pos.x,pos.z)+4.0)
		node.position = pos
		ocean_root.add_child(node)
		hazards.append({"node":node,"home":pos,"phase":float(i)})

	for zone_index in range(Ocean.ZONES.size()):
		for i in range(OUTER_FISH_PER_ZONE):
			var kind: int = (i+zone_index*2) % FishData.SPECIES.size()
			_add_fish(kind,Ocean.fish_home(zone_index,i))
	# Scattered travelling schools connect the bay to distant habitats.
	for school in range(TRANSIT_SCHOOLS):
		var angle: float = float(school)*2.399
		var radius: float = 75.0+float(school)*18.0
		var center := Vector3(cos(angle)*radius,-20.0-float(school%3)*10.0,sin(angle)*radius)
		for i in range(TRANSIT_FISH_PER_SCHOOL):
			var kind: int = [3,1,4,6,3,5,1,6][school]
			_add_fish(kind,center+Vector3(sin(float(i)*2.399)*10,float(i%3)*2,cos(float(i)*2.399)*9))
	for point in Ocean.pickup_points():
		_add_pickup(point.position,point.kind)
	for zone in Ocean.ZONES:
		var node: Node3D = _jellyfish()
		var pos: Vector3 = Ocean.hazard_home(Ocean.ZONES.find(zone))
		pos.y = maxf(pos.y,Ocean.seabed_height(pos.x,pos.z)+4.0)
		node.position = pos
		ocean_root.add_child(node)
		hazards.append({"node":node,"home":pos,"phase":rng.randf_range(0,TAU)})
func fish_population_count() -> int:
	return 33+OUTER_FISH_PER_ZONE*Ocean.ZONES.size()+TRANSIT_SCHOOLS*TRANSIT_FISH_PER_SCHOOL

func _add_fish(kind: int, point: Vector3) -> Dictionary:
	var p := point
	p.y = clampf(p.y,maxf(Ocean.Y_MIN+3,Ocean.seabed_height(p.x,p.z)+5),-6)
	var node: Node3D = Art.create_fish(kind)
	node.position = p
	ocean_root.add_child(node)
	var item: Dictionary = {"node":node,"kind":kind,"home":p,"phase":rng.randf_range(0,TAU),"hp":int(FishData.SPECIES[kind].hp),"alive":true}
	FishBrain.prepare(item)
	fish.append(item)
	return item
func _add_pickup(pos: Vector3, kind: String) -> void:
	pos.y = maxf(pos.y,Ocean.seabed_height(pos.x,pos.z)+1.0)
	var node: Node3D = Art.create_pickup(kind)
	node.position = pos
	ocean_root.add_child(node)
	pickups.append({"node":node,"kind":kind,"home":pos,"active":true})

func _jellyfish() -> Node3D:
	var root = Node3D.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color("e295d7")
	mat.emission_enabled = true
	mat.emission = Color("b958b2")
	mat.emission_energy_multiplier = 0.6
	var cap = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	cap.mesh = sphere
	cap.material_override = mat
	root.add_child(cap)
	for i in range(5):
		var tentacle = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.045
		cylinder.bottom_radius = 0.02
		cylinder.height = 1.5
		cylinder.radial_segments = 5
		tentacle.mesh = cylinder
		tentacle.material_override = mat
		tentacle.position = Vector3(cos(i*TAU/5)*0.45,-1,sin(i*TAU/5)*0.45)
		root.add_child(tentacle)
	return root

func request_new_game() -> void:
	if state not in ["dock","paused"] or new_game_confirmation:
		return
	new_game_confirmation = true
	new_game_error = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.rebuild()

func cancel_new_game() -> void:
	if not new_game_confirmation:
		return
	new_game_confirmation = false
	hud.rebuild()

func confirm_new_game() -> void:
	if not new_game_confirmation or state not in ["dock","paused"]:
		return
	if not progress.reset_game():
		new_game_error = "无法写入存档，原进度保留。请检查存档目录。"
		hud.rebuild()
		return
	new_game_confirmation = false
	state = "dock"
	entry_active = false
	entry_time = 0.0
	entry_splashed = false
	catch_timer = 0.0
	hit_timer = 0.0
	cargo.clear()
	orders.clear()
	last_result.clear()
	service_summary.clear()
	service_feedback.clear()
	service_reviews = {"satisfied":0,"okay":0,"lost":0}
	restaurant_node.clear_reactions()
	summary_visible = false
	menu_plan = {"orange":0,"blue":0,"lantern":0}
	restaurant_tab = "renovation"
	service_arrived = 0
	service_spawn_time = 0
	order_serial = 0
	service_close_view = false
	layout_mode = false
	layout_work = null
	layout_selected = -1
	layout_placing = false
	layout_rotation = 0
	layout_cursor = Vector3.ZERO
	layout_reason = ""
	layout_history.clear()
	layout_zoom = 31
	layout_panel_visible = true
	layout_pan = Vector3.ZERO
	layout_panning = false
	for effect in effects:
		if is_instance_valid(effect.node):
			effect.node.queue_free()
	effects.clear()
	restaurant_node.set_customers([])
	_rebuild_restaurant()
	restaurant_node.visible = false
	ocean_root.visible = true
	player.visible = false
	player.velocity = Vector3.ZERO
	player.position = Vector3(0,-6,14)
	oxygen = progress.oxygen_max()
	depth_record = 0
	yaw = 0
	pitch = -0.12
	clock = 0
	shot_cooldown = 0
	hurt_cooldown = 0
	poison_timer = 0
	hunt_warning_timer = 0
	hunt_warning = ""
	_spawn_population()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 66
	environment.fog_enabled = true
	environment.fog_light_color = Color("136675")
	environment.background_color = Color("126879")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tell("新的旅程开始了。从第一天出海，重新打造你的海岸小店。",9)
	hud.rebuild()

func start_dive(animate_entry: bool = true) -> void:
	if new_game_confirmation or state != "dock":
		return
	restaurant_node.visible = false
	ocean_root.visible = true
	environment.fog_enabled = true
	camera.fov = 66
	_spawn_population()
	cargo.clear()
	oxygen = progress.oxygen_max()
	depth_record = 0
	catch_timer = 0.0
	hit_timer = 0.0
	entry_active = animate_entry
	entry_time = 0.0
	entry_splashed = false
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.position = Vector3(0,2.4,17.5) if animate_entry else Vector3(0,-6,14)
	player.visible = true
	yaw = 0
	pitch = -0.12
	shot_cooldown = 0
	hurt_cooldown = 0
	poison_timer = 0
	hunt_warning_timer = 0
	hunt_warning = ""
	state = "dive"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	tell("WASD 游泳 · Q 下潜 / E 上浮 · 鼠标瞄准 · 左键发射鱼叉", 9)
	hud.rebuild()
	if entry_active:
		tell("跃入潮汐湾 · 让海水包围你", 3.2)
		_update_entry(0.0)
	_play_tone(480, 0.18)

func finish_dive(rescued: bool = false) -> void:
	if state != "dive":
		return
	entry_active = false
	camera.fov = 66
	last_result = progress.complete_dive(cargo, rescued, depth_record)
	environment.fog_light_color = Color("136675")
	environment.background_color = Color("126879")
	cargo.clear()
	state = "dock"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if rescued:
		tell("救援艇已接你返航。货物按 35% 价值结算，升级潜水气瓶后再试一次。", 14)
	else:
		tell("收获 %d 件，已存入仓库。去餐厅售卖筹资，或留下鱼做菜。" % last_result.count, 12)
	hud.rebuild()
	_play_tone(660,0.28)

func upgrade(kind: String) -> void:
	if progress.buy_upgrade(kind):
		tell("装备升级完成，下一次可以探索得更远。", 5)
		_play_tone(760,0.12)
	else:
		tell("金币不足，或这件装备已经满级。", 4)
	hud.rebuild()

func toggle_pause() -> void:
	if new_game_confirmation:
		cancel_new_game()
		return
	if state == "service":
		state = "service_paused"
	elif state == "service_paused":
		state = "service"
	elif state == "dive":
		state = "paused"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif state == "paused":
		state = "dive"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state in ["dive","service"] and not capture_mode and not smoke_mode:
		toggle_pause()

func _input(event: InputEvent) -> void:
	if not layout_mode or not layout_panning:
		return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed):
		_layout_input(event)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if new_game_confirmation:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			cancel_new_game()
		return
	if layout_mode:
		_layout_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			toggle_pause()
		if event.physical_keycode == KEY_M:
			muted = not muted
			tell("音效已关闭" if muted else "音效已开启", 3)
		if state == "dive":
			if event.physical_keycode == KEY_F:
				interact()
			if event.physical_keycode == KEY_SPACE:
				shoot()
	if state != "dive" or entry_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0026
		pitch = clampf(pitch - event.relative.y * 0.0022, -1.25, 1.10)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		shoot()

func _physics_process(delta: float) -> void:
	if state not in ["paused","service_paused"]:
		clock += delta
		notice_timer = maxf(0, notice_timer-delta)
		_animate_ocean(delta)
	if state == "dive":
		if entry_active:
			_update_entry(delta)
		else:
			_update_dive(delta)
	elif state in ["restaurant","service","service_paused"]:
		if layout_mode:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = layout_zoom
			update_layout_camera()
			_update_layout_preview()
		else:
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.position = restaurant_node.position + (Vector3(17,13,21) if service_close_view and state in ["service","service_paused"] else Vector3(22,18,27))
			camera.look_at(restaurant_node.position + (Vector3(0,1.1,0.5) if service_close_view and state in ["service","service_paused"] else Vector3(0,1,2)))
		if state != "service_paused":
			restaurant_node.animate(delta)
		if state == "service":
			_update_service(delta)
	elif state == "dock":
		var p = Vector3(16 + sin(clock*0.045)*3, -13, 29)
		camera.position = p
		camera.look_at(Vector3(0,-23,-10))
		player.visible = false
	if state not in ["paused","service_paused"]:
		catch_timer = maxf(0, catch_timer - delta)
		hit_timer = maxf(0, hit_timer - delta)
		_update_effects(delta)
	if is_instance_valid(hud):
		hud.queue_redraw()
	if capture_mode:
		capture_clock += delta
		if capture_clock > (1.0 if capture_name == "living_service" else 3.0):
			capture_mode = false
			call_deferred("_capture")

func _update_entry(delta: float) -> void:
	entry_time = minf(entry_time + delta, ENTRY_DURATION)
	var t: float = entry_time
	yaw = PI
	pitch = -0.12
	if t < 0.45:
		player.position = Vector3(0, 2.4 - sin(t / 0.45 * PI) * 0.25, 17.5)
		player.rotation = Vector3(PI / 2, PI, 0)
	elif t < 1.55:
		var u: float = (t - 0.45) / 1.1
		player.position = Vector3(0, 2.4 + 2.0 * u - 4.8 * u * u, 17.5 + 5.0 * u)
		player.rotation = Vector3(lerpf(PI / 2, -0.65, smoothstep(0.0, 1.0, u)), PI, 0)
	else:
		var u: float = smoothstep(0.0, 1.0, (t - 1.55) / 1.65)
		player.position = Vector3(0, lerpf(-0.4, -6.0, u), lerpf(22.5, 25.0, u))
		player.rotation = Vector3(lerpf(-0.65, 0, u), PI, 0)
	if not entry_splashed and player.position.y <= 0.65:
		entry_splashed = true
		_spawn_entry_water()
		_play_splash()
	var follow: float = smoothstep(1.4, ENTRY_DURATION, t)
	var forward := Vector3(0, sin(pitch), cos(pitch))
	var swim_camera: Vector3 = player.position - forward * 7.5 + Vector3.UP * 1.7
	camera.position = (player.position + Vector3(7, 3.2, 7)).lerp(swim_camera, follow)
	camera.look_at((player.position + Vector3.UP * 0.3).lerp(player.position + forward * 3 + Vector3.UP * 0.6, follow))
	camera.fov = 66 + sin(follow * PI) * 6
	var submerged: float = 1.0 - smoothstep(-1.2, 0.7, camera.position.y)
	environment.background_color = Color("89c6cd").lerp(Color("14596b"), submerged)
	environment.fog_light_color = environment.background_color
	environment.fog_density = lerpf(0.004, 0.024, submerged)
	if t >= ENTRY_DURATION:
		entry_active = false
		camera.fov = 66
		environment.fog_density = 0.024
		tell("WASD 游泳 · Q 下潜 / E 上浮 · 左键发射鱼叉", 7)

func _play_splash() -> void:
	if muted:
		return
	# Layer the initial impact, broad spray and irregular resonant bubbles.
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	var count: int = 26460
	data.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 31415
	var low: float = 0.0
	var mid: float = 0.0
	for i in range(count):
		var t: float = float(i) / 22050.0
		var white: float = noise.randf_range(-1, 1)
		low = lerpf(low, white, 0.045)
		mid = lerpf(mid, white, 0.42)
		var attack: float = minf(t / 0.008, 1.0)
		var impact: float = low * 3.8 * exp(-t * 24)
		var spray: float = (mid - low) * 1.3 * exp(-t * 5.5)
		var wash: float = low * 1.7 * (1.0 - exp(-t * 22)) * exp(-t * 3.8)
		var bubbles: float = 0.0
		for j in range(9):
			var age: float = t - (0.12 + j * 0.083 + sin(j * 17.0) * 0.025)
			if age > 0:
				var frequency: float = 340 + fposmod(j * 173.0, 630)
				bubbles += sin(TAU * (frequency * age - 230 * age * age)) * exp(-age * 38) * minf(age * 900, 1.0) * 0.17
		var value: float = (impact + spray + wash) * attack + bubbles
		data.encode_s16(i * 2, int(clampf(value, -0.95, 0.95) * 29000))
	wav.data = data
	sound_player.stream = wav
	sound_player.play()

func _capture_feedback(kind: int, location: Vector3) -> void:
	catch_timer = 2.4
	catch_kind = kind
	hit_timer = 0.3
	# A visible copy travels from the catch into the diver's bag.
	var caught: Node3D = Art.create_fish(kind)
	caught.position = location
	ocean_root.add_child(caught)
	effects.append({"node":caught,"life":0.6,"duration":0.6,"origin":location,"collect":true})
	for i in range(14):
		var bubble := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.045 + float(i % 3) * 0.025
		sphere.height = sphere.radius * 2
		bubble.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("f5c779") if i % 3 == 0 else Color("a9ead2")
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bubble.material_override = mat
		bubble.position = location
		ocean_root.add_child(bubble)
		var angle: float = i * 2.399
		effects.append({"node":bubble,"life":0.65,"velocity":Vector3(sin(angle)*1.8,0.8+float(i%4)*0.4,cos(angle)*1.8),"gravity":0.0})
	if muted:
		return
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(11025 * 2)
	for i in range(11025):
		var t: float = float(i) / 22050.0
		var value: float = 0.0
		for j in range(3):
			var age: float = t - j * 0.075
			if age >= 0:
				var frequency: float = [660.0, 880.0, 1100.0][j]
				value += sin(TAU * frequency * age) * exp(-age * 16) * minf(age * 300, 1.0) * 0.35
		data.encode_s16(i * 2, int(value * 23000))
	wav.data = data
	sound_player.stream = wav
	sound_player.play()

func _spawn_entry_water() -> void:
	for i in range(42):
		var droplet := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.06 + float(i % 4) * 0.025
		sphere.height = sphere.radius * 2
		droplet.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("b9f1ed")
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		droplet.material_override = mat
		var angle: float = float(i) * 2.399
		var bubble: bool = i >= 24
		droplet.position = Vector3(sin(angle) * 0.4, -0.8 if bubble else 0.65, player.position.z + cos(angle) * 0.4)
		ocean_root.add_child(droplet)
		var velocity := Vector3(sin(angle) * 2.6, 3.2 + float(i % 5) * 0.5, cos(angle) * 2.6)
		if bubble:
			velocity = Vector3(sin(angle) * 0.6, 1.1, cos(angle) * 0.6)
		effects.append({"node":droplet, "life":2.5 if bubble else 1.0, "velocity":velocity, "gravity":0.0 if bubble else 9.8})

func _update_dive(delta: float) -> void:
	shot_cooldown = maxf(0,shot_cooldown-delta)
	hurt_cooldown = maxf(0,hurt_cooldown-delta)
	_update_hunting_status(delta)
	var input_dir = Input.get_vector("swim_left","swim_right","swim_forward","swim_back")
	var horizontal = Vector3(input_dir.x,0,input_dir.y).rotated(Vector3.UP,yaw)
	var vertical: float = Input.get_action_strength("ascend") - Input.get_action_strength("descend")
	var move = Vector3(horizontal.x,vertical,horizontal.z).limit_length()
	var boosting: bool = Input.is_action_pressed("boost") and move.length() > 0.1
	var speed: float = 2.8 if Input.is_action_pressed("stealth") else (11.5 if boosting else 6.2)
	player.velocity = move * speed
	player.move_and_slide()
	player.position.x = clampf(player.position.x,Ocean.X_MIN,Ocean.X_MAX)
	player.position.z = clampf(player.position.z,Ocean.Z_MIN,Ocean.Z_MAX)
	player.position.y = clampf(player.position.y,maxf(Ocean.Y_MIN,Ocean.seabed_height(player.position.x,player.position.z)+0.8),Ocean.Y_MAX)
	player.rotation.y = lerp_angle(player.rotation.y,yaw,delta*8)
	player.rotation.x = lerpf(player.rotation.x,vertical*0.22,delta*5)
	var diver_art = player.get_child(0)
	for leg_name in ["LegLeft", "LegRight"]:
		var leg = diver_art.get_node_or_null(leg_name)
		if leg:
			leg.rotation.x = sin(clock * (10.0 if boosting else 5.5) + (0.0 if leg_name == "LegLeft" else PI)) * (0.3 if move.length() > 0.1 else 0.10)
	depth_record = maxf(depth_record,-player.position.y)
	var use_rate: float = (0.72 + maxf(0,-player.position.y-20)*0.009) * (1.8 if boosting else 1.0)
	oxygen = maxf(0, oxygen-use_rate*delta)
	var forward = Vector3(-sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))
	var desired_camera: Vector3 = player.position - forward*7.5 + Vector3.UP*1.7
	var camera_ray = PhysicsRayQueryParameters3D.create(player.position + Vector3.UP*0.8, desired_camera, 1, [player.get_rid()])
	var obstruction: Dictionary = get_world_3d().direct_space_state.intersect_ray(camera_ray)
	camera.position = desired_camera if obstruction.is_empty() else obstruction.position + obstruction.normal*0.4
	camera.look_at(player.position + forward*3 + Vector3.UP*0.6)
	var deep: float = clampf((-player.position.y-12)/110,0,1)
	environment.fog_light_color = Color("14596b").lerp(Color("061c30"),deep)
	environment.background_color = environment.fog_light_color
	for hazard in hazards:
		if player.position.distance_to(hazard.node.position) < 2.0 and hurt_cooldown <= 0:
			oxygen = maxf(0,oxygen-12)
			hurt_cooldown = 2.5
			tell("小心水母！气瓶量减少 12。", 3)
			_play_tone(120,0.18)
	if oxygen <= 0:
		finish_dive(true)

func _animate_ocean(_delta: float) -> void:
	for item in fish:
		if item.alive:
			_update_fish(item,_delta)
	for item in pickups:
		if item.active:
			item.node.position.y = item.home.y + sin(clock*1.4+item.home.x)*0.25
			item.node.rotation.y += _delta*0.3
	for item in hazards:
		item.node.position = item.home + Vector3(sin(clock*0.3+item.phase)*1.5,sin(clock*0.7+item.phase)*1.0,0)

func _update_fish(item: Dictionary, delta: float) -> void:
	FishBrain.advance(self,item,delta)

func take_hunt_damage(amount: float, poison: bool, source: String) -> void:
	if state != "dive" or entry_active or hurt_cooldown > 0:
		return
	oxygen = maxf(0,oxygen-amount)
	hurt_cooldown = 2.5
	if poison:
		poison_timer = 6.0
	hunt_warning = "%s · 气瓶量 -%d%s" % [source,int(amount),"，中毒6秒，保持距离" if poison else "，侧游避开下一次冲刺"]
	hunt_warning_timer = 3.0
	_play_tone(120,0.12)

func _update_hunting_status(delta: float) -> void:
	hunt_warning_timer = maxf(0,hunt_warning_timer-delta)
	if poison_timer > 0:
		var elapsed: float = minf(delta,poison_timer)
		oxygen = maxf(0,oxygen-elapsed*1.5)
		poison_timer = maxf(0,poison_timer-delta)
func weight() -> int:
	var value: int = 0
	for item in cargo:
		value += int(item.weight)
	return value

func cargo_value() -> int:
	var value: int = 0
	for item in cargo:
		value += int(item.value)
	return value

func target_fish() -> Dictionary:
	var center = get_viewport().get_visible_rect().size * 0.5
	var origin = camera.project_ray_origin(center)
	var direction = camera.project_ray_normal(center)
	var best: Dictionary = {}
	var best_dist: float = SPEAR_RANGE+15.0
	for item in fish:
		if not item.alive:
			continue
		var offset: Vector3 = item.node.position-origin
		var along: float = offset.dot(direction)
		if player.position.distance_to(item.node.position) > SPEAR_RANGE:
			continue
		var radius: float = float(FishData.SPECIES[item.kind].radius)
		if along > 0 and along < best_dist and (offset-direction*along).length() < radius:
			var sight_ray = PhysicsRayQueryParameters3D.create(origin, item.node.position, 1, [player.get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(sight_ray).is_empty():
				continue
			var spear_ray := PhysicsRayQueryParameters3D.create(player.position,item.node.position,1,[player.get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(spear_ray).is_empty():
				continue
			best = item
			best_dist = along
	return best

func shoot() -> void:
	if state != "dive" or entry_active or shot_cooldown > 0:
		return
	shot_cooldown = SPEAR_COOLDOWN
	_play_tone(270,0.08)
	var center := get_viewport().get_visible_rect().size*0.5
	var direction := camera.project_ray_normal(center)
	var end := player.position+direction*SPEAR_RANGE
	var target: Dictionary = target_fish()
	if not target.is_empty():
		end = target.node.position
		_hit_fish(target)
	else:
		for item in fish:
			if item.alive and player.position.distance_to(item.node.position) < 12:
				FishBrain.alarm(self,item)
				break
		var query := PhysicsRayQueryParameters3D.create(player.position,end,1,[player.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			end = hit.position
	_line_effect(player.position+Vector3.UP*0.4,end)

func _hit_fish(target: Dictionary) -> void:
	if state != "dive" or entry_active or not target.alive:
		return
	hit_timer = 0.18
	FishBrain.prepare(target)
	var data: Dictionary = FishData.SPECIES[target.kind]
	var damage: int = progress.spear_damage()
	var armored: bool = bool(target.armor)
	if armored:
		damage = mini(1,damage)
		tell("河豚膨胀防御中！等它泄气后再攻击。",3)
	target.hp -= damage
	FishBrain.alarm(self,target)
	if target.hp <= 0:
		if weight()+int(data.weight) <= progress.capacity():
			cargo.append({"id":data.id,"name":data.name,"value":data.value,"weight":data.weight,"kind":"fish"})
			target.alive = false
			target.node.visible = false
			tell("捕获 %s · 已装入背包 · 价值 %d G" % [data.name,data.value],3)
			_capture_feedback(target.kind, target.node.position)
		else:
			target.hp = 1
			tell("背包空间不足，猎物仍在逃跑。上浮返航清空背包。",4)
	elif not armored:
		tell("命中 %s！剩余耐久 %d / %d" % [data.name,target.hp,data.hp],2)

func _line_effect(start: Vector3, end: Vector3) -> void:
	var mesh = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.026
	cylinder.bottom_radius = 0.026
	cylinder.height = start.distance_to(end)
	cylinder.radial_segments = 5
	mesh.mesh = cylinder
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color("d9ffdb")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	mesh.position = (start+end)*0.5
	mesh.quaternion = Quaternion(Vector3.UP,(end-start).normalized())
	add_child(mesh)
	effects.append({"node":mesh,"life":0.16})

func _update_effects(delta: float) -> void:
	for i in range(effects.size()-1,-1,-1):
		if effects[i].has("collect"):
			var u: float = clampf(1.0 - (effects[i].life - delta) / effects[i].duration, 0, 1)
			effects[i].node.position = effects[i].origin.lerp(player.position, u * u)
			effects[i].node.scale = Vector3.ONE * maxf(0.02, 1.0 - u * 0.95)
			effects[i].node.rotation.y += delta * 8
		if effects[i].has("velocity"):
			effects[i].velocity.y -= effects[i].gravity * delta
			effects[i].node.position += effects[i].velocity * delta
		effects[i].life -= delta
		if effects[i].life <= 0:
			effects[i].node.queue_free()
			effects.remove_at(i)

func nearest_pickup() -> Dictionary:
	var best: Dictionary = {}
	var distance: float = 3.4
	for item in pickups:
		if item.active:
			var d: float = player.position.distance_to(item.node.position)
			if d < distance:
				best = item
				distance = d
	return best

func interact() -> void:
	if entry_active:
		return
	if state != "dive":
		return
	if player.position.y >= -3.5:
		finish_dive(false)
		return
	var item: Dictionary = nearest_pickup()
	if item.is_empty():
		tell("靠近发光物品按 F 采集；上浮至 3 米内按 F 返航。", 4)
		return
	var kind: String = item.kind
	if kind == "oxygen":
		oxygen = minf(progress.oxygen_max(),oxygen+35)
		tell("应急气瓶 · 气瓶量 +35", 3)
	else:
		var w: int = 3 if kind == "chest" else 1
		if weight()+w > progress.capacity():
			tell("背包空间不足，先返航将收获入库吧。", 3)
			return
		var value: int = 90 if kind == "chest" else 28
		var label: String = "沉船宝藏" if kind == "chest" else "月光珍珠"
		cargo.append({"id":kind,"name":label,"value":value,"weight":w,"kind":kind})
		tell("发现 %s  ·  +%d G" % [label,value], 3)
	item.active = false
	item.node.visible = false
	_play_tone(960,0.15)

func ocean_edge_distance() -> float:
	return minf(minf(player.position.x-Ocean.X_MIN,Ocean.X_MAX-player.position.x),minf(player.position.z-Ocean.Z_MIN,Ocean.Z_MAX-player.position.z))

func ocean_zone_name() -> String:
	var nearest: String = "蓝海航道"
	if Vector2(player.position.x,player.position.z).length() < 42:
		return "潮汐湾 · 近岸"
	var best: float = 45.0
	for zone in Ocean.ZONES:
		var distance: float = Vector2(player.position.x,player.position.z).distance_to(Vector2(zone.center.x,zone.center.z))
		if distance < best:
			best = distance
			nearest = zone.name
	return nearest
func context_hint() -> String:
	if entry_active:
		return "正在入水 · 感受海水的浮力"
	if player.position.y >= -3.5:
		return "F  呼叫接驳船 · 返航入库"
	var item: Dictionary = nearest_pickup()
	if not item.is_empty():
		var names: Dictionary = {"pearl":"采集月光珍珠","chest":"打开沉船宝藏","oxygen":"补充气瓶量"}
		return "F  " + names[item.kind]
	var target: Dictionary = target_fish()
	if not target.is_empty():
		var data: Dictionary = FishData.SPECIES[target.kind]
		return "%s · 耐久 %d/%d · %d kg | %s" % [data.name,target.hp,data.hp,data.weight,data.hint]
	return ""

func tell(message: String, seconds: float) -> void:
	notice = message
	notice_timer = seconds

func _setup_sound() -> void:
	sound_player = AudioStreamPlayer.new()
	sound_player.volume_db = -18
	add_child(sound_player)

func _play_tone(freq: float, duration: float) -> void:
	if muted or not is_instance_valid(sound_player):
		return
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var samples = PackedByteArray()
	var count: int = int(22050*duration)
	samples.resize(count*2)
	for i in range(count):
		var t: float = float(i)/22050
		var envelope: float = sin(PI*float(i)/count)*exp(-t*8)
		var value: int = int(sin(t*TAU*freq)*envelope*14000)
		samples.encode_s16(i*2,value)
	stream.data = samples
	sound_player.stream = stream
	sound_player.play()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var err: int = get_viewport().get_texture().get_image().save_png("res://artifacts/%s.png" % capture_name)
	print("CAPTURE ",err)
	get_tree().quit()

func _run_smoke() -> void:
	start_dive(false)
	assert(state == "dive")
	assert(fish.size() == fish_population_count())
	assert(pickups.size() == 11+Ocean.pickup_points().size())
	player.position = pickups[0].node.position
	interact()
	assert(cargo.size() == 1)
	assert(weight() == 1)
	assert(cargo_value() == 28)
	oxygen = 1
	player.position = pickups[9].node.position
	interact()
	assert(oxygen == 36)
	var target: Dictionary = fish[0]
	player.position = Vector3(0,-8,14)
	camera.position = Vector3(0,-6,21)
	target.node.position = Vector3(0,-7,2)
	camera.look_at(target.node.position)
	assert(not target_fish().is_empty())
	shoot()
	assert(cargo.size() == 2)
	toggle_pause()
	assert(state == "paused")
	toggle_pause()
	assert(state == "dive")
	print("SMOKE PASS: world, collection, oxygen, aim, capture, pause")
	get_tree().quit()






# Shore management and restaurant service.
func open_restaurant() -> void:
	if state not in ["dock","restaurant"]:
		return
	state = "restaurant"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.visible = false
	restaurant_node.visible = true
	ocean_root.visible = false
	_rebuild_restaurant()
	environment.fog_enabled = false
	environment.background_color = Color("7dafb8")
	camera.fov = 50
	_clamp_menu()
	hud.rebuild()

func return_to_dock() -> void:
	if layout_mode:
		cancel_layout()
	if state != "restaurant":
		return
	state = "dock"
	restaurant_node.visible = false
	ocean_root.visible = true
	environment.fog_enabled = true
	environment.background_color = Color("126879")
	camera.fov = 66
	hud.rebuild()

func _clamp_menu() -> void:
	for id in Progress.RECIPES:
		menu_plan[id] = clampi(int(menu_plan.get(id,0)),0,int(progress.inventory.get(id,0)))

func sell_goods(id: String, amount: int) -> void:
	if layout_mode or state != "restaurant":
		return
	var earned: int = progress.sell(id,amount)
	if earned > 0:
		tell("出售 %s · 收入 %d G" % [Progress.GOODS[id].name,earned],4)
		_play_tone(650,0.1)
	_clamp_menu()
	hud.rebuild()

func sell_valuables() -> void:
	if layout_mode or state != "restaurant":
		return
	var earned: int = progress.sell_valuables()
	tell("珍珠与宝藏出售收入 %d G，鱼类已保留。" % earned,4)
	hud.rebuild()

func renovate_shop(id: String) -> void:
	if layout_mode or state != "restaurant":
		return
	if progress.renovate(id):
		_rebuild_restaurant()
		tell("%s 已完成，店面焕然一新！" % Progress.RENOVATIONS[id].name,4)
		_play_tone(800,0.2)
	else:
		tell(progress.renovation_reason(id),4)
	hud.rebuild()

func change_menu(id: String, change: int) -> void:
	if layout_mode or state != "restaurant":
		return
	menu_plan[id] = clampi(int(menu_plan.get(id,0))+change,0,int(progress.inventory.get(id,0)))
	hud.rebuild()

func menu_total() -> int:
	var count: int = 0
	for value in menu_plan.values():
		count += int(value)
	return count

func service_block_reason() -> String:
	if layout_mode:
		return "先保存布局，再开始营业"
	if progress.renovation.clean and progress.renovation.kitchen and progress.renovation.tables and progress.seats() == 0:
		return "在自由布置中摆放至少一套餐桌"
	if not progress.can_open():
		return "先完成清理、基础厨房和桌椅"
	if progress.last_service_day == progress.day:
		return "今日已营业，先潜水补货迎接下一天"
	if menu_total() <= 0:
		return "在备菜页为菜单添加至少一份鱼料理"
	return ""

func start_service() -> void:
	if layout_mode or state != "restaurant":
		return
	_clamp_menu()
	if not service_block_reason().is_empty():
		tell(service_block_reason(),5)
		return
	if not progress.begin_service(menu_plan):
		tell("无法开业，请检查装修、库存和今日营业状态。",5)
		return
	state = "service"
	orders.clear()
	service_arrived = 0
	service_spawn_time = 0.2
	summary_visible = false
	service_summary.clear()
	service_feedback.clear()
	service_reviews = {"satisfied":0,"okay":0,"lost":0}
	restaurant_node.clear_reactions()
	restaurant_node.set_customers(orders)
	tell("潮间食堂开门迎客！点击制作，完成后记得上菜。",6)
	hud.rebuild()

func service_remaining() -> int:
	var count: int = 0
	for value in progress.service_stock.values():
		count += int(value)
	return count

func _spawn_customer() -> void:
	if state != "service" or orders.size() >= progress.seats() or service_arrived >= progress.guest_limit():
		return
	var dish: String = progress.allocate_dish()
	if dish.is_empty():
		return
	var seat: int = 0
	var occupied: Array = []
	for order in orders:
		occupied.append(order.seat)
	while seat in occupied:
		seat += 1
	order_serial += 1
	orders.append({"id":order_serial,"seat":seat,"dish":dish,"state":"waiting","patience":progress.patience(),"max_patience":progress.patience(),"cook_left":0.0})
	service_arrived += 1
	restaurant_node.set_customers(orders)
	hud.rebuild()

func _update_service(delta: float) -> void:
	if state != "service":
		return
	var changed: bool = false
	for order in orders.duplicate():
		order.patience -= delta
		if order.patience <= 0:
			progress.record_lost(order.dish)
			_record_customer_feedback(order)
			orders.erase(order)
			changed = true
			tell("一位顾客等得太久离开了，已用食材计为损耗。",4)
			continue
		if order.state == "cooking":
			order.cook_left = maxf(0,order.cook_left-delta)
			if order.cook_left <= 0:
				order.state = "ready"
				changed = true
	service_spawn_time -= delta
	if service_spawn_time <= 0:
		service_spawn_time = 2.0
		_spawn_customer()
	restaurant_node.set_customers(orders)
	if changed:
		hud.rebuild()
	if orders.is_empty() and (service_arrived >= progress.guest_limit() or service_remaining() <= 0):
		finish_service()

func cook_order(id: int) -> void:
	if state != "service":
		return
	for order in orders:
		if order.id == id and order.state == "waiting":
			order.state = "cooking"
			order.cook_left = float(Progress.RECIPES[order.dish].cook_time)
			_play_tone(400,0.06)
			break
	restaurant_node.set_customers(orders)
	hud.rebuild()

func serve_order(id: int) -> void:
	if state != "service":
		return
	for order in orders.duplicate():
		if order.id == id and order.state == "ready":
			var earned: int = progress.record_served(order.dish)
			if earned > 0:
				_record_customer_feedback(order)
				orders.erase(order)
				tell("热腾腾的料理送达 · +%d G" % earned,3)
				_play_tone(900,0.12)
			break
	restaurant_node.set_customers(orders)
	hud.rebuild()

func customer_mood(order: Dictionary) -> Dictionary:
	return Feedback.live(order)

func _record_customer_feedback(order: Dictionary, closed: bool = false) -> void:
	var response: Dictionary = Feedback.outcome(order,closed)
	service_reviews[response.mood] += 1
	service_feedback.push_front({"id":order.id,"seat":order.seat,"mood":response.mood,"text":response.text})
	if service_feedback.size() > 3:
		service_feedback.pop_back()
	restaurant_node.react_customer(order,response.mood)

func finish_service() -> void:
	if state not in ["service","service_paused"]:
		return
	for order in orders:
		_record_customer_feedback(order,true)
	service_summary = progress.end_service(orders.size(),service_reviews)
	summary_visible = true
	orders.clear()
	restaurant_node.set_customers(orders)
	state = "restaurant"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clamp_menu()
	tell("今日打烊，未分配的食材已退回仓库。下次出海后可再次营业。",7)
	hud.rebuild()







# Transactional furniture layout: only Save commits money and changes to progress.
func _rebuild_restaurant() -> void:
	var model = layout_work if layout_mode else progress
	restaurant_node.rebuild(model.renovation,model.furniture_items(),{"floor":model.floor_style,"wall":model.wall_style})
	if layout_mode:
		restaurant_node.set_layout_grid(true)
		restaurant_node.highlight_furniture(layout_selected)

func enter_layout() -> void:
	if state != "restaurant" or layout_mode or summary_visible or progress.service_active:
		return
	if not progress.renovation.clean:
		tell("先完成清理与修复，就能自由布置店面。",4)
		return
	layout_work = Progress.new()
	layout_work.persistence_enabled = false
	layout_work._apply_save_data(progress._save_data().duplicate(true))
	layout_mode = true
	layout_selected = -1
	layout_placing = false
	layout_reason = "点选家具，或从左侧选购；保存前不会扣除真实金币。"
	layout_history.clear()
	layout_zoom = 31
	layout_pan = Vector3.ZERO
	layout_panel_visible = true
	layout_panning = false
	_rebuild_restaurant()
	hud.rebuild()

func save_layout() -> void:
	if not layout_mode or state != "restaurant":
		return
	progress._apply_save_data(layout_work._save_data().duplicate(true))
	progress.save_game()
	_end_layout()
	tell("布局已保存。已摆放 %d 套餐桌，营业顾客会使用新的位置。" % progress.seats(),6)

func cancel_layout() -> void:
	if not layout_mode:
		return
	_end_layout()
	tell("已取消本次布置，金币和原布局保持不变。",4)

func _end_layout() -> void:
	layout_mode = false
	layout_placing = false
	layout_selected = -1
	layout_history.clear()
	layout_work = null
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	restaurant_node.clear_layout_preview()
	restaurant_node.set_layout_grid(false)
	restaurant_node.highlight_furniture(-1)
	_rebuild_restaurant()
	hud.rebuild()

func _remember_layout() -> void:
	layout_history.append(layout_work._save_data().duplicate(true))
	if layout_history.size() > 20:
		layout_history.pop_front()

func undo_layout() -> void:
	if not layout_mode or layout_history.is_empty():
		return
	layout_work._apply_save_data(layout_history.pop_back())
	layout_placing = false
	if layout_work.furniture_by_uid(layout_selected).is_empty():
		layout_selected = -1
	if layout_selected >= 0:
		layout_rotation = int(layout_work.furniture_by_uid(layout_selected).rotation)
	layout_reason = "已撤销上一步。"
	_rebuild_restaurant()
	hud.rebuild()

func select_furniture(uid: int) -> void:
	if not layout_mode:
		return
	var item: Dictionary = layout_work.furniture_by_uid(uid)
	if item.is_empty():
		return
	layout_selected = uid
	layout_rotation = int(item.rotation)
	layout_placing = not item.placed
	layout_reason = "移动鼠标预览，左键放下，R 旋转。" if layout_placing else "已选中家具 · G 移动 / R 旋转 / Delete 收回"
	restaurant_node.clear_layout_preview()
	restaurant_node.highlight_furniture(uid)
	hud.rebuild()

func begin_move_furniture() -> void:
	if not layout_mode or layout_work.furniture_by_uid(layout_selected).is_empty():
		return
	layout_placing = true
	layout_rotation = int(layout_work.furniture_by_uid(layout_selected).rotation)
	layout_reason = "选择新位置 · 原位置保留到你确认放下为止"
	hud.rebuild()

func buy_layout_furniture(kind: String, variant: String = "basic") -> void:
	if not layout_mode:
		return
	_remember_layout()
	var uid: int = layout_work.buy_furniture(kind,variant)
	if uid < 0:
		layout_history.pop_back()
		layout_reason = "金币不足，或该家具暂时不能购买。"
		hud.rebuild()
		return
	select_furniture(uid)
	layout_reason = "新家具已加入草稿收纳箱，保存布局时才会扣款。"

func rotate_layout() -> void:
	if not layout_mode:
		return
	var item: Dictionary = layout_work.furniture_by_uid(layout_selected)
	if item.is_empty():
		return
	if layout_placing:
		layout_rotation = (layout_rotation+1)%4
		_update_layout_preview()
		return
	var rotation: int = (int(item.rotation)+1)%4
	var reason: String = layout_work.placement_reason(layout_selected,item.x,item.z,rotation)
	if not reason.is_empty():
		layout_reason = reason + "，可先移动家具再转向。"
		return
	_remember_layout()
	layout_work.place_furniture(layout_selected,item.x,item.z,rotation)
	layout_rotation = rotation
	_rebuild_restaurant()
	hud.rebuild()

func store_selected_furniture() -> void:
	if not layout_mode:
		return
	_remember_layout()
	if not layout_work.store_furniture(layout_selected):
		layout_history.pop_back()
		return
	layout_placing = false
	layout_reason = "家具已收回收纳箱，可随时再次摆放，不需要重新购买。"
	_rebuild_restaurant()
	hud.rebuild()

func color_selected_furniture() -> void:
	if not layout_mode:
		return
	var item: Dictionary = layout_work.furniture_by_uid(layout_selected)
	if item.is_empty():
		return
	_remember_layout()
	layout_work.recolor_furniture(layout_selected,(int(item.color)+1)%3)
	_rebuild_restaurant()
	hud.rebuild()

func set_layout_style(surface: String, style: int) -> void:
	if not layout_mode:
		return
	_remember_layout()
	if not layout_work.set_room_style(surface,style):
		layout_history.pop_back()
	_rebuild_restaurant()
	hud.rebuild()

func reset_layout_draft() -> void:
	if not layout_mode:
		return
	_remember_layout()
	layout_work.reset_layout()
	layout_placing = false
	layout_selected = -1
	layout_reason = "原套装已归位，额外购入家具在收纳箱；可撤销本次还原。"
	_rebuild_restaurant()
	hud.rebuild()

func place_layout_at(x: float, z: float) -> bool:
	if not layout_mode or layout_selected < 0:
		return false
	layout_reason = layout_work.placement_reason(layout_selected,x,z,layout_rotation)
	if not layout_reason.is_empty():
		return false
	_remember_layout()
	if not layout_work.place_furniture(layout_selected,x,z,layout_rotation):
		layout_history.pop_back()
		return false
	layout_placing = false
	layout_reason = "已摆放在草稿中，点击保存布局生效。"
	_rebuild_restaurant()
	hud.rebuild()
	return true

func _layout_point(screen_position: Vector2) -> Variant:
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.001:
		return null
	var distance: float = (restaurant_node.global_position.y+0.08-origin.y)/direction.y
	if distance < 0:
		return null
	var local: Vector3 = restaurant_node.to_local(origin + direction*distance)
	var snapped: Vector2 = Layout.snap_position(local.x,local.z)
	return Vector3(snapped.x,0.08,snapped.y)

func _update_layout_preview() -> void:
	if not layout_mode:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	if not layout_view_rect().has_point(mouse) or not layout_placing:
		restaurant_node.clear_layout_preview()
		return
	var point: Variant = _layout_point(mouse)
	if point == null:
		return
	layout_cursor = point
	var item: Dictionary = layout_work.furniture_by_uid(layout_selected)
	if item.is_empty():
		return
	layout_reason = layout_work.placement_reason(layout_selected,layout_cursor.x,layout_cursor.z,layout_rotation)
	restaurant_node.set_layout_preview(item.kind,layout_cursor,layout_rotation,item.color,layout_reason.is_empty(),str(item.get("variant","basic")))

func layout_view_rect() -> Rect2:
	return LAYOUT_AREA if layout_panel_visible else Rect2(8,96,1424,708)

func toggle_layout_panel() -> void:
	if not layout_mode:
		return
	layout_panel_visible = not layout_panel_visible
	hud.rebuild()

func reset_layout_camera() -> void:
	layout_zoom = 31
	layout_pan = Vector3.ZERO
	layout_panning = false

func update_layout_camera() -> void:
	var right := Vector3(17,0,-10).normalized()
	var focus := restaurant_node.position + Vector3(0,0,3) + layout_pan
	if layout_panel_visible:
		focus -= right * layout_zoom * 0.112
	camera.position = focus + Vector3(10,24,17)
	camera.look_at(focus)

func _layout_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if not event.pressed:
			layout_panning = false
		elif layout_view_rect().has_point(event.position):
			layout_panning = true
		return
	if event is InputEventMouseMotion and layout_panning:
		var right: Vector3 = camera.global_transform.basis.x
		var forward := Vector3(right.z,0,-right.x)
		layout_pan -= (right * event.relative.x + forward * event.relative.y) * layout_zoom / 1000.0
		layout_pan.x = clampf(layout_pan.x,-16,16)
		layout_pan.z = clampf(layout_pan.z,-14,14)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if layout_placing:
					layout_placing = false
					restaurant_node.clear_layout_preview()
					layout_reason = "已取消这次摆放，草稿中的其他修改保留。"
					hud.rebuild()
				else:
					cancel_layout()
			KEY_TAB: toggle_layout_panel()
			KEY_F: reset_layout_camera()
			KEY_R: rotate_layout()
			KEY_G: begin_move_furniture()
			KEY_DELETE: store_selected_furniture()
			KEY_Z:
				if event.ctrl_pressed:
					undo_layout()
	if event is InputEventMouseButton and event.pressed and layout_view_rect().has_point(event.position):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			layout_zoom = maxf(12,layout_zoom-1.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			layout_zoom = minf(52,layout_zoom+1.5)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			layout_placing = false
			restaurant_node.clear_layout_preview()
			layout_reason = "已取消摆放。"
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var point: Variant = _layout_point(event.position)
			if point == null:
				return
			if layout_placing:
				place_layout_at(point.x,point.z)
			else:
				var chosen: int = -1
				for item in layout_work.furniture_items():
					if item.placed and Layout.bounds(item).has_point(Vector2(point.x,point.z)):
						if chosen < 0 or item.kind != "rug":
							chosen = int(item.uid)
				if chosen >= 0:
					select_furniture(chosen)

