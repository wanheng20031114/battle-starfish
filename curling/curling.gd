extends Node
class_name CurlingApp

const SESSION_FILE := "user://curling_session.json"
const MAIN_MENU_SCENE := "res://scene/main_menu/main_menu.tscn"
const LEAVE_ACK_TIMEOUT_MS := 1500
const SHOT_CLOCK_WARNING_SECONDS := [10, 5, 4, 3, 2, 1]
const CurlingSettingsScript := preload("res://curling/settings/curling_settings.gd")
const CurlingSettingsPanelScript := preload("res://curling/settings/curling_settings_panel.gd")
const CurlingManualPanelScript := preload("res://curling/manual/curling_manual_panel.gd")

@onready var net: CurlingNet = $CurlingNet
@onready var lan_discovery: CurlingLanDiscovery = $LanDiscovery
@onready var public_lobby: CurlingPublicLobbyClient = $PublicLobbyClient
@onready var settings: CurlingSettingsScript = $CurlingSettings
@onready var audio: CurlingAudio = $CurlingAudio
@onready var match_controller: CurlingMatchController = $MatchController

@onready var username_screen: Control = $UI/UsernameScreen
@onready var username_panel: Panel = $UI/UsernameScreen/Center/Card
@onready var username_input: LineEdit = $UI/UsernameScreen/Center/Card/Margin/Layout/UsernameInput
@onready var username_error: Label = $UI/UsernameScreen/Center/Card/Margin/Layout/UsernameError
@onready var lobby_screen: Control = $UI/LobbyScreen
@onready var room_screen: Control = $UI/RoomScreen
@onready var tactics_screen: Control = $UI/TacticsScreen
@onready var match_hud: Control = $UI/MatchHUD
@onready var result_screen: Control = $UI/ResultScreen
@onready var diagnostics: Label = $UI/Diagnostics
@onready var settings_panel: CurlingSettingsPanelScript = $UI/SettingsPanel
@onready var manual_panel: CurlingManualPanelScript = $UI/ManualPanel

@onready var nickname_input: LineEdit = $UI/LobbyScreen/Layout/Right/Nickname
@onready var lobby_identity: Label = $UI/LobbyScreen/Layout/Right/IdentityRow/Identity
@onready var ends_option: OptionButton = $UI/LobbyScreen/Layout/Right/EndsRow/Ends
@onready var address_input: LineEdit = $UI/LobbyScreen/Layout/Right/AddressRow/Address
@onready var room_code_input: LineEdit = $UI/LobbyScreen/Layout/Right/CodeRow/RoomCode
@onready var lobby_status: Label = $UI/LobbyScreen/Layout/Right/Status
@onready var public_rooms: ItemList = $UI/LobbyScreen/Layout/Right/PublicRooms
@onready var resume_button: Button = $UI/LobbyScreen/Layout/Right/PublicActions/Resume

@onready var room_title: Label = $UI/RoomScreen/Layout/Header/RoomTitle
@onready var red_roster: Label = $UI/RoomScreen/Layout/Teams/RedTeam/RedRoster
@onready var blue_roster: Label = $UI/RoomScreen/Layout/Teams/BlueTeam/BlueRoster
@onready var room_status: Label = $UI/RoomScreen/Layout/RoomStatus
@onready var ready_button: Button = $UI/RoomScreen/Layout/Actions/Ready
@onready var start_button: Button = $UI/RoomScreen/Layout/Actions/Start
@onready var host_assign: HBoxContainer = $UI/RoomScreen/Layout/HostAssign
@onready var host_assign_player: OptionButton = $UI/RoomScreen/Layout/HostAssign/Player

@onready var tactics_title: Label = $UI/TacticsScreen/Panel/Layout/Title
@onready var tactics_timer: Label = $UI/TacticsScreen/Panel/Layout/Timer
@onready var tactics_slots: ItemList = $UI/TacticsScreen/Panel/Layout/Slots
@onready var tactics_confirm: Button = $UI/TacticsScreen/Panel/Layout/Confirm

@onready var score_label: Label = $UI/MatchHUD/TopBar/Score
@onready var end_label: Label = $UI/MatchHUD/TopBar/End
@onready var timer_label: Label = $UI/MatchHUD/TopBar/Timer
@onready var active_label: Label = $UI/MatchHUD/RightRail/Layout/Active
@onready var team_status_label: Label = $UI/MatchHUD/RightRail/Layout/Teams
@onready var instruction_label: Label = $UI/MatchHUD/BottomBar/Instruction
@onready var power_bar: ProgressBar = $UI/MatchHUD/BottomBar/Power
@onready var spin_label: Label = $UI/MatchHUD/BottomBar/Spin
@onready var minimap: CurlingMinimap = $UI/MatchHUD/RightRail/Layout/Minimap
@onready var chat_history: RichTextLabel = $UI/MatchHUD/RightRail/Layout/ChatHistory
@onready var chat_channel: OptionButton = $UI/MatchHUD/RightRail/Layout/ChatRow/Channel
@onready var chat_input: LineEdit = $UI/MatchHUD/RightRail/Layout/ChatRow/Input

@onready var result_title: Label = $UI/ResultScreen/Panel/Layout/Title
@onready var result_score: Label = $UI/ResultScreen/Panel/Layout/Score
@onready var cursor_root: Control = $UI/CursorLayer

var _log := CurlingLog.new()
var _network_clock := CurlingNetworkClock.new()
var _room_players: Dictionary = {}
var _room_ends := 1
var _room_code := "LOCAL"
var _host_capability := ""
var _session_token := ""
var _public_player_id := ""
var _public_role := ""
var _demo_mode := false
var _room_started := false
var _cursor_send_accumulator := 0.0
var _clock_sync_accumulator := 0.0
var _heartbeat_accumulator := 0.0
var _chat_sent_ms: Dictionary = {}
var _chat_messages: Array[Dictionary] = []
var _remote_cursors: Array[CurlingRemoteCursor] = []
var _cursor_by_player: Dictionary = {}
var _lan_rooms: Array[Dictionary] = []
var _public_room_rows: Array[Dictionary] = []
var _debug_enabled := false
var _last_gameplay_notice := ""
var _disconnect_deadlines: Dictionary = {}
var _resume_payload: Dictionary = {}
var _heat_sync_accumulator := 0.0
var _session_refresh_accumulator := 0.0
var _cursor_last_received_ms: Dictionary = {}
var _lobby_services_started := false
var _username_intro_tween: Tween
var _current_screen := ""
var _leaving_room := false
var _leave_ack_deadline_ms := 0
var _last_shot_clock_warning_shot_id := -1
var _last_shot_clock_warning_second := -1


func _ready() -> void:
	_setup_options()
	_connect_ui()
	_connect_runtime()
	for child in cursor_root.get_children():
		if child is CurlingRemoteCursor:
			_remote_cursors.append(child as CurlingRemoteCursor)
	minimap.match_controller = match_controller
	match_controller.reduced_motion = settings.is_reduced_motion_enabled()
	var saved_nickname := _sanitize_nickname(_load_saved_nickname())
	# 旧版把占位名写进了配置；迁移后让玩家明确选择自己的名字。
	if saved_nickname == "冰壶手":
		saved_nickname = ""
	username_input.text = saved_nickname
	nickname_input.text = saved_nickname
	_update_lobby_identity()
	_ensure_local_session_token()
	_load_session_offer()
	_show_username_entry()
	_log.event("app", "ready", {"protocol": CurlingConstants.PROTOCOL_VERSION})


func _process(delta: float) -> void:
	if _leaving_room and Time.get_ticks_msec() >= _leave_ack_deadline_ms:
		_finish_pending_room_exit()
	_cursor_send_accumulator += delta
	_clock_sync_accumulator += delta
	_heartbeat_accumulator += delta
	_heat_sync_accumulator += delta
	_session_refresh_accumulator += delta
	if _cursor_send_accumulator >= 1.0 / CurlingConstants.CURSOR_HZ:
		_cursor_send_accumulator = 0.0
		_send_cursor()
	if net.is_online() and not net.is_host() and _clock_sync_accumulator >= CurlingConstants.CLOCK_SYNC_INTERVAL_SEC:
		_clock_sync_accumulator = 0.0
		_send_to_host(CurlingConstants.CH_SYSTEM, {"type": "ping", "data": _network_clock.make_ping()})
	if net.is_online() and net.is_host() and net.mode == CurlingNet.Mode.PUBLIC and not _host_capability.is_empty() and _heartbeat_accumulator >= 10.0:
		_heartbeat_accumulator = 0.0
		public_lobby.heartbeat(_room_code, _host_capability, _phase_wire_name(), _room_roster_for_api())
	if net.is_online() and net.mode == CurlingNet.Mode.PUBLIC and _session_refresh_accumulator >= 10.0:
		_session_refresh_accumulator = 0.0
		_store_session_file()
	if net.is_online() and net.is_host() and _heat_sync_accumulator >= CurlingConstants.HEAT_RESYNC_SEC:
		_heat_sync_accumulator = 0.0
		var sparse := match_controller.heat_grid.export_sparse()
		if not sparse.is_empty():
			_send_packet(CurlingConstants.CH_SWEEP, 0, {
				"type": "heat_sparse",
				"payload": sparse,
				"time_ms": Time.get_ticks_msec(),
			})
	_update_tactics_ui()
	_process_disconnect_grace()
	_update_diagnostics()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F1:
			_toggle_manual()
			get_viewport().set_input_as_handled()
		elif key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			if manual_panel.is_open():
				manual_panel.close_panel()
			elif username_screen.visible:
				_return_to_main_menu()
			elif settings_panel.is_open():
				settings_panel.close_panel()
			else:
				_open_settings()
			get_viewport().set_input_as_handled()
		elif key_event.pressed and not key_event.echo and key_event.keycode == KEY_F3:
			_debug_enabled = not _debug_enabled
			diagnostics.visible = _debug_enabled


func _setup_options() -> void:
	ends_option.clear()
	for ends in [1, 2, 4]:
		ends_option.add_item("%d End" % ends, ends)
	ends_option.select(0)
	chat_channel.clear()
	chat_channel.add_item("队伍", 0)
	chat_channel.add_item("全局", 1)


func _connect_ui() -> void:
	$UI/UsernameScreen/Center/Card/Margin/Layout/Actions/Confirm.pressed.connect(_confirm_username)
	$UI/UsernameScreen/Center/Card/Margin/Layout/Actions/Back.pressed.connect(_return_to_main_menu)
	username_input.text_submitted.connect(_on_username_submitted)
	$UI/LobbyScreen/Layout/Right/IdentityRow/ChangeNickname.pressed.connect(_show_username_entry)
	$UI/LobbyScreen/Layout/Right/Demo.pressed.connect(_on_demo_pressed)
	$UI/LobbyScreen/Layout/Right/NetworkActions/HostLan.pressed.connect(_on_host_lan_pressed)
	$UI/LobbyScreen/Layout/Right/NetworkActions/CreatePublic.pressed.connect(_on_create_public_pressed)
	$UI/LobbyScreen/Layout/Right/AddressRow/JoinLan.pressed.connect(_on_join_lan_pressed)
	$UI/LobbyScreen/Layout/Right/CodeRow/JoinCode.pressed.connect(_on_join_code_pressed)
	$UI/LobbyScreen/Layout/Right/PublicActions/Refresh.pressed.connect(func() -> void: public_lobby.list_rooms())
	$UI/LobbyScreen/Layout/Right/PublicActions/Quick.pressed.connect(_on_quick_match_pressed)
	$UI/LobbyScreen/Layout/Right/PublicActions/Settings.pressed.connect(_open_settings)
	resume_button.pressed.connect(_on_resume_pressed)
	public_rooms.item_activated.connect(_on_public_room_activated)
	$UI/RoomScreen/Layout/Actions/Red.pressed.connect(func() -> void: _request_room_intent("team", CurlingConstants.TEAM_RED))
	$UI/RoomScreen/Layout/Actions/Blue.pressed.connect(func() -> void: _request_room_intent("team", CurlingConstants.TEAM_BLUE))
	$UI/RoomScreen/Layout/HostAssign/ToRed.pressed.connect(func() -> void: _host_assign_selected_player(CurlingConstants.TEAM_RED))
	$UI/RoomScreen/Layout/HostAssign/ToBlue.pressed.connect(func() -> void: _host_assign_selected_player(CurlingConstants.TEAM_BLUE))
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	$UI/RoomScreen/Layout/Actions/Leave.pressed.connect(_leave_room)
	$UI/RoomScreen/Layout/Actions/Settings.pressed.connect(_open_settings)
	tactics_slots.item_clicked.connect(_on_tactics_slot_clicked)
	tactics_confirm.pressed.connect(_on_tactics_confirm_pressed)
	$UI/TacticsScreen/Panel/Layout/ExitRoom.pressed.connect(_leave_room)
	chat_input.text_submitted.connect(_on_chat_submitted)
	$UI/MatchHUD/RightRail/Layout/Actions/Manual.pressed.connect(_open_manual)
	$UI/MatchHUD/RightRail/Layout/Actions/Settings.pressed.connect(_open_settings)
	$UI/MatchHUD/RightRail/Layout/ExitRoom.pressed.connect(_leave_room)
	$UI/ResultScreen/Panel/Layout/Settings.pressed.connect(_open_settings)
	$UI/ResultScreen/Panel/Layout/BackToRoom.pressed.connect(_return_to_room_after_match)
	$UI/ResultScreen/Panel/Layout/ExitRoom.pressed.connect(_leave_room)
	settings_panel.opened.connect(_on_settings_opened)
	settings_panel.closed.connect(_on_settings_closed)
	manual_panel.opened.connect(_on_manual_opened)
	manual_panel.closed.connect(_on_manual_closed)


func _connect_runtime() -> void:
	net.connected.connect(_on_net_connected)
	net.connection_failed.connect(_on_net_connection_failed)
	net.disconnected.connect(_on_net_disconnected)
	net.peer_left.connect(_on_peer_left)
	net.packet_received.connect(_on_net_packet)
	lan_discovery.rooms_changed.connect(_on_lan_rooms_changed)
	public_lobby.request_completed.connect(_on_public_request_completed)
	match_controller.state_changed.connect(_on_match_state_changed)
	match_controller.hud_changed.connect(_on_match_hud_changed)
	match_controller.throw_intent.connect(func(direction: Vector2, power: float, spin: float) -> void:
		_send_to_host(CurlingConstants.CH_GAMEPLAY, {"type": "throw", "direction": direction, "power": power, "spin": spin})
	)
	match_controller.aim_preview_intent.connect(_on_local_aim_preview)
	match_controller.sweep_intent.connect(func(from_world: Vector2, to_world: Vector2, delta_sec: float, host_ms: int) -> void:
		var estimated_host_ms := _network_clock.estimated_host_time_ms() if net.is_online() and not net.is_host() else host_ms
		_send_to_host(CurlingConstants.CH_SWEEP, {"type": "sweep", "from": from_world, "to": to_world, "delta": delta_sec, "host_ms": estimated_host_ms})
	)
	match_controller.snapshot_ready.connect(func(payload: PackedByteArray) -> void:
		if net.is_online() and net.is_host(): net.send_packet(CurlingConstants.CH_STONE_SNAPSHOT, 0, payload)
	)
	match_controller.heat_grid.authoritative_segment.connect(_on_authoritative_heat_segment)
	match_controller.gameplay_event.connect(_on_gameplay_event)
	match_controller.match_finished.connect(_on_match_finished)
	settings.reduced_motion_changed.connect(_on_reduced_motion_changed)


func _show_username_entry(message: String = "") -> void:
	if username_input.text.is_empty() and not nickname_input.text.is_empty():
		username_input.text = nickname_input.text
	username_error.text = message
	username_error.visible = not message.is_empty()
	_show_screen("username")
	_play_username_intro()
	username_input.call_deferred("grab_focus")
	username_input.call_deferred("select_all")


func _play_username_intro() -> void:
	if _username_intro_tween != null and _username_intro_tween.is_valid():
		_username_intro_tween.kill()
	username_panel.modulate.a = 1.0 if settings.is_reduced_motion_enabled() else 0.0
	if settings.is_reduced_motion_enabled():
		return
	_username_intro_tween = create_tween()
	_username_intro_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_username_intro_tween.tween_property(username_panel, "modulate:a", 1.0, 0.18)


func _on_username_submitted(_submitted: String) -> void:
	_confirm_username()


func _confirm_username(start_services: bool = true, persist_nickname: bool = true) -> void:
	var nickname := _sanitize_nickname(username_input.text)
	if nickname.is_empty():
		username_error.text = "用户名需为2–16个可显示字符"
		username_error.visible = true
		username_input.grab_focus()
		return
	username_error.visible = false
	nickname_input.text = nickname
	username_input.text = nickname
	_update_lobby_identity()
	if persist_nickname:
		_save_nickname()
	_show_screen("lobby")
	if start_services:
		_start_lobby_services()


func _start_lobby_services() -> void:
	if not _lobby_services_started:
		_lobby_services_started = true
		lan_discovery.start_listening()
	public_lobby.list_rooms()


func _update_lobby_identity() -> void:
	var nickname := _sanitize_nickname(nickname_input.text)
	lobby_identity.text = "当前玩家：%s" % (nickname if not nickname.is_empty() else "未确认")


func _return_to_main_menu() -> void:
	net.shutdown()
	lan_discovery.stop_listening()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_demo_pressed(persist_nickname: bool = true) -> void:
	if persist_nickname:
		_save_nickname()
	_reset_public_identity()
	_demo_mode = true
	_room_ends = _selected_ends()
	_room_code = "DEMO"
	_room_players.clear()
	var names := [_nickname(), "阿霜", "小岚", "北辰", "夏沫", "海盐", "青禾", "白露"]
	for index in range(CurlingConstants.MAX_PLAYERS):
		_room_players[index + 1] = {
			"id": index + 1,
			"nickname": names[index],
			"team": CurlingConstants.TEAM_RED if index % 2 == 0 else CurlingConstants.TEAM_BLUE,
			"join_order": index,
			"connected": true,
			"ready": true,
			"bot": index > 0,
			"color": CurlingConstants.PLAYER_COLORS[index],
		}
	_show_room()


func _on_host_lan_pressed() -> void:
	_save_nickname()
	_reset_public_identity()
	var error := net.host_lan()
	if error != OK:
		_set_lobby_status("LAN Host创建失败：%s" % error_string(error))
		return
	_demo_mode = false
	_room_ends = _selected_ends()
	_room_code = _random_room_code()
	_room_players.clear()
	_add_local_room_player()
	lan_discovery.stop_listening()
	lan_discovery.start_advertising({"code": _room_code, "name": "%s的房间" % _nickname(), "ends": _room_ends, "players": 1})
	_show_room()


func _on_join_lan_pressed() -> void:
	_save_nickname()
	_reset_public_identity()
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var error := net.join_lan(address)
	if error != OK:
		_set_lobby_status("LAN连接失败：%s" % error_string(error))
	else:
		_set_lobby_status("正在连接 %s…" % address)


func _on_create_public_pressed() -> void:
	_save_nickname()
	_set_lobby_status("正在申请公网测试房…")
	public_lobby.create_room(_nickname(), _selected_ends(), true)


func _on_join_code_pressed() -> void:
	_save_nickname()
	var code := room_code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		_set_lobby_status("请输入6位房间码")
		return
	public_lobby.join_room(code, _nickname())


func _on_quick_match_pressed() -> void:
	_save_nickname()
	_set_lobby_status("正在快速匹配…")
	public_lobby.quick_match(_nickname(), _selected_ends())


func _on_public_room_activated(index: int) -> void:
	if index < 0 or index >= _public_room_rows.size():
		return
	room_code_input.text = str(_public_room_rows[index].get("code", ""))
	_on_join_code_pressed()


func _on_net_connected() -> void:
	_log.event("network", "connected", {"mode": net.mode, "peer": net.local_peer_id})
	if net.is_host():
		if not _room_players.has(net.local_peer_id):
			_add_local_room_player()
		_show_room()
	else:
		_send_to_host(CurlingConstants.CH_SYSTEM, {
			"type": "register",
			"v": CurlingConstants.PROTOCOL_VERSION,
			"nickname": _nickname(),
			"session_token": _session_token,
		})
		_send_to_host(CurlingConstants.CH_SYSTEM, {"type": "ping", "data": _network_clock.make_ping()})


func _on_net_connection_failed(reason: String) -> void:
	if reason.contains("nickname_in_use"):
		_handle_nickname_conflict()
	else:
		_set_lobby_status(reason)
		_show_screen("lobby")


func _on_net_disconnected(reason: String) -> void:
	_log.event("network", "disconnected", {"reason": reason})
	if _leaving_room:
		_finish_pending_room_exit()
		return
	_set_lobby_status(reason)
	if _public_role == "host":
		_clear_session_file()
	match_controller.reset_to_idle()
	_show_screen("lobby")


func _on_peer_left(peer_id: int) -> void:
	if not net.is_host() or not _room_players.has(peer_id):
		return
	if _room_started:
		var player: Dictionary = _room_players[peer_id]
		player["connected"] = false
		_room_players[peer_id] = player
		match_controller.set_player_connected(peer_id, false)
		_disconnect_deadlines[peer_id] = Time.get_unix_time_from_system() + CurlingConstants.RECONNECT_GRACE_SEC
	else:
		_room_players.erase(peer_id)
	_broadcast_room_state()


func _on_net_packet(channel: int, sender_peer_id: int, payload: PackedByteArray) -> void:
	if _leaving_room:
		if channel == CurlingConstants.CH_SYSTEM and sender_peer_id == net.host_peer_id:
			var leave_message := CurlingNet.decode_message(payload, 4096)
			if str(leave_message.get("type", "")) == "leave_ack":
				call_deferred("_finish_pending_room_exit")
		return
	if channel == CurlingConstants.CH_STONE_SNAPSHOT:
		if not net.is_host() and sender_peer_id == net.host_peer_id:
			match_controller.apply_remote_snapshot(payload)
		return
	var message := CurlingNet.decode_message(payload, 65536 if channel == CurlingConstants.CH_SYSTEM else 16384)
	if message.is_empty():
		return
	match channel:
		CurlingConstants.CH_SYSTEM: _handle_system_message(sender_peer_id, message)
		CurlingConstants.CH_CURSOR: _handle_cursor_message(sender_peer_id, message)
		CurlingConstants.CH_SWEEP: _handle_sweep_message(sender_peer_id, message)
		CurlingConstants.CH_AIM_PREVIEW: _handle_aim_message(sender_peer_id, message)
		CurlingConstants.CH_GAMEPLAY: _handle_gameplay_message(sender_peer_id, message)
		CurlingConstants.CH_CHAT: _handle_chat_message(sender_peer_id, message)


func _handle_system_message(sender: int, message: Dictionary) -> void:
	var type := str(message.get("type", ""))
	if net.is_host():
		match type:
			"register": _host_register_player(sender, message)
			"room_intent": _host_apply_room_intent(sender, message)
			"ping": _send_packet(CurlingConstants.CH_SYSTEM, sender, {"type": "pong", "data": _network_clock.make_pong(message.get("data", {}))})
			"leave": _host_remove_player(sender)
	else:
		if sender != net.host_peer_id:
			return
		match type:
			"room_state": _apply_room_state(message)
			"register_rejected": _on_registration_rejected(str(message.get("code", "join_rejected")))
			"match_state":
				if match_controller.apply_remote_state(message.get("state", {})):
					if match_controller.phase != CurlingMatchController.Phase.RESULT:
						_show_screen("match")
			"pong": _network_clock.accept_pong(message.get("data", {}))


func _handle_gameplay_message(sender: int, message: Dictionary) -> void:
	var type := str(message.get("type", ""))
	if net.is_host():
		match type:
			"lineup_toggle":
				if match_controller.toggle_lineup_slot(sender, int(message.get("slot", -1))): _broadcast_match_state()
			"tactics_confirm":
				if match_controller.set_tactics_confirmed(sender, bool(message.get("confirmed", true))): _broadcast_match_state()
			"throw":
				match_controller.host_apply_throw(sender, message.get("direction", Vector2.ZERO), float(message.get("power", 0.0)), float(message.get("spin", 0.0)))
	else:
		if sender != net.host_peer_id:
			return
		if type == "match_start":
			_room_started = true
			match_controller.start_match(message.get("players", []), int(message.get("ends", 1)), net.local_peer_id, false, int(message.get("seed", 1)))
			_show_screen("match")
		elif type == "authoritative_event":
			_on_gameplay_event(message.get("event", {}))


func _handle_aim_message(sender: int, message: Dictionary) -> void:
	if str(message.get("type", "")) != "aim":
		return
	if net.is_host():
		if sender != match_controller.active_thrower_id:
			return
		var direction_value: Variant = message.get("direction")
		var power := float(message.get("power", -1.0))
		var spin := float(message.get("spin", INF))
		if not direction_value is Vector2 or not (direction_value as Vector2).is_finite() or (direction_value as Vector2).length_squared() < 0.9 or power < 0.0 or power > 1.0 or absf(spin) > CurlingConstants.MAX_SPIN_RADPS + 0.001:
			return
		match_controller.show_aim_preview(direction_value as Vector2, power, spin)
		var forwarded := message.duplicate(true)
		forwarded["origin"] = sender
		_send_packet(CurlingConstants.CH_AIM_PREVIEW, 0, forwarded)
	elif sender == net.host_peer_id:
		match_controller.show_aim_preview(message.get("direction", Vector2.RIGHT), float(message.get("power", 0.0)), float(message.get("spin", 0.0)))


func _handle_sweep_message(sender: int, message: Dictionary) -> void:
	var type := str(message.get("type", ""))
	if net.is_host() and type == "sweep":
		match_controller.host_apply_sweep(sender, message.get("from", Vector2.ZERO), message.get("to", Vector2.ZERO), float(message.get("delta", 0.0)), int(message.get("host_ms", Time.get_ticks_msec())))
	elif not net.is_host() and sender == net.host_peer_id and type == "heat_segment":
		match_controller.heat_grid.apply_authoritative_segment(message.get("from", Vector2.ZERO), message.get("to", Vector2.ZERO), float(message.get("speed", 0.0)), _network_clock.host_to_local_time_ms(int(message.get("time_ms", Time.get_ticks_msec()))))
	elif not net.is_host() and sender == net.host_peer_id and type == "heat_sparse":
		match_controller.heat_grid.import_sparse(message.get("payload", PackedByteArray()), _network_clock.host_to_local_time_ms(int(message.get("time_ms", Time.get_ticks_msec()))))


func _handle_cursor_message(sender: int, message: Dictionary) -> void:
	var origin := int(message.get("origin", sender))
	if net.is_host() and sender != net.local_peer_id:
		var now_ms := Time.get_ticks_msec()
		if now_ms - int(_cursor_last_received_ms.get(sender, 0)) < 40:
			return
		var cursor_position: Variant = message.get("position")
		var context := str(message.get("context", ""))
		if not cursor_position is Vector2 or not (cursor_position as Vector2).is_finite() or not context in ["ui", "world"]:
			return
		if context == "ui" and (cursor_position as Vector2) != (cursor_position as Vector2).clamp(Vector2(-0.1, -0.1), Vector2(1.1, 1.1)):
			return
		if context == "world" and (absf((cursor_position as Vector2).x) > CurlingConstants.HALF_SHEET_LENGTH_PX + 500.0 or absf((cursor_position as Vector2).y) > CurlingConstants.HALF_SHEET_WIDTH_PX + 500.0):
			return
		_cursor_last_received_ms[sender] = now_ms
		var forwarded := message.duplicate(true)
		forwarded["origin"] = sender
		_send_packet(CurlingConstants.CH_CURSOR, 0, forwarded)
	_update_remote_cursor(origin, message)


func _handle_chat_message(sender: int, message: Dictionary) -> void:
	if net.is_host() and str(message.get("type", "")) == "chat_request":
		_host_accept_chat(sender, str(message.get("text", "")), bool(message.get("team_only", true)))
	elif str(message.get("type", "")) == "chat":
		_append_chat(message)


func _host_register_player(sender: int, message: Dictionary) -> void:
	if int(message.get("v", -1)) != CurlingConstants.PROTOCOL_VERSION:
		_reject_registration(sender, "protocol_mismatch")
		return
	var supplied_token := str(message.get("session_token", ""))
	var old_id := _find_disconnected_player_by_token(supplied_token)
	if old_id > 0:
		var restored: Dictionary = _room_players[old_id]
		_room_players.erase(old_id)
		restored["id"] = sender
		restored["connected"] = true
		_room_players[sender] = restored
		_disconnect_deadlines.erase(old_id)
		if match_controller.players.has(old_id):
			match_controller.remap_player_id(old_id, sender)
		_broadcast_room_state()
		if _room_started:
			_broadcast_match_state()
		return
	if _room_started:
		_reject_registration(sender, "room_started")
		return
	if _room_players.size() >= CurlingConstants.MAX_PLAYERS:
		_reject_registration(sender, "room_full")
		return
	var nickname := _sanitize_nickname(str(message.get("nickname", "")))
	if nickname.is_empty():
		_reject_registration(sender, "invalid_nickname")
		return
	if _nickname_exists(nickname):
		_reject_registration(sender, "nickname_in_use")
		return
	var team := _smaller_team()
	_room_players[sender] = {
		"id": sender,
		"nickname": nickname,
		"team": team,
		"join_order": _room_players.size(),
		"connected": true,
		"ready": false,
		"bot": false,
		"color": CurlingConstants.PLAYER_COLORS[_room_players.size() % CurlingConstants.PLAYER_COLORS.size()],
		"session_token": supplied_token,
	}
	_broadcast_room_state()


func _reject_registration(peer_id: int, code: String) -> void:
	_send_packet(CurlingConstants.CH_SYSTEM, peer_id, {"type": "register_rejected", "code": code})


func _on_registration_rejected(code: String) -> void:
	net.shutdown()
	if code == "nickname_in_use":
		_handle_nickname_conflict(_room_code)
		return
	_set_lobby_status("加入房间失败：%s" % _network_error_message(code))
	_show_screen("lobby")


func _host_apply_room_intent(sender: int, message: Dictionary) -> void:
	if _room_started or not _room_players.has(sender):
		return
	var player: Dictionary = _room_players[sender]
	match str(message.get("action", "")):
		"team":
			var requested := int(message.get("value", CurlingConstants.TEAM_NONE))
			if [CurlingConstants.TEAM_RED, CurlingConstants.TEAM_BLUE].has(requested) and _team_count(requested) < CurlingConstants.MAX_TEAM_PLAYERS:
				player["team"] = requested
				player["ready"] = false
		"ready":
			player["ready"] = not bool(player.get("ready", false))
	_room_players[sender] = player
	_broadcast_room_state()


func _host_remove_player(sender: int) -> void:
	if sender == net.host_peer_id:
		_leave_room()
		return
	# 主动退出使用应答后再由客户端断开，避免被误判为可重连的普通掉线。
	_send_packet(CurlingConstants.CH_SYSTEM, sender, {"type": "leave_ack"})
	if _room_started and _room_players.has(sender):
		var departed_team := int((_room_players[sender] as Dictionary).get("team", 0))
		match_controller.set_player_connected(sender, false)
		match_controller.remove_player(sender)
		_room_players.erase(sender)
		if _connected_team_count(departed_team) < CurlingConstants.MIN_TEAM_PLAYERS:
			match_controller.force_forfeit(CurlingConstants.other_team(departed_team), "队伍主动离开后已无人")
	else:
		_room_players.erase(sender)
	_broadcast_room_state()


func _request_room_intent(action: String, value: Variant) -> void:
	if _demo_mode:
		if action == "team":
			var player: Dictionary = _room_players[1]
			var requested_team := int(value)
			if int(player.get("team", CurlingConstants.TEAM_NONE)) == requested_team or _team_count(requested_team) < CurlingConstants.MAX_TEAM_PLAYERS:
				player["team"] = requested_team
				player["ready"] = false
				_room_players[1] = player
		elif action == "ready":
			var player: Dictionary = _room_players[1]
			player["ready"] = not bool(player.get("ready", false))
			_room_players[1] = player
		_refresh_room_ui()
	elif net.is_host():
		_host_apply_room_intent(net.local_peer_id, {"action": action, "value": value})
	else:
		_send_to_host(CurlingConstants.CH_SYSTEM, {"type": "room_intent", "action": action, "value": value})


func _on_ready_pressed() -> void:
	_request_room_intent("ready", true)


func _host_assign_selected_player(team: int) -> void:
	if not (_demo_mode or net.is_host()) or _room_started or host_assign_player.selected < 0:
		return
	var player_id := host_assign_player.get_item_id(host_assign_player.selected)
	if not _room_players.has(player_id):
		return
	var player: Dictionary = _room_players[player_id]
	var current_team := int(player.get("team", CurlingConstants.TEAM_NONE))
	if current_team != team and _team_count(team) >= CurlingConstants.MAX_TEAM_PLAYERS:
		room_status.text = "%s已满%d人" % [CurlingConstants.team_name(team), CurlingConstants.MAX_TEAM_PLAYERS]
		return
	player["team"] = team
	player["ready"] = false
	_room_players[player_id] = player
	if _demo_mode:
		_refresh_room_ui()
	else:
		_broadcast_room_state()


func _on_start_pressed() -> void:
	if not (_demo_mode or net.is_host()) or not _can_start_room():
		room_status.text = "需要2–8人、每队1–4人、人数差不超过1且全员准备"
		return
	_room_started = true
	var seed := int(Time.get_unix_time_from_system()) ^ Time.get_ticks_msec()
	var player_list := _room_player_list()
	if net.is_online():
		_send_packet(CurlingConstants.CH_GAMEPLAY, 0, {"type": "match_start", "players": player_list, "ends": _room_ends, "seed": seed})
	match_controller.start_match(player_list, _room_ends, 1 if _demo_mode else net.local_peer_id, true, seed)
	_show_screen("match")


func _on_tactics_slot_clicked(index: int, _position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if match_controller.authoritative:
		match_controller.toggle_lineup_slot(match_controller.local_player_id, index)
	else:
		_send_to_host(CurlingConstants.CH_GAMEPLAY, {"type": "lineup_toggle", "slot": index})


func _on_tactics_confirm_pressed() -> void:
	var local_id := match_controller.local_player_id
	var currently_confirmed := bool(match_controller.tactics_confirmed.get(local_id, false))
	if match_controller.authoritative:
		match_controller.set_tactics_confirmed(local_id, not currently_confirmed)
	else:
		_send_to_host(CurlingConstants.CH_GAMEPLAY, {"type": "tactics_confirm", "confirmed": not currently_confirmed})


func _on_local_aim_preview(direction: Vector2, power: float, spin: float) -> void:
	if net.is_online():
		if net.is_host():
			_send_packet(CurlingConstants.CH_AIM_PREVIEW, 0, {"type": "aim", "origin": net.local_peer_id, "direction": direction, "power": power, "spin": spin})
		else:
			_send_to_host(CurlingConstants.CH_AIM_PREVIEW, {"type": "aim", "direction": direction, "power": power, "spin": spin})


func _on_authoritative_heat_segment(from_world: Vector2, to_world: Vector2, speed_mps: float, sample_ms: int) -> void:
	if net.is_online() and net.is_host():
		_send_packet(CurlingConstants.CH_SWEEP, 0, {"type": "heat_segment", "from": from_world, "to": to_world, "speed": speed_mps, "time_ms": sample_ms})


func _on_match_state_changed() -> void:
	if match_controller.authoritative and net.is_online() and net.is_host():
		_broadcast_match_state()


func _broadcast_match_state() -> void:
	for peer_id_variant in _room_players.keys():
		var peer_id := int(peer_id_variant)
		if peer_id == net.local_peer_id:
			continue
		var team := int((_room_players[peer_id] as Dictionary).get("team", CurlingConstants.TEAM_NONE))
		_send_packet(CurlingConstants.CH_SYSTEM, peer_id, {"type": "match_state", "state": match_controller.export_state_for(team)})


func _on_match_hud_changed(data: Dictionary) -> void:
	score_label.text = "红 %d  —  %d 蓝" % [int(data.get("red_score", 0)), int(data.get("blue_score", 0))]
	end_label.text = "END %d / %d" % [int(data.get("end", 1)), int(data.get("scheduled_ends", 1))]
	timer_label.text = "%02d" % ceili(float(data.get("time", 0.0)))
	active_label.text = "%s · %s" % [str(data.get("phase_name", "")), str(data.get("active_player", ""))]
	team_status_label.text = "后手 %s  ·  本手 %s\n已投 %d / 16" % [CurlingConstants.team_name(int(data.get("hammer_team", 0))), CurlingConstants.team_name(int(data.get("active_team", 0))), int(data.get("delivered", 0))]
	power_bar.value = float(data.get("power", 0.0)) * 100.0
	spin_label.text = "力%.2f%% · 向%+0.02f° · 旋%+0.2frad/s" % [
		float(data.get("power", 0.0)) * 100.0,
		float(data.get("aim_offset_degrees", 0.0)),
		float(data.get("spin", 0.0)),
	]
	var phase_value := int(data.get("phase", CurlingMatchController.Phase.IDLE))
	_maybe_play_shot_clock_warning(data, phase_value)
	match phase_value:
		CurlingMatchController.Phase.TACTICS: instruction_label.text = "私密分配投壶位，确认后锁定"
		CurlingMatchController.Phase.AIMING: instruction_label.text = "推荐%d%% · 拖拽时 A/D方向 · W/S力度 · Shift慢调" % roundi(CurlingConstants.THROW_RECOMMENDED_POWER * 100.0)
		CurlingMatchController.Phase.MOVING: instruction_label.text = "镜头自动跟壶 · 壶上方显示预计剩余时间 · 左键快速擦冰"
		CurlingMatchController.Phase.SCORING: instruction_label.text = "测量距离并计算本End得分"
	_refresh_match_overlay_visibility(phase_value)
	audio.set_sweeping(_current_screen == "match" and bool(data.get("sweeping", false)), 0.7)


func _maybe_play_shot_clock_warning(data: Dictionary, phase_value: int) -> void:
	var remaining := float(data.get("time", 0.0))
	if _current_screen != "match" or phase_value != CurlingMatchController.Phase.AIMING or remaining <= 0.0:
		_reset_shot_clock_warning()
		return
	var shot_id := int(data.get("shot_id", -1))
	if shot_id != _last_shot_clock_warning_shot_id:
		_last_shot_clock_warning_shot_id = shot_id
		_last_shot_clock_warning_second = -1
	var remaining_second := ceili(remaining)
	if not SHOT_CLOCK_WARNING_SECONDS.has(remaining_second):
		return
	if remaining_second == _last_shot_clock_warning_second:
		return
	_last_shot_clock_warning_second = remaining_second
	audio.play_countdown(remaining_second <= 5)


func _reset_shot_clock_warning() -> void:
	_last_shot_clock_warning_shot_id = -1
	_last_shot_clock_warning_second = -1


func _on_gameplay_event(event: Dictionary) -> void:
	if net.is_online() and net.is_host():
		_send_packet(CurlingConstants.CH_GAMEPLAY, 0, {"type": "authoritative_event", "event": event})
	var type := str(event.get("type", ""))
	match type:
		"throw_launched":
			_last_gameplay_notice = "%s 已出手" % match_controller.player_name(int(event.get("player_id", 0)))
			audio.play_launch()
		"empty_throw": _last_gameplay_notice = str(event.get("reason", "空投"))
		"hog_violation": _last_gameplay_notice = "未越过hog line，冰壶移出场外"
		"free_guard_violation": _last_gameplay_notice = "五壶保护区违规，已恢复投壶前位置"
		"no_tick_violation": _last_gameplay_notice = "中线保护壶违规，已恢复投壶前位置"
		"end_scored":
			_last_gameplay_notice = "%s获得%d分" % [CurlingConstants.team_name(int(event.get("team", 0))), int(event.get("points", 0))]
			audio.play_score()
		"impact": audio.play_impact(float(event.get("speed", 0.0)))
	if not _last_gameplay_notice.is_empty():
		instruction_label.text = _last_gameplay_notice


func _on_match_finished(result: Dictionary) -> void:
	result_title.text = "%s获胜" % CurlingConstants.team_name(int(result.get("winner", 0)))
	result_score.text = "红队 %d  —  %d 蓝队" % [int(result.get("red_score", 0)), int(result.get("blue_score", 0))]
	if bool(result.get("forfeit", false)):
		result_score.text += "\n%s" % str(result.get("reason", "队伍判负"))
	_show_screen("result")


func _return_to_room_after_match() -> void:
	_room_started = false
	for player_id_variant in _room_players.keys():
		var player: Dictionary = _room_players[player_id_variant]
		player["ready"] = false if int(player_id_variant) == (1 if _demo_mode else net.local_peer_id) else bool(player.get("bot", false))
		_room_players[player_id_variant] = player
	_show_room()
	if net.is_online() and net.is_host():
		_broadcast_room_state()


func _leave_room() -> void:
	if _leaving_room:
		return
	if manual_panel.is_open():
		manual_panel.close_panel()
	if settings_panel.is_open():
		settings_panel.close_panel()
	var wait_for_host_ack := net.is_online() and not net.is_host()
	if net.is_online() and net.is_host() and net.mode == CurlingNet.Mode.PUBLIC and not _host_capability.is_empty():
		public_lobby.close_room(_room_code, _host_capability)
	if wait_for_host_ack:
		_leaving_room = true
		_leave_ack_deadline_ms = Time.get_ticks_msec() + LEAVE_ACK_TIMEOUT_MS
		_send_to_host(CurlingConstants.CH_SYSTEM, {"type": "leave"})
	else:
		net.shutdown()
	_clear_local_room_state_after_exit()
	_set_lobby_status("正在退出房间…" if wait_for_host_ack else "已退出房间")


func _clear_local_room_state_after_exit() -> void:
	lan_discovery.stop_advertising()
	lan_discovery.start_listening()
	_demo_mode = false
	_room_started = false
	_room_players.clear()
	_disconnect_deadlines.clear()
	_cursor_last_received_ms.clear()
	_chat_sent_ms.clear()
	_chat_messages.clear()
	chat_history.clear()
	_last_gameplay_notice = ""
	_clear_remote_cursors()
	match_controller.reset_to_idle()
	_reset_public_identity()
	_show_screen("lobby")


func _finish_pending_room_exit() -> void:
	if not _leaving_room:
		return
	_leaving_room = false
	_leave_ack_deadline_ms = 0
	net.shutdown()
	_set_lobby_status("已退出房间")


func _on_chat_submitted(text: String) -> void:
	chat_input.clear()
	var cleaned := text.strip_edges()
	if cleaned.is_empty() or cleaned.length() > 200:
		return
	if net.is_online():
		if net.is_host():
			_host_accept_chat(net.local_peer_id, cleaned, chat_channel.selected == 0)
		else:
			_send_to_host(CurlingConstants.CH_CHAT, {"type": "chat_request", "text": cleaned, "team_only": chat_channel.selected == 0})
	else:
		_append_chat({"type": "chat", "sender": 1, "nickname": _nickname(), "text": cleaned, "team_only": chat_channel.selected == 0})


func _host_accept_chat(sender: int, text: String, team_only: bool) -> void:
	var now_ms := Time.get_ticks_msec()
	var sender_times: Array = _chat_sent_ms.get(sender, [])
	sender_times = sender_times.filter(func(value: int) -> bool: return now_ms - value < 2000)
	if sender_times.size() >= 4 or text.length() > 200 or not _room_players.has(sender):
		return
	sender_times.append(now_ms)
	_chat_sent_ms[sender] = sender_times
	var sender_player: Dictionary = _room_players[sender]
	var message := {"type": "chat", "sender": sender, "nickname": sender_player.get("nickname", "玩家"), "text": text, "team_only": team_only, "team": sender_player.get("team", 0)}
	_append_chat(message)
	for peer_id_variant in _room_players.keys():
		var peer_id := int(peer_id_variant)
		if peer_id == net.local_peer_id:
			continue
		if not team_only or int((_room_players[peer_id] as Dictionary).get("team", 0)) == int(sender_player.get("team", 0)):
			_send_packet(CurlingConstants.CH_CHAT, peer_id, message)


func _append_chat(message: Dictionary) -> void:
	_chat_messages.append(message.duplicate(true))
	if _chat_messages.size() > 100:
		_chat_messages.pop_front()
	chat_history.append_text("[%s] %s\n" % [str(message.get("nickname", "玩家")), str(message.get("text", ""))])
	chat_history.scroll_to_line(maxi(0, chat_history.get_line_count() - 1))


func _send_cursor() -> void:
	if not net.is_online():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse_screen := get_viewport().get_mouse_position()
	var in_match := match_controller.visible and match_controller.phase not in [CurlingMatchController.Phase.IDLE, CurlingMatchController.Phase.RESULT]
	var message := {
		"type": "cursor",
		"context": "world" if in_match else "ui",
		"position": match_controller.get_global_mouse_position() if in_match else Vector2(mouse_screen.x / maxf(viewport_size.x, 1.0), mouse_screen.y / maxf(viewport_size.y, 1.0)),
		"pressed": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		"sweeping": in_match and match_controller.phase == CurlingMatchController.Phase.MOVING and match_controller.get_local_team() == match_controller.active_team,
	}
	if net.is_host():
		message["origin"] = net.local_peer_id
		_send_packet(CurlingConstants.CH_CURSOR, 0, message)
	else:
		_send_to_host(CurlingConstants.CH_CURSOR, message)


func _update_remote_cursor(player_id: int, message: Dictionary) -> void:
	if player_id == (1 if _demo_mode else net.local_peer_id) or not _room_players.has(player_id):
		return
	var cursor := _cursor_for_player(player_id)
	if cursor == null:
		return
	var raw_position: Vector2 = message.get("position", Vector2.ZERO)
	var screen_position := Vector2.ZERO
	if str(message.get("context", "ui")) == "world":
		screen_position = get_viewport().get_canvas_transform() * raw_position
	else:
		screen_position = raw_position * get_viewport().get_visible_rect().size
	cursor.set_target(screen_position, bool(message.get("pressed", false)), bool(message.get("sweeping", false)))


func _cursor_for_player(player_id: int) -> CurlingRemoteCursor:
	if _cursor_by_player.has(player_id):
		return _cursor_by_player[player_id] as CurlingRemoteCursor
	for cursor in _remote_cursors:
		if cursor.player_id == 0:
			cursor.configure(_room_players[player_id])
			_cursor_by_player[player_id] = cursor
			return cursor
	return null


func _sync_remote_cursor_identities() -> void:
	for player_id_variant in _cursor_by_player.keys():
		var player_id := int(player_id_variant)
		var cursor := _cursor_by_player[player_id] as CurlingRemoteCursor
		if _room_players.has(player_id):
			cursor.configure(_room_players[player_id])
		else:
			cursor.clear_identity()
			_cursor_by_player.erase(player_id)


func _clear_remote_cursors() -> void:
	_cursor_by_player.clear()
	for cursor in _remote_cursors:
		cursor.clear_identity()


func _on_lan_rooms_changed(rooms: Array[Dictionary]) -> void:
	_lan_rooms = rooms
	if rooms.is_empty():
		return
	var first := rooms[0]
	address_input.text = str(first.get("address", "127.0.0.1"))
	_set_lobby_status("发现LAN房间：%s" % str(first.get("name", "未命名")))


func _on_public_request_completed(action: String, ok: bool, data: Dictionary) -> void:
	if action == "heartbeat":
		return
	if not ok:
		var detail := str(data.get("detail", "unknown_error"))
		if detail == "nickname_in_use":
			_handle_nickname_conflict(room_code_input.text.strip_edges().to_upper() if action == "join" else "")
			return
		_set_lobby_status("公网请求失败：%s" % _network_error_message(detail))
		return
	if action == "list":
		_public_room_rows.clear()
		public_rooms.clear()
		for room_variant in data.get("rooms", []):
			var room := room_variant as Dictionary
			_public_room_rows.append(room)
			public_rooms.add_item("%s   %s   %d/%d   %d End" % [room.get("name", "房间"), room.get("code", "------"), room.get("players", 0), CurlingConstants.MAX_PLAYERS, room.get("ends", 1)])
		_set_lobby_status("公网房间列表已更新")
		return
	if action in ["create", "join", "matchmake", "resume"]:
		_room_code = str(data.get("code", ""))
		_room_ends = int(data.get("ends", 1))
		_host_capability = str(data.get("host_capability", ""))
		_session_token = str(data.get("session_token", ""))
		_public_player_id = str(data.get("player_id", ""))
		_public_role = str(data.get("role", "member"))
		if data.has("nickname"):
			nickname_input.text = str(data.get("nickname", nickname_input.text))
			username_input.text = nickname_input.text
			_update_lobby_identity()
		_store_session_file()
		resume_button.visible = false
		_resume_payload.clear()
		var relay_host := str(data.get("relay_host", "47.123.6.127"))
		var relay_port := int(data.get("relay_port", 0))
		var error := net.connect_public(relay_host, relay_port, str(data.get("ticket", "")), _nickname())
		if error != OK:
			_set_lobby_status("Relay连接初始化失败：%s" % error_string(error))


func _add_local_room_player() -> void:
	var player_id := net.local_peer_id
	_room_players[player_id] = {
		"id": player_id,
		"nickname": _nickname(),
		"team": CurlingConstants.TEAM_RED,
		"join_order": 0,
		"connected": true,
		"ready": false,
		"bot": false,
		"color": CurlingConstants.PLAYER_COLORS[0],
		"session_token": _session_token,
	}


func _broadcast_room_state() -> void:
	_sync_remote_cursor_identities()
	_refresh_room_ui()
	if net.mode == CurlingNet.Mode.LAN_HOST:
		lan_discovery.update_advertisement({"players": _room_players.size(), "phase": _phase_wire_name()})
	if net.is_online() and net.is_host():
		var public_players := {}
		for player_id_variant in _room_players:
			public_players[player_id_variant] = _public_player_copy(_room_players[player_id_variant])
		_send_packet(CurlingConstants.CH_SYSTEM, 0, {"type": "room_state", "code": _room_code, "ends": _room_ends, "players": public_players, "started": _room_started})


func _apply_room_state(message: Dictionary) -> void:
	_room_code = str(message.get("code", _room_code))
	_room_ends = int(message.get("ends", _room_ends))
	_room_players = message.get("players", {}).duplicate(true)
	_sync_remote_cursor_identities()
	_room_started = bool(message.get("started", false))
	if _room_started:
		if match_controller.authoritative or match_controller.phase in [CurlingMatchController.Phase.IDLE, CurlingMatchController.Phase.RESULT]:
			match_controller.start_match(_room_player_list(), _room_ends, net.local_peer_id, false, 0)
		_show_screen("match")
	else:
		_show_room()


func _show_room() -> void:
	match_controller.reset_to_idle()
	_show_screen("room")
	_refresh_room_ui()


func _refresh_room_ui() -> void:
	room_title.text = "%s · %s · %d End" % ["自动化测试" if _demo_mode else "房间", _room_code, _room_ends]
	red_roster.text = _team_roster_text(CurlingConstants.TEAM_RED)
	blue_roster.text = _team_roster_text(CurlingConstants.TEAM_BLUE)
	var local_id := 1 if _demo_mode else net.local_peer_id
	var local_player: Dictionary = _room_players.get(local_id, {})
	ready_button.text = "取消准备" if bool(local_player.get("ready", false)) else "准备"
	start_button.visible = _demo_mode or net.is_host()
	start_button.disabled = not _can_start_room()
	host_assign.visible = _demo_mode or net.is_host()
	if host_assign.visible:
		var selected_id := host_assign_player.get_item_id(host_assign_player.selected) if host_assign_player.selected >= 0 else -1
		host_assign_player.clear()
		for player in _room_player_list():
			host_assign_player.add_item(str(player.get("nickname", "玩家")), int(player.get("id", 0)))
		var selected_index := host_assign_player.get_item_index(selected_id)
		if selected_index >= 0:
			host_assign_player.select(selected_index)
	room_status.text = "%d/%d 玩家 · 每队1–4人且人数差≤1 · %s" % [_room_players.size(), CurlingConstants.MAX_PLAYERS, "可以开始" if _can_start_room() else "等待准备"]


func _update_tactics_ui() -> void:
	if not tactics_screen.visible or match_controller.phase != CurlingMatchController.Phase.TACTICS:
		return
	tactics_title.text = "第%d End · %s投壶安排" % [match_controller.current_end + 1, CurlingConstants.team_name(match_controller.get_local_team())]
	tactics_timer.text = "%03d 秒" % ceili(match_controller.phase_time_remaining)
	var local_team := match_controller.get_local_team()
	var lineup: Array = match_controller.lineups.get(local_team, [])
	if tactics_slots.item_count != CurlingConstants.STONES_PER_TEAM:
		tactics_slots.clear()
		for slot in range(CurlingConstants.STONES_PER_TEAM): tactics_slots.add_item("第%d壶" % (slot + 1))
	for slot in range(mini(lineup.size(), CurlingConstants.STONES_PER_TEAM)):
		var owner := int(lineup[slot])
		var owner_name := "空位（锁定时自动补位）" if owner == 0 else match_controller.player_name(owner)
		tactics_slots.set_item_text(slot, "第%d壶   %s" % [slot + 1, owner_name])
	var confirmed := bool(match_controller.tactics_confirmed.get(match_controller.local_player_id, false))
	tactics_confirm.text = "取消确认" if confirmed else "确认本队安排"


func _refresh_match_overlay_visibility(phase_value: int) -> void:
	# HUD 信号可能晚于退出/切屏到达；可见性必须同时服从当前顶层画面。
	var match_screen_active := _current_screen == "match"
	tactics_screen.visible = match_screen_active and phase_value == CurlingMatchController.Phase.TACTICS
	match_hud.visible = match_screen_active and phase_value in [
		CurlingMatchController.Phase.AIMING,
		CurlingMatchController.Phase.MOVING,
		CurlingMatchController.Phase.SCORING,
	]


func _show_screen(name: String) -> void:
	var previous_screen := _current_screen
	_current_screen = name
	username_screen.visible = name == "username"
	lobby_screen.visible = name == "lobby"
	room_screen.visible = name == "room"
	result_screen.visible = name == "result"
	match_controller.visible = name in ["match", "result"]
	_refresh_match_overlay_visibility(match_controller.phase)
	if not previous_screen.is_empty() and previous_screen != name:
		audio.play_ui()


func _open_settings() -> void:
	if manual_panel.is_open():
		manual_panel.close_panel()
	if not settings_panel.is_open():
		settings_panel.open_panel()


func _on_settings_opened() -> void:
	_refresh_modal_input_lock()


func _on_settings_closed() -> void:
	_refresh_modal_input_lock()


func _toggle_manual() -> void:
	if manual_panel.is_open():
		manual_panel.close_panel()
	else:
		_open_manual()


func _open_manual() -> void:
	if settings_panel.is_open():
		settings_panel.close_panel()
	if not manual_panel.is_open():
		manual_panel.open_panel()


func _on_manual_opened() -> void:
	_refresh_modal_input_lock()


func _on_manual_closed() -> void:
	_refresh_modal_input_lock()


func _refresh_modal_input_lock() -> void:
	# 弹层只锁住本机操作；权威计时、物理和网络同步继续运行。
	match_controller.set_local_input_locked(settings_panel.is_open() or manual_panel.is_open())


func _on_reduced_motion_changed(enabled: bool) -> void:
	match_controller.reduced_motion = enabled


func _send_to_host(channel: int, message: Dictionary) -> void:
	if net.is_online():
		net.send_to_host(channel, CurlingNet.encode_message(message))


func _send_packet(channel: int, target: int, message: Dictionary) -> void:
	if net.is_online():
		net.send_packet(channel, target, CurlingNet.encode_message(message))


func _can_start_room() -> bool:
	if not CurlingConstants.is_valid_team_distribution(
		_team_count(CurlingConstants.TEAM_RED),
		_team_count(CurlingConstants.TEAM_BLUE)
	):
		return false
	for player_variant in _room_players.values():
		if not bool((player_variant as Dictionary).get("ready", false)):
			return false
	return true


func _team_count(team: int) -> int:
	var count := 0
	for player_variant in _room_players.values():
		if int((player_variant as Dictionary).get("team", 0)) == team:
			count += 1
	return count


func _smaller_team() -> int:
	return CurlingConstants.TEAM_RED if _team_count(CurlingConstants.TEAM_RED) <= _team_count(CurlingConstants.TEAM_BLUE) else CurlingConstants.TEAM_BLUE


func _team_roster_text(team: int) -> String:
	var lines: PackedStringArray = []
	for player_variant in _room_players.values():
		var player := player_variant as Dictionary
		if int(player.get("team", 0)) != team:
			continue
		lines.append("%s  %s%s" % ["●" if bool(player.get("connected", true)) else "○", player.get("nickname", "玩家"), "  已准备" if bool(player.get("ready", false)) else ""])
	return "\n".join(lines) if not lines.is_empty() else "等待队员"


func _room_player_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for player_variant in _room_players.values(): result.append(_public_player_copy(player_variant as Dictionary))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("join_order", 0)) < int(b.get("join_order", 0)))
	return result


func _public_player_copy(player: Dictionary) -> Dictionary:
	var copy := player.duplicate(true)
	copy.erase("session_token")
	return copy


func _room_roster_for_api() -> Array:
	var result := []
	for player_variant in _room_players.values():
		var player := player_variant as Dictionary
		result.append({"id": str(player.get("id", "")), "nickname": str(player.get("nickname", "")), "connected": bool(player.get("connected", true))})
	return result


func _phase_wire_name() -> String:
	return "playing" if _room_started else "waiting"


func _nickname() -> String:
	return _sanitize_nickname(nickname_input.text)


func _sanitize_nickname(value: String) -> String:
	var trimmed := value.strip_edges()
	if trimmed.length() < 2 or trimmed.length() > 16:
		return ""
	for index in range(trimmed.length()):
		if trimmed.unicode_at(index) < 32:
			return ""
	return trimmed


func _network_error_message(code: String) -> String:
	match code:
		"nickname_in_use":
			return "用户名已被占用"
		"invalid_nickname":
			return "用户名格式无效"
		"room_full":
			return "房间已满"
		"room_started":
			return "比赛已经开始"
		"room_not_found":
			return "房间不存在或已经关闭"
		"protocol_mismatch":
			return "客户端协议版本不一致"
		"port_exhausted":
			return "测试服暂时没有可用Relay端口"
		_:
			return code if not code.is_empty() and code != "unknown_error" else "未知错误"


func _handle_nickname_conflict(requested_code: String = "") -> void:
	var resume_code := str(_resume_payload.get("code", ""))
	var resume_nickname := _sanitize_nickname(str(_resume_payload.get("nickname", "")))
	if (
		not resume_code.is_empty()
		and resume_nickname == _nickname()
		and (requested_code.is_empty() or requested_code == resume_code)
	):
		_show_screen("lobby")
		_set_lobby_status("该名字有可恢复会话，请点击“恢复 %s”；若不是你的会话，请更改用户名" % resume_code)
		return
	_show_username_entry("这个房间已有同名玩家，请换一个名字后重试")


func _nickname_exists(value: String) -> bool:
	for player_variant in _room_players.values():
		if str((player_variant as Dictionary).get("nickname", "")).to_lower() == value.to_lower(): return true
	return false


func _selected_ends() -> int:
	return ends_option.get_item_id(ends_option.selected)


func _random_room_code() -> String:
	const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var result := ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _index in range(6): result += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
	return result


func _save_nickname() -> void:
	settings.set_player_nickname(_nickname())


func _load_saved_nickname() -> String:
	return settings.get_player_nickname()


func _store_session_file() -> void:
	if _session_token.is_empty(): return
	var file := FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"code": _room_code,
			"player_id": _public_player_id,
			"session_token": _session_token,
			"nickname": _nickname(),
			"expires_unix": Time.get_unix_time_from_system() + CurlingConstants.RECONNECT_GRACE_SEC,
		}))


func _load_session_offer() -> void:
	resume_button.visible = false
	_resume_payload.clear()
	if not FileAccess.file_exists(SESSION_FILE):
		return
	var file := FileAccess.open(SESSION_FILE, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_clear_session_file()
		return
	var payload := parsed as Dictionary
	if (
		float(payload.get("expires_unix", 0.0)) <= Time.get_unix_time_from_system()
		or str(payload.get("code", "")).length() != 6
		or str(payload.get("player_id", "")).is_empty()
		or str(payload.get("session_token", "")).length() != 64
	):
		_clear_session_file()
		return
	_resume_payload = payload
	resume_button.visible = true
	resume_button.text = "恢复 %s" % str(payload.get("code", ""))
	_set_lobby_status("检测到90秒内可恢复的公网对局")


func _on_resume_pressed() -> void:
	if _resume_payload.is_empty():
		_load_session_offer()
		return
	_room_code = str(_resume_payload.get("code", ""))
	_public_player_id = str(_resume_payload.get("player_id", ""))
	_session_token = str(_resume_payload.get("session_token", ""))
	nickname_input.text = str(_resume_payload.get("nickname", nickname_input.text))
	username_input.text = nickname_input.text
	_update_lobby_identity()
	_set_lobby_status("正在申请重连票据…")
	public_lobby.resume_room(_room_code, _public_player_id, _session_token)


func _clear_session_file() -> void:
	if FileAccess.file_exists(SESSION_FILE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))
	_resume_payload.clear()
	if is_instance_valid(resume_button):
		resume_button.visible = false


func _ensure_local_session_token() -> void:
	if not _session_token.is_empty():
		return
	var crypto := Crypto.new()
	_session_token = crypto.generate_random_bytes(32).hex_encode()


func _reset_public_identity() -> void:
	_clear_session_file()
	_host_capability = ""
	_public_player_id = ""
	_public_role = ""
	_session_token = ""
	_ensure_local_session_token()


func _find_disconnected_player_by_token(token: String) -> int:
	if token.length() != 64:
		return 0
	for player_id_variant in _room_players.keys():
		var player_id := int(player_id_variant)
		var player: Dictionary = _room_players[player_id]
		if not bool(player.get("connected", true)) and str(player.get("session_token", "")) == token:
			return player_id
	return 0


func _process_disconnect_grace() -> void:
	if not net.is_host() or _disconnect_deadlines.is_empty():
		return
	var now_unix := Time.get_unix_time_from_system()
	for player_id_variant in _disconnect_deadlines.keys():
		var player_id := int(player_id_variant)
		if now_unix < float(_disconnect_deadlines[player_id]):
			continue
		_disconnect_deadlines.erase(player_id)
		if not _room_players.has(player_id):
			continue
		var team := int((_room_players[player_id] as Dictionary).get("team", 0))
		_room_players.erase(player_id)
		if match_controller.players.has(player_id):
			match_controller.remove_player(player_id)
		if _room_started and _connected_team_count(team) < CurlingConstants.MIN_TEAM_PLAYERS:
			match_controller.force_forfeit(CurlingConstants.other_team(team), "断线90秒后队伍已无人")
		_broadcast_room_state()


func _connected_team_count(team: int) -> int:
	var count := 0
	for player_variant in _room_players.values():
		var player := player_variant as Dictionary
		if int(player.get("team", 0)) == team and bool(player.get("connected", true)):
			count += 1
	return count


func _set_lobby_status(text: String) -> void:
	lobby_status.text = text


func _update_diagnostics() -> void:
	if not _debug_enabled: return
	diagnostics.text = "CURLING DIAGNOSTICS\n模式 %s  Peer %d  Host %d\nRTT %.1fms  抖动 %.1fms  时钟偏移 %.1fms\n弱网 %s\n状态 %s  Seq %d  Shot %d\n热单元 %d  最近事件 %s" % [CurlingNet.Mode.keys()[net.mode], net.local_peer_id, net.host_peer_id, _network_clock.rtt_ms, _network_clock.jitter_ms, _network_clock.offset_ms, net.development_impairment_label(), match_controller.get_phase_name(), match_controller.state_sequence, match_controller.shot_id, match_controller.heat_grid.active_cell_count(), _last_gameplay_notice]
