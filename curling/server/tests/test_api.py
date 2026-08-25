from __future__ import annotations

import importlib
import os

from fastapi.testclient import TestClient


def test_health_room_lifecycle_and_malformed_request(monkeypatch) -> None:
    monkeypatch.setenv("CURLING_MASTER_SECRET", "api-test-master-secret-0000000000000000")
    monkeypatch.setenv("CURLING_RELAY_AUTOSTART", "0")
    monkeypatch.setenv("CURLING_PUBLIC_RELAY_HOST", "127.0.0.1")
    import lobby_api.main as main_module

    main_module = importlib.reload(main_module)
    with TestClient(main_module.app) as client:
        health = client.get("/healthz")
        assert health.status_code == 200
        assert health.json()["protocol_version"] == 2
        old_client = client.post("/v1/rooms", json={"nickname": "旧客户端", "ends": 1, "protocol_version": 1})
        assert old_client.status_code == 409
        malformed = client.post("/v1/rooms", json={"nickname": "x", "ends": 3, "protocol_version": 2})
        assert malformed.status_code == 422
        created = client.post("/v1/rooms", json={"nickname": "房主", "ends": 1, "is_public": True, "protocol_version": 2})
        assert created.status_code == 200
        session = created.json()
        listed = client.get("/v1/rooms").json()["rooms"]
        assert listed[0]["code"] == session["code"]
        joined = client.post(
            f"/v1/rooms/{session['code']}/join",
            json={"nickname": "队员", "protocol_version": 2},
        )
        assert joined.status_code == 200
        resumed = client.post(
            f"/v1/rooms/{session['code']}/resume",
            json={
                "player_id": joined.json()["player_id"],
                "session_token": joined.json()["session_token"],
                "protocol_version": 2,
            },
        )
        assert resumed.status_code == 200
        roster = [
            {"id": str(index), "nickname": "选手%d" % index, "connected": True}
            for index in range(8)
        ]
        heartbeat = client.post(
            f"/v1/rooms/{session['code']}/heartbeat",
            json={"host_capability": session["host_capability"], "phase": "waiting", "roster": roster},
        )
        assert heartbeat.status_code == 200
        oversized_heartbeat = client.post(
            f"/v1/rooms/{session['code']}/heartbeat",
            json={
                "host_capability": session["host_capability"],
                "phase": "waiting",
                "roster": roster + [{"id": "8", "nickname": "选手八", "connected": True}],
            },
        )
        assert oversized_heartbeat.status_code == 422
        closed = client.request(
            "DELETE",
            f"/v1/rooms/{session['code']}",
            json={"host_capability": session["host_capability"]},
        )
        assert closed.status_code == 200
