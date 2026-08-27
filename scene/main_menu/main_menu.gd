extends Control

const CURLING_SCENE := "res://curling/curling.tscn"
const TEST_SCENE := "res://scene/test/test.tscn"
const CurlingSettingsScript := preload("res://curling/settings/curling_settings.gd")
const CurlingSettingsPanelScript := preload("res://curling/settings/curling_settings_panel.gd")
const INTRO_BUTTON_OFFSET_Y := 52.0
const INTRO_BUTTON_DURATION := 0.32
const INTRO_BUTTON_STAGGER := 0.055

@onready var settings: CurlingSettingsScript = $CurlingSettings
@onready var seabed_starfish: Node2D = $SeabedStarfish
@onready var content: VBoxContainer = $Content
@onready var single_player_button: Button = $Content/Menu/SinglePlayerSlot/SinglePlayerButton
@onready var test_scene_button: Button = $Content/Menu/TestSceneSlot/TestSceneButton
@onready var curling_button: Button = $Content/Menu/CurlingSlot/CurlingButton
@onready var settings_button: Button = $Content/Menu/SettingsSlot/SettingsButton
@onready var quit_button: Button = $Content/Menu/QuitSlot/QuitButton
@onready var status_label: Label = $Content/StatusLabel
@onready var settings_panel: CurlingSettingsPanelScript = $SettingsPanel

var _button_tweens: Dictionary = {}
var _menu_buttons: Array[Button] = []
var _button_rest_positions: Dictionary = {}
var _intro_tween: Tween
var _content_rest_position := Vector2.ZERO
var _content_layout_ready := false
var _intro_running := false


func _ready() -> void:
	_menu_buttons = [
		single_player_button,
		test_scene_button,
		curling_button,
		settings_button,
		quit_button,
	]
	for button in _menu_buttons:
		if button.disabled:
			continue
		button.mouse_entered.connect(_on_button_emphasized.bind(button))
		button.mouse_exited.connect(_on_button_released.bind(button))
		button.focus_entered.connect(_on_button_emphasized.bind(button))
		button.focus_exited.connect(_on_button_released.bind(button))

	settings.reduced_motion_changed.connect(_on_reduced_motion_changed)
	_on_reduced_motion_changed(settings.is_reduced_motion_enabled())
	call_deferred("_start_intro")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and settings_panel.is_open():
		settings_panel.close_panel()
		get_viewport().set_input_as_handled()


func _start_intro() -> void:
	_content_rest_position = content.position
	_content_layout_ready = true
	if settings.is_reduced_motion_enabled():
		_reset_intro_visuals()
		return

	_intro_running = true
	content.position = _content_rest_position + Vector2(-18.0, 0.0)
	content.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.tween_property(content, "position", _content_rest_position, 0.48).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(content, "modulate", Color.WHITE, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	for index in _menu_buttons.size():
		var button := _menu_buttons[index]
		var delay := index * INTRO_BUTTON_STAGGER
		var rest_position := button.position
		_button_rest_positions[button] = rest_position
		button.pivot_offset = Vector2(0.0, button.size.y)
		button.position.y += INTRO_BUTTON_OFFSET_Y
		button.scale = Vector2(0.97, 0.88)
		button.modulate.a = 0.0
		_intro_tween.tween_property(button, "position:y", rest_position.y, INTRO_BUTTON_DURATION).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_intro_tween.tween_property(button, "scale", Vector2.ONE, INTRO_BUTTON_DURATION).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_intro_tween.tween_property(button, "modulate:a", 1.0, 0.13).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_intro_tween.finished.connect(_finish_intro)


func _finish_intro() -> void:
	_intro_tween = null
	_intro_running = false
	_reset_intro_visuals()


func _reset_intro_visuals() -> void:
	content.position = _content_rest_position
	content.modulate = Color.WHITE
	for button in _menu_buttons:
		if _button_rest_positions.has(button):
			var rest_position: Vector2 = _button_rest_positions[button]
			button.position = rest_position
		button.scale = Vector2.ONE
		button.modulate.a = 1.0


func _on_button_emphasized(button: Button) -> void:
	if _intro_running:
		return
	_animate_button(button, 1.018)


func _on_button_released(button: Button) -> void:
	if _intro_running:
		return
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
	var error := get_tree().change_scene_to_file(TEST_SCENE)
	if error != OK:
		_set_status("测试场景载入失败：%s" % error_string(error), true)


func _on_curling_pressed() -> void:
	var error := get_tree().change_scene_to_file(CURLING_SCENE)
	if error != OK:
		_set_status("冰壶载入失败：%s" % error_string(error), true)


func _on_settings_pressed() -> void:
	if not settings_panel.is_open():
		settings_panel.open_panel()


func _on_quit_pressed() -> void:
	settings.flush_pending_save()
	get_tree().quit()


func _on_reduced_motion_changed(enabled: bool) -> void:
	seabed_starfish.process_mode = Node.PROCESS_MODE_DISABLED if enabled else Node.PROCESS_MODE_INHERIT
	if enabled and _content_layout_ready:
		if _intro_tween != null and _intro_tween.is_valid():
			_intro_tween.kill()
		_intro_tween = null
		_intro_running = false
		_reset_intro_visuals()


func _set_status(message: String, is_error := false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.55, 0.08, 0.06, 1.0) if is_error else Color(0.025, 0.18, 0.28, 0.92)
	)
