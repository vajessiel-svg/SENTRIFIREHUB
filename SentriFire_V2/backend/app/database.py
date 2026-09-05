from __future__ import annotations

import json
import sqlite3
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from .security import hash_password, hash_refresh_token


def utc_timestamp() -> float:
    return time.time()


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._write_lock = threading.RLock()

    @contextmanager
    def connection(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.path, timeout=10, check_same_thread=False)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 10000")
        try:
            yield connection
            connection.commit()
        finally:
            connection.close()

    def initialize(self) -> None:
        schema = """
        CREATE TABLE IF NOT EXISTS owners (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password_salt TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS refresh_tokens (
            id TEXT PRIMARY KEY,
            owner_id TEXT NOT NULL REFERENCES owners(id) ON DELETE CASCADE,
            token_hash TEXT NOT NULL UNIQUE,
            expires_at REAL NOT NULL,
            created_at REAL NOT NULL,
            revoked_at REAL
        );

        CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            camera_id TEXT NOT NULL,
            camera_name TEXT NOT NULL,
            location TEXT NOT NULL,
            level TEXT NOT NULL,
            peak_confidence REAL NOT NULL DEFAULT 0,
            started_at REAL NOT NULL,
            ended_at REAL,
            snapshot_path TEXT,
            acknowledged_at REAL,
            acknowledged_by TEXT,
            false_alarm INTEGER NOT NULL DEFAULT 0,
            false_alarm_reason TEXT,
            model_version TEXT NOT NULL,
            sensitivity TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_events_started_at ON events(started_at DESC);
        CREATE INDEX IF NOT EXISTS idx_events_camera_id ON events(camera_id);
        CREATE INDEX IF NOT EXISTS idx_events_active ON events(ended_at) WHERE ended_at IS NULL;

        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL,
            updated_at REAL NOT NULL,
            updated_by TEXT
        );

        CREATE TABLE IF NOT EXISTS device_tokens (
            token TEXT PRIMARY KEY,
            owner_id TEXT NOT NULL REFERENCES owners(id) ON DELETE CASCADE,
            platform TEXT NOT NULL,
            created_at REAL NOT NULL,
            last_seen_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS audit_log (
            id TEXT PRIMARY KEY,
            owner_id TEXT,
            action TEXT NOT NULL,
            details_json TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """
        with self._write_lock, self.connection() as connection:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute("PRAGMA synchronous = NORMAL")
            connection.executescript(schema)

    def ensure_owner(self, *, name: str, email: str, password: str) -> dict[str, Any]:
        with self._write_lock, self.connection() as connection:
            row = connection.execute(
                "SELECT * FROM owners WHERE email = ?",
                (email.lower(),),
            ).fetchone()
            if row is not None:
                return dict(row)
            salt, digest = hash_password(password)
            now = utc_timestamp()
            owner_id = str(uuid.uuid4())
            connection.execute(
                """
                INSERT INTO owners(id, name, email, password_salt, password_hash, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (owner_id, name, email.lower(), salt, digest, now, now),
            )
            # Return the inserted record directly. Opening a second connection here
            # would race the commit performed when this context manager exits.
            return {
                "id": owner_id,
                "name": name,
                "email": email.lower(),
                "password_salt": salt,
                "password_hash": digest,
                "created_at": now,
                "updated_at": now,
            }

    def get_owner_by_email(self, email: str) -> dict[str, Any] | None:
        with self.connection() as connection:
            row = connection.execute(
                "SELECT * FROM owners WHERE email = ?",
                (email.lower(),),
            ).fetchone()
            return dict(row) if row else None

    def get_owner(self, owner_id: str) -> dict[str, Any] | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM owners WHERE id = ?", (owner_id,)).fetchone()
            return dict(row) if row else None

    def change_password(self, owner_id: str, new_password: str) -> None:
        salt, digest = hash_password(new_password)
        with self._write_lock, self.connection() as connection:
            connection.execute(
                "UPDATE owners SET password_salt = ?, password_hash = ?, updated_at = ? WHERE id = ?",
                (salt, digest, utc_timestamp(), owner_id),
            )
            connection.execute(
                "UPDATE refresh_tokens SET revoked_at = ? WHERE owner_id = ? AND revoked_at IS NULL",
                (utc_timestamp(), owner_id),
            )

    def store_refresh_token(self, *, owner_id: str, token: str, expires_at: float) -> None:
        with self._write_lock, self.connection() as connection:
            connection.execute(
                """
                INSERT INTO refresh_tokens(id, owner_id, token_hash, expires_at, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (str(uuid.uuid4()), owner_id, hash_refresh_token(token), expires_at, utc_timestamp()),
            )

    def consume_refresh_token(self, token: str) -> dict[str, Any] | None:
        token_hash = hash_refresh_token(token)
        with self._write_lock, self.connection() as connection:
            row = connection.execute(
                """
                SELECT refresh_tokens.*, owners.email, owners.name
                FROM refresh_tokens
                JOIN owners ON owners.id = refresh_tokens.owner_id
                WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?
                """,
                (token_hash, utc_timestamp()),
            ).fetchone()
            if row is None:
                return None
            connection.execute(
                "UPDATE refresh_tokens SET revoked_at = ? WHERE id = ?",
                (utc_timestamp(), row["id"]),
            )
            return dict(row)

    def revoke_refresh_token(self, token: str) -> None:
        with self._write_lock, self.connection() as connection:
            connection.execute(
                "UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL",
                (utc_timestamp(), hash_refresh_token(token)),
            )

    def create_event(
        self,
        *,
        camera_id: str,
        camera_name: str,
        location: str,
        level: str,
        confidence: float,
        snapshot_path: str | None,
        model_version: str,
        sensitivity: str,
    ) -> str:
        event_id = str(uuid.uuid4())
        with self._write_lock, self.connection() as connection:
            connection.execute(
                """
                INSERT INTO events(
                    id, camera_id, camera_name, location, level, peak_confidence,
                    started_at, snapshot_path, model_version, sensitivity
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    event_id,
                    camera_id,
                    camera_name,
                    location,
                    level,
                    confidence,
                    utc_timestamp(),
                    snapshot_path,
                    model_version,
                    sensitivity,
                ),
            )
        return event_id

    def update_event(self, event_id: str, *, level: str, confidence: float) -> None:
        with self._write_lock, self.connection() as connection:
            connection.execute(
                """
                UPDATE events
                SET level = ?, peak_confidence = MAX(peak_confidence, ?)
                WHERE id = ?
                """,
                (level, confidence, event_id),
            )

    def set_event_snapshot(self, event_id: str, snapshot_path: str) -> None:
        with self._write_lock, self.connection() as connection:
            connection.execute(
                "UPDATE events SET snapshot_path = ? WHERE id = ?",
                (snapshot_path, event_id),
            )

    def close_event(self, event_id: str) -> None:
        with self._write_lock, self.connection() as connection:
            connection.execute(
                "UPDATE events SET ended_at = COALESCE(ended_at, ?) WHERE id = ?",
                (utc_timestamp(), event_id),
            )

    def close_open_events(self) -> int:
        """Close events left open by an earlier process interruption.

        Cameras must re-confirm from live frames after restart; stale database
        rows must not impersonate a current alarm.
        """
        with self._write_lock, self.connection() as connection:
            cursor = connection.execute(
                "UPDATE events SET ended_at = ? WHERE ended_at IS NULL",
                (utc_timestamp(),),
            )
            return cursor.rowcount

    def acknowledge_event(self, event_id: str, owner_id: str) -> bool:
        with self._write_lock, self.connection() as connection:
            cursor = connection.execute(
                "UPDATE events SET acknowledged_at = ?, acknowledged_by = ? WHERE id = ?",
                (utc_timestamp(), owner_id, event_id),
            )
            return cursor.rowcount > 0

    def mark_false_alarm(self, event_id: str, owner_id: str, reason: str) -> bool:
        with self._write_lock, self.connection() as connection:
            cursor = connection.execute(
                """
                UPDATE events
                SET false_alarm = 1, false_alarm_reason = ?, acknowledged_at = ?,
                    acknowledged_by = ?, ended_at = COALESCE(ended_at, ?)
                WHERE id = ?
                """,
                (reason, utc_timestamp(), owner_id, utc_timestamp(), event_id),
            )
            return cursor.rowcount > 0

    def get_event(self, event_id: str) -> dict[str, Any] | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
            return dict(row) if row else None

    def list_events(
        self,
        *,
        limit: int = 100,
        camera_id: str | None = None,
        level: str | None = None,
        active_only: bool = False,
    ) -> list[dict[str, Any]]:
        clauses: list[str] = []
        parameters: list[Any] = []
        if camera_id:
            clauses.append("camera_id = ?")
            parameters.append(camera_id)
        if level:
            clauses.append("level = ?")
            parameters.append(level)
        if active_only:
            clauses.append("ended_at IS NULL")
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        parameters.append(max(1, min(limit, 500)))
        with self.connection() as connection:
            rows = connection.execute(
                f"SELECT * FROM events {where} ORDER BY started_at DESC LIMIT ?",
                parameters,
            ).fetchall()
            return [dict(row) for row in rows]

    def set_setting(self, key: str, value: dict[str, Any], owner_id: str | None) -> None:
        with self._write_lock, self.connection() as connection:
            connection.execute(
                """
                INSERT INTO settings(key, value_json, updated_at, updated_by)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value_json = excluded.value_json,
                    updated_at = excluded.updated_at,
                    updated_by = excluded.updated_by
                """,
                (key, json.dumps(value, separators=(",", ":")), utc_timestamp(), owner_id),
            )

    def get_setting(self, key: str, default: dict[str, Any]) -> dict[str, Any]:
        with self.connection() as connection:
            row = connection.execute("SELECT value_json FROM settings WHERE key = ?", (key,)).fetchone()
            if row is None:
                return default
            try:
                value = json.loads(row["value_json"])
                return value if isinstance(value, dict) else default
            except json.JSONDecodeError:
                return default

    def register_device_token(self, *, token: str, owner_id: str, platform: str) -> None:
        now = utc_timestamp()
        with self._write_lock, self.connection() as connection:
            connection.execute(
                """
                INSERT INTO device_tokens(token, owner_id, platform, created_at, last_seen_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(token) DO UPDATE SET owner_id = excluded.owner_id,
                    platform = excluded.platform, last_seen_at = excluded.last_seen_at
                """,
                (token, owner_id, platform, now, now),
            )

    def list_device_tokens(self) -> list[str]:
        with self.connection() as connection:
            rows = connection.execute("SELECT token FROM device_tokens ORDER BY last_seen_at DESC").fetchall()
            return [str(row["token"]) for row in rows]

    def audit(self, *, owner_id: str | None, action: str, details: dict[str, Any]) -> None:
        with self._write_lock, self.connection() as connection:
            connection.execute(
                "INSERT INTO audit_log(id, owner_id, action, details_json, created_at) VALUES (?, ?, ?, ?, ?)",
                (str(uuid.uuid4()), owner_id, action, json.dumps(details, separators=(",", ":")), utc_timestamp()),
            )
