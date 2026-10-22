extends Node2D
const Rules = preload("res://scripts/layout_rules.gd")
const CREAM = Color("f6ead4")
const MINT = Color("a9ead2")
const GOLD = Color("efbf75")
const MUTED = Color("9cb5b6")
var game: Node
var font: SystemFont
var controls: Array[Control] = []

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _style(color: Color, border: Color = Color(0.7,0.85,0.8,0.15)) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(7)
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
	controls.append(b)

func rebuild() -> void:
	for c in controls:
		remove_child(c)
		c.queue_free()
	controls.clear()
	visible = game.layout_mode
	if not visible:
		return
	_button("保存布局",Rect2(1050,27,170,48),game.save_layout,true)
	_button("取消修改",Rect2(1234,27,178,48),game.cancel_layout)
	var i: int = 0
	for kind in Rules.CATALOG:
		var item: Dictionary = Rules.CATALOG[kind]
		_button("%d G · 加入草稿" % item.cost,Rect2(50,207+i*105,220,36),func(): game.buy_layout_furniture(kind),false,game.layout_work.coins < int(item.cost))
		i += 1
	_button("撤销上一步",Rect2(50,701,220,42),game.undo_layout,false,game.layout_history.is_empty())
	_button("还原默认摆位",Rect2(50,754,220,42),game.reset_layout_draft)
	var owned = ItemList.new()
	owned.name = "OwnedFurnitureList"
	owned.position = Vector2(1154,160)
	owned.size = Vector2(236,306)
	owned.add_theme_font_override("font",font)
	owned.add_theme_font_size_override("font_size",15)
	owned.add_theme_color_override("font_color",CREAM)
	owned.add_theme_color_override("font_selected_color",Color("16343a"))
	owned.add_theme_stylebox_override("panel",_style(Color("102b34")))
	owned.add_theme_stylebox_override("selected",_style(MINT))
	owned.add_theme_stylebox_override("selected_focus",_style(MINT))
	owned.add_theme_constant_override("v_separation",12)
	owned.focus_mode = Control.FOCUS_NONE
	i = 0
	for item in game.layout_work.furniture_items():
		owned.add_item("%s  %s %02d" % ["已摆" if item.placed else "收纳",Rules.CATALOG[item.kind].name,i+1])
		owned.set_item_metadata(i,int(item.uid))
		if int(item.uid) == game.layout_selected:
			owned.select(i)
		i += 1
	owned.item_selected.connect(func(index: int): game.select_furniture(int(owned.get_item_metadata(index))))
	add_child(owned)
	controls.append(owned)
	var selected: Dictionary = game.layout_work.furniture_by_uid(game.layout_selected)
	var empty: bool = selected.is_empty()
	_button("移动  G",Rect2(1154,548,111,41),game.begin_move_furniture,false,empty)
	_button("旋转  R",Rect2(1275,548,115,41),game.rotate_layout,false,empty)
	_button("切换配色",Rect2(1154,601,111,41),game.color_selected_furniture,false,empty)
	_button("收回家具",Rect2(1275,601,115,41),game.store_selected_furniture,false,empty or not selected.get("placed",false))
	var floors = ["暖木地板","浅砂地板","薄荷木板"]
	var walls = ["奶油墙面","薄荷墙面","珊瑚墙面"]
	_button(floors[game.layout_work.floor_style] + "  →",Rect2(1154,692,236,41),func(): game.set_layout_style("floor",(game.layout_work.floor_style+1)%3))
	_button(walls[game.layout_work.wall_style] + "  →",Rect2(1154,745,236,41),func(): game.set_layout_style("wall",(game.layout_work.wall_style+1)%3))
	queue_redraw()

func _text(pos: Vector2, text: String, size: int = 18, color: Color = CREAM) -> void:
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _panel(rect: Rect2, color: Color = Color(0.025,0.12,0.15,0.96)) -> void:
	draw_style_box(_style(color),rect)

func _draw() -> void:
	if not visible or font == null:
		return
	draw_rect(Rect2(0,0,1440,96),Color("09232d"))
	_text(Vector2(34,47),"把小店，布置成你的样子",27)
	_text(Vector2(36,76),"TIDE TABLE  /  自由布置",14,MINT)
	_text(Vector2(670,44),"草稿余额 %d G" % game.layout_work.coins,22,GOLD)
	_text(Vector2(670,73),"本次新购 %d G · 保存后统一扣款" % (game.progress.coins-game.layout_work.coins),14,MUTED)
	_panel(Rect2(28,112,264,708))
	_text(Vector2(50,146),"家具小铺",23)
	var explanations = ["含配套座椅 · 90° 转向","角落的一点绿意","可叠放在餐桌下方","温暖的角落灯光","展示你的海岸收藏"]
	var i: int = 0
	for kind in Rules.CATALOG:
		var y: float = 188+i*105
		_text(Vector2(50,y),Rules.CATALOG[kind].name,20)
		_text(Vector2(50,y+78),explanations[i],13,MUTED)
		i += 1

	_panel(Rect2(1134,112,278,708))
	_text(Vector2(1154,144),"我的家具 / 收纳箱",21)
	var selected: Dictionary = game.layout_work.furniture_by_uid(game.layout_selected)
	if selected.is_empty():
		_text(Vector2(1154,505),"点选地面或列表中的家具",15,MUTED)
		_text(Vector2(1154,531),"选择收纳家具可直接摆放",13,MUTED)
	else:
		_text(Vector2(1154,504),Rules.CATALOG[selected.kind].name,21,GOLD)
		var colors = ["暖木","薄荷","珊瑚"]
		_text(Vector2(1154,532),"%s · %s · %d°" % ["摆放预览" if game.layout_placing else ("已摆放" if selected.placed else "收纳中"),colors[int(selected.color)],game.layout_rotation*90],14,MUTED)
	_text(Vector2(1154,675),"地板与墙面 · 自由切换",15,MINT)
	_panel(Rect2(340,110,760,52),Color(0.025,0.12,0.15,0.84))
	_text(Vector2(360,143),"已摆 %d 套餐桌 / 上限 %d   ·   半米对齐   ·   中央留通道" % [game.layout_work.seats(),4 if game.layout_work.renovation.expansion else 2],16,MINT)
	_panel(Rect2(320,786,804,92),Color(0.025,0.12,0.15,0.96))
	var hint: String = game.layout_reason
	if game.layout_placing and hint.is_empty():
		hint = "绿色区域可放置 · 点击左键确认摆放"
	_text(Vector2(340,816),hint,15,GOLD if not game.layout_placing or not game.layout_reason.is_empty() else MINT)
	_text(Vector2(340,843),"左键选择 / 放置    G 移动    R 旋转    Delete 收回    Ctrl+Z 撤销",14,MUTED)
	_text(Vector2(340,867),"滚轮缩放    右键取消摆放    Esc 取消摆放 / 退出且不保存",13,MUTED)


