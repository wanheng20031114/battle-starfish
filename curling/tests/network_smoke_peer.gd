extends Node

@onready var net: CurlingNet = $CurlingNet

var _role := "client"
var _transport := "lan"
var _index := 0
var _port := 45150
var _report_path := ""
var _ticket := ""
var _nickname := "smoke-client"
var _expected_players := CurlingConstants.MAX_PLAYERS
var _elapsed := 0.0
var _registered: Dictionary = {}


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--curling-smoke-role="):
			_role = argument.trim_prefix("--curling-smoke-role=")
		elif argument.begins_with("--curling-smoke-transport="):
			_transport = argument.trim_prefix("--curling-smoke-transport=")
		elif argument.begins_with("--curling-smoke-index="):
			_index = int(argument.trim_prefix("--curling-smoke-index="))
		elif argument.begins_with("--curling-smoke-port="):
			_port = int(argument.trim_prefix("--curling-smoke-port="))
		elif argument.begins_with("--curling-smoke-report="):
			_report_path = argument.trim_prefix("--curling-smoke-report=")
		elif argument.begins_with("--curling-smoke-ticket="):
			_ticket = argument.trim_prefix("--curling-smoke-ticket=")
		elif argument.begins_with("--curling-smoke-nickname="):
			_nickname = argument.trim_prefix("--curling-smoke-nickname=")
		elif argument.begins_with("--curling-smoke-players="):
			_expected_players = clampi(
				int(argument.trim_prefix("--curling-smoke-players=")),
				CurlingConstants.MIN_PLAYERS,
				CurlingConstants.MAX_PLAYERS
			)
	net.connected.connect(_on_connected)
	net.packet_received.connect(_on_packet)
	net.connection_failed.connect(func(reason: String) -> void: _fail(reason))
	net.disconnected.connect(func(reason: String) -> void: _fail(reason))
	if _transport == "public":
		var error := net.connect_public("127.0.0.1", _port, _ticket, _nickname)
		if error != OK:
			_fail("public connect error %s" % error_string(error))
	elif _role == "host":
		var error := net.host_lan(_port)
		if error != OK:
			_fail("host error %s" % error_string(error))
	else:
		var error := net.join_lan("127.0.0.1", _port)
		if error != OK:
			_fail("join error %s" % error_string(error))


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 15.0:
		_fail("timeout")


func _on_connected() -> void:
	if _role == "host":
		_registered[net.local_peer_id] = "host"
	else:
		net.send_to_host(CurlingConstants.CH_SYSTEM, CurlingNet.encode_message({
			"type": "smoke_register",
			"index": _index,
			"protocol": CurlingConstants.PROTOCOL_VERSION,
		}))


func _on_packet(channel: int, sender: int, payload: PackedByteArray) -> void:
	if channel != CurlingConstants.CH_SYSTEM:
		return
	var message := CurlingNet.decode_message(payload, 4096)
	if _role == "host" and str(message.get("type", "")) == "smoke_register":
		if int(message.get("protocol", -1)) != CurlingConstants.PROTOCOL_VERSION:
			_fail("protocol mismatch accepted")
			return
		_registered[sender] = "client-%d" % int(message.get("index", -1))
		if _registered.size() == _expected_players:
			_write_report({"ok": true, "players": _registered.size(), "peer_ids": _registered.keys()})
			net.send_packet(CurlingConstants.CH_SYSTEM, 0, CurlingNet.encode_message({"type": "smoke_complete"}))
			await get_tree().create_timer(0.15).timeout
			get_tree().quit(0)
	elif _role != "host" and sender == net.host_peer_id and str(message.get("type", "")) == "smoke_complete":
		get_tree().quit(0)


func _fail(reason: String) -> void:
	if _role == "host":
		_write_report({"ok": false, "reason": reason, "players": _registered.size()})
	push_error("CURLING_SMOKE_FAIL role=%s index=%d reason=%s" % [_role, _index, reason])
	get_tree().quit(1)


func _write_report(data: Dictionary) -> void:
	if _report_path.is_empty():
		return
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
