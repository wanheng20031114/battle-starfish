extends Node
class_name CurlingPublicLobbyClient

signal request_completed(action: String, ok: bool, data: Dictionary)

@onready var http_request: HTTPRequest = $HTTPRequest

var api_url := CurlingConstants.PUBLIC_API_URL
var _pending_action := ""


func _ready() -> void:
	http_request.request_completed.connect(_on_request_completed)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--curling-api="):
			api_url = argument.trim_prefix("--curling-api=").trim_suffix("/")


func list_rooms() -> Error:
	return _request("list", HTTPClient.METHOD_GET, "/v1/rooms")


func create_room(nickname: String, ends: int, is_public: bool) -> Error:
	return _request("create", HTTPClient.METHOD_POST, "/v1/rooms", {
		"nickname": nickname,
		"ends": ends,
		"is_public": is_public,
		"protocol_version": CurlingConstants.PROTOCOL_VERSION,
	})


func join_room(code: String, nickname: String) -> Error:
	return _request("join", HTTPClient.METHOD_POST, "/v1/rooms/%s/join" % code.to_upper(), {
		"nickname": nickname,
		"protocol_version": CurlingConstants.PROTOCOL_VERSION,
	})


func quick_match(nickname: String, ends: int) -> Error:
	return _request("matchmake", HTTPClient.METHOD_POST, "/v1/matchmake", {
		"nickname": nickname,
		"ends": ends,
		"protocol_version": CurlingConstants.PROTOCOL_VERSION,
	})


func resume_room(code: String, player_id: String, session_token: String) -> Error:
	return _request("resume", HTTPClient.METHOD_POST, "/v1/rooms/%s/resume" % code.to_upper(), {
		"player_id": player_id,
		"session_token": session_token,
		"protocol_version": CurlingConstants.PROTOCOL_VERSION,
	})


func heartbeat(code: String, host_capability: String, phase: String, roster: Array) -> Error:
	return _request("heartbeat", HTTPClient.METHOD_POST, "/v1/rooms/%s/heartbeat" % code.to_upper(), {
		"host_capability": host_capability,
		"phase": phase,
		"roster": roster,
	})


func close_room(code: String, host_capability: String) -> Error:
	return _request("close", HTTPClient.METHOD_DELETE, "/v1/rooms/%s" % code.to_upper(), {"host_capability": host_capability})


func _request(action: String, method: HTTPClient.Method, path: String, body: Dictionary = {}) -> Error:
	if not _pending_action.is_empty():
		return ERR_BUSY
	_pending_action = action
	var request_body := "" if body.is_empty() else JSON.stringify(body)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var error := http_request.request(api_url + path, headers, method, request_body)
	if error != OK:
		_pending_action = ""
	return error


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _pending_action
	_pending_action = ""
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else {}
	var data := parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {"detail": body.get_string_from_utf8()}
	request_completed.emit(action, result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300, data)

