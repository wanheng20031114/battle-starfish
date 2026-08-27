extends Control
class_name CurlingSettingsPanel

signal opened
signal closed

const CurlingSettingsScript := preload("res://curling/settings/curling_settings.gd")

@export var settings_path: NodePath

@onready var resolution_option: OptionButton = _resolve_control([
	"Center/Panel/Margin/Layout/BodyScroll/BodyInsets/BodyContent/Display/Rows/ContentMargin/Content/ResolutionRow/Resolution",
	"Center/Panel/Margin/Layout/Display/ResolutionRow/Resolution",
]) as OptionButton
@onready var fullscreen_check: CheckButton = _resolve_control([
	"Center/Panel/Margin/Layout/BodyScroll/BodyInsets/BodyContent/Display/Rows/ContentMargin/Content/FullscreenRow/Fullscreen",
	"Center/Panel/Margin/Layout/Display/FullscreenRow/Fullscreen",
]) as CheckButton
@onready var master_slider: HSlider = _resolve_control([
	"Center/Panel/Margin/Layout/BodyScroll/BodyInsets/BodyContent/Audio/Rows/ContentMargin/Content/MasterRow/Slider",
	"Center/Panel/Margin/Layout/Audio/MasterRow/Slider",
]) as HSlider
@onready var master_value: Label = _resolve_control([
	"Center/Panel/Margin/Layout/BodyScroll/BodyInsets/BodyContent/Audio/Rows/ContentMargin/Content/MasterRow/Value",
	"Center/Panel/Margin/Layout/Audio/MasterRow/Value",
]) as Label
@onready var sfx_slider: HSlider = _resolve_control([
	"Center/Panel/Margin/Layout/BodyScroll/BodyInsets/BodyContent/Audio/Rows/ContentMargin/Content/SfxRow/Slider",
	"Center/Panel/Margin/Layout/Audio/SfxRow/Slider",
]) as HSlider
@onready var sfx_value: Label = _resolve_control([
	"Center/Panel/Margin/Layout/BodyScroll/BodyInsets/BodyContent/Audio/Rows/ContentMargin/Content/SfxRow/Value",
	"Center/Panel/Margin/Layout/Audio/SfxRow/Value",
]) as Label
@onready var reduced_motion_check: CheckButton = _resolve_control([
	"Center/Panel/Margin/Layout/BodyScroll/BodyInsets/BodyContent/Accessibility/Rows/ContentMargin/Content/ReducedMotionRow/ReducedMotion",
	"Center/Panel/Margin/Layout/Accessibility/ReducedMotionRow/ReducedMotion",
]) as CheckButton
@onready var config_label: Label = $Center/Panel/Margin/Layout/Persistence/ConfigPath
@onready var status_label: Label = $Center/Panel/Margin/Layout/Persistence/Status
@onready var reset_button: Button = $Center/Panel/Margin/Layout/Footer/Reset
@onready var close_button: Button = $Center/Panel/Margin/Layout/Footer/Close

var _settings: CurlingSettingsScript
var _refreshing := false


func _resolve_control(paths: Array[String]) -> Control:
	for path in paths:
		var node := get_node_or_null(path)
		if node is Control:
			return node as Control
	push_error("Settings panel is missing expected control: %s" % str(paths))
	return null


func _ready() -> void:
	_settings = get_node(settings_path) as CurlingSettingsScript
	_populate_resolution_options()
	resolution_option.item_selected.connect(_on_resolution_selected)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	master_slider.value_changed.connect(_on_master_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	reduced_motion_check.toggled.connect(_on_reduced_motion_toggled)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(close_panel)
	_settings.persistence_finished.connect(_on_persistence_finished)
	_refresh_controls()
	hide()


func open_panel() -> void:
	_settings.apply_all()
	_refresh_controls()
	status_label.text = "设置会自动保存"
	show()
	close_button.grab_focus()
	opened.emit()


func close_panel() -> void:
	if not visible:
		return
	_settings.flush_pending_save()
	get_viewport().gui_release_focus()
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func _populate_resolution_options() -> void:
	resolution_option.clear()
	for size in _settings.get_resolution_options():
		resolution_option.add_item("%d × %d" % [size.x, size.y])


func _refresh_controls() -> void:
	_refreshing = true
	resolution_option.select(_settings.get_selected_resolution_index())
	fullscreen_check.button_pressed = _settings.is_fullscreen_enabled()
	resolution_option.disabled = fullscreen_check.button_pressed
	master_slider.value = _settings.get_volume_percent(CurlingSettingsScript.CHANNEL_MASTER)
	sfx_slider.value = _settings.get_volume_percent(CurlingSettingsScript.CHANNEL_SFX)
	reduced_motion_check.button_pressed = _settings.is_reduced_motion_enabled()
	_update_volume_labels()
	config_label.text = "本机配置  %s" % _settings.get_config_path()
	_refreshing = false


func _on_resolution_selected(index: int) -> void:
	if _refreshing:
		return
	_settings.set_resolution_index(index)
	_mark_pending()


func _on_fullscreen_toggled(enabled: bool) -> void:
	if _refreshing:
		return
	_settings.set_fullscreen_enabled(enabled)
	resolution_option.disabled = enabled
	_mark_pending()


func _on_master_volume_changed(value: float) -> void:
	if _refreshing:
		return
	_settings.set_volume_percent(CurlingSettingsScript.CHANNEL_MASTER, roundi(value))
	_update_volume_labels()
	_mark_pending()


func _on_sfx_volume_changed(value: float) -> void:
	if _refreshing:
		return
	_settings.set_volume_percent(CurlingSettingsScript.CHANNEL_SFX, roundi(value))
	_update_volume_labels()
	_mark_pending()


func _on_reduced_motion_toggled(enabled: bool) -> void:
	if _refreshing:
		return
	_settings.set_reduced_motion_enabled(enabled)
	_mark_pending()


func _on_reset_pressed() -> void:
	var error := _settings.reset_all_settings()
	_refresh_controls()
	status_label.text = "已恢复默认设置" if error == OK else "重置失败：%s" % error_string(error)


func _on_persistence_finished(operation: StringName, _path: String, error_code: int) -> void:
	if not visible or operation == &"load":
		return
	if error_code == OK:
		status_label.text = "已保存到本机" if operation == &"save" else "已恢复默认设置"
	else:
		status_label.text = "设置写入失败：%s" % error_string(error_code)


func _update_volume_labels() -> void:
	master_value.text = "%d%%" % roundi(master_slider.value)
	sfx_value.text = "%d%%" % roundi(sfx_slider.value)


func _mark_pending() -> void:
	status_label.text = "正在保存…"
