# Curling 公网测试服务

服务由两个完全独立的部分组成：FastAPI 大厅管理最多 8 人的临时内存房间、匹配、租约与 30 秒 HMAC 票据；每个房间由大厅启动一个 Godot 4.6 无头 ENet Relay。Relay 不执行规则或物理，只认证并转发七个业务通道，控制通道为第八个通道。当前游戏协议为 v2，HTTP API 路径继续使用 `/v1`。

## 本地开发

```powershell
cd curling/server
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
$env:CURLING_MASTER_SECRET = "replace-with-at-least-32-random-characters"
$env:CURLING_RELAY_AUTOSTART = "1"
$env:CURLING_GODOT_BINARY = "C:\Program Files\Godot\Godot_console.exe"
.venv\Scripts\python -m uvicorn lobby_api.main:app --host 127.0.0.1 --port 8010
```

游戏客户端用 `--curling-api=http://127.0.0.1:8010` 覆盖固定测试地址。健康检查为 `GET /healthz`。

## API

- `GET /healthz`
- `GET /v1/rooms`
- `POST /v1/rooms`
- `POST /v1/rooms/{code}/join`
- `POST /v1/matchmake`
- `POST /v1/rooms/{code}/resume`
- `POST /v1/rooms/{code}/heartbeat`
- `DELETE /v1/rooms/{code}`

房间完全驻留内存。Host 每 10 秒续租；30 秒无有效心跳或 Relay 退出后，大厅会清理房间并回收 UDP 端口。Host 断线时 Relay 主动退出，不进行 Host 迁移。

## Linux 部署包

在目标机复制整个 `curling/server/` 后执行：

```bash
sudo ./deploy/install.sh
```

安装脚本创建独立系统用户、`/opt/battle-starfish-curling`、Python 虚拟环境、密钥环境文件和 `curling-lobby.service`。它不会读取或修改 arc-nice 的运行时文件。云防火墙仍需人工放行 TCP `8010` 与 UDP `40201:40300`。

卸载：

```bash
sudo ./deploy/uninstall.sh
```

日志进入 journald：`journalctl -u curling-lobby -f`。环境文件默认位于 `/etc/battle-starfish-curling.env`，权限为 `0640`。
