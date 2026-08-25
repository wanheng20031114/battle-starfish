from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from typing import Any

TICKET_PREFIX = "ct1"


def random_hex(byte_count: int = 32) -> str:
    return secrets.token_hex(byte_count)


def token_digest(master_secret: str, token: str) -> str:
    return hmac.new(master_secret.encode(), token.encode(), hashlib.sha256).hexdigest()


def issue_ticket(
    room_secret: str,
    *,
    protocol_version: int,
    room_id: str,
    role: str,
    nickname: str,
    player_id: str,
    ttl_seconds: int,
    now: int | None = None,
) -> tuple[str, int]:
    issued_at = int(time.time()) if now is None else now
    expires_at = issued_at + ttl_seconds
    claims: dict[str, Any] = {
        "v": protocol_version,
        "room_id": room_id,
        "role": role,
        "player_name": nickname,
        "player_id": player_id,
        "iat": issued_at,
        "exp": expires_at,
        "nonce": random_hex(16),
    }
    raw = json.dumps(claims, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    payload = base64.urlsafe_b64encode(raw).decode().rstrip("=")
    message = f"{TICKET_PREFIX}.{payload}"
    signature = hmac.new(room_secret.encode(), message.encode(), hashlib.sha256).hexdigest()
    return f"{message}.{signature}", expires_at


def verify_token(master_secret: str, token: str, expected_digest: str) -> bool:
    if len(token) != 64 or len(expected_digest) != 64:
        return False
    return hmac.compare_digest(token_digest(master_secret, token), expected_digest)

