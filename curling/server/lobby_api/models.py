from __future__ import annotations

from typing import Literal
from pydantic import BaseModel, ConfigDict, Field

from .config import MAX_PLAYERS


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class CreateRoomRequest(StrictModel):
    nickname: str = Field(min_length=2, max_length=16)
    ends: Literal[1, 2, 4]
    is_public: bool = True
    protocol_version: int


class JoinRoomRequest(StrictModel):
    nickname: str = Field(min_length=2, max_length=16)
    protocol_version: int


class MatchmakeRequest(JoinRoomRequest):
    ends: Literal[1, 2, 4]


class ResumeRoomRequest(StrictModel):
    player_id: str = Field(min_length=16, max_length=64)
    session_token: str = Field(min_length=64, max_length=64)
    protocol_version: int


class RosterEntry(StrictModel):
    id: str = Field(min_length=1, max_length=64)
    nickname: str = Field(min_length=2, max_length=16)
    connected: bool


class HeartbeatRequest(StrictModel):
    host_capability: str = Field(min_length=64, max_length=64)
    phase: Literal["waiting", "playing"]
    roster: list[RosterEntry] = Field(max_length=MAX_PLAYERS)


class CloseRoomRequest(StrictModel):
    host_capability: str = Field(min_length=64, max_length=64)


class SessionResponse(StrictModel):
    code: str
    room_id: str
    name: str
    ends: Literal[1, 2, 4]
    role: Literal["host", "member"]
    nickname: str
    player_id: str
    session_token: str
    host_capability: str = ""
    relay_host: str
    relay_port: int
    ticket: str
    ticket_expires_at: int
    test_server: bool = True
    transport_encrypted: bool = False


class RoomSummary(StrictModel):
    code: str
    name: str
    ends: Literal[1, 2, 4]
    players: int
    phase: Literal["waiting", "playing"]
    created_at: int


class RoomsResponse(StrictModel):
    rooms: list[RoomSummary]


class HealthResponse(StrictModel):
    ok: bool
    rooms: int
    relay_capacity: int
    protocol_version: int
    test_server: bool = True


def validate_nickname(value: str) -> str:
    value = value.strip()
    if len(value) < 2 or len(value) > 16 or any(ord(char) < 32 for char in value):
        raise ValueError("nickname must contain 2-16 printable characters")
    return value
