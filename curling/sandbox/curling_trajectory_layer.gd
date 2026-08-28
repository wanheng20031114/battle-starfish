extends Node2D
class_name CurlingSandboxTrajectoryLayer

var selected_record: CurlingShotRecord


func _ready() -> void:
	z_index = 4
	set_process(true)


func _process(_delta: float) -> void:
	if selected_record != null and selected_record.status == CurlingShotRecord.Status.MOVING:
		queue_redraw()


func show_record(record: CurlingShotRecord) -> void:
	selected_record = record
	queue_redraw()


func clear_record() -> void:
	selected_record = null
	queue_redraw()


func _draw() -> void:
	if selected_record == null or selected_record.trace.size() < 2:
		return
	var team_color := (
		CurlingConstants.TEAM_RED_COLOR
		if selected_record.team == CurlingConstants.TEAM_RED
		else CurlingConstants.TEAM_BLUE_COLOR
	)
	draw_polyline(selected_record.trace, Color(team_color, 0.78), 4.0, true)
	draw_circle(selected_record.trace[0], 7.0, Color("f8fbfc"))
	draw_circle(selected_record.trace[0], 4.0, team_color)
	var last_point := selected_record.trace[selected_record.trace.size() - 1]
	draw_circle(last_point, 6.0, Color(team_color, 0.88), false, 2.0, true)
