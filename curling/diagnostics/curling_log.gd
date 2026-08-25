extends RefCounted
class_name CurlingLog

const LOG_DIRECTORY := "user://curling/logs"
const MAX_LOG_BYTES := 2 * 1024 * 1024
const MAX_LOG_FILES := 5

var _file: FileAccess


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIRECTORY))
	_rotate_if_needed()
	_file = FileAccess.open(LOG_DIRECTORY + "/curling.log", FileAccess.READ_WRITE)
	if _file != null:
		_file.seek_end()


func event(category: String, name: String, fields: Dictionary = {}) -> void:
	if _file == null:
		return
	var safe_fields := fields.duplicate(true)
	for key in safe_fields.keys():
		var normalized := str(key).to_lower()
		if "token" in normalized or "ticket" in normalized or "secret" in normalized:
			safe_fields[key] = "[REDACTED]"
	var record := {
		"time_unix": Time.get_unix_time_from_system(),
		"category": category,
		"event": name,
		"fields": safe_fields,
	}
	_file.store_line(JSON.stringify(record))
	_file.flush()


func _rotate_if_needed() -> void:
	var current_path := LOG_DIRECTORY + "/curling.log"
	if not FileAccess.file_exists(current_path):
		return
	var current := FileAccess.open(current_path, FileAccess.READ)
	if current == null or current.get_length() < MAX_LOG_BYTES:
		return
	current = null
	for index in range(MAX_LOG_FILES - 1, 0, -1):
		var older := "%s/curling.%d.log" % [LOG_DIRECTORY, index]
		var newer := "%s/curling.%d.log" % [LOG_DIRECTORY, index + 1]
		if FileAccess.file_exists(older):
			if index + 1 >= MAX_LOG_FILES and FileAccess.file_exists(newer):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(newer))
			DirAccess.rename_absolute(ProjectSettings.globalize_path(older), ProjectSettings.globalize_path(newer))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(current_path), ProjectSettings.globalize_path(LOG_DIRECTORY + "/curling.1.log"))

