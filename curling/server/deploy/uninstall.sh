#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo ./deploy/uninstall.sh" >&2
  exit 1
fi

systemctl disable --now curling-lobby.service 2>/dev/null || true
rm -f -- /etc/systemd/system/curling-lobby.service
systemctl daemon-reload

# 精确删除本测试服务的独立目录与密钥，不接触 Battle Starfish 或 arc-nice 的其他文件。
rm -rf -- /opt/battle-starfish-curling
rm -f -- /etc/battle-starfish-curling.env
if id -u curlingtest >/dev/null 2>&1; then
  userdel curlingtest
fi
echo "Curling test service removed."

