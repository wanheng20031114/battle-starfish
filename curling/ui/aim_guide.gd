extends Node2D
class_name CurlingAimGuide

const STRAIGHT_LENGTH_PX := 420.0
const CURVE_FORWARD_PX := 178.0
const CURVE_MAX_OFFSET_PX := 73.0
const CURVE_SEGMENTS := 32
const ARROW_FORWARD_PX := 108.0
const ARROW_BASE_LENGTH_PX := 22.0
const LABEL_WIDTH_PX := 150.0

var preview_active := false
var preview_power := 0.0
var preview_spin_radps := 0.0
var preview_aim_offset_degrees := 0.0

var _start := Vector2.ZERO
var _direction := Vector2.RIGHT
var _lateral := Vector2.DOWN
var _team_color := Color.WHITE
var _straight_start := Vector2.ZERO
var _straight_end := Vector2.ZERO
var _curve_points := PackedVector2Array()
var _arrow_start := Vector2.ZERO
var _arrow_tip := Vector2.ZERO
var _spin_guide_degrees := 0.0


func _ready() -> void:
	z_index = 6
	hide_preview()


func show_preview(
	start: Vector2,
	aim_direction: Vector2,
	power: float,
	spin_radps: float,
	team_color: Color,
	aim_offset_degrees: float
) -> void:
	if not aim_direction.is_finite() or aim_direction.length_squared() < 0.9:
		hide_preview()
		return
	preview_active = true
	preview_power = clampf(power, 0.0, 1.0)
	preview_spin_radps = clampf(
		spin_radps,
		-CurlingConstants.MAX_SPIN_RADPS,
		CurlingConstants.MAX_SPIN_RADPS
	)
	preview_aim_offset_degrees = aim_offset_degrees
	_start = start
	_direction = aim_direction.normalized()
	_team_color = team_color
	_rebuild_geometry()
	visible = true
	queue_redraw()


func hide_preview() -> void:
	preview_active = false
	visible = false
	_curve_points.clear()
	queue_redraw()


func get_debug_geometry() -> Dictionary:
	return {
		"active": preview_active,
		"straight_start": _straight_start,
		"straight_end": _straight_end,
		"curve_points": _curve_points.duplicate(),
		"arrow_start": _arrow_start,
		"arrow_tip": _arrow_tip,
		"arrow_direction": _arrow_start.direction_to(_arrow_tip),
		"guide_angle_degrees": _spin_guide_degrees,
	}


func _rebuild_geometry() -> void:
	_straight_start = _start + _direction * (CurlingConstants.STONE_RADIUS_PX + 7.0)
	_straight_end = _start + _direction * STRAIGHT_LENGTH_PX
	_curve_points.clear()
	_arrow_start = _start
	_arrow_tip = _start
	_spin_guide_degrees = 0.0
	var spin_ratio := clampf(
		absf(preview_spin_radps) / CurlingConstants.MAX_SPIN_RADPS,
		0.0,
		1.0
	)
	if spin_ratio <= 0.005:
		return
	var spin_sign := signf(preview_spin_radps)
	_lateral = _direction.rotated(spin_sign * PI * 0.5)
	# 只用于旋向识别，平方根放大低旋转值；它不是落点预测。
	var curve_offset := CURVE_MAX_OFFSET_PX * sqrt(spin_ratio)
	var control := _straight_start + _direction * (CURVE_FORWARD_PX * 0.53) + _lateral * (curve_offset * 0.10)
	var curve_end := _straight_start + _direction * CURVE_FORWARD_PX + _lateral * curve_offset
	for index in range(CURVE_SEGMENTS + 1):
		var t := float(index) / float(CURVE_SEGMENTS)
		var inverse := 1.0 - t
		_curve_points.append(
			inverse * inverse * _straight_start
			+ 2.0 * inverse * t * control
			+ t * t * curve_end
		)
	var arrow_anchor := _start + _direction * ARROW_FORWARD_PX + _lateral * (curve_offset * 0.18)
	var arrow_length := ARROW_BASE_LENGTH_PX + spin_ratio * 10.0
	_arrow_start = arrow_anchor - _lateral * 3.0
	_arrow_tip = arrow_anchor + _lateral * arrow_length
	_spin_guide_degrees = spin_sign * rad_to_deg(atan2(curve_offset, CURVE_FORWARD_PX))


func _draw() -> void:
	if not preview_active:
		return
	var line_shadow := Color(0.03, 0.12, 0.15, 0.48)
	var line_color := Color(_team_color, 0.82)
	draw_line(_straight_start, _straight_end, line_shadow, 3.2, true)
	draw_line(_straight_start, _straight_end, line_color, 1.25, true)
	draw_circle(_straight_end, 2.8, Color(_team_color, 0.92))
	_draw_centered_text(
		"瞄准 %+0.02f°" % preview_aim_offset_degrees,
		_straight_end + Vector2(0.0, -13.0),
		Color(_team_color.lightened(0.24), 0.98)
	)
	if _curve_points.size() < 2:
		return
	for index in range(_curve_points.size() - 1):
		if index % 3 != 2:
			draw_line(
				_curve_points[index],
				_curve_points[index + 1],
				Color(_team_color.lightened(0.18), 0.88),
				2.15,
				true
			)
	draw_line(_arrow_start, _arrow_tip, line_shadow, 4.0, true)
	draw_line(_arrow_start, _arrow_tip, Color(_team_color.lightened(0.28), 0.96), 2.3, true)
	var arrow_back := _arrow_tip - _lateral * 9.0
	draw_line(_arrow_tip, arrow_back + _direction * 5.5, Color(_team_color.lightened(0.28), 0.96), 2.3, true)
	draw_line(_arrow_tip, arrow_back - _direction * 5.5, Color(_team_color.lightened(0.28), 0.96), 2.3, true)
	var label_offset_y := 16.0 if _lateral.y >= 0.0 else -11.0
	_draw_centered_text(
		"旋向示意 %+0.1f°" % _spin_guide_degrees,
		_arrow_tip + Vector2(0.0, label_offset_y),
		Color(_team_color.lightened(0.34), 1.0)
	)


func _draw_centered_text(text: String, center: Vector2, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var baseline := center + Vector2(-LABEL_WIDTH_PX * 0.5, 4.5)
	for offset in [Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0)]:
		draw_string(
			font,
			baseline + offset,
			text,
			HORIZONTAL_ALIGNMENT_CENTER,
			LABEL_WIDTH_PX,
			13,
			Color(0.03, 0.12, 0.15, 0.88)
		)
	draw_string(
		font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		LABEL_WIDTH_PX,
		13,
		color
	)
