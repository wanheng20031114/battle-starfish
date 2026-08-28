extends RigidBody2D
class_name CurlingStone

signal stone_collision(stone_id: int, other_id: int, impulse_hint: float)

@export var stone_id := 0
@export_enum("Red:1", "Blue:2") var team := CurlingConstants.TEAM_RED

var owner_player_id := 0
var owner_color := Color.WHITE
var in_play := false
var active_delivered_stone := false
var authoritative := true
var heat_grid: CurlingHeatGrid
var remote_target_position := Vector2.ZERO
var remote_target_rotation := 0.0
var remote_target_velocity := Vector2.ZERO
var inspection_selected := false
var guard_protected := false
var _remote_samples: Array[Dictionary] = []
var _in_play_collision_layer := 1
var _in_play_collision_mask := 1
var _telemetry_heat := 0.0
var _telemetry_drag_acceleration_mps2 := 0.0
var _telemetry_drag_force_n := 0.0
var _telemetry_curl_acceleration_mps2 := 0.0
var _telemetry_curl_force_n := 0.0
var _telemetry_collision_impulse_ns := 0.0

@onready var slide_time_marker: Node2D = $SlideTimeMarker
@onready var slide_time_label: Label = $SlideTimeMarker/Time
@onready var protection_overlay: Polygon2D = $ProtectionOverlay


func _ready() -> void:
	# 场景预先放置16颗壶。未出手的壶不可见，也必须完全退出碰撞；
	# freeze只会把刚体视作静态物体，本身不会禁用碰撞。
	_in_play_collision_layer = collision_layer
	_in_play_collision_mask = collision_mask
	_set_collision_active(in_play)
	mass = CurlingConstants.STONE_MASS_KG
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = CurlingConstants.ANGULAR_DAMP_PER_SEC
	contact_monitor = true
	max_contacts_reported = 16
	body_entered.connect(_on_body_entered)
	protection_overlay.set_instance_shader_parameter(
		"phase_offset",
		fmod(float(stone_id) * 0.173, 1.0)
	)
	_sync_guard_protection_visual()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if not authoritative and in_play:
		_render_buffered_remote_state()
	_update_slide_time_marker()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_telemetry_collision_impulse_ns = 0.0
	for contact_index in range(state.get_contact_count()):
		_telemetry_collision_impulse_ns += (
			state.get_contact_impulse(contact_index).length()
			/ CurlingConstants.PIXELS_PER_METER
		)
	if not authoritative or not in_play or freeze:
		_reset_force_telemetry()
		return
	var velocity := state.linear_velocity
	var speed := velocity.length()
	if speed <= CurlingConstants.STOP_SPEED_PXPS:
		_reset_force_telemetry()
		return
	var direction := velocity / speed
	var heat := 0.0
	if active_delivered_stone and heat_grid != null:
		heat = heat_grid.sample_heat(state.transform.origin)
	var drag_acceleration_pxps2 := (
		CurlingConstants.BASE_DRAG_PXPS2
		* (1.0 - CurlingConstants.SWEEP_DRAG_REDUCTION * heat)
	)
	# 以速度相关的阻尼系数让Godot原生线性阻尼产生近似恒定的冰面滚阻；
	# 满热时只降低该原生阻尼，不自行改写速度积分。
	linear_damp = drag_acceleration_pxps2 / maxf(speed, CurlingConstants.STOP_SPEED_PXPS)
	_telemetry_heat = heat
	_telemetry_drag_acceleration_mps2 = drag_acceleration_pxps2 / CurlingConstants.PIXELS_PER_METER
	_telemetry_drag_force_n = mass * _telemetry_drag_acceleration_mps2

	# Curl只旋转速度方向，不改变速度大小；停止时间和总路径仍由初速、阻尼与擦冰热量决定。
	# 曲线路径沿原瞄准方向的投影会略短，这不是额外阻力。
	var speed_mps := speed / CurlingConstants.PIXELS_PER_METER
	var low_speed_factor := 0.25 + 0.75 * clampf(1.0 - speed_mps / CurlingConstants.MAX_THROW_SPEED_MPS, 0.0, 1.0)
	var curl_multiplier := 1.0 - CurlingConstants.SWEEP_CURL_FORCE_REDUCTION * heat
	var curl_acceleration := (
		CurlingConstants.CURL_ACCEL_PER_RAD_PXPS2
		* state.angular_velocity
		* low_speed_factor
		* curl_multiplier
	)
	_telemetry_curl_acceleration_mps2 = curl_acceleration / CurlingConstants.PIXELS_PER_METER
	_telemetry_curl_force_n = mass * _telemetry_curl_acceleration_mps2
	var turn_radians := curl_acceleration / maxf(speed, CurlingConstants.STOP_SPEED_PXPS) * state.step
	state.linear_velocity = direction.rotated(turn_radians) * speed


func prepare_for_delivery(position: Vector2, owner_id: int, player_color: Color) -> void:
	_remote_samples.clear()
	_reset_physics_telemetry()
	owner_player_id = owner_id
	owner_color = player_color
	set_guard_protected(false)
	in_play = true
	active_delivered_stone = true
	visible = true
	# 瞄准阶段保持冻结；launch() 才解除冻结并交给原生物理积分。
	freeze = true
	sleeping = false
	global_position = position
	rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	linear_damp = 0.0
	_set_collision_active(true)
	queue_redraw()


func launch(direction: Vector2, speed_mps: float, spin_radps: float) -> void:
	if not authoritative or not in_play or direction.length_squared() < 0.99:
		return
	var speed_pxps := speed_mps * CurlingConstants.PIXELS_PER_METER
	# RigidBody2D会保留上一轮运行时写入的阻尼；复用冰壶必须以本次初速重新标定。
	linear_damp = CurlingConstants.BASE_DRAG_PXPS2 / maxf(speed_pxps, CurlingConstants.STOP_SPEED_PXPS)
	freeze = false
	sleeping = false
	linear_velocity = direction.normalized() * speed_pxps
	angular_velocity = clampf(spin_radps, -CurlingConstants.MAX_SPIN_RADPS, CurlingConstants.MAX_SPIN_RADPS)


func remove_from_play() -> void:
	_remote_samples.clear()
	_reset_physics_telemetry()
	in_play = false
	active_delivered_stone = false
	set_guard_protected(false)
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	linear_damp = 0.0
	freeze = true
	visible = false
	slide_time_marker.visible = false
	_set_collision_active(false)


func freeze_at_rest() -> void:
	_reset_physics_telemetry()
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	linear_damp = 0.0
	sleeping = true
	freeze = true
	active_delivered_stone = false
	slide_time_marker.visible = false


func enable_for_shot() -> void:
	if not authoritative or not in_play:
		return
	linear_damp = 0.0
	_set_collision_active(true)
	freeze = false
	sleeping = true
	active_delivered_stone = false


func restore_authoritative_state(snapshot: Dictionary) -> void:
	_remote_samples.clear()
	_reset_physics_telemetry()
	in_play = bool(snapshot.get("in_play", false))
	visible = in_play
	_sync_guard_protection_visual()
	freeze = true
	var restored_position: Vector2 = snapshot.get("position", Vector2.ZERO)
	var restored_rotation := float(snapshot.get("angle", 0.0))
	var restored_velocity: Vector2 = snapshot.get("velocity", Vector2.ZERO)
	var restored_angular_velocity := float(snapshot.get("angular_velocity", 0.0))
	global_position = restored_position
	rotation = restored_rotation
	linear_velocity = restored_velocity
	angular_velocity = restored_angular_velocity
	linear_damp = 0.0
	# FGZ回滚属于规则纠正，可直接同步刚体状态；下一手开始时再统一解冻场内壶。
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(restored_rotation, restored_position))
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, restored_velocity)
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, restored_angular_velocity)
	_set_collision_active(in_play)
	sleeping = true
	active_delivered_stone = false


func apply_remote_snapshot(snapshot: Dictionary, force_snap: bool, is_active_stone: bool = false) -> void:
	var next_in_play := bool(snapshot.get("in_play", false))
	if not next_in_play:
		remove_from_play()
		return
	in_play = true
	visible = true
	_sync_guard_protection_visual()
	freeze = true
	_set_collision_active(true)
	var receive_ms := Time.get_ticks_msec()
	var next_position: Vector2 = snapshot.get("position", global_position)
	var next_rotation := float(snapshot.get("angle", rotation))
	var next_velocity: Vector2 = snapshot.get("velocity", Vector2.ZERO)
	var next_angular_velocity := float(snapshot.get("angular_velocity", 0.0))
	active_delivered_stone = is_active_stone and next_velocity.length() > CurlingConstants.STOP_SPEED_PXPS
	var discontinuity := _remote_samples.is_empty()
	if not _remote_samples.is_empty():
		var previous: Dictionary = _remote_samples.back()
		var elapsed := maxf(0.0, float(receive_ms - int(previous["receive_ms"])) / 1000.0)
		var predicted := (previous["position"] as Vector2) + (previous["velocity"] as Vector2) * elapsed
		var position_error := predicted.distance_to(next_position)
		var velocity_change := (previous["velocity"] as Vector2).distance_to(next_velocity)
		discontinuity = position_error >= CurlingConstants.SNAP_CORRECTION_DISTANCE_PX or velocity_change >= 50.0
	var sample := {
		"receive_ms": receive_ms,
		"position": next_position,
		"rotation": next_rotation,
		"velocity": next_velocity,
		"angular_velocity": next_angular_velocity,
		"active": is_active_stone,
	}
	if force_snap or discontinuity:
		global_position = next_position
		rotation = next_rotation
		_remote_samples.clear()
	_remote_samples.append(sample)
	while _remote_samples.size() > 16:
		_remote_samples.pop_front()
	remote_target_position = next_position
	remote_target_rotation = next_rotation
	remote_target_velocity = next_velocity


func estimated_remaining_slide_time() -> float:
	var velocity_px := linear_velocity if authoritative else remote_target_velocity
	var speed_mps := velocity_px.length() / CurlingConstants.PIXELS_PER_METER
	var heat := heat_grid.sample_heat(global_position) if heat_grid != null else 0.0
	return estimate_remaining_slide_time(speed_mps, heat)


static func estimate_remaining_slide_time(speed_mps: float, heat: float) -> float:
	if speed_mps <= CurlingConstants.STOP_SPEED_MPS:
		return 0.0
	var effective_drag := CurlingConstants.BASE_DRAG_MPS2 * (
		1.0 - CurlingConstants.SWEEP_DRAG_REDUCTION * clampf(heat, 0.0, 1.0)
	)
	return (speed_mps - CurlingConstants.STOP_SPEED_MPS) / effective_drag


func _update_slide_time_marker() -> void:
	slide_time_marker.global_position = global_position
	slide_time_marker.global_rotation = 0.0
	var velocity_px := linear_velocity if authoritative else remote_target_velocity
	var speed_mps := velocity_px.length() / CurlingConstants.PIXELS_PER_METER
	var show_marker := (
		in_play
		and active_delivered_stone
		and speed_mps > CurlingConstants.STOP_SPEED_MPS
	)
	slide_time_marker.visible = show_marker
	if not show_marker:
		return
	var heat := heat_grid.sample_heat(global_position) if heat_grid != null else 0.0
	var remaining := estimate_remaining_slide_time(speed_mps, heat)
	slide_time_label.text = "%.1fs" % remaining
	slide_time_label.add_theme_color_override("font_color", CurlingConstants.NAVY_COLOR)


func _render_buffered_remote_state() -> void:
	if _remote_samples.is_empty():
		return
	var render_ms := Time.get_ticks_msec() - CurlingConstants.INTERPOLATION_DELAY_MS
	while _remote_samples.size() >= 2 and int(_remote_samples[1]["receive_ms"]) <= render_ms:
		_remote_samples.pop_front()
	var first: Dictionary = _remote_samples[0]
	if _remote_samples.size() >= 2:
		var second: Dictionary = _remote_samples[1]
		var duration := maxi(1, int(second["receive_ms"]) - int(first["receive_ms"]))
		var weight := clampf(float(render_ms - int(first["receive_ms"])) / float(duration), 0.0, 1.0)
		global_position = (first["position"] as Vector2).lerp(second["position"] as Vector2, weight)
		rotation = lerp_angle(float(first["rotation"]), float(second["rotation"]), weight)
		return
	global_position = first["position"]
	rotation = float(first["rotation"])
	if bool(first.get("active", false)) and render_ms > int(first["receive_ms"]):
		var extrapolation_ms := mini(render_ms - int(first["receive_ms"]), CurlingConstants.ACTIVE_EXTRAPOLATION_MAX_MS)
		var extrapolation_sec := float(extrapolation_ms) / 1000.0
		global_position += (first["velocity"] as Vector2) * extrapolation_sec
		rotation += float(first["angular_velocity"]) * extrapolation_sec


func export_state() -> Dictionary:
	return {
		"id": stone_id,
		"team": team,
		"owner_player_id": owner_player_id,
		"guard_protected": guard_protected,
		"in_play": in_play,
		"position": global_position,
		"velocity": linear_velocity,
		"angle": rotation,
		"angular_velocity": angular_velocity,
		"moving": in_play and linear_velocity.length() > CurlingConstants.STOP_SPEED_PXPS,
		"sleeping": sleeping,
	}


func get_physics_telemetry() -> Dictionary:
	var velocity_px := linear_velocity if authoritative else remote_target_velocity
	var velocity_mps := velocity_px / CurlingConstants.PIXELS_PER_METER
	return {
		"speed_mps": velocity_mps.length(),
		"velocity_mps": velocity_mps,
		"angular_velocity_radps": angular_velocity,
		"heat": _telemetry_heat,
		"linear_damp_per_sec": linear_damp,
		"drag_acceleration_mps2": _telemetry_drag_acceleration_mps2,
		"drag_force_n": _telemetry_drag_force_n,
		"curl_acceleration_mps2": _telemetry_curl_acceleration_mps2,
		"curl_force_n": _telemetry_curl_force_n,
		"collision_impulse_ns": _telemetry_collision_impulse_ns,
		"remaining_sec": estimated_remaining_slide_time(),
	}


func set_inspection_selected(selected: bool) -> void:
	if inspection_selected == selected:
		return
	inspection_selected = selected
	queue_redraw()


func set_guard_protected(protected: bool) -> void:
	guard_protected = protected
	_sync_guard_protection_visual()


func _sync_guard_protection_visual() -> void:
	if protection_overlay != null:
		protection_overlay.visible = guard_protected and in_play


func _on_body_entered(body: Node) -> void:
	if in_play and body is CurlingStone:
		var other := body as CurlingStone
		if not other.in_play:
			return
		stone_collision.emit(stone_id, other.stone_id, linear_velocity.distance_to(other.linear_velocity))


func _set_collision_active(enabled: bool) -> void:
	collision_layer = _in_play_collision_layer if enabled else 0
	collision_mask = _in_play_collision_mask if enabled else 0


func _reset_force_telemetry() -> void:
	_telemetry_heat = 0.0
	_telemetry_drag_acceleration_mps2 = 0.0
	_telemetry_drag_force_n = 0.0
	_telemetry_curl_acceleration_mps2 = 0.0
	_telemetry_curl_force_n = 0.0


func _reset_physics_telemetry() -> void:
	_reset_force_telemetry()
	_telemetry_collision_impulse_ns = 0.0


func _draw() -> void:
	var base_color := CurlingConstants.TEAM_RED_COLOR if team == CurlingConstants.TEAM_RED else CurlingConstants.TEAM_BLUE_COLOR
	draw_circle(Vector2.ZERO, CurlingConstants.STONE_RADIUS_PX, Color("253744"))
	draw_circle(Vector2.ZERO, CurlingConstants.STONE_RADIUS_PX - 1.5, base_color)
	draw_arc(Vector2.ZERO, CurlingConstants.STONE_RADIUS_PX - 4.0, 0.0, TAU, 32, Color(1, 1, 1, 0.38), 1.5)
	if team == CurlingConstants.TEAM_RED:
		draw_line(Vector2(-8, 7), Vector2(8, -7), Color(1, 1, 1, 0.36), 2.0)
	else:
		draw_line(Vector2(-7, 0), Vector2(7, 0), Color(1, 1, 1, 0.34), 2.0)
		draw_line(Vector2(0, -7), Vector2(0, 7), Color(1, 1, 1, 0.34), 2.0)
	draw_circle(Vector2.ZERO, 4.2, owner_color)
	draw_arc(Vector2.ZERO, 4.2, 0.0, TAU, 20, Color("102132"), 1.2)
	draw_line(Vector2(-5, -3), Vector2(5, -3), Color("f8fbfc"), 3.0, true)
	if inspection_selected:
		draw_arc(
			Vector2.ZERO,
			CurlingConstants.STONE_RADIUS_PX + 6.0,
			0.0,
			TAU,
			40,
			CurlingConstants.CYAN_ACCENT,
			3.0,
			true
		)
