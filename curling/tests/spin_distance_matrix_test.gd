extends Node

const TEST_POWERS := [0.65, 0.75, 0.85]
const TEST_SPINS := [0.0, -0.6, 0.6, -1.2, 1.2]
const TEST_DIRECTIONS := [-1, 1]
const REFERENCE_POWERS := [0.74, 0.76, 0.77, 0.78, 0.79]
const MAX_SIMULATION_FRAMES := 2100
const TIME_TOLERANCE_SEC := 0.035
const PATH_TOLERANCE_M := 0.025
const SPEED_PROFILE_TOLERANCE_MPS := 0.002

@onready var controller: CurlingMatchController = $MatchController

var _stones: Array[CurlingStone] = []
var _failures: Array[String] = []
var _cases: Dictionary = {}
var _launch_counts := PackedInt32Array()
var _total_launches := 0
var _max_time_delta_sec := 0.0
var _max_path_delta_m := 0.0
var _max_speed_profile_delta_mps := 0.0
var _max_forward_loss_m := 0.0


func _ready() -> void:
	await get_tree().physics_frame
	_collect_stones()
	if _stones.size() != CurlingConstants.STONE_COUNT:
		_failures.append("match scene exposes %d stones, expected %d" % [_stones.size(), CurlingConstants.STONE_COUNT])
		_finish()
		return

	_launch_counts.resize(_stones.size())
	for power in TEST_POWERS:
		for direction in TEST_DIRECTIONS:
			for spin in TEST_SPINS:
				var result := await _run_case(float(power), int(direction), float(spin))
				_cases[_case_key(float(power), int(direction), float(spin))] = result
				if not is_zero_approx(float(spin)):
					_compare_with_no_spin(float(power), int(direction), float(spin), result)
				if is_equal_approx(float(power), CurlingConstants.THROW_TEE_POWER):
					print(_case_summary(float(power), int(direction), float(spin), result))

	print(_draw_reference_summary(0.75, _cases[_case_key(0.75, 1, 0.0)]))
	for power in REFERENCE_POWERS:
		for direction in TEST_DIRECTIONS:
			var result := await _run_case(float(power), int(direction), 0.0)
			_cases[_case_key(float(power), int(direction), 0.0)] = result
			if int(direction) == 1:
				print(_draw_reference_summary(float(power), result))

	_check_direction_symmetry()
	_check_spin_symmetry()
	_check_straight_draw_reference()
	_check_launch_coverage()
	_finish()


func _collect_stones() -> void:
	for child in controller.stones_root.get_children():
		if child is CurlingStone:
			_stones.append(child as CurlingStone)
	_stones.sort_custom(func(a: CurlingStone, b: CurlingStone) -> bool: return a.stone_id < b.stone_id)


func _run_case(power: float, direction: int, spin: float) -> Dictionary:
	controller.phase = CurlingMatchController.Phase.IDLE
	controller.heat_grid.clear()
	for stone in _stones:
		stone.remove_from_play()
	await get_tree().physics_frame

	var starts: Array[Vector2] = []
	var previous_positions: Array[Vector2] = []
	var path_lengths_px := PackedFloat32Array()
	var finished := PackedByteArray()
	var records: Array[Dictionary] = []
	var speed_traces: Array[Array] = []
	path_lengths_px.resize(_stones.size())
	finished.resize(_stones.size())
	records.resize(_stones.size())
	var throw_direction := Vector2(float(direction), 0.0)
	for index in range(_stones.size()):
		var start := Vector2(0.0, (float(index) - 7.5) * 80.0)
		starts.append(start)
		previous_positions.append(start)
		speed_traces.append([])
		_stones[index].prepare_for_delivery(start, index + 1, Color.WHITE)
	await get_tree().physics_frame

	var speed_mps := CurlingConstants.throw_speed_for_power(power)
	for index in range(_stones.size()):
		_stones[index].launch(throw_direction, speed_mps, spin)
		_launch_counts[index] += 1
		_total_launches += 1

	var completed := 0
	var frame_count := 0
	while completed < _stones.size() and frame_count < MAX_SIMULATION_FRAMES:
		await get_tree().physics_frame
		frame_count += 1
		for index in range(_stones.size()):
			if finished[index] != 0:
				continue
			var stone := _stones[index]
			var position := stone.global_position
			path_lengths_px[index] += position.distance_to(previous_positions[index])
			previous_positions[index] = position
			var current_speed_mps := stone.linear_velocity.length() / CurlingConstants.PIXELS_PER_METER
			speed_traces[index].append(current_speed_mps)
			if stone.linear_velocity.length() > CurlingConstants.STOP_SPEED_PXPS:
				continue
			var displacement := position - starts[index]
			records[index] = {
				"stone_id": stone.stone_id,
				"time_sec": float(frame_count) / float(CurlingConstants.PHYSICS_HZ),
				"path_m": path_lengths_px[index] / CurlingConstants.PIXELS_PER_METER,
				"forward_m": displacement.dot(throw_direction) / CurlingConstants.PIXELS_PER_METER,
				"lateral_m": displacement.dot(throw_direction.rotated(PI * 0.5)) / CurlingConstants.PIXELS_PER_METER,
			}
			finished[index] = 1
			completed += 1
			stone.freeze_at_rest()

	if completed != _stones.size():
		_failures.append(
			"power %.2f direction %d spin %.2f stopped only %d/%d stones"
			% [power, direction, spin, completed, _stones.size()]
		)
		for index in range(_stones.size()):
			if finished[index] == 0:
				_stones[index].freeze_at_rest()
	return {"records": records, "speed_traces": speed_traces}


func _compare_with_no_spin(power: float, direction: int, spin: float, result: Dictionary) -> void:
	var baseline: Dictionary = _cases.get(_case_key(power, direction, 0.0), {})
	if baseline.is_empty():
		_failures.append("missing no-spin baseline for power %.2f direction %d" % [power, direction])
		return
	var records: Array = result["records"]
	var baseline_records: Array = baseline["records"]
	var traces: Array = result["speed_traces"]
	var baseline_traces: Array = baseline["speed_traces"]
	for index in range(_stones.size()):
		if records[index].is_empty() or baseline_records[index].is_empty():
			continue
		var record: Dictionary = records[index]
		var baseline_record: Dictionary = baseline_records[index]
		var time_delta := absf(float(record["time_sec"]) - float(baseline_record["time_sec"]))
		var path_delta := absf(float(record["path_m"]) - float(baseline_record["path_m"]))
		var forward_loss := float(baseline_record["forward_m"]) - float(record["forward_m"])
		_max_time_delta_sec = maxf(_max_time_delta_sec, time_delta)
		_max_path_delta_m = maxf(_max_path_delta_m, path_delta)
		_max_forward_loss_m = maxf(_max_forward_loss_m, forward_loss)
		if time_delta > TIME_TOLERANCE_SEC:
			_failures.append("stone %d spin changes stop time by %.4fs" % [index, time_delta])
		if path_delta > PATH_TOLERANCE_M:
			_failures.append("stone %d spin changes total path by %.4fm" % [index, path_delta])
		var trace: Array = traces[index]
		var baseline_trace: Array = baseline_traces[index]
		var shared_frames := mini(trace.size(), baseline_trace.size())
		for frame in range(shared_frames):
			var speed_delta := absf(float(trace[frame]) - float(baseline_trace[frame]))
			_max_speed_profile_delta_mps = maxf(_max_speed_profile_delta_mps, speed_delta)
			if speed_delta > SPEED_PROFILE_TOLERANCE_MPS:
				_failures.append(
					"stone %d power %.2f spin %.2f speed differs by %.4fm/s at frame %d"
					% [index, power, spin, speed_delta, frame]
				)
				break


func _check_direction_symmetry() -> void:
	for power in TEST_POWERS:
		for spin in TEST_SPINS:
			var left: Dictionary = _cases[_case_key(float(power), -1, float(spin))]
			var right: Dictionary = _cases[_case_key(float(power), 1, float(spin))]
			var left_records: Array = left["records"]
			var right_records: Array = right["records"]
			for index in range(_stones.size()):
				var left_record: Dictionary = left_records[index]
				var right_record: Dictionary = right_records[index]
				if left_record.is_empty() or right_record.is_empty():
					continue
				if absf(float(left_record["time_sec"]) - float(right_record["time_sec"])) > TIME_TOLERANCE_SEC:
					_failures.append("stone %d left/right stop time is asymmetric" % index)
				if absf(float(left_record["path_m"]) - float(right_record["path_m"])) > PATH_TOLERANCE_M:
					_failures.append("stone %d left/right path is asymmetric" % index)


func _check_spin_symmetry() -> void:
	for power in TEST_POWERS:
		for direction in TEST_DIRECTIONS:
			for spin_magnitude in [0.6, 1.2]:
				var negative: Dictionary = _cases[_case_key(float(power), int(direction), -float(spin_magnitude))]
				var positive: Dictionary = _cases[_case_key(float(power), int(direction), float(spin_magnitude))]
				var negative_records: Array = negative["records"]
				var positive_records: Array = positive["records"]
				for index in range(_stones.size()):
					var negative_record: Dictionary = negative_records[index]
					var positive_record: Dictionary = positive_records[index]
					if negative_record.is_empty() or positive_record.is_empty():
						continue
					var forward_delta := absf(float(negative_record["forward_m"]) - float(positive_record["forward_m"]))
					var lateral_sum := absf(float(negative_record["lateral_m"]) + float(positive_record["lateral_m"]))
					if forward_delta > PATH_TOLERANCE_M or lateral_sum > PATH_TOLERANCE_M:
						_failures.append("stone %d positive/negative spin is asymmetric" % index)


func _check_launch_coverage() -> void:
	var expected_per_stone := TEST_POWERS.size() * TEST_DIRECTIONS.size() * TEST_SPINS.size()
	expected_per_stone += REFERENCE_POWERS.size() * TEST_DIRECTIONS.size()
	for index in range(_launch_counts.size()):
		if _launch_counts[index] != expected_per_stone:
			_failures.append("stone %d launched %d times, expected %d" % [index, _launch_counts[index], expected_per_stone])


func _check_straight_draw_reference() -> void:
	var tee_distance := (
		2.0 * CurlingConstants.TEE_FROM_CENTER_M
		+ CurlingConstants.HACK_FROM_TEE_PX / CurlingConstants.PIXELS_PER_METER
	)
	var house_reach := (
		CurlingConstants.HOUSE_RADII_PX[0] + CurlingConstants.STONE_RADIUS_PX
	) / CurlingConstants.PIXELS_PER_METER
	for direction in TEST_DIRECTIONS:
		for power in [0.77, 0.78, 0.79]:
			var result: Dictionary = _cases[_case_key(float(power), int(direction), 0.0)]
			var records: Array = result["records"]
			for record_variant in records:
				var record: Dictionary = record_variant
				var tee_offset := float(record["forward_m"]) - tee_distance
				var in_house := absf(tee_offset) <= house_reach
				if is_equal_approx(float(power), CurlingConstants.THROW_RECOMMENDED_POWER):
					if not in_house or tee_offset < 1.0 or tee_offset > 1.3:
						_failures.append("stone %d recommended draw is not safely behind tee" % int(record["stone_id"]))
					var turn_time := float(record["time_sec"]) + CurlingConstants.SETTLE_TIME_SEC
					if absf(turn_time - 22.67) > 0.08:
						_failures.append("stone %d recommended draw turn time is %.3fs" % [int(record["stone_id"]), turn_time])
				elif is_equal_approx(float(power), 0.78) and not in_house:
					_failures.append("stone %d 78 percent draw should remain barely in house" % int(record["stone_id"]))
				elif is_equal_approx(float(power), 0.79) and in_house:
					_failures.append("stone %d 79 percent draw should pass the scoring edge" % int(record["stone_id"]))


func _equivalent_power_points() -> float:
	var max_power_points := 0.0
	for direction in TEST_DIRECTIONS:
		var lower: Dictionary = _cases[_case_key(0.74, int(direction), 0.0)]
		var upper: Dictionary = _cases[_case_key(0.76, int(direction), 0.0)]
		var baseline: Dictionary = _cases[_case_key(0.75, int(direction), 0.0)]
		for spin in [-1.2, 1.2]:
			var spun: Dictionary = _cases[_case_key(0.75, int(direction), float(spin))]
			for index in range(_stones.size()):
				var lower_record: Dictionary = (lower["records"] as Array)[index]
				var upper_record: Dictionary = (upper["records"] as Array)[index]
				var baseline_record: Dictionary = (baseline["records"] as Array)[index]
				var spun_record: Dictionary = (spun["records"] as Array)[index]
				if lower_record.is_empty() or upper_record.is_empty() or baseline_record.is_empty() or spun_record.is_empty():
					continue
				var meters_per_power := (
					float(upper_record["forward_m"]) - float(lower_record["forward_m"])
				) / 0.02
				if meters_per_power <= 0.0:
					continue
				var forward_loss := float(baseline_record["forward_m"]) - float(spun_record["forward_m"])
				max_power_points = maxf(max_power_points, forward_loss / meters_per_power * 100.0)
	return max_power_points


func _case_summary(power: float, direction: int, spin: float, result: Dictionary) -> String:
	var records: Array = result["records"]
	var time_total := 0.0
	var path_total := 0.0
	var forward_total := 0.0
	var lateral_total := 0.0
	for record_variant in records:
		var record: Dictionary = record_variant
		if record.is_empty():
			continue
		time_total += float(record["time_sec"])
		path_total += float(record["path_m"])
		forward_total += float(record["forward_m"])
		lateral_total += float(record["lateral_m"])
	var divisor := maxf(1.0, float(records.size()))
	return (
		"CURLING_SPIN_MATRIX_CASE power=%.2f direction=%d spin=%+.2f time=%.3fs path=%.3fm forward=%.3fm lateral=%+.3fm"
		% [power, direction, spin, time_total / divisor, path_total / divisor, forward_total / divisor, lateral_total / divisor]
	)


func _draw_reference_summary(power: float, result: Dictionary) -> String:
	var records: Array = result["records"]
	var time_total := 0.0
	var forward_total := 0.0
	for record_variant in records:
		var record: Dictionary = record_variant
		time_total += float(record["time_sec"])
		forward_total += float(record["forward_m"])
	var divisor := maxf(1.0, float(records.size()))
	var stop_time := time_total / divisor
	var forward := forward_total / divisor
	var tee_distance := (
		2.0 * CurlingConstants.TEE_FROM_CENTER_M
		+ CurlingConstants.HACK_FROM_TEE_PX / CurlingConstants.PIXELS_PER_METER
	)
	var tee_offset := forward - tee_distance
	var house_reach := (
		CurlingConstants.HOUSE_RADII_PX[0] + CurlingConstants.STONE_RADIUS_PX
	) / CurlingConstants.PIXELS_PER_METER
	return (
		"CURLING_STRAIGHT_DRAW_PROBE power=%d stop=%.3fs turn=%.3fs tee_offset=%+.3fm in_house=%s"
		% [
			roundi(power * 100.0),
			stop_time,
			stop_time + CurlingConstants.SETTLE_TIME_SEC,
			tee_offset,
			str(absf(tee_offset) <= house_reach),
		]
	)


func _case_key(power: float, direction: int, spin: float) -> String:
	return "%d:%d:%d" % [roundi(power * 1000.0), direction, roundi(spin * 1000.0)]


func _finish() -> void:
	var equivalent_power_points := _equivalent_power_points() if not _cases.is_empty() else 0.0
	if _failures.is_empty():
		print(
			"CURLING_SPIN_DISTANCE_MATRIX_OK launches=%d stones=%d max_time_delta=%.4fs max_path_delta=%.4fm max_speed_delta=%.5fm/s max_forward_loss=%.4fm equivalent_power=%.3fpp"
			% [
				_total_launches,
				_stones.size(),
				_max_time_delta_sec,
				_max_path_delta_m,
				_max_speed_profile_delta_mps,
				_max_forward_loss_m,
				equivalent_power_points,
			]
		)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("CURLING_SPIN_DISTANCE_MATRIX_FAIL %s" % failure)
		get_tree().quit(1)
