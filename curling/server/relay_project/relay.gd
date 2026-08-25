extends Node

const SERVER_PEER_ID := 1
const APP_CHANNEL_COUNT := 8
const MAX_PLAYERS := 8
const SNAPSHOT_BYTES := 204
const CHANNEL_LIMITS := {
	0: 65536,
	1: 4096,
	2: 16384,
	3: SNAPSHOT_BYTES,
	4: 4096,
	5: 16384,
	6: 16384,
}

@onready var endpoint: Node = $RelayEndpoint

var _peer := ENetMultiplayerPeer.new()
var _room_id := ""
var _admission_secret := ""
var _protocol_version := 2
var _max_clients := MAX_PLAYERS
var _host_peer_id := 0
var _authenticated: Dictionary = {}
var _pending_members: Dictionary = {}
var _used_nonces: Dictionary = {}


func _ready() -> void:
	_room_id = OS.get_environment("CURLING_ROOM_ID")
	_admission_secret = OS.get_environment("CURLING_ADMISSION_SECRET")
	_protocol_version = int(OS.get_environment("CURLING_PROTOCOL_VERSION"))
	_max_clients = clampi(int(OS.get_environment("CURLING_MAX_CLIENTS")), 1, MAX_PLAYERS)
	var port := int(OS.get_environment("CURLING_RELAY_PORT"))
	if _room_id.is_empty() or _admission_secret.length() < 32 or port <= 0:
		push_error("Curling Relay 缺少有效启动参数")
		get_tree().quit(2)
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_relay = false
	var error := _peer.create_server(port, _max_clients, APP_CHANNEL_COUNT)
	if error != OK:
		push_error("Curling Relay 无法监听 UDP 端口：%s" % error_string(error))
		get_tree().quit(3)
		return
	# 两端都把 MultiplayerAPI 根定在 RelayEndpoint，保证 RPC 路径和签名完全一致。
	multiplayer.root_path = endpoint.get_path()
	multiplayer.multiplayer_peer = _peer
	print("Curling Relay ready room=%s port=%d" % [_room_id, port])


func authenticate_peer(peer_id: int, ticket: String, nickname: String, protocol_version: int) -> void:
	if _authenticated.has(peer_id) or _pending_members.has(peer_id):
		_reject(peer_id, "already_authenticated")
		return
	var claims := _verify_ticket(ticket)
	if claims.is_empty():
		_reject(peer_id, "invalid_ticket")
		return
	if protocol_version != _protocol_version or int(claims.get("v", -1)) != _protocol_version:
		_reject(peer_id, "protocol_mismatch")
		return
	if str(claims.get("room_id", "")) != _room_id:
		_reject(peer_id, "wrong_room")
		return
	if str(claims.get("player_name", "")) != nickname.strip_edges():
		_reject(peer_id, "identity_mismatch")
		return
	if _identity_in_use(str(claims.get("player_id", ""))):
		_reject(peer_id, "identity_in_use")
		return
	var nonce := str(claims.get("nonce", ""))
	if nonce.is_empty() or _used_nonces.has(nonce):
		_reject(peer_id, "ticket_replayed")
		return
	_used_nonces[nonce] = int(claims.get("exp", 0))
	_prune_nonces()
	var role := str(claims.get("role", ""))
	if role == "host":
		if _host_peer_id != 0:
			_reject(peer_id, "host_already_connected")
			return
		_accept(peer_id, claims)
		_host_peer_id = peer_id
		endpoint.send_auth_result(peer_id, true, "ok", _host_peer_id)
		_accept_pending_members()
	elif role == "member":
		if _host_peer_id == 0:
			# API 可能先把成员票据发出；等 Host 到达后再统一放行，避免错误指定权威端。
			_pending_members[peer_id] = claims
		else:
			_accept_member(peer_id, claims)
	else:
		_reject(peer_id, "invalid_role")


func forward_packet(channel: int, sender_peer_id: int, target_peer_id: int, payload: PackedByteArray) -> void:
	if not _authenticated.has(sender_peer_id) or not CHANNEL_LIMITS.has(channel):
		return
	var limit := int(CHANNEL_LIMITS[channel])
	if payload.is_empty() or payload.size() > limit:
		return
	if channel == 3 and payload.size() != SNAPSHOT_BYTES:
		return
	if sender_peer_id != _host_peer_id:
		# 普通成员的业务意图只能发往 Host；禁止成员互相注入状态。
		if target_peer_id != _host_peer_id:
			return
		endpoint.send_downstream(channel, _host_peer_id, sender_peer_id, payload)
		return
	if target_peer_id == 0:
		for peer_id in _authenticated:
			if int(peer_id) != sender_peer_id:
				endpoint.send_downstream(channel, int(peer_id), sender_peer_id, payload)
	elif _authenticated.has(target_peer_id) and target_peer_id != sender_peer_id:
		endpoint.send_downstream(channel, target_peer_id, sender_peer_id, payload)


func _accept_member(peer_id: int, claims: Dictionary) -> void:
	_accept(peer_id, claims)
	endpoint.send_auth_result(peer_id, true, "ok", _host_peer_id)
	var identity := _public_identity(claims)
	endpoint.send_joined(_host_peer_id, peer_id, identity)
	endpoint.send_joined(peer_id, _host_peer_id, _public_identity(_authenticated[_host_peer_id]))


func _accept_pending_members() -> void:
	for pending_peer in _pending_members.keys():
		var peer_id := int(pending_peer)
		if multiplayer.get_peers().has(peer_id):
			_accept_member(peer_id, _pending_members[pending_peer])
	_pending_members.clear()


func _accept(peer_id: int, claims: Dictionary) -> void:
	_authenticated[peer_id] = claims


func _reject(peer_id: int, code: String) -> void:
	endpoint.send_auth_result(peer_id, false, code, _host_peer_id)


func _on_peer_connected(peer_id: int) -> void:
	var packet_peer := _peer.get_peer(peer_id)
	if packet_peer != null:
		packet_peer.set_timeout(32, 4000, 8000)


func _on_peer_disconnected(peer_id: int) -> void:
	_pending_members.erase(peer_id)
	if not _authenticated.has(peer_id):
		return
	var was_host := peer_id == _host_peer_id
	_authenticated.erase(peer_id)
	for target in _authenticated:
		endpoint.send_left(int(target), peer_id)
	if was_host:
		# Host 是唯一比赛权威；不迁移 Host，房间随之结束。
		get_tree().create_timer(0.1).timeout.connect(func() -> void: get_tree().quit(0))


func _verify_ticket(ticket: String) -> Dictionary:
	if ticket.length() > 4096:
		return {}
	var pieces := ticket.split(".", false)
	if pieces.size() != 3 or pieces[0] != "ct1" or pieces[2].length() != 64:
		return {}
	var signed_message := "%s.%s" % [pieces[0], pieces[1]]
	var crypto := Crypto.new()
	var expected := crypto.hmac_digest(
		HashingContext.HASH_SHA256,
		_admission_secret.to_utf8_buffer(),
		signed_message.to_utf8_buffer()
	).hex_encode()
	if not _constant_time_equal(expected, pieces[2]):
		return {}
	var encoded_payload := pieces[1].replace("-", "+").replace("_", "/")
	while encoded_payload.length() % 4 != 0:
		encoded_payload += "="
	var raw := Marshalls.base64_to_raw(encoded_payload)
	if raw.is_empty() or raw.size() > 2048:
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var claims := parsed as Dictionary
	var required := ["v", "room_id", "role", "player_name", "player_id", "iat", "exp", "nonce"]
	for key in required:
		if not claims.has(key):
			return {}
	var now := int(Time.get_unix_time_from_system())
	if int(claims["iat"]) > now + 5 or int(claims["exp"]) < now:
		return {}
	if str(claims["player_id"]).is_empty() or str(claims["player_name"]).length() > 20:
		return {}
	return claims


func _identity_in_use(player_id: String) -> bool:
	if player_id.is_empty():
		return true
	for claims in _authenticated.values():
		if str((claims as Dictionary).get("player_id", "")) == player_id:
			return true
	for claims in _pending_members.values():
		if str((claims as Dictionary).get("player_id", "")) == player_id:
			return true
	return false


func _public_identity(claims: Dictionary) -> Dictionary:
	return {
		"player_id": str(claims.get("player_id", "")),
		"nickname": str(claims.get("player_name", "")),
		"role": str(claims.get("role", "member")),
	}


func _prune_nonces() -> void:
	var now := int(Time.get_unix_time_from_system())
	for nonce in _used_nonces.keys():
		if int(_used_nonces[nonce]) < now:
			_used_nonces.erase(nonce)


func _constant_time_equal(left: String, right: String) -> bool:
	if left.length() != right.length():
		return false
	var difference := 0
	for index in range(left.length()):
		difference |= left.unicode_at(index) ^ right.unicode_at(index)
	return difference == 0
