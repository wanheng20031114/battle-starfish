extends Control
class_name CurlingTelemetryPlot

const PLOT_GAP := 12.0
const LABEL_HEIGHT := 18.0
const PLOT_COLORS := {
	"speed": Color("2e9296"),
	"drag": Color("d79a2b"),
	"curl": Color("df535c"),
	"heat": Color("37bbb3"),
}

var selected_record: CurlingShotRecord


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	if selected_record != null and selected_record.status == CurlingShotRecord.Status.MOVING:
		queue_redraw()


func show_record(record: CurlingShotRecord) -> void:
	selected_record = record
	queue_redraw()


func clear_record() -> void:
	selected_record = null
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if selected_record == null or selected_record.samples.is_empty():
		draw_string(font, Vector2(12.0, 30.0), "选择冰壶后显示曲线", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color("61777b"))
		return
	var content := Rect2(Vector2(10.0, 8.0), size - Vector2(20.0, 16.0))
	var band_height := (content.size.y - PLOT_GAP * 2.0) / 3.0
	var speed_rect := Rect2(content.position, Vector2(content.size.x, band_height))
	var force_rect := Rect2(content.position + Vector2(0.0, band_height + PLOT_GAP), Vector2(content.size.x, band_height))
	var heat_rect := Rect2(content.position + Vector2(0.0, (band_height + PLOT_GAP) * 2.0), Vector2(content.size.x, band_height))
	var end_time := maxf(1.0, float(selected_record.samples[-1].get("time_sec", 0.0)))
	_draw_speed_plot(speed_rect, end_time, font)
	_draw_force_plot(force_rect, end_time, font)
	_draw_heat_plot(heat_rect, end_time, font)


func _draw_speed_plot(rect: Rect2, end_time: float, font: Font) -> void:
	var maximum := 0.5
	for sample in selected_record.samples:
		maximum = maxf(maximum, float(sample.get("speed_mps", 0.0)))
	maximum *= 1.08
	_draw_plot_frame(rect, "速度  m/s", "%.2f" % maximum, font)
	_draw_series(rect, end_time, 0.0, maximum, "speed_mps", PLOT_COLORS.speed)


func _draw_force_plot(rect: Rect2, end_time: float, font: Font) -> void:
	var maximum := 0.5
	for sample in selected_record.samples:
		maximum = maxf(maximum, absf(float(sample.get("drag_force_n", 0.0))))
		maximum = maxf(maximum, absf(float(sample.get("curl_force_n", 0.0))))
	maximum *= 1.08
	_draw_plot_frame(rect, "作用力  N  ·  黄摩擦 / 红弯曲", "±%.2f" % maximum, font, true)
	_draw_series(rect, end_time, -maximum, maximum, "drag_force_n", PLOT_COLORS.drag)
	_draw_series(rect, end_time, -maximum, maximum, "curl_force_n", PLOT_COLORS.curl)


func _draw_heat_plot(rect: Rect2, end_time: float, font: Font) -> void:
	_draw_plot_frame(rect, "冰面热量", "100%", font)
	_draw_series(rect, end_time, 0.0, 1.0, "heat", PLOT_COLORS.heat)


func _draw_plot_frame(rect: Rect2, title: String, maximum_label: String, font: Font, zero_line := false) -> void:
	draw_rect(rect, Color(0.91, 0.97, 0.96, 0.54), true)
	draw_rect(rect, Color("8aa4a0"), false, 1.0)
	var plot_rect := _plot_area(rect)
	for index in range(1, 4):
		var y := plot_rect.position.y + plot_rect.size.y * float(index) / 4.0
		draw_line(Vector2(plot_rect.position.x, y), Vector2(plot_rect.end.x, y), Color(0.42, 0.58, 0.58, 0.18), 1.0)
	if zero_line:
		var zero_y := plot_rect.position.y + plot_rect.size.y * 0.5
		draw_line(Vector2(plot_rect.position.x, zero_y), Vector2(plot_rect.end.x, zero_y), Color(0.20, 0.36, 0.38, 0.42), 1.0)
	draw_string(font, rect.position + Vector2(8.0, 15.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("27474c"))
	draw_string(font, rect.position + Vector2(rect.size.x - 58.0, 15.0), maximum_label, HORIZONTAL_ALIGNMENT_RIGHT, 50.0, 11, Color("60777a"))


func _draw_series(rect: Rect2, end_time: float, minimum: float, maximum: float, field: String, color: Color) -> void:
	if selected_record.samples.size() < 2 or is_equal_approx(minimum, maximum):
		return
	var plot_rect := _plot_area(rect)
	var points := PackedVector2Array()
	for sample in selected_record.samples:
		var time_ratio := clampf(float(sample.get("time_sec", 0.0)) / end_time, 0.0, 1.0)
		var value_ratio := clampf((float(sample.get(field, 0.0)) - minimum) / (maximum - minimum), 0.0, 1.0)
		points.append(Vector2(
			plot_rect.position.x + plot_rect.size.x * time_ratio,
			plot_rect.end.y - plot_rect.size.y * value_ratio
		))
	if points.size() >= 2:
		draw_polyline(points, color, 2.0, true)


func _plot_area(rect: Rect2) -> Rect2:
	return Rect2(
		rect.position + Vector2(6.0, LABEL_HEIGHT + 4.0),
		Vector2(rect.size.x - 12.0, maxf(8.0, rect.size.y - LABEL_HEIGHT - 10.0))
	)
