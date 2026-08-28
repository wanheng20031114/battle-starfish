extends Node2D
class_name CurlingSandboxController

signal status_changed(message: String)
signal records_changed
signal selection_changed(record: CurlingShotRecord)
signal telemetry_changed(record: CurlingShotRecord)
signal aim_changed(data: Dictionary)
signal shot_launched(record: CurlingShotRecord)
signal impact_feedback(relative_speed_px: float)
signal sweeping_changed(active: bool, intensity: float)

const STONE_SCENE := preload("res://curling/game/curling_stone.tscn")
const CAMERA_ZOOM := 1.16
const CAMERA_PAN_SPEED_PXPS := 1100.0
const CAMERA_X_LIMIT_PX := CurlingConstants.TEE_FROM_CENTER_PX + CurlingConstants.HACK_FROM_TEE_PX

@onready var heat_grid: CurlingHeatGrid = $HeatGrid
@onready var trajectory_preview: Line2D = $TrajectoryPreview
@onready var trajectory_history: CurlingSandboxTrajectoryLayer = $TrajectoryHistory
@onready var stones_root: Node2D = $Stones
@onready var game_camera: Camera2D = $Camera2D

var next_team := CurlingConstants.TEAM_RED
var next_direction := 1
var reduced_motion := false
var input_locked := false

var records: Array[CurlingShotRecord] = []
var selected_record: CurlingShotRecord
var pending_stone: CurlingStone
var active_record: CurlingShotRecord

var _record_by_id: Dictionary = {}
var _next_shot_id := 1
var _shot_in_progress := false
var _settle_elapsed := 0.0
var _status_message := ""
var _telemetry_accumulator := 0.0

var _dragging := false
var _drag_origin_screen := Vector2.ZERO
var _drag_current_screen := Vector2.ZERO
var _drag_aim_direction := Vector2.RIGHT
var _drag_power_adjustment := 0.0
var _current_spin := 0.0

var _sweep_down := false
var _last_sweep_world := Vector2.ZERO
var _last_sweep_ms := 0
var _camera_left_held := false
var _camera_right_held := false
var _manual_camera_x := 0.0

var _stone_click_candidates: Array[CurlingStone] = []
var _stone_click_resolution_queued := false
var _stone_click_screen_position := Vector2.ZERO
var _last_collision_frame_by_pair: Dictionary = {}


func _ready() -> void:
	trajectory_preview.visible = false
	game_camera.enabled = true
	game_camera.zoom = Vector2.ONE * CAMERA_ZOOM
	_manual_camera_x = CurlingConstants.hack_position(next_direction).x
	game_camera.position = Vector2(_manual_camera_x, 0.0)
	_spawn_pending_stone()


func _process(delta: float) -> void:
	_process_camera(delta)
	if not input_locked and pending_stone != null:
		if _dragging:
			_update_drag_precision_from_keys(delta)
		_update_spin_from_keys(delta)
	_emit_aim_data()
	_telemetry_accumulator += delta
	if _telemetry_accumulator >= CurlingShotRecord.SAMPLE_INTERVAL_SEC:
		_telemetry_accumulator = fmod(_telemetry_accumulator, CurlingShotRecord.SAMPLE_INTERVAL_SEC)
		telemetry_changed.emit(selected_record)


func _physics_process(delta: float) -> void:
	var any_moving := false
	var status_did_change := false
	for record in records:
		if not record.is_on_field():
			continue
		var stone := record.stone
		if _is_out_of_play(stone.global_position):
			if record.status == CurlingShotRecord.Status.MOVING:
				record.update_from_stone(delta)
			_remove_record_entity(record, CurlingShotRecord.Status.OUT_OF_PLAY, "越出正式场地边界")
			status_did_change = true
			continue
		var moving := stone.linear_velocity.length() > CurlingConstants.STOP_SPEED_PXPS
		if moving and record.status != CurlingShotRecord.Status.MOVING:
			record.resume_motion("碰撞后滑行")
			status_did_change = true
		if record.status == CurlingShotRecord.Status.MOVING:
			record.update_from_stone(delta if moving else 0.0)
		if moving:
			any_moving = true

	if not _shot_in_progress:
		if status_did_change:
			records_changed.emit()
		return
	if any_moving:
		_settle_elapsed = 0.0
	else:
		_settle_elapsed += delta
		if _settle_elapsed >= CurlingConstants.SETTLE_TIME_SEC:
			_finish_current_shot()
	if status_did_change:
		records_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if pending_stone != null and mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var wheel_direction := 1.0 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			_adjust_spin(wheel_direction * CurlingConstants.SPIN_WHEEL_STEP_RADPS)
			get_viewport().set_input_as_handled()
			return
		if pending_stone != null and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed and _can_begin_drag(mouse_event.position):
				_begin_drag(mouse_event.position)
				get_viewport().set_input_as_handled()
				return
			if not mouse_event.pressed and _dragging:
				if not mouse_event.position.is_equal_approx(_drag_current_screen):
					_drag_current_screen = mouse_event.position
					_update_drag_aim_from_pointer(mouse_event.position)
				_release_throw()
				get_viewport().set_input_as_handled()
				return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag()
			get_viewport().set_input_as_handled()
			return
		if _shot_in_progress and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_set_sweep_down(mouse_event.pressed, _screen_to_world(mouse_event.position))
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging:
			_drag_current_screen = motion.position
			_update_drag_aim_from_pointer(motion.position)
			_refresh_aim_preview()
			get_viewport().set_input_as_handled()
		elif _shot_in_progress and _sweep_down:
			_submit_sweep_motion(_screen_to_world(motion.position))
			get_viewport().set_input_as_handled()
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if _dragging and _is_drag_precision_key(key_event):
			_camera_left_held = false
			_camera_right_held = false
			get_viewport().set_input_as_handled()
			return
		var camera_direction := _camera_key_direction(key_event)
		if camera_direction != 0 and not _shot_in_progress:
			if camera_direction < 0:
				_camera_left_held = key_event.pressed
			else:
				_camera_right_held = key_event.pressed
			get_viewport().set_input_as_handled()


func set_input_locked(locked: bool) -> void:
	input_locked = locked
	if locked:
		_cancel_drag()
		_set_sweep_down(false)
		_camera_left_held = false
		_camera_right_held = false


func set_next_team(team: int) -> bool:
	if team not in [CurlingConstants.TEAM_RED, CurlingConstants.TEAM_BLUE]:
		return false
	next_team = team
	if pending_stone != null:
		pending_stone.team = next_team
		pending_stone.owner_color = _owner_color_for_team(next_team)
		pending_stone.queue_redraw()
	_emit_aim_data()
	return true


func set_next_direction(direction_sign: int) -> bool:
	var normalized_direction := 1 if direction_sign >= 0 else -1
	if pending_stone != null and not _is_hack_clear(normalized_direction, pending_stone):
		_set_status("目标 Hack 被场上冰壶占用，请先移除")
		return false
	next_direction = normalized_direction
	_drag_aim_direction = Vector2(float(next_direction), 0.0)
	_drag_power_adjustment = 0.0
	if pending_stone != null:
		pending_stone.prepare_for_delivery(
			CurlingConstants.hack_position(next_direction),
			0,
			_owner_color_for_team(next_team)
		)
		pending_stone.team = next_team
	_manual_camera_x = CurlingConstants.hack_position(next_direction).x
	_cancel_drag()
	_set_status("可投壶")
	_emit_aim_data()
	return true


func get_records() -> Array[CurlingShotRecord]:
	return records.duplicate()


func get_selected_record() -> CurlingShotRecord:
	return selected_record


func get_field_count() -> int:
	var count := 0
	for record in records:
		if record.is_on_field():
			count += 1
	return count


func get_total_shots() -> int:
	return records.size()


func get_status_message() -> String:
	return _status_message


func select_record(shot_id: int) -> bool:
	var record_variant: Variant = _record_by_id.get(shot_id)
	if not record_variant is CurlingShotRecord:
		return false
	if selected_record != null and selected_record.is_on_field():
		selected_record.stone.set_inspection_selected(false)
	selected_record = record_variant as CurlingShotRecord
	if selected_record.is_on_field():
		selected_record.stone.set_inspection_selected(true)
	trajectory_history.show_record(selected_record)
	selection_changed.emit(selected_record)
	telemetry_changed.emit(selected_record)
	return true


func remove_selected() -> bool:
	if selected_record == null or not selected_record.is_on_field():
		return false
	var removed_id := selected_record.shot_id
	_remove_record_entity(selected_record, CurlingShotRecord.Status.REMOVED, "玩家手动移除")
	_set_status("已移除 #%d" % removed_id)
	if _shot_in_progress and not _has_moving_field_stone():
		_settle_elapsed = CurlingConstants.SETTLE_TIME_SEC
	elif not _shot_in_progress and pending_stone == null:
		_spawn_pending_stone()
	records_changed.emit()
	selection_changed.emit(selected_record)
	return true


func clear_field() -> void:
	_cancel_drag()
	_set_sweep_down(false)
	_remove_pending_stone()
	for record in records:
		if record.is_on_field():
			_remove_record_entity(record, CurlingShotRecord.Status.REMOVED, "清空场地")
	_shot_in_progress = false
	active_record = null
	_settle_elapsed = 0.0
	heat_grid.clear()
	_spawn_pending_stone()
	_set_status("场地已清空，历史记录已保留")
	records_changed.emit()
	selection_changed.emit(selected_record)


func clear_history() -> void:
	_cancel_drag()
	_set_sweep_down(false)
	_remove_pending_stone()
	for record in records:
		if record.is_on_field():
			_remove_record_entity(record, CurlingShotRecord.Status.REMOVED, "清空历史")
	records.clear()
	_record_by_id.clear()
	selected_record = null
	active_record = null
	_next_shot_id = 1
	_shot_in_progress = false
	_settle_elapsed = 0.0
	heat_grid.clear()
	trajectory_history.clear_record()
	_spawn_pending_stone()
	_set_status("测试历史已清空")
	records_changed.emit()
	selection_changed.emit(null)


func focus_selected() -> bool:
	if selected_record == null:
		return false
	_manual_camera_x = clampf(selected_record.current_position.x, -CAMERA_X_LIMIT_PX, CAMERA_X_LIMIT_PX)
	if reduced_motion and not _shot_in_progress:
		game_camera.position.x = _manual_camera_x
	return true


func _spawn_pending_stone() -> bool:
	if pending_stone != null or _shot_in_progress:
		return false
	if not _is_hack_clear(next_direction):
		_set_status("出手点被占用，请选择场上冰壶并移除")
		return false
	var stone := STONE_SCENE.instantiate() as CurlingStone
	stone.name = "SandboxStone%05d" % _next_shot_id
	stone.stone_id = _next_shot_id
	stone.team = next_team
	stone.authoritative = true
	stones_root.add_child(stone)
	stone.heat_grid = heat_grid
	stone.stone_collision.connect(_on_stone_collision)
	stone.input_event.connect(_on_stone_input_event.bind(stone))
	stone.prepare_for_delivery(
		CurlingConstants.hack_position(next_direction),
		0,
		_owner_color_for_team(next_team)
	)
	pending_stone = stone
	_current_spin = 0.0
	_drag_aim_direction = Vector2(float(next_direction), 0.0)
	_drag_power_adjustment = 0.0
	_manual_camera_x = pending_stone.global_position.x
	_set_status("可投壶")
	_emit_aim_data()
	return true


func _remove_pending_stone() -> void:
	if pending_stone == null:
		return
	pending_stone.remove_from_play()
	pending_stone.queue_free()
	pending_stone = null


func _begin_drag(screen_position: Vector2) -> void:
	_dragging = true
	_drag_origin_screen = screen_position
	_drag_current_screen = screen_position
	_drag_aim_direction = Vector2(float(next_direction), 0.0)
	_drag_power_adjustment = 0.0
	_camera_left_held = false
	_camera_right_held = false
	_set_status("正在瞄准")
	_refresh_aim_preview()


func _release_throw() -> void:
	if pending_stone == null:
		_cancel_drag()
		return
	var power := _current_drag_power()
	var aim_direction := _drag_aim_direction
	_dragging = false
	trajectory_preview.visible = false
	if power <= 0.0 or aim_direction.length_squared() < 0.9:
		_set_status("拖拽距离不足，已取消")
		_emit_aim_data()
		return
	for record in records:
		if record.is_on_field():
			record.stone.enable_for_shot()
	var stone := pending_stone
	stone.launch(aim_direction.normalized(), CurlingConstants.throw_speed_for_power(power), _current_spin)
	var record := CurlingShotRecord.new()
	record.begin(
		_next_shot_id,
		stone,
		next_team,
		next_direction,
		aim_direction,
		power,
		_current_spin
	)
	records.append(record)
	_record_by_id[record.shot_id] = record
	_next_shot_id += 1
	pending_stone = null
	active_record = record
	_shot_in_progress = true
	_settle_elapsed = 0.0
	heat_grid.clear()
	select_record(record.shot_id)
	_set_status("#%d 正在滑行" % record.shot_id)
	records_changed.emit()
	shot_launched.emit(record)
	_emit_aim_data()


func _finish_current_shot() -> void:
	for record in records:
		if not record.is_on_field():
			continue
		if record.status == CurlingShotRecord.Status.MOVING:
			record.mark_stopped("已停稳")
		record.stone.freeze_at_rest()
	_shot_in_progress = false
	active_record = null
	_settle_elapsed = 0.0
	_set_sweep_down(false)
	heat_grid.clear()
	var spawned := _spawn_pending_stone()
	if spawned:
		_set_status("全部冰壶已停稳，可继续投壶")
	records_changed.emit()
	selection_changed.emit(selected_record)


func _remove_record_entity(record: CurlingShotRecord, next_status: int, reason: String) -> void:
	if not record.is_on_field():
		return
	var stone := record.stone
	if record.status == CurlingShotRecord.Status.MOVING:
		record.update_from_stone(0.0)
	record.finish(next_status, reason)
	stone.set_inspection_selected(false)
	stone.remove_from_play()
	stone.queue_free()
	if active_record == record:
		active_record = null
	if selected_record == record:
		trajectory_history.show_record(record)
		telemetry_changed.emit(record)


func _on_stone_input_event(_viewport: Node, event: InputEvent, _shape_index: int, stone: CurlingStone) -> void:
	if input_locked or stone == pending_stone or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _stone_click_candidates.has(stone):
		_stone_click_candidates.append(stone)
	_stone_click_screen_position = mouse_event.position
	if not _stone_click_resolution_queued:
		_stone_click_resolution_queued = true
		call_deferred("_resolve_stone_click")
	get_viewport().set_input_as_handled()


func _resolve_stone_click() -> void:
	_stone_click_resolution_queued = false
	var pointer := _screen_to_world(_stone_click_screen_position)
	var best_stone: CurlingStone
	var best_distance := INF
	for stone in _stone_click_candidates:
		if stone == null or not is_instance_valid(stone) or not stone.in_play:
			continue
		var distance := stone.global_position.distance_to(pointer)
		if (
			distance < best_distance - 0.001
			or (is_equal_approx(distance, best_distance) and (best_stone == null or stone.stone_id > best_stone.stone_id))
		):
			best_stone = stone
			best_distance = distance
	_stone_click_candidates.clear()
	if best_stone != null:
		select_record(best_stone.stone_id)


func _on_stone_collision(stone_a: int, stone_b: int, relative_speed_px: float) -> void:
	var low := mini(stone_a, stone_b)
	var high := maxi(stone_a, stone_b)
	var pair_key := "%d:%d" % [low, high]
	var physics_frame := Engine.get_physics_frames()
	if int(_last_collision_frame_by_pair.get(pair_key, -1)) == physics_frame:
		return
	_last_collision_frame_by_pair[pair_key] = physics_frame
	for shot_id in [stone_a, stone_b]:
		var record_variant: Variant = _record_by_id.get(shot_id)
		if record_variant is CurlingShotRecord:
			(record_variant as CurlingShotRecord).mark_collision(relative_speed_px)
	impact_feedback.emit(relative_speed_px)
	records_changed.emit()


func _set_sweep_down(enabled: bool, world_position: Vector2 = Vector2.INF) -> void:
	if enabled and (not _shot_in_progress or active_record == null or not active_record.is_on_field()):
		return
	_sweep_down = enabled
	if enabled:
		_last_sweep_world = world_position if world_position.is_finite() else get_global_mouse_position()
		_last_sweep_ms = Time.get_ticks_msec()
	else:
		sweeping_changed.emit(false, 0.0)


func _submit_sweep_motion(world_position: Vector2) -> void:
	if active_record == null or not active_record.is_on_field():
		_set_sweep_down(false)
		return
	var now_ms := Time.get_ticks_msec()
	var delta_sec := clampf(float(now_ms - _last_sweep_ms) / 1000.0, 0.001, 0.25)
	var intensity := heat_grid.deposit_segment(
		_last_sweep_world,
		world_position,
		delta_sec,
		now_ms,
		false
	)
	_last_sweep_world = world_position
	_last_sweep_ms = now_ms
	sweeping_changed.emit(_sweep_down, intensity)


func _can_begin_drag(screen_position: Vector2) -> bool:
	if pending_stone == null or _shot_in_progress:
		return false
	return _screen_to_world(screen_position).distance_to(pending_stone.global_position) <= 80.0 / maxf(game_camera.zoom.x, 0.1)


func _cancel_drag() -> void:
	_dragging = false
	_drag_power_adjustment = 0.0
	trajectory_preview.visible = false
	_emit_aim_data()


func _current_drag_power() -> float:
	return clampf(_raw_drag_power() + _drag_power_adjustment, 0.0, 1.0)


func _raw_drag_power() -> float:
	var max_drag := minf(get_viewport_rect().size.x, get_viewport_rect().size.y) / 3.0
	var drag_distance := _drag_origin_screen.distance_to(_drag_current_screen)
	if drag_distance < 8.0:
		return 0.0
	return clampf((drag_distance - 8.0) / maxf(1.0, max_drag - 8.0), 0.0, 1.0)


func _update_drag_aim_from_pointer(screen_position: Vector2) -> void:
	if pending_stone == null:
		return
	var pointer_direction := _screen_to_world(screen_position).direction_to(pending_stone.global_position)
	if pointer_direction.length_squared() >= 0.9:
		_drag_aim_direction = pointer_direction.normalized()


func _update_drag_precision_from_keys(delta: float) -> void:
	var aim_axis := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		aim_axis -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		aim_axis += 1.0
	var power_axis := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		power_axis += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		power_axis -= 1.0
	var precision_multiplier := (
		CurlingConstants.THROW_FINE_ADJUST_MULTIPLIER
		if Input.is_key_pressed(KEY_SHIFT)
		else 1.0
	)
	if not is_zero_approx(aim_axis):
		_drag_aim_direction = _drag_aim_direction.normalized().rotated(
			deg_to_rad(aim_axis * CurlingConstants.AIM_KEY_RATE_DEGPS * precision_multiplier * delta)
		)
		_refresh_aim_preview()
	if not is_zero_approx(power_axis):
		var raw_power := _raw_drag_power()
		var adjusted_power := clampf(
			raw_power
			+ _drag_power_adjustment
			+ power_axis * CurlingConstants.POWER_KEY_RATE_PER_SEC * precision_multiplier * delta,
			0.0,
			1.0
		)
		_drag_power_adjustment = adjusted_power - raw_power
		_refresh_aim_preview()


func _update_spin_from_keys(delta: float) -> void:
	var input_axis := Input.get_axis("ui_page_up", "ui_page_down")
	if Input.is_key_pressed(KEY_Q):
		input_axis -= 1.0
	if Input.is_key_pressed(KEY_E):
		input_axis += 1.0
	if not is_zero_approx(input_axis):
		_adjust_spin(input_axis * CurlingConstants.SPIN_KEY_RATE_RADPS * delta)


func _adjust_spin(delta_spin: float) -> void:
	_current_spin = clampf(
		_current_spin + delta_spin,
		-CurlingConstants.MAX_SPIN_RADPS,
		CurlingConstants.MAX_SPIN_RADPS
	)
	if _dragging:
		_refresh_aim_preview()
	_emit_aim_data()


func _refresh_aim_preview() -> void:
	if not _dragging or pending_stone == null:
		trajectory_preview.visible = false
		return
	trajectory_preview.points = _predict_path(
		pending_stone.global_position,
		_drag_aim_direction,
		_current_drag_power(),
		_current_spin
	)
	trajectory_preview.visible = true
	_emit_aim_data()


func _predict_path(start: Vector2, aim_direction: Vector2, power: float, spin: float) -> PackedVector2Array:
	var speed_mps := CurlingConstants.throw_speed_for_power(power)
	var velocity := aim_direction * speed_mps * CurlingConstants.PIXELS_PER_METER
	var angular_velocity := spin
	var position := start
	var points := PackedVector2Array([position])
	var dt := 1.0 / 30.0
	for step in range(1200):
		var speed := velocity.length()
		if speed <= CurlingConstants.STOP_SPEED_PXPS:
			break
		var velocity_direction := velocity / speed
		var speed_factor := 0.25 + 0.75 * clampf(
			1.0 - speed / CurlingConstants.PIXELS_PER_METER / CurlingConstants.MAX_THROW_SPEED_MPS,
			0.0,
			1.0
		)
		velocity += -velocity_direction * CurlingConstants.BASE_DRAG_PXPS2 * dt
		var next_speed := velocity.length()
		if next_speed > CurlingConstants.STOP_SPEED_PXPS:
			var turn_radians := (
				CurlingConstants.CURL_ACCEL_PER_RAD_PXPS2
				* angular_velocity
				* speed_factor
				/ maxf(speed, CurlingConstants.STOP_SPEED_PXPS)
				* dt
			)
			velocity = velocity.normalized().rotated(turn_radians) * next_speed
		position += velocity * dt
		angular_velocity *= exp(-CurlingConstants.ANGULAR_DAMP_PER_SEC * dt)
		if step % 6 == 0:
			points.append(position)
		if _is_out_of_play(position):
			break
	points.append(position)
	return points


func _process_camera(delta: float) -> void:
	if not game_camera.enabled:
		return
	var target_x := _manual_camera_x
	if _shot_in_progress:
		var followed := active_record
		if followed == null or not followed.is_on_field():
			followed = _fastest_moving_record()
		if followed != null and followed.is_on_field():
			target_x = followed.stone.global_position.x
	elif not _dragging:
		var pan_axis := float(_camera_right_held) - float(_camera_left_held)
		if not is_zero_approx(pan_axis):
			_manual_camera_x = clampf(
				_manual_camera_x + pan_axis * CAMERA_PAN_SPEED_PXPS * delta,
				-CAMERA_X_LIMIT_PX,
				CAMERA_X_LIMIT_PX
			)
		target_x = _manual_camera_x
	var target := Vector2(clampf(target_x, -CAMERA_X_LIMIT_PX, CAMERA_X_LIMIT_PX), 0.0)
	var weight := 1.0 if reduced_motion else 1.0 - exp(-delta * 4.5)
	game_camera.position = game_camera.position.lerp(target, weight)
	game_camera.zoom = game_camera.zoom.lerp(Vector2.ONE * CAMERA_ZOOM, weight)


func _fastest_moving_record() -> CurlingShotRecord:
	var fastest: CurlingShotRecord
	var fastest_speed := 0.0
	for record in records:
		if not record.is_on_field():
			continue
		var speed := record.stone.linear_velocity.length()
		if speed > fastest_speed:
			fastest = record
			fastest_speed = speed
	return fastest


func _is_hack_clear(direction_sign: int, ignored_stone: CurlingStone = null) -> bool:
	var hack := CurlingConstants.hack_position(direction_sign)
	var clearance := CurlingConstants.STONE_RADIUS_PX * 2.0 + 2.0
	for record in records:
		if record.is_on_field() and record.stone != ignored_stone and record.stone.global_position.distance_to(hack) < clearance:
			return false
	return true


func _is_out_of_play(position: Vector2) -> bool:
	if absf(position.y) + CurlingConstants.STONE_RADIUS_PX >= CurlingConstants.HALF_SHEET_WIDTH_PX:
		return true
	var back_line_limit := CurlingConstants.TEE_FROM_CENTER_PX + CurlingConstants.BACK_LINE_FROM_TEE_PX
	return absf(position.x) - CurlingConstants.STONE_RADIUS_PX > back_line_limit


func _has_moving_field_stone() -> bool:
	for record in records:
		if record.is_on_field() and record.stone.linear_velocity.length() > CurlingConstants.STOP_SPEED_PXPS:
			return true
	return false


func _owner_color_for_team(team: int) -> Color:
	return CurlingConstants.PLAYER_COLORS[0 if team == CurlingConstants.TEAM_RED else 1]


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position


func _camera_key_direction(event: InputEventKey) -> int:
	if event.keycode in [KEY_LEFT, KEY_A] or event.physical_keycode in [KEY_LEFT, KEY_A]:
		return -1
	if event.keycode in [KEY_RIGHT, KEY_D] or event.physical_keycode in [KEY_RIGHT, KEY_D]:
		return 1
	return 0


func _is_drag_precision_key(event: InputEventKey) -> bool:
	return (
		event.keycode in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
		or event.physical_keycode in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	)


func _current_aim_offset_degrees() -> float:
	if _drag_aim_direction.length_squared() < 0.9:
		return 0.0
	return rad_to_deg(
		Vector2(float(next_direction), 0.0).angle_to(_drag_aim_direction.normalized())
	)


func _emit_aim_data() -> void:
	aim_changed.emit({
		"ready": pending_stone != null and not _shot_in_progress,
		"dragging": _dragging,
		"power": _current_drag_power() if _dragging else 0.0,
		"spin": _current_spin,
		"aim_offset_degrees": _current_aim_offset_degrees() if _dragging else 0.0,
		"team": next_team,
		"direction": next_direction,
		"field_count": get_field_count(),
		"shot_count": get_total_shots(),
	})


func _set_status(message: String) -> void:
	if _status_message == message:
		return
	_status_message = message
	status_changed.emit(message)
