from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


BACKEND_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(BACKEND_ROOT / ".env")


def _bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def _optional_float(name: str) -> float | None:
    value = os.getenv(name, "").strip()
    if not value:
        return None
    try:
        return max(0.05, min(0.95, float(value)))
    except ValueError:
        return None


def _path(name: str, default: str) -> Path:
    raw = Path(os.getenv(name, default))
    return raw if raw.is_absolute() else BACKEND_ROOT / raw


@dataclass(frozen=True, slots=True)
class CameraConfig:
    id: str
    name: str
    location: str
    rtsp_url: str
    stream_path: str
    enabled: bool


@dataclass(frozen=True, slots=True)
class Settings:
    environment: str
    host: str
    port: int
    secret_key: str
    owner_name: str
    owner_email: str
    owner_password: str
    database_path: Path
    model_path: Path
    snapshot_dir: Path
    public_base_url: str
    stream_base_url: str
    allowed_origins: tuple[str, ...]
    sensitivity: str
    advanced_confidence: float | None
    gpio_enabled: bool
    relay_pin: int
    relay_active_low: bool
    red_led_pin: int
    green_led_pin: int
    firebase_service_account: Path | None
    cameras: tuple[CameraConfig, ...]

    @classmethod
    def from_environment(cls) -> "Settings":
        firebase_raw = os.getenv("FIREBASE_SERVICE_ACCOUNT", "").strip()
        firebase_path = None
        if firebase_raw:
            candidate = Path(firebase_raw)
            firebase_path = candidate if candidate.is_absolute() else BACKEND_ROOT / candidate

        cameras: list[CameraConfig] = []
        for number in range(1, 4):
            prefix = f"CAMERA_{number}_"
            cameras.append(
                CameraConfig(
                    id=os.getenv(prefix + "ID", f"cam-{number:03d}"),
                    name=os.getenv(prefix + "NAME", f"Camera {number}"),
                    location=os.getenv(prefix + "LOCATION", f"Location {number}"),
                    rtsp_url=os.getenv(prefix + "RTSP_URL", "").strip(),
                    stream_path=os.getenv(prefix + "STREAM_PATH", f"cam{number}"),
                    enabled=_bool(prefix + "ENABLED", True),
                )
            )

        origins_raw = os.getenv("SENTRIFIRE_ALLOWED_ORIGINS", "*")
        origins = tuple(value.strip() for value in origins_raw.split(",") if value.strip())

        return cls(
            environment=os.getenv("APP_ENV", "development").strip().lower(),
            host=os.getenv("SENTRIFIRE_HOST", "0.0.0.0"),
            port=_int("SENTRIFIRE_PORT", 8000),
            secret_key=os.getenv("SENTRIFIRE_SECRET_KEY", ""),
            owner_name=os.getenv("SENTRIFIRE_OWNER_NAME", "Owner"),
            owner_email=os.getenv("SENTRIFIRE_OWNER_EMAIL", "").strip().lower(),
            owner_password=os.getenv("SENTRIFIRE_OWNER_PASSWORD", ""),
            database_path=_path("SENTRIFIRE_DATABASE_PATH", "data/sentrifire.db"),
            model_path=_path("SENTRIFIRE_MODEL_PATH", "models/best.pt"),
            snapshot_dir=_path("SENTRIFIRE_SNAPSHOT_DIR", "data/snapshots"),
            public_base_url=os.getenv("SENTRIFIRE_PUBLIC_BASE_URL", "http://127.0.0.1:8000").rstrip("/"),
            stream_base_url=os.getenv("SENTRIFIRE_STREAM_BASE_URL", "http://127.0.0.1:8888").rstrip("/"),
            allowed_origins=origins or ("*",),
            sensitivity=os.getenv("SENTRIFIRE_SENSITIVITY", "balanced").strip().lower(),
            advanced_confidence=_optional_float("SENTRIFIRE_ADVANCED_CONFIDENCE"),
            gpio_enabled=_bool("SENTRIFIRE_GPIO_ENABLED", False),
            relay_pin=_int("SENTRIFIRE_RELAY_PIN", 17),
            relay_active_low=_bool("SENTRIFIRE_RELAY_ACTIVE_LOW", True),
            red_led_pin=_int("SENTRIFIRE_RED_LED_PIN", 27),
            green_led_pin=_int("SENTRIFIRE_GREEN_LED_PIN", 22),
            firebase_service_account=firebase_path,
            cameras=tuple(cameras),
        )

    def validate(self) -> list[str]:
        problems: list[str] = []
        if len(self.secret_key) < 32:
            problems.append("SENTRIFIRE_SECRET_KEY must contain at least 32 characters.")
        if not self.owner_email or "@" not in self.owner_email:
            problems.append("SENTRIFIRE_OWNER_EMAIL must be a valid email address.")
        if len(self.owner_password) < 10:
            problems.append("SENTRIFIRE_OWNER_PASSWORD must contain at least 10 characters.")
        if not self.model_path.exists():
            problems.append(f"Model file not found: {self.model_path}")
        if self.sensitivity not in {"high", "balanced", "reduced_false_alarms"}:
            problems.append("SENTRIFIRE_SENSITIVITY is not a supported preset.")
        if self.environment == "production":
            for camera in self.cameras:
                if camera.enabled and not camera.rtsp_url:
                    problems.append(f"RTSP URL is missing for {camera.name}.")
        return problems


settings = Settings.from_environment()
