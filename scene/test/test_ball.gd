@tool
class_name TestBall
extends RigidBody2D

signal health_changed(current_health: float, maximum_health: float)

@export_category("Placeholder Ball")
@export var display_name := "测试球":
	set(value):
		display_name = value
		_refresh_labels()
@export_enum("玩家", "敌方") var team := "玩家":
	set(value):
		team = value
		_refresh_labels()
@export var accent_color := Color("4de7dd"):
	set(value):
		accent_color = value
		_refresh_labels()
		queue_redraw()
@export_range(1.0, 999.0, 1.0) var maximum_health := 100.0
@export_range(20.0, 80.0, 1.0) var ball_radius := 44.0:
	set(value):
		ball_radius = value
		queue_redraw()

var current_health := 100.0
var _hit_flash := 0.0

@onready var _name_label: Label = $NameLabel
@onready var _team_glyph: Label = $TeamGlyph


func _ready() -> void:
	current_health = maximum_health
	_refresh_labels()
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _hit_flash <= 0.0:
		return
	_hit_flash = maxf(_hit_flash - delta * 5.5, 0.0)
	queue_redraw()


func take_damage(amount: float) -> void:
	current_health = maxf(current_health - amount, 0.0)
	_hit_flash = 1.0
	health_changed.emit(current_health, maximum_health)
	queue_redraw()


func restore_health() -> void:
	current_health = maximum_health
	_hit_flash = 0.0
	health_changed.emit(current_health, maximum_health)
	queue_redraw()


func _refresh_labels() -> void:
	if not is_node_ready():
		return
	_name_label.text = display_name
	_name_label.add_theme_color_override("font_color", accent_color.lightened(0.28))
	_team_glyph.text = "P" if team == "玩家" else "E"
	_team_glyph.add_theme_color_override("font_color", accent_color.lightened(0.38))


func _draw() -> void:
	var flash_color := accent_color.lerp(Color.WHITE, _hit_flash * 0.78)
	var bubble_fill := Color(accent_color, 0.12 + _hit_flash * 0.15)
	var core_fill := flash_color.darkened(0.58)

	# The larger translucent ring stands in for the future bubble artwork.
	draw_circle(Vector2.ZERO, ball_radius + 5.0, Color(accent_color, 0.055), true, -1.0, true)
	draw_circle(Vector2.ZERO, ball_radius, bubble_fill, true, -1.0, true)
	draw_circle(Vector2.ZERO, ball_radius, Color(accent_color, 0.86), false, 2.5, true)
	draw_arc(Vector2.ZERO, ball_radius - 4.0, -2.72, -1.25, 24, Color(1.0, 1.0, 1.0, 0.38), 2.0, true)

	# A simple inner ball keeps this test independent of final character art.
	draw_circle(Vector2.ZERO, ball_radius - 10.0, Color("07141d"), true, -1.0, true)
	draw_circle(Vector2.ZERO, ball_radius - 13.0, core_fill, true, -1.0, true)
	draw_circle(Vector2(-11.0, -13.0), 4.2, Color(1.0, 1.0, 1.0, 0.42), true, -1.0, true)
	draw_arc(Vector2.ZERO, ball_radius - 13.0, 0.28, 2.42, 24, Color(accent_color, 0.52), 2.0, true)
