extends Node

const REPEAT_COUNT := 4
const FACTOR_POWERS := [0.50, 0.75, 0.77, 1.00]
const AIM_ANGLES_DEG := [-6.0, -3.0, 0.0, 3.0, 6.0]
const SPINS_RADPS := [-1.2, -0.6, 0.0, 0.6, 1.2]
const MAX_SIMULATION_FRAMES := 1900

@onready var controller: CurlingMatchController = $MatchController

var _stones: Array[CurlingStone] = []
var _failures: Array[String] = []
var _max_intrinsic_time_spread_sec := 0.0
var _max_intrinsic_path_spread_m := 0.0


func _ready() -> void:
	await get_tree().physics_frame
	_collect_stones()
	if _stones.size() != CurlingConstants.STONE_COUNT:
		_failures.append("experiment requires %d match stones, got %d" % [CurlingConstants.STONE_COUNT, _stones.size()])
		_finish([], [], [])
		return

	var power_records := await _run_conditions(_power_sweep_conditions(), false)
	var intrinsic_records := await _run_conditions(_factor_conditions(), false)
	var sheet_records := await _run_conditions(_factor_conditions(), true)
	_analyze_power_sweep(power_records)
	_analyze_intrinsic_factorial(intrinsic_records)
	_analyze_sheet_factorial(sheet_records)
	_finish(power_records, intrinsic_records, sheet_records)


func _collect_stones() -> void:
	for child in controller.stones_root.get_children():
		if child is CurlingStone:
			_stones.append(child as CurlingStone)
	_stones.sort_custom(func(a: CurlingStone, b: CurlingStone) -> bool: return a.stone_id < b.stone_id)


func _power_sweep_conditions() -> Array[Dictionary]:
	var conditions: Array[Dictionary] = []
	for repeat_index in range(REPEAT_COUNT):
		for power_step in range(21):
			conditions.append({
				"power": float(power_step) * 0.05,
				"aim_deg": 0.0,
				"spin_radps": 0.0,
				"repeat": repeat_index,
			})
	return conditions


func _factor_conditions() -> Array[Dictionary]:
	var conditions: Array[Dictionary] = []
	for repeat_index in range(REPEAT_COUNT):
		for power in FACTOR_POWERS:
			for aim_deg in AIM_ANGLES_DEG:
				for spin_radps in SPINS_RADPS:
					conditions.append({
						"power": float(power),
						"aim_deg": float(aim_deg),
						"spin_radps": float(spin_radps),
						"repeat": repeat_index,
					})
	return conditions


func _run_conditions(conditions: Array[Dictionary], use_sheet_boundaries: bool) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var batch_start := 0
	while batch_start < conditions.size():
		var batch_end := mini(batch_start + _stones.size(), conditions.size())
		var batch: Array[Dictionary] = []
		for index in range(batch_start, batch_end):
			batch.append(conditions[index])
		var batch_records := await _run_batch(batch, use_sheet_boundaries)
		records.append_array(batch_records)
		batch_start = batch_end
	return records


func _run_batch(conditions: Array[Dictionary], use_sheet_boundaries: bool) -> Array[Dictionary]:
	controller.phase = CurlingMatchController.Phase.IDLE
	controller.heat_grid.clear()
	for stone in _stones:
		stone.remove_from_play()
	await get_tree().physics_frame

	var starts: Array[Vector2] = []
	var previous_positions: Array[Vector2] = []
	var previous_rotations := PackedFloat32Array()
	var path_lengths_px := PackedFloat32Array()
	var accumulated_rotation_rad := PackedFloat32Array()
	var finished := PackedByteArray()
	var records: Array[Dictionary] = []
	previous_rotations.resize(conditions.size())
	path_lengths_px.resize(conditions.size())
	accumulated_rotation_rad.resize(conditions.size())
	finished.resize(conditions.size())
	for index in range(conditions.size()):
		var start := (
			CurlingConstants.hack_position(1)
			if use_sheet_boundaries
			else Vector2(0.0, float(index) * 2000.0)
		)
		starts.append(start)
		previous_positions.append(start)
		var stone := _stones[index]
		stone.prepare_for_delivery(start, index + 1, Color.WHITE)
	await get_tree().physics_frame

	for index in range(conditions.size()):
		var condition := conditions[index]
		var stone := _stones[index]
		# 实验排除其他壶碰撞；真实赛道边界仍由CurlingRules逐帧判定。
		stone.collision_layer = 0
		stone.collision_mask = 0
		previous_rotations[index] = stone.rotation
		var direction := Vector2.RIGHT.rotated(deg_to_rad(float(condition["aim_deg"])))
		stone.launch(
			direction,
			CurlingConstants.throw_speed_for_power(float(condition["power"])),
			float(condition["spin_radps"])
		)

	var completed := 0
	var frame_count := 0
	while completed < conditions.size() and frame_count < MAX_SIMULATION_FRAMES:
		await get_tree().physics_frame
		frame_count += 1
		for index in range(conditions.size()):
			if finished[index] != 0:
				continue
			var stone := _stones[index]
			var position := stone.global_position
			path_lengths_px[index] += position.distance_to(previous_positions[index])
			previous_positions[index] = position
			accumulated_rotation_rad[index] += wrapf(
				stone.rotation - previous_rotations[index], -PI, PI
			)
			previous_rotations[index] = stone.rotation
			var event := ""
			if use_sheet_boundaries and CurlingRules.is_out_of_play(position, 1):
				event = _out_event(position)
			elif stone.linear_velocity.length() <= CurlingConstants.STOP_SPEED_PXPS:
				event = "stopped"
			if event.is_empty():
				continue
			records.append(_make_record(
				conditions[index],
				stone,
				starts[index],
				path_lengths_px[index],
				accumulated_rotation_rad[index],
				frame_count,
				event,
				use_sheet_boundaries
			))
			finished[index] = 1
			completed += 1
			stone.freeze_at_rest()

	if completed != conditions.size():
		_failures.append("batch timed out after %d frames (%d/%d complete)" % [frame_count, completed, conditions.size()])
		for index in range(conditions.size()):
			if finished[index] == 0:
				_stones[index].freeze_at_rest()
	return records


func _make_record(
	condition: Dictionary,
	stone: CurlingStone,
	start: Vector2,
	path_length_px: float,
	rotation_rad: float,
	frame_count: int,
	event: String,
	use_sheet_boundaries: bool
) -> Dictionary:
	var direction := Vector2.RIGHT.rotated(deg_to_rad(float(condition["aim_deg"])))
	var displacement := stone.global_position - start
	var record := condition.duplicate()
	record["stone_id"] = stone.stone_id
	record["mode"] = "sheet" if use_sheet_boundaries else "intrinsic"
	record["event"] = event
	record["time_sec"] = float(frame_count) / float(CurlingConstants.PHYSICS_HZ)
	record["path_m"] = path_length_px / CurlingConstants.PIXELS_PER_METER
	record["forward_m"] = displacement.dot(direction) / CurlingConstants.PIXELS_PER_METER
	record["lateral_m"] = displacement.dot(direction.rotated(PI * 0.5)) / CurlingConstants.PIXELS_PER_METER
	record["end_x_m"] = stone.global_position.x / CurlingConstants.PIXELS_PER_METER
	record["end_y_m"] = stone.global_position.y / CurlingConstants.PIXELS_PER_METER
	record["rotation_turns"] = rotation_rad / TAU
	return record


func _out_event(position: Vector2) -> String:
	if absf(position.y) + CurlingConstants.STONE_RADIUS_PX >= CurlingConstants.HALF_SHEET_WIDTH_PX:
		return "side_out"
	return "back_out"


func _analyze_power_sweep(records: Array[Dictionary]) -> void:
	for power_step in range(21):
		var power := float(power_step) * 0.05
		var group := _matching(records, power, 0.0, 0.0)
		print(
			"CURLING_POWER_SWEEP power=%03d speed=%.5fm/s time=%.3fs path=%.3fm time_range=%.4fs"
			% [
				roundi(power * 100.0),
				CurlingConstants.throw_speed_for_power(power),
				_mean(group, "time_sec"),
				_mean(group, "path_m"),
				_range(group, "time_sec"),
			]
		)


func _analyze_intrinsic_factorial(records: Array[Dictionary]) -> void:
	for power in FACTOR_POWERS:
		var power_group := _matching_power(records, float(power))
		var time_spread := _range(power_group, "time_sec")
		var path_spread := _range(power_group, "path_m")
		_max_intrinsic_time_spread_sec = maxf(_max_intrinsic_time_spread_sec, time_spread)
		_max_intrinsic_path_spread_m = maxf(_max_intrinsic_path_spread_m, path_spread)
		print(
			"CURLING_INTRINSIC_FACTOR power=%03d samples=%d time=%.3fs time_spread=%.4fs path=%.3fm path_spread=%.4fm"
			% [
				roundi(float(power) * 100.0),
				power_group.size(),
				_mean(power_group, "time_sec"),
				time_spread,
				_mean(power_group, "path_m"),
				path_spread,
			]
		)
	if _max_intrinsic_time_spread_sec > 0.035:
		_failures.append("aim/spin changes intrinsic stop time by %.4fs" % _max_intrinsic_time_spread_sec)
	if _max_intrinsic_path_spread_m > 0.03:
		_failures.append("aim/spin changes intrinsic path by %.4fm" % _max_intrinsic_path_spread_m)

	for aim_deg in AIM_ANGLES_DEG:
		var group := _matching(records, 0.77, float(aim_deg), 0.0)
		print(
			"CURLING_AIM_ISOLATION power=077 aim=%+05.1fdeg time=%.3fs path=%.3fm"
			% [float(aim_deg), _mean(group, "time_sec"), _mean(group, "path_m")]
		)
	for spin_radps in SPINS_RADPS:
		var group := _matching(records, 0.77, 0.0, float(spin_radps))
		print(
			"CURLING_SPIN_ISOLATION power=077 spin=%+04.1frad/s time=%.3fs path=%.3fm lateral=%+.3fm turns=%+.3f"
			% [
				float(spin_radps),
				_mean(group, "time_sec"),
				_mean(group, "path_m"),
				_mean(group, "lateral_m"),
				_mean(group, "rotation_turns"),
			]
		)


func _analyze_sheet_factorial(records: Array[Dictionary]) -> void:
	for power in FACTOR_POWERS:
		var group := _matching_power(records, float(power))
		print(
			"CURLING_SHEET_FACTOR power=%03d samples=%d stopped=%d side_out=%d back_out=%d effective_time_mean=%.3fs effective_time_range=%.3fs"
			% [
				roundi(float(power) * 100.0),
				group.size(),
				_count_event(group, "stopped"),
				_count_event(group, "side_out"),
				_count_event(group, "back_out"),
				_mean(group, "time_sec"),
				_range(group, "time_sec"),
			]
		)

	for aim_deg in AIM_ANGLES_DEG:
		for spin_radps in SPINS_RADPS:
			var group := _matching(records, 0.77, float(aim_deg), float(spin_radps))
			print(
				"CURLING_SHEET_GRID power=077 aim=%+05.1fdeg spin=%+04.1frad/s event=%s time=%.3fs end=(%+.3f,%+.3f)m"
				% [
					float(aim_deg),
					float(spin_radps),
					_consistent_event(group),
					_mean(group, "time_sec"),
					_mean(group, "end_x_m"),
					_mean(group, "end_y_m"),
				]
			)


func _matching(
	records: Array[Dictionary], power: float, aim_deg: float, spin_radps: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in records:
		if (
			is_equal_approx(float(record["power"]), power)
			and is_equal_approx(float(record["aim_deg"]), aim_deg)
			and is_equal_approx(float(record["spin_radps"]), spin_radps)
		):
			result.append(record)
	return result


func _matching_power(records: Array[Dictionary], power: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in records:
		if is_equal_approx(float(record["power"]), power):
			result.append(record)
	return result


func _mean(records: Array[Dictionary], field: String) -> float:
	if records.is_empty():
		return 0.0
	var total := 0.0
	for record in records:
		total += float(record[field])
	return total / float(records.size())


func _range(records: Array[Dictionary], field: String) -> float:
	if records.is_empty():
		return 0.0
	var minimum := INF
	var maximum := -INF
	for record in records:
		var value := float(record[field])
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	return maximum - minimum


func _count_event(records: Array[Dictionary], event: String) -> int:
	var count := 0
	for record in records:
		if String(record["event"]) == event:
			count += 1
	return count


func _consistent_event(records: Array[Dictionary]) -> String:
	if records.is_empty():
		return "missing"
	var event := String(records[0]["event"])
	for record in records:
		if String(record["event"]) != event:
			return "mixed"
	return event


func _finish(
	power_records: Array[Dictionary],
	intrinsic_records: Array[Dictionary],
	sheet_records: Array[Dictionary]
) -> void:
	if power_records.size() != 21 * REPEAT_COUNT:
		_failures.append("power sweep produced %d records" % power_records.size())
	if intrinsic_records.size() != FACTOR_POWERS.size() * AIM_ANGLES_DEG.size() * SPINS_RADPS.size() * REPEAT_COUNT:
		_failures.append("intrinsic factorial produced %d records" % intrinsic_records.size())
	if sheet_records.size() != FACTOR_POWERS.size() * AIM_ANGLES_DEG.size() * SPINS_RADPS.size() * REPEAT_COUNT:
		_failures.append("sheet factorial produced %d records" % sheet_records.size())
	if _failures.is_empty():
		print(
			"CURLING_THROW_PARAMETER_EXPERIMENT_OK power_samples=%d intrinsic_samples=%d sheet_samples=%d max_intrinsic_time_spread=%.4fs max_intrinsic_path_spread=%.4fm"
			% [
				power_records.size(),
				intrinsic_records.size(),
				sheet_records.size(),
				_max_intrinsic_time_spread_sec,
				_max_intrinsic_path_spread_m,
			]
		)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("CURLING_THROW_PARAMETER_EXPERIMENT_FAIL %s" % failure)
		get_tree().quit(1)
