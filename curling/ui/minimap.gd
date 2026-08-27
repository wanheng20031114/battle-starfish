extends Control
class_name CurlingMinimap

const FRAME_INSET := 4.0
const SHEET_INSET := 7.0

var match_controller: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var frame_rect := Rect2(
		Vector2(FRAME_INSET, FRAME_INSET),
		size - Vector2(FRAME_INSET * 2.0, FRAME_INSET * 2.0)
	)
	draw_rect(frame_rect, CurlingConstants.NAVY_COLOR, true)
	draw_rect(frame_rect, Color("6b9aa5"), false, 1.0)
	var sheet_rect := minimap_sheet_rect()
	var world_scale := minimap_world_scale()
	draw_rect(sheet_rect, CurlingConstants.ICE_COLOR, true)
	for direction in [-1, 1]:
		_draw_end(direction, sheet_rect, world_scale)
	var center_start := _world_to_minimap(
		Vector2(-CurlingConstants.HALF_SHEET_LENGTH_PX, 0.0), sheet_rect, world_scale
	)
	var center_end := _world_to_minimap(
		Vector2(CurlingConstants.HALF_SHEET_LENGTH_PX, 0.0), sheet_rect, world_scale
	)
	draw_line(center_start, center_end, Color("9fcbd2"), 1.0)
	draw_rect(sheet_rect, Color("6caab4"), false, 1.0)
	_draw_stones(sheet_rect, world_scale)


func minimap_sheet_rect() -> Rect2:
	var available_size := size - Vector2(SHEET_INSET * 2.0, SHEET_INSET * 2.0)
	var world_scale := minf(
		available_size.x / CurlingConstants.SHEET_LENGTH_PX,
		available_size.y / CurlingConstants.SHEET_WIDTH_PX
	)
	var sheet_size := Vector2(CurlingConstants.SHEET_LENGTH_PX, CurlingConstants.SHEET_WIDTH_PX) * world_scale
	return Rect2((size - sheet_size) * 0.5, sheet_size)


func minimap_world_scale() -> float:
	return minimap_sheet_rect().size.x / CurlingConstants.SHEET_LENGTH_PX


func world_to_minimap(world: Vector2) -> Vector2:
	var sheet_rect := minimap_sheet_rect()
	return _world_to_minimap(world, sheet_rect, minimap_world_scale())


func _world_to_minimap(world: Vector2, sheet_rect: Rect2, world_scale: float) -> Vector2:
	return sheet_rect.position + Vector2(
		(world.x + CurlingConstants.HALF_SHEET_LENGTH_PX) * world_scale,
		(world.y + CurlingConstants.HALF_SHEET_WIDTH_PX) * world_scale
	)


func _draw_end(direction: int, sheet_rect: Rect2, world_scale: float) -> void:
	var tee_world := CurlingConstants.tee_position(direction)
	var tee := _world_to_minimap(tee_world, sheet_rect, world_scale)
	var house_colors := [Color("3b78bd"), Color("f8fbfc"), Color("df535c"), Color("f8fbfc")]
	for radius_index in range(CurlingConstants.HOUSE_RADII_PX.size()):
		draw_circle(
			tee,
			CurlingConstants.HOUSE_RADII_PX[radius_index] * world_scale,
			house_colors[radius_index]
		)
	var tee_top := _world_to_minimap(
		Vector2(tee_world.x, -CurlingConstants.HALF_SHEET_WIDTH_PX), sheet_rect, world_scale
	)
	var tee_bottom := _world_to_minimap(
		Vector2(tee_world.x, CurlingConstants.HALF_SHEET_WIDTH_PX), sheet_rect, world_scale
	)
	draw_line(tee_top, tee_bottom, Color("7e9da5"), 1.0)
	var hog_x := CurlingConstants.far_hog_x(direction)
	var hog_top := _world_to_minimap(
		Vector2(hog_x, -CurlingConstants.HALF_SHEET_WIDTH_PX), sheet_rect, world_scale
	)
	var hog_bottom := _world_to_minimap(
		Vector2(hog_x, CurlingConstants.HALF_SHEET_WIDTH_PX), sheet_rect, world_scale
	)
	draw_line(hog_top, hog_bottom, Color("d4535b"), 1.4)
	var back_x := tee_world.x + float(direction) * CurlingConstants.BACK_LINE_FROM_TEE_PX
	var back_top := _world_to_minimap(
		Vector2(back_x, -CurlingConstants.HALF_SHEET_WIDTH_PX), sheet_rect, world_scale
	)
	var back_bottom := _world_to_minimap(
		Vector2(back_x, CurlingConstants.HALF_SHEET_WIDTH_PX), sheet_rect, world_scale
	)
	draw_line(back_top, back_bottom, Color("7e9da5"), 1.0)
	var hack_x := CurlingConstants.hack_position(direction).x
	var hack_top := _world_to_minimap(Vector2(hack_x, -18.0), sheet_rect, world_scale)
	var hack_bottom := _world_to_minimap(Vector2(hack_x, 18.0), sheet_rect, world_scale)
	draw_line(hack_top, hack_bottom, Color("18374c"), 1.4)


func _draw_stones(sheet_rect: Rect2, world_scale: float) -> void:
	if match_controller == null or not match_controller.has_method("get_stone_states"):
		return
	for stone: Dictionary in match_controller.get_stone_states():
		if not bool(stone.get("in_play", false)):
			continue
		var world: Vector2 = stone.get("position", Vector2.ZERO)
		var point := _world_to_minimap(world, sheet_rect, world_scale)
		var color := CurlingConstants.TEAM_RED_COLOR if int(stone.get("team", 0)) == CurlingConstants.TEAM_RED else CurlingConstants.TEAM_BLUE_COLOR
		var stone_radius := maxf(1.05, CurlingConstants.STONE_RADIUS_PX * world_scale)
		draw_circle(point, stone_radius + 0.65, CurlingConstants.NAVY_COLOR)
		draw_circle(point, stone_radius, color)
