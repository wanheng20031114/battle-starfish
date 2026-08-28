extends Node
class_name CurlingAudio

@onready var ui_player: AudioStreamPlayer = $Ui
@onready var launch_player: AudioStreamPlayer = $Launch
@onready var countdown_player: AudioStreamPlayer = $Countdown
@onready var result_player: AudioStreamPlayer = $Result
@onready var alert_player: AudioStreamPlayer = $Alert
@onready var impact_player: AudioStreamPlayer = $Impact
@onready var sweep_player: AudioStreamPlayer = $Sweep

var _sweep_stream: AudioStreamWAV


func _ready() -> void:
	ui_player.stream = _make_tone(620.0, 0.08, 0.28)
	launch_player.stream = _make_launch()
	countdown_player.stream = _make_countdown_tone()
	result_player.stream = _make_score_chime()
	alert_player.stream = _make_rule_alert()
	impact_player.stream = _make_impact()
	_sweep_stream = _make_noise(0.35, true)
	sweep_player.stream = _sweep_stream


func play_ui() -> void:
	ui_player.pitch_scale = 1.0
	ui_player.play()


func play_launch() -> void:
	launch_player.pitch_scale = 1.0
	launch_player.play()


func play_countdown(seconds_remaining: int) -> void:
	var normalized_second := clampi(seconds_remaining, 1, 10)
	var urgency := float(10 - normalized_second) / 9.0
	countdown_player.pitch_scale = countdown_pitch_for_second(normalized_second)
	countdown_player.volume_db = lerpf(-9.0, -5.5, urgency)
	countdown_player.play()


static func countdown_pitch_for_second(seconds_remaining: int) -> float:
	var normalized_second := clampi(seconds_remaining, 1, 10)
	return lerpf(0.94, 1.32, float(10 - normalized_second) / 9.0)


func play_score() -> void:
	result_player.pitch_scale = 1.0
	result_player.play()


func play_rule_warning() -> void:
	alert_player.pitch_scale = 1.0
	alert_player.volume_db = -7.0
	alert_player.play()


func play_stone_out() -> void:
	alert_player.pitch_scale = 0.72
	alert_player.volume_db = -11.0
	alert_player.play()


func play_impact(relative_speed_px: float) -> void:
	impact_player.volume_db = linear_to_db(clampf(relative_speed_px / 350.0, 0.08, 1.0))
	impact_player.pitch_scale = lerpf(0.85, 1.12, clampf(relative_speed_px / 500.0, 0.0, 1.0))
	impact_player.play()


func set_sweeping(active: bool, intensity: float = 0.0) -> void:
	if active:
		sweep_player.volume_db = linear_to_db(clampf(0.08 + intensity * 0.42, 0.01, 0.5))
		if not sweep_player.playing:
			sweep_player.play()
	elif sweep_player.playing:
		sweep_player.stop()


func stop_all() -> void:
	for player in [
		ui_player,
		launch_player,
		countdown_player,
		result_player,
		alert_player,
		impact_player,
		sweep_player,
	]:
		(player as AudioStreamPlayer).stop()


func _make_tone(frequency: float, duration: float, amplitude: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := maxi(1, roundi(duration * sample_rate))
	var stream_buffer := StreamPeerBuffer.new()
	stream_buffer.big_endian = false
	for index in range(sample_count):
		var time := float(index) / float(sample_rate)
		var envelope := pow(1.0 - float(index) / float(sample_count), 2.0)
		var sample := sin(TAU * frequency * time) * amplitude * envelope
		stream_buffer.put_16(clampi(roundi(sample * 32767.0), -32767, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = stream_buffer.data_array
	return stream


func _make_launch() -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := roundi(0.24 * sample_rate)
	var stream_buffer := StreamPeerBuffer.new()
	stream_buffer.big_endian = false
	var seed_value := 0x13579BDF
	var filtered_noise := 0.0
	for index in range(sample_count):
		var time := float(index) / float(sample_rate)
		var thump_envelope := exp(-time * 17.0)
		var scrape_envelope := clampf(time / 0.025, 0.0, 1.0) * exp(-time * 9.5)
		seed_value = int((seed_value * 1103515245 + 12345) & 0x7FFFFFFF)
		var noise := float(seed_value % 65536) / 32768.0 - 1.0
		filtered_noise = lerpf(filtered_noise, noise, 0.12)
		var thump := sin(TAU * (92.0 - time * 95.0) * time) * thump_envelope * 0.42
		var scrape := filtered_noise * scrape_envelope * 0.16
		stream_buffer.put_16(clampi(roundi((thump + scrape) * 32767.0), -32767, 32767))
	return _stream_from_buffer(stream_buffer, sample_rate)


func _make_countdown_tone() -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := roundi(0.11 * sample_rate)
	var stream_buffer := StreamPeerBuffer.new()
	stream_buffer.big_endian = false
	for index in range(sample_count):
		var time := float(index) / float(sample_rate)
		var attack := clampf(time / 0.004, 0.0, 1.0)
		var envelope := attack * exp(-time * 25.0)
		var tone := sin(TAU * 880.0 * time) + 0.18 * sin(TAU * 1320.0 * time)
		stream_buffer.put_16(clampi(roundi(tone * envelope * 0.3 * 32767.0), -32767, 32767))
	return _stream_from_buffer(stream_buffer, sample_rate)


func _make_score_chime() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.58
	var sample_count := roundi(duration * sample_rate)
	var stream_buffer := StreamPeerBuffer.new()
	stream_buffer.big_endian = false
	var frequencies := [523.25, 659.25, 783.99]
	var starts := [0.0, 0.14, 0.28]
	for index in range(sample_count):
		var time := float(index) / float(sample_rate)
		var sample := 0.0
		for note_index in range(frequencies.size()):
			var local_time := time - float(starts[note_index])
			if local_time < 0.0:
				continue
			var envelope := exp(-local_time * 6.5)
			var frequency := float(frequencies[note_index])
			sample += sin(TAU * frequency * local_time) * envelope * 0.15
			sample += sin(TAU * frequency * 2.0 * local_time) * envelope * 0.025
		stream_buffer.put_16(clampi(roundi(sample * 32767.0), -32767, 32767))
	return _stream_from_buffer(stream_buffer, sample_rate)


func _make_rule_alert() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.34
	var sample_count := roundi(duration * sample_rate)
	var stream_buffer := StreamPeerBuffer.new()
	stream_buffer.big_endian = false
	for index in range(sample_count):
		var time := float(index) / float(sample_rate)
		var segment_time := fmod(time, 0.17)
		var frequency := 440.0 if time < 0.17 else 330.0
		var envelope := clampf(segment_time / 0.004, 0.0, 1.0) * exp(-segment_time * 15.0)
		var tone := sin(TAU * frequency * segment_time) + 0.22 * sin(TAU * frequency * 2.0 * segment_time)
		stream_buffer.put_16(clampi(roundi(tone * envelope * 0.27 * 32767.0), -32767, 32767))
	return _stream_from_buffer(stream_buffer, sample_rate)


func _make_impact() -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := roundi(0.16 * sample_rate)
	var stream_buffer := StreamPeerBuffer.new()
	stream_buffer.big_endian = false
	for index in range(sample_count):
		var time := float(index) / float(sample_rate)
		var envelope := exp(-time * 28.0)
		var metallic := sin(TAU * 390.0 * time) + 0.45 * sin(TAU * 735.0 * time)
		stream_buffer.put_16(clampi(roundi(metallic * envelope * 0.32 * 32767.0), -32767, 32767))
	return _stream_from_buffer(stream_buffer, sample_rate)


func _make_noise(duration: float, looped: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := roundi(duration * sample_rate)
	var stream_buffer := StreamPeerBuffer.new()
	stream_buffer.big_endian = false
	var seed_value := 0x41C64E6D
	var previous := 0.0
	for index in range(sample_count):
		seed_value = int((seed_value * 1103515245 + 12345) & 0x7FFFFFFF)
		var noise := (float(seed_value % 65536) / 32768.0 - 1.0) * 0.24
		previous = lerpf(previous, noise, 0.18)
		var pulse := 0.65 + 0.35 * sin(TAU * 7.0 * float(index) / float(sample_rate))
		stream_buffer.put_16(clampi(roundi(previous * pulse * 32767.0), -32767, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = stream_buffer.data_array
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = sample_count
	return stream


func _stream_from_buffer(stream_buffer: StreamPeerBuffer, sample_rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = stream_buffer.data_array
	return stream
