from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
import threading
from collections import deque
from dataclasses import dataclass
from typing import Any


PASSWORD_ITERATIONS = 310_000


class LoginAttemptLimiter:
    """Small in-memory guard for a single-owner local appliance."""

    def __init__(self, maximum_attempts: int = 5, window_seconds: int = 300) -> None:
        self.maximum_attempts = maximum_attempts
        self.window_seconds = window_seconds
        self._attempts: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def allowed(self, key: str, now: float | None = None) -> bool:
        timestamp = time.time() if now is None else now
        with self._lock:
            attempts = self._attempts.setdefault(key, deque())
            while attempts and timestamp - attempts[0] >= self.window_seconds:
                attempts.popleft()
            return len(attempts) < self.maximum_attempts

    def record_failure(self, key: str, now: float | None = None) -> None:
        timestamp = time.time() if now is None else now
        with self._lock:
            self._attempts.setdefault(key, deque()).append(timestamp)

    def reset(self, key: str) -> None:
        with self._lock:
            self._attempts.pop(key, None)


def _b64_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + padding)


def hash_password(password: str, salt: bytes | None = None) -> tuple[str, str]:
    actual_salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        actual_salt,
        PASSWORD_ITERATIONS,
    )
    return _b64_encode(actual_salt), _b64_encode(digest)


def verify_password(password: str, salt_text: str, digest_text: str) -> bool:
    salt = _b64_decode(salt_text)
    _, candidate = hash_password(password, salt)
    return hmac.compare_digest(candidate, digest_text)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


@dataclass(frozen=True, slots=True)
class AccessClaims:
    subject: str
    email: str
    expires_at: int
    issued_at: int
    token_id: str


def create_access_token(
    *,
    subject: str,
    email: str,
    secret_key: str,
    lifetime_seconds: int = 900,
) -> tuple[str, int]:
    now = int(time.time())
    expires_at = now + lifetime_seconds
    payload = {
        "sub": subject,
        "email": email,
        "iat": now,
        "exp": expires_at,
        "jti": secrets.token_urlsafe(12),
        "typ": "access",
    }
    payload_part = _b64_encode(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signature = hmac.new(secret_key.encode("utf-8"), payload_part.encode("ascii"), hashlib.sha256).digest()
    return f"{payload_part}.{_b64_encode(signature)}", expires_at


def verify_access_token(token: str, secret_key: str) -> AccessClaims:
    try:
        payload_part, signature_part = token.split(".", 1)
        expected = hmac.new(
            secret_key.encode("utf-8"),
            payload_part.encode("ascii"),
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(expected, _b64_decode(signature_part)):
            raise ValueError("Invalid token signature.")
        payload: dict[str, Any] = json.loads(_b64_decode(payload_part))
        if payload.get("typ") != "access":
            raise ValueError("Invalid token type.")
        if int(payload["exp"]) <= int(time.time()):
            raise ValueError("Access token has expired.")
        return AccessClaims(
            subject=str(payload["sub"]),
            email=str(payload["email"]),
            expires_at=int(payload["exp"]),
            issued_at=int(payload["iat"]),
            token_id=str(payload["jti"]),
        )
    except (KeyError, ValueError, TypeError, json.JSONDecodeError) as exc:
        raise ValueError("Invalid access token.") from exc
