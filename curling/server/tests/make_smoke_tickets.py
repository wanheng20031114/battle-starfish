from __future__ import annotations

import json
from pathlib import Path
import sys

from lobby_api.security import issue_ticket


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: make_smoke_tickets.py ROOM_ID SECRET OUTPUT")
    room_id, secret, output = sys.argv[1:]
    sessions: list[dict[str, str]] = []
    for index in range(8):
        role = "host" if index == 0 else "member"
        nickname = "smoke-host" if index == 0 else f"smoke-{index}"
        ticket, _expiry = issue_ticket(
            secret,
            protocol_version=2,
            room_id=room_id,
            role=role,
            nickname=nickname,
            player_id=f"smoke-player-{index}",
            ttl_seconds=30,
        )
        sessions.append({"role": role, "nickname": nickname, "ticket": ticket})
    Path(output).write_text(json.dumps(sessions), encoding="utf-8")


if __name__ == "__main__":
    main()
