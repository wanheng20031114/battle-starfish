extends Control
class_name CurlingMinimap

var match_controller: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var area := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	draw_rect(area, Color("102939"), true)
	draw_rect(area, Color("6b9aa5"), false, 1.0)
	var center_y := area.position.y + area.size.y * 0.5
	draw_line(Vector2(area.position.x, center_y), Vector2(area.end.x, center_y), Color(0.7, 0.9, 0.92, 0.35), 1.0)
	for direction in [-1, 1]:
		var tee_x := remap(
			CurlingConstants.tee_position(direction).x,
			-CurlingConstants.HALF_SHEET_LENGTH_PX,
			CurlingConstants.HALF_SHEET_LENGTH_PX,
			area.position.x,
			area.end.x
		)
		draw_circle(Vector2(tee_x, center_y), 7.0, CurlingConstants.TEAM_BLUE_COLOR)
		draw_circle(Vector2(tee_x, center_y), 4.5, Color("edf8f9"))
		draw_circle(Vector2(tee_x, center_y), 2.3, CurlingConstants.TEAM_RED_COLOR)
	if match_controller == null or not match_controller.has_method("get_stone_states"):
		return
	for stone: Dictionary in match_controller.get_stone_states():
		if not bool(stone.get("in_play", false)):
			continue
		var world: Vector2 = stone.get("position", Vector2.ZERO)
		var point := Vector2(
			remap(world.x, -CurlingConstants.HALF_SHEET_LENGTH_PX, CurlingConstants.HALF_SHEET_LENGTH_PX, area.position.x, area.end.x),
			remap(world.y, -CurlingConstants.HALF_SHEET_WIDTH_PX, CurlingConstants.HALF_SHEET_WIDTH_PX, area.position.y, area.end.y)
		)
		var color := CurlingConstants.TEAM_RED_COLOR if int(stone.get("team", 0)) == CurlingConstants.TEAM_RED else CurlingConstants.TEAM_BLUE_COLOR
		draw_circle(point, 2.8, color)

