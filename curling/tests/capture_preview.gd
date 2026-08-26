extends Node

@onready var curling: CurlingApp = $Curling

var _output_path := ""
var _screen := "lobby"
var _player_count := CurlingConstants.MAX_PLAYERS


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--curling-capture="):
			_output_path = argument.trim_prefix("--curling-capture=")
		elif argument.begins_with("--curling-capture-screen="):
			_screen = argument.trim_prefix("--curling-capture-screen=")
		elif argument.begins_with("--curling-capture-players="):
			_player_count = clampi(
				int(argument.trim_prefix("--curling-capture-players=")),
				CurlingConstants.MIN_PLAYERS,
				CurlingConstants.MAX_PLAYERS
			)
	if _output_path.is_empty():
		push_error("capture_preview requires --curling-capture=ABSOLUTE_PATH")
		get_tree().quit(2)
		return
	await get_tree().process_frame
	if _screen in ["room", "tactics", "match"]:
		curling._on_demo_pressed()
		_set_demo_player_count()
	if _screen in ["tactics", "match"]:
		curling._on_start_pressed()
	if _screen == "match":
		curling.match_controller.set_tactics_confirmed(1, true)
		for _frame in range(55):
			await get_tree().process_frame
	if _screen == "settings":
		curling._open_settings()
		if not curling.settings_panel.is_open() or not curling.match_controller.local_input_locked:
			push_error("settings panel must lock only local match input while open")
			get_tree().quit(5)
			return
		curling.settings_panel.close_panel()
		if curling.match_controller.local_input_locked:
			push_error("closing settings panel must restore local match input")
			get_tree().quit(6)
			return
		curling._open_settings()
	for _frame in range(4):
		await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		push_error("capture requires a rendering display driver; do not use --headless")
		get_tree().quit(4)
		return
	var error := image.save_png(_output_path)
	if error != OK:
		push_error("capture failed: %s" % error_string(error))
		get_tree().quit(3)
		return
	print("CURLING_CAPTURE_OK %s" % _output_path)
	get_tree().quit(0)


func _set_demo_player_count() -> void:
	for player_id in range(CurlingConstants.MAX_PLAYERS, _player_count, -1):
		curling._room_players.erase(player_id)
	for index in range(_player_count):
		var player_id := index + 1
		var player: Dictionary = curling._room_players[player_id]
		player["team"] = CurlingConstants.TEAM_RED if index % 2 == 0 else CurlingConstants.TEAM_BLUE
		curling._room_players[player_id] = player
	curling._refresh_room_ui()
