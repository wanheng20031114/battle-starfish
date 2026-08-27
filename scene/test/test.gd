extends Node2D

const MAIN_MENU_SCENE := "res://scene/main_menu/main_menu.tscn"
const PLAYER_START := Vector2(250.0, 371.0)
const ENEMY_START := Vector2(674.0, 371.0)
const MAX_PULL_DISTANCE := 190.0
const MIN_LAUNCH_RATIO := 0.06
const READY_SPEED := 7.0

@onready var player_ball: TestBall = $PlayerBall
@onready var enemy_ball: TestBall = $EnemyBall
@onready var arena_walls: StaticBody2D = $ArenaWalls
@onready var aim_guide: Line2D = $AimGuide
@onready var pull_guide: Line2D = $PullGuide

@onready var status_label: Label = $HUD/Overlay/StatusLabel
@onready var power_label: Label = $HUD/Overlay/PowerLabel
@onready var player_speed_label: Label = $HUD/Overlay/Inspector/Margin/VBox/Kinematics/PlayerSpeed
@onready var enemy_speed_label: Label = $HUD/Overlay/Inspector/Margin/VBox/Kinematics/EnemySpeed
@onready var enemy_health_bar: ProgressBar = $HUD/Overlay/Inspector/Margin/VBox/EnemyHealthBar
@onready var enemy_health_value: Label = $HUD/Overlay/Inspector/Margin/VBox/EnemyHeader/EnemyHealthValue
@onready var collision_log: Label = $HUD/Overlay/Inspector/Margin/VBox/CollisionLog

@onready var shot_slider: HSlider = $HUD/Overlay/Inspector/Margin/VBox/Parameters/ShotSlider
@onready var attack_slider: HSlider = $HUD/Overlay/Inspector/Margin/VBox/Parameters/AttackSlider
@onready var player_mass_slider: HSlider = $HUD/Overlay/Inspector/Margin/VBox/Parameters/PlayerMassSlider
@onready var enemy_mass_slider: HSlider = $HUD/Overlay/Inspector/Margin/VBox/Parameters/EnemyMassSlider
@onready var bounce_slider: HSlider = $HUD/Overlay/Inspector/Margin/VBox/Parameters/BounceSlider
@onready var friction_slider: HSlider = $HUD/Overlay/Inspector/Margin/VBox/Parameters/FrictionSlider
@onready var damping_slider: HSlider = $HUD/Overlay/Inspector/Margin/VBox/Parameters/DampingSlider

@onready var shot_value: Label = $HUD/Overlay/Inspector/Margin/VBox/Parameters/ShotValue
@onready var attack_value: Label = $HUD/Overlay/Inspector/Margin/VBox/Parameters/AttackValue
@onready var player_mass_value: Label = $HUD/Overlay/Inspector/Margin/VBox/Parameters/PlayerMassValue
@onready var enemy_mass_value: Label = $HUD/Overlay/Inspector/Margin/VBox/Parameters/EnemyMassValue
@onready var bounce_value: Label = $HUD/Overlay/Inspector/Margin/VBox/Parameters/BounceValue
@onready var friction_value: Label = $HUD/Overlay/Inspector/Margin/VBox/Parameters/FrictionValue
@onready var damping_value: Label = $HUD/Overlay/Inspector/Margin/VBox/Parameters/DampingValue

var _dragging := false
var _drag_mouse_position := Vector2.ZERO
var _shot_active := false
var _settled_duration := 0.0
var _shot_count := 0
var _hit_count := 0


func _ready() -> void:
	_on_shot_changed(shot_slider.value)
	_on_attack_changed(attack_slider.value)
	_on_player_mass_changed(player_mass_slider.value)
	_on_enemy_mass_changed(enemy_mass_slider.value)
	_on_bounce_changed(bounce_slider.value)
	_on_friction_changed(friction_slider.value)
	_on_damping_changed(damping_slider.value)
	_update_health(enemy_ball.current_health, enemy_ball.maximum_health)
	_set_guides_visible(false)
	_update_live_readout()


func _process(delta: float) -> void:
	if _dragging:
		_drag_mouse_position = get_global_mouse_position()
		_update_aim_guides()

	_update_simulation_state(delta)
	_update_live_readout()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file(MAIN_MENU_SCENE)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			_reset_test()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			_quick_launch()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_begin_drag(get_global_mouse_position())
		elif _dragging:
			_release_drag()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if not _dragging:
		return

	var launch_data := _get_launch_data()
	var direction: Vector2 = launch_data.direction
	var ratio: float = launch_data.ratio
	var arrow_length := lerpf(92.0, 238.0, ratio)
	var tip := player_ball.global_position + direction * arrow_length
	var arrow_base := tip - direction * 18.0
	var perpendicular := direction.orthogonal()
	var accent := Color(0.30, 0.94, 0.88, 0.94)

	draw_circle(_drag_mouse_position, 10.0, Color(0.30, 0.94, 0.88, 0.16), true, -1.0, true)
	draw_circle(_drag_mouse_position, 10.0, accent, false, 2.0, true)
	draw_arc(player_ball.global_position, 57.0, -PI * 0.35, PI * (1.65 * ratio), 48, Color(accent, 0.32), 2.0, true)
	draw_colored_polygon(
		PackedVector2Array([tip, arrow_base + perpendicular * 8.0, arrow_base - perpendicular * 8.0]),
		accent
	)


func _try_begin_drag(pointer_position: Vector2) -> void:
	if pointer_position.distance_to(player_ball.global_position) > player_ball.ball_radius + 14.0:
		return
	if not _bodies_are_ready():
		collision_log.text = "球体仍在运动，停稳后才能再次发射。"
		return

	_dragging = true
	_drag_mouse_position = pointer_position
	_set_guides_visible(true)
	_update_aim_guides()
	get_viewport().set_input_as_handled()


func _release_drag() -> void:
	var launch_data := _get_launch_data()
	_dragging = false
	_set_guides_visible(false)
	queue_redraw()

	if launch_data.ratio < MIN_LAUNCH_RATIO:
		collision_log.text = "已取消：向后拖得更远，发射力度会更大。"
		return

	_launch(launch_data.direction, launch_data.ratio)


func _quick_launch() -> void:
	if not _bodies_are_ready():
		collision_log.text = "球体仍在运动，暂时不能试射。"
		return
	_launch(Vector2.RIGHT, 1.0)


func _launch(direction: Vector2, strength_ratio: float) -> void:
	player_ball.sleeping = false
	player_ball.apply_central_impulse(direction * shot_slider.value * strength_ratio)
	_shot_active = true
	_settled_duration = 0.0
	_shot_count += 1
	collision_log.text = "第 %d 次发射 · 冲量 %.0f · 等待碰撞" % [_shot_count, shot_slider.value * strength_ratio]


func _get_launch_data() -> Dictionary:
	var pull_vector := player_ball.global_position - _drag_mouse_position
	var pull_distance := minf(pull_vector.length(), MAX_PULL_DISTANCE)
	var direction := pull_vector.normalized() if pull_distance > 0.0 else Vector2.RIGHT
	return {
		"direction": direction,
		"ratio": pull_distance / MAX_PULL_DISTANCE,
		"pull_distance": pull_distance,
	}


func _update_aim_guides() -> void:
	var launch_data := _get_launch_data()
	var direction: Vector2 = launch_data.direction
	var ratio: float = launch_data.ratio
	var clamped_pointer := player_ball.global_position - direction * float(launch_data.pull_distance)
	var preview_end := player_ball.global_position + direction * lerpf(92.0, 238.0, ratio)

	pull_guide.points = PackedVector2Array([player_ball.global_position, clamped_pointer])
	aim_guide.points = PackedVector2Array([player_ball.global_position, preview_end])
	aim_guide.width = lerpf(2.0, 5.0, ratio)
	power_label.text = "力度 %3.0f%%  ·  冲量 %.0f" % [ratio * 100.0, shot_slider.value * ratio]
	queue_redraw()


func _update_simulation_state(delta: float) -> void:
	if _dragging:
		status_label.text = "AIMING  /  拖拽蓄力"
		return

	var maximum_speed := maxf(player_ball.linear_velocity.length(), enemy_ball.linear_velocity.length())
	if maximum_speed > READY_SPEED:
		_settled_duration = 0.0
		status_label.text = "SIMULATING  /  物理解算中"
		power_label.text = "累计命中 %d  ·  总发射 %d" % [_hit_count, _shot_count]
	else:
		_settled_duration += delta
		if _settled_duration >= 0.35:
			_shot_active = false
		status_label.text = "READY  /  可发射"
		power_label.text = "拖住青色球向后拉"


func _update_live_readout() -> void:
	player_speed_label.text = "玩家速度\n%.0f px/s" % player_ball.linear_velocity.length()
	enemy_speed_label.text = "敌方速度\n%.0f px/s" % enemy_ball.linear_velocity.length()


func _bodies_are_ready() -> bool:
	return not _dragging \
		and player_ball.linear_velocity.length() <= READY_SPEED \
		and enemy_ball.linear_velocity.length() <= READY_SPEED


func _set_guides_visible(value: bool) -> void:
	aim_guide.visible = value
	pull_guide.visible = value


func _on_player_ball_body_entered(body: Node) -> void:
	if body != enemy_ball or not _shot_active:
		return

	var impact_speed := (player_ball.linear_velocity - enemy_ball.linear_velocity).length()
	var damage := attack_slider.value
	_hit_count += 1
	enemy_ball.take_damage(damage)
	collision_log.text = "命中 #%d · 相对速度 %.0f px/s · 造成 %.0f 伤害" % [_hit_count, impact_speed, damage]


func _on_enemy_health_changed(current_health: float, maximum_health: float) -> void:
	_update_health(current_health, maximum_health)


func _update_health(current_health: float, maximum_health: float) -> void:
	enemy_health_bar.max_value = maximum_health
	enemy_health_bar.value = current_health
	enemy_health_value.text = "%.0f / %.0f" % [current_health, maximum_health]


func _on_shot_changed(value: float) -> void:
	shot_value.text = "%.0f" % value


func _on_attack_changed(value: float) -> void:
	attack_value.text = "%.0f" % value


func _on_player_mass_changed(value: float) -> void:
	player_ball.mass = value
	player_mass_value.text = "%.2f" % value


func _on_enemy_mass_changed(value: float) -> void:
	enemy_ball.mass = value
	enemy_mass_value.text = "%.2f" % value


func _on_bounce_changed(value: float) -> void:
	player_ball.physics_material_override.bounce = value
	enemy_ball.physics_material_override.bounce = value
	arena_walls.physics_material_override.bounce = value
	bounce_value.text = "%.2f" % value


func _on_friction_changed(value: float) -> void:
	player_ball.physics_material_override.friction = value
	enemy_ball.physics_material_override.friction = value
	arena_walls.physics_material_override.friction = value
	friction_value.text = "%.2f" % value


func _on_damping_changed(value: float) -> void:
	player_ball.linear_damp = value
	enemy_ball.linear_damp = value
	damping_value.text = "%.2f" % value


func _reset_test() -> void:
	_dragging = false
	_shot_active = false
	_settled_duration = 0.0
	_shot_count = 0
	_hit_count = 0
	_set_guides_visible(false)
	queue_redraw()

	_reset_body(player_ball, PLAYER_START)
	_reset_body(enemy_ball, ENEMY_START)
	enemy_ball.restore_health()
	status_label.text = "READY  /  可发射"
	power_label.text = "拖住青色球向后拉"
	collision_log.text = "试验已重置。调整参数后可以立即再次发射。"


func _reset_body(body: RigidBody2D, target_position: Vector2) -> void:
	body.freeze = true
	body.position = target_position
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0.0
	body.freeze = false
	body.sleeping = true


func _on_quick_launch_pressed() -> void:
	_quick_launch()


func _on_reset_pressed() -> void:
	_reset_test()
