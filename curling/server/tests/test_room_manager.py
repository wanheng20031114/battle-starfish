from __future__ import annotations

from pathlib import Path
import time

import pytest

from lobby_api.config import Settings
from lobby_api.room_manager import LobbyError, RoomManager


class FakeLauncher:
    def __init__(self) -> None:
        self.started: dict[str, int] = {}
        self.stopped: list[str] = []
        self.exited: list[str] = []

    def start(self, room_id: str, port: int, _secret: str) -> None:
        self.started[room_id] = port

    def stop(self, room_id: str) -> None:
        self.started.pop(room_id, None)
        self.stopped.append(room_id)

    def reap(self) -> list[str]:
        result = self.exited[:]
        self.exited.clear()
        return result


def settings(*, max_rooms: int = 3, port_min: int = 40201, port_max: int = 40203) -> Settings:
    return Settings(
        bind_host="127.0.0.1",
        bind_port=8010,
        public_relay_host="127.0.0.1",
        relay_port_min=port_min,
        relay_port_max=port_max,
        max_rooms=max_rooms,
        lease_timeout_seconds=30,
        ticket_ttl_seconds=30,
        protocol_version=2,
        master_secret="master-secret-for-curling-tests-000000000000",
        relay_autostart=False,
        godot_binary="godot",
        relay_project_path=Path("relay_project"),
    )


def test_create_join_list_matchmake_and_resume() -> None:
    launcher = FakeLauncher()
    manager = RoomManager(settings(), launcher)  # type: ignore[arg-type]
    host = manager.create("房主", 2, True, 2)
    assert host.role == "host"
    assert host.relay_port == 40201
    assert len(host.ticket.split(".")) == 3
    member = manager.join(host.code, "队员", 2)
    assert member.role == "member"
    assert member.player_id != host.player_id
    assert manager.list_public()[0].players == 2

    resumed = manager.resume(host.code, member.player_id, member.session_token, 2)
    assert resumed.player_id == member.player_id
    assert resumed.session_token == member.session_token
    assert resumed.ticket != member.ticket

    matched = manager.matchmake("第三人", 2, 2)
    assert matched.code == host.code
    separate = manager.matchmake("另一房", 4, 2)
    assert separate.code != host.code


def test_protocol_nickname_capacity_and_port_exhaustion() -> None:
    manager = RoomManager(settings(max_rooms=2, port_min=40201, port_max=40202), FakeLauncher())  # type: ignore[arg-type]
    with pytest.raises(LobbyError, match="protocol_mismatch"):
        manager.create("房主", 1, True, 1)
    with pytest.raises(LobbyError, match="invalid_nickname"):
        manager.create("x", 1, True, 2)
    manager.create("房主一", 1, True, 2)
    manager.create("房主二", 1, True, 2)
    with pytest.raises(LobbyError, match="room_capacity_exhausted"):
        manager.create("房主三", 1, True, 2)

    port_limited = RoomManager(settings(max_rooms=2, port_min=40300, port_max=40300), FakeLauncher())  # type: ignore[arg-type]
    port_limited.create("端口房一", 1, True, 2)
    with pytest.raises(LobbyError, match="relay_port_exhausted"):
        port_limited.create("端口房二", 1, True, 2)


def test_room_full_duplicate_identity_and_host_capability() -> None:
    manager = RoomManager(settings(), FakeLauncher())  # type: ignore[arg-type]
    host = manager.create("房主", 1, False, 2)
    with pytest.raises(LobbyError, match="nickname_in_use"):
        manager.join(host.code, "房主", 2)
    for index in range(7):
        manager.join(host.code, "队员%d" % index, 2)
    with pytest.raises(LobbyError, match="room_full"):
        manager.join(host.code, "第九人", 2)
    with pytest.raises(LobbyError, match="invalid_host_capability"):
        manager.heartbeat(host.code, "0" * 64, "waiting", [])
    manager.heartbeat(host.code, host.host_capability, "playing", [{"nickname": "房主"}])
    with pytest.raises(LobbyError, match="room_already_started"):
        manager.join(host.code, "迟到玩家", 2)


def test_matchmake_fills_eight_players_then_opens_a_new_room() -> None:
    manager = RoomManager(settings(), FakeLauncher())  # type: ignore[arg-type]
    host = manager.create("房主", 1, True, 2)
    for index in range(1, 8):
        matched = manager.matchmake("匹配%d" % index, 1, 2)
        assert matched.code == host.code
    overflow = manager.matchmake("匹配八", 1, 2)
    assert overflow.code != host.code


def test_lease_and_relay_exit_cleanup_reuse_ports() -> None:
    launcher = FakeLauncher()
    manager = RoomManager(settings(max_rooms=1, port_min=40201, port_max=40201), launcher)  # type: ignore[arg-type]
    host = manager.create("房主", 1, True, 2)
    room = manager._rooms_by_code[host.code]
    room.last_heartbeat = time.monotonic() - 31
    assert manager.expire_stale() == [host.code]
    replacement = manager.create("新房主", 1, True, 2)
    assert replacement.relay_port == 40201
    launcher.exited.append(replacement.room_id)
    assert manager.expire_stale() == [replacement.code]
    assert manager.room_count == 0
