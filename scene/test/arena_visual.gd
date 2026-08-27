@tool
extends Node2D

const CANVAS_SIZE := Vector2(1280.0, 720.0)
const ARENA_RECT := Rect2(36.0, 88.0, 860.0, 566.0)
const INNER_RECT := Rect2(58.0, 108.0, 816.0, 526.0)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color("061018"))
	draw_circle(Vector2(120.0, 675.0), 420.0, Color("081923"))
	draw_circle(Vector2(850.0, 40.0), 360.0, Color("0a1821"))
	draw_rect(ARENA_RECT, Color("091720"), true)

	for x in range(58, 875, 64):
		draw_line(Vector2(x, INNER_RECT.position.y), Vector2(x, INNER_RECT.end.y), Color(0.12, 0.38, 0.43, 0.075), 1.0)
	for y in range(122, 635, 64):
		draw_line(Vector2(INNER_RECT.position.x, y), Vector2(INNER_RECT.end.x, y), Color(0.12, 0.38, 0.43, 0.075), 1.0)

	var arena_center := INNER_RECT.get_center()
	draw_line(Vector2(arena_center.x, INNER_RECT.position.y), Vector2(arena_center.x, INNER_RECT.end.y), Color(0.24, 0.78, 0.78, 0.1), 1.0)
	draw_line(Vector2(INNER_RECT.position.x, arena_center.y), Vector2(INNER_RECT.end.x, arena_center.y), Color(0.24, 0.78, 0.78, 0.1), 1.0)
	for radius in [80.0, 160.0, 240.0]:
		draw_arc(arena_center, radius, 0.0, TAU, 96, Color(0.18, 0.66, 0.68, 0.065), 1.0, true)

	draw_rect(ARENA_RECT, Color("18343d"), false, 2.0)
	draw_rect(Rect2(44.0, 96.0, 844.0, 550.0), Color(0.22, 0.74, 0.73, 0.16), false, 1.0)

	var tick_color := Color(0.30, 0.91, 0.86, 0.72)
	var corners := [
		Vector2(36.0, 88.0), Vector2(896.0, 88.0),
		Vector2(36.0, 654.0), Vector2(896.0, 654.0),
	]
	for corner in corners:
		var horizontal_direction := 1.0 if corner.x < 400.0 else -1.0
		var vertical_direction := 1.0 if corner.y < 300.0 else -1.0
		draw_line(corner, corner + Vector2(horizontal_direction * 24.0, 0.0), tick_color, 3.0)
		draw_line(corner, corner + Vector2(0.0, vertical_direction * 24.0), tick_color, 3.0)
