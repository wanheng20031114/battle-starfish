extends Node
class_name CurlingLanDiscovery

signal rooms_changed(rooms: Array[Dictionary])

var _listener: PacketPeerUDP
var _broadcaster: PacketPeerUDP
var _advertisement: Dictionary = {}
var _rooms: Dictionary = {}
var _broadcast_accumulator := 0.0


func _ready() -> void:
	set_process(true)


func start_listening() -> Error:
	stop_listening()
	_listener = PacketPeerUDP.new()
	var error := _listener.bind(CurlingConstants.LAN_DISCOVERY_PORT, "*")
	if error != OK:
		_listener = null
	return error


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
	_listener = null
	_rooms.clear()


func start_advertising(room_info: Dictionary) -> Error:
	stop_advertising()
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	var error := _broadcaster.connect_to_host("255.255.255.255", CurlingConstants.LAN_DISCOVERY_PORT)
	if error != OK:
		_broadcaster = null
		return error
	_advertisement = room_info.duplicate(true)
	_advertisement["v"] = CurlingConstants.PROTOCOL_VERSION
	_advertisement["port"] = CurlingConstants.LAN_GAME_PORT
	_broadcast_accumulator = 999.0
	return OK


func stop_advertising() -> void:
	if _broadcaster != null:
		_broadcaster.close()
	_broadcaster = null
	_advertisement.clear()


func update_advertisement(changes: Dictionary) -> void:
	if _broadcaster == null:
		return
	for key in changes:
		_advertisement[key] = changes[key]
	_broadcast_accumulator = 999.0


func _process(delta: float) -> void:
	if _broadcaster != null:
		_broadcast_accumulator += delta
		if _broadcast_accumulator >= 1.0:
			_broadcast_accumulator = 0.0
			_broadcaster.put_packet(JSON.stringify(_advertisement).to_utf8_buffer())
	if _listener != null:
		_poll_listener()
	_prune_rooms()


func _poll_listener() -> void:
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var payload := _listener.get_packet()
		if payload.size() <= 0 or payload.size() > 1024:
			continue
		var parsed: Variant = JSON.parse_string(payload.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var room := parsed as Dictionary
		if int(room.get("v", -1)) != CurlingConstants.PROTOCOL_VERSION:
			continue
		var address := _listener.get_packet_ip()
		room["address"] = address
		room["last_seen_ms"] = Time.get_ticks_msec()
		_rooms["%s:%d" % [address, int(room.get("port", CurlingConstants.LAN_GAME_PORT))]] = room
		changed = true
	if changed:
		rooms_changed.emit(get_rooms())


func _prune_rooms() -> void:
	var now_ms := Time.get_ticks_msec()
	var changed := false
	for key in _rooms.keys():
		if now_ms - int((_rooms[key] as Dictionary).get("last_seen_ms", 0)) > 3500:
			_rooms.erase(key)
			changed = true
	if changed:
		rooms_changed.emit(get_rooms())


func get_rooms() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room_variant in _rooms.values():
		result.append((room_variant as Dictionary).duplicate(true))
	return result
