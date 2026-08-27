extends Node2D
class_name SeabedStarfish

@export_range(0, 7, 1) var start_frame := 0
@export var crawl_extent := Vector2(8.0, 2.0)
@export_range(4.0, 20.0, 0.1) var crawl_period := 9.0
@export_range(0.0, 1.0, 0.01) var crawl_phase := 0.0
@export_range(0.0, 3.0, 0.1) var turn_degrees := 1.0

@onready var sprite: AnimatedSprite2D = $Sprite

var _anchor_position := Vector2.ZERO
var _anchor_rotation := 0.0
var _elapsed := 0.0


func _ready() -> void:
	_anchor_position = position
	_anchor_rotation = rotation
	sprite.frame = start_frame
	sprite.frame_progress = 0.0
	_apply_crawl_pose()


func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, crawl_period)
	_apply_crawl_pose()


func _apply_crawl_pose() -> void:
	var phase := ((_elapsed / crawl_period) + crawl_phase) * TAU
	position = _anchor_position + Vector2(
		sin(phase) * crawl_extent.x,
		sin(phase * 2.0) * crawl_extent.y
	)
	rotation = _anchor_rotation + deg_to_rad(sin(phase + PI / 3.0) * turn_degrees)
