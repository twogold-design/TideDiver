extends "res://scripts/responsive_ui.gd"
const RestaurantUI = preload("res://scripts/restaurant_ui.gd")
const PixelText = preload("res://scripts/pixel_text.gd")
const PixelButtonLabel = preload("res://scripts/pixel_button_label.gd")
var restaurant_ui: Node2D

var game: Node
var font: Font
var latin: Font
var buttons: Array[Button] = []
var fade_texture: GradientTexture2D
const INK = Color("092834")
const LIGHT = Color("e9f5ec")
const MINT = Color("a9ead2")
const GOLD = Color("f5c779")
const MUTED = Color("8bb2b5")
const DOCK_LEFT_INSET := 96.0

func _ready() -> void:
	super._ready()
	font = preload("res://assets/fonts/ui_font.tres")
	latin = preload("res://assets/fonts/ui_font.tres")
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.018,0.085,0.12,0.96))
	gradient.set_color(1, Color(0.018,0.085,0.12,0.0))
	fade_texture = GradientTexture2D.new()
	fade_texture.gradient = gradient
	fade_texture.width = 512
	fade_texture.height = 1
	fade_texture.fill_from = Vector2(0,0)
	fade_texture.fill_to = Vector2(1,0)
	restaurant_ui = RestaurantUI.new()
	restaurant_ui.game = game
	add_child(restaurant_ui)
	rebuild()

func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.border_color = border
	style.set_border_width_all(1)
	return style

func _button(label: String, rect: Rect2, callback: Callable, primary: bool = false, disabled: bool = false, anchor: Vector2 = CENTER) -> void:
	var button = Button.new()
	button.text = label
	place_control(button, rect, anchor)
	button.add_theme_font_override("font",font)
	button.add_theme_font_size_override("font_size",18)
	button.add_theme_color_override("font_color",INK if primary else LIGHT)
	button.add_theme_color_override("font_hover_color",INK if primary else Color.WHITE)
	button.add_theme_stylebox_override("normal",_style(MINT if primary else Color("153f49"), Color("39636a")))
	button.add_theme_stylebox_override("hover",_style(Color("c9ffe5") if primary else Color("25606a"), MINT))
	button.add_theme_stylebox_override("pressed",_style(Color("74bca6")))
	button.add_theme_stylebox_override("disabled",_style(Color("18323c")))
	button.disabled = disabled
	button.pressed.connect(callback)
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	if _use_pixel_text():
		var label_node = PixelButtonLabel.new()
		label_node.button = button
		label_node.font = font
		label_node.normal_color = INK if primary else LIGHT
		label_node.hover_color = INK if primary else Color.WHITE
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
			button.add_theme_color_override(key, Color.TRANSPARENT)
		button.add_child(label_node)
	buttons.append(button)

func rebuild() -> void:
	for button in buttons:
		remove_child(button)
		button.queue_free()
	buttons.clear()
	if is_instance_valid(restaurant_ui):
		restaurant_ui.rebuild()
	if game.state == "rescuing":
		queue_redraw()
		return
	if game.rescue_result_visible:
		_button("知道了，继续整备",Rect2(520,610,400,58),game.dismiss_rescue_result,true)
		queue_redraw()
		return
	if game.new_game_confirmation:
		_button("保留进度 / 取消",Rect2(451,511,256,53),game.cancel_new_game,true)
		_button("确认重新开始",Rect2(733,511,256,53),game.confirm_new_game)
		queue_redraw()
		return
	if game.gm_menu_open:
		for index in range(game.Ocean.DIVE_SITES.size()):
			var y: float = 215 + index * 66
			_button("船上入水",Rect2(817,y+8,150,40),game.gm_select_dive_site.bind(index,false))
			_button("直达景观",Rect2(982,y+8,170,40),game.gm_select_dive_site.bind(index,true),true)
		_button("无限气瓶量：" + ("开启" if game.gm_infinite_air else "关闭"),Rect2(290,715,420,48),game.toggle_gm_infinite_air,game.gm_infinite_air)
		_button("返回游戏 · F1 / Esc",Rect2(750,715,400,48),game.close_gm_menu)
		queue_redraw()
		return
	if game.state == "dock":
		_button("出发潜水    →",_dock_left_rect(Rect2(64,486,370,64)),game.start_dive,true,false,CENTER_LEFT)
		var kinds = ["tank","bag","spear"]
		for i in range(3):
			var kind: String = kinds[i]
			var cost: int = game.progress.upgrade_cost(kind)
			var label: String = "%d G   升级" % cost if cost >= 0 else "已满级"
			_button(label,Rect2(1045,530+i*77,180,43),func(): game.upgrade(kind),false,cost < 0 or game.progress.coins < cost,CENTER_RIGHT)
		_button("我的餐厅  ·  仓库 / 装修 / 营业",_dock_left_rect(Rect2(64,561,370,49)),game.open_restaurant,false,false,CENTER_LEFT)
		if not OS.has_feature("web"):
			_button("退出游戏",_dock_left_rect(Rect2(64,782,150,43)),func(): get_tree().quit(),false,false,BOTTOM_LEFT)
		_button("重新开始游戏",_dock_left_rect(Rect2(230,782,204,43)),game.request_new_game,false,false,BOTTOM_LEFT)
		_button("GM 自选潜点 · F1",Rect2(545,782,260,43),game.open_gm_menu,false,false,BOTTOM_CENTER)
	elif game.state == "paused":
		_button("重新开始游戏",Rect2(545,558,350,48),game.request_new_game)
		_button("继续探索",Rect2(545,410,350,58),game.toggle_pause,true)
		_button("呼叫救援 · 保留 35% 收益",Rect2(545,484,350,58),_rescue)
		if not OS.has_feature("web"):
			_button("退出游戏",Rect2(545,620,350,48),func(): get_tree().quit())
		_button("GM 自选潜点 · F1",Rect2(545,680,350,48),game.open_gm_menu)
	queue_redraw()

func _rescue() -> void:
	game.state = "dive"
	game.finish_dive(true)

func _dock_left_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position + Vector2(DOCK_LEFT_INSET,0),rect.size)

func _dock_left_region(anchor: Vector2) -> void:
	region(anchor)
	draw_offset.x += DOCK_LEFT_INSET
	draw_set_transform(draw_offset)

func _text(pos: Vector2, text: String, size: int, color: Color = LIGHT, english: bool = false) -> void:
	if _use_pixel_text():
		PixelText.draw(self, latin if english else font, pos + draw_offset, text, size, color)
		draw_set_transform(draw_offset)
		return
	draw_string(latin if english else font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _center(pos: Vector2, text: String, size: int, color: Color = LIGHT) -> void:
	if _use_pixel_text():
		PixelText.draw(self, font, pos + draw_offset, text, size, color, true)
		draw_set_transform(draw_offset)
		return
	var width: float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	_text(pos-Vector2(width*0.5,0),text,size,color)

func _use_pixel_text() -> bool:
	return OS.has_feature("web") and is_instance_valid(game) and game.state == "dock" and not game.rescue_result_visible and not game.new_game_confirmation and not game.gm_menu_open

func _panel(rect: Rect2, color: Color = Color(0.025,0.12,0.16,0.88), border: Color = Color(0.4,0.8,0.75,0.18)) -> void:
	draw_style_box(_style(color,border),rect)

func _draw() -> void:
	if not is_instance_valid(game) or font == null:
		return
	if OS.has_feature("web"):
		PixelText.pixel_ratio = float(JavaScriptBridge.get_interface("window").devicePixelRatio)
	if game.state in ["restaurant","service","service_paused"]:
		return
	region(CENTER)
	if game.state == "rescuing":
		_draw_rescue_transit()
		return
	if game.state == "dock":
		_draw_dock()
	else:
		if game.hurt_flash > 0:
			screen_overlay(Color(0.65,0.04,0.035,0.16*game.hurt_flash/0.45))
		_draw_hud()
	if game.rescue_result_visible:
		_draw_rescue_result()
		return
	if game.state == "paused":
		region(CENTER)
		screen_overlay(Color(0.01,0.05,0.08,0.75))
		_panel(Rect2(495,260,450,510),Color("0d303d"))
		_center(Vector2(720,317),"静候下一次呼吸",29)
		_center(Vector2(720,351),"PAUSED / 潜水已暂停",14,MUTED)
	if game.harvest_result_visible and game.notice_timer > 0 and game.state == "dock" and not game.new_game_confirmation and not game.gm_menu_open:
		_draw_harvest_result()
	elif game.notice_timer > 0 and game.state != "paused":
		region(BOTTOM_CENTER)
		var w: float = font.get_string_size(game.notice,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x + 50
		_panel(Rect2(720-w/2,824,w,43),Color(0.025,0.12,0.16,0.94))
		_center(Vector2(720,852),game.notice,17,MINT)

	if game.new_game_confirmation:
		region(CENTER)
		screen_overlay(Color(0.01,0.04,0.07,0.88))
		_panel(Rect2(410,283,620,324),Color("0d303d"))
		_center(Vector2(720,337),"重新开始一段旅程？",29)
		_center(Vector2(720,387),"金币、装备、仓库、店面和家具将全部重置。",19,LIGHT)
		_center(Vector2(720,423),"从第 1 天重新开始，并覆盖当前自动存档。",18,GOLD)
		_center(Vector2(720,467),game.new_game_error if not game.new_game_error.is_empty() else "取消或按 Esc 可保留当前进度。",16,GOLD if not game.new_game_error.is_empty() else MUTED)
	if game.gm_test_active and game.state == "dive":
		region(CENTER_LEFT)
		_panel(Rect2(30,414,220,44),Color(0.08,0.17,0.20,0.94),Color(GOLD,0.65))
		_text(Vector2(44,442),"GM 试游 · F1 切换潜点",14,GOLD)
	if game.gm_menu_open and not game.new_game_confirmation:
		_draw_gm_menu()

func _draw_harvest_result() -> void:
	region(CENTER)
	# A brief centered notification leaves the dock controls immediately usable.
	_panel(Rect2(440,294,560,174),Color(0.07,0.20,0.24,0.96),MINT)
	_center(Vector2(720,331),"平安返航",19,GOLD)
	var count: int = int(game.last_result.count)
	_center(Vector2(720,378),"收获 %d 件 · 已存入仓库" % count if count > 0 else "本次没有带回物资",28,LIGHT)
	_center(Vector2(720,418),"可去餐厅售卖筹资，或留下海鱼备菜。" if count > 0 else "岸上物资与装备保留，可以继续整备。",17,MINT)
	_center(Vector2(720,447),"进度已自动保存",14,MUTED)

func _draw_rescue_transit() -> void:
	region(CENTER)
	screen_overlay(Color(0.03,0.07,0.10,0.84))
	_panel(Rect2(350,278,740,320),Color("26343b"),Color("ef9e72"))
	_center(Vector2(720,345),"气瓶耗尽",42,Color("ffb190"))
	_center(Vector2(720,405),"救援艇正在接你返航",30,LIGHT)
	_center(Vector2(720,453),"本次潜水已结束，请等待返航。",20,MUTED)
	_center(Vector2(720,503),"本次携带物资按 35% 价值折价结算",20,GOLD)
	var fraction: float = clampf(1.0 - game.rescue_time / 2.8,0,1)
	draw_style_box(_style(Color("38535a")),Rect2(450,546,540,8))
	draw_style_box(_style(GOLD),Rect2(450,546,maxf(1,540*fraction),8))

func _draw_rescue_result() -> void:
	region(CENTER)
	screen_overlay(Color(0.01,0.05,0.08,0.86))
	_panel(Rect2(330,218,780,490),Color("12333e"),GOLD)
	_center(Vector2(720,285),"救援返航 · 已安全抵达码头",32,GOLD)
	_center(Vector2(720,330),"气瓶耗尽，本次潜水由救援艇接回。" if game.last_result.get("depleted",false) else "你呼叫了救援艇，本次潜水已结束。",21,LIGHT)
	_center(Vector2(720,392),"本次折价结算  +%d G" % int(game.last_result.earned),36,MINT)
	_center(Vector2(720,438),"携带 %d 件物资，按总价值的 35%% 兑换金币，未入仓库。" % int(game.last_result.count),19,LIGHT)
	_center(Vector2(720,480),"原有金币、岸上仓库与家具均保留。进度已保存。",18,MUTED)
	_center(Vector2(720,535),"下次留意氧气余量，提前上浮至 3 米内，按 F 安全返航。",18,GOLD)
	_center(Vector2(720,572),"也可以升级潜水气瓶，让每次探索更从容。",17,MUTED)

func _draw_gm_menu() -> void:
	region(CENTER)
	screen_overlay(Color(0.01,0.04,0.07,0.87))
	_panel(Rect2(245,102,950,696),Color("0d303d"),Color(MINT,0.42))
	_text(Vector2(286,151),"GM · 自选潜点",30,LIGHT)
	_text(Vector2(1010,148),"F1 / Esc 关闭",15,MUTED)
	var subtitle: String = "选择潜点开始本次潜水；船上入水播放跳水动画，直达景观立即进入水下。" if game.gm_return_state == "dock" else "潜水中切换地点会保留背包和气瓶量，不结算本次潜水。"
	_text(Vector2(286,187),subtitle,16,MUTED)
	var descriptions: Array[String] = [
		"浅水鱼群与近岸采集，适合试游和捕鱼。",
		"深切峡谷与双门遗迹，体验顺流 / 逆流。",
		"沉船结构与宝藏，检查遮挡与鱼叉弹道。",
		"大片鹿角、桌状珊瑚与海扇，沿通道游览。",
		"420 条杰克鱼旋游风暴，观赏鱼不进入背包。",
		"贝壳环礁与珍珠采集，观察远海浅水鱼群。"
	]
	for index in range(game.Ocean.DIVE_SITES.size()):
		var y: float = 215 + index * 66
		var selected: bool = game.gm_test_active and game.entry_site_index == index
		_panel(Rect2(270,y,900,56),Color("153f49") if selected else Color("10353e"),Color(GOLD,0.55) if selected else Color(MINT,0.12))
		_text(Vector2(286,y+31),"%02d" % (index+1),15,MINT,true)
		_text(Vector2(326,y+25),game.Ocean.DIVE_SITES[index].name,19,GOLD if selected else LIGHT)
		_text(Vector2(326,y+46),descriptions[index],13,MUTED)
	_center(Vector2(720,784),"无限气瓶量适用于呼吸、受伤和中毒；重新打开游戏后默认关闭。",13,MUTED)

func _draw_dock() -> void:
	# An editorial split layout keeps the underwater vista visible.
	region(TOP_LEFT)
	draw_texture_rect(fade_texture,Rect2(0,0,1080,ui_size().y),false)

	screen_bar(90,Color(0.02,0.09,0.12,0.50))
	draw_circle(Vector2(73,46),12,MINT)
	draw_arc(Vector2(73,46),18,0,TAU,40,Color(MINT,0.3),1.5,true)
	_text(Vector2(106,53),"TIDE DIVER",21,LIGHT,true)
	_text(Vector2(286,51),"潮间潜客",18,MUTED)
	region(TOP_RIGHT)
	_text(Vector2(1010,51),"DAY %02d" % game.progress.day,19,MINT,true)
	_text(Vector2(1165,51),"%04d  G" % game.progress.coins,23,GOLD,true)
	_dock_left_region(CENTER_LEFT)
	_text(Vector2(67,151),"A LITTLE FURTHER, A LITTLE DEEPER.",14,MINT,true)
	_text(Vector2(58,250),"TIDE",98,LIGHT,true)
	_text(Vector2(58,339),"DIVER",98,LIGHT,true)
	draw_line(Vector2(65,369),Vector2(111,369),GOLD,3)
	_text(Vector2(130,376),"潮间潜客  /  潮汐湾",24,LIGHT)
	_text(Vector2(65,424),"把日常留在岸上。",20,MUTED)
	_text(Vector2(65,458),"向海而行，带着故事返航。",20,MUTED)
	
	_panel(Rect2(64,624,370,144),Color(0.03,0.16,0.20,0.76))
	_text(Vector2(85,654),"潜客日志",16,MINT)
	if game.last_result.is_empty():
		_text(Vector2(85,686),"潜水筹资 · 修复你的海岸旧店",18,LIGHT)
		_text(Vector2(85,718),"仓库 %d 件 · 去餐厅售货或备菜" % game.progress.inventory_total(),15,MUTED)
	else:
		_text(Vector2(85,687),("救援结算  +%d G" % game.last_result.earned) if game.last_result.rescued else ("收获入库  %d 件" % game.last_result.count),25,GOLD,true)
		if game.last_result.rescued:
			_text(Vector2(85,719),"本次货物按 35% 折价，岸上物资保留",13,MUTED)
		else:
			var entries: Array[String] = []
			var stored: Dictionary = game.last_result.get("stored",{})
			for id in stored:
				entries.append("%s ×%d" % [game.progress.GOODS[id].name,stored[id]])
			_text(Vector2(85,716),"  ".join(entries.slice(0,3)) if not entries.is_empty() else "这次没有带回物资，再试一次吧。",13,MUTED)
			if entries.size() > 3:
				_text(Vector2(85,742),"  ".join(entries.slice(3)),13,MUTED)
	region(CENTER_RIGHT)
	_panel(Rect2(895,422,365,347),Color(0.025,0.12,0.16,0.92))
	_text(Vector2(923,459),"下一次，潜得更远",24,LIGHT)
	_text(Vector2(923,490),"EQUIPMENT / 出航整备",13,MINT,true)
	var levels = [game.progress.tank_level,game.progress.bag_level,game.progress.spear_level]
	var names = ["潜水气瓶","采集背包","强化鱼叉"]
	var values = ["%d 气瓶量" % int(game.progress.oxygen_max()),"%d kg 容量" % game.progress.capacity(),"%d 点伤害" % game.progress.spear_damage()]
	for i in range(3):
		var y: float = 544+i*77
		_text(Vector2(923,y),names[i],18,LIGHT)
		_text(Vector2(923,y+26),values[i],13,MUTED)
		for j in range(3):
			draw_rect(Rect2(923+j*24,y+37,18,3),MINT if j < levels[i] else Color("34535b"))
	region(BOTTOM_RIGHT)
	_text(Vector2(906,811),"OCEAN EXPLORATION",13,MUTED,true)
	_dock_left_region(BOTTOM_LEFT)
	_text(Vector2(65,886),"WASD 移动 · 鼠标转向 · Q / E 下潜上浮",13,MUTED)
	# A discreet vista locator.
	region(CENTER_RIGHT)
	draw_arc(Vector2(1032,247),38,0,TAU,60,Color(MINT,0.45),1.0,true)
	draw_circle(Vector2(1032,247),4,MINT)
	draw_line(Vector2(1070,247),Vector2(1134,247),Color(MINT,0.45),1)
	_text(Vector2(1144,252),"潮汐湾",18,LIGHT)
	_text(Vector2(1144,277),"REEF 01",12,MINT,true)

func _draw_hud() -> void:
	region(CENTER)
	if game.entry_active:
		var immersion: float = 1.0 - smoothstep(-1.5, 0.6, game.camera.position.y)
		screen_overlay(Color(0.02,0.28,0.34,immersion * 0.12))
		_center(Vector2(720,710), ("跃入%s" % game.Ocean.DIVE_SITES[game.entry_site_index].name) if not game.entry_splashed else "沉入蔚蓝", 28, LIGHT)
		if game.entry_splashed:
			for i in range(16):
				var age: float = maxf(0, game.entry_time - 1.4)
				var pos := Vector2(180 + fposmod(float(i) * 173,1080), 900 - fposmod(age * (170 + i * 9) + i * 83, 1000))
				draw_arc(pos, 4 + i % 5 * 2, 0, TAU, 20, Color(0.7,0.94,0.95,0.22 * maxf(0, 1.0 - age / 2.0)), 1.5, true)
		return
	region(TOP_LEFT)
	_panel(Rect2(30,28,345,116))
	_text(Vector2(52,59),"TIDE DIVER",19,LIGHT,true)
	_text(Vector2(230,57),"潮间潜客",15,MUTED)
	_text(Vector2(52,88),"AIR",22,MINT,true)
	var fraction: float = 1.0 if game.gm_infinite_air else game.oxygen/game.progress.oxygen_max()
	var oxygen_color: Color = MINT if fraction > 0.25 else Color("ff886b")
	draw_style_box(_style(Color("21434b")),Rect2(95,77,210,11))
	draw_style_box(_style(oxygen_color),Rect2(95,77,210*maxf(fraction,0.01),11))
	_text(Vector2(316,88),"∞" if game.gm_infinite_air else str(int(game.oxygen)),17,oxygen_color,true)
	_text(Vector2(52,123),"气瓶量 · GM 无限" if game.gm_infinite_air else "气瓶量",13,MINT if game.gm_infinite_air else MUTED)
	_text(Vector2(214,123),"DAY %02d  ·  潮汐湾" % game.progress.day,13,MUTED)
	region(TOP_RIGHT)
	var bag_full: bool = game.weight() >= game.progress.capacity()
	var capacity_alert: bool = bag_full or game.capacity_warning_timer > 0
	var capacity_ink := Color("ffb190")
	_panel(Rect2(1135,28,275,116),Color("352b2b") if capacity_alert else Color(0.025,0.12,0.16,0.88),capacity_ink if capacity_alert else Color(0.4,0.8,0.75,0.18))
	_text(Vector2(1157,60),"深度",14,MUTED)
	_text(Vector2(1220,66),"%04.1f" % -game.player.position.y,36,LIGHT,true)
	_text(Vector2(1345,64),"m",18,MINT,true)
	_text(Vector2(1157,105),"载重 %02d / %02d kg" % [game.weight(),game.progress.capacity()],18,capacity_ink if capacity_alert else LIGHT)
	_text(Vector2(1157,130),"背包已满 · 请返航入库" if bag_full else "收获价值  %d G" % game.cargo_value(),14,capacity_ink if bag_full else GOLD)
	# Compass and heading markers.
	region(TOP_CENTER)
	var heading: float = fposmod(-rad_to_deg(game.yaw),360)
	_text(Vector2(644,48),"N   ·   %03d°   ·   S" % int(heading),17,MINT,true)
	draw_line(Vector2(720,61),Vector2(720,72),GOLD,2)
	_center(Vector2(720,102),game.ocean_zone_name(),19,LIGHT)
	if not game.current_hint.is_empty():
		_center(Vector2(720,137), "峡谷水流 · %s · %.1f m/s" % [game.current_hint,game.drift_current.length()], 16, MINT)
	if game.ocean_edge_distance() < 18:
		_center(Vector2(720,137),"前方洋流增强 · 请转向海域内部",18,GOLD)
	_draw_ocean_map()
	# Center reticle turns gold when a fish is in range.
	region(CENTER)
	var target: Dictionary = game.target_fish()
	var reticle: Color = GOLD if not target.is_empty() else Color(0.88,1,0.94,0.7)
	if not target.is_empty() and int(game.FishData.SPECIES[target.kind].weight) > game.progress.capacity()-game.weight():
		reticle = capacity_ink
	var center = Vector2(720,450)
	for dir in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		draw_line(center+dir*9,center+dir*17,reticle,2,true)
	draw_circle(center,2,reticle)
	if game.shot_cooldown > 0:
		draw_arc(center,23,-PI/2,-PI/2+TAU*(1-game.shot_cooldown/game.SPEAR_COOLDOWN),30,MINT,2,true)
	if game.hit_timer > 0:
		var flash: Color = GOLD if game.catch_timer > 0 else MINT
		var spread: float = 21 + (1.0 - game.hit_timer / 0.3) * 14
		for diagonal in [Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
			draw_line(center + diagonal * spread, center + diagonal * (spread + 9), Color(flash, minf(1, game.hit_timer * 6)), 3, true)
	if game.capacity_warning_timer > 0:
		var alpha: float = minf(1.0,game.capacity_warning_timer/0.5)
		_panel(Rect2(410,566,620,170),Color(0.20,0.10,0.09,0.97*alpha),Color(capacity_ink,alpha))
		draw_rect(Rect2(410,566,620,5),Color(capacity_ink,alpha))
		native_text(font,Vector2(720,608),"背包空间不足",30,Color(capacity_ink,alpha),true,20)
		native_text(font,Vector2(720,643),"%s · %s" % [game.capacity_warning_action,game.capacity_warning_name],22,Color(LIGHT,alpha),true,16)
		native_text(font,Vector2(720,676),"需要 %d kg · 当前仅剩 %d kg" % [game.capacity_warning_weight,maxi(0,game.progress.capacity()-game.weight())],19,Color(GOLD,alpha),true,14)
		native_text(font,Vector2(720,713),"按住 E 上浮，靠近海面后按 F 返航入库",17,Color(LIGHT,alpha),true,14)
	elif game.loot_feedback_timer > 0:
		var alpha: float = minf(1.0,game.loot_feedback_timer/0.5)
		var rows: int = mini(3,game.loot_feedback.size())
		var has_note: bool = not game.loot_feedback_note.is_empty()
		var card_height: float = 72+rows*24+(24 if has_note else 0)
		_panel(Rect2(470,565,500,card_height),Color(0.025,0.12,0.16,0.94*alpha),Color(GOLD,0.55*alpha))
		_center(Vector2(720,595),game.loot_feedback_title,23,Color(GOLD,alpha))
		for row in range(rows):
			_center(Vector2(720,627+row*24),game.loot_feedback[row],17,Color(LIGHT,alpha))
		if has_note:
			_center(Vector2(720,627+rows*24),game.loot_feedback_note,16,Color(MINT,alpha))
	elif game.catch_timer > 0:
		var caught: Dictionary = game.FishData.SPECIES[game.catch_kind]
		var age: float = 2.4 - game.catch_timer
		var slide: float = (1.0 - smoothstep(0.0, 0.18, age)) * 20
		var alpha: float = minf(1.0, game.catch_timer / 0.35)
		_panel(Rect2(510, 568 + slide, 420, 104), Color(0.025,0.12,0.16,0.92 * alpha), Color(GOLD,0.55 * alpha))
		_center(Vector2(720, 604 + slide), "捕获成功 · %s" % caught.name, 24, Color(GOLD,alpha))
		_center(Vector2(720, 644 + slide), "已装入背包  ·  %d kg  ·  价值 %d G" % [caught.weight, caught.value], 16, Color(LIGHT,alpha))
	if not target.is_empty():
		var fraction_hp: float = float(target.hp)/float(game.FishData.SPECIES[target.kind].hp)
		draw_style_box(_style(Color("21434b")),Rect2(667,479,106,5))
		draw_style_box(_style(GOLD if target.armor else MINT),Rect2(667,479,106*fraction_hp,5))
	var hint: String = game.context_hint()
	if not hint.is_empty():
		var w: float = font.get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+42
		_panel(Rect2(720-w/2,504,w,42))
		_center(Vector2(720,532),hint,18,GOLD)
	if fraction < 0.25:
		region(TOP_CENTER)
		_panel(Rect2(350,154,740,78),Color(0.27,0.10,0.08,0.96),Color("ef9e72"))
		_center(Vector2(720,185),"氧气不足 · 剩余 %d%%" % maxi(0,ceili(fraction*100)),25,Color("ffb190"))
		_center(Vector2(720,216),"立即按住 E 上浮，抵达 3 米内按 F 返航；耗尽将触发救援折价结算。",17,LIGHT)
	if game.hunt_warning_timer > 0:
		region(TOP_CENTER)
		_panel(Rect2(370,244,700,42),Color(0.24,0.08,0.10,0.92))
		_center(Vector2(720,271),game.hunt_warning,18,Color("ffb190"))
	if game.poison_timer > 0:
		region(TOP_CENTER)
		var poison_label: String = "中毒 %.1f 秒 · GM 已免除耗气" if game.gm_infinite_air else "中毒 %.1f 秒 · 每秒额外消耗 1.5 气瓶量"
		_center(Vector2(720,316),poison_label % game.poison_timer,17,Color("d5c0f2"))
	region(BOTTOM_LEFT)
	_panel(Rect2(30,685,236,104),Color(0.025,0.12,0.16,0.78))
	_text(Vector2(48,712),"探索目标",13,MINT)
	var discovery: Dictionary = game.nearby_exploration_point()
	var exploration_label: String = "沿导航寻找外围支路"
	if not discovery.is_empty():
		exploration_label = ("抵达 · %s" % discovery.name) if discovery.distance < 16.0 else ("%s · %d m" % [discovery.name,int(discovery.distance)])
	_text(Vector2(48,743),exploration_label,17,LIGHT)
	_text(Vector2(48,771),"◇ 外围景观 · + 补气点",13,MUTED)
	_draw_depth_gauge()
	region(BOTTOM_CENTER)
	_panel(Rect2(290,768,1035,43),Color(0.025,0.12,0.16,0.85))
	_text(Vector2(308,794),"WASD 游泳   Q / E 潜浮   Shift 冲刺   Ctrl 慢游   左键 / 空格 鱼叉 · 20m   F 互动   Esc 暂停",15,MUTED)
	region(BOTTOM_LEFT)
	_text(Vector2(42,882),"M  音效开关   ·   F1  GM 自选潜点",12,MUTED)
	region(BOTTOM_RIGHT)
	_text(Vector2(1200,882),"TIDAL BAY / 01",13,MUTED,true)
	if game.hurt_cooldown > 1.8:
		screen_overlay(Color(0.85,0.2,0.2,0.08))

func _draw_depth_gauge() -> void:
	region(CENTER_RIGHT)
	var x: float = 1360
	draw_line(Vector2(x,264),Vector2(x,604),Color(MUTED,0.35),2)
	for i in range(6):
		var y: float = 264+i*68
		draw_line(Vector2(x-5,y),Vector2(x+5,y),MUTED,1)
		_text(Vector2(x+14,y+5),str(int(float(i)*-game.Ocean.Y_MIN/5.0)),12,MUTED,true)
	var marker: float = 264 + clampf(-game.player.position.y/-game.Ocean.Y_MIN,0,1)*340
	draw_colored_polygon(PackedVector2Array([Vector2(x-13,marker),Vector2(x-23,marker-6),Vector2(x-23,marker+6)]),GOLD)
	_text(Vector2(x-56,240),"DEPTH",12,MINT,true)







func _draw_ocean_map() -> void:
	region(TOP_LEFT)
	var rect := Rect2(30,170,220,230)
	_panel(rect,Color(0.025,0.12,0.16,0.84))
	_text(rect.position+Vector2(14,25),"海域导航  ·  N ↑",14,MINT)
	var map_rect := Rect2(rect.position+Vector2(18,42),Vector2(184,160))
	draw_rect(map_rect,Color(0.08,0.27,0.31,0.8))
	var areas: Array = game.Ocean.exploration_areas()
	for site in range(areas.size()):
		var zone: Dictionary = areas[site]
		var pos: Vector2 = _map_point(zone.center,map_rect)
		var radius: float = float(zone.radius)*map_rect.size.x/(game.Ocean.X_MAX-game.Ocean.X_MIN)
		draw_circle(pos,radius,Color(0.45,0.72,0.72,0.12))
		draw_arc(pos,radius,0,TAU,32,Color(0.45,0.72,0.72,0.38),1,true)
		draw_circle(pos,5,Color("719ca0"))
		for point: Dictionary in game.Ocean.exploration_points(site):
			var marker: Vector2 = _map_point(point.position,map_rect)
			draw_polyline(PackedVector2Array([marker+Vector2(0,-3),marker+Vector2(3,0),marker+Vector2(0,3),marker+Vector2(-3,0),marker+Vector2(0,-3)]),GOLD,1,true)
	for item in game.pickups:
		if item.kind == "oxygen" and item.active:
			var pos: Vector2 = _map_point(item.home,map_rect)
			draw_line(pos-Vector2(3,0),pos+Vector2(3,0),MINT,2)
			draw_line(pos-Vector2(0,3),pos+Vector2(0,3),MINT,2)
	var diver: Vector2 = _map_point(game.player.position,map_rect)
	var direction := Vector2(-sin(game.yaw),-cos(game.yaw))
	draw_circle(diver,4,GOLD)
	draw_line(diver,diver+direction*11,GOLD,2)
	_text(rect.position+Vector2(14,220),"金色：你   +：补气   ◇：支路",12,MUTED)

func _map_point(point: Vector3, rect: Rect2) -> Vector2:
	return rect.position + Vector2(inverse_lerp(game.Ocean.X_MIN,game.Ocean.X_MAX,point.x)*rect.size.x,inverse_lerp(game.Ocean.Z_MIN,game.Ocean.Z_MAX,point.z)*rect.size.y)
