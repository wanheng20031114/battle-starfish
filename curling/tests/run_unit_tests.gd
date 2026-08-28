extends SceneTree

const CurlingSettingsScript := preload("res://curling/settings/curling_settings.gd")
const CurlingAppScript := preload("res://curling/curling.gd")

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_dimensions_and_calibration()
	_test_minimap_geometry()
	_test_player_capacity_and_disconnects()
	_test_lineup_allocation()
	_test_rules()
	_test_snapshot_codec()
	_test_throw_input_precision()
	_test_team_aim_privacy_and_geometry()
	_test_ui_asset_boundary_and_audio_cues()
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
	_expect_close(CurlingConstants.THROW_TEE_POWER, 0.75, 0.0001, "HUD Tee reference power")
	_expect_close(CurlingConstants.THROW_RECOMMENDED_POWER, 0.77, 0.0001, "HUD recommended draw power")

	var draw_distance := 2.0 * CurlingConstants.TEE_FROM_CENTER_M + CurlingConstants.HACK_FROM_TEE_PX / CurlingConstants.PIXELS_PER_METER
	var standard_speed := draw_distance / 22.0 + 0.5 * CurlingConstants.BASE_DRAG_MPS2 * 22.0
	var tee_speed := CurlingConstants.throw_speed_for_power(CurlingConstants.THROW_TEE_POWER)
	var tee_draw := _integrate_calibration(tee_speed, 0.0, 0.0)
	_expect_close(float(tee_draw["forward"]), draw_distance, 0.35, "75 percent no-sweep straight draw reaches tee")
	var swept_tee_draw := _integrate_calibration(tee_speed, 0.0, 1.0)
	_expect(float(swept_tee_draw["forward"]) > draw_distance + 2.5, "75 percent full-sweep draw clearly passes tee")
	var house_reach_m := (
		CurlingConstants.HOUSE_RADII_PX[0] + CurlingConstants.STONE_RADIUS_PX
	) / CurlingConstants.PIXELS_PER_METER
	var recommended_draw := _integrate_calibration(
		CurlingConstants.throw_speed_for_power(CurlingConstants.THROW_RECOMMENDED_POWER), 0.0, 0.0
	)
	var recommended_offset := float(recommended_draw["forward"]) - draw_distance
	_expect(recommended_offset >= 1.0 and recommended_offset <= 1.3, "77 percent recommendation stops safely behind tee")
	_expect(recommended_offset < house_reach_m - 0.7, "77 percent recommendation keeps back-house safety margin")
	_expect_close(
		float(recommended_draw["time"]) + CurlingConstants.SETTLE_TIME_SEC,
		22.67,
		0.20,
		"77 percent recommendation ends just under 23 seconds"
	)
	for front_power in [0.72, 0.74]:
		var front_draw := _integrate_calibration(CurlingConstants.throw_speed_for_power(front_power), 0.0, 0.0)
		var front_offset := float(front_draw["forward"]) - draw_distance
		_expect(front_offset < 0.0 and front_offset >= -house_reach_m, "%d percent no-sweep draw stops in the front house" % roundi(front_power * 100.0))
	for back_power in [0.76, 0.78]:
		var back_draw := _integrate_calibration(CurlingConstants.throw_speed_for_power(back_power), 0.0, 0.0)
		var back_offset := float(back_draw["forward"]) - draw_distance
		_expect(back_offset > 0.0 and back_offset <= house_reach_m, "%d percent no-sweep draw stops in the back house" % roundi(back_power * 100.0))
	var overdraw := _integrate_calibration(CurlingConstants.throw_speed_for_power(0.79), 0.0, 0.0)
	var legal_back_center_m := CurlingConstants.BACK_LINE_FROM_TEE_PX / CurlingConstants.PIXELS_PER_METER + CurlingConstants.STONE_RADIUS_M
	_expect(float(overdraw["forward"]) - draw_distance > legal_back_center_m, "79 percent no-sweep draw crosses the legal back-line limit")
	var lower_step := tee_speed - CurlingConstants.throw_speed_for_power(0.70)
	var upper_step := CurlingConstants.throw_speed_for_power(0.80) - tee_speed
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
	_expect_close(absf(float(cold["lateral"])), 2.49, 0.15, "expanded maximum curl")
	_expect_close(float(swept["forward"]) - float(cold["forward"]), 3.0, 0.40, "full heat adds about 3m")
	var curl_reduction := 1.0 - absf(float(swept["lateral"]) / float(cold["lateral"]))
	_expect_close(curl_reduction, 0.35, 0.04, "full heat reduces final curl about 35 percent")


func _test_minimap_geometry() -> void:
	var minimap := CurlingMinimap.new()
	minimap.size = Vector2(312.0, 64.0)
	var sheet_rect := minimap.minimap_sheet_rect()
	var physical_aspect := CurlingConstants.SHEET_LENGTH_PX / CurlingConstants.SHEET_WIDTH_PX
	_expect_close(sheet_rect.size.x / sheet_rect.size.y, physical_aspect, 0.0001, "minimap preserves sheet aspect ratio")
	var world_scale := minimap.minimap_world_scale()
	var tee := CurlingConstants.tee_position(1)
	var tee_point := minimap.world_to_minimap(tee)
	var house_x := minimap.world_to_minimap(tee + Vector2(CurlingConstants.HOUSE_RADII_PX[0], 0.0))
	var house_y := minimap.world_to_minimap(tee + Vector2(0.0, CurlingConstants.HOUSE_RADII_PX[0]))
	var expected_house_radius := CurlingConstants.HOUSE_RADII_PX[0] * world_scale
	_expect_close(tee_point.distance_to(house_x), expected_house_radius, 0.001, "minimap house uses the world x scale")
	_expect_close(tee_point.distance_to(house_y), expected_house_radius, 0.001, "minimap house uses the world y scale")
	_expect(expected_house_radius >= 11.0, "minimap outer house is legible at the HUD size")
	var world_corner := minimap.world_to_minimap(Vector2(CurlingConstants.HALF_SHEET_LENGTH_PX, CurlingConstants.HALF_SHEET_WIDTH_PX))
	_expect_close(world_corner.x, sheet_rect.end.x, 0.001, "minimap maps the sheet length exactly")
	_expect_close(world_corner.y, sheet_rect.end.y, 0.001, "minimap maps the sheet width exactly")
	minimap.free()


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
	_expect(
		CurlingRules.protected_guard_ids(pre, CurlingConstants.TEAM_RED, 0, 1) == [8],
		"authoritative guard query identifies the opponent FGZ stone",
	)
	_expect(
		CurlingRules.protected_guard_ids(pre, CurlingConstants.TEAM_RED, 5, 1).is_empty(),
		"authoritative guard query clears after the fifth delivered stone",
	)
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

	var controller_scene := load("res://curling/game/match_controller.tscn") as PackedScene
	var players: Array[Dictionary] = [
		{"id": 1, "nickname": "红", "team": CurlingConstants.TEAM_RED, "connected": true},
		{"id": 2, "nickname": "蓝", "team": CurlingConstants.TEAM_BLUE, "connected": true},
	]
	var authority := controller_scene.instantiate() as CurlingMatchController
	root.add_child(authority)
	authority.start_match(players, 1, 1, true, 91)
	authority.active_team = CurlingConstants.TEAM_RED
	authority.delivered_count = 2
	authority.direction = 1
	authority._pre_shot_state = pre
	authority._refresh_guard_protection_for_current_throw()
	_expect(authority.protected_stone_mask == 1 << 8, "host stores protected guards as an authoritative mask")
	var exported_guard_state := authority.export_state_for(CurlingConstants.TEAM_BLUE)
	_expect(int(exported_guard_state.get("protected_stone_mask", 0)) == 1 << 8, "guard mask is part of match state")
	authority.free()

	var remote := controller_scene.instantiate() as CurlingMatchController
	root.add_child(remote)
	remote.start_match(players, 1, 2, false, 92)
	exported_guard_state["state_sequence"] = remote.state_sequence + 1
	_expect(remote.apply_remote_state(exported_guard_state), "remote accepts authoritative guard state")
	_expect(remote.protected_stone_mask == 1 << 8 and remote._stones[8].guard_protected, "remote applies protection to the same stone")
	remote.free()


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


func _test_throw_input_precision() -> void:
	_expect_close(CurlingConstants.MAX_SPIN_RADPS, 2.0, 0.0001, "expanded spin limit")
	var exact_direction := Vector2.RIGHT.rotated(deg_to_rad(0.0123456789))
	var exact_power := 0.77123456789
	var exact_spin := CurlingConstants.MAX_SPIN_RADPS - 0.000123456
	var encoded := CurlingNet.encode_message({
		"type": "throw",
		"direction": exact_direction,
		"power": exact_power,
		"spin": exact_spin,
	})
	var decoded := CurlingNet.decode_message(encoded)
	_expect(str(decoded.get("type", "")) == "throw", "member throw message round trip")
	_expect(
		(decoded.get("direction", Vector2.ZERO) as Vector2).distance_to(exact_direction) <= 0.000000000001,
		"member throw direction keeps native Vector2 precision",
	)
	_expect_close(float(decoded.get("power", 0.0)), exact_power, 0.000000000001, "member throw power keeps double precision")
	_expect_close(float(decoded.get("spin", 0.0)), exact_spin, 0.000000000001, "member throw spin keeps double precision")

	var scene := load("res://curling/game/match_controller.tscn") as PackedScene
	var controller := scene.instantiate() as CurlingMatchController
	root.add_child(controller)
	var players: Array[Dictionary] = [
		{"id": 1, "nickname": "Host", "team": CurlingConstants.TEAM_RED, "join_order": 0, "connected": true, "bot": false},
		{"id": 2, "nickname": "Member", "team": CurlingConstants.TEAM_BLUE, "join_order": 1, "connected": true, "bot": false},
	]
	controller.start_match(players, 1, 1, true, 99117)
	controller.direction = 1
	controller._force_lock_all_teams()
	controller._dragging = true
	controller._drag_aim_direction = Vector2.RIGHT
	controller._drag_power_adjustment = 0.0
	var max_drag := minf(controller.get_viewport_rect().size.x, controller.get_viewport_rect().size.y) / 3.0
	controller._drag_origin_screen = Vector2.ZERO
	controller._drag_current_screen = Vector2(8.0 + 0.77 * (max_drag - 8.0), 0.0)
	controller._adjust_drag_aim_degrees(0.01)
	controller._adjust_drag_power(0.0001)
	_expect_close(controller._current_aim_offset_degrees(), 0.01, 0.000001, "keyboard aim adjustment is finer than one mouse pixel")
	_expect_close(controller._current_drag_power(), 0.7701, 0.000001, "keyboard power adjustment preserves sub-percent precision")
	controller._cancel_drag()
	var precision_key := InputEventKey.new()
	precision_key.keycode = KEY_A
	_expect(controller._is_drag_precision_key(precision_key), "A key is reserved for aim precision while dragging")

	var member_intent: Dictionary = {}
	controller.throw_intent.connect(func(direction: Vector2, power: float, spin: float) -> void:
		member_intent["direction"] = direction
		member_intent["power"] = power
		member_intent["spin"] = spin
	)
	controller.authoritative = false
	controller.phase = CurlingMatchController.Phase.AIMING
	controller.local_player_id = 2
	controller.active_thrower_id = 2
	controller._dragging = true
	controller._drag_origin_screen = Vector2.ZERO
	controller._drag_current_screen = Vector2(8.0 + exact_power * (max_drag - 8.0), 0.0)
	controller._drag_power_adjustment = 0.0
	controller._drag_aim_direction = exact_direction
	controller._current_spin = exact_spin
	controller._release_local_throw()
	_expect(not member_intent.is_empty(), "member release emits a throw intent")
	_expect((member_intent.get("direction", Vector2.ZERO) as Vector2).distance_to(exact_direction) <= 0.000000000001, "member release keeps fine aim direction")
	_expect_close(float(member_intent.get("power", 0.0)), exact_power, 0.0000001, "member release keeps fine power")
	_expect_close(float(member_intent.get("spin", 0.0)), exact_spin, 0.000000000001, "member release keeps expanded spin")

	controller.start_match(players, 1, 1, true, 99117)
	controller.direction = 1
	controller._force_lock_all_teams()
	controller.active_thrower_id = 1
	_expect(controller.host_apply_throw(1, exact_direction, exact_power, exact_spin), "host local throw is accepted")
	var host_stone: CurlingStone = controller._stones[controller.active_stone_id]
	var host_velocity := host_stone.linear_velocity
	var host_spin := host_stone.angular_velocity

	controller.start_match(players, 1, 1, true, 99117)
	controller.direction = 1
	controller._force_lock_all_teams()
	controller.active_thrower_id = 2
	var member_direction := decoded.get("direction", Vector2.ZERO) as Vector2
	var member_power := float(decoded.get("power", 0.0))
	var member_spin := float(decoded.get("spin", 0.0))
	_expect(controller.host_apply_throw(2, member_direction, member_power, member_spin), "member network throw is accepted by host")
	var member_stone: CurlingStone = controller._stones[controller.active_stone_id]
	_expect(member_stone.linear_velocity.distance_to(host_velocity) <= 0.000001, "host and member throws create identical initial velocity")
	_expect_close(member_stone.angular_velocity, host_spin, 0.000001, "host and member throws create identical angular velocity")
	_expect_close(
		member_stone.linear_velocity.length() / CurlingConstants.PIXELS_PER_METER,
		CurlingConstants.throw_speed_for_power(exact_power),
		0.000001,
		"member power maps to the configured authoritative speed",
	)
	controller.queue_free()


func _test_team_aim_privacy_and_geometry() -> void:
	var room_players := {
		1: {"id": 1, "team": CurlingConstants.TEAM_RED, "connected": true},
		2: {"id": 2, "team": CurlingConstants.TEAM_RED, "connected": true},
		3: {"id": 3, "team": CurlingConstants.TEAM_BLUE, "connected": true},
		4: {"id": 4, "team": CurlingConstants.TEAM_RED, "connected": true},
		5: {"id": 5, "team": CurlingConstants.TEAM_RED, "connected": false},
	}
	_expect(
		CurlingAppScript.team_aim_recipient_ids(
			room_players, 2, CurlingConstants.TEAM_RED, 1
		) == [4],
		"aim preview is routed only to connected same-team remote peers",
	)
	var sanitized_launch := CurlingAppScript.sanitize_authoritative_event_for_broadcast({
		"type": "throw_launched",
		"shot_id": 7,
		"player_id": 2,
		"direction": Vector2.RIGHT,
		"power": 0.77125,
		"spin": 1.25,
	})
	_expect(not sanitized_launch.has("direction"), "public launch event omits the private aim direction")
	_expect(not sanitized_launch.has("power"), "public launch event omits the private power")
	_expect(not sanitized_launch.has("spin"), "public launch event omits the private spin")
	_expect(int(sanitized_launch.get("shot_id", -1)) == 7, "public launch event keeps its synchronization identity")
	var cursor_scene := load("res://curling/ui/remote_cursor.tscn") as PackedScene
	var private_cursor := cursor_scene.instantiate() as CurlingRemoteCursor
	root.add_child(private_cursor)
	private_cursor.configure({
		"id": 2,
		"nickname": "Thrower",
		"team": CurlingConstants.TEAM_RED,
		"color": Color.WHITE,
	})
	_expect(private_cursor.visible, "remote cursor starts visible for ordinary shared movement")
	private_cursor.set_tactical_visibility(false)
	_expect(not private_cursor.visible, "opponent can hide the active thrower's tactical cursor")
	private_cursor.configure({
		"id": 2,
		"nickname": "Thrower",
		"team": CurlingConstants.TEAM_RED,
		"color": Color.WHITE,
	})
	private_cursor.set_target(Vector2(240.0, 180.0), true, false)
	_expect(not private_cursor.visible, "identity refresh and stale cursor packets cannot bypass tactical privacy")
	private_cursor.set_tactical_visibility(true)
	_expect(private_cursor.visible, "cursor is restored after the private aiming phase ends")
	private_cursor.queue_free()

	var players: Array[Dictionary] = [
		{"id": 1, "nickname": "Thrower", "team": CurlingConstants.TEAM_RED, "join_order": 0, "connected": true, "bot": false},
		{"id": 2, "nickname": "Opponent", "team": CurlingConstants.TEAM_BLUE, "join_order": 1, "connected": true, "bot": false},
		{"id": 3, "nickname": "Teammate", "team": CurlingConstants.TEAM_RED, "join_order": 2, "connected": true, "bot": false},
		{"id": 4, "nickname": "Opponent2", "team": CurlingConstants.TEAM_BLUE, "join_order": 3, "connected": true, "bot": false},
	]
	var scene := load("res://curling/game/match_controller.tscn") as PackedScene
	var teammate := scene.instantiate() as CurlingMatchController
	root.add_child(teammate)
	teammate.start_match(players, 1, 3, false, 11991)
	teammate.phase = CurlingMatchController.Phase.AIMING
	teammate.direction = 1
	teammate.active_team = CurlingConstants.TEAM_RED
	teammate.active_thrower_id = 1
	teammate.active_stone_id = 0
	teammate._stones[0].prepare_for_delivery(CurlingConstants.hack_position(1), 1, Color.WHITE)
	var teammate_hud := {"data": {}}
	teammate.hud_changed.connect(func(data: Dictionary) -> void: teammate_hud["data"] = data)
	var shared_direction := Vector2.RIGHT.rotated(deg_to_rad(0.27))
	_expect(teammate.show_aim_preview(shared_direction, 0.77125, 1.25), "same-team aim preview is accepted")
	_expect(teammate.has_visible_aim_preview(), "same-team aim guide is visible")
	_expect(not teammate.has_method("_predict_path"), "formal match no longer exposes a full path predictor")
	var shared_data := teammate.get_aim_preview_data()
	_expect_close(float(shared_data.get("power", 0.0)), 0.77125, 0.000001, "teammate receives exact aim power")
	_expect_close(float(shared_data.get("spin", 0.0)), 1.25, 0.000001, "teammate receives exact aim spin")
	var teammate_hud_data := teammate_hud["data"] as Dictionary
	_expect(bool(teammate_hud_data.get("can_view_aim", false)), "teammate HUD is allowed to show tactical values")
	_expect(not bool(teammate_hud_data.get("can_adjust_aim", true)), "teammate HUD does not advertise throw controls")
	_expect(bool(teammate_hud_data.get("aim_from_teammate", false)), "teammate HUD marks remote shared aim")
	_expect_close(float(teammate_hud_data.get("power", 0.0)), 0.77125, 0.000001, "teammate HUD shares power")
	_expect_close(float(teammate_hud_data.get("aim_offset_degrees", 0.0)), 0.27, 0.00001, "teammate HUD shares aim angle")

	var positive_geometry := teammate.aim_guide.get_debug_geometry()
	var straight_start := positive_geometry.get("straight_start", Vector2.ZERO) as Vector2
	var straight_end := positive_geometry.get("straight_end", Vector2.ZERO) as Vector2
	var positive_arrow := positive_geometry.get("arrow_direction", Vector2.ZERO) as Vector2
	var curve_points := positive_geometry.get("curve_points", PackedVector2Array()) as PackedVector2Array
	_expect_close(
		straight_start.distance_to(straight_end),
		CurlingConstants.SHEET_LENGTH_PX - CurlingConstants.STONE_RADIUS_PX - 7.0,
		0.01,
		"formal straight guide spans the full sheet",
	)
	_expect(curve_points.size() == 33, "spin guide uses a short sampled dashed curve")
	_expect(curve_points[-1].distance_to(straight_start) < 230.0, "spin guide keeps its short visual range")
	_expect(curve_points[-1].distance_to(straight_start) < straight_end.distance_to(straight_start), "spin guide is shorter than the straight guide")
	_expect(absf(positive_arrow.dot(shared_direction.normalized())) < 0.0001, "spin arrow is perpendicular to the aim line")
	_expect(shared_direction.cross(positive_arrow) > 0.0, "positive spin arrow points to the positive curl side")
	_expect(float(positive_geometry.get("guide_angle_degrees", 0.0)) > 0.0, "positive spin has a positive exaggerated guide angle")

	_expect(teammate.show_aim_preview(shared_direction, 0.77125, -1.25), "negative teammate spin preview is accepted")
	var negative_geometry := teammate.aim_guide.get_debug_geometry()
	var negative_arrow := negative_geometry.get("arrow_direction", Vector2.ZERO) as Vector2
	_expect(shared_direction.cross(negative_arrow) < 0.0, "negative spin arrow points to the opposite curl side")
	_expect(float(negative_geometry.get("guide_angle_degrees", 0.0)) < 0.0, "negative spin has a negative exaggerated guide angle")
	var heartbeat := {"count": 0, "power": 0.0, "spin": 0.0}
	teammate.aim_preview_intent.connect(func(_direction: Vector2, power: float, spin: float) -> void:
		heartbeat["count"] = int(heartbeat["count"]) + 1
		heartbeat["power"] = power
		heartbeat["spin"] = spin
	)
	teammate.active_thrower_id = 3
	teammate._emit_hud()
	var thrower_hud_data := teammate_hud["data"] as Dictionary
	_expect(bool(thrower_hud_data.get("can_adjust_aim", false)), "local thrower HUD advertises aim controls")
	_expect(not bool(thrower_hud_data.get("aim_dragging", true)), "local thrower HUD starts outside drag adjustment")
	_expect(teammate.show_aim_preview(shared_direction, 0.76875, -0.8, true), "local thrower preview is accepted")
	teammate._last_aim_preview_ms = 0
	teammate._send_local_aim_preview_heartbeat()
	_expect(int(heartbeat["count"]) == 1, "stationary local aim sends a heartbeat instead of expiring for teammates")
	_expect_close(float(heartbeat["power"]), 0.76875, 0.000001, "aim heartbeat preserves exact power")
	_expect_close(float(heartbeat["spin"]), -0.8, 0.000001, "aim heartbeat preserves exact spin")
	teammate.hide_aim_preview()
	_expect(not teammate.has_visible_aim_preview(), "team preview can be cleared without leaving a stale guide")
	teammate.queue_free()

	var opponent := scene.instantiate() as CurlingMatchController
	root.add_child(opponent)
	opponent.start_match(players, 1, 2, false, 11992)
	opponent.phase = CurlingMatchController.Phase.AIMING
	opponent.direction = 1
	opponent.active_team = CurlingConstants.TEAM_RED
	opponent.active_thrower_id = 1
	opponent.active_stone_id = 0
	opponent._stones[0].prepare_for_delivery(CurlingConstants.hack_position(1), 1, Color.WHITE)
	var opponent_hud := {"data": {}}
	opponent.hud_changed.connect(func(data: Dictionary) -> void: opponent_hud["data"] = data)
	_expect(not opponent.show_aim_preview(shared_direction, 0.82, 1.5), "opponent aim preview is rejected by the controller")
	opponent._emit_hud()
	var opponent_hud_data := opponent_hud["data"] as Dictionary
	_expect(not opponent.has_visible_aim_preview(), "opponent never renders tactical aim geometry")
	_expect(not bool(opponent_hud_data.get("can_view_aim", true)), "opponent HUD cannot reveal aim values")
	_expect(not bool(opponent_hud_data.get("can_adjust_aim", true)), "opponent HUD does not advertise throw controls")
	_expect_close(float(opponent_hud_data.get("power", -1.0)), 0.0, 0.000001, "opponent HUD receives no power")
	_expect_close(float(opponent_hud_data.get("spin", -1.0)), 0.0, 0.000001, "opponent HUD receives no spin")
	opponent.queue_free()


func _test_ui_asset_boundary_and_audio_cues() -> void:
	var main_settings_scene := FileAccess.get_file_as_string(
		"res://scene/main_menu/main_menu_settings_panel.tscn"
	)
	var curling_scene := FileAccess.get_file_as_string("res://curling/curling.tscn")
	_expect(
		main_settings_scene.contains("assets/ui_pixel/production/large_sandstone_frame.png"),
		"main-menu settings keeps its generated sandstone frame",
	)
	_expect(
		main_settings_scene.contains("assets/ui_pixel/production/icons/settings_40/"),
		"main-menu settings keeps its generated icon family",
	)
	_expect(
		curling_scene.contains("res://curling/ui/geometric_backdrop.tscn"),
		"curling multiplayer uses the native geometric backdrop",
	)
	_expect(
		not curling_scene.contains("assets/main_menu/")
		and not curling_scene.contains("assets/ui_pixel/"),
		"curling multiplayer does not reuse decorative generated images",
	)
	_expect(
		curling_scene.contains("GuardStatus")
		and curling_scene.contains("GuardProgress")
		and curling_scene.contains("ControlRow")
		and curling_scene.contains("KeyGuide"),
		"match HUD exposes guard status and separates its control guidance rows",
	)

	var stone_scene := load("res://curling/game/curling_stone.tscn") as PackedScene
	var protected_stone := stone_scene.instantiate() as CurlingStone
	root.add_child(protected_stone)
	protected_stone.in_play = true
	protected_stone.visible = true
	protected_stone.set_guard_protected(true)
	var protection_material := protected_stone.protection_overlay.material as ShaderMaterial
	_expect(protected_stone.protection_overlay.visible, "protected guard enables its geometric overlay")
	_expect(
		protection_material != null
		and protection_material.shader != null
		and protection_material.shader.code.contains("TIME")
		and protection_material.shader.code.contains("diagonal_progress"),
		"protected guard shader contains animated diagonal sheen",
	)
	protected_stone.set_guard_protected(false)
	_expect(not protected_stone.protection_overlay.visible, "guard overlay disables with authoritative state")
	protected_stone.free()

	_expect(CurlingAppScript.SHOT_CLOCK_WARNING_SECONDS.size() == 10, "shot clock has ten warning seconds")
	for second in range(1, 11):
		_expect(
			CurlingAppScript.SHOT_CLOCK_WARNING_SECONDS.has(second),
			"shot clock warns at %d seconds" % second,
		)

	var audio_scene := load("res://curling/audio/curling_audio.tscn") as PackedScene
	var audio := audio_scene.instantiate() as CurlingAudio
	root.add_child(audio)
	var cue_players: Array[AudioStreamPlayer] = [
		audio.ui_player,
		audio.launch_player,
		audio.countdown_player,
		audio.result_player,
		audio.alert_player,
		audio.impact_player,
		audio.sweep_player,
	]
	for player in cue_players:
		_expect(player.stream is AudioStreamWAV, "%s has a generated PCM cue" % player.name)
		_expect((player.stream as AudioStreamWAV).data.size() > 1000, "%s cue contains audible samples" % player.name)
	var distinct_streams := {}
	for player in cue_players:
		distinct_streams[(player.stream as AudioStreamWAV).get_instance_id()] = true
	_expect(distinct_streams.size() == cue_players.size(), "gameplay cues do not reuse the UI click stream")
	_expect(
		CurlingAudio.countdown_pitch_for_second(1) > CurlingAudio.countdown_pitch_for_second(10),
		"countdown pitch increases toward one second",
	)
	audio.free()


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
