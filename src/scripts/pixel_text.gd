extends RefCounted
## Render UI glyphs at their final pixel size instead of scaling a design-size bitmap.
static var pixel_ratio: float = 1.0

static func transform_for(item: CanvasItem) -> Transform2D:
	return item.get_viewport_transform() * item.get_global_transform()

static func font_size_for(item: CanvasItem, design_size: int, minimum: int = 14) -> int:
	var scale_y: float = transform_for(item).get_scale().y
	return maxi(roundi(design_size * scale_y), ceili(minimum * pixel_ratio))

static func draw(item: CanvasItem, face: Font, pos: Vector2, text: String, design_size: int, color: Color, centered: bool = false, minimum: int = 14) -> void:
	var transform: Transform2D = transform_for(item)
	var pixels: int = font_size_for(item, design_size, minimum)
	var baseline: Vector2 = transform * pos
	if centered:
		baseline.x -= face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x * 0.5
	# Cancel the viewport's fractional UI scale for the glyphs only. Panels and hitboxes
	# keep their design coordinates; glyphs use whole pixels and explicit 1:1 sampling.
	item.draw_set_transform_matrix(transform.affine_inverse())
	face.draw_string(item.get_canvas_item(), baseline.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color, TextServer.JUSTIFICATION_KASHIDA | TextServer.JUSTIFICATION_WORD_BOUND, TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL, 1.0)
	item.draw_set_transform_matrix(Transform2D.IDENTITY)
