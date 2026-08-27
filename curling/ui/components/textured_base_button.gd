extends Button

@export var normal_texture: Texture2D
@export var active_texture: Texture2D
@export var display_text := ""
@export var display_icon: Texture2D

@onready var background: TextureRect = $Background
@onready var content_icon: TextureRect = $ContentInsets/Center/Content/Icon
@onready var content_label: Label = $ContentInsets/Center/Content/Label

var _last_draw_mode := -1
var _last_disabled := false


func _ready() -> void:
	if display_text.is_empty() and not text.is_empty():
		display_text = text
	text = ""
	_refresh_content()
	_refresh_background()


func _process(_delta: float) -> void:
	if not text.is_empty() and text != display_text:
		display_text = text
		text = ""
		_refresh_content()
	elif not text.is_empty():
		text = ""
	var draw_mode := get_draw_mode()
	if draw_mode != _last_draw_mode or disabled != _last_disabled:
		_refresh_background()


func _refresh_content() -> void:
	content_label.text = display_text
	content_icon.texture = display_icon
	content_icon.visible = display_icon != null


func _refresh_background() -> void:
	_last_draw_mode = get_draw_mode()
	_last_disabled = disabled
	var is_active := _last_draw_mode in [DRAW_PRESSED, DRAW_HOVER, DRAW_HOVER_PRESSED]
	background.texture = active_texture if is_active and active_texture != null else normal_texture
	background.modulate = Color(1.0, 1.0, 1.0, 0.58) if disabled else Color.WHITE
