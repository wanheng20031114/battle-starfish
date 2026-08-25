extends Node2D
class_name CurlingHeatGrid

signal authoritative_segment(from_world: Vector2, to_world: Vector2, speed_mps: float, sample_ms: int)

var authoritative := true
var _cells: Dictionary = {}
var _last_draw_ms := 0


func _ready() -> void:
	z_index = 3
	set_process(true)


func _process(_delta: float) -> void:
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_draw_ms >= 50:
		_prune(now_ms)
		queue_redraw()
		_last_draw_ms = now_ms


## Host唯一写入入口。输入路径已经过时间、阶段、队伍与速度校验。
func deposit_segment(
	from_world: Vector2,
	to_world: Vector2,
	delta_sec: float,
	sample_ms: int = -1,
	broadcast_segment: bool = true
) -> float:
	if delta_sec <= 0.0 or delta_sec > 0.25:
		return 0.0
	var distance_px := from_world.distance_to(to_world)
	var speed_mps := distance_px / CurlingConstants.PIXELS_PER_METER / delta_sec
	if speed_mps < CurlingConstants.SWEEP_MIN_SPEED_MPS:
		return 0.0
	var accepted_distance_px := minf(
		distance_px,
		CurlingConstants.SWEEP_MAX_SPEED_MPS * CurlingConstants.PIXELS_PER_METER * delta_sec
	)
	if distance_px <= 0.001:
		return 0.0
	var accepted_to := from_world + from_world.direction_to(to_world) * accepted_distance_px
	var speed_factor := clampf(
		(speed_mps - CurlingConstants.SWEEP_MIN_SPEED_MPS)
		/ (CurlingConstants.SWEEP_FULL_SPEED_MPS - CurlingConstants.SWEEP_MIN_SPEED_MPS),
		0.0,
		1.0
	)
	var now_ms := sample_ms if sample_ms >= 0 else Time.get_ticks_msec()
	var sample_step := CurlingConstants.HEAT_CELL_PX * 0.5
	var sample_count := maxi(1, ceili(accepted_distance_px / sample_step))
	var brush_cell_radius := ceili(CurlingConstants.BRUSH_RADIUS_PX / CurlingConstants.HEAT_CELL_PX)
	var touched_cells: Dictionary = {}
	for sample_index in range(sample_count + 1):
		var ratio := float(sample_index) / float(sample_count)
		var sample_position := from_world.lerp(accepted_to, ratio)
		var center_cell := _world_to_cell(sample_position)
		for cell_y in range(center_cell.y - brush_cell_radius, center_cell.y + brush_cell_radius + 1):
			for cell_x in range(center_cell.x - brush_cell_radius, center_cell.x + brush_cell_radius + 1):
				var cell := Vector2i(cell_x, cell_y)
				if _cell_center(cell).distance_to(sample_position) > CurlingConstants.BRUSH_RADIUS_PX:
					continue
				touched_cells[cell] = true
	# 同一输入段内每个网格只累计一次，避免路径采样密度放大热量。
	for cell_variant in touched_cells:
		var cell := cell_variant as Vector2i
		var current_heat := _decayed_heat(cell, now_ms)
		_cells[cell] = {
			"heat": clampf(
				current_heat + CurlingConstants.HEAT_DEPOSIT_PER_SEC * speed_factor * delta_sec,
				0.0,
				1.0
			),
			"time_ms": now_ms,
		}
	if authoritative and broadcast_segment:
		authoritative_segment.emit(from_world, accepted_to, minf(speed_mps, CurlingConstants.SWEEP_MAX_SPEED_MPS), now_ms)
	queue_redraw()
	return speed_factor


func apply_authoritative_segment(
	from_world: Vector2,
	to_world: Vector2,
	speed_mps: float,
	host_sample_ms: int
) -> void:
	var distance_m := from_world.distance_to(to_world) / CurlingConstants.PIXELS_PER_METER
	var delta_sec := distance_m / maxf(speed_mps, CurlingConstants.SWEEP_MIN_SPEED_MPS)
	deposit_segment(from_world, to_world, clampf(delta_sec, 0.001, 0.25), host_sample_ms, false)


func sample_heat(world_position: Vector2, now_ms: int = -1) -> float:
	var sample_time := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var grid_position := world_position / CurlingConstants.HEAT_CELL_PX
	var base := Vector2i(floori(grid_position.x), floori(grid_position.y))
	var fraction := Vector2(grid_position.x - float(base.x), grid_position.y - float(base.y))
	var h00 := _decayed_heat(base, sample_time)
	var h10 := _decayed_heat(base + Vector2i.RIGHT, sample_time)
	var h01 := _decayed_heat(base + Vector2i.DOWN, sample_time)
	var h11 := _decayed_heat(base + Vector2i(1, 1), sample_time)
	return lerpf(lerpf(h00, h10, fraction.x), lerpf(h01, h11, fraction.x), fraction.y)


func export_sparse(now_ms: int = -1, max_cells: int = 2500) -> PackedByteArray:
	var sample_time := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var active_cells: Array[Vector2i] = []
	for cell_variant in _cells.keys():
		var cell := cell_variant as Vector2i
		if _decayed_heat(cell, sample_time) >= 0.02:
			active_cells.append(cell)
	active_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	if active_cells.size() > max_cells:
		active_cells.resize(max_cells)
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.put_u16(active_cells.size())
	for cell in active_cells:
		stream.put_16(cell.x)
		stream.put_16(cell.y)
		stream.put_u8(clampi(roundi(_decayed_heat(cell, sample_time) * 255.0), 0, 255))
	return stream.data_array


func import_sparse(payload: PackedByteArray, host_time_ms: int) -> bool:
	if payload.size() < 2 or (payload.size() - 2) % 5 != 0:
		return false
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.data_array = payload
	var count := stream.get_u16()
	if count > 4096 or payload.size() != 2 + count * 5:
		return false
	_cells.clear()
	for _index in range(count):
		var cell := Vector2i(stream.get_16(), stream.get_16())
		var heat := float(stream.get_u8()) / 255.0
		_cells[cell] = {"heat": heat, "time_ms": host_time_ms}
	queue_redraw()
	return true


func clear() -> void:
	_cells.clear()
	queue_redraw()


func active_cell_count() -> int:
	return _cells.size()


func _decayed_heat(cell: Vector2i, now_ms: int) -> float:
	var entry_variant: Variant = _cells.get(cell)
	if typeof(entry_variant) != TYPE_DICTIONARY:
		return 0.0
	var entry: Dictionary = entry_variant
	var elapsed_sec := maxf(0.0, float(now_ms - int(entry.get("time_ms", now_ms))) / 1000.0)
	if elapsed_sec >= CurlingConstants.HEAT_CUTOFF_SEC:
		return 0.0
	return float(entry.get("heat", 0.0)) * pow(0.5, elapsed_sec / CurlingConstants.HEAT_HALF_LIFE_SEC)


func _prune(now_ms: int) -> void:
	for cell_variant in _cells.keys():
		var cell := cell_variant as Vector2i
		if _decayed_heat(cell, now_ms) < 0.01:
			_cells.erase(cell)


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / CurlingConstants.HEAT_CELL_PX),
		floori(world_position.y / CurlingConstants.HEAT_CELL_PX)
	)


func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CurlingConstants.HEAT_CELL_PX


func _draw() -> void:
	var now_ms := Time.get_ticks_msec()
	for cell_variant in _cells.keys():
		var cell := cell_variant as Vector2i
		var heat := _decayed_heat(cell, now_ms)
		if heat < 0.01:
			continue
		var top_left := Vector2(cell) * CurlingConstants.HEAT_CELL_PX
		var color := Color(0.18, 0.83, 0.82, 0.05 + heat * 0.38)
		draw_rect(Rect2(top_left, Vector2.ONE * CurlingConstants.HEAT_CELL_PX), color, true)
