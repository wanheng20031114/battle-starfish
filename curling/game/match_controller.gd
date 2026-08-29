extends Node2D
class_name CurlingMatchController

const CurlingAimGuideScript := preload("res://curling/ui/aim_guide.gd")

signal state_changed
signal hud_changed(data: Dictionary)
signal aim_preview_intent(direction: Vector2, power: float, spin: float)
signal aim_preview_clear_intent
signal throw_intent(direction: Vector2, power: float, spin: float)
signal sweep_intent(from_world: Vector2, to_world: Vector2, delta_sec: float, estimated_host_ms: int)
signal snapshot_ready(payload: PackedByteArray)
signal gameplay_event(event: Dictionary)
signal collision_feedback(relative_speed_px: float)
signal match_finished(result: Dictionary)

enum Phase {
	IDLE,
	TACTICS,
	AIMING,
	MOVING,
	SCORING,
	RESULT,
}

const OVERVIEW_CAMERA_ZOOM := 0.24
const GAMEPLAY_CAMERA_ZOOM := 1.16
const HOUSE_CAMERA_ZOOM := 1.12
const CAMERA_PAN_SPEED_PXPS := 1100.0
const CAMERA_X_LIMIT_PX := CurlingConstants.TEE_FROM_CENTER_PX + CurlingConstants.HACK_FROM_TEE_PX
const REMOTE_AIM_STALE_MS := 650

@onready var heat_grid: CurlingHeatGrid = $HeatGrid
@onready var aim_guide: CurlingAimGuideScript = $AimGuide
@onready var game_camera: Camera2D = $Camera2D
@onready var stones_root: Node2D = $Stones

var phase := Phase.IDLE
var authoritative := true
var local_player_id := 1
var players: Dictionary = {}
var total_regular_ends := 1
var scheduled_ends := 1
var current_end := 0
var delivered_count := 0
var hammer_team := CurlingConstants.TEAM_RED
var direction := 1
var red_score := 0
var blue_score := 0
var end_scores: Array[Dictionary] = []
var lineups := {
	CurlingConstants.TEAM_RED: [0, 0, 0, 0, 0, 0, 0, 0],
	CurlingConstants.TEAM_BLUE: [0, 0, 0, 0, 0, 0, 0, 0],
}
var team_locked := {
	CurlingConstants.TEAM_RED: false,
	CurlingConstants.TEAM_BLUE: false,
}
var tactics_confirmed: Dictionary = {}
var phase_time_remaining := 0.0
var active_stone_id := -1
var active_thrower_id := 0
var active_team := CurlingConstants.TEAM_NONE
var protected_stone_mask := 0
var state_sequence := 0
var shot_id := 0
var reduced_motion := false
var local_input_locked := false
var final_result: Dictionary = {}

var _stones: Array[CurlingStone] = []
var _rng := RandomNumberGenerator.new()
var _settle_elapsed := 0.0
var _score_delay := 0.0
var _bot_delay := 0.0
var _snapshot_accumulator := 0.0
var _last_aim_preview_ms := 0
var _dragging := false
var _drag_origin_screen := Vector2.ZERO
var _drag_current_screen := Vector2.ZERO
var _drag_aim_direction := Vector2.RIGHT
var _drag_power_adjustment := 0.0
var _current_spin := 0.0
var _aim_preview_visible := false
var _aim_preview_from_local := false
var _aim_preview_direction := Vector2.RIGHT
var _aim_preview_power := 0.0
var _aim_preview_spin := 0.0
var _aim_preview_last_update_ms := 0
var _sweep_down := false
var _last_sweep_world := Vector2.ZERO
var _last_sweep_ms := 0
var _active_touched_other := false
var _pre_shot_state: Array[Dictionary] = []
var _last_remote_state_sequence := -1
var _last_remote_shot_id := -1
var _last_sweep_accept_ms_by_player: Dictionary = {}
var _camera_phase := Phase.IDLE
var _manual_camera_x := 0.0
var _camera_left_held := false
var _camera_right_held := false


func _ready() -> void:
	for child in stones_root.get_children():
		if child is CurlingStone:
			var stone := child as CurlingStone
			stone.heat_grid = heat_grid
			stone.stone_collision.connect(_on_stone_collision)
			_stones.append(stone)
	_stones.sort_custom(func(a: CurlingStone, b: CurlingStone) -> bool: return a.stone_id < b.stone_id)
	aim_guide.hide_preview()
	visible = false
	set_process(true)
	set_physics_process(true)


func start_match(
	player_list: Array[Dictionary],
	ends: int,
	local_id: int,
	is_authoritative: bool,
	session_seed: int
) -> void:
	players.clear()
	for player in player_list:
		players[int(player.get("id", 0))] = player.duplicate(true)
	local_player_id = local_id
	authoritative = is_authoritative
	_reset_transient_match_state()
	total_regular_ends = ends if [1, 2, 4].has(ends) else 1
	scheduled_ends = total_regular_ends
	current_end = 0
	delivered_count = 0
	red_score = 0
	blue_score = 0
	end_scores.clear()
	final_result.clear()
	_rng.seed = session_seed
	hammer_team = CurlingConstants.TEAM_RED if _rng.randi() % 2 == 0 else CurlingConstants.TEAM_BLUE
	direction = 1 if _rng.randi() % 2 == 0 else -1
	state_sequence = 1
	shot_id = 0
	visible = true
	game_camera.enabled = true
	for stone in _stones:
		stone.authoritative = authoritative
		stone.remove_from_play()
	_begin_tactics()
	_manual_camera_x = CurlingConstants.tee_position(direction).x
	game_camera.position = Vector2(_manual_camera_x, 0.0)
	game_camera.zoom = Vector2.ONE * HOUSE_CAMERA_ZOOM
	_camera_phase = phase


func reset_to_idle() -> void:
	_reset_transient_match_state()
	state_sequence = 0
	shot_id = 0
	visible = false
	game_camera.enabled = false
	for stone in _stones:
		stone.remove_from_play()


func _reset_transient_match_state() -> void:
	phase = Phase.IDLE
	phase_time_remaining = 0.0
	active_stone_id = -1
	active_thrower_id = 0
	active_team = CurlingConstants.TEAM_NONE
	_set_guard_protection_mask(0)
	local_input_locked = false
	_settle_elapsed = 0.0
	_score_delay = 0.0
	_bot_delay = 0.0
	_snapshot_accumulator = 0.0
	_last_aim_preview_ms = 0
	_dragging = false
	_drag_aim_direction = Vector2.RIGHT
	_drag_power_adjustment = 0.0
	_current_spin = 0.0
	_aim_preview_visible = false
	_aim_preview_from_local = false
	_aim_preview_direction = Vector2.RIGHT
	_aim_preview_power = 0.0
	_aim_preview_spin = 0.0
	_aim_preview_last_update_ms = 0
	_sweep_down = false
	_last_sweep_world = Vector2.ZERO
	_last_sweep_ms = 0
	_active_touched_other = false
	_pre_shot_state.clear()
	_last_remote_state_sequence = -1
	_last_remote_shot_id = -1
	_last_sweep_accept_ms_by_player.clear()
	_camera_phase = Phase.IDLE
	_manual_camera_x = 0.0
	_camera_left_held = false
	_camera_right_held = false
	aim_guide.hide_preview()
	heat_grid.clear()


func _process(delta: float) -> void:
	_expire_remote_aim_preview()
	_send_local_aim_preview_heartbeat()
	if phase == Phase.IDLE or phase == Phase.RESULT:
		_process_camera(delta)
		return
	_process_camera(delta)
	if not authoritative:
		_process_remote_phase_timer(delta)
		if phase == Phase.AIMING and not local_input_locked:
			_update_drag_precision_from_keys(delta)
			_update_spin_from_keys(delta)
		_emit_hud()
		return
	match phase:
		Phase.TACTICS:
			phase_time_remaining = maxf(0.0, phase_time_remaining - delta)
			_bot_delay -= delta
			if _bot_delay <= 0.0:
				_confirm_demo_bots()
			if phase_time_remaining <= 0.0:
				_force_lock_all_teams()
		Phase.AIMING:
			phase_time_remaining = maxf(0.0, phase_time_remaining - delta)
			if not local_input_locked:
				_update_drag_precision_from_keys(delta)
				_update_spin_from_keys(delta)
			_bot_delay -= delta
			if _is_bot(active_thrower_id) and _bot_delay <= 0.0:
				_launch_bot_throw()
			elif phase_time_remaining <= 0.0:
				_finish_empty_throw("瞄准超时，本手记为空投")
		Phase.SCORING:
			_score_delay -= delta
			if _score_delay <= 0.0:
				_advance_after_score()
	_emit_hud()


func _process_remote_phase_timer(delta: float) -> void:
	match phase:
		Phase.TACTICS, Phase.AIMING:
			phase_time_remaining = maxf(0.0, phase_time_remaining - delta)


func _physics_process(delta: float) -> void:
	if not authoritative or phase == Phase.IDLE or phase == Phase.RESULT:
		return
	_snapshot_accumulator += delta
	if _snapshot_accumulator >= 1.0 / CurlingConstants.SNAPSHOT_HZ:
		_snapshot_accumulator = fmod(_snapshot_accumulator, 1.0 / CurlingConstants.SNAPSHOT_HZ)
		var payload := CurlingStoneSnapshotCodec.encode_snapshot(
			Time.get_ticks_msec(), state_sequence, shot_id, get_stone_states()
		)
		if not payload.is_empty():
			snapshot_ready.emit(payload)
	if phase != Phase.MOVING:
		return
	_remove_out_of_play_stones()
	if _all_stones_below_stop_speed():
		_settle_elapsed += delta
		if _settle_elapsed >= CurlingConstants.SETTLE_TIME_SEC:
			_resolve_shot()
	else:
		_settle_elapsed = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not visible or local_input_locked:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if phase == Phase.AIMING and active_thrower_id == local_player_id:
			if mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var wheel_direction := 1.0 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				_adjust_spin(wheel_direction * CurlingConstants.SPIN_WHEEL_STEP_RADPS, true)
				get_viewport().set_input_as_handled()
				return
			elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
				if mouse_event.pressed and _can_begin_drag(mouse_event.position):
					_dragging = true
					_drag_origin_screen = mouse_event.position
					_drag_current_screen = mouse_event.position
					_drag_aim_direction = Vector2(float(direction), 0.0)
					_drag_power_adjustment = 0.0
					_camera_left_held = false
					_camera_right_held = false
					_refresh_local_aim_preview(true)
					get_viewport().set_input_as_handled()
				elif not mouse_event.pressed and _dragging:
					if not mouse_event.position.is_equal_approx(_drag_current_screen):
						_drag_current_screen = mouse_event.position
						_update_drag_aim_from_pointer(mouse_event.position)
					_release_local_throw()
					get_viewport().set_input_as_handled()
			elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_drag()
		if phase == Phase.MOVING and _local_team() == active_team and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_sweep_down = mouse_event.pressed
			_last_sweep_world = viewport_to_world(mouse_event.position)
			_last_sweep_ms = Time.get_ticks_msec()
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if phase == Phase.AIMING and _dragging:
			_drag_current_screen = motion.position
			_update_drag_aim_from_pointer(motion.position)
			_refresh_local_aim_preview()
		elif phase == Phase.MOVING and _sweep_down and _local_team() == active_team:
			_submit_sweep_motion(viewport_to_world(motion.position))
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if _dragging and phase == Phase.AIMING and active_thrower_id == local_player_id and _is_drag_precision_key(key_event):
			_camera_left_held = false
			_camera_right_held = false
			get_viewport().set_input_as_handled()
			return
		var camera_direction := _camera_key_direction(key_event)
		if camera_direction != 0:
			if camera_direction < 0:
				_camera_left_held = key_event.pressed and phase not in [Phase.IDLE, Phase.MOVING]
			else:
				_camera_right_held = key_event.pressed and phase not in [Phase.IDLE, Phase.MOVING]
			if phase not in [Phase.IDLE, Phase.MOVING]:
				get_viewport().set_input_as_handled()
			return
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			_cancel_drag()


func set_local_input_locked(locked: bool) -> void:
	local_input_locked = locked
	if not locked:
		return
	_cancel_drag()
	_sweep_down = false
	_camera_left_held = false
	_camera_right_held = false
	_emit_hud()


func toggle_lineup_slot(player_id: int, slot_index: int) -> bool:
	if not authoritative or phase != Phase.TACTICS or slot_index < 0 or slot_index >= CurlingConstants.STONES_PER_TEAM:
		return false
	var player_variant: Variant = players.get(player_id)
	if typeof(player_variant) != TYPE_DICTIONARY:
		return false
	var team := int((player_variant as Dictionary).get("team", CurlingConstants.TEAM_NONE))
	if bool(team_locked.get(team, false)) or bool(tactics_confirmed.get(player_id, false)):
		return false
	var team_lineup: Array = lineups[team]
	var owner := int(team_lineup[slot_index])
	if owner != 0 and owner != player_id:
		return false
	team_lineup[slot_index] = 0 if owner == player_id else player_id
	lineups[team] = team_lineup
	_mark_state_changed()
	return true


func set_tactics_confirmed(player_id: int, confirmed: bool) -> bool:
	if not authoritative or phase != Phase.TACTICS or not players.has(player_id):
		return false
	var team := int((players[player_id] as Dictionary).get("team", CurlingConstants.TEAM_NONE))
	if bool(team_locked.get(team, false)):
		return false
	tactics_confirmed[player_id] = confirmed
	if _all_connected_team_members_confirmed(team):
		_lock_team(team)
	if phase == Phase.TACTICS:
		_mark_state_changed()
	return true


func host_apply_throw(
	player_id: int,
	aim_direction: Vector2,
	power: float,
	spin: float,
	expected_shot_id: int = -1,
) -> bool:
	if (
		not authoritative
		or phase != Phase.AIMING
		or player_id != active_thrower_id
		or (expected_shot_id >= 0 and expected_shot_id != shot_id)
		or not aim_direction.is_finite()
		or aim_direction.length_squared() < 0.9
		or not is_finite(power)
		or power <= 0.0
		or power > 1.0
		or not is_finite(spin)
		or absf(spin) > CurlingConstants.MAX_SPIN_RADPS + 0.001
	):
		return false
	_launch_active_stone(aim_direction.normalized(), power, spin)
	return true


func host_apply_sweep(
	player_id: int,
	from_world: Vector2,
	to_world: Vector2,
	delta_sec: float,
	sample_host_ms: int,
	expected_shot_id: int = -1,
) -> bool:
	if (
		not authoritative
		or phase != Phase.MOVING
		or not players.has(player_id)
		or (expected_shot_id >= 0 and expected_shot_id != shot_id)
		or not from_world.is_finite()
		or not to_world.is_finite()
		or delta_sec <= 0.0
		or delta_sec > 0.25
		or absf(from_world.x) > CurlingConstants.HALF_SHEET_LENGTH_PX + 300.0
		or absf(to_world.x) > CurlingConstants.HALF_SHEET_LENGTH_PX + 300.0
		or absf(from_world.y) > CurlingConstants.HALF_SHEET_WIDTH_PX + 300.0
		or absf(to_world.y) > CurlingConstants.HALF_SHEET_WIDTH_PX + 300.0
	):
		return false
	var player_team := int((players[player_id] as Dictionary).get("team", CurlingConstants.TEAM_NONE))
	if player_team != active_team or not bool((players[player_id] as Dictionary).get("connected", true)):
		return false
	var now_ms := Time.get_ticks_msec()
	if sample_host_ms < now_ms - CurlingConstants.SWEEP_SAMPLE_MAX_AGE_MS or sample_host_ms > now_ms + CurlingConstants.SWEEP_SAMPLE_MAX_FUTURE_MS:
		return false
	var previous_ms := int(_last_sweep_accept_ms_by_player.get(player_id, now_ms - 50))
	var elapsed_ms := now_ms - previous_ms
	if elapsed_ms < roundi(1000.0 / CurlingConstants.HEAT_PATH_HZ):
		return false
	_last_sweep_accept_ms_by_player[player_id] = now_ms
	var accepted_delta := minf(delta_sec, float(elapsed_ms) / 1000.0)
	return heat_grid.deposit_segment(from_world, to_world, accepted_delta, sample_host_ms) > 0.0


func apply_remote_state(state: Dictionary) -> bool:
	if authoritative:
		return false
	var previous_phase := phase
	var previous_shot_id := shot_id
	var previous_thrower_id := active_thrower_id
	var incoming_sequence := int(state.get("state_sequence", -1))
	if incoming_sequence < state_sequence:
		return false
	state_sequence = incoming_sequence
	phase = int(state.get("phase", Phase.IDLE))
	phase_time_remaining = float(state.get("phase_time_remaining", 0.0))
	current_end = int(state.get("current_end", 0))
	scheduled_ends = int(state.get("scheduled_ends", 1))
	total_regular_ends = int(state.get("total_regular_ends", 1))
	delivered_count = int(state.get("delivered_count", 0))
	hammer_team = int(state.get("hammer_team", CurlingConstants.TEAM_RED))
	direction = int(state.get("direction", 1))
	red_score = int(state.get("red_score", 0))
	blue_score = int(state.get("blue_score", 0))
	active_stone_id = int(state.get("active_stone_id", -1))
	active_thrower_id = int(state.get("active_thrower_id", 0))
	active_team = int(state.get("active_team", CurlingConstants.TEAM_NONE))
	_set_guard_protection_mask(int(state.get("protected_stone_mask", 0)))
	shot_id = int(state.get("shot_id", 0))
	if shot_id != previous_shot_id or active_thrower_id != previous_thrower_id:
		_current_spin = 0.0
		_cancel_drag(false)
		_sweep_down = false
		heat_grid.clear()
	if state.has("players"):
		players = state["players"].duplicate(true)
	if state.has("lineups"):
		lineups = state["lineups"].duplicate(true)
	_apply_remote_stone_ownership()
	if phase != Phase.AIMING or _local_team() != active_team:
		_clear_aim_preview(false)
	team_locked = state.get("team_locked", team_locked).duplicate(true)
	tactics_confirmed = state.get("tactics_confirmed", tactics_confirmed).duplicate(true)
	final_result = state.get("final_result", {}).duplicate(true)
	visible = phase != Phase.IDLE
	game_camera.enabled = visible
	state_changed.emit()
	_emit_hud()
	if phase == Phase.RESULT and previous_phase != Phase.RESULT and not final_result.is_empty():
		match_finished.emit(final_result)
	return true


func _apply_remote_stone_ownership() -> void:
	for stone_index in range(_stones.size()):
		var team := CurlingConstants.TEAM_RED if stone_index < CurlingConstants.STONES_PER_TEAM else CurlingConstants.TEAM_BLUE
		var slot := stone_index % CurlingConstants.STONES_PER_TEAM
		var team_lineup: Array = lineups.get(team, [])
		if slot >= team_lineup.size():
			continue
		var owner_id := int(team_lineup[slot])
		if owner_id <= 0:
			continue
		_stones[stone_index].team = team
		_stones[stone_index].owner_player_id = owner_id
		_stones[stone_index].owner_color = _player_color(owner_id)
		_stones[stone_index].queue_redraw()


func export_state_for(viewer_team: int = CurlingConstants.TEAM_NONE) -> Dictionary:
	var exported_lineups := lineups.duplicate(true)
	if phase == Phase.TACTICS and not (bool(team_locked[CurlingConstants.TEAM_RED]) and bool(team_locked[CurlingConstants.TEAM_BLUE])):
		if viewer_team == CurlingConstants.TEAM_RED:
			exported_lineups[CurlingConstants.TEAM_BLUE] = [-1, -1, -1, -1, -1, -1, -1, -1]
		elif viewer_team == CurlingConstants.TEAM_BLUE:
			exported_lineups[CurlingConstants.TEAM_RED] = [-1, -1, -1, -1, -1, -1, -1, -1]
		else:
			exported_lineups = {
				CurlingConstants.TEAM_RED: [-1, -1, -1, -1, -1, -1, -1, -1],
				CurlingConstants.TEAM_BLUE: [-1, -1, -1, -1, -1, -1, -1, -1],
			}
	return {
		"state_sequence": state_sequence,
		"phase": phase,
		"phase_time_remaining": phase_time_remaining,
		"current_end": current_end,
		"scheduled_ends": scheduled_ends,
		"total_regular_ends": total_regular_ends,
		"delivered_count": delivered_count,
		"hammer_team": hammer_team,
		"direction": direction,
		"red_score": red_score,
		"blue_score": blue_score,
		"end_scores": end_scores.duplicate(true),
		"active_stone_id": active_stone_id,
		"active_thrower_id": active_thrower_id,
		"active_team": active_team,
		"protected_stone_mask": protected_stone_mask,
		"shot_id": shot_id,
		"players": players.duplicate(true),
		"lineups": exported_lineups,
		"team_locked": team_locked.duplicate(true),
		"tactics_confirmed": tactics_confirmed.duplicate(true),
		"final_result": final_result.duplicate(true),
	}


func apply_remote_snapshot(payload: PackedByteArray) -> bool:
	if authoritative:
		return false
	var decoded := CurlingStoneSnapshotCodec.decode_snapshot(payload)
	if not bool(decoded.get("valid", false)):
		return false
	var incoming_sequence := int(decoded.get("state_sequence", -1))
	var incoming_shot := int(decoded.get("shot_id", -1))
	if (
		incoming_sequence != state_sequence
		or incoming_sequence < _last_remote_state_sequence
		or incoming_shot != shot_id
	):
		return false
	var force_snap := incoming_sequence != _last_remote_state_sequence or incoming_shot != _last_remote_shot_id
	_last_remote_state_sequence = incoming_sequence
	_last_remote_shot_id = incoming_shot
	var snapshots: Array = decoded.get("stones", [])
	for stone_index in range(mini(snapshots.size(), _stones.size())):
		_stones[stone_index].apply_remote_snapshot(snapshots[stone_index], force_snap, stone_index == active_stone_id)
	return true


func get_stone_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for stone in _stones:
		states.append(stone.export_state())
	return states


func get_protected_stone_count() -> int:
	var count := 0
	for stone_index in range(_stones.size()):
		if protected_stone_mask & (1 << stone_index):
			count += 1
	return count


func _set_guard_protection_mask(next_mask: int) -> void:
	var valid_mask := (1 << _stones.size()) - 1 if not _stones.is_empty() else 0
	protected_stone_mask = next_mask & valid_mask
	for stone in _stones:
		stone.set_guard_protected(bool(protected_stone_mask & (1 << stone.stone_id)))


func _refresh_guard_protection_for_current_throw() -> void:
	var next_mask := 0
	for protected_id in CurlingRules.protected_guard_ids(
		_pre_shot_state,
		active_team,
		delivered_count,
		direction
	):
		if protected_id >= 0 and protected_id < _stones.size():
			next_mask |= 1 << protected_id
	_set_guard_protection_mask(next_mask)


func get_local_team() -> int:
	return _local_team()


func get_phase_name() -> String:
	match phase:
		Phase.TACTICS: return "战术分配"
		Phase.AIMING: return "瞄准"
		Phase.MOVING: return "投壶进行中"
		Phase.SCORING: return "计分"
		Phase.RESULT: return "比赛结束"
		_: return "等待"


func set_player_connected(player_id: int, connected: bool) -> void:
	if not authoritative or not players.has(player_id):
		return
	var player: Dictionary = players[player_id]
	player["connected"] = connected
	players[player_id] = player
	if not connected and phase in [Phase.TACTICS, Phase.AIMING, Phase.MOVING]:
		var team := int(player.get("team", CurlingConstants.TEAM_NONE))
		var remaining: Array[int] = []
		var join_order := {}
		for candidate_id_variant in players.keys():
			var candidate_id := int(candidate_id_variant)
			var candidate: Dictionary = players[candidate_id]
			if (
				candidate_id != player_id
				and int(candidate.get("team", CurlingConstants.TEAM_NONE)) == team
				and bool(candidate.get("connected", true))
			):
				remaining.append(candidate_id)
				join_order[candidate_id] = int(candidate.get("join_order", 0))
		var typed_lineup: Array[int] = []
		for owner_variant in lineups.get(team, []):
			typed_lineup.append(int(owner_variant))
		if remaining.is_empty():
			# 队伍最后一名在线玩家断线时保留其位置；重连后仍可接回剩余倒计时与未来投壶。
			lineups[team] = CurlingLineupAllocator.fill_empty_slots(
				typed_lineup,
				[player_id],
				{player_id: int(player.get("join_order", 0))}
			)
		else:
			var first_unplayed := _team_slots_already_played(team)
			lineups[team] = CurlingLineupAllocator.redistribute_player_slots(
				typed_lineup, player_id, remaining, join_order, first_unplayed
			)
			if phase == Phase.AIMING and active_thrower_id == player_id:
				var current_slot := floori(float(delivered_count) / 2.0)
				active_thrower_id = int((lineups[team] as Array)[current_slot])
				if active_stone_id >= 0 and active_thrower_id > 0:
					_stones[active_stone_id].owner_player_id = active_thrower_id
					_stones[active_stone_id].owner_color = _player_color(active_thrower_id)
					_stones[active_stone_id].queue_redraw()
	_mark_state_changed()


func remap_player_id(old_player_id: int, new_player_id: int) -> bool:
	if not authoritative or old_player_id == new_player_id or not players.has(old_player_id) or players.has(new_player_id):
		return false
	var player: Dictionary = players[old_player_id]
	players.erase(old_player_id)
	player["id"] = new_player_id
	player["connected"] = true
	players[new_player_id] = player
	for team in [CurlingConstants.TEAM_RED, CurlingConstants.TEAM_BLUE]:
		var team_lineup: Array = lineups[team]
		for slot_index in range(team_lineup.size()):
			if int(team_lineup[slot_index]) == old_player_id:
				team_lineup[slot_index] = new_player_id
		lineups[team] = team_lineup
	if tactics_confirmed.has(old_player_id):
		tactics_confirmed[new_player_id] = bool(tactics_confirmed[old_player_id])
		tactics_confirmed.erase(old_player_id)
	if active_thrower_id == old_player_id:
		active_thrower_id = new_player_id
	for stone in _stones:
		if stone.owner_player_id == old_player_id:
			stone.owner_player_id = new_player_id
	_mark_state_changed()
	return true


func remove_player(player_id: int) -> void:
	if not authoritative or not players.has(player_id):
		return
	players.erase(player_id)
	tactics_confirmed.erase(player_id)
	_mark_state_changed()


func force_forfeit(winning_team: int, reason: String) -> void:
	if not authoritative or phase == Phase.RESULT:
		return
	phase = Phase.RESULT
	_set_guard_protection_mask(0)
	final_result = {
		"winner": winning_team,
		"red_score": red_score,
		"blue_score": blue_score,
		"end_scores": end_scores.duplicate(true),
		"forfeit": true,
		"reason": reason,
	}
	gameplay_event.emit({"type": "forfeit", "winner": winning_team, "reason": reason})
	_mark_state_changed()
	match_finished.emit(final_result)


func player_name(player_id: int) -> String:
	var player_variant: Variant = players.get(player_id)
	return str((player_variant as Dictionary).get("nickname", "玩家")) if typeof(player_variant) == TYPE_DICTIONARY else "玩家"


func _begin_tactics() -> void:
	phase = Phase.TACTICS
	phase_time_remaining = CurlingConstants.TACTICS_TIME_SEC
	delivered_count = 0
	active_stone_id = -1
	active_thrower_id = 0
	active_team = CurlingConstants.TEAM_NONE
	_set_guard_protection_mask(0)
	lineups = {
		CurlingConstants.TEAM_RED: [0, 0, 0, 0, 0, 0, 0, 0],
		CurlingConstants.TEAM_BLUE: [0, 0, 0, 0, 0, 0, 0, 0],
	}
	team_locked = {CurlingConstants.TEAM_RED: false, CurlingConstants.TEAM_BLUE: false}
	tactics_confirmed.clear()
	for player_id_variant in players.keys():
		tactics_confirmed[int(player_id_variant)] = false
	for stone in _stones:
		stone.remove_from_play()
	heat_grid.clear()
	_last_sweep_accept_ms_by_player.clear()
	_clear_aim_preview(false)
	_bot_delay = 0.7
	_mark_state_changed()


func _team_slots_already_played(team: int) -> int:
	var first_team := CurlingConstants.other_team(hammer_team)
	var played := 0
	for slot in range(CurlingConstants.STONES_PER_TEAM):
		var global_throw_index := slot * 2 + (0 if team == first_team else 1)
		if global_throw_index < delivered_count:
			played += 1
	return played


func _confirm_demo_bots() -> void:
	_bot_delay = 9999.0
	for player_id_variant in players.keys():
		var player_id := int(player_id_variant)
		if _is_bot(player_id):
			tactics_confirmed[player_id] = true
	for team in [CurlingConstants.TEAM_RED, CurlingConstants.TEAM_BLUE]:
		if _all_connected_team_members_confirmed(team):
			_lock_team(team)
	if phase == Phase.TACTICS:
		_mark_state_changed()


func _force_lock_all_teams() -> void:
	_lock_team(CurlingConstants.TEAM_RED)
	_lock_team(CurlingConstants.TEAM_BLUE)


func _lock_team(team: int) -> void:
	if bool(team_locked.get(team, false)):
		return
	var team_ids: Array[int] = []
	var join_order := {}
	for player_id_variant in players.keys():
		var player_id := int(player_id_variant)
		var player: Dictionary = players[player_id]
		if int(player.get("team", CurlingConstants.TEAM_NONE)) == team and bool(player.get("connected", true)):
			team_ids.append(player_id)
			join_order[player_id] = int(player.get("join_order", 0))
	var typed_lineup: Array[int] = []
	for owner_variant in lineups[team]:
		typed_lineup.append(int(owner_variant))
	lineups[team] = CurlingLineupAllocator.fill_empty_slots(typed_lineup, team_ids, join_order)
	team_locked[team] = true
	if bool(team_locked[CurlingConstants.TEAM_RED]) and bool(team_locked[CurlingConstants.TEAM_BLUE]):
		_begin_next_throw()


func _begin_next_throw() -> void:
	if delivered_count >= CurlingConstants.STONE_COUNT:
		_score_end()
		return
	var first_team := CurlingConstants.other_team(hammer_team)
	active_team = first_team if delivered_count % 2 == 0 else hammer_team
	var team_slot := floori(float(delivered_count) / 2.0)
	active_thrower_id = int((lineups[active_team] as Array)[team_slot])
	active_stone_id = team_slot if active_team == CurlingConstants.TEAM_RED else CurlingConstants.STONES_PER_TEAM + team_slot
	shot_id = (shot_id + 1) & 0xFFFF
	_pre_shot_state = get_stone_states()
	_refresh_guard_protection_for_current_throw()
	for stone in _stones:
		stone.enable_for_shot()
	var owner_color := _player_color(active_thrower_id)
	var active_stone := _stones[active_stone_id]
	active_stone.team = active_team
	active_stone.prepare_for_delivery(CurlingConstants.hack_position(direction), active_thrower_id, owner_color)
	phase = Phase.AIMING
	phase_time_remaining = CurlingConstants.AIM_TIME_SEC
	_current_spin = 0.0
	_dragging = false
	_drag_aim_direction = Vector2(float(direction), 0.0)
	_drag_power_adjustment = 0.0
	_active_touched_other = false
	_clear_aim_preview(false)
	_bot_delay = 0.9 + _rng.randf_range(0.0, 0.7)
	_mark_state_changed()


func _launch_active_stone(aim_direction: Vector2, power: float, spin: float) -> void:
	var speed := CurlingConstants.throw_speed_for_power(power)
	_stones[active_stone_id].launch(aim_direction, speed, spin)
	phase = Phase.MOVING
	phase_time_remaining = 0.0
	_settle_elapsed = 0.0
	_clear_aim_preview(false)
	heat_grid.clear()
	_last_sweep_accept_ms_by_player.clear()
	gameplay_event.emit({
		"type": "throw_launched",
		"shot_id": shot_id,
		"player_id": active_thrower_id,
		"direction": aim_direction,
		"power": power,
		"spin": spin,
	})
	_mark_state_changed()


func _finish_empty_throw(reason: String) -> void:
	if active_stone_id >= 0:
		_stones[active_stone_id].remove_from_play()
	gameplay_event.emit({"type": "empty_throw", "reason": reason, "player_id": active_thrower_id})
	delivered_count += 1
	_begin_next_throw()


func _resolve_shot() -> void:
	if phase != Phase.MOVING:
		return
	var active_stone := _stones[active_stone_id]
	if active_stone.in_play and not CurlingRules.crossed_far_hog(active_stone.global_position, direction) and not _active_touched_other:
		active_stone.remove_from_play()
		gameplay_event.emit({"type": "hog_violation", "stone_id": active_stone_id})
	var post_shot := get_stone_states()
	if CurlingRules.has_free_guard_violation(_pre_shot_state, post_shot, active_team, delivered_count, direction):
		_restore_pre_shot_state()
		gameplay_event.emit({"type": "free_guard_violation", "stone_id": active_stone_id})
	elif CurlingRules.has_no_tick_violation(_pre_shot_state, post_shot, active_team, delivered_count, direction):
		_restore_pre_shot_state()
		gameplay_event.emit({"type": "no_tick_violation", "stone_id": active_stone_id})
	for stone in _stones:
		if stone.in_play:
			stone.freeze_at_rest()
	heat_grid.clear()
	delivered_count += 1
	_begin_next_throw()


func _score_end() -> void:
	phase = Phase.SCORING
	_set_guard_protection_mask(0)
	var result := CurlingRules.score_end(get_stone_states(), direction)
	var scoring_team := int(result.get("team", CurlingConstants.TEAM_NONE))
	var points := int(result.get("points", 0))
	if scoring_team == CurlingConstants.TEAM_RED:
		red_score += points
	elif scoring_team == CurlingConstants.TEAM_BLUE:
		blue_score += points
	end_scores.append({"end": current_end + 1, "team": scoring_team, "points": points})
	_score_delay = 3.0
	gameplay_event.emit({"type": "end_scored", "end": current_end + 1, "team": scoring_team, "points": points})
	_mark_state_changed()


func _advance_after_score() -> void:
	current_end += 1
	if current_end >= scheduled_ends:
		if red_score == blue_score:
			scheduled_ends += 2
		else:
			_finish_match()
			return
	hammer_team = CurlingConstants.other_team(hammer_team)
	direction *= -1
	_begin_tactics()


func _finish_match() -> void:
	phase = Phase.RESULT
	var winner := CurlingConstants.TEAM_RED if red_score > blue_score else CurlingConstants.TEAM_BLUE
	final_result = {"winner": winner, "red_score": red_score, "blue_score": blue_score, "end_scores": end_scores.duplicate(true)}
	_mark_state_changed()
	match_finished.emit(final_result)


func _restore_pre_shot_state() -> void:
	for stone_index in range(mini(_pre_shot_state.size(), _stones.size())):
		_stones[stone_index].restore_authoritative_state(_pre_shot_state[stone_index])


func _remove_out_of_play_stones() -> void:
	for stone in _stones:
		if stone.in_play and CurlingRules.is_out_of_play(stone.global_position, direction):
			stone.remove_from_play()
			gameplay_event.emit({"type": "stone_out", "stone_id": stone.stone_id})


func _all_stones_below_stop_speed() -> bool:
	for stone in _stones:
		if stone.in_play and stone.linear_velocity.length() > CurlingConstants.STOP_SPEED_PXPS:
			return false
	return true


func _all_connected_team_members_confirmed(team: int) -> bool:
	var found := false
	for player_id_variant in players.keys():
		var player_id := int(player_id_variant)
		var player: Dictionary = players[player_id]
		if int(player.get("team", CurlingConstants.TEAM_NONE)) != team or not bool(player.get("connected", true)):
			continue
		found = true
		if not bool(tactics_confirmed.get(player_id, false)):
			return false
	return found


func _launch_bot_throw() -> void:
	if phase != Phase.AIMING or not _is_bot(active_thrower_id):
		return
	var target := CurlingConstants.tee_position(direction)
	var lateral := _rng.randf_range(-90.0, 90.0)
	var desired := target + Vector2(0.0, lateral)
	var aim_direction := CurlingConstants.hack_position(direction).direction_to(desired)
	var power := clampf(_rng.randf_range(0.73, 0.83), 0.0, 1.0)
	var spin := _rng.randf_range(-0.85, 0.85)
	_launch_active_stone(aim_direction, power, spin)


func viewport_to_world(viewport_position: Vector2) -> Vector2:
	# 输入事件已经位于 Viewport 坐标系，不再经过桌面原点与窗口位置换算。
	return get_canvas_transform().affine_inverse() * viewport_position


func _can_begin_drag(viewport_position: Vector2) -> bool:
	if active_stone_id < 0:
		return false
	return viewport_to_world(viewport_position).distance_to(
		_stones[active_stone_id].global_position
	) <= 80.0 / maxf(game_camera.zoom.x, 0.1)


func _refresh_local_aim_preview(force_send: bool = false) -> void:
	if not _dragging or active_stone_id < 0:
		return
	_publish_local_aim_preview(
		_drag_aim_direction,
		_current_drag_power(),
		_current_spin,
		force_send
	)


func _publish_local_aim_preview(
	aim_direction: Vector2,
	power: float,
	spin: float,
	force_send: bool = false
) -> void:
	if not show_aim_preview(aim_direction, power, spin, true):
		return
	var now_ms := Time.get_ticks_msec()
	if force_send or now_ms - _last_aim_preview_ms >= roundi(1000.0 / CurlingConstants.AIM_PREVIEW_HZ):
		_last_aim_preview_ms = now_ms
		aim_preview_intent.emit(aim_direction.normalized(), power, spin)


func show_aim_preview(aim_direction: Vector2, power: float, spin: float, from_local: bool = false) -> bool:
	if (
		phase != Phase.AIMING
		or active_stone_id < 0
		or active_stone_id >= _stones.size()
		or not aim_direction.is_finite()
		or aim_direction.length_squared() < 0.9
		or not is_finite(power)
		or power < 0.0
		or power > 1.0
		or not is_finite(spin)
		or absf(spin) > CurlingConstants.MAX_SPIN_RADPS + 0.001
		or _local_team() != active_team
	):
		_clear_aim_preview()
		return false
	_aim_preview_visible = true
	_aim_preview_from_local = from_local
	_aim_preview_direction = aim_direction.normalized()
	_aim_preview_power = power
	_aim_preview_spin = spin
	_aim_preview_last_update_ms = Time.get_ticks_msec()
	var aim_offset := rad_to_deg(
		Vector2(float(direction), 0.0).angle_to(_aim_preview_direction)
	)
	var team_color := (
		CurlingConstants.TEAM_RED_COLOR
		if active_team == CurlingConstants.TEAM_RED
		else CurlingConstants.TEAM_BLUE_COLOR
	)
	aim_guide.show_preview(
		_stones[active_stone_id].global_position,
		_aim_preview_direction,
		power,
		spin,
		team_color,
		aim_offset
	)
	_emit_hud()
	return true


func hide_aim_preview() -> void:
	_clear_aim_preview()


func has_visible_aim_preview() -> bool:
	return _aim_preview_visible and aim_guide.preview_active


func get_aim_preview_data() -> Dictionary:
	return {
		"visible": _aim_preview_visible,
		"direction": _aim_preview_direction,
		"power": _aim_preview_power,
		"spin": _aim_preview_spin,
		"from_local": _aim_preview_from_local,
	}


func _release_local_throw() -> void:
	var power := _current_drag_power()
	var aim_direction := _drag_aim_direction
	_dragging = false
	_clear_local_aim_preview()
	if power <= 0.0 or aim_direction.length_squared() < 0.9:
		return
	if authoritative:
		host_apply_throw(local_player_id, aim_direction, power, _current_spin)
	else:
		throw_intent.emit(aim_direction, power, _current_spin)


func _cancel_drag(notify_team: bool = true) -> void:
	var had_local_preview := (
		_aim_preview_visible
		and _aim_preview_from_local
		and active_thrower_id == local_player_id
	)
	_dragging = false
	_drag_power_adjustment = 0.0
	_clear_aim_preview()
	if notify_team and had_local_preview:
		aim_preview_clear_intent.emit()


func _clear_local_aim_preview() -> void:
	var should_notify := (
		_aim_preview_visible
		and _aim_preview_from_local
		and active_thrower_id == local_player_id
	)
	_clear_aim_preview()
	if should_notify:
		aim_preview_clear_intent.emit()


func _clear_aim_preview(emit_hud_update: bool = true) -> void:
	var changed: bool = _aim_preview_visible or aim_guide.preview_active
	_aim_preview_visible = false
	_aim_preview_from_local = false
	_aim_preview_power = 0.0
	_aim_preview_spin = 0.0
	_aim_preview_last_update_ms = 0
	aim_guide.hide_preview()
	if changed and emit_hud_update:
		_emit_hud()


func _expire_remote_aim_preview() -> void:
	if (
		not _aim_preview_visible
		or _aim_preview_from_local
		or Time.get_ticks_msec() - _aim_preview_last_update_ms <= REMOTE_AIM_STALE_MS
	):
		return
	_clear_aim_preview()


func _send_local_aim_preview_heartbeat() -> void:
	if (
		phase != Phase.AIMING
		or not _aim_preview_visible
		or not _aim_preview_from_local
		or active_thrower_id != local_player_id
	):
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_aim_preview_ms < roundi(1000.0 / CurlingConstants.AIM_PREVIEW_HZ):
		return
	_last_aim_preview_ms = now_ms
	aim_preview_intent.emit(
		_aim_preview_direction,
		_aim_preview_power,
		_aim_preview_spin
	)


func _current_drag_power() -> float:
	return clampf(_raw_drag_power() + _drag_power_adjustment, 0.0, 1.0)


func _raw_drag_power() -> float:
	var max_drag := minf(get_viewport_rect().size.x, get_viewport_rect().size.y) / 3.0
	var drag_distance := _drag_origin_screen.distance_to(_drag_current_screen)
	if drag_distance < 8.0:
		return 0.0
	return clampf((drag_distance - 8.0) / maxf(1.0, max_drag - 8.0), 0.0, 1.0)


func _update_drag_aim_from_pointer(viewport_position: Vector2) -> void:
	if active_stone_id < 0:
		return
	var active_position := _stones[active_stone_id].global_position
	var pointer_direction := viewport_to_world(viewport_position).direction_to(active_position)
	if pointer_direction.length_squared() >= 0.9:
		_drag_aim_direction = pointer_direction.normalized()


func _update_drag_precision_from_keys(delta: float) -> void:
	if not _dragging or active_thrower_id != local_player_id:
		return
	var aim_axis := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		aim_axis -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		aim_axis += 1.0
	var power_axis := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		power_axis += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		power_axis -= 1.0
	var precision_multiplier := (
		CurlingConstants.THROW_FINE_ADJUST_MULTIPLIER
		if Input.is_key_pressed(KEY_SHIFT)
		else 1.0
	)
	if not is_zero_approx(aim_axis):
		_adjust_drag_aim_degrees(
			aim_axis * CurlingConstants.AIM_KEY_RATE_DEGPS * precision_multiplier * delta
		)
	if not is_zero_approx(power_axis):
		_adjust_drag_power(
			power_axis * CurlingConstants.POWER_KEY_RATE_PER_SEC * precision_multiplier * delta
		)


func _adjust_drag_aim_degrees(delta_degrees: float) -> void:
	if not _dragging or _drag_aim_direction.length_squared() < 0.9:
		return
	_drag_aim_direction = _drag_aim_direction.normalized().rotated(deg_to_rad(delta_degrees))
	_refresh_local_aim_preview()


func _adjust_drag_power(delta_power: float) -> void:
	if not _dragging:
		return
	var raw_power := _raw_drag_power()
	var adjusted_power := clampf(raw_power + _drag_power_adjustment + delta_power, 0.0, 1.0)
	_drag_power_adjustment = adjusted_power - raw_power
	_refresh_local_aim_preview()


func _current_aim_offset_degrees() -> float:
	if not _dragging or _drag_aim_direction.length_squared() < 0.9:
		return 0.0
	return rad_to_deg(Vector2(float(direction), 0.0).angle_to(_drag_aim_direction.normalized()))


func _is_drag_precision_key(event: InputEventKey) -> bool:
	return (
		event.keycode in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
		or event.physical_keycode in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	)


func _submit_sweep_motion(world_position: Vector2) -> void:
	var now_ms := Time.get_ticks_msec()
	var delta_sec := clampf(float(now_ms - _last_sweep_ms) / 1000.0, 0.001, 0.25)
	if authoritative:
		host_apply_sweep(local_player_id, _last_sweep_world, world_position, delta_sec, now_ms)
	else:
		sweep_intent.emit(_last_sweep_world, world_position, delta_sec, now_ms)
	_last_sweep_world = world_position
	_last_sweep_ms = now_ms


func _update_spin_from_keys(delta: float) -> void:
	if active_thrower_id != local_player_id:
		return
	var input_axis := Input.get_axis("ui_page_up", "ui_page_down")
	if Input.is_key_pressed(KEY_Q):
		input_axis -= 1.0
	if Input.is_key_pressed(KEY_E):
		input_axis += 1.0
	if not is_zero_approx(input_axis):
		_adjust_spin(input_axis * CurlingConstants.SPIN_KEY_RATE_RADPS * delta)


func _adjust_spin(delta_spin: float, force_send: bool = false) -> void:
	_current_spin = clampf(
		_current_spin + delta_spin,
		-CurlingConstants.MAX_SPIN_RADPS,
		CurlingConstants.MAX_SPIN_RADPS
	)
	if _dragging:
		_refresh_local_aim_preview(force_send)
	elif phase == Phase.AIMING and active_thrower_id == local_player_id:
		_publish_local_aim_preview(
			Vector2(float(direction), 0.0),
			0.0,
			_current_spin,
			force_send
		)


func _camera_key_direction(event: InputEventKey) -> int:
	if event.keycode in [KEY_LEFT, KEY_A] or event.physical_keycode in [KEY_LEFT, KEY_A]:
		return -1
	if event.keycode in [KEY_RIGHT, KEY_D] or event.physical_keycode in [KEY_RIGHT, KEY_D]:
		return 1
	return 0


func _sync_camera_phase_anchor() -> void:
	if _camera_phase == phase:
		return
	_camera_phase = phase
	match phase:
		Phase.TACTICS, Phase.SCORING, Phase.RESULT:
			_manual_camera_x = CurlingConstants.tee_position(direction).x
		Phase.AIMING:
			_manual_camera_x = CurlingConstants.hack_position(direction).x
			if active_stone_id >= 0 and active_stone_id < _stones.size() and _stones[active_stone_id].in_play:
				_manual_camera_x = _stones[active_stone_id].global_position.x
		Phase.IDLE:
			_manual_camera_x = 0.0
	_manual_camera_x = clampf(_manual_camera_x, -CAMERA_X_LIMIT_PX, CAMERA_X_LIMIT_PX)


func _process_camera(delta: float) -> void:
	if not game_camera.enabled:
		return
	_sync_camera_phase_anchor()
	var target_position := Vector2(_manual_camera_x, 0.0)
	var target_zoom := Vector2.ONE * OVERVIEW_CAMERA_ZOOM
	match phase:
		Phase.TACTICS, Phase.SCORING:
			target_zoom = Vector2.ONE * HOUSE_CAMERA_ZOOM
		Phase.AIMING:
			target_zoom = Vector2.ONE * GAMEPLAY_CAMERA_ZOOM
		Phase.MOVING:
			if active_stone_id >= 0 and active_stone_id < _stones.size() and _stones[active_stone_id].in_play:
				target_position = _stones[active_stone_id].global_position
			target_zoom = Vector2.ONE * GAMEPLAY_CAMERA_ZOOM
		Phase.RESULT:
			target_zoom = Vector2.ONE * HOUSE_CAMERA_ZOOM
	if phase not in [Phase.IDLE, Phase.MOVING] and not _dragging:
		var pan_axis := float(_camera_right_held) - float(_camera_left_held)
		if not is_zero_approx(pan_axis):
			_manual_camera_x = clampf(
				_manual_camera_x + pan_axis * CAMERA_PAN_SPEED_PXPS * delta,
				-CAMERA_X_LIMIT_PX,
				CAMERA_X_LIMIT_PX
			)
			target_position.x = _manual_camera_x
	var camera_weight := 1.0 if reduced_motion else 1.0 - exp(-delta * 4.5)
	game_camera.position = game_camera.position.lerp(target_position, camera_weight)
	game_camera.zoom = game_camera.zoom.lerp(target_zoom, camera_weight)


func _on_stone_collision(stone_a: int, stone_b: int, relative_speed_px: float) -> void:
	if phase == Phase.MOVING and (stone_a == active_stone_id or stone_b == active_stone_id):
		_active_touched_other = true
	collision_feedback.emit(relative_speed_px)
	gameplay_event.emit({"type": "impact", "speed": relative_speed_px, "a": stone_a, "b": stone_b})


func _is_bot(player_id: int) -> bool:
	var player_variant: Variant = players.get(player_id)
	return typeof(player_variant) == TYPE_DICTIONARY and bool((player_variant as Dictionary).get("bot", false))


func _local_team() -> int:
	var player_variant: Variant = players.get(local_player_id)
	return int((player_variant as Dictionary).get("team", CurlingConstants.TEAM_NONE)) if typeof(player_variant) == TYPE_DICTIONARY else CurlingConstants.TEAM_NONE


func _player_color(player_id: int) -> Color:
	var player_variant: Variant = players.get(player_id)
	if typeof(player_variant) == TYPE_DICTIONARY:
		var color_variant: Variant = (player_variant as Dictionary).get("color")
		if color_variant is Color:
			return color_variant
	return CurlingConstants.PLAYER_COLORS[absi(player_id) % CurlingConstants.PLAYER_COLORS.size()]


func _mark_state_changed() -> void:
	state_sequence = (state_sequence + 1) & 0xFFFF
	state_changed.emit()
	_emit_hud()


func _emit_hud() -> void:
	var can_view_aim := phase == Phase.AIMING and _local_team() == active_team
	var can_adjust_aim := (
		phase == Phase.AIMING
		and active_thrower_id == local_player_id
		and not local_input_locked
	)
	var aim_visible := can_view_aim and _aim_preview_visible
	var aim_offset := 0.0
	if aim_visible and _aim_preview_direction.length_squared() >= 0.9:
		aim_offset = rad_to_deg(
			Vector2(float(direction), 0.0).angle_to(_aim_preview_direction.normalized())
		)
	hud_changed.emit({
		"phase": phase,
		"phase_name": get_phase_name(),
		"time": phase_time_remaining,
		"shot_id": shot_id,
		"end": current_end + 1,
		"scheduled_ends": scheduled_ends,
		"delivered": delivered_count,
		"red_score": red_score,
		"blue_score": blue_score,
		"hammer_team": hammer_team,
		"active_team": active_team,
		"active_player": player_name(active_thrower_id),
		"active_player_id": active_thrower_id,
		"guard_window_active": (
			delivered_count < CurlingRules.FREE_GUARD_PROTECTED_STONES
			and phase in [Phase.AIMING, Phase.MOVING]
		),
		"guard_throw_index": mini(
			delivered_count + 1,
			CurlingRules.FREE_GUARD_PROTECTED_STONES
		),
		"protected_stone_count": get_protected_stone_count(),
		"can_view_aim": can_view_aim,
		"can_adjust_aim": can_adjust_aim,
		"aim_dragging": can_adjust_aim and _dragging,
		"aim_visible": aim_visible,
		"aim_from_teammate": aim_visible and not _aim_preview_from_local,
		"spin": _aim_preview_spin if aim_visible else 0.0,
		"power": _aim_preview_power if aim_visible else 0.0,
		"aim_offset_degrees": aim_offset,
		"sweeping": _sweep_down and phase == Phase.MOVING,
	})
