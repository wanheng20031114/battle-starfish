extends Node
class_name CurlingNet

signal connected
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal packet_received(channel: int, sender_peer_id: int, payload: PackedByteArray)

enum Mode { OFFLINE, LAN_HOST, LAN_CLIENT, PUBLIC }

@onready var relay_endpoint: CurlingRelayEndpoint = $RelayEndpoint

var mode := Mode.OFFLINE
var host_peer_id := 1
var local_peer_id := 1
var authenticated := false
var _public_ticket := ""
var _nickname := ""
var _peer: ENetMultiplayerPeer
var _dev_one_way_delay_ms := 0
var _dev_unreliable_loss := 0.0
var _delayed_packets: Array[Dictionary] = []
var _impairment_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_impairment_rng.randomize()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--curling-net-rtt-ms="):
			_dev_one_way_delay_ms = maxi(0, int(argument.trim_prefix("--curling-net-rtt-ms=")) / 2)
		elif argument.begins_with("--curling-net-loss-percent="):
			_dev_unreliable_loss = clampf(float(argument.trim_prefix("--curling-net-loss-percent=")) / 100.0, 0.0, 0.5)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	relay_endpoint.packet_received.connect(packet_received.emit)
	relay_endpoint.authenticated.connect(_on_relay_authenticated)
	relay_endpoint.authentication_failed.connect(_on_relay_authentication_failed)
	relay_endpoint.relay_peer_joined.connect(func(peer_id: int, _identity: Dictionary) -> void: peer_joined.emit(peer_id))
	relay_endpoint.relay_peer_left.connect(peer_left.emit)
	set_process(true)


func _process(_delta: float) -> void:
	if _delayed_packets.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	for index in range(_delayed_packets.size() - 1, -1, -1):
		var queued: Dictionary = _delayed_packets[index]
		if int(queued.get("deliver_ms", now_ms + 1)) > now_ms:
			continue
		_delayed_packets.remove_at(index)
		_dispatch_packet(int(queued["channel"]), int(queued["target"]), queued["payload"])


func host_lan(port: int = CurlingConstants.LAN_GAME_PORT) -> Error:
	shutdown()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, CurlingConstants.MAX_PLAYERS, CurlingConstants.APP_CHANNEL_COUNT)
	if error != OK:
		_peer = null
		return error
	mode = Mode.LAN_HOST
	host_peer_id = 1
	local_peer_id = 1
	authenticated = true
	multiplayer.root_path = get_path()
	multiplayer.multiplayer_peer = _peer
	connected.emit()
	return OK


func join_lan(address: String, port: int = CurlingConstants.LAN_GAME_PORT) -> Error:
	shutdown()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, port, CurlingConstants.APP_CHANNEL_COUNT)
	if error != OK:
		_peer = null
		return error
	mode = Mode.LAN_CLIENT
	host_peer_id = 1
	authenticated = false
	multiplayer.root_path = get_path()
	multiplayer.multiplayer_peer = _peer
	return OK


func connect_public(address: String, port: int, ticket: String, nickname: String) -> Error:
	shutdown()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, port, CurlingConstants.APP_CHANNEL_COUNT)
	if error != OK:
		_peer = null
		return error
	mode = Mode.PUBLIC
	_public_ticket = ticket
	_nickname = nickname
	authenticated = false
	multiplayer.root_path = relay_endpoint.get_path()
	multiplayer.multiplayer_peer = _peer
	return OK


func shutdown() -> void:
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	multiplayer.root_path = NodePath("/root")
	_peer = null
	mode = Mode.OFFLINE
	host_peer_id = 1
	local_peer_id = 1
	authenticated = false
	_public_ticket = ""
	_delayed_packets.clear()


func is_host() -> bool:
	return mode == Mode.LAN_HOST or (mode == Mode.PUBLIC and authenticated and local_peer_id == host_peer_id)


func is_online() -> bool:
	return mode != Mode.OFFLINE and authenticated


func send_packet(channel: int, target_peer_id: int, payload: PackedByteArray) -> void:
	if payload.is_empty() or channel < 0 or channel > CurlingConstants.CH_CHAT:
		return
	if _should_drop_development_packet(channel):
		return
	if _dev_one_way_delay_ms > 0 and mode != Mode.OFFLINE and target_peer_id != local_peer_id:
		_delayed_packets.append({
			"deliver_ms": Time.get_ticks_msec() + _dev_one_way_delay_ms,
			"channel": channel,
			"target": target_peer_id,
			"payload": payload.duplicate(),
		})
		return
	_dispatch_packet(channel, target_peer_id, payload)


func _dispatch_packet(channel: int, target_peer_id: int, payload: PackedByteArray) -> void:
	if mode == Mode.PUBLIC:
		if authenticated:
			relay_endpoint.send_packet(channel, target_peer_id, payload)
		return
	if mode == Mode.OFFLINE:
		packet_received.emit(channel, local_peer_id, payload)
		return
	if target_peer_id == local_peer_id:
		packet_received.emit(channel, local_peer_id, payload)
		return
	if target_peer_id == 0:
		if not is_host():
			return
		for peer_id in multiplayer.get_peers():
			_send_lan_rpc(channel, peer_id, payload)
	else:
		_send_lan_rpc(channel, target_peer_id, payload)


func _should_drop_development_packet(channel: int) -> bool:
	if _dev_unreliable_loss <= 0.0 or not channel in [
		CurlingConstants.CH_CURSOR,
		CurlingConstants.CH_SWEEP,
		CurlingConstants.CH_STONE_SNAPSHOT,
		CurlingConstants.CH_AIM_PREVIEW,
	]:
		return false
	return _impairment_rng.randf() < _dev_unreliable_loss


func development_impairment_label() -> String:
	return "%dms RTT / %.1f%% loss" % [_dev_one_way_delay_ms * 2, _dev_unreliable_loss * 100.0]


func send_to_host(channel: int, payload: PackedByteArray) -> void:
	if is_host():
		packet_received.emit(channel, local_peer_id, payload)
	else:
		send_packet(channel, host_peer_id, payload)


static func encode_message(message: Dictionary) -> PackedByteArray:
	return var_to_bytes(message)


static func decode_message(payload: PackedByteArray, max_bytes: int = 16384) -> Dictionary:
	if payload.is_empty() or payload.size() > max_bytes:
		return {}
	var decoded: Variant = bytes_to_var(payload)
	return decoded as Dictionary if typeof(decoded) == TYPE_DICTIONARY else {}


func _send_lan_rpc(channel: int, target_peer_id: int, payload: PackedByteArray) -> void:
	match channel:
		0: _rpc_system.rpc_id(target_peer_id, payload)
		1: _rpc_cursor.rpc_id(target_peer_id, payload)
		2: _rpc_sweep.rpc_id(target_peer_id, payload)
		3: _rpc_snapshot.rpc_id(target_peer_id, payload)
		4: _rpc_aim.rpc_id(target_peer_id, payload)
		5: _rpc_gameplay.rpc_id(target_peer_id, payload)
		6: _rpc_chat.rpc_id(target_peer_id, payload)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_system(payload: PackedByteArray) -> void:
	packet_received.emit(0, multiplayer.get_remote_sender_id(), payload)
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_cursor(payload: PackedByteArray) -> void:
	packet_received.emit(1, multiplayer.get_remote_sender_id(), payload)
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_sweep(payload: PackedByteArray) -> void:
	packet_received.emit(2, multiplayer.get_remote_sender_id(), payload)
@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _rpc_snapshot(payload: PackedByteArray) -> void:
	packet_received.emit(3, multiplayer.get_remote_sender_id(), payload)
@rpc("any_peer", "call_remote", "unreliable_ordered", 4)
func _rpc_aim(payload: PackedByteArray) -> void:
	packet_received.emit(4, multiplayer.get_remote_sender_id(), payload)
@rpc("any_peer", "call_remote", "reliable", 5)
func _rpc_gameplay(payload: PackedByteArray) -> void:
	packet_received.emit(5, multiplayer.get_remote_sender_id(), payload)
@rpc("any_peer", "call_remote", "reliable", 6)
func _rpc_chat(payload: PackedByteArray) -> void:
	packet_received.emit(6, multiplayer.get_remote_sender_id(), payload)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	_configure_enet_peer_timeout(1)
	if mode == Mode.PUBLIC:
		relay_endpoint.authenticate_with_relay(_public_ticket, _nickname)
	else:
		authenticated = true
		connected.emit()


func _on_connection_failed() -> void:
	connection_failed.emit("连接失败")
	shutdown()


func _on_server_disconnected() -> void:
	disconnected.emit("Host或Relay已断开")
	shutdown()


func _on_peer_connected(peer_id: int) -> void:
	_configure_enet_peer_timeout(peer_id)
	if mode != Mode.PUBLIC:
		peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if mode != Mode.PUBLIC:
		peer_left.emit(peer_id)


func _on_relay_authenticated(new_host_peer_id: int, new_local_peer_id: int) -> void:
	host_peer_id = new_host_peer_id
	local_peer_id = new_local_peer_id
	authenticated = true
	connected.emit()


func _on_relay_authentication_failed(code: String) -> void:
	connection_failed.emit("Relay认证失败：%s" % code)
	shutdown()


func _configure_enet_peer_timeout(peer_id: int) -> void:
	if _peer == null:
		return
	var packet_peer := _peer.get_peer(peer_id)
	if packet_peer != null:
		packet_peer.set_timeout(32, 4000, CurlingConstants.PEER_DISCONNECT_TIMEOUT_MS)
