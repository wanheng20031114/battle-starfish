extends Node

var _failures: Array[String] = []
var _collision_count := 0

@onready var controller: CurlingMatchController = $MatchController


func _ready() -> void:
	await get_tree().physics_frame
	for stone in _stones():
		stone.stone_collision.connect(_on_stone_collision)
	await _test_full_match_lifecycle()
	await _test_centerline_throw_after_restart()
	await _test_remote_second_match_snapshot()
	await _test_remote_snapshot_matches_host_stones()
	await _test_gameplay_tee_calibration()
	await _test_gameplay_recommended_draw()
	await _test_camera_modes()
	if _failures.is_empty():
		print("CURLING_STONE_LIFECYCLE_OK stones=%d" % _stones().size())
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("CURLING_STONE_LIFECYCLE_FAIL %s" % failure)
		get_tree().quit(1)


func _test_full_match_lifecycle() -> void:
	controller.start_match(_players(), 2, 1, true, 12345)
	await get_tree().physics_frame
	_expect_all_inactive("match start")

	controller._force_lock_all_teams()
	await get_tree().physics_frame
	_expect_only_active_stone_collidable("first throw")

	var expired_id := controller.active_stone_id
	controller._finish_empty_throw("lifecycle test")
	await get_tree().physics_frame
	_expect_inactive(_stones()[expired_id], "empty throw at Hack")
	_expect_only_active_stone_collidable("throw after empty throw")
	_collision_count = 0
	var post_empty := _stones()[controller.active_stone_id]
	var post_empty_start := post_empty.global_position
	post_empty.launch(_throw_direction(), 2.0, 0.0)
	await _wait_physics(0.2)
	if _collision_count != 0 or post_empty.global_position.distance_to(post_empty_start) < 10.0:
		_failures.append("next throw is unobstructed after an empty throw at Hack")

	for stone in _stones():
		stone.remove_from_play()
	var old_hack := CurlingConstants.hack_position(1)
	var next_hack := CurlingConstants.hack_position(-1)
	var occupied_positions := [Vector2.ZERO, old_hack, next_hack, Vector2(420.0, 75.0)]
	for index in range(occupied_positions.size()):
		_stones()[index].prepare_for_delivery(occupied_positions[index], index + 1, Color.WHITE)
		_stones()[index].freeze_at_rest()
	controller.current_end = 0
	controller.scheduled_ends = 2
	controller.direction = 1
	controller.phase = CurlingMatchController.Phase.SCORING
	controller._advance_after_score()
	await get_tree().physics_frame
	if controller.direction != -1 or controller.phase != CurlingMatchController.Phase.TACTICS:
		_failures.append("scoring transition switches direction and begins tactics")
	_expect_all_inactive("side switch cleanup")

	controller._force_lock_all_teams()
	await get_tree().physics_frame
	_expect_only_active_stone_collidable("first throw after side switch")
	var switched_active := _stones()[controller.active_stone_id]
	if switched_active.global_position.distance_to(next_hack) > 0.01:
		_failures.append("side switch uses the opposite Hack")
	_collision_count = 0
	var switched_start := switched_active.global_position
	switched_active.launch(_throw_direction(), 2.0, 0.0)
	await _wait_physics(0.2)
	if _collision_count != 0 or switched_active.global_position.distance_to(switched_start) < 10.0:
		_failures.append("first throw after side switch is unobstructed")

	var snapshot_stone: CurlingStone = _stones().back()
	snapshot_stone.restore_authoritative_state({"in_play": false, "position": Vector2.ZERO})
	_expect_inactive(snapshot_stone, "rule rollback inactive state")
	snapshot_stone.restore_authoritative_state({"in_play": true, "position": Vector2(250.0, 0.0)})
	_expect_active(snapshot_stone, "rule rollback active state")
	snapshot_stone.apply_remote_snapshot({"in_play": false}, true)
	_expect_inactive(snapshot_stone, "remote inactive snapshot")
	snapshot_stone.apply_remote_snapshot({"in_play": true, "position": Vector2(300.0, 0.0)}, true)
	_expect_active(snapshot_stone, "remote active snapshot")


func _test_centerline_throw_after_restart() -> void:
	controller.start_match(_players(), 1, 1, true, 22334)
	await get_tree().physics_frame
	_expect_all_inactive("restarted match before centerline throw")
	controller._force_lock_all_teams()
	await get_tree().physics_frame
	var stone := _stones()[controller.active_stone_id]
	_collision_count = 0
	var throw_direction := _throw_direction()
	if not controller.host_apply_throw(controller.active_thrower_id, throw_direction, 1.0, 0.0):
		_failures.append("full-sheet centerline throw starts")
		return
	await get_tree().physics_frame
	var slide_time_text := stone.slide_time_label.text
	if (
		not stone.slide_time_marker.visible
		or not slide_time_text.ends_with("s")
		or slide_time_text.contains(" ")
		or slide_time_text.contains("\n")
	):
		_failures.append("moving stone shows one compact remaining-time value")
	var remaining_before_heat := slide_time_text.substr(0, slide_time_text.length() - 1).to_float()
	var heat_finish_ms := Time.get_ticks_msec()
	for sample_index in range(24):
		controller.heat_grid.deposit_segment(
			stone.global_position + Vector2(-6.25, 0.0),
			stone.global_position + Vector2(6.25, 0.0),
			0.05,
			heat_finish_ms - (23 - sample_index) * 50,
			false
		)
	stone._update_slide_time_marker()
	var heated_time_text := stone.slide_time_label.text
	var remaining_after_heat := heated_time_text.substr(0, heated_time_text.length() - 1).to_float()
	if (
		not heated_time_text.ends_with("s")
		or heated_time_text.contains(" ")
		or heated_time_text.contains("\n")
		or remaining_after_heat <= remaining_before_heat
	):
		_failures.append("moving-stone timer stays compact and reacts to sweep heat")
	var previous_progress := stone.global_position.x * throw_direction.x
	var crossed_center := false
	var reversed := false
	for _frame in range(360):
		await get_tree().physics_frame
		var progress := stone.global_position.x * throw_direction.x
		if progress < previous_progress - 1.0:
			reversed = true
		previous_progress = progress
		if progress >= 100.0:
			crossed_center = true
			break
	if _collision_count != 0 or reversed or not crossed_center:
		_failures.append("restarted match crosses the complete centerline without an invisible collision")


func _test_remote_second_match_snapshot() -> void:
	controller.start_match(_players(), 1, 1, false, 33445)
	await get_tree().physics_frame
	var first_sequence := 50
	var first_active := 0
	if not controller.apply_remote_state(_remote_moving_state(first_sequence, 7, first_active)):
		_failures.append("first remote match state applies")
	if not controller.apply_remote_snapshot(_remote_snapshot(first_sequence, 7, first_active)):
		_failures.append("first remote match snapshot applies")

	controller.start_match(_players(), 1, 1, false, 44556)
	await get_tree().physics_frame
	_expect_all_inactive("second remote match reset")
	var second_sequence := controller.state_sequence
	var second_active := CurlingConstants.STONES_PER_TEAM
	if not controller.apply_remote_state(_remote_moving_state(second_sequence, 1, second_active)):
		_failures.append("second remote match accepts reset state sequence")
	if not controller.apply_remote_snapshot(_remote_snapshot(second_sequence, 1, second_active)):
		_failures.append("second remote match accepts its first snapshot")
	await get_tree().physics_frame
	var visible_stone := _stones()[second_active]
	_expect_active(visible_stone, "second remote match first stone")
	if not visible_stone.slide_time_marker.visible:
		_failures.append("second remote match renders the moving stone and timer")


func _test_remote_snapshot_matches_host_stones() -> void:
	controller.start_match(_players(), 1, 2, false, 66778)
	await get_tree().physics_frame
	var sequence := 73
	var active_id := 3
	if not controller.apply_remote_state(_remote_moving_state(sequence, 12, active_id)):
		_failures.append("remote stone sync state applies")
		return
	var host_states: Array[Dictionary] = []
	var in_play_ids := [0, active_id, 8, 12]
	for index in range(CurlingConstants.STONE_COUNT):
		var in_play := in_play_ids.has(index)
		var moving := index == active_id
		var velocity := Vector2(float(controller.direction) * 310.0, -12.0) if moving else Vector2.ZERO
		host_states.append({
			"id": index,
			"team": CurlingConstants.TEAM_RED if index < CurlingConstants.STONES_PER_TEAM else CurlingConstants.TEAM_BLUE,
			"in_play": in_play,
			"moving": moving,
			"position": Vector2(-240.0 + float(index) * 29.25, -54.0 + float(index) * 6.5),
			"velocity": velocity,
			"angle": -0.25 + float(index) * 0.035,
			"angular_velocity": 1.1 if moving else 0.0,
		})
	var payload := CurlingStoneSnapshotCodec.encode_snapshot(Time.get_ticks_msec(), sequence, 12, host_states)
	if not controller.apply_remote_snapshot(payload):
		_failures.append("remote stone sync snapshot applies")
		return
	var decoded := CurlingStoneSnapshotCodec.decode_snapshot(payload)
	var decoded_stones: Array = decoded.get("stones", [])
	for stone_index in range(CurlingConstants.STONE_COUNT):
		var expected: Dictionary = decoded_stones[stone_index]
		var stone := _stones()[stone_index]
		var expected_in_play := bool(expected.get("in_play", false))
		if stone.in_play != expected_in_play:
			_failures.append("remote stone sync in_play stone %d" % stone_index)
			continue
		if not expected_in_play:
			_expect_inactive(stone, "remote stone sync")
			continue
		_expect_active(stone, "remote stone sync")
		_expect_vector_close(stone.global_position, expected["position"] as Vector2, 0.2, "remote stone %d position" % stone_index)
		_expect_vector_close(stone.remote_target_velocity, expected["velocity"] as Vector2, 0.2, "remote stone %d velocity" % stone_index)
		if stone_index == active_id and not stone.active_delivered_stone:
			_failures.append("remote stone sync active moving stone")


func _test_gameplay_tee_calibration() -> void:
	for test_direction in [-1, 1]:
		controller.start_match(_players(), 1, 1, true, 77889 + test_direction)
		await get_tree().physics_frame
		controller.direction = test_direction
		for candidate in _stones():
			candidate.linear_damp = 9.0
		controller._force_lock_all_teams()
		await get_tree().physics_frame
		var stone := _stones()[controller.active_stone_id]
		if not is_zero_approx(stone.linear_damp):
			_failures.append("reused stone clears stale damping before delivery")
		var tee := CurlingConstants.tee_position(test_direction)
		var throw_direction := stone.global_position.direction_to(tee)
		var max_drag := minf(controller.get_viewport_rect().size.x, controller.get_viewport_rect().size.y) / 3.0
		controller._drag_origin_screen = Vector2.ZERO
		controller._drag_current_screen = Vector2(8.0 + CurlingConstants.THROW_TEE_POWER * (max_drag - 8.0), 0.0)
		controller._dragging = true
		var hud_power := controller._current_drag_power()
		controller._dragging = false
		if not is_equal_approx(hud_power, CurlingConstants.THROW_TEE_POWER):
			_failures.append("HUD drag maps exactly to the configured Tee power")
		if not is_zero_approx(controller.heat_grid.sample_heat(stone.global_position)):
			_failures.append("gameplay Tee calibration starts without sweep heat")
		if not controller.host_apply_throw(controller.active_thrower_id, throw_direction, hud_power, 0.0):
			_failures.append("gameplay Tee draw launches through the host path")
			continue
		var expected_launch_damp := CurlingConstants.BASE_DRAG_PXPS2 / (
			CurlingConstants.throw_speed_for_power(hud_power) * CurlingConstants.PIXELS_PER_METER
		)
		if absf(stone.linear_damp - expected_launch_damp) > 0.0001:
			_failures.append("reused stone launch damping derives from the new throw speed")
		var frames_waited := 0
		while controller.phase == CurlingMatchController.Phase.MOVING and frames_waited < 1800:
			await get_tree().physics_frame
			frames_waited += 1
		var tee_error_m := stone.global_position.distance_to(tee) / CurlingConstants.PIXELS_PER_METER
		print("CURLING_GAMEPLAY_TEE_PROBE direction=%d power=%.3f spin=0 heat=0 tee_error=%.3fm" % [test_direction, hud_power, tee_error_m])
		if controller.phase == CurlingMatchController.Phase.MOVING:
			_failures.append("gameplay Tee draw settles within 30 seconds")
		if not stone.in_play or not CurlingRules.is_in_house(stone.global_position, test_direction):
			_failures.append("75 percent no-sweep gameplay draw remains in the house")
		if tee_error_m > 0.25:
			_failures.append("75 percent no-sweep gameplay draw stops near Tee: %.3fm error" % tee_error_m)


func _test_gameplay_recommended_draw() -> void:
	for test_direction in [-1, 1]:
		controller.start_match(_players(), 1, 1, true, 88990 + test_direction)
		await get_tree().physics_frame
		controller.direction = test_direction
		controller._force_lock_all_teams()
		await get_tree().physics_frame
		var stone := _stones()[controller.active_stone_id]
		var throw_direction := Vector2(float(test_direction), 0.0)
		if not controller.host_apply_throw(
			controller.active_thrower_id,
			throw_direction,
			CurlingConstants.THROW_RECOMMENDED_POWER,
			0.0
		):
			_failures.append("77 percent recommended draw launches through the host path")
			continue
		var frames_waited := 0
		while controller.phase == CurlingMatchController.Phase.MOVING and frames_waited < 1800:
			await get_tree().physics_frame
			frames_waited += 1
		var tee := CurlingConstants.tee_position(test_direction)
		var tee_offset_m := (stone.global_position - tee).dot(throw_direction) / CurlingConstants.PIXELS_PER_METER
		var turn_time_sec := float(frames_waited) / float(CurlingConstants.PHYSICS_HZ)
		print(
			"CURLING_GAMEPLAY_RECOMMENDED_DRAW direction=%d power=%.3f turn=%.3fs tee_offset=%+.3fm"
			% [test_direction, CurlingConstants.THROW_RECOMMENDED_POWER, turn_time_sec, tee_offset_m]
		)
		if controller.phase == CurlingMatchController.Phase.MOVING:
			_failures.append("77 percent recommended draw settles within 30 seconds")
		if not stone.in_play or not CurlingRules.is_in_house(stone.global_position, test_direction):
			_failures.append("77 percent recommended draw remains in the house")
		if tee_offset_m < 1.0 or tee_offset_m > 1.3:
			_failures.append("77 percent recommended draw stops %.3fm behind Tee" % tee_offset_m)
		if absf(turn_time_sec - 22.67) > 0.12:
			_failures.append("77 percent recommended draw turn lasts %.3fs" % turn_time_sec)


func _test_camera_modes() -> void:
	controller.start_match(_players(), 1, 1, true, 55667)
	controller.reduced_motion = true
	controller._process_camera(0.0)
	var left_key := InputEventKey.new()
	left_key.keycode = KEY_A
	if controller._camera_key_direction(left_key) != -1:
		_failures.append("A and left-arrow camera mapping is available")
	controller._manual_camera_x = 0.0
	controller._process_camera(0.0)
	var before_key_pan := controller.game_camera.position.x
	controller._camera_left_held = true
	controller._process_camera(0.25)
	controller._camera_left_held = false
	if controller.game_camera.position.x >= before_key_pan - 10.0:
		_failures.append("A or left-arrow continuously pans the manual camera left")

	controller._force_lock_all_teams()
	await get_tree().physics_frame
	var camera_x_before_wheel := controller._manual_camera_x
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	controller._unhandled_input(wheel_up)
	if not is_equal_approx(controller._current_spin, CurlingConstants.SPIN_WHEEL_STEP_RADPS):
		_failures.append("mouse wheel up increases throw spin by one step")
	if not is_equal_approx(controller._manual_camera_x, camera_x_before_wheel):
		_failures.append("mouse wheel no longer moves the manual camera")
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	controller._unhandled_input(wheel_down)
	if not is_zero_approx(controller._current_spin):
		_failures.append("mouse wheel down decreases throw spin by one step")
	var moving_stone := _stones()[controller.active_stone_id]
	controller.host_apply_throw(controller.active_thrower_id, _throw_direction(), 0.77, 0.0)
	await get_tree().physics_frame
	controller._process_camera(0.0)
	if controller.game_camera.position.distance_to(moving_stone.global_position) > 0.1:
		_failures.append("moving phase exclusively returns to automatic stone tracking")


func _remote_moving_state(sequence: int, remote_shot_id: int, active_id: int) -> Dictionary:
	var state := controller.export_state_for()
	state["state_sequence"] = sequence
	state["shot_id"] = remote_shot_id
	state["phase"] = CurlingMatchController.Phase.MOVING
	state["active_stone_id"] = active_id
	state["active_thrower_id"] = 1
	state["active_team"] = CurlingConstants.TEAM_RED if active_id < CurlingConstants.STONES_PER_TEAM else CurlingConstants.TEAM_BLUE
	return state


func _remote_snapshot(sequence: int, remote_shot_id: int, active_id: int) -> PackedByteArray:
	var states := controller.get_stone_states()
	var active_state: Dictionary = states[active_id]
	active_state["in_play"] = true
	active_state["moving"] = true
	active_state["position"] = CurlingConstants.hack_position(controller.direction)
	active_state["velocity"] = Vector2(float(controller.direction) * 260.0, 0.0)
	states[active_id] = active_state
	return CurlingStoneSnapshotCodec.encode_snapshot(
		Time.get_ticks_msec(), sequence, remote_shot_id, states
	)


func _expect_all_inactive(context: String) -> void:
	if _stones().size() != CurlingConstants.STONE_COUNT:
		_failures.append("%s has exactly %d preallocated stones" % [context, CurlingConstants.STONE_COUNT])
		return
	for stone in _stones():
		_expect_inactive(stone, context)


func _expect_only_active_stone_collidable(context: String) -> void:
	var active_count := 0
	for stone in _stones():
		if stone.in_play:
			active_count += 1
			_expect_active(stone, context)
		else:
			_expect_inactive(stone, context)
	if active_count != 1:
		_failures.append("%s has one in-play stone, got %d" % [context, active_count])


func _expect_inactive(stone: CurlingStone, context: String) -> void:
	if (
		stone.in_play
		or stone.visible
		or stone.collision_layer != 0
		or stone.collision_mask != 0
		or stone.slide_time_marker.visible
	):
		_failures.append("%s stone %d is invisible and collision-free" % [context, stone.stone_id])


func _expect_active(stone: CurlingStone, context: String) -> void:
	if not stone.in_play or not stone.visible or stone.collision_layer == 0 or stone.collision_mask == 0:
		_failures.append("%s stone %d is visible and collidable" % [context, stone.stone_id])


func _expect_vector_close(actual: Vector2, expected: Vector2, tolerance: float, context: String) -> void:
	if actual.distance_to(expected) > tolerance:
		_failures.append("%s expected %s got %s" % [context, expected, actual])


func _stones() -> Array[CurlingStone]:
	var result: Array[CurlingStone] = []
	for child in controller.get_node("Stones").get_children():
		result.append(child as CurlingStone)
	return result


func _players() -> Array[Dictionary]:
	return [
		{"id": 1, "nickname": "红方", "team": CurlingConstants.TEAM_RED, "join_order": 0, "connected": true, "bot": false, "color": Color.RED},
		{"id": 2, "nickname": "蓝方", "team": CurlingConstants.TEAM_BLUE, "join_order": 1, "connected": true, "bot": false, "color": Color.BLUE},
	]


func _throw_direction() -> Vector2:
	return Vector2(float(controller.direction), 0.0)


func _wait_physics(seconds: float) -> void:
	for _frame in range(ceili(seconds * Engine.physics_ticks_per_second)):
		await get_tree().physics_frame


func _on_stone_collision(_stone_id: int, _other_id: int, _speed: float) -> void:
	_collision_count += 1
