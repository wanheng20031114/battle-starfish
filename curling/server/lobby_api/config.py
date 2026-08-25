from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path


MAX_PLAYERS = 8


@dataclass(frozen=True, slots=True)
class Settings:
    bind_host: str
    bind_port: int
    public_relay_host: str
    relay_port_min: int
    relay_port_max: int
    max_rooms: int
    lease_timeout_seconds: int
    ticket_ttl_seconds: int
    protocol_version: int
    master_secret: str
    relay_autostart: bool
    godot_binary: str
    relay_project_path: Path


def load_settings() -> Settings:
    default_relay_project = Path(__file__).resolve().parents[1] / "relay_project"
    settings = Settings(
        bind_host=os.getenv("CURLING_BIND_HOST", "0.0.0.0"),
        bind_port=int(os.getenv("CURLING_BIND_PORT", "8010")),
        public_relay_host=os.getenv("CURLING_PUBLIC_RELAY_HOST", "47.123.6.127"),
        relay_port_min=int(os.getenv("CURLING_RELAY_PORT_MIN", "40201")),
        relay_port_max=int(os.getenv("CURLING_RELAY_PORT_MAX", "40300")),
        max_rooms=int(os.getenv("CURLING_MAX_ROOMS", "100")),
        lease_timeout_seconds=int(os.getenv("CURLING_LEASE_TIMEOUT_SECONDS", "30")),
        ticket_ttl_seconds=int(os.getenv("CURLING_TICKET_TTL_SECONDS", "30")),
        protocol_version=int(os.getenv("CURLING_PROTOCOL_VERSION", "2")),
        master_secret=os.getenv("CURLING_MASTER_SECRET", ""),
        relay_autostart=os.getenv("CURLING_RELAY_AUTOSTART", "0") == "1",
        godot_binary=os.getenv("CURLING_GODOT_BINARY", "godot"),
        relay_project_path=Path(os.getenv("CURLING_RELAY_PROJECT", str(default_relay_project))).resolve(),
    )
    if settings.relay_port_max < settings.relay_port_min:
        raise RuntimeError("CURLING_RELAY_PORT_MAX must be >= CURLING_RELAY_PORT_MIN")
    if settings.max_rooms <= 0 or settings.max_rooms > settings.relay_port_max - settings.relay_port_min + 1:
        raise RuntimeError("CURLING_MAX_ROOMS exceeds the relay port pool")
    if len(settings.master_secret) < 32:
        raise RuntimeError("CURLING_MASTER_SECRET must contain at least 32 characters")
    return settings
