extends Node2D
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

func _ready() -> void:
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
	for child in get_children():
		if child is Control and child.has_meta("layout_anchor"):
			child.position = child.get_meta("design_position") + anchor_offset(child.get_meta("layout_anchor"))
			if child.has_meta("native_list_font_size"):
				_fit_native_list(child)
	queue_redraw()

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
