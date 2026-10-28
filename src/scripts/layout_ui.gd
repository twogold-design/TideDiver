extends "res://scripts/responsive_ui.gd"
const Rules = preload("res://scripts/layout_rules.gd")
const CREAM = Color("f6ead4")
const MINT = Color("a9ead2")
const GOLD = Color("efbf75")
const MUTED = Color("9cb5b6")
var game: Node
var font: Font
var controls: Array[Control] = []
var category: String = "rug"
var page: String = "shop"
var button_anchor := TOP_LEFT
var _preview_views: Dictionary = {}
var _last_reason: String = ""
const PREVIEW_CACHE_LIMIT := 8

func _ready() -> void:
	super._ready()
	font = preload("res://assets/fonts/ui_font.tres")

func _process(_delta: float) -> void:
	if visible and _last_reason != game.layout_reason:
		_last_reason = game.layout_reason
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
	place_control(b, rect, button_anchor)
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
	native_button_label(b,font,15,Color("14343a") if primary else CREAM,Color("14343a") if primary else Color.WHITE,Color("778e94"))
	controls.append(b)

func _preview(rect: Rect2, kind: String, variant: String) -> void:
	var key: String = kind+"/"+variant
	if _preview_views.has(key):
		var cached: TextureRect = _preview_views[key]
		_preview_views.erase(key)
		_preview_views[key] = cached
		place_control(cached,rect,TOP_LEFT)
		cached.visible = true
		return
	if _preview_views.size() >= PREVIEW_CACHE_LIMIT:
		var oldest: String = _preview_views.keys()[0]
		var old_view: TextureRect = _preview_views[oldest]
		remove_child(old_view)
		old_view.queue_free()
		_preview_views.erase(oldest)
	var display = TextureRect.new()
	place_control(display, rect, TOP_LEFT)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# The shop views are static. Bake them from the full models instead of
	# allocating four 3D worlds and compiling their shaders on first entry.
	display.texture = load("res://assets/furniture_previews/%s_%s.png" % [kind,variant])
	add_child(display)
	_preview_views[key] = display

func set_page(value: String) -> void:
	page = value
	rebuild()

func set_category(value: String) -> void:
	category = value
	rebuild()

func shop_variants() -> Array:
	var variants: Array = Rules.variant_ids(category)
	variants.sort_custom(func(a, b): return int(Rules.variant_data(category,a).cost) < int(Rules.variant_data(category,b).cost))
	return variants

func rebuild() -> void:
	for display: TextureRect in _preview_views.values():
		display.visible = false
	for c in controls:
		remove_child(c)
		c.queue_free()
	controls.clear()
	visible = game.layout_mode
	if not visible:
		return
	button_anchor = TOP_CENTER
	_button("展开家具栏  Tab" if not game.layout_panel_visible else "收起家具栏  Tab",Rect2(368,24,162,45),game.toggle_layout_panel)
	_button("视角归中  F",Rect2(542,24,128,45),game.reset_layout_camera)
	button_anchor = TOP_RIGHT
	_button("保存布局",Rect2(1050,24,170,45),game.save_layout,true)
	_button("取消修改",Rect2(1234,24,178,45),game.cancel_layout)
	button_anchor = BOTTOM_LEFT
	_button("撤销 Ctrl+Z",Rect2(20,839,142,41),game.undo_layout,false,game.layout_history.is_empty())
	_button("还原默认摆位",Rect2(174,839,142,41),game.reset_layout_draft)
	var selected: Dictionary = game.layout_work.furniture_by_uid(game.layout_selected)
	var empty: bool = selected.is_empty()
	button_anchor = BOTTOM_RIGHT
	_button("仅收纳",Rect2(725,839,98,41),game.store_selected_furniture,false,empty or not selected.get("placed",false))
	_button("移动  G",Rect2(835,839,130,41),game.begin_move_furniture,false,empty)
	_button("旋转  R",Rect2(978,839,130,41),game.rotate_layout,false,empty)
	_button("切换配色",Rect2(1121,839,130,41),game.color_selected_furniture,false,empty)
	var pending: bool = not game.layout_pending_purchase.is_empty()
	var refund: int = game.layout_work.furniture_refund(game.layout_selected)
	_button("取消选购" if pending else ("回收 +%d G" % refund if not empty else "半价回收"),Rect2(1264,839,148,41),game.recycle_selected_furniture,false,empty)
	if game.layout_panel_visible:
		button_anchor = TOP_LEFT
		_button("家具商店",Rect2(20,110,142,40),func(): set_page("shop"),page=="shop")
		_button("我的家具",Rect2(174,110,142,40),func(): set_page("owned"),page=="owned")
		if page == "shop":
			var index: int = 0
			for kind in Rules.CATALOG:
				var last_single: bool = index == Rules.CATALOG.size()-1 and index%4 == 0
				_button(Rules.CATALOG[kind].name,Rect2(20+(index%4)*75,158+int(index/4)*38,296 if last_single else 71,34),func(): set_category(kind),category==kind)
				index += 1
			index = 0
			for variant in shop_variants():
				var product: Dictionary = Rules.variant_data(category,variant)
				var y: float = 278 + index*128
				_preview(Rect2(26,y+8,108,116),category,variant)
				var available: int = game.layout_work.coins + int(game.layout_pending_purchase.get("cost",0))
				_button("%d G · 选购" % int(product.cost),Rect2(153,y+94,150,28),func(): game.buy_layout_furniture(category,variant),false,available < int(product.cost))
				index += 1
		else:
			var owned = ItemList.new()
			owned.name = "OwnedFurnitureList"
			place_control(owned, Rect2(20,190,296,405), TOP_LEFT)
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
			# Rebuilding removes this list; let ItemList finish handling the click first.
			owned.item_selected.connect(func(index: int): game.call_deferred("select_furniture",int(owned.get_item_metadata(index))))
			add_child(owned)
			native_item_list(owned,16,14)
			controls.append(owned)
			var floors = ["暖木地板","浅砂地板","薄荷木板"]
			var walls = ["奶油墙面","薄荷墙面","珊瑚墙面"]
			_button(floors[game.layout_work.floor_style] + "  →",Rect2(20,652,296,44),func(): game.set_layout_style("floor",(game.layout_work.floor_style+1)%3))
			_button(walls[game.layout_work.wall_style] + "  →",Rect2(20,707,296,44),func(): game.set_layout_style("wall",(game.layout_work.wall_style+1)%3))
	queue_redraw()

func _text(pos: Vector2, value: String, size: int = 18, color: Color = CREAM) -> void:
	native_text(font,pos,value,size,color)

func _panel(rect: Rect2, color: Color = Color(0.025,0.12,0.15,0.97)) -> void:
	draw_style_box(_style(color),rect)

func _draw() -> void:
	if not visible or font == null:
		return
	region(TOP_LEFT)
	screen_bar(88,Color("09232d"))
	_text(Vector2(24,40),"一间有你风格的海岸小店",25)
	_text(Vector2(26,68),"TIDE TABLE  /  家具与空间",13,MINT)
	region(TOP_CENTER)
	_text(Vector2(702,39),"可用 %d G" % game.layout_work.coins,22,GOLD)
	var cost: int = game.progress.coins-game.layout_work.coins
	_text(Vector2(702,66),("本次支出 %d G" % cost if cost >= 0 else "本次返还 %d G" % -cost)+" · 保存后生效",14,MUTED)
	if game.layout_panel_visible:
		region(TOP_LEFT)
		_panel(Rect2(8,96,320,704))
		if page == "shop":
			var i: int = 0
			var tiers = ["日常精选","质感升级","匠心收藏"]
			var notes = {
				"rug":[["椰纤粗织","迎宾字样"],["双色海蓝条纹","户外薄织"],["人字编织","绳纹缝边"]],
				"table":[["旧木拼板","折叠木椅"],["浅蓝木圆桌","藤编椅背"],["柚木桌面","条纹软座"]],
				"plant":[["素陶花盆","海岸绿叶"],["板条木箱","组合花草"],["大陶缸","棕榈羽叶"]],
				"lamp":[["铁艺护笼","暖光灯芯"],["木杆挂钩","悬挂渔灯"],["弧架链环","铜框暖灯"]],
				"shelf":[["开放木架","日常碗碟"],["百叶柜门","调料餐具"],["碎冰鲜鱼","今日鱼价"]],
				"bench":[["风化漂木","渔港长凳"],["浅蓝木靠背","条纹坐垫"],["藤编沙发","配套茶几"]],
				"parasol":[["浅蓝帆布","木质伞杆"],["双色海蓝伞面","加固伞骨"],["木架卷帘","暖色灯串"]],
				"coastal":[["手绘鲜鱼","黑板菜单"],["渔获木箱","浮球缆绳"],["木船造型","鲜鱼陈列"]]}
			for variant in shop_variants():
				var y: float = 278+i*128
				var product: Dictionary = Rules.variant_data(category,variant)
				var tier_index: int = ["basic","comfort","premium"].find(variant)
				var details: Array = product.notes if product.has("notes") else notes[category][tier_index]
				_panel(Rect2(20,y,296,126),Color("17363e"))
				_text(Vector2(153,y+24),product.name,16)
				_text(Vector2(153,y+44),"三款配色" if variant == "summer" or category == "soft" else tiers[tier_index],12,GOLD)
				_text(Vector2(153,y+64),details[0],13,MUTED)
				_text(Vector2(153,y+83),details[1],13,MUTED)
				i += 1
		else:
			_text(Vector2(22,177),"点选收纳家具即可重新摆放",14,MUTED)
			_text(Vector2(22,625),"房间风格 / 免费切换",17,MINT)
			_text(Vector2(22,779),"回收退50% · 仅收纳则保留家具",13,MUTED)
	region(BOTTOM_LEFT)
	screen_bar(96,Color("09232d"),true)
	var selected: Dictionary = game.layout_work.furniture_by_uid(game.layout_selected)
	var hint: String = game.layout_reason
	if game.layout_placing and hint.is_empty():
		hint = "绿色可放置 · 左键确认 · 右键 / Esc 取消选购不扣款" if not game.layout_pending_purchase.is_empty() else "绿色可放置 · 左键确认 · 右键 / Esc 取消摆放"
	_text(Vector2(20,827),hint,15,GOLD)
	region(BOTTOM_CENTER)
	_text(Vector2(340,857),"点选家具开始布置" if selected.is_empty() else Rules.item_name(selected),18,MINT)
	_text(Vector2(340,883),"中键平移 · Alt+中键旋转 · 滚轮缩放",13,MUTED)
	region(BOTTOM_RIGHT)
	_text(Vector2(1100,784),"营业桌位 %d / %d" % [game.layout_work.seats(),4 if game.layout_work.renovation.expansion else 2],16,Color("183c41"))

