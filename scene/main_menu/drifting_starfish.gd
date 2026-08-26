extends Node2D
class_name DriftingStarfish

@export var velocity := Vector2(22.0, -15.0)
@export_range(0.0, 1.0, 0.01) var reset_y_ratio := 0.82
@export_range(0, 7, 1) var start_frame := 0
@export var wrap_margin := 90.0

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	sprite.frame = start_frame
	sprite.frame_progress = 0.0


func _process(delta: float) -> void:
	position += velocity * delta
	var viewport_size := get_viewport_rect().size
	if position.x > viewport_size.x + wrap_margin or position.y < -wrap_margin:
		position = Vector2(-wrap_margin, viewport_size.y * reset_y_ratio)
