extends Node2D
const BuildMode = preload("res://scripts/build_mode.gd")
const NativeText = preload("res://scripts/pixel_text.gd")
const NativeButtonLabel = preload("res://scripts/pixel_button_label.gd")
## Keep UI elements at their design size while the 3D viewport expands.
const DESIGN_SIZE := Vector2(1440, 900)
const TOP_LEFT := Vector2(0, 0)
const TOP_CENTER := Vector2(0.5, 0)
const TOP_RIGHT := Vector2(1, 0)
const CENTER_LEFT := Vector2(0, 0.5)
const CENTER := Vector2(0.5, 0.5)
const CENTER_RIGHT := Vector2(1, 0.5)
const BOTTOM_LEFT := Vector2(0, 1)
const BOTTOM_CENTER := Vector2(0.5, 1)
const BOTTOM_RIGHT := Vector2(1, 1)
var draw_offset := Vector2.ZERO
var _last_compact := false
var _layout_rebuild_queued := false

func _ready() -> void:
	_last_compact = compact_enabled()
	get_viewport().size_changed.connect(_resize_ui)

func ui_size() -> Vector2:
	return get_viewport_rect().size

func anchor_offset(anchor: Vector2) -> Vector2:
	return (ui_size() - DESIGN_SIZE) * anchor

func place_control(control: Control, rect: Rect2, anchor: Vector2) -> void:
	control.set_meta("design_position", rect.position)
	control.set_meta("design_size", rect.size)
	control.set_meta("layout_anchor", anchor)
	control.position = rect.position + anchor_offset(anchor)
	control.size = rect.size

func _resize_ui() -> void:
	var compact := compact_enabled()
	if (compact or compact != _last_compact) and not _layout_rebuild_queued and has_method("rebuild"):
		_layout_rebuild_queued = true
		call_deferred("_rebuild_for_size")
	_last_compact = compact
	if compact and not _mobile_actions.is_empty():
		call_deferred("_refresh_mobile")
	for child in get_children():
		if child is Control and child.has_meta("layout_anchor"):
			child.position = child.get_meta("design_position") + anchor_offset(child.get_meta("layout_anchor"))
			if child.has_meta("native_list_font_size"):
				_fit_native_list(child)
	queue_redraw()

func _rebuild_for_size() -> void:
	_layout_rebuild_queued = false
	if is_inside_tree():
		call("rebuild")

func region(anchor: Vector2) -> void:
	draw_offset = anchor_offset(anchor)
	draw_set_transform(draw_offset)

func screen_overlay(color: Color) -> void:
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(Vector2.ZERO, ui_size()), color)
	draw_set_transform(draw_offset)

func screen_bar(height: float, color: Color, bottom: bool = false) -> void:
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(0, ui_size().y - height if bottom else 0, ui_size().x, height), color)
	draw_set_transform(draw_offset)

func native_text(face: Font, pos: Vector2, value: String, size: int, color: Color, centered: bool = false, minimum_size: int = 1) -> void:
	if OS.has_feature("web"):
		# Panels can opt into a readable CSS-pixel minimum while keeping native glyphs.
		NativeText.draw(self,face,pos+draw_offset,value,size,color,centered,minimum_size)
		draw_set_transform(draw_offset)
	else:
		var origin := pos
		if centered:
			origin.x -= face.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x*0.5
		draw_string(face,origin,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func native_button_label(button: Button, face: Font, size: int, normal: Color, hover: Color, disabled: Color, minimum_size: int = 1) -> void:
	if not OS.has_feature("web"):
		return
	var label := NativeButtonLabel.new()
	label.button = button
	label.font = face
	label.design_size = size
	label.minimum_size = minimum_size
	label.normal_color = normal
	label.hover_color = hover
	label.disabled_color = disabled
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(key,Color.TRANSPARENT)
	button.add_child(label)

func native_item_list(control: ItemList, font_size: int, separation: int) -> void:
	if not OS.has_feature("web"):
		return
	control.set_meta("native_list_font_size",font_size)
	control.set_meta("native_list_separation",separation)
	_fit_native_list(control)

func _fit_native_list(control: ItemList) -> void:
	# ItemList owns scrolling/selection. Cancel only its fractional render scale,
	# then express its size and theme metrics in physical pixels to retain hitboxes.
	var transform := NativeText.transform_for(self)
	var factor: float = transform.get_scale().y
	if factor <= 0.0:
		return
	control.scale = Vector2.ONE / factor
	control.size = (Vector2(control.get_meta("design_size")) * factor).round()
	control.position = transform.affine_inverse() * (transform * control.position).round()
	control.add_theme_font_size_override("font_size",maxi(1,roundi(int(control.get_meta("native_list_font_size"))*factor)))
	control.add_theme_constant_override("v_separation",maxi(1,roundi(int(control.get_meta("native_list_separation"))*factor)))

# Compact menus keep readable CSS-pixel sizes on phones and small desktop embeds.
var _mobile_actions: Array = []
var _mobile_nav: Array[Control] = []
var _mobile_page := 0
var _mobile_title := ""
var _mobile_summary := ""
var _mobile_sidebar := false
var _mobile_page_size := 6
var _mobile_shield: Control

func mobile_enabled() -> bool:
	var owner_game: Variant = get("game")
	return is_instance_valid(owner_game) and bool(owner_game.get("mobile_controls"))

func compact_enabled() -> bool:
	var screen := ui_size()/mobile_unit()
	return mobile_enabled() or screen.x < 1100.0 or screen.y < 650.0

func mobile_unit() -> float:
	var ratio := 1.0
	if OS.has_feature("web"):
		var canvas = JavaScriptBridge.get_interface("document").getElementById("canvas")
		ratio = float(canvas.width)/maxf(1.0,float(canvas.clientWidth))
	return ratio / maxf(.01,NativeText.transform_for(self).get_scale().y)

func mobile_menu(actions: Array, title: String, summary: String, sidebar: bool = false) -> void:
	if _mobile_title != title:
		_mobile_page = 0
	_mobile_actions = actions.duplicate()
	_mobile_title = title
	_mobile_summary = summary
	_mobile_sidebar = sidebar
	_refresh_mobile()

func clear_mobile_menu() -> void:
	if is_instance_valid(_mobile_shield):
		_mobile_shield.queue_free()
	_mobile_shield = null
	for control in _mobile_nav:
		if is_instance_valid(control):
			control.queue_free()
	_mobile_nav.clear()
	_mobile_actions.clear()

func _refresh_mobile() -> void:
	if not compact_enabled():
		return
	for control in _mobile_nav:
		if is_instance_valid(control):
			control.queue_free()
	_mobile_nav.clear()
	var unit := mobile_unit()
	var screen := ui_size()/unit
	var width: float = minf(300,screen.x*.46) if _mobile_sidebar else screen.x
	if not is_instance_valid(_mobile_shield):
		_mobile_shield = Control.new()
		_mobile_shield.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_mobile_shield)
		move_child(_mobile_shield,0)
	_mobile_shield.size = Vector2(width*unit,ui_size().y)
	var rows := clampi(int((screen.y-130)/52),2,5)
	var columns := 1 if _mobile_sidebar else 2
	_mobile_page_size = rows*columns
	var pages := maxi(1,ceili(float(_mobile_actions.size())/_mobile_page_size))
	_mobile_page = clampi(_mobile_page,0,pages-1)
	var cell_width: float = (width-24.0-8.0*(columns-1))/columns
	for index in range(_mobile_actions.size()):
		var action: Control = _mobile_actions[index]
		if not is_instance_valid(action):
			continue
		action.visible = index/_mobile_page_size == _mobile_page
		action.remove_meta("layout_anchor")
		var slot := index%_mobile_page_size
		action.position = Vector2(12+(slot%columns)*(cell_width+8),76+int(slot/columns)*52)*unit
		action.size = Vector2(cell_width,46)*unit
		if action is Button:
			for child in action.get_children():
				if child is NativeButtonLabel:
					child.queue_free()
			action.add_theme_font_size_override("font_size",roundi(14*unit))
			var fill: StyleBox = action.get_theme_stylebox("normal")
			var ink := Color("092834") if fill is StyleBoxFlat and fill.bg_color.get_luminance() > .5 else Color("e8f3ed")
			action.add_theme_color_override("font_color",ink)
			action.add_theme_color_override("font_hover_color",Color.WHITE)
			action.add_theme_color_override("font_pressed_color",Color("092834"))
			action.add_theme_color_override("font_disabled_color",Color("81989d"))
			action.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for offset in range(2):
		var button := Button.new()
		button.text = "上一页" if offset == 0 else "下一页"
		button.disabled = _mobile_page == 0 if offset == 0 else _mobile_page == pages-1
		button.position = Vector2(12 if offset == 0 else width*.5+4,screen.y-50)*unit
		button.size = Vector2(width*.5-16,44)*unit
		button.add_theme_font_override("font",preload("res://assets/fonts/ui_font.tres"))
		button.add_theme_font_size_override("font_size",roundi(15*unit))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_mobile_turn.bind(-1 if offset == 0 else 1))
		add_child(button)
		_mobile_nav.append(button)
	queue_redraw()

func _mobile_turn(amount: int) -> void:
	_mobile_page += amount
	_refresh_mobile()

func draw_mobile_menu() -> void:
	var unit := mobile_unit()
	var screen := ui_size()/unit
	var width: float = minf(300,screen.x*.46) if _mobile_sidebar else screen.x
	draw_set_transform(Vector2.ZERO)
	draw_offset = Vector2.ZERO
	draw_rect(Rect2(0,0,width*unit,ui_size().y),Color(.025,.10,.14,.97))
	var face = preload("res://assets/fonts/ui_font.tres")
	draw_string(face,Vector2(12,25)*unit,_mobile_title,HORIZONTAL_ALIGNMENT_LEFT,width*unit-24*unit,roundi(19*unit),Color("a9ead2"))
	draw_string(face,Vector2(12,49)*unit,_mobile_summary,HORIZONTAL_ALIGNMENT_LEFT,width*unit-24*unit,roundi(12*unit),Color("f5c779"))
	var pages := maxi(1,ceili(float(_mobile_actions.size())/_mobile_page_size))
	draw_string(face,Vector2(12,68)*unit,"%d / %d  ·  点击操作，翻页查看更多" % [_mobile_page+1,pages],HORIZONTAL_ALIGNMENT_LEFT,width*unit-24*unit,roundi(11*unit),Color("98b7bb"))

func place_mobile_button(button: Button, css_rect: Rect2) -> void:
	var unit := mobile_unit()
	button.remove_meta("layout_anchor")
	button.position = css_rect.position*unit
	button.size = css_rect.size*unit
	for child in button.get_children():
		if child is NativeButtonLabel:
			child.queue_free()
	button.add_theme_font_size_override("font_size",roundi(15*unit))
	var fill: StyleBox = button.get_theme_stylebox("normal")
	var ink := Color("092834") if fill is StyleBoxFlat and fill.bg_color.get_luminance() > .5 else Color("e8f3ed")
	button.add_theme_color_override("font_color",ink)
	button.add_theme_color_override("font_hover_color",Color.WHITE)
	button.add_theme_color_override("font_disabled_color",Color("81989d"))
