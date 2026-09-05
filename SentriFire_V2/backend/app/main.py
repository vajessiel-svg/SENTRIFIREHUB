from __future__ import annotations

import asyncio
import logging
import time
from contextlib import asynccontextmanager
from dataclasses import asdict
from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, FastAPI, HTTPException, Query, Request, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .alarm import AlarmController
from .config import settings
from .database import Database
from .detector import DetectionService
from .notifications import NotificationService
from .runtime import EventCoordinator
from .schemas import (
    AlarmSettingsRequest,
    AlarmTestRequest,
    ChangePasswordRequest,
    DeviceTokenRequest,
    FalseAlarmRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    SilenceRequest,
)
from .security import (
    LoginAttemptLimiter,
    create_access_token,
    new_refresh_token,
    verify_access_token,
    verify_password,
)


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
LOGGER = logging.getLogger(__name__)
REFRESH_LIFETIME_SECONDS = 30 * 24 * 60 * 60


class BroadcastHub:
    def __init__(self) -> None:
        self._clients: set[WebSocket] = set()
        self._lock = asyncio.Lock()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self._lock:
            self._clients.add(websocket)

    async def disconnect(self, websocket: WebSocket) -> None:
        async with self._lock:
            self._clients.discard(websocket)

    async def broadcast(self, message: dict) -> None:
        async with self._lock:
            clients = list(self._clients)
        dead: list[WebSocket] = []
        for client in clients:
            try:
                await client.send_json(message)
            except Exception:
                dead.append(client)
        if dead:
            async with self._lock:
                for client in dead:
                    self._clients.discard(client)


database = Database(settings.database_path)
# Runtime state reads settings during construction, so the schema must exist
# before the coordinator is created (including when an ASGI server imports app).
database.initialize()
alarm = AlarmController(settings)
notifications = NotificationService(settings.firebase_service_account)
coordinator = EventCoordinator(
    settings=settings,
    database=database,
    alarm=alarm,
    notifications=notifications,
)
detector = DetectionService(
    settings,
    on_connection=coordinator.on_connection,
    on_detection=coordinator.on_detection,
)
hub = BroadcastHub()
login_limiter = LoginAttemptLimiter()


@asynccontextmanager
async def lifespan(_: FastAPI):
    problems = settings.validate()
    if problems:
        joined = "\n- ".join(problems)
        raise RuntimeError(f"SentriFire configuration is incomplete:\n- {joined}")
    settings.snapshot_dir.mkdir(parents=True, exist_ok=True)
    database.initialize()
    database.ensure_owner(
        name=settings.owner_name,
        email=settings.owner_email,
        password=settings.owner_password,
    )
    loop = asyncio.get_running_loop()

    def publish_from_thread(message: dict) -> None:
        asyncio.run_coroutine_threadsafe(hub.broadcast(message), loop)

    coordinator.set_publisher(publish_from_thread)
    detector.start()
    LOGGER.info("SentriFire backend started.")
    try:
        yield
    finally:
        detector.stop()
        alarm.close()
        LOGGER.info("SentriFire backend stopped.")


app = FastAPI(
    title="SentriFire API",
    description="Local-first fire detection, alarm, event, and camera status API.",
    version="2.0.0",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=list(settings.allowed_origins),
    allow_credentials=settings.allowed_origins != ("*",),
    allow_methods=["*"],
    allow_headers=["*"],
)
settings.snapshot_dir.mkdir(parents=True, exist_ok=True)

bearer = HTTPBearer(auto_error=False)


def current_owner(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> dict[str, Any]:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Authentication required.")
    try:
        claims = verify_access_token(credentials.credentials, settings.secret_key)
    except ValueError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session has expired.") from None
    owner = database.get_owner(claims.subject)
    if owner is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Owner account not found.")
    return owner


def token_pair(owner: dict[str, Any]) -> dict[str, Any]:
    access_token, access_expires_at = create_access_token(
        subject=str(owner["id"]),
        email=str(owner["email"]),
        secret_key=settings.secret_key,
    )
    refresh_token = new_refresh_token()
    refresh_expires_at = time.time() + REFRESH_LIFETIME_SECONDS
    database.store_refresh_token(
        owner_id=str(owner["id"]),
        token=refresh_token,
        expires_at=refresh_expires_at,
    )
    return {
        "access_token": access_token,
        "access_expires_at": access_expires_at,
        "refresh_token": refresh_token,
        "refresh_expires_at": refresh_expires_at,
        "token_type": "bearer",
        "owner": {
            "id": owner["id"],
            "name": owner["name"],
            "email": owner["email"],
            "role": "owner",
        },
    }


def event_payload(event: dict[str, Any]) -> dict[str, Any]:
    payload = dict(event)
    payload["false_alarm"] = bool(payload.get("false_alarm"))
    filename = payload.get("snapshot_path")
    payload["snapshot_url"] = (
        f"{settings.public_base_url}/api/v1/media/{filename}" if filename else None
    )
    return payload


@app.get("/")
def root() -> dict[str, str]:
    return {"name": "SentriFire API", "version": "2.0.0", "status": "online"}


@app.get("/health")
def health() -> dict[str, Any]:
    detector_health = detector.health
    return {
        "api_online": True,
        "detector_running": detector_health.running,
        "model_loaded": detector_health.model_loaded,
    }


@app.post("/api/v1/auth/login")
def login(payload: LoginRequest, request: Request) -> dict[str, Any]:
    normalized_email = payload.email.strip().lower()
    client_host = request.client.host if request.client else "unknown"
    limiter_key = f"{client_host}:{normalized_email}"
    if not login_limiter.allowed(limiter_key):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many login attempts. Wait five minutes before trying again.",
            headers={"Retry-After": "300"},
        )
    owner = database.get_owner_by_email(normalized_email)
    if owner is None or not verify_password(
        payload.password,
        str(owner["password_salt"]),
        str(owner["password_hash"]),
    ):
        login_limiter.record_failure(limiter_key)
        database.audit(
            owner_id=None,
            action="login_failed",
            details={"email": payload.email.strip().lower(), "ip": request.client.host if request.client else None},
        )
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Incorrect email or password.")
    login_limiter.reset(limiter_key)
    database.audit(owner_id=str(owner["id"]), action="login_success", details={})
    return token_pair(owner)


@app.post("/api/v1/auth/refresh")
def refresh(payload: RefreshRequest) -> dict[str, Any]:
    token_record = database.consume_refresh_token(payload.refresh_token)
    if token_record is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Remembered session has expired.")
    owner = database.get_owner(str(token_record["owner_id"]))
    if owner is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Owner account not found.")
    return token_pair(owner)


@app.post("/api/v1/auth/logout")
def logout(payload: LogoutRequest) -> dict[str, bool]:
    database.revoke_refresh_token(payload.refresh_token)
    return {"logged_out": True}


@app.post("/api/v1/auth/change-password")
def change_password(
    payload: ChangePasswordRequest,
    owner: Annotated[dict[str, Any], Depends(current_owner)],
) -> dict[str, bool]:
    if not verify_password(
        payload.current_password,
        str(owner["password_salt"]),
        str(owner["password_hash"]),
    ):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Current password is incorrect.")
    database.change_password(str(owner["id"]), payload.new_password)
    database.audit(owner_id=str(owner["id"]), action="password_changed", details={})
    return {"changed": True, "reauthentication_required": True}


@app.get("/api/v1/bootstrap")
def bootstrap(owner: Annotated[dict[str, Any], Depends(current_owner)]) -> dict[str, Any]:
    events = [event_payload(event) for event in database.list_events(limit=100)]
    return {
        "owner": {
            "id": owner["id"],
            "name": owner["name"],
            "email": owner["email"],
            "role": "owner",
        },
        "cameras": coordinator.cameras(),
        "events": events,
        "alarm_settings": coordinator.alarm_settings(),
        "system_health": coordinator.system_health(asdict(detector.health)),
        "server_time": time.time(),
    }


@app.get("/api/v1/cameras")
def cameras(_: Annotated[dict[str, Any], Depends(current_owner)]) -> list[dict]:
    return coordinator.cameras()


@app.get("/api/v1/media/{filename}")
def protected_media(
    filename: str,
    _: Annotated[dict[str, Any], Depends(current_owner)],
) -> FileResponse:
    safe_name = Path(filename).name
    if safe_name != filename or not safe_name.lower().endswith((".jpg", ".jpeg")):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Image not found.")
    path = settings.snapshot_dir / safe_name
    if not path.is_file():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Image not found.")
    return FileResponse(path, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


@app.get("/api/v1/events")
def events(
    _: Annotated[dict[str, Any], Depends(current_owner)],
    limit: int = Query(100, ge=1, le=500),
    camera_id: str | None = None,
    level: str | None = None,
    active_only: bool = False,
) -> list[dict[str, Any]]:
    return [
        event_payload(event)
        for event in database.list_events(
            limit=limit,
            camera_id=camera_id,
            level=level,
            active_only=active_only,
        )
    ]


@app.post("/api/v1/events/{event_id}/acknowledge")
def acknowledge_event(
    event_id: str,
    owner: Annotated[dict[str, Any], Depends(current_owner)],
) -> dict[str, bool]:
    if not coordinator.acknowledge_event(event_id, str(owner["id"])):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Event not found.")
    return {"acknowledged": True}


@app.post("/api/v1/events/{event_id}/false-alarm")
def false_alarm(
    event_id: str,
    payload: FalseAlarmRequest,
    owner: Annotated[dict[str, Any], Depends(current_owner)],
) -> dict[str, bool]:
    if not coordinator.mark_false_alarm(event_id, str(owner["id"]), payload.reason.strip()):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Event not found.")
    return {"updated": True}


@app.get("/api/v1/alarm/settings")
def get_alarm_settings(_: Annotated[dict[str, Any], Depends(current_owner)]) -> dict:
    return coordinator.alarm_settings()


@app.put("/api/v1/alarm/settings")
def update_alarm_settings(
    payload: AlarmSettingsRequest,
    owner: Annotated[dict[str, Any], Depends(current_owner)],
) -> dict:
    return coordinator.update_alarm_settings(payload.model_dump(), str(owner["id"]))


@app.post("/api/v1/alarm/activate")
def activate_alarm(owner: Annotated[dict[str, Any], Depends(current_owner)]) -> dict[str, bool]:
    alarm.activate_manual()
    database.audit(owner_id=str(owner["id"]), action="manual_alarm_activated", details={})
    return {"active": True}


@app.post("/api/v1/alarm/cancel-manual")
def cancel_manual_alarm(owner: Annotated[dict[str, Any], Depends(current_owner)]) -> dict[str, bool]:
    alarm.cancel_manual()
    database.audit(owner_id=str(owner["id"]), action="manual_alarm_cancelled", details={})
    return {"active": False}


@app.post("/api/v1/alarm/silence")
def silence_alarm(
    payload: SilenceRequest,
    owner: Annotated[dict[str, Any], Depends(current_owner)],
) -> dict[str, Any]:
    silenced_until = alarm.silence_temporarily(payload.minutes)
    database.audit(
        owner_id=str(owner["id"]),
        action="alarm_temporarily_silenced",
        details={"minutes": payload.minutes, "silenced_until": silenced_until},
    )
    return {"silenced_until": silenced_until}


@app.post("/api/v1/alarm/cancel-silence")
def cancel_silence(owner: Annotated[dict[str, Any], Depends(current_owner)]) -> dict[str, bool]:
    alarm.cancel_silence()
    database.audit(owner_id=str(owner["id"]), action="alarm_silence_cancelled", details={})
    return {"cancelled": True}


@app.post("/api/v1/alarm/test")
def test_alarm(
    payload: AlarmTestRequest,
    owner: Annotated[dict[str, Any], Depends(current_owner)],
) -> dict[str, int]:
    alarm.test(payload.seconds)
    database.audit(
        owner_id=str(owner["id"]),
        action="alarm_test_started",
        details={"seconds": payload.seconds},
    )
    return {"seconds": payload.seconds}


@app.get("/api/v1/system/health")
def system_health(_: Annotated[dict[str, Any], Depends(current_owner)]) -> dict[str, Any]:
    return coordinator.system_health(asdict(detector.health))


@app.post("/api/v1/devices/register")
def register_device(
    payload: DeviceTokenRequest,
    owner: Annotated[dict[str, Any], Depends(current_owner)],
) -> dict[str, bool]:
    database.register_device_token(
        token=payload.token,
        owner_id=str(owner["id"]),
        platform=payload.platform,
    )
    return {"registered": True}


@app.websocket("/ws/status")
async def status_socket(websocket: WebSocket, token: str = Query(...)) -> None:
    try:
        verify_access_token(token, settings.secret_key)
    except ValueError:
        await websocket.close(code=4401)
        return
    await hub.connect(websocket)
    await websocket.send_json(
        {
            "type": "bootstrap",
            "data": {
                "cameras": coordinator.cameras(),
                "alarm_settings": coordinator.alarm_settings(),
            },
            "timestamp": time.time(),
        }
    )
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        await hub.disconnect(websocket)
    except Exception:
        await hub.disconnect(websocket)
