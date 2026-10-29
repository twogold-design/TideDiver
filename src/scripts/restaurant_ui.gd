extends "res://scripts/responsive_ui.gd"
const LayoutUI = preload("res://scripts/layout_ui.gd")
var layout_ui: Node2D

const P = preload("res://scripts/progression.gd")
const CREAM = Color("f6ead4")
const MINT = Color("a9ead2")
const GOLD = Color("efbf75")
const MUTED = Color("9cb5b6")
var game: Node
var font: Font
var latin: Font
var buttons: Array[Button] = []
const WAREHOUSE_PAGE_SIZE := 5
var warehouse_page: int = 0
var button_anchor := CENTER

func _warehouse_page_count() -> int:
	return maxi(1, ceili(float(P.GOODS.size()) / WAREHOUSE_PAGE_SIZE))

func _warehouse_ids() -> Array:
	warehouse_page = clampi(warehouse_page, 0, _warehouse_page_count() - 1)
	var first: int = warehouse_page * WAREHOUSE_PAGE_SIZE
	return P.GOODS.keys().slice(first, first + WAREHOUSE_PAGE_SIZE)

func _change_warehouse_page(delta: int) -> void:
	warehouse_page = clampi(warehouse_page + delta, 0, _warehouse_page_count() - 1)
	rebuild()

func _ready() -> void:
	super._ready()
	font = preload("res://assets/fonts/ui_font.tres")
	latin = preload("res://assets/fonts/ui_font.tres")
	layout_ui = LayoutUI.new()
	layout_ui.game = game
	add_child(layout_ui)

func _process(_delta: float) -> void:
	if visible and not game.layout_mode:
		queue_redraw()

func _style(color: Color, border: Color = Color(0.7,0.85,0.8,0.15)) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = border
	return s

func _button(text: String, rect: Rect2, action: Callable, primary: bool = false, disabled: bool = false, tip: String = "") -> void:
	var open_service: bool = text == "开门营业   →"
	var main_action: bool = text == "自由布置" or text == "开门营业   →"
	var service_action: bool = game.state in ["service", "service_paused"]
	var label_size: int = 18 if main_action or service_action else 16
	var disabled_ink := Color("9cb5b6") if main_action else Color("778e94")
	var normal_ink: Color = Color("e5f1ed") if open_service else (Color("14343a") if primary else CREAM)
	var hover_ink: Color = Color("e5f1ed") if open_service else (Color("14343a") if primary else Color.WHITE)
	var b = Button.new()
	b.text = text
	place_control(b, rect, button_anchor)
	b.disabled = disabled
	b.tooltip_text = tip
	if not tip.is_empty():
		var tooltip_theme := Theme.new()
		tooltip_theme.default_font = font
		tooltip_theme.set_font("font","TooltipLabel",font)
		tooltip_theme.set_font_size("font_size","TooltipLabel",16)
		b.theme = tooltip_theme
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font",font)
	b.add_theme_font_size_override("font_size",label_size)
	b.add_theme_color_override("font_color",normal_ink)
	b.add_theme_color_override("font_hover_color",hover_ink)
	b.add_theme_color_override("font_disabled_color",disabled_ink)
	b.add_theme_stylebox_override("normal",_style(GOLD if primary else Color("254952")))
	b.add_theme_stylebox_override("hover",_style(Color("ffe2ae") if primary else Color("3a636b"),MINT))
	b.add_theme_stylebox_override("pressed",_style(Color("699d94")))
	b.add_theme_stylebox_override("disabled",_style(Color("1d353d")))
	if open_service:
		var fills: Dictionary = {"normal":Color("197549"),"hover":Color("238b57"),"pressed":Color("125a37"),"disabled":Color("244653")}
		for state: String in fills:
			var style: StyleBoxFlat = _style(fills[state],Color("5b7d88") if state == "disabled" else Color("a4e5ae"))
			style.set_border_width_all(2)
			style.shadow_color = Color(0.02,0.10,0.14,0.30)
			style.shadow_size = 4
			style.shadow_offset = Vector2(0,3)
			b.add_theme_stylebox_override(state,style)
	b.pressed.connect(action)
	add_child(b)
	native_button_label(b,font,label_size,normal_ink,hover_ink,disabled_ink,16 if main_action or service_action else 1)
	buttons.append(b)

func rebuild() -> void:
	# A mode change must clear retained CanvasItem draw commands even when the
	# layout screen stops this panel's continuous redraws.
	queue_redraw()
	button_anchor = CENTER
	for b in buttons:
		remove_child(b)
		b.queue_free()
	buttons.clear()
	visible = game.state in ["restaurant","service","service_paused"]
	if is_instance_valid(layout_ui):
		layout_ui.rebuild()
	if game.layout_mode:
		return
	if not visible:
		return
	if game.state == "service_paused":
		_button("继续营业",Rect2(545,412,350,56),game.toggle_pause,true)
		_button("提前打烊并结算",Rect2(545,484,350,56),game.finish_service)
		return
	if game.state == "restaurant" and game.summary_visible:
		_button("收好账单 · 继续整备",Rect2(540,611,360,54),func(): game.summary_visible = false; rebuild(),true)
		return
	if game.state == "restaurant":
		var menu_locked: bool = not (game.progress.renovation.clean and game.progress.renovation.kitchen and game.progress.renovation.tables)
		if menu_locked and game.restaurant_tab == "menu":
			game.restaurant_tab = "renovation"
		button_anchor = TOP_LEFT
		_button("← 返回码头",Rect2(32,30,150,43),game.return_to_dock)
		button_anchor = CENTER_RIGHT
		_button("店面装修",Rect2(1050,110,166,42),func(): game.restaurant_tab = "renovation"; rebuild(),game.restaurant_tab == "renovation")
		_button("备菜菜单",Rect2(1226,110,180,42),func(): game.restaurant_tab = "menu"; rebuild(),game.restaurant_tab == "menu",menu_locked,"请先装修店面" if menu_locked else "")
		button_anchor = CENTER_LEFT
		var i: int = 0
		for id in _warehouse_ids():
			var amount: int = int(game.progress.inventory.get(id,0))
			var y: float = 221 + i*82
			_button("卖 1 件",Rect2(54,y,110,30),func(): game.sell_goods(id,1),false,amount <= 0)
			_button("全卖",Rect2(174,y,110,30),func(): game.sell_goods(id,amount),false,amount <= 0)
			i += 1
		_button("上一页",Rect2(54,625,78,32),func(): _change_warehouse_page(-1),false,warehouse_page == 0)
		_button("下一页",Rect2(206,625,78,32),func(): _change_warehouse_page(1),false,warehouse_page >= _warehouse_page_count() - 1)
		_button("仅出售珍珠与宝藏",Rect2(54,701,230,44),game.sell_valuables,false,int(game.progress.inventory.get("pearl",0))+int(game.progress.inventory.get("chest",0)) == 0)
		button_anchor = CENTER_RIGHT
		if game.restaurant_tab == "renovation":
			i = 0
			for id in P.RENOVATIONS:
				var item: Dictionary = P.RENOVATIONS[id]
				var owned: bool = bool(game.progress.renovation.get(id,false))
				_button("已完成" if owned else "%d G · 施工" % item.cost,Rect2(1241,182+i*94,140,35),func(): game.renovate_shop(id),false,not game.progress.renovation_reason(id).is_empty())
				i += 1
		else:
			i = 0
			for id in P.RECIPES:
				var y: float = 268+i*140
				_button("−",Rect2(1080,y,65,36),func(): game.change_menu(id,-1),false,int(game.menu_plan.get(id,0)) <= 0)
				_button("+",Rect2(1300,y,65,36),func(): game.change_menu(id,1),true,int(game.menu_plan.get(id,0)) >= int(game.progress.inventory.get(id,0)))
				_button("口味 · "+game.Cuisine.SEASONINGS[int(game.menu_seasoning.get(id,0))],Rect2(1080,y+44,136,31),func(): game.change_seasoning(id))
				_button("备料中" if game.preparation.has(id) and game.preparation[id].left > 0 else ("备料完成" if game.preparation.has(id) else "精细备料"),Rect2(1224,y+44,150,31),func(): game.prepare_dish(id),false,game.preparation.has(id) or int(game.menu_plan.get(id,0)) <= 0 or not game.progress.renovation.kitchen)
				i += 1
		button_anchor = BOTTOM_CENTER
		_button("自由布置",Rect2(357,726,173,58),game.enter_layout,false,not game.progress.renovation.clean)
		var reason: String = game.service_block_reason()
		_button("开门营业   →",Rect2(545,726,350,58),game.start_service,true,not reason.is_empty())
		if not game.service_summary.is_empty():
			_button("查看上次账单",Rect2(558,789,324,33),func(): game.summary_visible = true; rebuild())
	else:
		button_anchor = TOP_RIGHT
		_button("提前打烊",Rect2(1238,31,168,42),game.finish_service)
		button_anchor = TOP_CENTER
		_button("全店视角" if game.service_close_view else "近看人物",Rect2(750,31,170,42),func(): game.service_close_view = not game.service_close_view; rebuild())
		button_anchor = BOTTOM_CENTER
		for order in game.orders:
			var x: float = 32 + order.seat*352
			var label: String = "开始制作"
			if order.state == "cooking":
				label = "料理制作中…"
			elif order.state == "ready":
				label = "上菜  +%d G" % game.order_price(order)
			var order_id: int = order.id
			if order.state == "ready":
				_button("已摆盘" if order.get("plated",false) else "精致摆盘",Rect2(x+18,747,122,40),func(): game.tend_order(order_id),false,order.get("plated",false))
				_button(label,Rect2(x+148,747,162,40),func(): game.serve_order(order_id),true)
			elif order.state == "cooking":
				_button("已掌勺" if order.get("heat_result","") != "" else "绿色区点击 · 翻面",Rect2(x+18,747,292,40),func(): game.tend_order(order_id),true,order.get("heat_result","") != "")
			else:
				_button(label,Rect2(x+18,747,292,40),func(): game.cook_order(order_id),false,order.state == "cooking")
	queue_redraw()

func _text(pos: Vector2, text: String, size: int = 18, color: Color = CREAM, english: bool = false) -> void:
	native_text(latin if english else font,pos,text,size,color,false,14 if game.state in ["service", "service_paused"] else 1)

func _center(pos: Vector2, text: String, size: int = 18, color: Color = CREAM) -> void:
	native_text(font,pos,text,size,color,true,14 if game.state in ["service", "service_paused"] else 1)

func _service_feedback_lines(value: String) -> Array[String]:
	# Fit full customer comments to the card using the actual rendered font size.
	var pixels: int = NativeText.font_size_for(self,16,14) if OS.has_feature("web") else 16
	var width: float = 282.0 * NativeText.transform_for(self).get_scale().x if OS.has_feature("web") else 282.0
	var lines: Array[String] = []
	var line := ""
	for character in value:
		if not line.is_empty() and font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x > width:
			lines.append(line)
			line = ""
		line += character
	lines.append(line)
	return lines

func _panel(rect: Rect2, color: Color = Color(0.025,0.12,0.15,0.95)) -> void:
	draw_style_box(_style(color),rect)

func _draw() -> void:
	if not visible or font == null or game.layout_mode:
		return
	region(TOP_LEFT)
	screen_bar(94,Color(0.025,0.10,0.13,0.96))
	_text(Vector2(207,52),"潮间食堂",27,CREAM)
	_text(Vector2(363,52),"TIDE TABLE",17,MINT,true)
	region(TOP_RIGHT)
	_text(Vector2(970,49),"DAY %02d" % game.progress.day,21,MINT,true)
	_text(Vector2(1100,49),"%d G" % game.progress.coins,25,GOLD,true)
	if game.state == "restaurant":
		_draw_management()
	else:
		_draw_service()
	if game.notice_timer > 0 and game.state != "service_paused":
		region(BOTTOM_CENTER)
		var w: float = font.get_string_size(game.notice,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x+40
		if OS.has_feature("web") and game.state == "service":
			var pixels: int = NativeText.font_size_for(self,16,14)
			w = font.get_string_size(game.notice,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x / NativeText.transform_for(self).get_scale().x + 40
		_panel(Rect2(720-w/2,844,w,39))
		_center(Vector2(720,870),game.notice,16,MINT)
	if game.summary_visible and game.state == "restaurant":
		_draw_bill()
	if game.state == "service_paused":
		region(CENTER)
		screen_overlay(Color(0.01,0.05,0.07,0.75))
		_panel(Rect2(495,270,450,320))
		_center(Vector2(720,330),"休息片刻",30)
		_center(Vector2(720,370),"料理与顾客耐心已暂停",17,MUTED)

func _draw_management() -> void:
	region(CENTER_LEFT)
	_panel(Rect2(32,110,276,660))
	_text(Vector2(54,144),"岸上仓库",23)
	_text(Vector2(54,169),"前三种鱼可烹饪，其余仅售卖",14,MUTED)
	var i: int = 0
	for id in _warehouse_ids():
		var y: float = 205+i*82
		_text(Vector2(54,y),P.GOODS[id].name,18)
		_text(Vector2(217,y),"× %d" % int(game.progress.inventory.get(id,0)),18,MINT)
		_text(Vector2(54,y+60),"%d G / 件 · %s" % [P.GOODS[id].value, "可烹饪" if P.RECIPES.has(id) else "仅售卖"],12,MUTED)
		i += 1
	_center(Vector2(169,647),"%d / %d" % [warehouse_page + 1, _warehouse_page_count()],15,MINT)
	var completed: int = game.progress.total_served + game.progress.total_lost
	var satisfaction: String = "尚未营业" if completed == 0 else "出餐率 %d%%" % int(float(game.progress.total_served)/completed*100)
	_text(Vector2(54,678),"营业 %d 场 · %s" % [game.progress.restaurant_runs,satisfaction],13,MINT)
	region(CENTER_RIGHT)
	_panel(Rect2(1050,164,356,606))
	if game.restaurant_tab == "renovation":
		i = 0
		var descriptions: Dictionary = {"clean":"清除杂物，修复地板与墙面", "kitchen":"开业必需 · 炉灶与料理台", "tables":"开业必需 · 同时服务 2 位", "sign":"每场目标顾客 +2", "expansion":"赠2套餐桌 · 上限4位 · 客流+2", "decor":"耐心+8秒 · 小费+10% · 赠品入收纳"}
		for id in P.RENOVATIONS:
			var y: float = 207+i*94
			_text(Vector2(1072,y),P.RENOVATIONS[id].name,17)
			_text(Vector2(1072,y+30),descriptions[id],13,MUTED)
			var reason: String = game.progress.renovation_reason(id)
			_text(Vector2(1072,y+54),"✓ 已装好" if game.progress.renovation.get(id,false) else ("可以施工" if reason.is_empty() else reason),12,MINT if reason.is_empty() else GOLD)
			i += 1
	else:
		_text(Vector2(1074,201),"今晚，端上你的收获",22)
		i = 0
		for id in P.RECIPES:
			var y: float = 238+i*140
			_text(Vector2(1074,y),P.RECIPES[id].name,19)
			_text(Vector2(1074,y+24),"售价 %d G · %d 秒 · 库存 %d" % [P.RECIPES[id].price,P.RECIPES[id].cook_time,int(game.progress.inventory.get(id,0))],13,MUTED)
			_center(Vector2(1223,y+56),"%d 份" % int(game.menu_plan.get(id,0)),23,GOLD)
			_text(Vector2(1080,y+116),game.preparation_label(id),13,MINT)
			i += 1
		_text(Vector2(1074,689),"计划共 %d 份 · 每份消耗 1 条鱼" % game.menu_total(),16,MINT)
		_text(Vector2(1074,720),"备料 / 火候 / 摆盘 · 品质收入最高+25%",12,MUTED)
	var stage: String = "待修复的旧店"
	if game.progress.can_open():
		stage = "海岸小餐厅 · 可以备菜开业"
	elif game.progress.renovation.get("clean",false):
		stage = "施工中 · 为第一位客人做准备"
	region(TOP_CENTER)
	_panel(Rect2(350,110,656,63),Color(0.025,0.12,0.15,0.84))
	_center(Vector2(678,140),stage,23)
	_center(Vector2(678,161),"从一间旧店，到你自己的海岸餐厅",13,MINT)
	region(BOTTOM_CENTER)
	_panel(Rect2(350,612,656,103),Color(0.025,0.12,0.15,0.91))
	_text(Vector2(371,642),"下一步",14,MINT)
	_text(Vector2(371,671),game.progress.next_goal(),19)
	var reason: String = game.service_block_reason()
	_text(Vector2(371,699),reason if not reason.is_empty() else "准备就绪。开门后点击订单制作，再点击上菜。",14,GOLD)
	region(CENTER_LEFT)
	_panel(Rect2(32,786,276,43))
	_text(Vector2(48,813),"累计营收 %d G · 服务 %d 位" % [game.progress.restaurant_income,game.progress.total_served],14,MINT)

func _draw_service() -> void:
	region(TOP_LEFT)
	_text(Vector2(34,51),"营业中",24,GOLD)
	_panel(Rect2(32,110,295,126))
	_text(Vector2(52,143),"本场收入",16,MUTED)
	_text(Vector2(52,185),"%d G" % int(game.progress.service_stats.get("earned",0)),36,GOLD,true)
	_text(Vector2(52,216),"已服务 %d · 流失 %d" % [int(game.progress.service_stats.get("served",0)),int(game.progress.service_stats.get("lost",0))],16)
	region(TOP_RIGHT)
	_panel(Rect2(1110,110,296,126))
	_text(Vector2(1130,144),"到店 %d / %d 位" % [game.service_arrived,game.progress.guest_limit()],21)
	_text(Vector2(1130,180),"剩余备料 %d 份" % game.service_remaining(),18,MINT)
	_text(Vector2(1130,214),"Esc 暂停 · 做好后及时上菜",16,MUTED)
	region(TOP_LEFT)
	_panel(Rect2(32,250,322,226),Color(0.025,0.12,0.15,0.95))
	_text(Vector2(52,278),"顾客留言",18,MINT)
	if game.service_feedback.is_empty():
		_text(Vector2(52,311),"留意气泡，先照顾着急的客人",16,MUTED)
	for i in range(game.service_feedback.size()):
		var feedback: Dictionary = game.service_feedback[i]
		var lines := _service_feedback_lines("%02d 桌 · %s" % [feedback.seat+1,feedback.text])
		for row in range(lines.size()):
			_text(Vector2(52,309+i*56+row*24),lines[row],16,_mood_color(feedback.mood))
	region(BOTTOM_CENTER)
	for seat in range(game.progress.seats()):
		var x: float = 32+seat*352
		_panel(Rect2(x,568,328,236))
		var current: Dictionary = {}
		for order in game.orders:
			if order.seat == seat:
				current = order
		if current.is_empty():
			_center(Vector2(x+164,681),"等待下一位客人",19,MUTED)
			_center(Vector2(x+164,714),"TABLE %02d" % (seat+1),16,MINT)
			continue
		_text(Vector2(x+18,598),"%02d 号桌 · 偏好%s" % [seat+1,game.Cuisine.SEASONINGS[int(current.get("preference",0))]],17,MUTED)
		_text(Vector2(x+18,629),P.RECIPES[current.dish].name,21)
		var fraction: float = clampf(current.patience/float(current.get("max_patience",game.progress.patience())),0,1)
		draw_style_box(_style(Color("31515a")),Rect2(x+18,643,292,7))
		draw_style_box(_style(MINT if fraction > 0.3 else Color("ed8e78")),Rect2(x+18,643,maxf(1,292*fraction),7))
		var label: String = "等待中 · 耐心 %.0f 秒" % current.patience
		if current.state == "cooking":
			label = "制作中 · 还需 %.1f 秒" % current.cook_left
		elif current.state == "ready":
			label = "已凉 · 无品质加成" if float(current.get("ready_age",0)) > game.Cuisine.HOT_WINDOW else "%s · 趁热 %.1fs" % [game.Cuisine.quality_label(current),maxf(0,game.Cuisine.HOT_WINDOW-float(current.get("ready_age",0)))]
		_text(Vector2(x+18,676),label,17,GOLD if current.state == "ready" else MUTED)
		if current.state == "cooking":
			draw_rect(Rect2(x+18,689,292,10),Color("31515a"))
			draw_rect(Rect2(x+18+292*0.4,689,292*0.35,10),Color("559b70"))
			var marker: float = x+18+292*game.Cuisine.heat_fraction(current)
			draw_line(Vector2(marker,685),Vector2(marker,703),GOLD,3)
		_text(Vector2(x+18,717),"%s · %s · 品质+%d%%" % [game.Cuisine.SEASONINGS[int(current.get("seasoning",0))],"精细备料" if current.get("prepped",false) else "普通备料",game.Cuisine.bonus_percent(current)],16,MINT)
		var mood: Dictionary = game.customer_mood(current)
		_text(Vector2(x+18,740),"“%s”" % mood.text,16,_mood_color(mood.mood))

func _draw_bill() -> void:
	region(CENTER)
	screen_overlay(Color(0.01,0.05,0.07,0.76))
	_panel(Rect2(460,213,520,486),Color("12343e"))
	_center(Vector2(720,263),"潮汐落幕，烟火未散",28)
	_center(Vector2(720,296),"今日营业账单  /  TIDE TABLE",14,MINT)
	var result: Dictionary = game.service_summary
	if result.get("culinary") is Dictionary:
		var cooking: Dictionary = result.culinary
		_center(Vector2(720,328),"拿手 %d · 合口味 %d · 凉菜 %d · 品质增收 %dG" % [cooking.get("excellent",0),cooking.get("matched",0),cooking.get("cold",0),cooking.get("bonus",0)],14,MINT)
	_center(Vector2(720,367),"收入  %d G" % int(result.get("earned",0)),43,GOLD)
	_text(Vector2(510,426),"完成用餐",18)
	_text(Vector2(840,426),"%d 位" % int(result.get("served",0)),22,MINT)
	_text(Vector2(510,471),"未完成 / 流失",18)
	_text(Vector2(840,471),"%d 位" % int(result.get("lost",0)),22)
	_text(Vector2(510,516),"未使用食材退库",18)
	_text(Vector2(840,516),"%d 份" % int(result.get("returned",0)),22)
	if result.get("reviews") is Dictionary:
		var reviews: Dictionary = result.reviews
		_center(Vector2(720,555),"满意 %d   ·   待改进 %d   ·   未吃到 %d" % [reviews.get("satisfied",0),reviews.get("okay",0),reviews.get("lost",0)],17,MINT)
		var suggestion: String = "料理送得很及时，继续保持！"
		if int(reviews.get("lost",0)) > 0:
			suggestion = "建议：优先照顾催单顾客，打烊前送完已接订单。"
		elif int(reviews.get("okay",0)) > 0:
			suggestion = "建议：及时开始制作，菜做好后尽快上桌。"
		_center(Vector2(720,584),suggestion,14,MUTED)
	else:
		_center(Vector2(720,565),"已完成订单即时保存，打烊后可继续装修。",15,MUTED)




func _mood_color(mood: String) -> Color:
	return Color("ed8e78") if mood == "lost" else (GOLD if mood == "okay" else MINT)
