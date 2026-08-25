from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI, HTTPException

from .config import load_settings
from .models import (
    CloseRoomRequest,
    CreateRoomRequest,
    HealthResponse,
    HeartbeatRequest,
    JoinRoomRequest,
    MatchmakeRequest,
    ResumeRoomRequest,
    RoomsResponse,
    SessionResponse,
)
from .relay_launcher import RelayLauncher
from .room_manager import LobbyError, RoomManager

settings = load_settings()
launcher = RelayLauncher(settings)
rooms = RoomManager(settings, launcher)


async def cleanup_loop() -> None:
    while True:
        await asyncio.sleep(5)
        rooms.expire_stale()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    cleanup_task = asyncio.create_task(cleanup_loop())
    try:
        yield
    finally:
        cleanup_task.cancel()
        with suppress(asyncio.CancelledError):
            await cleanup_task
        launcher.stop_all()


app = FastAPI(
    title="Curling Test Lobby",
    version="1.0.0",
    description="Ephemeral plaintext test lobby; transport content is not encrypted.",
    lifespan=lifespan,
)


def translate_error(error: LobbyError) -> HTTPException:
    return HTTPException(status_code=error.status_code, detail=error.code)


@app.get("/healthz", response_model=HealthResponse)
def healthz() -> HealthResponse:
    return HealthResponse(
        ok=True,
        rooms=rooms.room_count,
        relay_capacity=settings.max_rooms,
        protocol_version=settings.protocol_version,
    )


@app.get("/v1/rooms", response_model=RoomsResponse)
def list_rooms() -> RoomsResponse:
    return RoomsResponse(rooms=rooms.list_public())


@app.post("/v1/rooms", response_model=SessionResponse)
def create_room(request: CreateRoomRequest) -> SessionResponse:
    try:
        return rooms.create(request.nickname, request.ends, request.is_public, request.protocol_version)
    except LobbyError as error:
        raise translate_error(error) from error


@app.post("/v1/rooms/{code}/join", response_model=SessionResponse)
def join_room(code: str, request: JoinRoomRequest) -> SessionResponse:
    try:
        return rooms.join(code, request.nickname, request.protocol_version)
    except LobbyError as error:
        raise translate_error(error) from error


@app.post("/v1/matchmake", response_model=SessionResponse)
def matchmake(request: MatchmakeRequest) -> SessionResponse:
    try:
        return rooms.matchmake(request.nickname, request.ends, request.protocol_version)
    except LobbyError as error:
        raise translate_error(error) from error


@app.post("/v1/rooms/{code}/resume", response_model=SessionResponse)
def resume_room(code: str, request: ResumeRoomRequest) -> SessionResponse:
    try:
        return rooms.resume(code, request.player_id, request.session_token, request.protocol_version)
    except LobbyError as error:
        raise translate_error(error) from error


@app.post("/v1/rooms/{code}/heartbeat")
def heartbeat(code: str, request: HeartbeatRequest) -> dict[str, bool]:
    try:
        rooms.heartbeat(code, request.host_capability, request.phase, [entry.model_dump() for entry in request.roster])
        return {"ok": True}
    except LobbyError as error:
        raise translate_error(error) from error


@app.delete("/v1/rooms/{code}")
def close_room(code: str, request: CloseRoomRequest) -> dict[str, bool]:
    try:
        rooms.close(code, request.host_capability)
        return {"ok": True}
    except LobbyError as error:
        raise translate_error(error) from error

