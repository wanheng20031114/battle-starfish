extends Control

const CURLING_SCENE := "res://curling/curling.tscn"
const ARCHIVED_TEST_EXECUTABLE := "res://backup/3d-camera-demo/build/BattleStarfish.exe"
const CurlingSettingsScript := preload("res://curling/settings/curling_settings.gd")
const CurlingSettingsPanelScript := preload("res://curling/settings/curling_settings_panel.gd")

@onready var settings: CurlingSettingsScript = $CurlingSettings
@onready var starfield: Node2D = $Starfield
@onready var content: VBoxContainer = $Content
@onready var test_scene_button: Button = $Content/Menu/TestSceneButton
@onready var multiplayer_button: Button = $Content/Menu/MultiplayerButton
@onready var settings_button: Button = $Content/Menu/SettingsButton
@onready var quit_button: Button = $Content/Menu/QuitButton
@onready var status_label: Label = $Content/StatusLabel
@onready var settings_panel: CurlingSettingsPanelScript = $SettingsPanel

var _button_tweens: Dictionary = {}
var _intro_tween: Tween
var _content_rest_position := Vector2.ZERO
var _content_layout_ready := false


func _ready() -> void:
	var active_buttons: Array[Button] = [
		test_scene_button,
		multiplayer_button,
		settings_button,
		quit_button,
	]
	for button in active_buttons:
		button.mouse_entered.connect(_on_button_emphasized.bind(button))
		button.mouse_exited.connect(_on_button_released.bind(button))
		button.focus_entered.connect(_on_button_emphasized.bind(button))
		button.focus_exited.connect(_on_button_released.bind(button))

	settings.reduced_motion_changed.connect(_on_reduced_motion_changed)
	settings_panel.closed.connect(_on_settings_closed)
	_on_reduced_motion_changed(settings.is_reduced_motion_enabled())
	multiplayer_button.grab_focus()
	call_deferred("_start_intro")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and settings_panel.is_open():
		settings_panel.close_panel()
		get_viewport().set_input_as_handled()


func _start_intro() -> void:
	_content_rest_position = content.position
	_content_layout_ready = true
	if settings.is_reduced_motion_enabled():
		content.modulate = Color.WHITE
		return

	content.position = _content_rest_position + Vector2(-18.0, 0.0)
	content.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(content, "position", _content_rest_position, 0.55)
	_intro_tween.tween_property(content, "modulate", Color.WHITE, 0.42)


func _on_button_emphasized(button: Button) -> void:
	_animate_button(button, 1.018)


func _on_button_released(button: Button) -> void:
	_animate_button(button, 1.0)


func _animate_button(button: Button, target_scale: float) -> void:
	if settings.is_reduced_motion_enabled():
		button.scale = Vector2.ONE
		return
	if _button_tweens.has(button):
		(_button_tweens[button] as Tween).kill()
	button.pivot_offset = Vector2(0.0, button.size.y * 0.5)
	var tween := create_tween()
	_button_tweens[button] = tween
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * target_scale, 0.12)


func _on_test_scene_pressed() -> void:
	if OS.get_name() != "Windows":
		_set_status("归档测试场景目前仅提供 Windows 可执行文件。", true)
		return
	var executable_path := ProjectSettings.globalize_path(ARCHIVED_TEST_EXECUTABLE)
	if not FileAccess.file_exists(executable_path):
		_set_status("未找到 backup 中的归档测试程序。", true)
		return
	var process_id := OS.create_process(executable_path, PackedStringArray())
	if process_id <= 0:
		_set_status("归档测试场景启动失败。", true)
		return
	_set_status("归档测试场景已在独立窗口启动。")


func _on_multiplayer_pressed() -> void:
	var error := get_tree().change_scene_to_file(CURLING_SCENE)
	if error != OK:
		_set_status("多人游戏载入失败：%s" % error_string(error), true)


func _on_settings_pressed() -> void:
	if not settings_panel.is_open():
		settings_panel.open_panel()


func _on_quit_pressed() -> void:
	settings.flush_pending_save()
	get_tree().quit()


func _on_settings_closed() -> void:
	settings_button.grab_focus()


func _on_reduced_motion_changed(enabled: bool) -> void:
	starfield.process_mode = Node.PROCESS_MODE_DISABLED if enabled else Node.PROCESS_MODE_INHERIT
	if enabled and _content_layout_ready:
		if _intro_tween != null and _intro_tween.is_valid():
			_intro_tween.kill()
		content.position = _content_rest_position
		content.modulate = Color.WHITE
		for button in [test_scene_button, multiplayer_button, settings_button, quit_button]:
			button.scale = Vector2.ONE


func _set_status(message: String, is_error := false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.55, 0.08, 0.06, 1.0) if is_error else Color(0.025, 0.18, 0.28, 0.92)
	)
