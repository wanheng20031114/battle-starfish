extends RefCounted
class_name CurlingNetworkClock

var offset_ms := 0.0
var rtt_ms := 0.0
var jitter_ms := 0.0
var _initialized := false


func make_ping() -> Dictionary:
	return {"client_send_ms": Time.get_ticks_msec()}


func make_pong(ping: Dictionary) -> Dictionary:
	return {
		"client_send_ms": int(ping.get("client_send_ms", 0)),
		"host_receive_ms": Time.get_ticks_msec(),
	}


func accept_pong(pong: Dictionary) -> void:
	var now_ms := Time.get_ticks_msec()
	var client_send_ms := int(pong.get("client_send_ms", now_ms))
	var host_receive_ms := int(pong.get("host_receive_ms", now_ms))
	var sample_rtt := maxf(0.0, float(now_ms - client_send_ms))
	var sample_offset := float(host_receive_ms) - (float(client_send_ms + now_ms) * 0.5)
	if not _initialized:
		rtt_ms = sample_rtt
		offset_ms = sample_offset
		jitter_ms = 0.0
		_initialized = true
		return
	var previous_rtt := rtt_ms
	rtt_ms = lerpf(rtt_ms, sample_rtt, 0.18)
	offset_ms = lerpf(offset_ms, sample_offset, 0.12)
	jitter_ms = lerpf(jitter_ms, absf(sample_rtt - previous_rtt), 0.18)


func estimated_host_time_ms() -> int:
	return roundi(float(Time.get_ticks_msec()) + offset_ms)


func host_to_local_time_ms(host_time_ms: int) -> int:
	return roundi(float(host_time_ms) - offset_ms)
