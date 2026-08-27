extends Node
class_name CurlingSettings

signal persistence_finished(operation: StringName, config_path: String, error_code: int)
signal reduced_motion_changed(enabled: bool)

const DEFAULT_CONFIG_PATH := "user://curling_settings.cfg"
const SAVE_DEBOUNCE_SECONDS := 0.25
const BASE_CONTENT_SIZE := Vector2i(1280, 720)

const SECTION_DISPLAY := "display"
const SECTION_AUDIO := "audio"
const SECTION_ACCESSIBILITY := "accessibility"
const SECTION_PLAYER := "player"

const CHANNEL_MASTER := &"master"
const CHANNEL_SFX := &"sfx"
const MASTER_BUS := &"Master"
const SFX_BUS := &"SFX"

const DEFAULT_RESOLUTION_INDEX := 0
const DEFAULT_FULLSCREEN := false
const DEFAULT_MASTER_VOLUME := 100
const DEFAULT_SFX_VOLUME := 100
const DEFAULT_REDUCED_MOTION := false

const RESOLUTION_OPTIONS := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
]

@export var config_path := DEFAULT_CONFIG_PATH

var _config := ConfigFile.new()
var _resolution_index := DEFAULT_RESOLUTION_INDEX
var _fullscreen := DEFAULT_FULLSCREEN
var _master_volume := DEFAULT_MASTER_VOLUME
var _sfx_volume := DEFAULT_SFX_VOLUME
var _reduced_motion := DEFAULT_REDUCED_MOTION
var _save_pending := false
var _save_elapsed := 0.0
var _last_persistence_error := OK


func _ready() -> void:
	set_process(false)
	load_settings()
	apply_all()


func _process(delta: float) -> void:
	if not _save_pending:
		set_process(false)
		return
	_save_elapsed += delta
	if _save_elapsed >= SAVE_DEBOUNCE_SECONDS:
		_save_now()


func _exit_tree() -> void:
	flush_pending_save()


func load_settings() -> int:
	_config = ConfigFile.new()
	var error := _config.load(config_path)
	if error == ERR_FILE_NOT_FOUND:
		error = OK
	elif error != OK:
		_set_defaults()
		_last_persistence_error = error
		persistence_finished.emit(&"load", config_path, error)
		return error

	_resolution_index = clampi(
		int(_config.get_value(SECTION_DISPLAY, "resolution_index", DEFAULT_RESOLUTION_INDEX)),
		0,
		RESOLUTION_OPTIONS.size() - 1
	)
	_fullscreen = bool(_config.get_value(SECTION_DISPLAY, "fullscreen", DEFAULT_FULLSCREEN))
	_master_volume = clampi(int(_config.get_value(SECTION_AUDIO, "master_volume", DEFAULT_MASTER_VOLUME)), 0, 100)
	_sfx_volume = clampi(int(_config.get_value(SECTION_AUDIO, "sfx_volume", DEFAULT_SFX_VOLUME)), 0, 100)
	_reduced_motion = bool(_config.get_value(SECTION_ACCESSIBILITY, "reduced_motion", DEFAULT_REDUCED_MOTION))
	_last_persistence_error = OK
	persistence_finished.emit(&"load", config_path, OK)
	return OK


func apply_all() -> void:
	_apply_display()
	_apply_audio()


func get_config_path() -> String:
	return config_path


func get_config_file_system_path() -> String:
	return ProjectSettings.globalize_path(config_path)


func is_save_pending() -> bool:
	return _save_pending


func get_last_persistence_error() -> int:
	return _last_persistence_error


func flush_pending_save() -> int:
	if not _save_pending:
		return _last_persistence_error
	return _save_now()


func reset_all_settings() -> int:
	_set_defaults()
	_config = ConfigFile.new()
	_save_pending = false
	_save_elapsed = 0.0
	set_process(false)
	apply_all()
	reduced_motion_changed.emit(_reduced_motion)
	var error := OK
	if FileAccess.file_exists(config_path):
		error = DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
	_last_persistence_error = error
	persistence_finished.emit(&"reset", config_path, error)
	return error


func get_resolution_options() -> Array[Vector2i]:
	var options: Array[Vector2i] = []
	for option in RESOLUTION_OPTIONS:
		options.append(option)
	return options


func get_selected_resolution_index() -> int:
	return _resolution_index


func set_resolution_index(index: int) -> void:
	var normalized := clampi(index, 0, RESOLUTION_OPTIONS.size() - 1)
	if normalized == _resolution_index:
		return
	_resolution_index = normalized
	_apply_display()
	_schedule_save()


func is_fullscreen_enabled() -> bool:
	return _fullscreen


func set_fullscreen_enabled(enabled: bool) -> void:
	if enabled == _fullscreen:
		return
	_fullscreen = enabled
	_apply_display()
	_schedule_save()


func get_volume_percent(channel: StringName) -> int:
	match channel:
		CHANNEL_MASTER:
			return _master_volume
		CHANNEL_SFX:
			return _sfx_volume
	return 0


func set_volume_percent(channel: StringName, percent: int) -> void:
	var normalized := clampi(percent, 0, 100)
	match channel:
		CHANNEL_MASTER:
			if normalized == _master_volume:
				return
			_master_volume = normalized
		CHANNEL_SFX:
			if normalized == _sfx_volume:
				return
			_sfx_volume = normalized
		_:
			return
	_apply_audio()
	_schedule_save()


func is_reduced_motion_enabled() -> bool:
	return _reduced_motion


func get_player_nickname() -> String:
	return str(_config.get_value(SECTION_PLAYER, "nickname", ""))


func set_player_nickname(nickname: String) -> void:
	if nickname == get_player_nickname():
		return
	_config.set_value(SECTION_PLAYER, "nickname", nickname)
	_schedule_save()


func set_reduced_motion_enabled(enabled: bool) -> void:
	if enabled == _reduced_motion:
		return
	_reduced_motion = enabled
	reduced_motion_changed.emit(enabled)
	_schedule_save()


func _set_defaults() -> void:
	_resolution_index = DEFAULT_RESOLUTION_INDEX
	_fullscreen = DEFAULT_FULLSCREEN
	_master_volume = DEFAULT_MASTER_VOLUME
	_sfx_volume = DEFAULT_SFX_VOLUME
	_reduced_motion = DEFAULT_REDUCED_MOTION


func _schedule_save() -> void:
	_save_pending = true
	_save_elapsed = 0.0
	set_process(true)


func _save_now() -> int:
	_write_values_to_config()
	var error := _config.save(config_path)
	_save_pending = false
	_save_elapsed = 0.0
	set_process(false)
	_last_persistence_error = error
	persistence_finished.emit(&"save", config_path, error)
	return error


func _write_values_to_config() -> void:
	_config.set_value(SECTION_DISPLAY, "resolution_index", _resolution_index)
	_config.set_value(SECTION_DISPLAY, "fullscreen", _fullscreen)
	_config.set_value(SECTION_AUDIO, "master_volume", _master_volume)
	_config.set_value(SECTION_AUDIO, "sfx_volume", _sfx_volume)
	_config.set_value(SECTION_ACCESSIBILITY, "reduced_motion", _reduced_motion)


func _apply_display() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = BASE_CONTENT_SIZE
	if _fullscreen:
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	var target_size: Vector2i = RESOLUTION_OPTIONS[_resolution_index]
	window.size = target_size
	var usable_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.position = usable_rect.position + (usable_rect.size - target_size) / 2


func _apply_audio() -> void:
	var sfx_index := _ensure_sfx_bus()
	_apply_bus_volume(AudioServer.get_bus_index(MASTER_BUS), _master_volume)
	_apply_bus_volume(sfx_index, _sfx_volume)


func _ensure_sfx_bus() -> int:
	var bus_index := AudioServer.get_bus_index(SFX_BUS)
	if bus_index >= 0:
		return bus_index
	AudioServer.add_bus(AudioServer.bus_count)
	bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, SFX_BUS)
	AudioServer.set_bus_send(bus_index, MASTER_BUS)
	return bus_index


func _apply_bus_volume(bus_index: int, percent: int) -> void:
	if bus_index < 0:
		return
	var linear := float(percent) / 100.0
	AudioServer.set_bus_mute(bus_index, percent <= 0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(linear, 0.0001)))
