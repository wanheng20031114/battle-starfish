extends SceneTree

const CurlingSettingsScript := preload("res://curling/settings/curling_settings.gd")

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_dimensions_and_calibration()
	_test_player_capacity_and_disconnects()
	_test_lineup_allocation()
	_test_rules()
	_test_snapshot_codec()
	_test_heat_grid()
	_test_match_alternation_and_overtime()
	_test_settings_persistence()
	if _failures.is_empty():
		print("CURLING_UNIT_OK checks=%d" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error("CURLING_UNIT_FAIL %s" % failure)
		quit(1)


func _test_dimensions_and_calibration() -> void:
	_expect_close(CurlingConstants.SHEET_LENGTH_M, 45.720, 0.0001, "sheet length")
	_expect_close(CurlingConstants.SHEET_WIDTH_M, 4.750, 0.0001, "sheet width")
	_expect_close(CurlingConstants.STONE_RADIUS_M, 0.1455, 0.00001, "stone radius")
	_expect_close(CurlingConstants.STONE_MASS_KG, 19.0, 0.001, "stone mass")
	_expect_close(CurlingConstants.STONE_RESTITUTION, 0.92, 0.0001, "restitution")

	var draw_distance := 2.0 * CurlingConstants.TEE_FROM_CENTER_M + CurlingConstants.HACK_FROM_TEE_PX / CurlingConstants.PIXELS_PER_METER
	var standard_speed := draw_distance / 22.0 + 0.5 * CurlingConstants.BASE_DRAG_MPS2 * 22.0
	var beginner_power := CurlingConstants.THROW_DRAW_POWER
	var beginner_speed := CurlingConstants.throw_speed_for_power(beginner_power)
	var beginner_draw := _integrate_calibration(beginner_speed, 0.0, 0.0)
	_expect_close(float(beginner_draw["forward"]), draw_distance, 0.35, "75 percent no-sweep straight draw reaches tee")
	var swept_beginner_draw := _integrate_calibration(beginner_speed, 0.0, 1.0)
	_expect(float(swept_beginner_draw["forward"]) > draw_distance + 2.5, "75 percent full-sweep draw clearly passes tee")
	var lower_step := beginner_speed - CurlingConstants.throw_speed_for_power(0.70)
	var upper_step := CurlingConstants.throw_speed_for_power(0.80) - beginner_speed
	_expect_close(lower_step, upper_step, 0.001, "throw power is linear around the 75 percent draw")
	var planned_sweep_power := 0.70
	var planned_sweep_speed := CurlingConstants.throw_speed_for_power(planned_sweep_power)
	var planned_sweep_draw := _integrate_calibration(planned_sweep_speed, 0.0, 1.0)
	_expect_close(float(planned_sweep_draw["forward"]), draw_distance, 0.35, "70 percent full-sweep draw reaches tee")
	var straight := _integrate_calibration(standard_speed, 0.0, 0.0)
	var cold := _integrate_calibration(standard_speed, CurlingConstants.MAX_SPIN_RADPS, 0.0)
	var swept := _integrate_calibration(standard_speed, CurlingConstants.MAX_SPIN_RADPS, 1.0)
	var cold_time_estimate := CurlingStone.estimate_remaining_slide_time(standard_speed, 0.0)
	var swept_time_estimate := CurlingStone.estimate_remaining_slide_time(standard_speed, 1.0)
	_expect_close(cold_time_estimate, float(cold["time"]), 0.35, "remaining-time label matches cold draw duration")
	_expect(swept_time_estimate > cold_time_estimate + 1.5, "remaining-time label exposes sweep extension")
	_expect_close(float(cold["time"]), 22.0, 0.35, "22 second draw")
	_expect_close(float(straight["forward"]), draw_distance, 0.35, "draw reaches far tee")
	_expect_close(float(cold["path"]), float(straight["path"]), 0.02, "spin preserves slide distance")
	_expect_close(absf(float(cold["lateral"])), 1.5, 0.12, "maximum curl")
	_expect_close(float(swept["forward"]) - float(cold["forward"]), 3.0, 0.40, "full heat adds about 3m")
	var curl_reduction := 1.0 - absf(float(swept["lateral"]) / float(cold["lateral"]))
	_expect_close(curl_reduction, 0.35, 0.04, "full heat reduces final curl about 35 percent")


func _integrate_calibration(initial_speed: float, initial_spin: float, heat: float) -> Dictionary:
	var velocity := Vector2(initial_speed, 0.0)
	var position := Vector2.ZERO
	var path := 0.0
	var spin := initial_spin
	var elapsed := 0.0
	var delta := 1.0 / 600.0
	while elapsed < 45.0 and velocity.length() > CurlingConstants.STOP_SPEED_MPS:
		var previous_position := position
		var speed := velocity.length()
		var forward := velocity / speed
		var speed_factor := 0.25 + 0.75 * clampf(1.0 - speed / CurlingConstants.MAX_THROW_SPEED_MPS, 0.0, 1.0)
		var acceleration := -forward * CurlingConstants.BASE_DRAG_MPS2 * (1.0 - CurlingConstants.SWEEP_DRAG_REDUCTION * heat)
		velocity += acceleration * delta
		var next_speed := velocity.length()
		if next_speed > CurlingConstants.STOP_SPEED_MPS:
			var turn_radians := (
				CurlingConstants.CURL_ACCEL_PER_RAD_MPS2
				* spin
				* speed_factor
				* (1.0 - CurlingConstants.SWEEP_CURL_FORCE_REDUCTION * heat)
				/ maxf(speed, CurlingConstants.STOP_SPEED_MPS)
				* delta
			)
			velocity = velocity.normalized().rotated(turn_radians) * next_speed
		position += velocity * delta
		path += position.distance_to(previous_position)
		spin *= exp(-CurlingConstants.ANGULAR_DAMP_PER_SEC * delta)
		elapsed += delta
	return {"time": elapsed, "forward": position.x, "lateral": position.y, "path": path}


func _test_lineup_allocation() -> void:
	var one := CurlingLineupAllocator.fill_empty_slots([0, 0, 0, 0, 0, 0, 0, 0], [10], {10: 0})
	_expect(one.count(10) == CurlingConstants.STONES_PER_TEAM, "1-player team owns all eight stones")
	var two := CurlingLineupAllocator.fill_empty_slots([0, 0, 0, 0, 0, 0, 0, 0], [10, 20], {10: 0, 20: 1})
	_expect(two == [10, 20, 10, 20, 10, 20, 10, 20], "2-player fair fill")
	var three := CurlingLineupAllocator.fill_empty_slots([10, 0, 0, 0, 0, 0, 0, 0], [10, 20, 30], {10: 0, 20: 1, 30: 2})
	_expect(three.count(10) == 3 and three.count(20) == 3 and three.count(30) == 2, "3-player fill differs by at most one")
	var four := CurlingLineupAllocator.fill_empty_slots([0, 0, 0, 0, 0, 0, 0, 0], [10, 20, 30, 40], {10: 0, 20: 1, 30: 2, 40: 3})
	_expect(four == [10, 20, 30, 40, 10, 20, 30, 40], "4-player team receives two stones each")
	var reassigned := CurlingLineupAllocator.redistribute_player_slots([10, 20, 10, 20, 10, 20, 10, 20], 20, [10, 30], {10: 0, 30: 2}, 2)
	_expect(reassigned[1] == 20, "played slot is preserved after disconnect")
	_expect(not 20 in reassigned.slice(2), "future slots transfer immediately")


func _test_player_capacity_and_disconnects() -> void:
	_expect(CurlingConstants.PROTOCOL_VERSION == 2, "2-8 player contract uses protocol v2")
	var valid_pairs := [
		Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 3),
		Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 4),
	]
	for pair in valid_pairs:
		_expect(
			CurlingConstants.is_valid_team_distribution(pair.x, pair.y),
			"valid team distribution %dv%d" % [pair.x, pair.y]
		)
	var invalid_pairs := [
		Vector2i(0, 2), Vector2i(1, 3), Vector2i(1, 4),
		Vector2i(2, 4), Vector2i(4, 5), Vector2i(0, 0),
	]
	for pair in invalid_pairs:
		_expect(
			not CurlingConstants.is_valid_team_distribution(pair.x, pair.y),
			"invalid team distribution %dv%d" % [pair.x, pair.y]
		)

	var solo := CurlingMatchController.new()
	solo.authoritative = true
	solo.phase = CurlingMatchController.Phase.TACTICS
	solo.players = {
		10: {"id": 10, "team": CurlingConstants.TEAM_RED, "join_order": 0, "connected": true},
	}
	solo.set_player_connected(10, false)
	_expect((solo.lineups[CurlingConstants.TEAM_RED] as Array).count(10) == 8, "solo disconnect retains all future slots")
	_expect(solo.remap_player_id(10, 11), "solo reconnect remaps temporary peer id")
	_expect((solo.lineups[CurlingConstants.TEAM_RED] as Array).count(11) == 8, "solo reconnect recovers retained slots")
	solo.free()

	var teammates := CurlingMatchController.new()
	teammates.authoritative = true
	teammates.phase = CurlingMatchController.Phase.TACTICS
	teammates.players = {
		20: {"id": 20, "team": CurlingConstants.TEAM_BLUE, "join_order": 0, "connected": true},
		30: {"id": 30, "team": CurlingConstants.TEAM_BLUE, "join_order": 1, "connected": true},
	}
	teammates.lineups[CurlingConstants.TEAM_BLUE] = [20, 30, 20, 30, 20, 30, 20, 30]
	teammates.set_player_connected(20, false)
	_expect(not 20 in teammates.lineups[CurlingConstants.TEAM_BLUE], "disconnect transfers slots when a teammate remains")
	_expect((teammates.lineups[CurlingConstants.TEAM_BLUE] as Array).count(30) == 8, "remaining teammate receives transferred slots")
	teammates.free()


func _test_rules() -> void:
	var tee := CurlingConstants.tee_position(1)
	var score := CurlingRules.score_end([
		{"id": 0, "team": CurlingConstants.TEAM_RED, "position": tee + Vector2(10, 0), "in_play": true},
		{"id": 1, "team": CurlingConstants.TEAM_RED, "position": tee + Vector2(30, 0), "in_play": true},
		{"id": 8, "team": CurlingConstants.TEAM_BLUE, "position": tee + Vector2(40, 0), "in_play": true},
	], 1)
	_expect(int(score["team"]) == CurlingConstants.TEAM_RED and int(score["points"]) == 2, "house counts stones closer than opponent")
	var tied := CurlingRules.score_end([
		{"team": CurlingConstants.TEAM_RED, "position": tee + Vector2(10.00, 0), "in_play": true},
		{"team": CurlingConstants.TEAM_BLUE, "position": tee + Vector2(10.10, 0), "in_play": true},
	], 1)
	_expect(int(tied["team"]) == CurlingConstants.TEAM_NONE, "2mm measurement tie is blank")
	_expect(CurlingRules.crossed_far_hog(Vector2(CurlingConstants.far_hog_x(1) + CurlingConstants.STONE_RADIUS_PX + 1.0, 0), 1), "far hog requires whole stone")
	_expect(CurlingRules.is_out_of_play(Vector2.ZERO + Vector2(0, CurlingConstants.HALF_SHEET_WIDTH_PX), 1), "sideline out")
	var guard := Vector2((CurlingConstants.far_hog_x(1) + tee.x) * 0.5, CurlingConstants.HOUSE_RADII_PX[0] + 50.0)
	var hog_biter := Vector2(CurlingConstants.far_hog_x(1) - CurlingConstants.STONE_RADIUS_PX + 0.1, CurlingConstants.HOUSE_RADII_PX[0] + 50.0)
	var tee_biter_outside_house := Vector2(tee.x - CurlingConstants.STONE_RADIUS_PX + 0.1, CurlingConstants.HOUSE_RADII_PX[0] + 80.0)
	var reverse_tee := CurlingConstants.tee_position(-1)
	var reverse_guard := Vector2((CurlingConstants.far_hog_x(-1) + reverse_tee.x) * 0.5, CurlingConstants.HOUSE_RADII_PX[0] + 50.0)
	_expect(CurlingRules.is_in_free_guard_zone(guard, 1), "guard zone classification")
	_expect(CurlingRules.is_in_free_guard_zone(hog_biter, 1), "hog-line biter is in FGZ")
	_expect(not CurlingRules.is_in_free_guard_zone(tee_biter_outside_house, 1), "tee-line biter is not in FGZ")
	_expect(CurlingRules.is_in_free_guard_zone(reverse_guard, -1), "reverse guard zone classification")
	var pre: Array[Dictionary] = [{"id": 8, "team": CurlingConstants.TEAM_BLUE, "position": guard, "in_play": true}]
	var post: Array[Dictionary] = [{"id": 8, "team": CurlingConstants.TEAM_BLUE, "position": guard, "in_play": false}]
	for delivered_before in range(CurlingRules.FREE_GUARD_PROTECTED_STONES):
		_expect(
			CurlingRules.has_free_guard_violation(pre, post, CurlingConstants.TEAM_RED, delivered_before, 1),
			"FGZ protects delivered stone %d" % [delivered_before + 1]
		)
	_expect(not CurlingRules.has_free_guard_violation(pre, post, CurlingConstants.TEAM_RED, 5, 1), "FGZ protection ends on sixth delivered stone")
	var own_pre: Array[Dictionary] = [{"id": 0, "team": CurlingConstants.TEAM_RED, "position": guard, "in_play": true}]
	var own_removed: Array[Dictionary] = [{"id": 0, "team": CurlingConstants.TEAM_RED, "position": guard, "in_play": false}]
	_expect(not CurlingRules.has_free_guard_violation(own_pre, own_removed, CurlingConstants.TEAM_RED, 2, 1), "FGZ protects opponent guards only")
	var moved_in_play: Array[Dictionary] = [{"id": 8, "team": CurlingConstants.TEAM_BLUE, "position": tee, "in_play": true}]
	_expect(not CurlingRules.has_free_guard_violation(pre, moved_in_play, CurlingConstants.TEAM_RED, 2, 1), "FGZ guard may move if it stays in play")
	var center_guard := Vector2((CurlingConstants.far_hog_x(1) + tee.x) * 0.5, 0.0)
	var center_pre: Array[Dictionary] = [{"id": 8, "team": CurlingConstants.TEAM_BLUE, "position": center_guard, "in_play": true}]
	var ticked_off_center: Array[Dictionary] = [{"id": 8, "team": CurlingConstants.TEAM_BLUE, "position": center_guard + Vector2(0.0, CurlingConstants.STONE_RADIUS_PX + 3.0), "in_play": true}]
	var moved_on_center: Array[Dictionary] = [{"id": 8, "team": CurlingConstants.TEAM_BLUE, "position": center_guard + Vector2(12.0, 0.0), "in_play": true}]
	_expect(CurlingRules.has_no_tick_violation(center_pre, ticked_off_center, CurlingConstants.TEAM_RED, 4, 1), "fifth-stone no-tick rollback")
	_expect(not CurlingRules.has_no_tick_violation(center_pre, ticked_off_center, CurlingConstants.TEAM_RED, 5, 1), "no-tick protection ends on sixth delivered stone")
	_expect(not CurlingRules.has_no_tick_violation(center_pre, moved_on_center, CurlingConstants.TEAM_RED, 2, 1), "center guard may move along center line inside FGZ")


func _test_snapshot_codec() -> void:
	var stones: Array[Dictionary] = []
	for index in range(CurlingConstants.STONE_COUNT):
		stones.append({
			"id": index,
			"position": Vector2(index * 7.31, -index * 1.25),
			"velocity": Vector2(index * 0.5, 0.0),
			"angle": index * 0.01,
			"angular_velocity": 0.5,
			"in_play": index < 4,
			"moving": index < 2,
		})
	var payload := CurlingStoneSnapshotCodec.encode_snapshot(123456, 17, 9, stones)
	_expect(payload.size() == 204, "snapshot is fixed 204 bytes")
	var decoded := CurlingStoneSnapshotCodec.decode_snapshot(payload)
	_expect(bool(decoded.get("valid", false)), "snapshot round trip")
	_expect(int(decoded.get("host_tick", 0)) == 123456 and int(decoded.get("shot_id", 0)) == 9, "snapshot header")
	_expect_close(((decoded["stones"] as Array)[3] as Dictionary)["position"].x, stones[3]["position"].x, 1.0, "centimeter position quantization")
	_expect(not bool(CurlingStoneSnapshotCodec.decode_snapshot(payload.slice(0, 203)).get("valid", true)), "malformed snapshot length rejected")
	var invalid_masks := payload.duplicate()
	invalid_masks[10] = invalid_masks[10] | 0x10
	_expect(not bool(CurlingStoneSnapshotCodec.decode_snapshot(invalid_masks).get("valid", true)), "moving stone outside in-play mask rejected")


func _test_heat_grid() -> void:
	var grid := CurlingHeatGrid.new()
	root.add_child(grid)
	var base_ms := 10_000
	for sample_index in range(24):
		grid.deposit_segment(Vector2(0, 5), Vector2(12.5, 5), 0.05, base_ms + sample_index * 50, false)
	var finish_ms := base_ms + 23 * 50
	var full_heat := grid.sample_heat(Vector2(5, 5), finish_ms)
	_expect(full_heat >= 0.92 and full_heat <= 1.0, "one accurate sweeper reaches full heat in about 1.2 seconds")
	_expect_close(grid.sample_heat(Vector2(5, 5), finish_ms + 600), full_heat * 0.5, 0.04, "heat 0.6 second half-life")
	_expect(grid.sample_heat(Vector2(5, 5), finish_ms + 2500) == 0.0, "heat clears after 2.5 seconds")
	grid.queue_free()


func _test_match_alternation_and_overtime() -> void:
	var scene := load("res://curling/game/match_controller.tscn") as PackedScene
	var match_controller := scene.instantiate() as CurlingMatchController
	root.add_child(match_controller)
	var players: Array[Dictionary] = []
	for index in range(4):
		players.append({"id": index + 1, "nickname": "P%d" % index, "team": 1 if index % 2 == 0 else 2, "join_order": index, "connected": true, "bot": false})
	match_controller.start_match(players, 1, 1, true, 77)
	var private_state := match_controller.export_state_for(CurlingConstants.TEAM_RED)
	_expect((private_state["lineups"] as Dictionary)[CurlingConstants.TEAM_BLUE] == [-1, -1, -1, -1, -1, -1, -1, -1], "opponent tactics stay private before both teams lock")
	match_controller.phase = CurlingMatchController.Phase.AIMING
	match_controller.active_thrower_id = 1
	_expect(not match_controller.host_apply_throw(2, Vector2.RIGHT, 0.5, 0.0), "non-active player cannot throw")
	_expect(not match_controller.host_apply_throw(1, Vector2(NAN, 0.0), 0.5, 0.0), "non-finite throw rejected")
	match_controller.phase = CurlingMatchController.Phase.MOVING
	match_controller.active_team = CurlingConstants.TEAM_RED
	var now_ms := Time.get_ticks_msec()
	_expect(not match_controller.host_apply_sweep(2, Vector2.ZERO, Vector2(20, 0), 0.05, now_ms), "opponent sweep rejected")
	_expect(not match_controller.host_apply_sweep(1, Vector2.ZERO, Vector2(20, 0), 0.05, now_ms - 300), "expired sweep sample rejected")
	_expect(match_controller.host_apply_sweep(1, Vector2.ZERO, Vector2(20, 0), 0.05, now_ms), "valid team sweep accepted")
	var initial_hammer := match_controller.hammer_team
	var initial_direction := match_controller.direction
	match_controller.current_end = 0
	match_controller.scheduled_ends = 1
	match_controller.red_score = 0
	match_controller.blue_score = 0
	match_controller._advance_after_score()
	_expect(match_controller.scheduled_ends == 3, "tie adds a complete 2-End overtime block")
	_expect(match_controller.hammer_team == CurlingConstants.other_team(initial_hammer), "hammer alternates after blank End")
	_expect(match_controller.direction == -initial_direction, "direction alternates after every End")
	match_controller.queue_free()

	var remote_controller := scene.instantiate() as CurlingMatchController
	root.add_child(remote_controller)
	remote_controller.start_match(players, 1, 2, false, 88)
	var remote_tactics_time := remote_controller.phase_time_remaining
	remote_controller._process(1.25)
	_expect_close(remote_controller.phase_time_remaining, remote_tactics_time - 1.25, 0.01, "remote tactics timer ticks locally")
	remote_controller.phase = CurlingMatchController.Phase.AIMING
	remote_controller.phase_time_remaining = 60.0
	remote_controller.active_thrower_id = 2
	remote_controller.local_input_locked = true
	remote_controller._process(2.0)
	_expect_close(remote_controller.phase_time_remaining, 58.0, 0.01, "remote aiming timer ticks locally")
	remote_controller.queue_free()


func _test_settings_persistence() -> void:
	var test_path := "user://curling_settings_test_%d.cfg" % Time.get_ticks_usec()
	var first := CurlingSettingsScript.new()
	first.config_path = test_path
	_expect(first.load_settings() == OK, "missing settings file loads defaults")
	first.set_resolution_index(3)
	first.set_fullscreen_enabled(true)
	first.set_volume_percent(CurlingSettingsScript.CHANNEL_MASTER, 37)
	first.set_volume_percent(CurlingSettingsScript.CHANNEL_SFX, 64)
	first.set_reduced_motion_enabled(true)
	first.set_player_nickname("测试冰壶手")
	_expect(first.flush_pending_save() == OK, "settings file saves")
	_expect(FileAccess.file_exists(test_path), "settings file exists after save")

	var second := CurlingSettingsScript.new()
	second.config_path = test_path
	_expect(second.load_settings() == OK, "settings file reloads")
	_expect(second.get_selected_resolution_index() == 3, "resolution persists")
	_expect(second.is_fullscreen_enabled(), "fullscreen persists")
	_expect(second.get_volume_percent(CurlingSettingsScript.CHANNEL_MASTER) == 37, "master volume persists")
	_expect(second.get_volume_percent(CurlingSettingsScript.CHANNEL_SFX) == 64, "SFX volume persists")
	_expect(second.is_reduced_motion_enabled(), "reduced motion persists")
	_expect(second.get_player_nickname() == "测试冰壶手", "confirmed player nickname persists with settings")
	_expect(second.get_resolution_options().size() == 9, "Arc Nice resolution list is available")
	_expect(second.reset_all_settings() == OK, "settings reset succeeds")
	_expect(not FileAccess.file_exists(test_path), "settings reset removes local config")
	_expect(second.get_selected_resolution_index() == CurlingSettingsScript.DEFAULT_RESOLUTION_INDEX, "settings reset restores defaults")
	first.free()
	second.free()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual=%f expected=%f tolerance=%f)" % [message, actual, expected, tolerance])
