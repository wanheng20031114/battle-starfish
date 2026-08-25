extends Node2D

var _failures: Array[String] = []
var _measured_restitution := 0.0
@onready var stones: Array[CurlingStone] = [$StoneA, $StoneB, $StoneC, $StoneD]


func _ready() -> void:
	await get_tree().physics_frame
	await _test_head_on()
	await _test_offset()
	await _test_chain()
	await _test_continuous_collision()
	if _failures.is_empty():
		print("CURLING_NATIVE_PHYSICS_OK restitution=%.3f" % _measured_restitution)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("CURLING_NATIVE_PHYSICS_FAIL %s" % failure)
		get_tree().quit(1)


func _reset_stones(positions: Array[Vector2]) -> void:
	for index in range(stones.size()):
		var stone := stones[index]
		stone.in_play = index < positions.size()
		stone.visible = stone.in_play
		stone.authoritative = true
		stone.active_delivered_stone = false
		stone.freeze = true
		stone.sleeping = true
		stone.linear_velocity = Vector2.ZERO
		stone.angular_velocity = 0.0
	await get_tree().physics_frame
	for index in range(stones.size()):
		var stone := stones[index]
		var target_position := positions[index] if index < positions.size() else Vector2(5000, index * 100)
		stone.global_position = target_position
		PhysicsServer2D.body_set_state(stone.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, target_position))
		PhysicsServer2D.body_set_state(stone.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2.ZERO)
		PhysicsServer2D.body_set_state(stone.get_rid(), PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 0.0)
		stone.linear_velocity = Vector2.ZERO
		stone.angular_velocity = 0.0
		stone.linear_damp = 0.0
	await get_tree().physics_frame


func _activate_stones(count: int) -> void:
	for index in range(count):
		stones[index].freeze = false
		stones[index].sleeping = false
		stones[index].linear_velocity = Vector2.ZERO
		stones[index].angular_velocity = 0.0


func _wait_physics(seconds: float) -> void:
	var frames := ceili(seconds * Engine.physics_ticks_per_second)
	for _frame in range(frames):
		await get_tree().physics_frame


func _test_head_on() -> void:
	await _reset_stones([Vector2(-80, 0), Vector2.ZERO])
	if absf(stones[0].physics_material_override.bounce - CurlingConstants.STONE_MATERIAL_BOUNCE) > 0.001:
		_failures.append("PhysicsMaterial bounce calibration")
	_activate_stones(2)
	stones[0].linear_velocity = Vector2(500, 0)
	for _frame in range(60):
		await get_tree().physics_frame
		if stones[1].linear_velocity.x > 1.0:
			break
	_measured_restitution = (stones[1].linear_velocity.x - stones[0].linear_velocity.x) / 500.0
	if absf(_measured_restitution - CurlingConstants.STONE_RESTITUTION) > 0.04:
		_failures.append("native restitution %.3f" % _measured_restitution)
	await _wait_physics(0.20)
	if stones[1].linear_velocity.x < 420.0:
		_failures.append("0.92 equal-mass head-on transfer")


func _test_offset() -> void:
	await _reset_stones([Vector2(-80, -11), Vector2.ZERO])
	_activate_stones(2)
	stones[0].linear_velocity = Vector2(500, 0)
	await _wait_physics(0.35)
	if absf(stones[1].linear_velocity.y) < 35.0:
		_failures.append("off-centre collision produces lateral impulse")


func _test_chain() -> void:
	await _reset_stones([Vector2(-80, 0), Vector2(-20, 0), Vector2(25, 0)])
	_activate_stones(3)
	stones[0].linear_velocity = Vector2(650, 0)
	await _wait_physics(0.45)
	if stones[2].linear_velocity.x < 350.0:
		_failures.append("three-stone chain collision")


func _test_continuous_collision() -> void:
	await _reset_stones([Vector2(-300, 0), Vector2.ZERO])
	_activate_stones(2)
	stones[0].linear_velocity = Vector2(4500, 0)
	await _wait_physics(0.15)
	if stones[1].linear_velocity.x < 500.0:
		_failures.append("shape CCD prevents high-speed tunnelling")
