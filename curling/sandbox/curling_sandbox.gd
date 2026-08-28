extends Node
class_name CurlingSandbox

const MAIN_MENU_SCENE := "res://scene/main_menu/main_menu.tscn"
const CurlingSettingsScript := preload("res://curling/settings/curling_settings.gd")
const CurlingSettingsPanelScript := preload("res://curling/settings/curling_settings_panel.gd")

@onready var settings: CurlingSettingsScript = $CurlingSettings
@onready var audio: CurlingAudio = $CurlingAudio
@onready var controller: CurlingSandboxController = $SandboxController
@onready var settings_panel: CurlingSettingsPanelScript = $UI/SettingsPanel

@onready var status_label: Label = $UI/Root/TopBar/Margin/Content/Status
@onready var counts_label: Label = $UI/Root/TopBar/Margin/Content/Counts
@onready var shot_list: ItemList = $UI/Root/RightRail/Margin/Layout/ShotList
@onready var selected_title: Label = $UI/Root/RightRail/Margin/Layout/InspectorHeader/SelectedTitle
@onready var focus_button: Button = $UI/Root/RightRail/Margin/Layout/InspectorHeader/Focus
@onready var data_tab: Button = $UI/Root/RightRail/Margin/Layout/Tabs/Data
@onready var curves_tab: Button = $UI/Root/RightRail/Margin/Layout/Tabs/Curves
@onready var data_view: ScrollContainer = $UI/Root/RightRail/Margin/Layout/DataView
@onready var curves_view: CurlingTelemetryPlot = $UI/Root/RightRail/Margin/Layout/CurvesView
@onready var record_status: Label = $UI/Root/RightRail/Margin/Layout/DataView/Data/RecordStatus
@onready var launch_data: RichTextLabel = $UI/Root/RightRail/Margin/Layout/DataView/Data/LaunchData
@onready var live_data: RichTextLabel = $UI/Root/RightRail/Margin/Layout/DataView/Data/LiveData
@onready var remove_button: Button = $UI/Root/RightRail/Margin/Layout/Actions/Remove
@onready var clear_field_button: Button = $UI/Root/RightRail/Margin/Layout/Actions/ClearField
@onready var clear_history_button: Button = $UI/Root/RightRail/Margin/Layout/Actions/ClearHistory
@onready var clear_history_dialog: ConfirmationDialog = $UI/ClearHistoryDialog

@onready var power_bar: ProgressBar = $UI/Root/BottomBar/Margin/Content/Power
@onready var aim_readout: Label = $UI/Root/BottomBar/Margin/Content/AimReadout
@onready var red_button: Button = $UI/Root/BottomBar/Margin/Content/Red
@onready var blue_button: Button = $UI/Root/BottomBar/Margin/Content/Blue
@onready var right_button: Button = $UI/Root/BottomBar/Margin/Content/Right
@onready var left_button: Button = $UI/Root/BottomBar/Margin/Content/Left


func _ready() -> void:
	_connect_ui()
	_connect_controller()
	controller.reduced_motion = settings.is_reduced_motion_enabled()
	_refresh_mode_buttons()
	_refresh_records()
	_refresh_selected(controller.get_selected_record())
	_on_status_changed(controller.get_status_message())
	_show_data_tab()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return
	if settings_panel.is_open():
		settings_panel.close_panel()
	else:
		settings_panel.open_panel()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(audio):
		audio.stop_all()


func _connect_ui() -> void:
	$UI/Root/TopBar/Margin/Content/MainMenu.pressed.connect(_return_to_main_menu)
	$UI/Root/TopBar/Margin/Content/Settings.pressed.connect(settings_panel.open_panel)
	shot_list.item_selected.connect(_on_history_selected)
	focus_button.pressed.connect(controller.focus_selected)
	data_tab.pressed.connect(_show_data_tab)
	curves_tab.pressed.connect(_show_curves_tab)
	remove_button.pressed.connect(controller.remove_selected)
	clear_field_button.pressed.connect(controller.clear_field)
	clear_history_button.pressed.connect(func() -> void: clear_history_dialog.popup_centered())
	clear_history_dialog.confirmed.connect(controller.clear_history)
	red_button.pressed.connect(func() -> void:
		controller.set_next_team(CurlingConstants.TEAM_RED)
		_refresh_mode_buttons()
	)
	blue_button.pressed.connect(func() -> void:
		controller.set_next_team(CurlingConstants.TEAM_BLUE)
		_refresh_mode_buttons()
	)
	right_button.pressed.connect(func() -> void:
		controller.set_next_direction(1)
		_refresh_mode_buttons()
	)
	left_button.pressed.connect(func() -> void:
		controller.set_next_direction(-1)
		_refresh_mode_buttons()
	)
	settings_panel.opened.connect(func() -> void:
		controller.set_input_locked(true)
		audio.set_sweeping(false)
	)
	settings_panel.closed.connect(func() -> void: controller.set_input_locked(false))
	settings.reduced_motion_changed.connect(func(enabled: bool) -> void: controller.reduced_motion = enabled)


func _connect_controller() -> void:
	controller.status_changed.connect(_on_status_changed)
	controller.records_changed.connect(_refresh_records)
	controller.selection_changed.connect(_refresh_selected)
	controller.telemetry_changed.connect(_refresh_selected)
	controller.aim_changed.connect(_on_aim_changed)
	controller.shot_launched.connect(func(_record: CurlingShotRecord) -> void: audio.play_launch())
	controller.impact_feedback.connect(audio.play_impact)
	controller.sweeping_changed.connect(func(active: bool, intensity: float) -> void:
		audio.set_sweeping(active, intensity)
	)


func _return_to_main_menu() -> void:
	audio.stop_all()
	settings.flush_pending_save()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_status_changed(message: String) -> void:
	status_label.text = message
	_refresh_counts()


func _on_aim_changed(data: Dictionary) -> void:
	power_bar.value = float(data.get("power", 0.0)) * 100.0
	aim_readout.text = "力 %.2f%%  ·  向 %+0.02f°  ·  旋 %+0.2f rad/s" % [
		float(data.get("power", 0.0)) * 100.0,
		float(data.get("aim_offset_degrees", 0.0)),
		float(data.get("spin", 0.0)),
	]
	_refresh_counts()


func _refresh_counts() -> void:
	counts_label.text = "场上 %d  ·  记录 %d" % [
		controller.get_field_count(),
		controller.get_total_shots(),
	]


func _refresh_mode_buttons() -> void:
	red_button.button_pressed = controller.next_team == CurlingConstants.TEAM_RED
	blue_button.button_pressed = controller.next_team == CurlingConstants.TEAM_BLUE
	right_button.button_pressed = controller.next_direction > 0
	left_button.button_pressed = controller.next_direction < 0


func _refresh_records() -> void:
	var selected_id := controller.get_selected_record().shot_id if controller.get_selected_record() != null else -1
	shot_list.clear()
	var all_records := controller.get_records()
	all_records.reverse()
	for record in all_records:
		var row := shot_list.add_item(
			"#%03d  %s  ·  %s" % [record.shot_id, record.team_text(), record.status_text()]
		)
		shot_list.set_item_metadata(row, record.shot_id)
		shot_list.set_item_custom_fg_color(
			row,
			CurlingConstants.TEAM_RED_COLOR.darkened(0.25)
			if record.team == CurlingConstants.TEAM_RED
			else CurlingConstants.TEAM_BLUE_COLOR.darkened(0.20)
		)
		if record.shot_id == selected_id:
			shot_list.select(row)
	_refresh_counts()


func _on_history_selected(index: int) -> void:
	if index < 0 or index >= shot_list.item_count:
		return
	controller.select_record(int(shot_list.get_item_metadata(index)))


func _refresh_selected(record: CurlingShotRecord) -> void:
	if record == null:
		selected_title.text = "未选择冰壶"
		record_status.text = "从场上或历史记录选择一颗冰壶"
		launch_data.text = ""
		live_data.text = ""
		focus_button.disabled = true
		remove_button.disabled = true
		curves_view.clear_record()
		return
	selected_title.text = "#%03d  %s" % [record.shot_id, record.team_text()]
	record_status.text = "%s  ·  %s" % [record.status_text(), record.status_reason]
	focus_button.disabled = false
	remove_button.disabled = not record.is_on_field()
	launch_data.text = _format_launch_data(record)
	live_data.text = _format_live_data(record)
	curves_view.show_record(record)


func _format_launch_data(record: CurlingShotRecord) -> String:
	return "\n".join([
		"[color=#547377]出手时间[/color]  %s" % record.launched_at_clock,
		"[color=#547377]投掷方向[/color]  %s" % record.direction_text(),
		"[color=#547377]起点[/color]  (%.3f, %.3f) m" % [
			record.launch_origin.x / CurlingConstants.PIXELS_PER_METER,
			record.launch_origin.y / CurlingConstants.PIXELS_PER_METER,
		],
		"[color=#547377]力度[/color]  %.3f%%" % (record.power * 100.0),
		"[color=#547377]初速度[/color]  %.4f m/s" % record.initial_speed_mps,
		"[color=#547377]绝对方向角[/color]  %+0.4f°" % record.launch_angle_degrees,
		"[color=#547377]方向偏移[/color]  %+0.4f°" % record.aim_offset_degrees,
		"[color=#547377]初始旋转[/color]  %+0.4f rad/s" % record.initial_spin_radps,
	])


func _format_live_data(record: CurlingShotRecord) -> String:
	var telemetry := record.latest_telemetry
	var velocity := telemetry.get("velocity_mps", Vector2.ZERO) as Vector2
	var position := record.current_position / CurlingConstants.PIXELS_PER_METER
	var tee_distance := record.current_position.distance_to(
		CurlingConstants.tee_position(record.throw_direction)
	) / CurlingConstants.PIXELS_PER_METER
	return "\n".join([
		"[color=#547377]位置[/color]  (%.3f, %.3f) m" % [position.x, position.y],
		"[color=#547377]速度[/color]  %.4f m/s  (%.4f, %.4f)" % [
			float(telemetry.get("speed_mps", 0.0)), velocity.x, velocity.y,
		],
		"[color=#547377]角速度[/color]  %+0.4f rad/s" % float(telemetry.get("angular_velocity_radps", 0.0)),
		"[color=#547377]滑行时间[/color]  %.3f s" % record.elapsed_sec,
		"[color=#547377]累计路径[/color]  %.4f m" % record.path_length_m,
		"[color=#547377]起点位移[/color]  %.4f m" % record.displacement_m,
		"[color=#547377]距目标 Tee[/color]  %.4f m" % tee_distance,
		"[color=#547377]最高速度[/color]  %.4f m/s" % record.max_speed_mps,
		"[color=#547377]冰面热量[/color]  %.2f%%" % (float(telemetry.get("heat", 0.0)) * 100.0),
		"[color=#547377]线性阻尼[/color]  %.6f /s" % float(telemetry.get("linear_damp_per_sec", 0.0)),
		"[color=#547377]摩擦减速度[/color]  %.5f m/s²" % float(telemetry.get("drag_acceleration_mps2", 0.0)),
		"[color=#547377]摩擦力[/color]  %.5f N" % float(telemetry.get("drag_force_n", 0.0)),
		"[color=#547377]弯曲加速度[/color]  %+0.5f m/s²" % float(telemetry.get("curl_acceleration_mps2", 0.0)),
		"[color=#547377]横向作用力[/color]  %+0.5f N" % float(telemetry.get("curl_force_n", 0.0)),
		"[color=#547377]预计剩余[/color]  %.3f s" % float(telemetry.get("remaining_sec", 0.0)),
		"[color=#547377]碰撞[/color]  %d 次  ·  最近 %.4f m/s" % [
			record.collision_count, record.last_collision_speed_mps,
		],
		"[color=#547377]最近碰撞冲量[/color]  %.5f N·s" % record.last_collision_impulse_ns,
	])


func _show_data_tab() -> void:
	data_tab.button_pressed = true
	curves_tab.button_pressed = false
	data_view.visible = true
	curves_view.visible = false


func _show_curves_tab() -> void:
	data_tab.button_pressed = false
	curves_tab.button_pressed = true
	data_view.visible = false
	curves_view.visible = true
