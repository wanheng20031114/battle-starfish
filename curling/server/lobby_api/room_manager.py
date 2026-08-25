from __future__ import annotations

from dataclasses import dataclass, field
import secrets
import threading
import time
import uuid
from typing import Literal

from .config import MAX_PLAYERS, Settings
from .models import RoomSummary, SessionResponse, validate_nickname
from .relay_launcher import RelayLauncher
from .security import issue_ticket, random_hex, token_digest, verify_token

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


class LobbyError(RuntimeError):
    def __init__(self, code: str, status_code: int = 400) -> None:
        super().__init__(code)
        self.code = code
        self.status_code = status_code


@dataclass(slots=True)
class Member:
    player_id: str
    nickname: str
    role: Literal["host", "member"]
    session_digest: str
    connected: bool = True


@dataclass(slots=True)
class Room:
    room_id: str
    code: str
    name: str
    ends: Literal[1, 2, 4]
    is_public: bool
    relay_port: int
    admission_secret: str
    host_capability_digest: str
    created_at: int
    last_heartbeat: float
    phase: Literal["waiting", "playing"] = "waiting"
    members: dict[str, Member] = field(default_factory=dict)


class RoomManager:
    def __init__(self, settings: Settings, launcher: RelayLauncher) -> None:
        self.settings = settings
        self.launcher = launcher
        self._rooms_by_code: dict[str, Room] = {}
        self._codes_by_id: dict[str, str] = {}
        self._ports_in_use: set[int] = set()
        self._lock = threading.RLock()

    def create(self, nickname: str, ends: int, is_public: bool, protocol_version: int) -> SessionResponse:
        nickname = self._validate_request(nickname, protocol_version)
        if ends not in (1, 2, 4):
            raise LobbyError("invalid_ends")
        with self._lock:
            if len(self._rooms_by_code) >= self.settings.max_rooms:
                raise LobbyError("room_capacity_exhausted", 503)
            code = self._new_code()
            room_id = uuid.uuid4().hex
            relay_port = self._allocate_port()
            admission_secret = random_hex(32)
            host_capability = random_hex(32)
            session_token = random_hex(32)
            player_id = uuid.uuid4().hex
            now = int(time.time())
            room = Room(
                room_id=room_id,
                code=code,
                name=f"{nickname}的房间",
                ends=ends,  # type: ignore[arg-type]
                is_public=is_public,
                relay_port=relay_port,
                admission_secret=admission_secret,
                host_capability_digest=token_digest(self.settings.master_secret, host_capability),
                created_at=now,
                last_heartbeat=time.monotonic(),
            )
            room.members[player_id] = Member(
                player_id=player_id,
                nickname=nickname,
                role="host",
                session_digest=token_digest(self.settings.master_secret, session_token),
            )
            self._rooms_by_code[code] = room
            self._codes_by_id[room_id] = code
            try:
                self.launcher.start(room_id, relay_port, admission_secret)
            except Exception as error:
                self._delete_locked(room)
                raise LobbyError("relay_start_failed", 503) from error
            return self._session_response(room, room.members[player_id], session_token, host_capability)

    def join(self, code: str, nickname: str, protocol_version: int) -> SessionResponse:
        nickname = self._validate_request(nickname, protocol_version)
        with self._lock:
            room = self._room(code)
            return self._join_locked(room, nickname)

    def matchmake(self, nickname: str, ends: int, protocol_version: int) -> SessionResponse:
        nickname = self._validate_request(nickname, protocol_version)
        if ends not in (1, 2, 4):
            raise LobbyError("invalid_ends")
        with self._lock:
            candidates = [
                room
                for room in self._rooms_by_code.values()
                if room.is_public and room.phase == "waiting" and room.ends == ends and len(room.members) < MAX_PLAYERS
            ]
            candidates.sort(key=lambda room: room.created_at)
            for room in candidates:
                if all(member.nickname.casefold() != nickname.casefold() for member in room.members.values()):
                    return self._join_locked(room, nickname)
        return self.create(nickname, ends, True, protocol_version)

    def resume(self, code: str, player_id: str, session_token: str, protocol_version: int) -> SessionResponse:
        if protocol_version != self.settings.protocol_version:
            raise LobbyError("protocol_mismatch", 409)
        with self._lock:
            room = self._room(code)
            member = room.members.get(player_id)
            if member is None or not verify_token(self.settings.master_secret, session_token, member.session_digest):
                raise LobbyError("invalid_resume_token", 401)
            member.connected = True
            return self._session_response(room, member, session_token, "")

    def heartbeat(self, code: str, host_capability: str, phase: str, roster: list[dict[str, object]]) -> None:
        with self._lock:
            room = self._room(code)
            if not verify_token(self.settings.master_secret, host_capability, room.host_capability_digest):
                raise LobbyError("invalid_host_capability", 401)
            if phase not in ("waiting", "playing"):
                raise LobbyError("invalid_phase")
            room.phase = phase  # type: ignore[assignment]
            room.last_heartbeat = time.monotonic()
            roster_names = {str(entry.get("nickname", "")).casefold() for entry in roster}
            for member in room.members.values():
                member.connected = member.nickname.casefold() in roster_names

    def close(self, code: str, host_capability: str) -> None:
        with self._lock:
            room = self._room(code)
            if not verify_token(self.settings.master_secret, host_capability, room.host_capability_digest):
                raise LobbyError("invalid_host_capability", 401)
            self._delete_locked(room)

    def list_public(self) -> list[RoomSummary]:
        with self._lock:
            rooms = [
                RoomSummary(
                    code=room.code,
                    name=room.name,
                    ends=room.ends,
                    players=sum(1 for member in room.members.values() if member.connected),
                    phase=room.phase,
                    created_at=room.created_at,
                )
                for room in self._rooms_by_code.values()
                if room.is_public and room.phase == "waiting"
            ]
        rooms.sort(key=lambda room: room.created_at)
        return rooms

    def expire_stale(self) -> list[str]:
        expired: list[str] = []
        now = time.monotonic()
        with self._lock:
            for room in list(self._rooms_by_code.values()):
                if now - room.last_heartbeat >= self.settings.lease_timeout_seconds:
                    expired.append(room.code)
                    self._delete_locked(room)
            for exited_room_id in self.launcher.reap():
                code = self._codes_by_id.get(exited_room_id)
                if code and code in self._rooms_by_code:
                    expired.append(code)
                    self._delete_locked(self._rooms_by_code[code])
        return expired

    @property
    def room_count(self) -> int:
        with self._lock:
            return len(self._rooms_by_code)

    def _join_locked(self, room: Room, nickname: str) -> SessionResponse:
        if room.phase != "waiting":
            raise LobbyError("room_already_started", 409)
        if len(room.members) >= MAX_PLAYERS:
            raise LobbyError("room_full", 409)
        if any(member.nickname.casefold() == nickname.casefold() for member in room.members.values()):
            raise LobbyError("nickname_in_use", 409)
        session_token = random_hex(32)
        player_id = uuid.uuid4().hex
        member = Member(
            player_id=player_id,
            nickname=nickname,
            role="member",
            session_digest=token_digest(self.settings.master_secret, session_token),
        )
        room.members[player_id] = member
        return self._session_response(room, member, session_token, "")

    def _session_response(
        self,
        room: Room,
        member: Member,
        session_token: str,
        host_capability: str,
    ) -> SessionResponse:
        ticket, expires_at = issue_ticket(
            room.admission_secret,
            protocol_version=self.settings.protocol_version,
            room_id=room.room_id,
            role=member.role,
            nickname=member.nickname,
            player_id=member.player_id,
            ttl_seconds=self.settings.ticket_ttl_seconds,
        )
        return SessionResponse(
            code=room.code,
            room_id=room.room_id,
            name=room.name,
            ends=room.ends,
            role=member.role,
            nickname=member.nickname,
            player_id=member.player_id,
            session_token=session_token,
            host_capability=host_capability,
            relay_host=self.settings.public_relay_host,
            relay_port=room.relay_port,
            ticket=ticket,
            ticket_expires_at=expires_at,
        )

    def _validate_request(self, nickname: str, protocol_version: int) -> str:
        if protocol_version != self.settings.protocol_version:
            raise LobbyError("protocol_mismatch", 409)
        try:
            return validate_nickname(nickname)
        except ValueError as error:
            raise LobbyError("invalid_nickname") from error

    def _room(self, code: str) -> Room:
        room = self._rooms_by_code.get(code.strip().upper())
        if room is None:
            raise LobbyError("room_not_found", 404)
        return room

    def _new_code(self) -> str:
        for _ in range(1000):
            code = "".join(secrets.choice(ALPHABET) for _ in range(6))
            if code not in self._rooms_by_code:
                return code
        raise LobbyError("code_space_exhausted", 503)

    def _allocate_port(self) -> int:
        for port in range(self.settings.relay_port_min, self.settings.relay_port_max + 1):
            if port not in self._ports_in_use:
                self._ports_in_use.add(port)
                return port
        raise LobbyError("relay_port_exhausted", 503)

    def _delete_locked(self, room: Room) -> None:
        self._rooms_by_code.pop(room.code, None)
        self._codes_by_id.pop(room.room_id, None)
        self._ports_in_use.discard(room.relay_port)
        self.launcher.stop(room.room_id)
