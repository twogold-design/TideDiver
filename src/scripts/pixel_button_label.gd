extends Node2D
const PixelText = preload("res://scripts/pixel_text.gd")
var button: Button
var font: Font
var normal_color: Color
var hover_color: Color
var disabled_color := Color("93a9ad")
var design_size := 18
var minimum_size := 16

func _ready() -> void:
	button.mouse_entered.connect(queue_redraw)
	button.mouse_exited.connect(queue_redraw)
	button.resized.connect(queue_redraw)
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var pixels: int = PixelText.font_size_for(self, design_size, minimum_size)
	var scale_y: float = PixelText.transform_for(self).get_scale().y
	var baseline := button.size * 0.5
	baseline.y += (font.get_ascent(pixels) - font.get_descent(pixels)) * 0.5 / scale_y
	var color := disabled_color if button.disabled else (hover_color if button.is_hovered() else normal_color)
	PixelText.draw(self, font, baseline, button.text, design_size, color, true, minimum_size)
