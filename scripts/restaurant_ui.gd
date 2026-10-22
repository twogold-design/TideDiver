extends Node2D
const LayoutUI = preload("res://scripts/layout_ui.gd")
var layout_ui: Node2D

const P = preload("res://scripts/progression.gd")
const CREAM = Color("f6ead4")
const MINT = Color("a9ead2")
const GOLD = Color("efbf75")
const MUTED = Color("9cb5b6")
var game: Node
var font: SystemFont
var latin: SystemFont
var buttons: Array[Button] = []

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	latin = SystemFont.new()
	latin.font_names = PackedStringArray(["Bahnschrift","Arial"])
	layout_ui = LayoutUI.new()
	layout_ui.game = game
	add_child(layout_ui)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _style(color: Color, border: Color = Color(0.7,0.85,0.8,0.15)) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = border
	return s

func _button(text: String, rect: Rect2, action: Callable, primary: bool = false, disabled: bool = false) -> void:
	var b = Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font",font)
	b.add_theme_font_size_override("font_size",16)
	b.add_theme_color_override("font_color",Color("14343a") if primary else CREAM)
	b.add_theme_color_override("font_hover_color",Color("14343a") if primary else Color.WHITE)
	b.add_theme_color_override("font_disabled_color",Color("778e94"))
	b.add_theme_stylebox_override("normal",_style(GOLD if primary else Color("254952")))
	b.add_theme_stylebox_override("hover",_style(Color("ffe2ae") if primary else Color("3a636b"),MINT))
	b.add_theme_stylebox_override("pressed",_style(Color("699d94")))
	b.add_theme_stylebox_override("disabled",_style(Color("1d353d")))
	b.pressed.connect(action)
	add_child(b)
	buttons.append(b)

func rebuild() -> void:
	for b in buttons:
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
		_button("← 返回码头",Rect2(32,30,150,43),game.return_to_dock)
		_button("店面装修",Rect2(1050,110,166,42),func(): game.restaurant_tab = "renovation"; rebuild(),game.restaurant_tab == "renovation")
		_button("备菜菜单",Rect2(1226,110,180,42),func(): game.restaurant_tab = "menu"; rebuild(),game.restaurant_tab == "menu")
		var i: int = 0
		for id in P.GOODS:
			var amount: int = int(game.progress.inventory.get(id,0))
			var y: float = 221 + i*92
			_button("卖 1 件",Rect2(54,y,110,30),func(): game.sell_goods(id,1),false,amount <= 0)
			_button("全卖",Rect2(174,y,110,30),func(): game.sell_goods(id,amount),false,amount <= 0)
			i += 1
		_button("仅出售珍珠与宝藏",Rect2(54,701,230,44),game.sell_valuables,false,int(game.progress.inventory.get("pearl",0))+int(game.progress.inventory.get("chest",0)) == 0)
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
				i += 1
		_button("自由布置",Rect2(357,726,173,58),game.enter_layout,false,not game.progress.renovation.clean)
		var reason: String = game.service_block_reason()
		_button("开门营业   →",Rect2(545,726,350,58),game.start_service,true,not reason.is_empty())
		if not game.service_summary.is_empty():
			_button("查看上次账单",Rect2(558,789,324,33),func(): game.summary_visible = true; rebuild())
	else:
		_button("提前打烊",Rect2(1238,31,168,42),game.finish_service)
		for order in game.orders:
			var x: float = 32 + order.seat*352
			var label: String = "开始制作"
			if order.state == "cooking":
				label = "料理制作中…"
			elif order.state == "ready":
				var sale_price: int = int(P.RECIPES[order.dish].price)
				if game.progress.renovation.get("decor",false):
					sale_price += int(sale_price / 10.0)
				label = "上菜  +%d G" % sale_price
			var order_id: int = order.id
			if order.state == "ready":
				_button(label,Rect2(x+18,747,292,40),func(): game.serve_order(order_id),true)
			else:
				_button(label,Rect2(x+18,747,292,40),func(): game.cook_order(order_id),false,order.state == "cooking")
	queue_redraw()

func _text(pos: Vector2, text: String, size: int = 18, color: Color = CREAM, english: bool = false) -> void:
	draw_string(latin if english else font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _center(pos: Vector2, text: String, size: int = 18, color: Color = CREAM) -> void:
	var w: float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	_text(pos-Vector2(w/2,0),text,size,color)

func _panel(rect: Rect2, color: Color = Color(0.025,0.12,0.15,0.95)) -> void:
	draw_style_box(_style(color),rect)

func _draw() -> void:
	if not visible or font == null or game.layout_mode:
		return
	draw_rect(Rect2(0,0,1440,94),Color(0.025,0.10,0.13,0.96))
	_text(Vector2(207,52),"潮间食堂",27,CREAM)
	_text(Vector2(363,52),"TIDE TABLE",17,MINT,true)
	_text(Vector2(970,49),"DAY %02d" % game.progress.day,21,MINT,true)
	_text(Vector2(1100,49),"%d G" % game.progress.coins,25,GOLD,true)
	if game.state == "restaurant":
		_draw_management()
	else:
		_draw_service()
	if game.notice_timer > 0 and game.state != "service_paused":
		var w: float = font.get_string_size(game.notice,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x+40
		_panel(Rect2(720-w/2,844,w,39))
		_center(Vector2(720,870),game.notice,16,MINT)
	if game.summary_visible and game.state == "restaurant":
		_draw_bill()
	if game.state == "service_paused":
		draw_rect(Rect2(0,0,1440,900),Color(0.01,0.05,0.07,0.75))
		_panel(Rect2(495,270,450,320))
		_center(Vector2(720,330),"休息片刻",30)
		_center(Vector2(720,370),"料理与顾客耐心已暂停",17,MUTED)

func _draw_management() -> void:
	_panel(Rect2(32,110,276,660))
	_text(Vector2(54,144),"岸上仓库",23)
	_text(Vector2(54,169),"卖出筹资，留鱼做菜",14,MUTED)
	var i: int = 0
	for id in P.GOODS:
		var y: float = 205+i*92
		_text(Vector2(54,y),P.GOODS[id].name,18)
		_text(Vector2(217,y),"× %d" % int(game.progress.inventory.get(id,0)),18,MINT)
		_text(Vector2(54,y+69),"售卖 %d G / 件" % P.GOODS[id].value,12,MUTED)
		i += 1
	var completed: int = game.progress.total_served + game.progress.total_lost
	var satisfaction: String = "尚未营业" if completed == 0 else "满意度 %d%%" % int(float(game.progress.total_served)/completed*100)
	_text(Vector2(54,678),"营业 %d 场 · %s" % [game.progress.restaurant_runs,satisfaction],13,MINT)
	_panel(Rect2(1050,164,356,606))
	if game.restaurant_tab == "renovation":
		i = 0
		var descriptions: Dictionary = {"clean":"清除杂物，修复地板与墙面", "kitchen":"开业必需 · 炉灶与料理台", "tables":"开业必需 · 同时服务 2 位", "sign":"每场目标顾客 +2", "expansion":"4 个座位 · 目标顾客再 +2", "decor":"耐心 +8 秒 · 料理小费 +10%"}
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
			i += 1
		_text(Vector2(1074,689),"计划共 %d 份 · 每份消耗 1 条鱼" % game.menu_total(),16,MINT)
		_text(Vector2(1074,720),"未接单的备料打烊后会退回仓库",13,MUTED)
	var stage: String = "待修复的旧店"
	if game.progress.can_open():
		stage = "海岸小餐厅 · 可以备菜开业"
	elif game.progress.renovation.get("clean",false):
		stage = "施工中 · 为第一位客人做准备"
	_panel(Rect2(350,110,656,63),Color(0.025,0.12,0.15,0.84))
	_center(Vector2(678,140),stage,23)
	_center(Vector2(678,161),"从一间旧店，到你自己的海岸餐厅",13,MINT)
	_panel(Rect2(350,612,656,103),Color(0.025,0.12,0.15,0.91))
	_text(Vector2(371,642),"下一步",14,MINT)
	_text(Vector2(371,671),game.progress.next_goal(),19)
	var reason: String = game.service_block_reason()
	_text(Vector2(371,699),reason if not reason.is_empty() else "准备就绪。开门后点击订单制作，再点击上菜。",14,GOLD)
	_panel(Rect2(32,786,276,43))
	_text(Vector2(48,813),"累计营收 %d G · 服务 %d 位" % [game.progress.restaurant_income,game.progress.total_served],14,MINT)

func _draw_service() -> void:
	_text(Vector2(34,51),"营业中",24,GOLD)
	_panel(Rect2(32,110,295,126))
	_text(Vector2(52,143),"本场收入",16,MUTED)
	_text(Vector2(52,185),"%d G" % int(game.progress.service_stats.get("earned",0)),36,GOLD,true)
	_text(Vector2(52,216),"已服务 %d · 流失 %d" % [int(game.progress.service_stats.get("served",0)),int(game.progress.service_stats.get("lost",0))],16)
	_panel(Rect2(1110,110,296,126))
	_text(Vector2(1130,144),"到店 %d / %d 位" % [game.service_arrived,game.progress.guest_limit()],21)
	_text(Vector2(1130,180),"剩余备料 %d 份" % game.service_remaining(),18,MINT)
	_text(Vector2(1130,214),"Esc 暂停 · 完成料理后记得上菜",13,MUTED)
	for seat in range(game.progress.seats()):
		var x: float = 32+seat*352
		_panel(Rect2(x,608,328,196))
		var current: Dictionary = {}
		for order in game.orders:
			if order.seat == seat:
				current = order
		if current.is_empty():
			_center(Vector2(x+164,681),"等待下一位客人",19,MUTED)
			_center(Vector2(x+164,714),"TABLE %02d" % (seat+1),13,MINT)
			continue
		_text(Vector2(x+18,638),"%02d 号桌" % (seat+1),14,MUTED)
		_text(Vector2(x+18,671),P.RECIPES[current.dish].name,21)
		var fraction: float = clampf(current.patience/game.progress.patience(),0,1)
		draw_style_box(_style(Color("31515a")),Rect2(x+18,685,292,7))
		draw_style_box(_style(MINT if fraction > 0.3 else Color("ed8e78")),Rect2(x+18,685,maxf(1,292*fraction),7))
		var label: String = "顾客等待中 · 耐心 %.0f 秒" % current.patience
		if current.state == "cooking":
			label = "制作中 · 还需 %.1f 秒" % current.cook_left
		elif current.state == "ready":
			label = "料理完成！点击上菜领取收入"
		_text(Vector2(x+18,723),label,14,GOLD if current.state == "ready" else MUTED)

func _draw_bill() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.01,0.05,0.07,0.76))
	_panel(Rect2(460,213,520,486),Color("12343e"))
	_center(Vector2(720,263),"潮汐落幕，烟火未散",28)
	_center(Vector2(720,296),"今日营业账单  /  TIDE TABLE",14,MINT)
	var result: Dictionary = game.service_summary
	_center(Vector2(720,367),"收入  %d G" % int(result.get("earned",0)),43,GOLD)
	_text(Vector2(510,426),"满意离店",18)
	_text(Vector2(840,426),"%d 位" % int(result.get("served",0)),22,MINT)
	_text(Vector2(510,471),"未完成 / 流失",18)
	_text(Vector2(840,471),"%d 位" % int(result.get("lost",0)),22)
	_text(Vector2(510,516),"未使用食材退库",18)
	_text(Vector2(840,516),"%d 份" % int(result.get("returned",0)),22)
	_center(Vector2(720,565),"已完成订单即时保存，打烊后可继续装修。",15,MUTED)



