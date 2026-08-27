extends Node2D

@onready var cold_stone: CurlingStone = $ColdStone
@onready var swept_stone: CurlingStone = $SweptStone
@onready var no_spin_stone: CurlingStone = $NoSpinStone
@onready var cold_heat: CurlingHeatGrid = $ColdHeatGrid
@onready var full_heat: CurlingHeatGrid = $FullHeatGrid

var _elapsed := 0.0
var _running := false
var _cold_stop_time := -1.0
var _swept_stop_time := -1.0
var _no_spin_stop_time := -1.0
var _cold_spin_at_twenty := 0.0
var _failures: Array[String] = []
var _cold_start := Vector2(0, -500)
var _swept_start := Vector2(0, 500)
var _no_spin_start := Vector2.ZERO
var _cold_path_px := 0.0
var _no_spin_path_px := 0.0
var _last_cold_position := Vector2.ZERO
var _last_no_spin_position := Vector2.ZERO


func _ready() -> void:
	cold_stone.heat_grid = cold_heat
	swept_stone.heat_grid = full_heat
	cold_stone.prepare_for_delivery(_cold_start, 1, Color.WHITE)
	swept_stone.prepare_for_delivery(_swept_start, 2, Color.WHITE)
	no_spin_stone.prepare_for_delivery(_no_spin_start, 3, Color.WHITE)
	_last_cold_position = _cold_start
	_last_no_spin_position = _no_spin_start
	await get_tree().physics_frame
	var draw_speed := CurlingConstants.throw_speed_for_power(CurlingConstants.THROW_DRAW_POWER)
	cold_stone.launch(Vector2.RIGHT, draw_speed, CurlingConstants.MAX_SPIN_RADPS)
	swept_stone.launch(Vector2.RIGHT, draw_speed, CurlingConstants.MAX_SPIN_RADPS)
	no_spin_stone.launch(Vector2.RIGHT, draw_speed, 0.0)
	_running = true


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	if _cold_stop_time < 0.0:
		_cold_path_px += cold_stone.global_position.distance_to(_last_cold_position)
		_last_cold_position = cold_stone.global_position
	if _no_spin_stop_time < 0.0:
		_no_spin_path_px += no_spin_stone.global_position.distance_to(_last_no_spin_position)
		_last_no_spin_position = no_spin_stone.global_position
	if _elapsed >= 20.0 and _cold_spin_at_twenty == 0.0:
		_cold_spin_at_twenty = cold_stone.angular_velocity
	if _cold_stop_time < 0.0 and cold_stone.linear_velocity.length() <= CurlingConstants.STOP_SPEED_PXPS:
		_cold_stop_time = _elapsed
	if _swept_stop_time < 0.0 and swept_stone.linear_velocity.length() <= CurlingConstants.STOP_SPEED_PXPS:
		_swept_stop_time = _elapsed
	if _no_spin_stop_time < 0.0 and no_spin_stone.linear_velocity.length() <= CurlingConstants.STOP_SPEED_PXPS:
		_no_spin_stop_time = _elapsed
	if (_cold_stop_time >= 0.0 and _swept_stop_time >= 0.0 and _no_spin_stop_time >= 0.0) or _elapsed > 30.0:
		_finish()


func _finish() -> void:
	_running = false
	var cold_delta := cold_stone.global_position - _cold_start
	var swept_delta := swept_stone.global_position - _swept_start
	var no_spin_delta := no_spin_stone.global_position - _no_spin_start
	_check(absf(_cold_stop_time - 22.0) <= 0.8, "native draw stop time %.3fs" % _cold_stop_time)
	_check(absf(no_spin_delta.x / CurlingConstants.PIXELS_PER_METER - 36.58) <= 0.25, "native 75 percent no-sweep draw distance %.3fm" % (no_spin_delta.x / CurlingConstants.PIXELS_PER_METER))
	_check(absf(_cold_stop_time - _no_spin_stop_time) <= 0.05, "native spin preserves stop time %.3fs vs %.3fs" % [_cold_stop_time, _no_spin_stop_time])
	_check(absf((_cold_path_px - _no_spin_path_px) / CurlingConstants.PIXELS_PER_METER) <= 0.05, "native spin preserves slide distance %.3fm vs %.3fm" % [_cold_path_px / CurlingConstants.PIXELS_PER_METER, _no_spin_path_px / CurlingConstants.PIXELS_PER_METER])
	_check(absf(absf(cold_delta.y / CurlingConstants.PIXELS_PER_METER) - 1.5) <= 0.20, "native curl %.3fm" % (cold_delta.y / CurlingConstants.PIXELS_PER_METER))
	_check(absf(_cold_spin_at_twenty - 0.6) <= 0.08, "native angular half-life %.3frad/s" % _cold_spin_at_twenty)
	_check(absf((swept_delta.x - cold_delta.x) / CurlingConstants.PIXELS_PER_METER - 3.0) <= 0.55, "native swept extension %.3fm" % ((swept_delta.x - cold_delta.x) / CurlingConstants.PIXELS_PER_METER))
	var curl_reduction := 1.0 - absf((swept_delta.y) / (cold_delta.y))
	_check(absf(curl_reduction - 0.35) <= 0.06, "native swept curl reduction %.1f%%" % (curl_reduction * 100.0))
	if _failures.is_empty():
		print("CURLING_NATIVE_CALIBRATION_OK no_sweep_75=%.2fm draw=%.2fs curl=%.2fm full_sweep_75_extra=%.2fm" % [no_spin_delta.x / 100.0, _cold_stop_time, cold_delta.y / 100.0, (swept_delta.x - cold_delta.x) / 100.0])
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("CURLING_NATIVE_CALIBRATION_FAIL %s" % failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
