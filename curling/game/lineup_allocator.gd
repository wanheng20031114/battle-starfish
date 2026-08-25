extends RefCounted
class_name CurlingLineupAllocator


## 依次填补空位；已分配总数最少者优先，同数按稳定入房顺序。
static func fill_empty_slots(
	lineup: Array[int],
	team_player_ids: Array[int],
	join_order_by_id: Dictionary
) -> Array[int]:
	var result: Array[int] = lineup.duplicate()
	if result.size() != CurlingConstants.STONES_PER_TEAM:
		result.resize(CurlingConstants.STONES_PER_TEAM)
	for slot_index in range(result.size()):
		if result[slot_index] > 0:
			continue
		var chosen_id := _least_assigned_player(result, team_player_ids, join_order_by_id)
		if chosen_id > 0:
			result[slot_index] = chosen_id
	return result


static func redistribute_player_slots(
	lineup: Array[int],
	departed_player_id: int,
	remaining_player_ids: Array[int],
	join_order_by_id: Dictionary,
	first_unplayed_slot: int = 0
) -> Array[int]:
	var result: Array[int] = lineup.duplicate()
	for slot_index in range(maxi(0, first_unplayed_slot), result.size()):
		if result[slot_index] == departed_player_id:
			result[slot_index] = 0
	return fill_empty_slots(result, remaining_player_ids, join_order_by_id)


static func _least_assigned_player(
	lineup: Array[int],
	player_ids: Array[int],
	join_order_by_id: Dictionary
) -> int:
	var chosen_id := 0
	var chosen_count := 1_000_000
	var chosen_order := 1_000_000
	for player_id in player_ids:
		var assigned_count := lineup.count(player_id)
		var join_order := int(join_order_by_id.get(player_id, 1_000_000))
		if (
			assigned_count < chosen_count
			or (assigned_count == chosen_count and join_order < chosen_order)
		):
			chosen_id = player_id
			chosen_count = assigned_count
			chosen_order = join_order
	return chosen_id

