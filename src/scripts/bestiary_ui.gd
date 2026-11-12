extends "res://scripts/responsive_ui.gd"
## A small, isolated specimen viewport; opening the journal never changes sea life.
const Catalog = preload("res://scripts/wildlife_catalog.gd")
const FishArt = preload("res://scripts/fish_art.gd")
const ReefArt = preload("res://scripts/reef_fish_art.gd")
const MarineArt = preload("res://scripts/marine_life_art.gd")
const RayArt = preload("res://scripts/ray_art.gd")
const ThresherArt = preload("res://scripts/thresher_shark.gd")
const CaveArt = preload("res://scripts/crevice_art.gd")
const PAGE_SIZE := 7
const CREAM := Color("e8f3ed")
const MINT := Color("a9ead2")
const MUTED := Color("98b7bb")
const GOLD := Color("f5c779")
var game: Node
var font: Font
var buttons: Array[Button] = []
var page: int = 0
var selected: int = 0
var preview: SubViewport
var preview_image: TextureRect
var specimen: Node3D
var pivot: Node3D
var preview_camera: Camera3D
var input_shield: Control
var _preview_key: String = ""
var _turn: float = 0.0

func _ready() -> void:
	super._ready()
	font = preload("res://assets/fonts/ui_font.tres")
	z_index = 30
	# Keep clicks on empty journal space from reaching management or pause buttons.
	input_shield = Control.new()
	input_shield.name = "JournalInputShield"
	input_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	input_shield.size = ui_size()
	add_child(input_shield)
	_create_preview()
	rebuild()

func _resize_ui() -> void:
	super._resize_ui()
	if is_instance_valid(input_shield):
		input_shield.size = ui_size()

func _style(fill: Color, border: Color = Color("365861")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style

func _button(label: String, rect: Rect2, action: Callable, primary: bool = false, disabled: bool = false) -> void:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = disabled
	place_control(button,rect,CENTER)
	button.add_theme_font_override("font",font)
	button.add_theme_font_size_override("font_size",18)
	var ink: Color = Color("123c44") if primary else CREAM
	button.add_theme_color_override("font_color",ink)
	button.add_theme_color_override("font_hover_color",ink)
	button.add_theme_color_override("font_disabled_color",MUTED)
	button.add_theme_stylebox_override("normal",_style(MINT if primary else Color("183d48")))
	button.add_theme_stylebox_override("hover",_style(Color("cefae7") if primary else Color("2b5661"),MINT))
	button.add_theme_stylebox_override("pressed",_style(Color("76b7aa")))
	button.add_theme_stylebox_override("disabled",_style(Color("142d36")))
	button.pressed.connect(action)
	add_child(button)
	native_button_label(button,font,18,ink,ink,MUTED,14)
	buttons.append(button)

func rebuild() -> void:
	for button: Button in buttons:
		remove_child(button)
		button.queue_free()
	buttons.clear()
	visible = is_instance_valid(game) and game.bestiary_open
	if not is_instance_valid(preview):
		return
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	preview_image.visible = visible
	if not visible:
		return
	if compact_enabled():
		_rebuild_mobile()
		return
	# A desktop resize restores the specimen frame after the compact layout.
	place_control(preview_image,Rect2(586,270,690,244),CENTER)
	var entries: Array = Catalog.entries()
	page = clampi(page,0,maxi(0,ceili(float(entries.size())/PAGE_SIZE)-1))
	selected = clampi(selected,0,entries.size()-1)
	_button("返回 · B / Esc",Rect2(1110,88,192,44),game.close_bestiary)
	for index in range(page*PAGE_SIZE,mini((page+1)*PAGE_SIZE,entries.size())):
		var entry: Dictionary = entries[index]
		var known: bool = game.progress.has_discovery(entry.id)
		var label: String = "%02d  %s" % [index+1,str(entry.name) if known else "尚未发现"]
		_button(label,Rect2(132,208+(index%PAGE_SIZE)*68,390,56),_select.bind(index),selected == index)
	_button("上一页",Rect2(132,728,122,44),_change_page.bind(-1),false,page == 0)
	_button("下一页",Rect2(400,728,122,44),_change_page.bind(1),false,(page+1)*PAGE_SIZE >= entries.size())
	_refresh_specimen(entries[selected])
	queue_redraw()

func _select(index: int) -> void:
	selected = index
	rebuild()

func _change_page(amount: int) -> void:
	page += amount
	selected = page*PAGE_SIZE
	rebuild()

func _text(point: Vector2, value: String, size: int = 18, color: Color = CREAM, centered: bool = false) -> void:
	native_text(font,point,value,size,color,centered,14)

func _paragraph(point: Vector2, value: String, width: float, size: int = 18, color: Color = CREAM) -> void:
	var line := ""
	var baseline := point
	for character: String in value:
		if character == "\n" or (not line.is_empty() and font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x > width):
			_text(baseline,line,size,color)
			baseline.y += size+11
			line = ""
		if character != "\n":
			line += character
	if not line.is_empty():
		_text(baseline,line,size,color)

func _draw() -> void:
	if not visible or font == null:
		return
	if compact_enabled():
		_draw_mobile()
		return
	region(CENTER)
	screen_overlay(Color(.015,.055,.075,.90))
	draw_style_box(_style(Color("0e2a35"),Color("436872")),Rect2(100,58,1240,784))
	_text(Vector2(132,116),"海洋图鉴",32)
	_text(Vector2(132,153),"可捕获鱼首次捕获收录；观赏生物完成轮廓描绘后收录。",17,MUTED)
	var entries: Array = Catalog.entries()
	var unlocked := 0
	for item: Dictionary in entries:
		if game.progress.has_discovery(item.id):
			unlocked += 1
	_text(Vector2(940,119),"已收录  %d / %d" % [unlocked,entries.size()],20,MINT)
	draw_rect(Rect2(132,177,1176,2),Color("315560"))
	draw_style_box(_style(Color("133440")),Rect2(558,204,748,568))
	_text(Vector2(327,757),"%d / %d" % [page+1,ceili(float(entries.size())/PAGE_SIZE)],18,MUTED,true)
	_text(Vector2(132,813),"每个物种仅奖励一次，图鉴与奖励会自动保存。",17,MUTED)
	if entries.is_empty():
		return
	var entry: Dictionary = entries[selected]
	var known: bool = game.progress.has_discovery(entry.id)
	_text(Vector2(586,246),str(entry.name) if known else "未知的海洋居民",26,CREAM if known else MUTED)
	_text(Vector2(1268,245),"可捕获" if bool(entry.catchable) else "观赏生物",16,MINT if entry.catchable else GOLD,true)
	_text(Vector2(586,531),"生活习性" if known else "探索线索",16,MINT)
	var hint: String = "首次成功捕获它，即可解锁完整记录。" if entry.catchable else "在潜点发现它后，点击描绘按钮，沿轮廓画完即可解锁。"
	_paragraph(Vector2(586,562),str(entry.description) if known else hint,684,18,CREAM if known else MUTED)
	_text(Vector2(586,635),"常见区域",16,MINT)
	_paragraph(Vector2(586,665),str(entry.habitat),684,18)
	draw_rect(Rect2(586,693,692,1),Color("315560"))
	var status: String = "首次收录奖励  +%d G" % int(entry.reward)
	if known:
		var record: Dictionary = game.progress.discoveries.get(entry.id,{})
		var method: String = str(record.get("method","observed"))
		status = "捕获记录已收录" if method == "caught" else ("描绘记录已收录" if method == "sketched" else "观察记录已收录")
		status += "  ·  不重复奖励"
	_text(Vector2(586,731),status,19,GOLD if not known else MINT)
	_text(Vector2(586,756),"新发现自动获得金币奖励，无需额外点击领取。",14,MUTED)

func _create_preview() -> void:
	preview = SubViewport.new()
	preview.name = "SpecimenViewport"
	preview.size = Vector2i(690,244)
	preview.own_world_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	preview.gui_disable_input = true
	add_child(preview)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("133440")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cde4e0")
	environment.ambient_light_energy = .7
	world.environment = environment
	preview.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-35,0)
	light.light_energy = 1.0
	preview.add_child(light)
	pivot = Node3D.new()
	preview.add_child(pivot)
	preview_camera = Camera3D.new()
	preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview_camera.position = Vector3(4,1.3,-5)
	preview.add_child(preview_camera)
	preview_camera.look_at(Vector3.ZERO)
	preview_camera.current = true
	preview_image = TextureRect.new()
	preview_image.name = "SpecimenPreview"
	preview_image.texture = preview.get_texture()
	preview_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	place_control(preview_image,Rect2(586,270,690,244),CENTER)
	add_child(preview_image)

func _refresh_specimen(entry: Dictionary) -> void:
	var known: bool = game.progress.has_discovery(entry.id)
	var key: String = str(entry.id)+str(known)
	if key == _preview_key:
		return
	_preview_key = key
	if is_instance_valid(specimen):
		specimen.free()
	specimen = _model(entry)
	pivot.add_child(specimen)
	var bounds: AABB = _bounds(specimen,Transform3D.IDENTITY)
	specimen.position -= bounds.get_center()
	var diameter: float = Vector2(bounds.size.x,bounds.size.z).length()
	# Fit the panoramic card, accounting for the slightly elevated camera.
	preview_camera.size = maxf(.2,maxf(bounds.size.y+diameter*.24,diameter/2.8))*1.30
	_turn = .30
	if not known:
		var silhouette := StandardMaterial3D.new()
		silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		silhouette.albedo_color = Color("284f5a")
		for visual: Node in specimen.find_children("*","MeshInstance3D",true,false):
			visual.material_override = silhouette
		if specimen is MeshInstance3D:
			specimen.material_override = silhouette

func _model(entry: Dictionary) -> Node3D:
	if int(entry.kind) >= 0:
		return FishArt.build(int(entry.kind))
	var id: String = str(entry.id)
	if id == "sand_ray":
		return RayArt.build()
	if id == "thresher_shark":
		var shark := ThresherArt.new()
		shark._assemble()
		return shark
	if id == "lightning_clam":
		return CaveArt._clam()
	var visual := MeshInstance3D.new()
	if id.begins_with("reef_"):
		visual.mesh = ReefArt.mesh(id.trim_prefix("reef_"))
		visual.material_override = ReefArt.material()
	else:
		var form: String = id.trim_prefix("marine_")
		visual.mesh = MarineArt.mesh(form)
		visual.material_override = MarineArt.material(form)
	return visual

func _bounds(node: Node3D, transform: Transform3D) -> AABB:
	var current: Transform3D = transform*node.transform
	var result := AABB()
	var found := false
	if node is MeshInstance3D and node.mesh != null:
		result = current*node.mesh.get_aabb()
		found = true
	for child: Node in node.get_children():
		if child is Node3D:
			var child_bounds: AABB = _bounds(child,current)
			if child_bounds.size.length_squared() > 0:
				result = result.merge(child_bounds) if found else child_bounds
				found = true
	return result

func _process(delta: float) -> void:
	if visible and is_instance_valid(pivot):
		_turn += delta*.23
		pivot.rotation.y = _turn

func _rebuild_mobile() -> void:
	var entries: Array = Catalog.entries()
	selected = clampi(selected,0,entries.size()-1)
	var unit := mobile_unit()
	var screen := ui_size()/unit
	_button("上一种",Rect2(),_mobile_select.bind(-1),false,selected == 0)
	_button("返回游戏",Rect2(),game.close_bestiary,true)
	_button("下一种",Rect2(),_mobile_select.bind(1),false,selected == entries.size()-1)
	var width: float = (screen.x-48)/3
	for index in range(buttons.size()):
		place_mobile_button(buttons[index],Rect2(12+index*(width+12),screen.y-54,width,46))
	preview_image.remove_meta("layout_anchor")
	preview_image.position = Vector2(12,62)*unit
	preview_image.size = Vector2(screen.x*.40-24,maxf(80,screen.y-132))*unit
	_refresh_specimen(entries[selected])
	queue_redraw()

func _mobile_select(amount: int) -> void:
	selected += amount
	rebuild()

func _mobile_paragraph(point: Vector2, value: String, width: float, size: int, color: Color) -> void:
	var unit := mobile_unit()
	var actual_size := roundi(size*unit)
	var line := ""
	for character: String in value:
		if character == "\n" or font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size).x > width*unit:
			draw_string(font,point*unit,line,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size,color)
			point.y += size+7
			line = ""
		if character != "\n":
			line += character
	if not line.is_empty():
		draw_string(font,point*unit,line,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size,color)

func _draw_mobile() -> void:
	var unit := mobile_unit()
	var screen := ui_size()/unit
	var entries: Array = Catalog.entries()
	var entry: Dictionary = entries[selected]
	var known: bool = game.progress.has_discovery(entry.id)
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(Vector2.ZERO,ui_size()),Color("0e2a35"))
	draw_string(font,Vector2(12,29)*unit,"海洋图鉴 · %d / %d" % [selected+1,entries.size()],HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(20*unit),MINT)
	draw_string(font,Vector2(screen.x*.4,29)*unit,"已收录 %d / %d" % [game.progress.discoveries.size(),entries.size()],HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(15*unit),MUTED)
	var left: float = screen.x*.4+12
	var width: float = screen.x-left-16
	_mobile_paragraph(Vector2(left,76),str(entry.name) if known else "未知的海洋居民",width,20,CREAM)
	_mobile_paragraph(Vector2(left,108),"可捕获 · 首次捕获收录" if entry.catchable else "观赏生物 · 描绘轮廓收录",width,13,GOLD)
	var hint: String = "首次成功捕获它，即可解锁。" if entry.catchable else "发现它后点描绘按钮，沿轮廓画完即可解锁。"
	var details: String = str(entry.description) if known else hint
	details += "\n出没："+str(entry.habitat)
	_mobile_paragraph(Vector2(left,136 if screen.y >= 330 else 124),details,width,14 if screen.y >= 330 else 12,CREAM)
	_mobile_paragraph(Vector2(left,screen.y-76),"已收录 · 不重复奖励" if known else "首次收录奖励 +%d G" % entry.reward,width,14,GOLD)
