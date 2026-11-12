extends Control
## A paused field sketch. Only an ordered, near-outline drag can finish discovery.
signal completed(id: String)
signal cancelled
const Contours = preload("res://scripts/wildlife_contours.gd")
const Catalog = preload("res://scripts/wildlife_catalog.gd")
const PixelText = preload("res://scripts/pixel_text.gd")
const COMPLETE_COVERAGE := .95
const INK := Color("a9ead2")
const GUIDE := Color("77aeb5")
const CREAM := Color("e8f3ed")
var game: Node
var active := false
var species_id := ""
var _normalized := PackedVector2Array()
var _points := PackedVector2Array()
var _progress := 0.0
var _direction := 0
var _drawing := false
var _pointer := Vector2.ZERO
var _last_pointer := Vector2.ZERO
var _pointer_inside := false
var _touch_id := -1
var _unit := 1.0
var _tolerance := 12.0
var _canvas := Rect2()
var _status := "从发光圆点起笔，沿轮廓描绘"
var _font: Font = preload("res://assets/fonts/ui_font.tres")
var _restart_button: Button
var _cancel_button: Button
var _finished := false
var trace_complete: bool:
	get: return _finished

func _ready() -> void:
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_restart_button = _make_button("重新描绘",restart)
	_cancel_button = _make_button("返回潜水",_confirm_or_cancel)
	get_viewport().size_changed.connect(_layout)
	mouse_entered.connect(func() -> void: _pointer_inside = true)
	mouse_exited.connect(func() -> void: _pointer_inside = false; queue_redraw())
	hide()
	_layout()

func _make_button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font",_font)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("194753")
	style.border_color = GUIDE
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal",style)
	var hover := style.duplicate()
	hover.bg_color = Color("28616b")
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_color_override("font_color",CREAM)
	button.pressed.connect(callback)
	add_child(button)
	return button

func open_entry(id: String) -> void:
	var record: Dictionary = Catalog.entry(id)
	if record.is_empty() or record.catchable:
		return
	species_id = id
	_normalized = Contours.outline(id)
	if _normalized.is_empty():
		return
	active = true
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restart()
	_layout()

func close_panel() -> void:
	active = false
	_drawing = false
	_touch_id = -1
	_pointer_inside = false
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func restart() -> void:
	_progress = 0.0
	_direction = 0
	_drawing = false
	_touch_id = -1
	_finished = false
	if is_instance_valid(_cancel_button):
		_cancel_button.text = "返回潜水"
	_status = "从发光圆点起笔，沿轮廓描绘"
	queue_redraw()

func completion_ratio() -> float:
	return minf(1.0,_progress/maxf(1.0,float(_points.size()-1)))

func contour_points() -> PackedVector2Array:
	return _points.duplicate()

func resume_point() -> Vector2:
	return _at_index(float(_direction)*_progress) if _direction != 0 else (_points[0] if not _points.is_empty() else Vector2.ZERO)

func _layout() -> void:
	size = get_viewport_rect().size
	var ratio := 1.0
	if OS.has_feature("web"):
		var canvas = JavaScriptBridge.get_interface("document").getElementById("canvas")
		ratio = float(canvas.width)/maxf(1.0,float(canvas.clientWidth))
	_unit = ratio/maxf(.01,PixelText.transform_for(self).get_scale().y)
	var css := size/_unit
	var short := css.y < 420
	var top: float = 63 if short else 98
	var bottom: float = 62 if short else 88
	_canvas = Rect2(Vector2(20,top)*_unit,Vector2(maxf(60,css.x-40),maxf(80,css.y-top-bottom))*_unit)
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for point in _normalized:
		low = low.min(point)
		high = high.max(point)
	var fit := 1.0
	if not _normalized.is_empty():
		var span := high-low
		fit = minf(_canvas.size.x*.80/maxf(.01,span.x),_canvas.size.y*.78/maxf(.01,span.y))
		fit = minf(fit,620*_unit)
	_points.clear()
	for point in _normalized:
		_points.append(_canvas.get_center()+point*fit)
	_tolerance = clampf(minf(_canvas.size.x,_canvas.size.y)*.045,6*_unit,12*_unit)
	_drawing = false
	_touch_id = -1
	if is_instance_valid(_restart_button):
		var width: float = minf(155,(css.x-36)*.5)
		_restart_button.position = Vector2(12,css.y-50)*_unit
		_cancel_button.position = Vector2(css.x-width-12,css.y-50)*_unit
		for button: Button in [_restart_button,_cancel_button]:
			button.size = Vector2(width,44)*_unit
			button.add_theme_font_size_override("font_size",roundi(14*_unit))
	queue_redraw()

func begin_stroke(point: Vector2) -> void:
	if not active or _finished or _points.is_empty() or not _canvas.has_point(point):
		return
	_pointer = point
	_pointer_inside = true
	_last_pointer = point
	_drawing = point.distance_to(resume_point()) <= _tolerance*1.35
	_status = "沿轮廓慢慢描绘，可抬笔后从亮点接续" if _drawing else "请从发光圆点接着描绘"
	queue_redraw()

func continue_stroke(point: Vector2) -> void:
	_pointer = point
	_pointer_inside = true
	if not active or not _drawing or _finished:
		return
	# Sample the actual pointer line; teleports across the interior cannot earn a
	# long contour arc, even if their final coordinate lies on the opposite edge.
	var distance: float = _last_pointer.distance_to(point)
	var steps: int = maxi(1,ceili(distance/maxf(1.0,2.0*_unit)))
	var from := _last_pointer
	for i in range(1,steps+1):
		if not _drawing or _finished:
			break
		_accept_point(from.lerp(point,float(i)/float(steps)))
	_last_pointer = point
	queue_redraw()

func end_stroke() -> void:
	_drawing = false
	_touch_id = -1
	queue_redraw()

func _at_index(index: float) -> Vector2:
	var count: int = _points.size()-1
	var wrapped: float = fposmod(index,float(count))
	var lower := int(floor(wrapped))
	return _points[lower].lerp(_points[(lower+1)%count],wrapped-float(lower))

func _accept_point(point: Vector2) -> void:
	var count: int = _points.size()-1
	var signed_progress: float = float(_direction)*_progress
	var best_distance := INF
	var best_index := signed_progress
	# Restrict matching to nearby ordered segments: crossing fins or a folded tail
	# does not let the brush jump to an unrelated part of the outline.
	for segment in range(int(floor(signed_progress))-5,int(floor(signed_progress))+6):
		var start: Vector2 = _points[posmod(segment,count)]
		var finish: Vector2 = _points[posmod(segment+1,count)]
		var span := finish-start
		var fraction: float = clampf((point-start).dot(span)/maxf(.001,span.length_squared()),0,1)
		var nearest: Vector2 = start+span*fraction
		var error: float = nearest.distance_squared_to(point)
		if error < best_distance:
			best_distance = error
			best_index = float(segment)+fraction
	if best_distance > _tolerance*_tolerance:
		_drawing = false
		_status = "画笔离开轮廓了，从发光圆点继续即可"
		return
	if _direction == 0:
		if absf(best_index) < .25:
			return
		_direction = 1 if best_index > 0 else -1
	var candidate: float = best_index*float(_direction)
	if candidate > _progress:
		_progress = minf(float(count),candidate)
		_status = "轮廓完成 %d%% · 可抬笔接续" % roundi(completion_ratio()*100)
	if completion_ratio() >= COMPLETE_COVERAGE:
		_finished = true
		_drawing = false
		_status = "描绘完成 · 点击继续潜水，收录图鉴"
		# A separate click confirms completion and supplies the user gesture needed
		# by browser pointer lock before returning to mouse-controlled swimming.
		call_deferred("_finish")

func _finish() -> void:
	if active and _finished:
		_cancel_button.text = "完成 · 继续潜水"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		queue_redraw()

func confirm_completion() -> void:
	if active and _finished:
		completed.emit(species_id)

func _confirm_or_cancel() -> void:
	if _finished:
		confirm_completion()
	else:
		_cancel()

func _cancel() -> void:
	if active:
		end_stroke()
		cancelled.emit()

func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _touch_id < 0:
		if event.pressed:
			begin_stroke(event.position)
		else:
			end_stroke()
	elif event is InputEventMouseMotion and _touch_id < 0:
		_pointer = event.position
		_pointer_inside = true
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			continue_stroke(event.position)
		queue_redraw()
	elif event is InputEventScreenTouch:
		if event.pressed and _touch_id < 0:
			begin_stroke(event.position)
			_touch_id = event.index
		elif not event.pressed and event.index == _touch_id:
			end_stroke()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		continue_stroke(event.position)
	accept_event()

func _input(event: InputEvent) -> void:
	if active and event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel()

func _process(_delta: float) -> void:
	if not active:
		return
	# Only hide the arrow above the drawing canvas, leaving normal button cursors.
	var point := get_local_mouse_position()
	var desired: Input.MouseMode = Input.MOUSE_MODE_HIDDEN if not _finished and _canvas.has_point(point) and _touch_id < 0 else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != desired:
		Input.mouse_mode = desired

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and active:
		end_stroke()

func _draw() -> void:
	if not active:
		return
	draw_rect(Rect2(Vector2.ZERO,size),Color(.015,.07,.09,.88))
	var short: bool = size.y/_unit < 420
	var title := "描绘 · " + str(Catalog.entry(species_id).get("name","海洋生物"))
	var title_size: int = roundi((18 if short else 26)*_unit)
	draw_string(_font,Vector2(18,26 if short else 40)*_unit,title,HORIZONTAL_ALIGNMENT_LEFT,-1,title_size,CREAM)
	var percentage := "%d%%" % roundi(completion_ratio()*100)
	draw_string(_font,Vector2(size.x-72*_unit,(26 if short else 40)*_unit),percentage,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(18*_unit),INK)
	draw_string(_font,Vector2(18,49 if short else 71)*_unit,_status,HORIZONTAL_ALIGNMENT_LEFT,size.x-36*_unit,roundi(12*_unit),GUIDE)
	draw_rect(_canvas,Color(.05,.16,.20,.72))
	if _points.size() < 2:
		return
	draw_colored_polygon(_points,Color(.17,.34,.37,.4))
	draw_polyline(_points,GUIDE,2.2*_unit,true)
	if _progress > 0:
		var traced := PackedVector2Array([_points[0]])
		for i in range(1,int(floor(_progress))+1):
			traced.append(_at_index(float(i*_direction)))
		traced.append(resume_point())
		draw_polyline(traced,INK,4.0*_unit,true)
	var next := resume_point()
	draw_circle(next,7*_unit,Color(.67,.92,.82,.2))
	draw_arc(next,7*_unit,0,TAU,24,INK,1.5*_unit,true)
	draw_circle(next,3*_unit,INK)
	if not _finished and _pointer_inside and _canvas.has_point(_pointer) and _touch_id < 0:
		# A tiny angled brush: the tip is exactly the input coordinate.
		var tip := _pointer
		var end := tip+Vector2(13,-22)*_unit
		draw_line(tip+Vector2(3,-5)*_unit,end,Color("e5c294"),4*_unit,true)
		draw_line(tip,tip+Vector2(4,-7)*_unit,INK,2.5*_unit,true)
		draw_circle(tip,1.7*_unit,Color.WHITE)
