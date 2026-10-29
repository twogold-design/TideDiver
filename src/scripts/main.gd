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
const StormSchool = preload("res://scripts/storm_school.gd")
const DiverMotion = preload("res://scripts/diver_motion.gd")
const SandRays = preload("res://scripts/ray_habitat.gd")
const CanyonShark = preload("res://scripts/thresher_shark.gd")
const StonefishHabitat = preload("res://scripts/stonefish_habitat.gd")
const DepthLighting = preload("res://scripts/depth_lighting.gd")
const Loot = preload("res://scripts/loot_catalog.gd")
const DiverBubbles = preload("res://scripts/diver_bubbles.gd")
const MarineLife = preload("res://scripts/marine_life.gd")
const ReefFish = preload("res://scripts/reef_fish_habitat.gd")
const ReefPlants = preload("res://scripts/reef_vegetation.gd")
const CoralGarden = preload("res://scripts/coral_garden.gd")
var reef_plants: Node3D
const SWIMMING_SPECIES := 9
const COASTAL_FISH_COUNT = 21
const COASTAL_KINDS = [0,1,3,4,6,2]
const ENTRY_SCHOOL_KINDS = [0,1,3,4,6]
const ENTRY_FISH_PER_SCHOOL = 2
const OUTER_FISH_PER_ZONE = 16
const Harpoon = preload("res://scripts/harpoon.gd")
const Cuisine = preload("res://scripts/cuisine.gd")
const TRANSIT_SCHOOLS = 8
const TRANSIT_FISH_PER_SCHOOL = 5
const SPEAR_RANGE = 20.0
const SPEAR_COOLDOWN = 0.95
var progress = Progress.new()
var state: String = "dock"
var canyon_root: Node3D
var drift_current: Vector3 = Vector3.ZERO
var current_hint: String = ""
var storm_school: Node3D
var ray_habitat: Node3D
var explorable_wreck: Node3D
var canyon_shark: Node3D
var stonefish_count: int = 0
var _camera_probe: SphereShape3D
var boat: Node3D
var dive_origin: Vector3 = Vector3.ZERO
var entry_site_index: int = -1
var entry_rng = RandomNumberGenerator.new()
var wildlife_rng = RandomNumberGenerator.new()
var gm_menu_open: bool = false
var gm_return_state: String = "dock"
var gm_test_active: bool = false
var gm_infinite_air: bool = false
var player: CharacterBody3D
var diver_motion = DiverMotion.new()
var camera: Camera3D
var environment: Environment
var ocean_sun: DirectionalLight3D
var diver_light: OmniLight3D
var diver_bubbles: Node3D
var marine_life: Node3D
var reef_fish: Node3D
var hud: Node2D
var fish: Array = []
var pickups: Array = []
var hazards: Array = []
var effects: Array = []
var projectiles: Array = []
var cargo: Array = []
var oxygen: float = 100.0
var catch_timer: float = 0.0
var loot_feedback: Array[String] = []
var loot_feedback_title: String = ""
var loot_feedback_note: String = ""
var loot_feedback_timer: float = 0.0
var capacity_warning_timer: float = 0.0
var capacity_warning_name: String = ""
var capacity_warning_weight: int = 0
var capacity_warning_action: String = ""
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
var hurt_flash: float = 0.0
var poison_timer: float = 0.0
var hunt_warning: String = ""
var hunt_warning_timer: float = 0.0
var notice: String = "潮汐湾的第一束晨光，正在等你。"
var notice_timer: float = 8.0
var last_result: Dictionary = {}
var rescue_result_visible := false
var harvest_result_visible := false
var rescue_time := 0.0
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
var menu_seasoning: Dictionary = {"orange":1,"blue":0,"lantern":2}
var preparation: Dictionary = {}
var service_preparation: Dictionary = {}
var culinary_results: Dictionary = {"excellent":0,"matched":0,"cold":0,"bonus":0}
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
var layout_pending_purchase: Dictionary = {}
var layout_rotation: int = 0
var layout_cursor: Vector3 = Vector3.ZERO
var layout_reason: String = ""
var layout_history: Array = []
var layout_zoom: float = 31.0
var layout_panel_visible: bool = true
var layout_pan: Vector3 = Vector3.ZERO
var layout_panning: bool = false
var layout_orbiting: bool = false
const LAYOUT_DEFAULT_YAW: float = 0.5317240673
const LAYOUT_DEFAULT_PITCH: float = 0.8829062407
var layout_camera_yaw: float = LAYOUT_DEFAULT_YAW
var layout_camera_pitch: float = LAYOUT_DEFAULT_PITCH
var _entry_water_meshes: Array[SphereMesh] = []
var _entry_water_material: StandardMaterial3D
const LAYOUT_AREA = Rect2(332,96,1100,708)

func _ready() -> void:
	rng.seed = 271828
	entry_rng.randomize()
	wildlife_rng.randomize()
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
	_prepare_entry_water()
	if OS.has_feature("web"):
		var web_platform = preload("res://scripts/web_platform.gd").new()
		web_platform.game = self
		add_child(web_platform)
	capture_mode = "--capture" in OS.get_cmdline_user_args() or "--capture-dock" in OS.get_cmdline_user_args() or "--capture-deep" in OS.get_cmdline_user_args()
	smoke_mode = "--smoke" in OS.get_cmdline_user_args()
	if capture_mode and not "--capture-dock" in OS.get_cmdline_user_args():
		start_dive(false, false)
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
		start_dive(false, false)
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
		start_dive(false, false)
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
	ocean_sun = DirectionalLight3D.new()
	ocean_sun.rotation_degrees = Vector3(-55, -28, 0)
	ocean_sun.light_color = Color("fff1d4")
	ocean_sun.light_energy = 0.65
	ocean_sun.shadow_enabled = true
	add_child(ocean_sun)
	ocean_root = Node3D.new()
	add_child(ocean_root)
	Art.build_world(ocean_root)
	reef_plants = ReefPlants.build(ocean_root)
	canyon_root = ocean_root.get_node("OuterOcean/twin_gates/TidalCanyon")
	explorable_wreck = ocean_root.get_node("OuterOcean/merchant_wreck/ExplorableWreck")
	ray_habitat = SandRays.new()
	ocean_root.add_child(ray_habitat)
	canyon_shark = CanyonShark.build(ocean_root)
	storm_school = StormSchool.new()
	storm_school.position = StormSchool.CENTER
	ocean_root.add_child(storm_school)
	boat = Art.create_boat()
	boat.position = Vector3(0, 0.3, 14)
	ocean_root.add_child(boat)
	player = CharacterBody3D.new()
	player.add_child(Art.create_diver())
	diver_motion.setup(player.get_child(0))
	var collider = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.65
	collider.shape = shape
	player.add_child(collider)
	player.position = Vector3(0, -6, 14)
	add_child(player)
	ray_habitat.ignored_bodies.append(player.get_rid())
	_camera_probe = SphereShape3D.new()
	_camera_probe.radius = 0.28
	camera = Camera3D.new()
	camera.fov = 66
	camera.far = 1100
	camera.current = true
	add_child(camera)
	diver_light = OmniLight3D.new()
	diver_light.light_color = Color("a2ffe4")
	diver_light.light_energy = 0.35
	diver_light.omni_range = 12
	player.add_child(diver_light)
	diver_bubbles = DiverBubbles.new()
	ocean_root.add_child(diver_bubbles)
	diver_bubbles.ignored_bodies.append(player.get_rid())
	marine_life = MarineLife.build(ocean_root,[player.get_rid()],explorable_wreck)
	reef_fish = ReefFish.build(ocean_root)
	_reset_shore_lighting()

func _spawn_population() -> void:
	marine_life.reset()
	reef_fish.reset()
	reef_plants.animate(0.0,reef_plants.global_position)
	CoralGarden.animate(0.0)
	ReefPlants.animate_shared(0.0)
	ray_habitat.reset()
	canyon_shark.begin_dive(wildlife_rng.randi())
	for item in fish:
		item.node.queue_free()
	for item in pickups:
		item.node.queue_free()
	for item in hazards:
		item.node.queue_free()
	fish.clear()
	pickups.clear()
	hazards.clear()
	for i in range(COASTAL_FISH_COUNT):
		var kind: int = COASTAL_KINDS[posmod(i - 5, COASTAL_KINDS.size())]
		var depth: float = rng.randf_range(7, 15) if kind != 2 else rng.randf_range(17, 24)
		var p = Vector3(rng.randf_range(-34, 34), -depth, rng.randf_range(-37, 27))
		if i >= 13:
			var angle: float = float(i)*2.399963
			var reach: float = rng.randf_range(47.0,Ocean.COASTAL_RADIUS*0.90)
			p.x = sin(angle)*reach
			p.z = cos(angle)*reach
		if i < 5:
			kind = 0
			p = Vector3((i - 2) * 3.0, -7 - i * 0.6, 1 - i * 2.0)
		_add_fish(kind,p)
	var places: Array = [Vector3(3,-8,8),Vector3(-8,-16,0),Vector3(13,-22,-8),Vector3(-14,-29,-14),Vector3(7,-38,-22),Vector3(-5,-46,-29),Vector3(24,-48,7)]
	for index in range(places.size()):
		_add_pickup(places[index], Loot.COASTAL_KINDS[index])
	_add_pickup(Vector3(1,-49,-25), "chest")
	_add_pickup(Vector3(-22,-34,-6), "chest")
	_add_pickup(Vector3(-5,-18,3), "oxygen")
	_add_pickup(Vector3(15,-37,-15), "oxygen")
	for i in range(7):
		var node = _jellyfish()
		var pos = Vector3(rng.randf_range(-25,25),rng.randf_range(-45,-22),rng.randf_range(-28,14))
		pos = _safe_hazard_home(pos)
		node.position = pos
		ocean_root.add_child(node)
		hazards.append({"node":node,"home":pos,"phase":float(i)})

	for zone_index in range(Ocean.ZONES.size()):
		for i in range(OUTER_FISH_PER_ZONE):
			var kind: int = (i+zone_index*2) % SWIMMING_SPECIES
			_add_fish(kind,Ocean.fish_home(zone_index,i))
	# Scattered travelling schools connect the bay to distant habitats.
	for school in range(TRANSIT_SCHOOLS):
		var angle: float = float(school)*2.399
		var radius: float = 75.0+float(school)*18.0
		var center := Vector3(cos(angle)*radius,-20.0-float(school%3)*10.0,sin(angle)*radius)
		for i in range(TRANSIT_FISH_PER_SCHOOL):
			var kind: int = [3,1,4,6,3,5,1,6][school]
			_add_fish(kind,center+Vector3(sin(float(i)*2.399)*16,float(i%3)*3,cos(float(i)*2.399)*14))
	_spread_background_fish()
	_spawn_entry_fish()
	for point in Ocean.pickup_points():
		var pickup_position: Vector3 = explorable_wreck.to_global(point.wreck_local) if point.has("wreck_local") else point.position
		_add_pickup(pickup_position,point.kind)
		if point.get("exploration",false):
			pickups[-1]["exploration_site"] = point.site_index
			pickups[-1]["location_name"] = point.name
	for zone in Ocean.ZONES:
		var node: Node3D = _jellyfish()
		var pos: Vector3 = Ocean.hazard_home(Ocean.ZONES.find(zone))
		pos = _safe_hazard_home(pos)
		node.position = pos
		ocean_root.add_child(node)
		hazards.append({"node":node,"home":pos,"phase":rng.randf_range(0,TAU)})
	stonefish_count = StonefishHabitat.populate(self)
func fish_population_count() -> int:
	return COASTAL_FISH_COUNT+OUTER_FISH_PER_ZONE*Ocean.ZONES.size()+TRANSIT_SCHOOLS*TRANSIT_FISH_PER_SCHOOL+ENTRY_SCHOOL_KINDS.size()*ENTRY_FISH_PER_SCHOOL

func _add_fish(kind: int, point: Vector3) -> Dictionary:
	var p := point
	if FishData.SPECIES[kind].behavior in ["venom","ambush","predator"]:
		var landing := dive_origin + Vector3(0,-6,25)
		var away := Vector2(p.x-landing.x,p.z-landing.z)
		if away.length() < 42.0:
			away = away.normalized() * 45.0 if away.length_squared() > 0.01 else Vector2(45,0)
			p.x = landing.x + away.x
			p.z = landing.z + away.y
	p.y = clampf(p.y,minf(-6,maxf(Ocean.Y_MIN+3,Ocean.seabed_height(p.x,p.z)+5)),-6)
	p = _clear_fish_home(p, kind)
	if not p.is_finite():
		return {}
	var node: Node3D = Art.create_fish(kind)
	node.position = p
	ocean_root.add_child(node)
	var item: Dictionary = {"node":node,"kind":kind,"home":p,"phase":rng.randf_range(0,TAU),"hp":int(FishData.SPECIES[kind].hp),"alive":true}
	FishBrain.prepare(item)
	fish.append(item)
	return item
func _open_water(point: Vector3, radius: float = 1.2) -> bool:
	# A trimesh only tests its surface; points inside an island are also solid land.
	if point.y < Ocean.seabed_height(point.x,point.z)+radius:
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _clear_fish_home(point: Vector3, kind: int) -> Vector3:
	var radius: float = float(FishData.SPECIES[kind].radius)
	var dangerous: bool = FishData.SPECIES[kind].behavior in ["venom","ambush","predator"]
	var landing := dive_origin + Vector3(0,-6,25)
	if point.y <= -maxf(3.0,radius) and _open_water(point, radius):
		return point
	for ring in range(1,13):
		for direction in range(8):
			var angle: float = float(direction) * TAU / 8.0
			var candidate := point + Vector3(sin(angle)*ring*2.5,ring*0.5,cos(angle)*ring*2.5)
			candidate.x = clampf(candidate.x,Ocean.X_MIN+5,Ocean.X_MAX-5)
			candidate.z = clampf(candidate.z,Ocean.Z_MIN+5,Ocean.Z_MAX-5)
			if Ocean.seabed_height(candidate.x,candidate.z)+5 > -6:
				continue
			candidate.y = clampf(candidate.y,Ocean.seabed_height(candidate.x,candidate.z)+5,-6)
			if dangerous and Vector2(candidate.x-landing.x,candidate.z-landing.z).length() < 42.0:
				continue
			if _open_water(candidate,radius):
				return candidate
	# If a landmark fills the local area, search verified open water across the map.
	for x in range(-400,401,100):
		for z in range(-400,401,100):
			var candidate := Vector3(x,-6,z)
			if dangerous and Vector2(candidate.x-landing.x,candidate.z-landing.z).length() < 42.0:
				continue
			if _open_water(candidate,radius):
				return candidate
	push_error("No open water available for fish spawn")
	return Vector3.INF

func _select_dive_site(random_entry: bool, site_override: int = -1) -> void:
	if site_override >= 0 and site_override < Ocean.DIVE_SITES.size():
		entry_site_index = site_override
		dive_origin = Ocean.DIVE_SITES[site_override].origin
		boat.position = dive_origin + Vector3(0,0.3,14)
		return
	if not random_entry:
		dive_origin = Vector3.ZERO
		entry_site_index = 0
		boat.position = dive_origin + Vector3(0,0.3,14)
		return
	var first: int = entry_rng.randi_range(0, Ocean.DIVE_SITES.size()-1)
	if entry_site_index >= 0:
		first = entry_rng.randi_range(0, Ocean.DIVE_SITES.size()-2)
		if first >= entry_site_index:
			first += 1
	for offset in range(Ocean.DIVE_SITES.size()):
		var index: int = (first + offset) % Ocean.DIVE_SITES.size()
		if index == entry_site_index:
			continue
		for attempt in range(12):
			var origin: Vector3 = Ocean.DIVE_SITES[index].origin + Vector3(entry_rng.randf_range(-8,8),0,entry_rng.randf_range(-8,8))
			var clear: bool = true
			for local_point: Vector3 in [Vector3(0,0.5,22.5),Vector3(0,-3,24),Vector3(0,-6,25),Vector3(0,-6,14),Vector3(0,-4,17.5)]:
				if not _open_water(origin + local_point):
					clear = false
					break
			if clear:
				dive_origin = origin
				entry_site_index = index
				boat.position = origin + Vector3(0,0.3,14)
				return
	# The original cove remains a known clear fallback.
	dive_origin = Vector3.ZERO
	entry_site_index = 0
	boat.position = Vector3(0,0.3,14)

func _safe_hazard_home(point: Vector3) -> Vector3:
	var p := point
	var landing := dive_origin + Vector3(0,-6,25)
	var away := Vector2(p.x-landing.x,p.z-landing.z)
	if away.length() < 20.0:
		away = away.normalized() * 23.0 if away.length_squared() > 0.01 else Vector2(23,0)
		p.x = landing.x + away.x
		p.z = landing.z + away.y
	p.y = maxf(p.y,Ocean.seabed_height(p.x,p.z)+4.0)
	if p.y > -4.0:
		p.x = Ocean.canyon_center_x(p.z)
		p.y = maxf(-30.0,Ocean.seabed_height(p.x,p.z)+4.0)
	return p

func _spread_background_fish() -> void:
	# Keep the landing open instead of stacking local and travelling populations.
	var landing := dive_origin + Vector3(0,-6,25)
	for item in fish.slice(5):
		var offset := Vector2(item.home.x-landing.x,item.home.z-landing.z)
		if offset.length() >= 35.0:
			continue
		offset = offset.normalized()*40.0 if offset.length_squared() > 0.01 else Vector2(40,0)
		var point := Vector3(landing.x+offset.x,item.home.y,landing.z+offset.y)
		point.y = clampf(point.y,minf(-6,Ocean.seabed_height(point.x,point.z)+5),-6)
		point = _clear_fish_home(point,item.kind)
		if point.is_finite():
			item.home = point
			item.node.position = point

func _spawn_entry_fish() -> void:
	# Small, separated pairs keep variety without filling the entire view.
	var anchors: Array[Vector3] = [Vector3(-12,-8,38),Vector3(10,-11,43),Vector3(-3,-9,49),Vector3(-23,-13,63),Vector3(22,-12,76)]
	for school in range(ENTRY_SCHOOL_KINDS.size()):
		var kind: int = ENTRY_SCHOOL_KINDS[school]
		for i in range(ENTRY_FISH_PER_SCHOOL):
			var point: Vector3 = dive_origin + anchors[school] + Vector3((float(i)-0.5)*8,0,0)
			point += Vector3(rng.randf_range(-1,1),rng.randf_range(-0.75,0.75),rng.randf_range(-1,1))
			_add_fish(kind,point)

func _add_pickup(pos: Vector3, kind: String) -> void:
	if Ocean.seabed_height(pos.x,pos.z) > -5.0:
		pos.x = Ocean.canyon_center_x(pos.z)
		pos.y = minf(pos.y,-8.0)
	pos.y = maxf(pos.y,Ocean.seabed_height(pos.x,pos.z)+1.0)
	var node: Node3D = Art.create_pickup(kind)
	node.position = pos
	ocean_root.add_child(node)
	var item: Dictionary = {"node":node,"kind":kind,"home":pos,"active":true}
	if kind == "chest":
		Loot.prepare_chest(item,wildlife_rng.randi())
	pickups.append(item)

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
	if state not in ["dock","paused"] or new_game_confirmation or gm_menu_open:
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
	gm_menu_open = false
	gm_test_active = false
	gm_return_state = "dock"
	gm_infinite_air = false
	diver_bubbles.reset()
	state = "dock"
	entry_active = false
	drift_current = Vector3.ZERO
	current_hint = ""
	entry_time = 0.0
	entry_splashed = false
	catch_timer = 0.0
	_clear_loot_feedback()
	hit_timer = 0.0
	cargo.clear()
	orders.clear()
	last_result.clear()
	rescue_result_visible = false
	harvest_result_visible = false
	rescue_time = 0.0
	service_summary.clear()
	service_feedback.clear()
	service_reviews = {"satisfied":0,"okay":0,"lost":0}
	restaurant_node.clear_reactions()
	summary_visible = false
	menu_plan = {"orange":0,"blue":0,"lantern":0}
	menu_seasoning = {"orange":1,"blue":0,"lantern":2}
	preparation.clear()
	service_preparation.clear()
	culinary_results = {"excellent":0,"matched":0,"cold":0,"bonus":0}
	_clear_projectiles()
	restaurant_tab = "renovation"
	service_arrived = 0
	service_spawn_time = 0
	order_serial = 0
	service_close_view = false
	layout_mode = false
	layout_work = null
	layout_selected = -1
	layout_placing = false
	layout_pending_purchase.clear()
	layout_rotation = 0
	layout_cursor = Vector3.ZERO
	layout_reason = ""
	layout_history.clear()
	layout_zoom = 31
	layout_panel_visible = true
	layout_pan = Vector3.ZERO
	layout_panning = false
	layout_orbiting = false
	layout_camera_yaw = LAYOUT_DEFAULT_YAW
	layout_camera_pitch = LAYOUT_DEFAULT_PITCH
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
	dive_origin = Vector3.ZERO
	diver_motion.reset()
	entry_site_index = -1
	boat.position = Vector3(0,0.3,14)
	player.position = Vector3(0,-6,14)
	oxygen = progress.oxygen_max()
	depth_record = 0
	yaw = 0
	pitch = -0.12
	clock = 0
	shot_cooldown = 0
	hurt_cooldown = 0
	hurt_flash = 0
	poison_timer = 0
	hunt_warning_timer = 0
	hunt_warning = ""
	_spawn_population()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 66
	environment.fog_enabled = true
	_reset_shore_lighting()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tell("新的旅程开始了。从第一天出海，重新打造你的海岸小店。",9)
	hud.rebuild()

func start_dive(animate_entry: bool = true, random_entry: bool = true, site_override: int = -1) -> void:
	if new_game_confirmation or gm_menu_open or rescue_result_visible or state != "dock":
		return
	if site_override < -1 or site_override >= Ocean.DIVE_SITES.size():
		return
	harvest_result_visible = false
	gm_test_active = false
	diver_bubbles.reset()
	_clear_projectiles()
	restaurant_node.visible = false
	preparation.clear()
	ocean_root.visible = true
	environment.fog_enabled = true
	camera.fov = 66
	_select_dive_site(random_entry, site_override)
	_spawn_population()
	cargo.clear()
	oxygen = progress.oxygen_max()
	depth_record = 0
	catch_timer = 0.0
	_clear_loot_feedback()
	hit_timer = 0.0
	drift_current = Vector3.ZERO
	current_hint = ""
	entry_active = animate_entry
	entry_time = 0.0
	entry_splashed = false
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.position = dive_origin + (Vector3(0,2.4,17.5) if animate_entry else Vector3(0,-6,14))
	diver_motion.reset()
	player.visible = true
	player.get_child(0).visible = true
	yaw = 0
	pitch = -0.12
	shot_cooldown = 0
	hurt_cooldown = 0
	hurt_flash = 0
	poison_timer = 0
	hunt_warning_timer = 0
	hunt_warning = ""
	state = "dive"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	tell("WASD 游泳 · Q 下潜 / E 上浮 · 鼠标瞄准 · 左键发射鱼叉", 9)
	hud.rebuild()
	if entry_active:
		tell("本次入水 · %s" % Ocean.DIVE_SITES[entry_site_index].name, 3.2)
		_update_entry(0.0)
	else:
		_update_swim_camera()
	_play_tone(480, 0.18)

func open_gm_menu() -> void:
	if gm_menu_open or new_game_confirmation or rescue_result_visible or layout_mode or state not in ["dock","dive","paused"]:
		return
	gm_return_state = state
	gm_menu_open = true
	if state == "dive":
		state = "paused"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.rebuild()

func close_gm_menu() -> void:
	if not gm_menu_open:
		return
	gm_menu_open = false
	state = gm_return_state
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if state == "dive" else Input.MOUSE_MODE_VISIBLE
	hud.rebuild()

func toggle_gm_infinite_air() -> void:
	if not gm_menu_open:
		return
	gm_infinite_air = not gm_infinite_air
	if gm_infinite_air:
		oxygen = progress.oxygen_max()
	hud.rebuild()

func _consume_air(amount: float) -> void:
	if not gm_infinite_air:
		oxygen = maxf(0.0,oxygen-maxf(0.0,amount))

func gm_select_dive_site(index: int, direct: bool = false) -> void:
	if not gm_menu_open or index < 0 or index >= Ocean.DIVE_SITES.size():
		return
	var from_dock: bool = gm_return_state == "dock"
	gm_menu_open = false
	if from_dock:
		state = "dock"
		start_dive(not direct, false, index)
	else:
		# Move within this dive: harvested fish, cargo, air and progress stay intact.
		_select_dive_site(false, index)
		_clear_projectiles()
		state = "dive"
	gm_test_active = true
	diver_bubbles.reset()
	entry_active = not direct
	entry_time = 0.0
	entry_splashed = false
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	drift_current = Vector3.ZERO
	diver_motion.reset()
	player.get_child(0).visible = true
	current_hint = ""
	catch_timer = 0.0
	_clear_loot_feedback()
	hit_timer = 0.0
	shot_cooldown = 0.0
	hurt_cooldown = 0.0
	hurt_flash = 0.0
	poison_timer = 0.0
	hunt_warning_timer = 0.0
	hunt_warning = ""
	camera.fov = 66
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	if direct:
		var pose: Dictionary = _gm_test_pose(index)
		player.position = pose.position
		yaw = pose.yaw
		pitch = pose.pitch
		player.rotation.y = yaw
		_update_swim_camera()
	else:
		_update_entry(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	tell("GM · %s · %s" % [Ocean.DIVE_SITES[index].name,"直达景观" if direct else "船上入水"],5)
	hud.rebuild()

func _gm_test_pose(index: int) -> Dictionary:
	var point: Vector3 = Ocean.DIVE_SITES[index].origin + Vector3(0,-9,12)
	var heading: float = 0.0
	var tilt: float = -0.12
	match str(Ocean.DIVE_SITES[index].id):
		"twin_gates":
			point = Vector3(Ocean.canyon_center_x(-325),-78,-325)
			var downstream: Vector3 = Ocean.canyon_tangent(point.z)
			heading = atan2(-downstream.x,-downstream.z)
			tilt = -0.20
		"merchant_wreck":
			point = explorable_wreck.to_global(Vector3(0,6,36))
			heading = explorable_wreck.rotation.y
		"amber_reef":
			point = Vector3(-180,-11,180)
			tilt = -0.25
		"southern_spires":
			point = StormSchool.CENTER + Vector3(0,0,37)
		"pearl_atoll":
			point = Vector3(245,Ocean.seabed_height(245,276)+12,276)
	# Verify real terrain/landmark collision before placing a player at a viewpoint.
	if not _open_water(point):
		var found: bool = false
		for ring in range(1,13):
			for direction in range(8):
				var angle: float = float(direction)*TAU/8.0
				var candidate := point + Vector3(sin(angle)*ring*2.0,ring*1.5,cos(angle)*ring*2.0)
				if Ocean.seabed_height(candidate.x,candidate.z)+3 > -6:
					continue
				candidate.y = clampf(candidate.y,Ocean.seabed_height(candidate.x,candidate.z)+3,-6)
				if _open_water(candidate):
					point = candidate
					found = true
					break
			if found:
				break
		if not found:
			point = Ocean.DIVE_SITES[index].origin + Vector3(0,-6,25)
	return {"position":point,"yaw":heading,"pitch":tilt}

func finish_dive(rescued: bool = false) -> void:
	if state != "dive":
		return
	_clear_loot_feedback()
	diver_bubbles.reset()
	var depleted: bool = rescued and oxygen <= 0.0
	gm_test_active = false
	diver_motion.reset()
	drift_current = Vector3.ZERO
	current_hint = ""
	entry_active = false
	camera.fov = 66
	_clear_projectiles()
	last_result = progress.complete_dive(cargo, rescued, depth_record)
	last_result["depleted"] = depleted
	rescue_result_visible = rescued
	if not depleted:
		_reset_shore_lighting()
	cargo.clear()
	state = "rescuing" if depleted else "dock"
	rescue_time = 2.8 if depleted else 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if rescued:
		tell("救援艇已接你返航。货物按 35% 价值结算，升级潜水气瓶后再试一次。", 14)
	else:
		tell("收获 %d 件，已存入仓库。去餐厅售卖筹资，或留下鱼做菜。" % last_result.count, 5)
		harvest_result_visible = true
	hud.rebuild()
	_play_tone(660,0.28)

func dismiss_rescue_result() -> void:
	if state != "dock" or not rescue_result_visible:
		return
	rescue_result_visible = false
	hud.rebuild()

func _update_rescue(delta: float) -> void:
	rescue_time = maxf(0.0, rescue_time - delta)
	if rescue_time <= 0.0:
		state = "dock"
		_reset_shore_lighting()
		hud.rebuild()

func upgrade(kind: String) -> void:
	if progress.buy_upgrade(kind):
		tell("装备升级完成，下一次可以探索得更远。", 5)
		_play_tone(760,0.12)
	else:
		tell("金币不足，或这件装备已经满级。", 4)
	hud.rebuild()

func toggle_pause() -> void:
	if gm_menu_open:
		close_gm_menu()
		return
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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		layout_panning = false
		layout_orbiting = false
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state in ["dive","service"] and not capture_mode and not smoke_mode:
		toggle_pause()

func _input(event: InputEvent) -> void:
	if not layout_mode or not (layout_panning or layout_orbiting):
		return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed):
		_layout_input(event)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if state == "rescuing":
		return
	if rescue_result_visible:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_SPACE]:
			dismiss_rescue_result()
		return
	if new_game_confirmation:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			cancel_new_game()
		return
	if gm_menu_open:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE,KEY_F1]:
			close_gm_menu()
			get_viewport().set_input_as_handled()
		return
	if layout_mode:
		_layout_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			open_gm_menu()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_ESCAPE and not (OS.has_feature("web") and state == "paused"):
			toggle_pause()
		if event.physical_keycode == KEY_P:
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
	if state == "rescuing":
		_update_rescue(delta)
		hud.queue_redraw()
		return
	if state not in ["paused","service_paused"]:
		clock += delta
		notice_timer = maxf(0, notice_timer-delta)
		if notice_timer <= 0.0:
			harvest_result_visible = false
		_animate_ocean(delta)
	if state == "dive":
		if entry_active:
			_update_entry(delta)
		else:
			_update_dive(delta)
			_update_projectiles(delta)
			if state == "dive":
				var effort: float = 1.0 if Input.is_action_pressed("boost") else minf(0.5,player.velocity.length()/12.0)
				diver_bubbles.advance(delta,player.get_child(0).global_transform,true,effort,drift_current)
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
		elif state == "restaurant" and not layout_mode:
			_update_preparation(delta)
	elif state == "dock":
		var p = Vector3(16 + sin(clock*0.045)*3, -13, 29)
		camera.position = p
		camera.look_at(Vector3(0,-23,-10))
		player.visible = false
	if state not in ["paused","service_paused"]:
		catch_timer = maxf(0, catch_timer - delta)
		loot_feedback_timer = maxf(0, loot_feedback_timer - delta)
		capacity_warning_timer = maxf(0, capacity_warning_timer - delta)
		hit_timer = maxf(0, hit_timer - delta)
		hurt_flash = maxf(0, hurt_flash - delta)
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
		player.position = dive_origin + Vector3(0, 2.4 - sin(t / 0.45 * PI) * 0.25, 17.5)
		player.rotation = Vector3(PI / 2, PI, 0)
	elif t < 1.55:
		var u: float = (t - 0.45) / 1.1
		player.position = dive_origin + Vector3(0, 2.4 + 2.0 * u - 4.8 * u * u, 17.5 + 5.0 * u)
		player.rotation = Vector3(lerpf(PI / 2, -0.65, smoothstep(0.0, 1.0, u)), PI, 0)
	else:
		var u: float = smoothstep(0.0, 1.0, (t - 1.55) / 1.65)
		player.position = dive_origin + Vector3(0, lerpf(-0.4, -6.0, u), lerpf(22.5, 25.0, u))
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
	var light_profile: Dictionary = _apply_underwater_lighting(maxf(0.0,-camera.position.y),submerged)
	environment.background_color = Color("89c6cd").lerp(light_profile.water_color, submerged)
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
	sound_player.stream = preload("res://assets/audio/dive_splash.wav")
	sound_player.play()

func _capture_feedback(kind: int, location: Vector3) -> void:
	_clear_loot_feedback()
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

func _prepare_entry_water() -> void:
	_entry_water_material = StandardMaterial3D.new()
	_entry_water_material.albedo_color = Color("b9f1ed")
	_entry_water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(4):
		var sphere := SphereMesh.new()
		sphere.radius = 0.06 + float(i) * 0.025
		sphere.height = sphere.radius * 2
		_entry_water_meshes.append(sphere)

func _spawn_entry_water() -> void:
	for i in range(42):
		var droplet := MeshInstance3D.new()
		droplet.mesh = _entry_water_meshes[i % 4]
		droplet.material_override = _entry_water_material
		var angle: float = float(i) * 2.399
		var bubble: bool = i >= 24
		droplet.position = Vector3(player.position.x + sin(angle) * 0.4, -0.8 if bubble else 0.65, player.position.z + cos(angle) * 0.4)
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
	drift_current = Ocean.current_velocity(player.position)
	current_hint = ""
	if drift_current.length() > 0.05:
		var alignment: float = move.dot(drift_current.normalized())
		if move.length() < 0.1:
			current_hint = "随流漂行"
		elif alignment > 0.25:
			current_hint = "顺流 · 水流助推"
		elif alignment < -0.25:
			current_hint = "逆流 · 水流阻力"
		else:
			current_hint = "横向游动 · 水流侧推"
	player.velocity = move * speed + drift_current
	var previous_position: Vector3 = player.position
	player.move_and_slide()
	player.position.x = clampf(player.position.x,Ocean.X_MIN,Ocean.X_MAX)
	player.position.z = clampf(player.position.z,Ocean.Z_MIN,Ocean.Z_MAX)
	var floor_limit: float = maxf(Ocean.Y_MIN,Ocean.seabed_height(player.position.x,player.position.z)+0.8)
	if floor_limit > Ocean.Y_MAX:
		# Never resolve a shoreline collision by lifting the swimmer onto dry land.
		player.position = previous_position
		player.velocity = Vector3.ZERO
	else:
		player.position.y = clampf(player.position.y,floor_limit,Ocean.Y_MAX)
	player.rotation.y = lerp_angle(player.rotation.y,yaw,delta*8)
	player.rotation.x = lerpf(player.rotation.x,vertical*0.22,delta*5)
	diver_motion.advance(delta, Vector3(input_dir.x,vertical,input_dir.y).limit_length(), boosting)
	depth_record = maxf(depth_record,-player.position.y)
	var use_rate: float = (0.72 + maxf(0,-player.position.y-20)*0.009) * (1.8 if boosting else 1.0)
	_consume_air(use_rate*delta)
	if gm_infinite_air:
		oxygen = progress.oxygen_max()
	_update_swim_camera()
	for hazard in hazards:
		if player.position.distance_to(hazard.node.position) < 2.0 and hurt_cooldown <= 0:
			_consume_air(12)
			hurt_cooldown = 2.5
			tell("小心水母！GM 无限气瓶量已免除耗气。" if gm_infinite_air else "小心水母！气瓶量减少 12。", 3)
			_play_tone(120,0.18)
	if oxygen <= 0 and not gm_infinite_air:
		finish_dive(true)

func _update_swim_camera() -> void:
	var inside_wreck: bool = explorable_wreck.contains_point(player.position)
	var forward := Vector3(-sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))
	var anchor: Vector3 = player.position+Vector3.UP*0.25
	var desired: Vector3 = player.position-forward*(3.8 if inside_wreck else 7.5)+Vector3.UP*(1.15 if inside_wreck else 1.7)
	# Sweep a volume so the near plane fits through real openings and stays off walls.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _camera_probe
	query.transform = Transform3D(Basis.IDENTITY,anchor)
	query.motion = desired-anchor
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var travel: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	var fraction: float = travel[0] if travel.size() > 0 else 1.0
	if fraction < 1.0:
		fraction = maxf(0.0,fraction-0.06/maxf(query.motion.length(),0.01))
	camera.position = anchor+query.motion*fraction
	camera.fov = 76.0 if inside_wreck else 66.0
	# When a doorway squeezes the camera against the diver, expose the view ahead.
	player.get_child(0).visible = camera.position.distance_to(player.position) >= 2.6
	camera.look_at(player.position+forward*3.0+Vector3.UP*0.6)
	_apply_underwater_lighting(maxf(0.0,-camera.position.y))
	var canyon_along: float = absf(player.position.z-Ocean.CANYON_CENTER.z)
	var canyon_across: float = absf(player.position.x-Ocean.canyon_center_x(player.position.z))
	var canyon_view: float = smoothstep(30.0,55.0,-player.position.y)*(1.0-smoothstep(44.0,64.0,canyon_across))*(1.0-smoothstep(Ocean.CANYON_HALF_LENGTH-35.0,Ocean.CANYON_HALF_LENGTH+15.0,canyon_along))
	environment.fog_density = 0.011 if inside_wreck else lerpf(0.024,0.010,canyon_view)

func _apply_underwater_lighting(depth: float, immersion: float = 1.0) -> Dictionary:
	var values: Dictionary = DepthLighting.profile(depth,camera.global_position)
	DepthLighting.apply(environment,ocean_sun,diver_light,values,immersion)
	environment.fog_light_color = values.water_color
	environment.background_color = values.water_color
	_set_water_view_depth(depth*clampf(immersion,0.0,1.0))
	return values

func _reset_shore_lighting() -> void:
	DepthLighting.reset(environment,ocean_sun,diver_light)
	_set_water_view_depth(0.0)

func _set_water_view_depth(depth: float) -> void:
	for key: String in ["water_surface_material","sunshaft_material"]:
		var material: ShaderMaterial = ocean_root.get_meta(key,null)
		if material != null:
			material.set_shader_parameter("viewer_depth",depth)

func _animate_ocean(_delta: float) -> void:
	# The restaurant hides the entire ocean; do not simulate invisible fish there.
	if not ocean_root.visible:
		return
	canyon_root.animate(clock,player.position)
	marine_life.animate(clock,player.position)
	reef_fish.animate(clock,player.position)
	reef_plants.animate(clock,player.position)
	CoralGarden.animate(clock)
	ReefPlants.animate_shared(clock)
	storm_school.animate(clock,player.position)
	explorable_wreck.get_node("WreckFishSchool").animate(clock,player.position)
	canyon_shark.animate(clock,player.position)
	var ray_sensitivity: float = 0.55 if Input.is_action_pressed("stealth") else (1.35 if Input.is_action_pressed("boost") else 1.0)
	ray_habitat.advance(_delta,player.position,state == "dive" and not entry_active,ray_sensitivity)
	for item in fish:
		if item.alive:
			item.previous_position = item.node.position
			# The dock is a local vista, not a simulation of every distant habitat.
			if state == "dock":
				item.node.visible = item.node.position.distance_squared_to(camera.position) < 140.0 * 140.0
				if not item.node.visible:
					continue
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
	_consume_air(amount)
	hurt_cooldown = 2.5
	hurt_flash = 0.45
	if poison:
		poison_timer = 6.0
	hunt_warning = "%s · 气瓶量 -%d%s" % [source,int(amount),"，中毒6秒，保持距离" if poison else "，侧游避开下一次冲刺"]
	if source == "石头鱼":
		hunt_warning = "石头鱼毒棘刺伤 · 气瓶量 -%d · 中毒6秒，请远离岩石边缘" % int(amount)
	if gm_infinite_air:
		hunt_warning = "%s · GM 无限气瓶量已免除耗气%s" % [source," · 中毒6秒" if poison else ""]
	hunt_warning_timer = 3.0
	_play_tone(120,0.12)

func _update_hunting_status(delta: float) -> void:
	hunt_warning_timer = maxf(0,hunt_warning_timer-delta)
	if poison_timer > 0:
		var elapsed: float = minf(delta,poison_timer)
		_consume_air(elapsed*1.5)
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
		var aim_point: Vector3 = item.node.to_global(item.node.get_meta("harpoon_center",Vector3.ZERO))
		var offset: Vector3 = aim_point-origin
		var along: float = offset.dot(direction)
		if player.position.distance_to(item.node.position) > SPEAR_RANGE:
			continue
		var radius: float = float(FishData.SPECIES[item.kind].radius)*item.node.scale.x
		if along > 0 and along < best_dist and (offset-direction*along).length() < radius:
			var sight_ray = PhysicsRayQueryParameters3D.create(origin, aim_point, 1, [player.get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(sight_ray).is_empty():
				continue
			var spear_ray := PhysicsRayQueryParameters3D.create(player.position,aim_point,1,[player.get_rid()])
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
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var distance: float = (player.position-origin).dot(direction)+SPEAR_RANGE
	var target: Dictionary = target_fish()
	if not target.is_empty():
		var aim_point: Vector3 = target.node.to_global(target.node.get_meta("harpoon_center",Vector3.ZERO))
		distance = (aim_point-origin).dot(direction)
	var aim: Vector3 = origin+direction*distance
	var start: Vector3 = player.position+Vector3(0.58,-0.15,-1.5).rotated(Vector3.UP,yaw)
	var obstruction := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(player.position,start,1,[player.get_rid()]))
	if not obstruction.is_empty():
		Harpoon.impact(self,obstruction.position,false)
		return
	projectiles.append(Harpoon.launch(self,start,(aim-start).normalized()))

func _update_projectiles(delta: float) -> void:
	if state != "dive" or entry_active or delta <= 0:
		return
	for index in range(projectiles.size()-1,-1,-1):
		if Harpoon.step(self,projectiles[index],delta):
			Harpoon.dispose(projectiles[index])
			projectiles.remove_at(index)
	for item in fish:
		item.previous_position = item.node.position

func _clear_projectiles() -> void:
	for shot in projectiles:
		Harpoon.dispose(shot)
	projectiles.clear()
func _hit_fish(target: Dictionary, launched_damage: int = -1) -> void:
	if state != "dive" or entry_active or not target.alive:
		return
	hit_timer = 0.18
	FishBrain.prepare(target)
	var data: Dictionary = FishData.SPECIES[target.kind]
	var damage: int = progress.spear_damage() if launched_damage < 0 else launched_damage
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
			_show_capacity_warning(data,"未能捕获")
	elif not armored:
		tell("命中 %s！剩余耐久 %d / %d" % [data.name,target.hp,data.hp],2)

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
	if kind == "chest":
		_open_chest(item)
		return
	var info: Dictionary = Loot.pickup_info(kind)
	if info.is_empty():
		return
	if kind == "oxygen":
		var restored: float = minf(35.0,maxf(0.0,progress.oxygen_max()-oxygen))
		if restored <= 0.0:
			tell("气瓶已满，可以在需要补气时再来。",3)
			return
		oxygen += restored
		_show_loot_feedback("补给已拾取",[],restored)
	else:
		if weight()+int(info.weight) > progress.capacity():
			_show_capacity_warning(info,"未能采集")
			return
		cargo.append(info)
		_show_loot_feedback("采集成功",[info],0.0)
	_pickup_feedback(kind,item.node.position)
	item.active = false
	item.node.visible = false
	_play_tone(960,0.15)

func _clear_loot_feedback() -> void:
	loot_feedback.clear()
	loot_feedback_title = ""
	loot_feedback_note = ""
	loot_feedback_timer = 0.0
	capacity_warning_timer = 0.0
	capacity_warning_name = ""
	capacity_warning_weight = 0
	capacity_warning_action = ""

func _show_capacity_warning(info: Dictionary, action: String) -> void:
	_clear_loot_feedback()
	catch_timer = 0.0
	capacity_warning_name = str(info.name)
	capacity_warning_weight = int(info.weight)
	capacity_warning_action = action
	capacity_warning_timer = 6.0
	tell("背包空间不足，先返航将收获入库。",6.0)

func _show_loot_feedback(title: String, claimed: Array, air: float, note: String = "") -> void:
	_clear_loot_feedback()
	catch_timer = 0.0
	loot_feedback_title = title
	loot_feedback_note = note
	var counts: Dictionary = {}
	for reward: Dictionary in claimed:
		var id: String = reward.id
		counts[id] = int(counts.get(id,0))+1
	for id: String in counts:
		var info: Dictionary = Loot.pickup_info(id)
		var count: int = counts[id]
		loot_feedback.append("%s ×%d  ·  %d kg  ·  价值 %d G" % [info.name,count,int(info.weight)*count,int(info.value)*count])
	if air > 0.0:
		loot_feedback.append("应急气瓶  ·  气瓶量 +%s" % String.num(air,1))
	loot_feedback_timer = 4.5

func _open_chest(item: Dictionary) -> void:
	var was_opened: bool = item.get("loot_opened",false)
	var claim: Dictionary = Loot.claim_chest(item,progress.capacity()-weight(),progress.oxygen_max()-oxygen)
	for reward: Dictionary in claim.cargo:
		cargo.append(reward)
		_pickup_feedback(reward.id,item.node.position+Vector3.UP)
	oxygen += float(claim.air)
	if float(claim.air) > 0.0:
		_pickup_feedback("oxygen",item.node.position+Vector3.UP)
	Art.set_chest_open(item.node,true)
	item.active = not claim.complete
	var contents: Node3D = item.node.get_node_or_null("Contents")
	if contents != null:
		contents.visible = not claim.complete
	var note := ""
	if not claim.complete:
		var cargo_left := false
		for reward: Dictionary in claim.remaining:
			cargo_left = cargo_left or reward.id != "oxygen"
		note = "背包空间不足，剩余物品留在箱内" if cargo_left else "未用补气留在箱内，需要时可继续领取"
	_show_loot_feedback("领取宝箱物品" if was_opened else "宝箱已打开",claim.cargo,claim.air,note)
	_play_tone(960 if claim.complete else 760,0.2)

func _pickup_feedback(kind: String, origin: Vector3) -> void:
	var prop: Node3D = Art.create_pickup(kind)
	prop.position = origin
	ocean_root.add_child(prop)
	effects.append({"node":prop,"life":0.7,"duration":0.7,"origin":origin,"collect":true})

func ocean_edge_distance() -> float:
	return minf(minf(player.position.x-Ocean.X_MIN,Ocean.X_MAX-player.position.x),minf(player.position.z-Ocean.Z_MIN,Ocean.Z_MAX-player.position.z))

func ocean_zone_name() -> String:
	var area: Dictionary = Ocean.exploration_area_for_position(player.position)
	if area.is_empty():
		return "蓝海航道"
	var nearest: String = area.name
	if area.id == "southern_spires":
		nearest += " · 杰克风暴"
	elif area.id == "amber_reef":
		nearest += " · 珊瑚花园"
	var destination: Dictionary = nearby_exploration_point()
	if not destination.is_empty() and destination.distance < 16.0:
		nearest = "%s · %s" % [area.name,destination.name]
	return nearest

func nearby_exploration_point() -> Dictionary:
	var areas: Array = Ocean.exploration_areas()
	var area: Dictionary = Ocean.exploration_area_for_position(player.position)
	if area.is_empty():
		return {}
	var best: float = INF
	var result: Dictionary = {}
	var site_index: int = areas.find(area)
	for point: Dictionary in Ocean.exploration_points(site_index):
		var distance: float = Vector2(player.position.x-point.position.x,player.position.z-point.position.z).length()
		if distance < best:
			best = distance
			result = {"name":point.name,"position":point.position,"distance":distance}
	return result
func context_hint() -> String:
	if entry_active:
		return "正在入水 · 感受海水的浮力"
	if player.position.y >= -3.5:
		return "F  呼叫接驳船 · 返航入库"
	var item: Dictionary = nearest_pickup()
	if not item.is_empty():
		if item.kind == "chest":
			return "F  领取宝箱剩余物品" if item.get("loot_opened",false) else "F  打开沉船宝箱"
		if item.kind == "oxygen":
			return "F  补充气瓶量"
		var info: Dictionary = Loot.pickup_info(item.kind)
		return "F  采集%s" % info.get("name","物品")
	var target: Dictionary = target_fish()
	if not target.is_empty():
		var data: Dictionary = FishData.SPECIES[target.kind]
		var remaining: int = maxi(0,progress.capacity()-weight())
		if int(data.weight) > remaining:
			return "%s · 空间不足：需 %d kg，剩余 %d kg" % [data.name,data.weight,remaining]
		return "%s · 耐久 %d/%d · %d kg | %s" % [data.name,target.hp,data.hp,data.weight,data.hint]
	var observed: String = marine_life.nearby_species(player.position)
	if observed.is_empty():
		observed = reef_fish.nearby_species(player.position,player.get_rid())
	if not observed.is_empty():
		return "观察 · %s" % observed
	return ""

func tell(message: String, seconds: float) -> void:
	harvest_result_visible = false
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
	start_dive(false, false)
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
	target.previous_position = target.node.position
	camera.look_at(target.node.position)
	assert(not target_fish().is_empty())
	shoot()
	for frame in range(50):
		_update_projectiles(0.02)
	assert(cargo.size() == 2)
	toggle_pause()
	assert(state == "paused")
	toggle_pause()
	assert(state == "dive")
	print("SMOKE PASS: world, collection, oxygen, aim, capture, pause")
	get_tree().quit()






# Shore management and restaurant service.
func open_restaurant() -> void:
	if rescue_result_visible or state not in ["dock","restaurant"]:
		return
	harvest_result_visible = false
	state = "restaurant"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.visible = false
	restaurant_node.visible = true
	ocean_root.visible = false
	_reset_shore_lighting()
	_rebuild_restaurant(true)
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
	_reset_shore_lighting()
	environment.background_color = Color("126879")
	camera.fov = 66
	hud.rebuild()

func _clamp_menu() -> void:
	for id in Progress.RECIPES:
		menu_plan[id] = clampi(int(menu_plan.get(id,0)),0,int(progress.inventory.get(id,0)))
		if preparation.has(id) and int(preparation[id].count) != int(menu_plan[id]):
			preparation.erase(id)

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
		if id in ["tables","expansion"]:
			var stored: int = 0
			for uid in ([1,2] if id == "tables" else [3,4]):
				if not progress.furniture_by_uid(uid).placed:
					stored += 1
			tell("赠送2套餐桌：%d套已摆放，%d套在收纳中；自由布置 → 我的家具可摆放。" % [2-stored,stored] if stored > 0 else "赠送的2套餐桌已摆到空位，现有家具位置保持不变。",8)
		elif id == "decor":
			tell("海洋软装已完成，赠送的2盆绿植与2张地毯已入收纳；到“我的家具”自主摆放。",8)
		else:
			tell("%s 已完成，店面焕然一新！" % Progress.RENOVATIONS[id].name,4)
		_play_tone(800,0.2)
	else:
		tell(progress.renovation_reason(id),4)
	hud.rebuild()

func change_menu(id: String, change: int) -> void:
	if layout_mode or state != "restaurant":
		return
	menu_plan[id] = clampi(int(menu_plan.get(id,0))+change,0,int(progress.inventory.get(id,0)))
	preparation.erase(id)
	hud.rebuild()

func change_seasoning(id: String) -> void:
	if state != "restaurant" or layout_mode or not Progress.RECIPES.has(id):
		return
	menu_seasoning[id] = (int(menu_seasoning.get(id,0))+1)%3
	preparation.erase(id)
	hud.rebuild()

func prepare_dish(id: String) -> void:
	if state != "restaurant" or layout_mode or not progress.renovation.kitchen or int(menu_plan.get(id,0)) <= 0:
		return
	if preparation.has(id):
		return
	preparation[id] = {"left":Cuisine.PREP_TIME,"count":int(menu_plan[id]),"seasoning":int(menu_seasoning.get(id,0))}
	tell("正在清理、切配与腌制，完成后本批菜品获得备料品质。",4)
	hud.rebuild()

func _update_preparation(delta: float) -> void:
	if state != "restaurant" or layout_mode:
		return
	var active := false
	for id in preparation:
		if float(preparation[id].left) > 0:
			preparation[id].left = maxf(0,float(preparation[id].left)-delta)
			if preparation[id].left <= 0:
				tell("%s 的备料已完成，开业后可争取更好的火候与评价。" % Progress.RECIPES[id].name,4)
				hud.rebuild()
		active = active or float(preparation[id].left) > 0
	restaurant_node.set_preparing(active)

func preparation_label(id: String) -> String:
	if not preparation.has(id):
		return "精细备料 · 4秒"
	var left: float = preparation[id].left
	if left <= 0:
		return "已备好 · 品质+1"
	return "%s %.1fs" % ["清理" if left > 2.7 else ("切配" if left > 1.3 else "腌制"),left]

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
	for batch in preparation.values():
		if float(batch.left) > 0:
			return "厨房正在备料，完成后即可营业"
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
	service_preparation = preparation.duplicate(true)
	preparation.clear()
	culinary_results = {"excellent":0,"matched":0,"cold":0,"bonus":0}
	orders.clear()
	service_arrived = 0
	service_spawn_time = 0.2
	summary_visible = false
	service_summary.clear()
	service_feedback.clear()
	service_reviews = {"satisfied":0,"okay":0,"lost":0}
	restaurant_node.clear_reactions()
	restaurant_node.set_customers(orders)
	tell("开门迎客！留意口味偏好，绿色火候区点击翻面，摆盘后趁热上菜。",7)
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
	orders.append({"id":order_serial,"seat":seat,"dish":dish,"state":"waiting","patience":progress.patience(),"max_patience":progress.patience(),"cook_left":0.0,"cook_total":float(Progress.RECIPES[dish].cook_time),"preference":(order_serial-1)%3,"seasoning":int(menu_seasoning.get(dish,0)),"prepped":service_preparation.has(dish) and float(service_preparation[dish].left) <= 0,"heat_result":"","plated":false,"ready_age":0.0})
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
			var before: float = order.cook_left
			order.cook_left = maxf(0,order.cook_left-delta)
			if order.cook_left <= 0:
				order.state = "ready"
				order.ready_age = maxf(0,delta-before)
				changed = true
		elif order.state == "ready":
			var was_hot: bool = float(order.get("ready_age",0)) <= Cuisine.HOT_WINDOW
			order.ready_age = float(order.get("ready_age",0))+delta
			if was_hot and order.ready_age > Cuisine.HOT_WINDOW:
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
			var bonus: int = Cuisine.bonus_percent(order)
			var earned: int = progress.record_served(order.dish,bonus)
			if earned > 0:
				culinary_results.excellent += int(Cuisine.quality(order) >= 3)
				culinary_results.matched += int(Cuisine.matches(order))
				culinary_results.cold += int(float(order.get("ready_age",0)) > Cuisine.HOT_WINDOW)
				culinary_results.bonus += int(float(Progress.RECIPES[order.dish].price)*bonus/100.0)
				_record_customer_feedback(order)
				orders.erase(order)
				tell("料理送达 · %s · +%d G" % [Cuisine.quality_label(order),earned],3)
				_play_tone(900,0.12)
			break
	restaurant_node.set_customers(orders)
	hud.rebuild()

func tend_order(id: int) -> void:
	if state != "service":
		return
	for order in orders:
		if order.id != id:
			continue
		if order.state == "cooking" and str(order.get("heat_result","")) == "":
			var fraction: float = Cuisine.heat_fraction(order)
			order.heat_result = "perfect" if fraction >= 0.4 and fraction <= 0.75 else "missed"
			tell("翻面恰到好处，火候品质+2！" if order.heat_result == "perfect" else "这次翻面偏早或偏晚，下一份留意绿色区域。",3)
		elif order.state == "ready" and not order.get("plated",false):
			order.plated = true
			tell("点缀柠檬与香草，摆盘完成。趁热送到客人桌上吧！",3)
		break
	restaurant_node.set_customers(orders)
	hud.rebuild()

func order_price(order: Dictionary) -> int:
	var base: int = int(Progress.RECIPES[order.dish].price)
	return base + (int(base/10.0) if progress.renovation.decor else 0) + int(base*Cuisine.bonus_percent(order)/100.0)

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
	service_summary = progress.end_service(orders.size(),service_reviews,culinary_results)
	summary_visible = true
	orders.clear()
	restaurant_node.set_customers(orders)
	state = "restaurant"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clamp_menu()
	tell("今日打烊，未分配的食材已退回仓库。下次出海后可再次营业。",7)
	hud.rebuild()







# Transactional furniture layout: only Save commits money and changes to progress.
func _rebuild_restaurant(reuse_room: bool = false) -> void:
	var model = layout_work if layout_mode else progress
	restaurant_node.rebuild(model.renovation,model.furniture_items(),{"floor":model.floor_style,"wall":model.wall_style},layout_mode or reuse_room)
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
	layout_pending_purchase.clear()
	layout_reason = "点选家具，或从左侧选购；保存前不会扣除真实金币。"
	layout_history.clear()
	layout_zoom = 31
	layout_pan = Vector3.ZERO
	layout_panel_visible = true
	layout_panning = false
	layout_orbiting = false
	layout_camera_yaw = LAYOUT_DEFAULT_YAW
	layout_camera_pitch = LAYOUT_DEFAULT_PITCH
	_rebuild_restaurant()
	hud.rebuild()

func save_layout() -> void:
	if not layout_mode or state != "restaurant":
		return
	_discard_pending_purchase()
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
	layout_pending_purchase.clear()
	layout_selected = -1
	layout_history.clear()
	layout_work = null
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	restaurant_node.clear_layout_preview()
	restaurant_node.set_layout_grid(false)
	restaurant_node.highlight_furniture(-1)
	_rebuild_restaurant(true)
	hud.rebuild()

func _remember_layout() -> void:
	var snapshot: Dictionary = layout_work._save_data().duplicate(true)
	snapshot["pending_purchase"] = layout_pending_purchase.duplicate(true)
	layout_history.append(snapshot)
	if layout_history.size() > 20:
		layout_history.pop_front()

func undo_layout() -> void:
	if not layout_mode or layout_history.is_empty():
		return
	var snapshot: Dictionary = layout_history.pop_back()
	layout_work._apply_save_data(snapshot)
	layout_pending_purchase = snapshot.get("pending_purchase",{}).duplicate(true)
	layout_placing = not layout_pending_purchase.is_empty()
	if layout_placing:
		layout_selected = int(layout_pending_purchase.uid)
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
	if not layout_pending_purchase.is_empty() and int(layout_pending_purchase.uid) != uid:
		_remember_layout()
		_discard_pending_purchase()
	layout_selected = uid
	layout_rotation = int(item.rotation)
	layout_placing = not item.placed
	layout_reason = "移动鼠标预览，左键放下，R 旋转。" if layout_placing else "已选中家具 · G 移动 / R 旋转 / Delete 半价回收 · 可撤销"
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
	_discard_pending_purchase()
	_remember_layout()
	var uid: int = layout_work.buy_furniture(kind,variant)
	if uid < 0:
		layout_history.pop_back()
		layout_reason = "金币不足，或该家具暂时不能购买。"
		hud.rebuild()
		return
	layout_pending_purchase = {"uid":uid,"cost":int(Layout.variant_data(kind,variant).cost)}
	select_furniture(uid)
	layout_reason = "选购待放置 · 右键 / Esc 取消不扣款；放下并保存后才购买。"

func _discard_pending_purchase() -> void:
	if layout_pending_purchase.is_empty():
		return
	var uid: int = int(layout_pending_purchase.uid)
	for index in range(layout_work.furnishings.size()):
		if int(layout_work.furnishings[index].uid) == uid:
			layout_work.furnishings.remove_at(index)
			layout_work.coins += int(layout_pending_purchase.cost)
			break
	if layout_selected == uid:
		layout_selected = -1
	layout_pending_purchase.clear()
	layout_placing = false
	restaurant_node.clear_layout_preview()

func cancel_layout_placement() -> void:
	if not layout_mode:
		return
	var was_purchase: bool = not layout_pending_purchase.is_empty()
	if was_purchase:
		_remember_layout()
		_discard_pending_purchase()
	layout_placing = false
	restaurant_node.clear_layout_preview()
	layout_reason = "已取消选购，预留金币已退回，其他修改保留。" if was_purchase else "已取消这次摆放，原位置和其他修改保留。"
	_rebuild_restaurant()
	hud.rebuild()

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
		layout_placing = true
		layout_rotation = rotation
		layout_reason = reason + " · 已旋转预览，请移动到空位后放下；右键可取消。"
		_update_layout_preview()
		hud.rebuild()
		return
	_remember_layout()
	layout_work.place_furniture(layout_selected,item.x,item.z,rotation)
	layout_rotation = rotation
	_rebuild_restaurant()
	hud.rebuild()

func store_selected_furniture() -> void:
	if not layout_mode:
		return
	if not layout_pending_purchase.is_empty():
		cancel_layout_placement()
		return
	_remember_layout()
	if not layout_work.store_furniture(layout_selected):
		layout_history.pop_back()
		return
	layout_placing = false
	layout_reason = "家具已收回收纳箱，可随时再次摆放，不需要重新购买。"
	_rebuild_restaurant()
	hud.rebuild()

func recycle_selected_furniture() -> void:
	if not layout_mode or state != "restaurant":
		return
	if not layout_pending_purchase.is_empty():
		cancel_layout_placement()
		return
	if layout_work.furniture_by_uid(layout_selected).is_empty():
		return
	_remember_layout()
	var refund: int = layout_work.recycle_furniture(layout_selected)
	if refund <= 0:
		layout_history.pop_back()
		layout_reason = "暂时不能回收；金币达到上限时请先消费。"
	else:
		layout_selected = -1
		layout_placing = false
		layout_reason = "已回收家具，退还 %d G（售价50%%，向上取整）；保存后生效，可撤销。" % refund
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
	_discard_pending_purchase()
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
	layout_pending_purchase.clear()
	layout_placing = false
	layout_reason = "已摆放在草稿中，点击保存布局生效。"
	_rebuild_restaurant()
	hud.rebuild()
	return true

func _layout_plane_point(screen_position: Vector2) -> Variant:
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.001:
		return null
	var distance: float = (restaurant_node.global_position.y+0.08-origin.y)/direction.y
	if distance < 0:
		return null
	return origin + direction*distance

func _layout_point(screen_position: Vector2) -> Variant:
	var point: Variant = _layout_plane_point(screen_position)
	if point == null:
		return null
	var local: Vector3 = restaurant_node.to_local(point)
	var snapped: Vector2 = Layout.snap_position(local.x,local.z)
	return Vector3(snapped.x,0.08,snapped.y)

func _update_layout_preview() -> void:
	if not layout_mode:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	if not layout_view_rect().has_point(mouse) or not layout_placing:
		restaurant_node.hide_layout_preview()
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
	var view_size := get_viewport().get_visible_rect().size
	var left: float = LAYOUT_AREA.position.x if layout_panel_visible else 8.0
	return Rect2(left,96,view_size.x-left-8,view_size.y-192)

func toggle_layout_panel() -> void:
	if not layout_mode:
		return
	layout_panel_visible = not layout_panel_visible
	hud.rebuild()

func reset_layout_camera() -> void:
	layout_zoom = 31
	layout_pan = Vector3.ZERO
	layout_panning = false
	layout_orbiting = false
	layout_camera_yaw = LAYOUT_DEFAULT_YAW
	layout_camera_pitch = LAYOUT_DEFAULT_PITCH
	if layout_mode:
		update_layout_camera()

func update_layout_camera() -> void:
	var right := Vector3(cos(layout_camera_yaw),0,-sin(layout_camera_yaw))
	var focus := restaurant_node.position + Vector3(0,0,3) + layout_pan
	if layout_panel_visible:
		focus -= right * layout_zoom * 0.112
	var offset := Vector3(sin(layout_camera_yaw)*cos(layout_camera_pitch),sin(layout_camera_pitch),cos(layout_camera_yaw)*cos(layout_camera_pitch)) * 31.064449134
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = layout_zoom
	camera.position = focus + offset
	camera.look_at(focus)

func _layout_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if not event.pressed:
			layout_panning = false
			layout_orbiting = false
		elif layout_view_rect().has_point(event.position):
			layout_orbiting = event.alt_pressed
			layout_panning = not layout_orbiting
		return
	if event is InputEventMouseMotion and layout_orbiting:
		layout_camera_yaw = wrapf(layout_camera_yaw-event.relative.x*0.006,-PI,PI)
		layout_camera_pitch = clampf(layout_camera_pitch+event.relative.y*0.006,deg_to_rad(20),deg_to_rad(85))
		update_layout_camera()
		_update_layout_preview()
		return
	if event is InputEventMouseMotion and layout_panning:
		# Keep the grabbed floor point under the cursor, without furniture grid snapping.
		var previous: Variant = _layout_plane_point(event.position-event.relative)
		var current: Variant = _layout_plane_point(event.position)
		if previous == null or current == null:
			return
		layout_pan += previous-current
		layout_pan.x = clampf(layout_pan.x,-16,16)
		layout_pan.z = clampf(layout_pan.z,-14,14)
		update_layout_camera()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if layout_placing:
					cancel_layout_placement()
				else:
					cancel_layout()
			KEY_TAB: toggle_layout_panel()
			KEY_F: reset_layout_camera()
			KEY_R: rotate_layout()
			KEY_G: begin_move_furniture()
			KEY_DELETE: recycle_selected_furniture()
			KEY_Z:
				if event.ctrl_pressed:
					undo_layout()
	if event is InputEventMouseButton and event.pressed and layout_view_rect().has_point(event.position):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			layout_zoom = maxf(12,layout_zoom-1.5)
			update_layout_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			layout_zoom = minf(52,layout_zoom+1.5)
			update_layout_camera()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_layout_placement()
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

