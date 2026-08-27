extends Control
class_name CurlingManualPanel

signal opened
signal closed

@onready var content: RichTextLabel = $Center/Panel/Margin/Layout/Content
@onready var close_button: Button = $Center/Panel/Margin/Layout/Footer/Close

const MANUAL_BBCODE := """
[font_size=21][b][color=#0f7a80]1. 一场比赛怎么进行[/color][/b][/font_size]

每个 End 依次经过：[b]120 秒战术分配 → 两队交替投 16 颗壶 → 计分[/b]。每队固定投 8 颗，不随队伍人数变化。非后手队先投，后手队最后投。

战术阶段可点击本队的投壶位认领，再次点击释放；所有队员分别确认后锁定。空位会优先补给当前投壶次数最少的队员。

[font_size=21][b][color=#0f7a80]2. 投壶与入垒标准投法[/color][/b][/font_size]

• 在当前壶附近按住鼠标左键，向目标的反方向拖拽，松开发射。
• 拖得越远力量越大；窗口较短边约三分之一达到满力。
• [b]Q / E[/b] 连续调旋，鼠标右键取消拖拽。
• 非滑行阶段可用[b]滚轮、← / → 或 A / D[/b]沿赛道查看；滚轮向上朝本 End 目标端移动。
• 壶开始滑行后镜头自动跟踪，直到本手停稳；此阶段无需手动调整镜头。
• 瞄准限时 60 秒；超时记为空投。
• 轨迹线不预测与其他壶的碰撞，撞壶后路线可能不同。

[b][color=#8a4c12]新手标准：沿中线瞄准远端 Tee，旋转保持 +0.00，力量拉到 75%，第一遍先不擦冰。[/color][/b]

• [b]70%[/b] 通常停在营垒前半，[b]75%[/b] 接近圆心，[b]80%[/b] 通常停在后半；90%以上才接近强力打击。
• 接近 75% 时，每调整 1 个百分点，停点约改变 0.6 米。连续过短就加 1%，连续过长就减 1%。
• 擦冰只能让壶滑得更远、弯得更少，不能把过重的壶减速。看起来会短时才擦，预计已经入垒就停手。
• 持续满擦约多滑 3.2 米。若计划全程擦冰，从 [b]69–70%[/b] 起手，不要仍用 75%。
• 熟悉直投后再加旋转；最大旋转约横移 1.5 米，应看轨迹弯向哪边，并向反方向预留瞄准量。

[font_size=21][b][color=#0f7a80]3. 擦冰[/color][/b][/font_size]

出手后，投壶方所有在线队员都可按住左键，在壶前方快速来回移动鼠标。有效擦冰会让壶滑得稍远并减弱弯曲。多人贡献可叠加，但热量有上限并会快速衰减；只按住不移动没有明显效果。

滑行壶上方会显示[b]“预计剩余 X.X 秒”[/b]。当前冰面受热时会再显示[b]“擦冰 +X.X 秒”[/b]，可直接观察擦冰对剩余滑行时间的延长；碰撞或停止擦冰后预测会继续更新。

[font_size=21][b][color=#0f7a80]4. 标线与出界[/color][/b][/font_size]

[b][color=#8a2d26]Hack 起点和中线都只用于定位，没有任何障碍。中线也没有越线惩罚。[/color][/b]

• [b]远端 Hog Line（红色粗线）[/b]：本手壶停稳时须整颗越过。若未越过且途中没碰到其他壶，本手壶会被移除。
• [b]边线[/b]：壶触及赛道侧边界即出界。
• [b]Back Line（背线）[/b]：壶整颗越过目标端背线后出界。
• [b]House（营垒）[/b]：目标端同心圆。接触最外圈的壶也能参与计分。
• [b]Tee[/b]：营垒圆心，也是计分距离的测量点。

[font_size=21][b][color=#0f7a80]5. 五壶保护区[/color][/b][/font_size]

自由防守区位于远端 Hog Line 与 Tee 之间、但不包含营垒。一个 End 的前 5 手中，不能把对方原本位于自由防守区的壶击出场；若对方保护壶压在中线，也不能把它 tick 到离开中线或离开保护区。违规时整条冰道恢复到本手之前，本手仍计入已投数量。

[font_size=21][b][color=#0f7a80]6. 计分与加赛[/color][/b][/font_size]

只统计营垒内或接触外圈的壶。离 Tee 最近的一方是该 End 唯一得分方；该队每有一颗壶比对方最近的壶更靠近 Tee，就得 1 分。营垒为空或最近距离相同则记 0 分。

当前版本每个 End 后，后手与投掷方向都会交替。预定 End 打完仍平分时追加 2 个 End，直到分出胜负。

[font_size=21][b][color=#0f7a80]7. 房间与网络[/color][/b][/font_size]

合法阵容为 2–8 人，每队 1–4 人，两队人数差不超过 1。Host 开赛前可调队，被调队的玩家需重新准备。公网短暂断线后可在约 90 秒内从大厅恢复；当前版本没有 Host 迁移。

等待房间、战术阶段、比赛 HUD 和结算页都有[b]“退出房间”[/b]。Host 退出会关闭房间；比赛中的队员主动退出会离开本局，若一队因此无人则判负。

[font_size=21][b][color=#0f7a80]8. 快捷键[/color][/b][/font_size]

• [b]F1[/b]：打开 / 关闭本说明书。
• [b]Esc[/b]：关闭当前弹层；没有弹层时打开设置。
• [b]F3[/b]：显示 / 隐藏网络与物理诊断。

[font_size=21][b][color=#0f7a80]9. 异常判断[/color][/b][/font_size]

[color=#8a2d26]Hack 起点与赛道中间都没有隐藏规则障碍。[/color] 如果附近没有可见冰壶却发生碰撞、减速或反弹，请视为异常并记录当时画面。

正常的规则移除会在界面底部显示原因，例如未越过 Hog Line 或五壶保护区违规。
"""


func _ready() -> void:
	close_button.pressed.connect(close_panel)
	content.text = MANUAL_BBCODE
	hide()


func open_panel() -> void:
	if visible:
		return
	show()
	content.scroll_to_line(0)
	call_deferred("_focus_content_if_open")
	opened.emit()


func close_panel() -> void:
	if not visible:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and (focus_owner == self or is_ancestor_of(focus_owner)):
		focus_owner.release_focus()
	hide()
	closed.emit()


func _focus_content_if_open() -> void:
	# 关闭与延迟聚焦可能发生在同一帧；隐藏后绝不能重新抢走输入焦点。
	if visible:
		content.grab_focus()


func is_open() -> bool:
	return visible
