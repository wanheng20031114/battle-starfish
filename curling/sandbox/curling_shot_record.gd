extends RefCounted
class_name CurlingShotRecord

enum Status {
	MOVING,
	STOPPED,
	OUT_OF_PLAY,
	REMOVED,
}

const SAMPLE_INTERVAL_SEC := 0.05
const TRACE_STEP_PX := 0.05 * CurlingConstants.PIXELS_PER_METER

var shot_id := 0
var team := CurlingConstants.TEAM_RED
var throw_direction := 1
var launch_origin := Vector2.ZERO
var launch_direction := Vector2.RIGHT
var launch_angle_degrees := 0.0
var aim_offset_degrees := 0.0
var power := 0.0
var initial_speed_mps := 0.0
var initial_spin_radps := 0.0
var launched_at_clock := ""
var status := Status.MOVING
var status_reason := "滑行中"
var stone: CurlingStone

var elapsed_sec := 0.0
var path_length_m := 0.0
var displacement_m := 0.0
var max_speed_mps := 0.0
var current_position := Vector2.ZERO
var final_position := Vector2.ZERO
var collision_count := 0
var last_collision_speed_mps := 0.0
var last_collision_impulse_ns := 0.0
var latest_telemetry: Dictionary = {}
var samples: Array[Dictionary] = []
var trace := PackedVector2Array()

var _last_position := Vector2.ZERO
var _sample_accumulator := 0.0


func begin(
	id: int,
	stone_node: CurlingStone,
	selected_team: int,
	direction_sign: int,
	aim_direction: Vector2,
	shot_power: float,
	spin_radps: float
) -> void:
	shot_id = id
	stone = stone_node
	team = selected_team
	throw_direction = 1 if direction_sign >= 0 else -1
	launch_origin = stone.global_position
	launch_direction = aim_direction.normalized()
	launch_angle_degrees = rad_to_deg(launch_direction.angle())
	aim_offset_degrees = rad_to_deg(
		Vector2(float(throw_direction), 0.0).angle_to(launch_direction)
	)
	power = shot_power
	initial_speed_mps = CurlingConstants.throw_speed_for_power(power)
	initial_spin_radps = spin_radps
	launched_at_clock = Time.get_datetime_string_from_system(false, true).replace("T", " ")
	status = Status.MOVING
	status_reason = "滑行中"
	current_position = launch_origin
	final_position = launch_origin
	_last_position = launch_origin
	trace.append(launch_origin)
	_capture_sample(true)


func update_from_stone(delta: float) -> void:
	if stone == null or not is_instance_valid(stone) or status != Status.MOVING:
		return
	elapsed_sec += delta
	current_position = stone.global_position
	final_position = current_position
	path_length_m += _last_position.distance_to(current_position) / CurlingConstants.PIXELS_PER_METER
	displacement_m = launch_origin.distance_to(current_position) / CurlingConstants.PIXELS_PER_METER
	_last_position = current_position
	latest_telemetry = stone.get_physics_telemetry()
	max_speed_mps = maxf(max_speed_mps, float(latest_telemetry.get("speed_mps", 0.0)))
	var collision_impulse := float(latest_telemetry.get("collision_impulse_ns", 0.0))
	if collision_impulse > 0.00001:
		last_collision_impulse_ns = collision_impulse
	if trace.is_empty() or trace[trace.size() - 1].distance_to(current_position) >= TRACE_STEP_PX:
		trace.append(current_position)
	_sample_accumulator += delta
	if _sample_accumulator >= SAMPLE_INTERVAL_SEC:
		_sample_accumulator = fmod(_sample_accumulator, SAMPLE_INTERVAL_SEC)
		_capture_sample(false)


func mark_collision(relative_speed_px: float) -> void:
	collision_count += 1
	last_collision_speed_mps = relative_speed_px / CurlingConstants.PIXELS_PER_METER


func resume_motion(reason: String = "碰撞后滑行") -> void:
	if not is_on_field():
		return
	status = Status.MOVING
	status_reason = reason
	_last_position = stone.global_position


func mark_stopped(reason: String = "已停稳") -> void:
	if stone != null and is_instance_valid(stone):
		current_position = stone.global_position
		final_position = current_position
		latest_telemetry = stone.get_physics_telemetry()
	if trace.is_empty() or not trace[trace.size() - 1].is_equal_approx(final_position):
		trace.append(final_position)
	_capture_sample(true)
	status = Status.STOPPED
	status_reason = reason


func finish(next_status: int, reason: String) -> void:
	if stone != null and is_instance_valid(stone):
		current_position = stone.global_position
		final_position = current_position
		latest_telemetry = stone.get_physics_telemetry()
	if trace.is_empty() or not trace[trace.size() - 1].is_equal_approx(final_position):
		trace.append(final_position)
	_capture_sample(true)
	status = next_status
	status_reason = reason
	stone = null


func is_on_field() -> bool:
	return stone != null and is_instance_valid(stone) and stone.in_play


func status_text() -> String:
	match status:
		Status.MOVING: return "滑行中"
		Status.STOPPED: return "已停稳"
		Status.OUT_OF_PLAY: return "已出界"
		Status.REMOVED: return "已移除"
		_: return "未知"


func team_text() -> String:
	return CurlingConstants.team_name(team)


func direction_text() -> String:
	return "左 → 右" if throw_direction > 0 else "右 → 左"


func _capture_sample(force: bool) -> void:
	if not force and not samples.is_empty() and absf(float(samples[-1]["time_sec"]) - elapsed_sec) < 0.001:
		return
	var telemetry := latest_telemetry
	if telemetry.is_empty() and stone != null and is_instance_valid(stone):
		telemetry = stone.get_physics_telemetry()
		latest_telemetry = telemetry
	samples.append({
		"time_sec": elapsed_sec,
		"position": current_position,
		"speed_mps": float(telemetry.get("speed_mps", initial_speed_mps if elapsed_sec <= 0.0 else 0.0)),
		"angular_velocity_radps": float(telemetry.get("angular_velocity_radps", initial_spin_radps if elapsed_sec <= 0.0 else 0.0)),
		"drag_force_n": float(telemetry.get("drag_force_n", 0.0)),
		"curl_force_n": float(telemetry.get("curl_force_n", 0.0)),
		"heat": float(telemetry.get("heat", 0.0)),
	})
