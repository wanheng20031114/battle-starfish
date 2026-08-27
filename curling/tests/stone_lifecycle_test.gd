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
	if not stone.slide_time_marker.visible or not stone.slide_time_label.text.begins_with("预计剩余"):
		_failures.append("moving stone shows its remaining slide time")
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
	if not stone.slide_time_label.text.contains("擦冰 +"):
		_failures.append("moving-stone timer exposes the current sweep extension")
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


func _test_camera_modes() -> void:
	controller.start_match(_players(), 1, 1, true, 55667)
	controller.reduced_motion = true
	controller._process_camera(0.0)
	var initial_x := controller.game_camera.position.x
	controller._nudge_manual_camera(1.0)
	controller._process_camera(0.0)
	if (controller.game_camera.position.x - initial_x) * float(controller.direction) <= 10.0:
		_failures.append("mouse wheel moves the manual camera toward the target end")
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
