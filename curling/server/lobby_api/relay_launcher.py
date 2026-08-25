from __future__ import annotations

import asyncio
import os
from pathlib import Path
import subprocess
from dataclasses import dataclass

from .config import MAX_PLAYERS, Settings


@dataclass(slots=True)
class RelayProcess:
    room_id: str
    port: int
    process: subprocess.Popen[bytes]


class RelayLauncher:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._processes: dict[str, RelayProcess] = {}

    def start(self, room_id: str, port: int, admission_secret: str) -> None:
        if not self.settings.relay_autostart:
            return
        if room_id in self._processes:
            raise RuntimeError("relay already exists")
        environment = os.environ.copy()
        environment.update(
            {
                "CURLING_ROOM_ID": room_id,
                "CURLING_RELAY_PORT": str(port),
                "CURLING_ADMISSION_SECRET": admission_secret,
                "CURLING_MAX_CLIENTS": str(MAX_PLAYERS),
                "CURLING_PROTOCOL_VERSION": str(self.settings.protocol_version),
            }
        )
        command = [
            self.settings.godot_binary,
            "--headless",
            "--path",
            str(self.settings.relay_project_path),
            "--scene",
            "res://relay.tscn",
        ]
        process = subprocess.Popen(
            command,
            cwd=self.settings.relay_project_path,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=None,
            stderr=None,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        self._processes[room_id] = RelayProcess(room_id, port, process)

    def stop(self, room_id: str) -> None:
        relay = self._processes.pop(room_id, None)
        if relay is None or relay.process.poll() is not None:
            return
        relay.process.terminate()
        try:
            relay.process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            relay.process.kill()
            relay.process.wait(timeout=2)

    def stop_all(self) -> None:
        for room_id in list(self._processes):
            self.stop(room_id)

    def reap(self) -> list[str]:
        exited: list[str] = []
        for room_id, relay in list(self._processes.items()):
            if relay.process.poll() is not None:
                exited.append(room_id)
                self._processes.pop(room_id, None)
        return exited
