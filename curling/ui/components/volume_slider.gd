extends HSlider
class_name VolumeSlider

@onready var progress_bar: ProgressBar = $ProgressBar


func _ready() -> void:
	progress_bar.min_value = min_value
	progress_bar.max_value = max_value
	progress_bar.step = step
	progress_bar.value = value
	value_changed.connect(_on_value_changed)


func _on_value_changed(new_value: float) -> void:
	progress_bar.value = new_value
