extends Node
class_name CurlingAudio

@onready var ui_player: AudioStreamPlayer = $Ui
@onready var impact_player: AudioStreamPlayer = $Impact
@onready var sweep_player: AudioStreamPlayer = $Sweep

var _sweep_stream: AudioStreamWAV


func _ready() -> void:
	ui_player.stream = _make_tone(620.0, 0.08, 0.28)
	impact_player.stream = _make_impact()
	_sweep_stream = _make_noise(0.35, true)
	sweep_player.stream = _sweep_stream


func play_ui() -> void:
	ui_player.pitch_scale = 1.0
	ui_player.play()


func play_launch() -> void:
	ui_player.pitch_scale = 0.62
	ui_player.play()


func play_countdown() -> void:
	ui_player.pitch_scale = 1.45
	ui_player.play()


func play_score() -> void:
	ui_player.pitch_scale = 0.82
	ui_player.play()


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
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = stream_buffer.data_array
	return stream


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

