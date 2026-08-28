extends RefCounted
class_name CurlingRules

const SCORE_TIE_EPSILON_PX := 0.002 * CurlingConstants.PIXELS_PER_METER
const FREE_GUARD_PROTECTED_STONES := 5
const CENTER_LINE_HALF_WIDTH_PX := 0.013 * CurlingConstants.PIXELS_PER_METER * 0.5


static func is_in_house(position: Vector2, direction: int) -> bool:
	var distance := position.distance_to(CurlingConstants.tee_position(direction))
	return distance <= CurlingConstants.HOUSE_RADII_PX[0] + CurlingConstants.STONE_RADIUS_PX


static func is_in_free_guard_zone(position: Vector2, direction: int) -> bool:
	if is_in_house(position, direction):
		return false
	var tee_x := CurlingConstants.tee_position(direction).x
	var hog_x := CurlingConstants.far_hog_x(direction)
	var stone_radius := CurlingConstants.STONE_RADIUS_PX
	if direction > 0:
		return position.x + stone_radius >= hog_x and position.x + stone_radius < tee_x
	return position.x - stone_radius <= hog_x and position.x - stone_radius > tee_x


static func is_touching_center_line(position: Vector2) -> bool:
	return absf(position.y) <= CurlingConstants.STONE_RADIUS_PX + CENTER_LINE_HALF_WIDTH_PX


static func protected_guard_ids(
	stones: Array[Dictionary],
	delivered_team: int,
	delivered_count_before_shot: int,
	direction: int
) -> Array[int]:
	var protected_ids: Array[int] = []
	if (
		delivered_count_before_shot >= FREE_GUARD_PROTECTED_STONES
		or delivered_team not in [CurlingConstants.TEAM_RED, CurlingConstants.TEAM_BLUE]
	):
		return protected_ids
	var opponent := CurlingConstants.other_team(delivered_team)
	for stone in stones:
		var position_variant: Variant = stone.get("position")
		if (
			int(stone.get("team", CurlingConstants.TEAM_NONE)) != opponent
			or not bool(stone.get("in_play", false))
			or not position_variant is Vector2
		):
			continue
		if is_in_free_guard_zone(position_variant as Vector2, direction):
			protected_ids.append(int(stone.get("id", -1)))
	protected_ids.sort()
	return protected_ids


static func is_out_of_play(position: Vector2, direction: int) -> bool:
	if absf(position.y) + CurlingConstants.STONE_RADIUS_PX >= CurlingConstants.HALF_SHEET_WIDTH_PX:
		return true
	var tee_x := CurlingConstants.tee_position(direction).x
	var back_line_x := tee_x + float(direction) * CurlingConstants.BACK_LINE_FROM_TEE_PX
	if direction > 0:
		return position.x - CurlingConstants.STONE_RADIUS_PX > back_line_x
	return position.x + CurlingConstants.STONE_RADIUS_PX < back_line_x


static func crossed_far_hog(position: Vector2, direction: int) -> bool:
	var hog_x := CurlingConstants.far_hog_x(direction)
	if direction > 0:
		return position.x - CurlingConstants.STONE_RADIUS_PX > hog_x
	return position.x + CurlingConstants.STONE_RADIUS_PX < hog_x


## 返回 {team, points, red_distance, blue_distance}。stones元素需含team/position/in_play。
static func score_end(stones: Array[Dictionary], direction: int) -> Dictionary:
	var tee := CurlingConstants.tee_position(direction)
	var red_distances: Array[float] = []
	var blue_distances: Array[float] = []
	for stone in stones:
		if not bool(stone.get("in_play", false)):
			continue
		var position_variant: Variant = stone.get("position")
		if not position_variant is Vector2:
			continue
		var position := position_variant as Vector2
		if not is_in_house(position, direction):
			continue
		var distance := position.distance_to(tee)
		if int(stone.get("team", CurlingConstants.TEAM_NONE)) == CurlingConstants.TEAM_RED:
			red_distances.append(distance)
		elif int(stone.get("team", CurlingConstants.TEAM_NONE)) == CurlingConstants.TEAM_BLUE:
			blue_distances.append(distance)
	red_distances.sort()
	blue_distances.sort()
	var red_nearest := red_distances[0] if not red_distances.is_empty() else INF
	var blue_nearest := blue_distances[0] if not blue_distances.is_empty() else INF
	if absf(red_nearest - blue_nearest) <= SCORE_TIE_EPSILON_PX:
		return {"team": CurlingConstants.TEAM_NONE, "points": 0}
	var scoring_team := (
		CurlingConstants.TEAM_RED if red_nearest < blue_nearest else CurlingConstants.TEAM_BLUE
	)
	var scoring_distances := red_distances if scoring_team == CurlingConstants.TEAM_RED else blue_distances
	var opposing_nearest := blue_nearest if scoring_team == CurlingConstants.TEAM_RED else red_nearest
	var points := 0
	for distance in scoring_distances:
		if distance + SCORE_TIE_EPSILON_PX < opposing_nearest:
			points += 1
	return {"team": scoring_team, "points": points}


static func has_free_guard_violation(
	pre_shot: Array[Dictionary],
	post_shot: Array[Dictionary],
	delivered_team: int,
	delivered_count_before_shot: int,
	direction: int
) -> bool:
	var protected_ids := protected_guard_ids(
		pre_shot,
		delivered_team,
		delivered_count_before_shot,
		direction
	)
	if protected_ids.is_empty():
		return false
	var post_by_id := {}
	for stone in post_shot:
		post_by_id[int(stone.get("id", -1))] = stone
	for protected_id in protected_ids:
		var after_variant: Variant = post_by_id.get(protected_id)
		if typeof(after_variant) != TYPE_DICTIONARY:
			return true
		var after: Dictionary = after_variant
		if not bool(after.get("in_play", false)):
			return true
	return false


static func has_no_tick_violation(
	pre_shot: Array[Dictionary],
	post_shot: Array[Dictionary],
	delivered_team: int,
	delivered_count_before_shot: int,
	direction: int
) -> bool:
	var protected_ids := protected_guard_ids(
		pre_shot,
		delivered_team,
		delivered_count_before_shot,
		direction
	)
	if protected_ids.is_empty():
		return false
	var post_by_id := {}
	for stone in post_shot:
		post_by_id[int(stone.get("id", -1))] = stone
	for before in pre_shot:
		var before_position_variant: Variant = before.get("position")
		if not before_position_variant is Vector2:
			continue
		var before_position := before_position_variant as Vector2
		if (
			int(before.get("id", -1)) not in protected_ids
			or not is_touching_center_line(before_position)
		):
			continue
		var after_variant: Variant = post_by_id.get(int(before.get("id", -1)))
		if typeof(after_variant) != TYPE_DICTIONARY:
			continue
		var after: Dictionary = after_variant
		if not bool(after.get("in_play", false)):
			continue
		var after_position_variant: Variant = after.get("position")
		if not after_position_variant is Vector2:
			continue
		var after_position := after_position_variant as Vector2
		if not is_in_free_guard_zone(after_position, direction) or not is_touching_center_line(after_position):
			return true
	return false
