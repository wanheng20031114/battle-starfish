extends Control
class_name CurlingRemoteCursor

var player_id := 0
var nickname := ""
var personal_color := Color.WHITE
var team := CurlingConstants.TEAM_NONE
var mouse_down := false
var sweeping := false
var _from_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _target_time_ms := 0
var _tactical_visibility_allowed := true

@onready var name_label: Label = $Name


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	queue_redraw()


func configure(identity: Dictionary) -> void:
	player_id = int(identity.get("id", 0))
	nickname = str(identity.get("nickname", "玩家"))
	team = int(identity.get("team", CurlingConstants.TEAM_NONE))
	personal_color = identity.get("color", Color.WHITE)
	name_label.text = nickname
	name_label.add_theme_color_override("font_color", personal_color)
	visible = player_id > 0 and _tactical_visibility_allowed
	queue_redraw()


func set_target(screen_position: Vector2, pressed: bool, is_sweeping: bool) -> void:
	_from_position = position
	_target_position = screen_position
	_target_time_ms = Time.get_ticks_msec()
	mouse_down = pressed
	sweeping = is_sweeping
	visible = player_id > 0 and _tactical_visibility_allowed
	set_process(true)
	queue_redraw()


func set_tactical_visibility(allowed: bool) -> void:
	_tactical_visibility_allowed = allowed
	visible = player_id > 0 and allowed
	if not allowed:
		mouse_down = false
		sweeping = false
		set_process(false)
	queue_redraw()


func clear_identity() -> void:
	player_id = 0
	_tactical_visibility_allowed = true
	visible = false


func _process(_delta: float) -> void:
	var elapsed := float(Time.get_ticks_msec() - _target_time_ms)
	var weight := clampf(elapsed / float(CurlingConstants.CURSOR_INTERPOLATION_MS), 0.0, 1.0)
	position = _from_position.lerp(_target_position, weight)
	if weight >= 1.0:
		set_process(false)


func _draw() -> void:
	var team_color := (
		CurlingConstants.TEAM_RED_COLOR
		if team == CurlingConstants.TEAM_RED
		else CurlingConstants.TEAM_BLUE_COLOR
		if team == CurlingConstants.TEAM_BLUE
		else Color("8ca0ad")
	)
	if sweeping:
		draw_circle(Vector2.ZERO, 12.0, Color(personal_color, 0.22))
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 28, team_color, 3.0)
		draw_line(Vector2(-10, 5), Vector2(11, -5), personal_color, 5.0, true)
		draw_line(Vector2(-8, 9), Vector2(13, -1), Color("f4fbfc"), 2.0, true)
	else:
		var tip := Vector2.ZERO
		var points := PackedVector2Array([tip, Vector2(4, 19), Vector2(8, 12), Vector2(14, 18), Vector2(18, 14), Vector2(12, 8), Vector2(19, 4)])
		draw_colored_polygon(points, personal_color)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, team_color, 2.5)
	if mouse_down:
		draw_arc(Vector2.ZERO, 18.0, -PI * 0.85, PI * 0.15, 18, Color(1, 1, 1, 0.72), 2.0)
