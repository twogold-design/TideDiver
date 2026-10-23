extends Node2D
const Rules = preload("res://scripts/layout_rules.gd")
const Furniture = preload("res://scripts/furniture_art.gd")
const CREAM = Color("f6ead4")
const MINT = Color("a9ead2")
const GOLD = Color("efbf75")
const MUTED = Color("9cb5b6")
var game: Node
var font: SystemFont
var controls: Array[Control] = []
var category: String = "rug"
var page: String = "shop"

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _style(color: Color, border: Color = Color(0.7,0.85,0.8,0.15)) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(9)
	s.set_border_width_all(1)
	s.border_color = border
	return s

func _button(label: String, rect: Rect2, action: Callable, primary: bool = false, disabled: bool = false) -> void:
	var b = Button.new()
	b.text = label
	b.position = rect.position
	b.size = rect.size
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font",font)
	b.add_theme_font_size_override("font_size",15)
	b.add_theme_color_override("font_color",Color("14343a") if primary else CREAM)
	b.add_theme_color_override("font_hover_color",Color("14343a") if primary else Color.WHITE)
	b.add_theme_color_override("font_disabled_color",Color("778e94"))
	b.add_theme_stylebox_override("normal",_style(GOLD if primary else Color("254952")))
	b.add_theme_stylebox_override("hover",_style(Color("ffe2ae") if primary else Color("3a636b"),MINT))
	b.add_theme_stylebox_override("pressed",_style(Color("699d94")))
	b.add_theme_stylebox_override("disabled",_style(Color("1d353d")))
	b.pressed.connect(action)
	add_child(b)
	controls.append(b)

func _preview(rect: Rect2, kind: String, variant: String) -> void:
	var display = TextureRect.new()
	display.position = rect.position
	display.size = rect.size
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var viewport = SubViewport.new()
	viewport.size = Vector2i(232,248)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.msaa_3d = Viewport.MSAA_2X
	display.add_child(viewport)
	var scene = Node3D.new()
	viewport.add_child(scene)
	var furniture: Node3D = Furniture.build({"kind":kind,"variant":variant,"uid":-1,"color":0})
	scene.add_child(furniture)
	var world = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c0d5dc")
	world.environment.ambient_light_energy = 0.65
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(world)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42,-28,0)
	light.light_energy = 1.1
	scene.add_child(light)
	var view = Camera3D.new()
	view.projection = Camera3D.PROJECTION_ORTHOGONAL
	view.size = 4.4 if kind in ["table","rug"] else 2.8
	view.position = Vector3(4,5,6) if kind == "rug" else Vector3(4,3,6)
	scene.add_child(view)
	view.look_at_from_position(view.position,Vector3(0,0.15 if kind == "rug" else 0.85,0))
	view.current = true
	display.texture = viewport.get_texture()
	add_child(display)
	controls.append(display)

func set_page(value: String) -> void:
	page = value
	rebuild()

func set_category(value: String) -> void:
	category = value
	rebuild()

func rebuild() -> void:
	for c in controls:
		remove_child(c)
		c.queue_free()
	controls.clear()
	visible = game.layout_mode
	if not visible:
		return
	_button("展开家具栏  Tab" if not game.layout_panel_visible else "收起家具栏  Tab",Rect2(368,24,162,45),game.toggle_layout_panel)
	_button("视角归中  F",Rect2(542,24,128,45),game.reset_layout_camera)
	_button("保存布局",Rect2(1050,24,170,45),game.save_layout,true)
	_button("取消修改",Rect2(1234,24,178,45),game.cancel_layout)
	_button("撤销 Ctrl+Z",Rect2(20,839,142,41),game.undo_layout,false,game.layout_history.is_empty())
	_button("还原默认摆位",Rect2(174,839,142,41),game.reset_layout_draft)
	var selected: Dictionary = game.layout_work.furniture_by_uid(game.layout_selected)
	var empty: bool = selected.is_empty()
	_button("移动  G",Rect2(835,839,130,41),game.begin_move_furniture,false,empty)
	_button("旋转  R",Rect2(978,839,130,41),game.rotate_layout,false,empty)
	_button("切换配色",Rect2(1121,839,130,41),game.color_selected_furniture,false,empty)
	_button("收回家具",Rect2(1264,839,148,41),game.store_selected_furniture,false,empty or not selected.get("placed",false))
	if game.layout_panel_visible:
		_button("家具商店",Rect2(20,110,142,40),func(): set_page("shop"),page=="shop")
		_button("我的家具",Rect2(174,110,142,40),func(): set_page("owned"),page=="owned")
		if page == "shop":
			var index: int = 0
			for kind in Rules.CATALOG:
				_button(Rules.CATALOG[kind].name,Rect2(20+index*60,163,56,35),func(): set_category(kind),category==kind)
				index += 1
			index = 0
			for variant in Rules.variant_ids(category):
				var product: Dictionary = Rules.variant_data(category,variant)
				var y: float = 212 + index*176
				_preview(Rect2(26,y+19,120,128),category,variant)
				var available: int = game.layout_work.coins + int(game.layout_pending_purchase.get("cost",0))
				_button("%d G · 选购" % int(product.cost),Rect2(153,y+112,150,38),func(): game.buy_layout_furniture(category,variant),false,available < int(product.cost))
				index += 1
		else:
			var owned = ItemList.new()
			owned.name = "OwnedFurnitureList"
			owned.position = Vector2(20,190)
			owned.size = Vector2(296,405)
			owned.add_theme_font_override("font",font)
			owned.add_theme_font_size_override("font_size",16)
			owned.add_theme_color_override("font_color",CREAM)
			owned.add_theme_color_override("font_selected_color",Color("16343a"))
			owned.add_theme_stylebox_override("panel",_style(Color("102b34")))
			owned.add_theme_stylebox_override("selected",_style(MINT))
			owned.add_theme_stylebox_override("selected_focus",_style(MINT))
			owned.add_theme_constant_override("v_separation",14)
			owned.focus_mode = Control.FOCUS_NONE
			var i: int = 0
			for item in game.layout_work.furniture_items():
				var status: String = "待放置" if int(game.layout_pending_purchase.get("uid",-1)) == int(item.uid) else ("已摆" if item.placed else "收纳")
				if game.Progress.GIFT_FURNITURE.has(int(item.uid)):
					status += " · 赠品"
				owned.add_item("%s · %s" % [status,Rules.item_name(item)])
				owned.set_item_metadata(i,int(item.uid))
				if int(item.uid) == game.layout_selected:
					owned.select(i)
				i += 1
			owned.item_selected.connect(func(index: int): game.select_furniture(int(owned.get_item_metadata(index))))
			add_child(owned)
			controls.append(owned)
			var floors = ["暖木地板","浅砂地板","薄荷木板"]
			var walls = ["奶油墙面","薄荷墙面","珊瑚墙面"]
			_button(floors[game.layout_work.floor_style] + "  →",Rect2(20,652,296,44),func(): game.set_layout_style("floor",(game.layout_work.floor_style+1)%3))
			_button(walls[game.layout_work.wall_style] + "  →",Rect2(20,707,296,44),func(): game.set_layout_style("wall",(game.layout_work.wall_style+1)%3))
	queue_redraw()

func _text(pos: Vector2, value: String, size: int = 18, color: Color = CREAM) -> void:
	draw_string(font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _panel(rect: Rect2, color: Color = Color(0.025,0.12,0.15,0.97)) -> void:
	draw_style_box(_style(color),rect)

func _draw() -> void:
	if not visible or font == null:
		return
	draw_rect(Rect2(0,0,1440,88),Color("09232d"))
	_text(Vector2(24,40),"一间有你风格的海岸小店",25)
	_text(Vector2(26,68),"TIDE TABLE  /  家具与空间",13,MINT)
	_text(Vector2(702,39),"可用 %d G" % game.layout_work.coins,22,GOLD)
	_text(Vector2(702,66),"本次新购 %d G · 保存才扣款" % (game.progress.coins-game.layout_work.coins),14,MUTED)
	if game.layout_panel_visible:
		_panel(Rect2(8,96,320,704))
		if page == "shop":
			var i: int = 0
			var tiers = ["日常精选","质感升级","匠心收藏"]
			var notes = {
				"rug":[["平织纹理","轻薄包边"],["厚绒羊毛","柔软绒面"],["几何纹样","编结流苏"]],
				"table":[["原木圆面","轻巧木椅"],["橡木桌面","布艺软座"],["石纹桌面","精致桌脚"]],
				"plant":[["素陶花盆","清新绿叶"],["亮釉陶盆","大叶龟背竹"],["金属花器","层次盆景"]],
				"lamp":[["布艺灯罩","柔和暖光"],["黄铜灯杆","弧形轮廓"],["彩色玻璃","复古光影"]],
				"shelf":[["开放松木","日常收藏"],["橡木框架","玻璃柜门"],["深色胡桃木","精致陈列"]]}
			for variant in Rules.variant_ids(category):
				var y: float = 212+i*176
				_panel(Rect2(20,y,296,164),Color("17363e"))
				_text(Vector2(153,y+29),Rules.variant_data(category,variant).name,16)
				_text(Vector2(153,y+53),tiers[i],12,GOLD)
				_text(Vector2(153,y+76),notes[category][i][0],13,MUTED)
				_text(Vector2(153,y+96),notes[category][i][1],13,MUTED)
				i += 1
			_text(Vector2(24,772),"每款均为独立造型 · 保存后拥有",13,MUTED)
		else:
			_text(Vector2(22,177),"点选收纳家具即可重新摆放",14,MUTED)
			_text(Vector2(22,625),"房间风格 / 免费切换",17,MINT)
			_text(Vector2(22,779),"收纳保留家具，随时重新摆放",13,MUTED)
	draw_rect(Rect2(0,804,1440,96),Color("09232d"))
	var selected: Dictionary = game.layout_work.furniture_by_uid(game.layout_selected)
	var hint: String = game.layout_reason
	if game.layout_placing and hint.is_empty():
		hint = "绿色可放置 · 左键确认 · 右键 / Esc 取消选购不扣款" if not game.layout_pending_purchase.is_empty() else "绿色可放置 · 左键确认 · 右键 / Esc 取消摆放"
	_text(Vector2(20,827),hint,15,GOLD)
	_text(Vector2(340,857),"点选家具开始布置" if selected.is_empty() else Rules.item_name(selected)+"  /  %d°" % (game.layout_rotation*90),18,MINT)
	_text(Vector2(340,883),"中键拖移 · 滚轮缩放 · F 归中 · Tab 展开 / 收起",13,MUTED)
	_text(Vector2(1100,784),"营业桌位 %d / %d" % [game.layout_work.seats(),4 if game.layout_work.renovation.expansion else 2],16,Color("183c41"))

