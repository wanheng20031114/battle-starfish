extends Node
class_name CurlingRelayEndpoint

signal packet_received(channel: int, sender_peer_id: int, payload: PackedByteArray)
signal authenticated(host_peer_id: int, local_peer_id: int)
signal authentication_failed(code: String)
signal relay_peer_joined(peer_id: int, identity: Dictionary)
signal relay_peer_left(peer_id: int)


func authenticate_with_relay(ticket: String, nickname: String) -> void:
	_rpc_authenticate.rpc_id(1, ticket, nickname, CurlingConstants.PROTOCOL_VERSION)


func send_packet(channel: int, target_peer_id: int, payload: PackedByteArray) -> void:
	match channel:
		0: _rpc_up_system.rpc_id(1, target_peer_id, payload)
		1: _rpc_up_cursor.rpc_id(1, target_peer_id, payload)
		2: _rpc_up_sweep.rpc_id(1, target_peer_id, payload)
		3: _rpc_up_snapshot.rpc_id(1, target_peer_id, payload)
		4: _rpc_up_aim.rpc_id(1, target_peer_id, payload)
		5: _rpc_up_gameplay.rpc_id(1, target_peer_id, payload)
		6: _rpc_up_chat.rpc_id(1, target_peer_id, payload)


@rpc("any_peer", "call_remote", "reliable", 7)
func _rpc_authenticate(_ticket: String, _nickname: String, _protocol_version: int) -> void:
	pass


@rpc("authority", "call_remote", "reliable", 7)
func _rpc_auth_result(ok: bool, code: String, host_peer_id: int, local_peer_id: int) -> void:
	if ok:
		authenticated.emit(host_peer_id, local_peer_id)
	else:
		authentication_failed.emit(code)


@rpc("authority", "call_remote", "reliable", 7)
func _rpc_relay_peer_joined(peer_id: int, identity_payload: PackedByteArray) -> void:
	var identity_variant: Variant = bytes_to_var(identity_payload)
	if typeof(identity_variant) == TYPE_DICTIONARY:
		relay_peer_joined.emit(peer_id, identity_variant as Dictionary)


@rpc("authority", "call_remote", "reliable", 7)
func _rpc_relay_peer_left(peer_id: int) -> void:
	relay_peer_left.emit(peer_id)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_up_system(_target_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_up_cursor(_target_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_up_sweep(_target_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _rpc_up_snapshot(_target_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("any_peer", "call_remote", "unreliable_ordered", 4)
func _rpc_up_aim(_target_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("any_peer", "call_remote", "reliable", 5)
func _rpc_up_gameplay(_target_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("any_peer", "call_remote", "reliable", 6)
func _rpc_up_chat(_target_peer_id: int, _payload: PackedByteArray) -> void: pass


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_down_system(sender_peer_id: int, payload: PackedByteArray) -> void:
	packet_received.emit(0, sender_peer_id, payload)
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_down_cursor(sender_peer_id: int, payload: PackedByteArray) -> void:
	packet_received.emit(1, sender_peer_id, payload)
@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_down_sweep(sender_peer_id: int, payload: PackedByteArray) -> void:
	packet_received.emit(2, sender_peer_id, payload)
@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _rpc_down_snapshot(sender_peer_id: int, payload: PackedByteArray) -> void:
	packet_received.emit(3, sender_peer_id, payload)
@rpc("authority", "call_remote", "unreliable_ordered", 4)
func _rpc_down_aim(sender_peer_id: int, payload: PackedByteArray) -> void:
	packet_received.emit(4, sender_peer_id, payload)
@rpc("authority", "call_remote", "reliable", 5)
func _rpc_down_gameplay(sender_peer_id: int, payload: PackedByteArray) -> void:
	packet_received.emit(5, sender_peer_id, payload)
@rpc("authority", "call_remote", "reliable", 6)
func _rpc_down_chat(sender_peer_id: int, payload: PackedByteArray) -> void:
	packet_received.emit(6, sender_peer_id, payload)
