extends RefCounted
class_name CurlingConstants

## 协议与场地的稳定合同。客户端、Host、测试和Relay均以此版本拒绝不兼容数据。
const PROTOCOL_VERSION := 2
const APP_CHANNEL_COUNT := 8

const CH_SYSTEM := 0
const CH_CURSOR := 1
const CH_SWEEP := 2
const CH_STONE_SNAPSHOT := 3
const CH_AIM_PREVIEW := 4
const CH_GAMEPLAY := 5
const CH_CHAT := 6
const CH_RELAY_CONTROL := 7

const PIXELS_PER_METER := 100.0
const SHEET_LENGTH_M := 45.720
const SHEET_WIDTH_M := 4.750
const SHEET_LENGTH_PX := SHEET_LENGTH_M * PIXELS_PER_METER
const SHEET_WIDTH_PX := SHEET_WIDTH_M * PIXELS_PER_METER
const HALF_SHEET_LENGTH_PX := SHEET_LENGTH_PX * 0.5
const HALF_SHEET_WIDTH_PX := SHEET_WIDTH_PX * 0.5

const TEE_FROM_CENTER_M := 17.375
const TEE_FROM_CENTER_PX := TEE_FROM_CENTER_M * PIXELS_PER_METER
const BACK_LINE_FROM_TEE_PX := 1.829 * PIXELS_PER_METER
const HOG_LINE_FROM_TEE_PX := 6.401 * PIXELS_PER_METER
const HACK_FROM_TEE_PX := 1.829 * PIXELS_PER_METER
const HOUSE_RADII_PX := [182.9, 121.9, 61.0, 15.2]

const STONE_RADIUS_M := 0.1455
const STONE_RADIUS_PX := STONE_RADIUS_M * PIXELS_PER_METER
const STONE_MASS_KG := 19.0
const STONE_RESTITUTION := 0.92
## Godot会把两个非absorbent PhysicsMaterial 的bounce相加；两颗同材质壶各取一半，实测恢复系数约0.92。
const STONE_MATERIAL_BOUNCE := STONE_RESTITUTION * 0.5
const STONE_COUNT := 16
const STONES_PER_TEAM := 8

const PHYSICS_HZ := 60
const BASE_DRAG_MPS2 := 0.151
const BASE_DRAG_PXPS2 := BASE_DRAG_MPS2 * PIXELS_PER_METER
const CURL_ACCEL_PER_RAD_MPS2 := 0.02155
const CURL_ACCEL_PER_RAD_PXPS2 := CURL_ACCEL_PER_RAD_MPS2 * PIXELS_PER_METER
const ANGULAR_HALF_LIFE_SEC := 20.0
const ANGULAR_DAMP_PER_SEC := log(2.0) / ANGULAR_HALF_LIFE_SEC
const STOP_SPEED_MPS := 0.03
const STOP_SPEED_PXPS := STOP_SPEED_MPS * PIXELS_PER_METER
const SETTLE_TIME_SEC := 0.5

const MIN_THROW_SPEED_MPS := 0.5
const MAX_THROW_SPEED_MPS := 4.5
const THROW_TEE_POWER := 0.75
## 新手推荐略过Tee，给短壶体感留出余量；零旋转、不擦冰时约滑22.17秒，
## 加0.5秒停稳确认后本手约22.67秒，停在Tee后约1.15米且仍安全留在营垒。
const THROW_RECOMMENDED_POWER := 0.77
## 输入百分比使用线性速度曲线。75%严格标定为零旋转、不擦冰的直线Tee停点；
## 100%约等于旧90%强度，让旧50%-90%的有效段扩展到更大的操作范围。
const THROW_LINEAR_MIN_SPEED_MPS := 1.39319
const THROW_LINEAR_MAX_SPEED_MPS := 3.96966
const MAX_SPIN_RADPS := 1.2
const SPIN_KEY_RATE_RADPS := 1.2
const SPIN_WHEEL_STEP_RADPS := 0.08
const AIM_TIME_SEC := 60.0
const TACTICS_TIME_SEC := 120.0

const HEAT_CELL_M := 0.10
const HEAT_CELL_PX := HEAT_CELL_M * PIXELS_PER_METER
const BRUSH_WIDTH_M := 0.50
const BRUSH_RADIUS_PX := BRUSH_WIDTH_M * PIXELS_PER_METER * 0.5
const SWEEP_MIN_SPEED_MPS := 0.5
const SWEEP_FULL_SPEED_MPS := 2.5
const SWEEP_MAX_SPEED_MPS := 4.0
const HEAT_HALF_LIFE_SEC := 0.6
const HEAT_CUTOFF_SEC := 2.5
const HEAT_DEPOSIT_PER_SEC := 1.55
const SWEEP_DRAG_REDUCTION := 0.08
## 由于满热会延长滑行时间，内部力系数需降低约44%，最终横向位移才减少约35%。
const SWEEP_CURL_FORCE_REDUCTION := 0.44
const SWEEP_SAMPLE_MAX_AGE_MS := 250
const SWEEP_SAMPLE_MAX_FUTURE_MS := 50

const SNAPSHOT_HZ := 60.0
const CURSOR_HZ := 20.0
const AIM_PREVIEW_HZ := 20.0
const SWEEP_BATCH_HZ := 30.0
const HEAT_PATH_HZ := 20.0
const HEAT_RESYNC_SEC := 2.0
const INTERPOLATION_DELAY_MS := 100
const ACTIVE_EXTRAPOLATION_MAX_MS := 120
const SNAP_CORRECTION_DISTANCE_PX := 0.15 * PIXELS_PER_METER
const CURSOR_INTERPOLATION_MS := 50
const CLOCK_SYNC_INTERVAL_SEC := 1.0
const PEER_DISCONNECT_TIMEOUT_MS := 8000
const RECONNECT_GRACE_SEC := 90.0

const LAN_GAME_PORT := 40150
const LAN_DISCOVERY_PORT := 40151
const PUBLIC_API_URL := "http://47.123.6.127:8010"
const PUBLIC_RELAY_PORT_MIN := 40201
const PUBLIC_RELAY_PORT_MAX := 40300
const MAX_PLAYERS := 8
const MIN_PLAYERS := 2
const MAX_TEAM_PLAYERS := 4
const MIN_TEAM_PLAYERS := 1
const MAX_TEAM_SIZE_DIFFERENCE := 1

const TEAM_NONE := 0
const TEAM_RED := 1
const TEAM_BLUE := 2
const TEAM_RED_COLOR := Color("e85a62")
const TEAM_BLUE_COLOR := Color("4a87d8")
const ICE_COLOR := Color("eaf7f9")
const NAVY_COLOR := Color("102132")
const CYAN_ACCENT := Color("63d6cf")

const PLAYER_COLORS := [
	Color("f6c85f"), Color("6f4eeb"), Color("45c486"),
	Color("f28e5b"), Color("df70b5"), Color("64b5f6"),
	Color("26c6da"), Color("c0ca33"),
]


static func is_valid_team_distribution(red_count: int, blue_count: int) -> bool:
	var total_players := red_count + blue_count
	return (
		red_count >= MIN_TEAM_PLAYERS
		and red_count <= MAX_TEAM_PLAYERS
		and blue_count >= MIN_TEAM_PLAYERS
		and blue_count <= MAX_TEAM_PLAYERS
		and total_players >= MIN_PLAYERS
		and total_players <= MAX_PLAYERS
		and absi(red_count - blue_count) <= MAX_TEAM_SIZE_DIFFERENCE
	)


static func tee_position(direction: int) -> Vector2:
	return Vector2(float(direction) * TEE_FROM_CENTER_PX, 0.0)


static func hack_position(direction: int) -> Vector2:
	return Vector2(-float(direction) * (TEE_FROM_CENTER_PX + HACK_FROM_TEE_PX), 0.0)


static func far_hog_x(direction: int) -> float:
	return float(direction) * (TEE_FROM_CENTER_PX - HOG_LINE_FROM_TEE_PX)


static func team_name(team: int) -> String:
	return "红队" if team == TEAM_RED else "蓝队" if team == TEAM_BLUE else "未分队"


static func other_team(team: int) -> int:
	return TEAM_BLUE if team == TEAM_RED else TEAM_RED


static func throw_speed_for_power(power: float) -> float:
	return lerpf(THROW_LINEAR_MIN_SPEED_MPS, THROW_LINEAR_MAX_SPEED_MPS, clampf(power, 0.0, 1.0))
