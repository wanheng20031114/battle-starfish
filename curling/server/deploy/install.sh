#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo ./deploy/install.sh" >&2
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
INSTALL_DIR=/opt/battle-starfish-curling
ENV_FILE=/etc/battle-starfish-curling.env
SERVICE_FILE=/etc/systemd/system/curling-lobby.service
SERVICE_USER=curlingtest

for command_name in python3 openssl systemctl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
done

if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --home-dir "${INSTALL_DIR}" --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

systemctl stop curling-lobby.service 2>/dev/null || true
install -d -m 0750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${INSTALL_DIR}"
install -d -m 0750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${INSTALL_DIR}/lobby_api" "${INSTALL_DIR}/relay_project"
cp -a "${SOURCE_DIR}/lobby_api/." "${INSTALL_DIR}/lobby_api/"
cp -a "${SOURCE_DIR}/relay_project/." "${INSTALL_DIR}/relay_project/"
install -m 0644 "${SOURCE_DIR}/requirements.txt" "${INSTALL_DIR}/requirements.txt"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"

python3 -m venv "${INSTALL_DIR}/venv"
"${INSTALL_DIR}/venv/bin/python" -m pip install --disable-pip-version-check --no-cache-dir -r "${INSTALL_DIR}/requirements.txt"

if [[ ! -f "${ENV_FILE}" ]]; then
  SECRET=$(openssl rand -hex 32)
  sed "s/^CURLING_MASTER_SECRET=.*/CURLING_MASTER_SECRET=${SECRET}/" "${SOURCE_DIR}/.env.example" > "${ENV_FILE}"
fi
chown root:"${SERVICE_USER}" "${ENV_FILE}"
chmod 0640 "${ENV_FILE}"
install -m 0644 "${SCRIPT_DIR}/curling-lobby.service" "${SERVICE_FILE}"

GODOT_BINARY=$(sed -n 's/^CURLING_GODOT_BINARY=//p' "${ENV_FILE}" | tail -n 1)
if [[ -z "${GODOT_BINARY}" || ! -x "${GODOT_BINARY}" ]]; then
  echo "Godot binary is not executable. Set CURLING_GODOT_BINARY in ${ENV_FILE}." >&2
  exit 1
fi
GODOT_VERSION=$("${GODOT_BINARY}" --headless --version | head -n 1)
if [[ "${GODOT_VERSION}" != 4.6* ]]; then
  echo "Godot 4.6 is required; found: ${GODOT_VERSION}" >&2
  exit 1
fi

systemctl daemon-reload
systemctl enable --now curling-lobby.service
echo "Curling lobby installed. Open TCP 8010 and UDP 40201:40300 in the cloud firewall."
