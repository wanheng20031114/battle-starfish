from __future__ import annotations

import base64
import hashlib
import hmac
import json

from lobby_api.security import issue_ticket, token_digest, verify_token


def decode_claims(ticket: str) -> dict[str, object]:
    prefix, encoded, signature = ticket.split(".")
    expected = hmac.new(
        b"r" * 64,
        f"{prefix}.{encoded}".encode(),
        hashlib.sha256,
    ).hexdigest()
    assert hmac.compare_digest(signature, expected)
    padded = encoded + "=" * (-len(encoded) % 4)
    return json.loads(base64.urlsafe_b64decode(padded))


def test_ticket_contract_and_expiry() -> None:
    ticket, expires_at = issue_ticket(
        "r" * 64,
        protocol_version=2,
        room_id="room-1",
        role="host",
        nickname="测试玩家",
        player_id="player-1",
        ttl_seconds=30,
        now=1_700_000_000,
    )
    claims = decode_claims(ticket)
    assert ticket.startswith("ct1.")
    assert claims["v"] == 2
    assert claims["room_id"] == "room-1"
    assert claims["player_name"] == "测试玩家"
    assert claims["iat"] == 1_700_000_000
    assert claims["exp"] == expires_at == 1_700_000_030
    assert len(str(claims["nonce"])) == 32


def test_resume_token_digest_is_constant_contract() -> None:
    digest = token_digest("m" * 64, "a" * 64)
    assert len(digest) == 64
    assert verify_token("m" * 64, "a" * 64, digest)
    assert not verify_token("m" * 64, "b" * 64, digest)
    assert not verify_token("m" * 64, "short", digest)
