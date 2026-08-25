extends Node2D
class_name CurlingSheet


func _ready() -> void:
	z_index = 0
	queue_redraw()


func _draw() -> void:
	var half_length := CurlingConstants.HALF_SHEET_LENGTH_PX
	var half_width := CurlingConstants.HALF_SHEET_WIDTH_PX
	# 场外深色平台让狭长冰面成为整场唯一视觉主体。
	draw_rect(Rect2(Vector2(-half_length - 90.0, -half_width - 65.0), Vector2(CurlingConstants.SHEET_LENGTH_PX + 180.0, CurlingConstants.SHEET_WIDTH_PX + 130.0)), Color("0a1825"), true)
	draw_rect(Rect2(Vector2(-half_length, -half_width), Vector2(CurlingConstants.SHEET_LENGTH_PX, CurlingConstants.SHEET_WIDTH_PX)), CurlingConstants.ICE_COLOR, true)
	for stripe_index in range(19):
		var x := -half_length + float(stripe_index) * CurlingConstants.SHEET_LENGTH_PX / 18.0
		draw_rect(Rect2(Vector2(x, -half_width), Vector2(CurlingConstants.SHEET_LENGTH_PX / 36.0, CurlingConstants.SHEET_WIDTH_PX)), Color(0.72, 0.91, 0.93, 0.09), true)
	_draw_end(-1)
	_draw_end(1)
	draw_line(Vector2(-half_length, 0), Vector2(half_length, 0), Color("9fcbd2"), 1.3)
	draw_line(Vector2(-half_length, -half_width), Vector2(half_length, -half_width), Color("6caab4"), 3.0)
	draw_line(Vector2(-half_length, half_width), Vector2(half_length, half_width), Color("6caab4"), 3.0)


func _draw_end(direction: int) -> void:
	var tee := CurlingConstants.tee_position(direction)
	var outer := CurlingConstants.HOUSE_RADII_PX[0]
	draw_circle(tee, outer, Color("3b78bd"))
	draw_circle(tee, CurlingConstants.HOUSE_RADII_PX[1], Color("f8fbfc"))
	draw_circle(tee, CurlingConstants.HOUSE_RADII_PX[2], Color("df535c"))
	draw_circle(tee, CurlingConstants.HOUSE_RADII_PX[3], Color("f8fbfc"))
	draw_line(Vector2(tee.x, -CurlingConstants.HALF_SHEET_WIDTH_PX), Vector2(tee.x, CurlingConstants.HALF_SHEET_WIDTH_PX), Color("7e9da5"), 2.0)
	var hog_x := CurlingConstants.far_hog_x(direction)
	draw_line(Vector2(hog_x, -CurlingConstants.HALF_SHEET_WIDTH_PX), Vector2(hog_x, CurlingConstants.HALF_SHEET_WIDTH_PX), Color("d4535b"), 8.0)
	var back_x := tee.x + float(direction) * CurlingConstants.BACK_LINE_FROM_TEE_PX
	draw_line(Vector2(back_x, -CurlingConstants.HALF_SHEET_WIDTH_PX), Vector2(back_x, CurlingConstants.HALF_SHEET_WIDTH_PX), Color("7e9da5"), 2.0)
	var hack_x := -float(direction) * (CurlingConstants.TEE_FROM_CENTER_PX + CurlingConstants.HACK_FROM_TEE_PX)
	draw_line(Vector2(hack_x, -18.0), Vector2(hack_x, 18.0), Color("18374c"), 5.0)

