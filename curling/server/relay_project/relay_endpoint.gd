extends Node

# 本文件与客户端 RelayEndpoint 保持同一 RPC 接口和通道配置。
# Relay 只认证、限制包长并转发；比赛状态和物理始终由玩家 Host 权威处理。

func _relay() -> Node:
	return get_parent()


@rpc("any_peer", "call_remote", "reliable", 7)
func _rpc_authenticate(ticket: String, nickname: String, protocol_version: int) -> void:
	_relay().authenticate_peer(multiplayer.get_remote_sender_id(), ticket, nickname, protocol_version)


@rpc("authority", "call_remote", "reliable", 7)
func _rpc_auth_result(_ok: bool, _code: String, _host_peer_id: int, _local_peer_id: int) -> void:
	pass


@rpc("authority", "call_remote", "reliable", 7)
func _rpc_relay_peer_joined(_peer_id: int, _identity_payload: PackedByteArray) -> void:
	pass


@rpc("authority", "call_remote", "reliable", 7)
func _rpc_relay_peer_left(_peer_id: int) -> void:
	pass


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_up_system(target_peer_id: int, payload: PackedByteArray) -> void:
	_relay().forward_packet(0, multiplayer.get_remote_sender_id(), target_peer_id, payload)
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_up_cursor(target_peer_id: int, payload: PackedByteArray) -> void:
	_relay().forward_packet(1, multiplayer.get_remote_sender_id(), target_peer_id, payload)
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_up_sweep(target_peer_id: int, payload: PackedByteArray) -> void:
	_relay().forward_packet(2, multiplayer.get_remote_sender_id(), target_peer_id, payload)
@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _rpc_up_snapshot(target_peer_id: int, payload: PackedByteArray) -> void:
	_relay().forward_packet(3, multiplayer.get_remote_sender_id(), target_peer_id, payload)
@rpc("any_peer", "call_remote", "unreliable_ordered", 4)
func _rpc_up_aim(target_peer_id: int, payload: PackedByteArray) -> void:
	_relay().forward_packet(4, multiplayer.get_remote_sender_id(), target_peer_id, payload)
@rpc("any_peer", "call_remote", "reliable", 5)
func _rpc_up_gameplay(target_peer_id: int, payload: PackedByteArray) -> void:
	_relay().forward_packet(5, multiplayer.get_remote_sender_id(), target_peer_id, payload)
@rpc("any_peer", "call_remote", "reliable", 6)
func _rpc_up_chat(target_peer_id: int, payload: PackedByteArray) -> void:
	_relay().forward_packet(6, multiplayer.get_remote_sender_id(), target_peer_id, payload)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_down_system(_sender_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_down_cursor(_sender_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_down_sweep(_sender_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _rpc_down_snapshot(_sender_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("authority", "call_remote", "unreliable_ordered", 4)
func _rpc_down_aim(_sender_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("authority", "call_remote", "reliable", 5)
func _rpc_down_gameplay(_sender_peer_id: int, _payload: PackedByteArray) -> void: pass
@rpc("authority", "call_remote", "reliable", 6)
func _rpc_down_chat(_sender_peer_id: int, _payload: PackedByteArray) -> void: pass


func send_auth_result(peer_id: int, ok: bool, code: String, host_peer_id: int) -> void:
	_rpc_auth_result.rpc_id(peer_id, ok, code, host_peer_id, peer_id)


func send_joined(peer_id: int, joined_peer_id: int, identity: Dictionary) -> void:
	_rpc_relay_peer_joined.rpc_id(peer_id, joined_peer_id, var_to_bytes(identity))


func send_left(peer_id: int, departed_peer_id: int) -> void:
	_rpc_relay_peer_left.rpc_id(peer_id, departed_peer_id)


func send_downstream(channel: int, target_peer_id: int, sender_peer_id: int, payload: PackedByteArray) -> void:
	match channel:
		0: _rpc_down_system.rpc_id(target_peer_id, sender_peer_id, payload)
		1: _rpc_down_cursor.rpc_id(target_peer_id, sender_peer_id, payload)
		2: _rpc_down_sweep.rpc_id(target_peer_id, sender_peer_id, payload)
		3: _rpc_down_snapshot.rpc_id(target_peer_id, sender_peer_id, payload)
		4: _rpc_down_aim.rpc_id(target_peer_id, sender_peer_id, payload)
		5: _rpc_down_gameplay.rpc_id(target_peer_id, sender_peer_id, payload)
		6: _rpc_down_chat.rpc_id(target_peer_id, sender_peer_id, payload)

