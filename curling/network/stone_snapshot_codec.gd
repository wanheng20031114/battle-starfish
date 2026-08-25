extends RefCounted
class_name CurlingStoneSnapshotCodec

## 12字节头 + 16颗壶 × 12字节 = 固定204字节。
const HEADER_BYTES := 12
const RECORD_BYTES := 12
const SNAPSHOT_BYTES := HEADER_BYTES + CurlingConstants.STONE_COUNT * RECORD_BYTES


static func encode_snapshot(
	host_tick: int,
	state_sequence: int,
	shot_id: int,
	stones: Array[Dictionary]
) -> PackedByteArray:
	if stones.size() != CurlingConstants.STONE_COUNT:
		return PackedByteArray()
	var in_play_mask := 0
	var moving_mask := 0
	for stone_index in range(stones.size()):
		var stone := stones[stone_index]
		if bool(stone.get("in_play", false)):
			in_play_mask |= 1 << stone_index
		if bool(stone.get("moving", false)):
			moving_mask |= 1 << stone_index
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.put_u32(host_tick & 0xFFFFFFFF)
	stream.put_u16(state_sequence & 0xFFFF)
	stream.put_u16(shot_id & 0xFFFF)
	stream.put_u16(in_play_mask)
	stream.put_u16(moving_mask)
	for stone in stones:
		var position: Vector2 = stone.get("position", Vector2.ZERO)
		var velocity: Vector2 = stone.get("velocity", Vector2.ZERO)
		stream.put_16(_meters_to_i16(position.x))
		stream.put_16(_meters_to_i16(position.y))
		stream.put_16(_meters_to_i16(velocity.x))
		stream.put_16(_meters_to_i16(velocity.y))
		stream.put_16(clampi(roundi(wrapf(float(stone.get("angle", 0.0)), -PI, PI) * 1000.0), -32767, 32767))
		stream.put_16(clampi(roundi(float(stone.get("angular_velocity", 0.0)) * 1000.0), -32767, 32767))
	var payload := stream.data_array
	return payload if payload.size() == SNAPSHOT_BYTES else PackedByteArray()


static func decode_snapshot(payload: PackedByteArray) -> Dictionary:
	if payload.size() != SNAPSHOT_BYTES:
		return {"valid": false}
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.data_array = payload
	var host_tick := stream.get_u32()
	var state_sequence := stream.get_u16()
	var shot_id := stream.get_u16()
	var in_play_mask := stream.get_u16()
	var moving_mask := stream.get_u16()
	if moving_mask & ~in_play_mask:
		return {"valid": false}
	var stones: Array[Dictionary] = []
	for stone_index in range(CurlingConstants.STONE_COUNT):
		var position := Vector2(_i16_to_pixels(stream.get_16()), _i16_to_pixels(stream.get_16()))
		var velocity := Vector2(_i16_to_pixels(stream.get_16()), _i16_to_pixels(stream.get_16()))
		var angle := float(stream.get_16()) / 1000.0
		var angular_velocity := float(stream.get_16()) / 1000.0
		if (
			not position.is_finite()
			or not velocity.is_finite()
			or absf(position.x) > CurlingConstants.SHEET_LENGTH_PX
			or absf(position.y) > CurlingConstants.SHEET_WIDTH_PX * 2.0
			or velocity.length() > CurlingConstants.MAX_THROW_SPEED_MPS * CurlingConstants.PIXELS_PER_METER * 4.0
			or absf(angle) > PI + 0.01
			or absf(angular_velocity) > CurlingConstants.MAX_SPIN_RADPS * 4.0
		):
			return {"valid": false}
		stones.append({
			"id": stone_index,
			"position": position,
			"velocity": velocity,
			"angle": angle,
			"angular_velocity": angular_velocity,
			"in_play": bool(in_play_mask & (1 << stone_index)),
			"moving": bool(moving_mask & (1 << stone_index)),
		})
	return {
		"valid": true,
		"host_tick": host_tick,
		"state_sequence": state_sequence,
		"shot_id": shot_id,
		"stones": stones,
	}


static func _meters_to_i16(pixels: float) -> int:
	return clampi(roundi(pixels / CurlingConstants.PIXELS_PER_METER * 100.0), -32767, 32767)


static func _i16_to_pixels(centimeters: int) -> float:
	return float(centimeters) * CurlingConstants.PIXELS_PER_METER / 100.0

