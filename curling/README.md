# Curling Lab

这是一个与 Battle Starfish 主玩法完全隔离的 2–8 人冰壶联机测试。合法阵容为 1v1、1v2、2v2、2v3、3v3、3v4 和 4v4；每队仍投 8 颗壶。所有场景、脚本、测试和公网服务文件都位于 `res://curling/`，没有新增 Autoload，也没有更改主场景、项目设置或导出配置。

## 运行

- 在 Godot 4.6 中打开 `res://curling/curling.tscn` 并按 F6。
- Windows 也可从仓库根目录运行 `powershell -ExecutionPolicy Bypass -File curling/tools/run_curling.ps1`。
- 单机演示会创建 8 名模拟玩家组成 4v4，可直接验证战术分配、投壶、碰撞、擦冰、计分与加时流程。
- LAN Host 使用 UDP `40150`，发现广播使用 UDP `40151`。
- 公网大厅固定指向 `http://47.123.6.127:8010`，可用启动参数 `--curling-api=http://127.0.0.1:8010` 覆盖。

公网测试连接是明文 HTTP 与普通 ENet，不提供传输加密或竞技级反作弊。玩家 Host 持有规则与物理权威，因此理论上可以作弊。

## 操作

- 大厅：创建单机、LAN 或公网房，或从公开列表/代码房/快速匹配加入。
- 房间：自行选红蓝队并准备；每队最多 4 人，开赛时人数差不得超过 1。Host 可以在开赛前为任意玩家调队，但不能踢人。
- 战术：点击自己的投壶位认领/释放；每名队员分别确认。无人认领的位置在锁定时公平补齐。
- 出手：从当前壶向后拖拽，短边三分之一达到满力；`Q/E` 连续调旋，滚轮微调。
- 擦冰：投壶方所有在线成员都可按住左键并快速移动鼠标；多人贡献相加但热量封顶。
- `F3`：显示只读网络/物理诊断。

## 目录

- `curling.tscn` / `curling.gd`：独立入口与应用状态机。
- `game/`：原生 `RigidBody2D` 冰壶、冰道、热网格、规则和比赛状态机。
- `network/`：LAN、公网 Relay 协议、204 字节快照、时钟和远端光标。
- `server/lobby_api/`：FastAPI 临时房间、匹配、租约和 HMAC 票据。
- `server/relay_project/`：每房间一个只认证/转发的 Godot ENet Relay。
- `server/deploy/`：独立 systemd 安装与卸载包；本仓库不会自动操作服务器。
- `tests/`：规则、协议、物理标定和可配置为 2–8 人的多人网络烟测。

Godot 会把两份默认非吸收型 `PhysicsMaterial.bounce` 相加，因此单壶资源使用 `0.46`；两壶相撞的实测恢复系数为约 `0.92`。

## 公网本地启动

参见 [`server/README.md`](server/README.md)。测试脚本会跟踪自己启动的 PID，并在退出时只终止对应的无头 Godot 与 Python 进程。

当前游戏协议为 v2；LAN 发现、房间注册、公网票据和 Relay 会拒绝 v1 客户端。HTTP API 路径仍保持 `/v1`。
