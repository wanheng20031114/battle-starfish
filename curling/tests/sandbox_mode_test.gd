extends Node

const SANDBOX_SCENE := preload("res://curling/sandbox/curling_sandbox.tscn")
const SANDBOX_CONTROLLER_SCENE := preload("res://curling/sandbox/curling_sandbox_controller.tscn")
const STONE_SCENE := preload("res://curling/game/curling_stone.tscn")
const FULL_HEAT_GRID_SCRIPT := preload("res://curling/tests/full_heat_grid.gd")

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var full_scene := SANDBOX_SCENE.instantiate()
	_expect(full_scene.get_node_or_null("CurlingNet") == null, "sandbox scene has no network client")
	_expect(full_scene.get_node_or_null("LanDiscovery") == null, "sandbox scene has no lobby discovery")
	full_scene.free()
	var controller := SANDBOX_CONTROLLER_SCENE.instantiate() as CurlingSandboxController
	add_child(controller)
	await get_tree().process_frame
	_expect(controller.pending_stone != null, "sandbox starts with a pending stone")
	_expect(controller.get_total_shots() == 0, "sandbox starts with empty history")
	var pending_screen_position := controller.get_canvas_transform() * controller.pending_stone.global_position
	_expect(controller._can_begin_drag(pending_screen_position), "screen coordinates can select the pending stone")
	_expect(not controller._can_begin_drag(pending_screen_position + Vector2(240.0, 160.0)), "distant screen coordinates do not select the pending stone")
	_expect(not controller._is_out_of_play(CurlingConstants.hack_position(1)), "hack remains inside sandbox boundary")
	_expect(controller._is_out_of_play(Vector2(0.0, CurlingConstants.HALF_SHEET_WIDTH_PX)), "side boundary removes stones")
	_expect(controller._is_out_of_play(Vector2(CurlingConstants.TEE_FROM_CENTER_PX + CurlingConstants.BACK_LINE_FROM_TEE_PX + CurlingConstants.STONE_RADIUS_PX + 1.0, 0.0)), "back line boundary removes stones")

	for index in range(32):
		var expected_team := CurlingConstants.TEAM_RED if index % 2 == 0 else CurlingConstants.TEAM_BLUE
		var expected_direction := 1 if index % 2 == 0 else -1
		_expect(controller.set_next_team(expected_team), "shot %d team can be selected" % (index + 1))
		_expect(controller.set_next_direction(expected_direction), "shot %d direction can be selected" % (index + 1))
		_launch_pending(controller, 0.75, 0.15 if index % 3 == 0 else 0.0)
		_expect(controller.pending_stone == null, "shot %d consumes pending stone" % (index + 1))
		_expect(not controller._spawn_pending_stone(), "shot %d blocks a concurrent pending stone" % (index + 1))
		var record: CurlingShotRecord = controller.get_selected_record()
		_expect(record != null and record.shot_id == index + 1, "shot %d keeps monotonic id" % (index + 1))
		_expect(record != null and record.team == expected_team, "shot %d keeps selected team" % (index + 1))
		_expect(record != null and record.throw_direction == expected_direction, "shot %d keeps selected direction" % (index + 1))
		_expect(controller.remove_selected(), "shot %d can be removed while moving" % (index + 1))
		await get_tree().physics_frame
		await get_tree().physics_frame
		_expect(controller.pending_stone != null, "shot %d removal restores ready state" % (index + 1))

	_expect(controller.get_total_shots() == 32, "sandbox history is not capped at sixteen stones")
	_expect(controller.records[0].shot_id == 1 and controller.records[-1].shot_id == 32, "sandbox ids remain ordered through 32 shots")
	_expect(controller.select_record(1), "removed history remains selectable")
	_expect(not controller.remove_selected(), "removed history cannot be removed twice")

	controller.clear_history()
	_expect(controller.get_total_shots() == 0, "clear history removes records")
	_expect(controller.pending_stone != null and controller.pending_stone.stone_id == 1, "clear history resets shot numbering")
	controller.set_next_team(CurlingConstants.TEAM_RED)
	controller.set_next_direction(1)
	_launch_pending(controller, 0.75, 0.0)
	_expect(controller.active_record != null, "physics telemetry shot launches")
	for _frame in range(12):
		await get_tree().physics_frame
	var live_record: CurlingShotRecord = controller.active_record
	var cold_telemetry: Dictionary = live_record.latest_telemetry
	_expect_close(float(cold_telemetry.get("drag_force_n", 0.0)), 2.869, 0.02, "cold friction force")
	_expect(float(cold_telemetry.get("speed_mps", 0.0)) > 0.0, "live telemetry exposes speed")
	_expect(live_record.path_length_m > 0.0, "live record accumulates path")
	_expect(live_record.trace.size() >= 2, "live record accumulates trajectory")
	_expect(live_record.samples.size() >= 2, "live record samples curves at runtime")
	controller.remove_selected()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var retained_count: int = controller.get_total_shots()
	controller.clear_field()
	_expect(controller.get_total_shots() == retained_count, "clear field retains history")

	await _test_full_heat_telemetry()
	controller.queue_free()
	await get_tree().process_frame
	call_deferred("_finish")


func _test_full_heat_telemetry() -> void:
	var heat_grid := FULL_HEAT_GRID_SCRIPT.new() as CurlingHeatGrid
	add_child(heat_grid)
	var stone := STONE_SCENE.instantiate() as CurlingStone
	add_child(stone)
	stone.heat_grid = heat_grid
	stone.authoritative = true
	stone.prepare_for_delivery(Vector2.ZERO, 1, Color.WHITE)
	stone.launch(Vector2.RIGHT, CurlingConstants.throw_speed_for_power(0.75), 0.0)
	for _frame in range(6):
		await get_tree().physics_frame
	var telemetry := stone.get_physics_telemetry()
	var expected_force := (
		CurlingConstants.STONE_MASS_KG
		* CurlingConstants.BASE_DRAG_MPS2
		* (1.0 - CurlingConstants.SWEEP_DRAG_REDUCTION)
	)
	_expect_close(float(telemetry.get("heat", 0.0)), 1.0, 0.0001, "full heat telemetry")
	_expect_close(float(telemetry.get("drag_force_n", 0.0)), expected_force, 0.02, "full heat friction force")
	stone.remove_from_play()
	stone.queue_free()
	heat_grid.queue_free()
	await get_tree().process_frame


func _launch_pending(controller: CurlingSandboxController, power: float, spin: float) -> void:
	var max_drag := minf(controller.get_viewport_rect().size.x, controller.get_viewport_rect().size.y) / 3.0
	controller._dragging = true
	controller._drag_origin_screen = Vector2.ZERO
	controller._drag_current_screen = Vector2(8.0 + power * (max_drag - 8.0), 0.0)
	controller._drag_power_adjustment = 0.0
	controller._drag_aim_direction = Vector2(float(controller.next_direction), 0.0)
	controller._current_spin = spin
	controller._release_throw()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s: %.6f vs %.6f" % [message, actual, expected])


func _finish() -> void:
	if _failures.is_empty():
		print("CURLING_SANDBOX_OK checks=%d launches=32" % _checks)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("CURLING_SANDBOX_FAIL: %s" % failure)
	get_tree().quit(1)
