from __future__ import annotations

import logging
import shutil
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable

from .alarm import AlarmController
from .config import CameraConfig, Settings
from .database import Database
from .domain import AlarmLevel, DetectionStateMachine, Sensitivity
from .notifications import NotificationService


LOGGER = logging.getLogger(__name__)
MODEL_VERSION = "yolov8n-fire-v1"


@dataclass(slots=True)
class CameraRuntime:
    id: str
    name: str
    location: str
    stream_path: str
    enabled: bool
    online: bool = False
    level: str = AlarmLevel.OFFLINE.value
    confidence: float = 0.0
    last_seen_at: float | None = None
    connection_message: str | None = "Waiting for camera stream."
    active_event_id: str | None = None
    confirmed_latched: bool = False
    screen_suppressed: bool = False
    last_event_update_at: float = 0.0


class EventCoordinator:
    def __init__(
        self,
        *,
        settings: Settings,
        database: Database,
        alarm: AlarmController,
        notifications: NotificationService,
    ) -> None:
        self.settings = settings
        self.database = database
        self.alarm = alarm
        self.notifications = notifications
        self._lock = threading.RLock()
        self._publisher: Callable[[dict], None] | None = None
        self._machines: dict[str, DetectionStateMachine] = {}
        self._cameras: dict[str, CameraRuntime] = {}
        self._camera_configs = {camera.id: camera for camera in settings.cameras}
        self._last_thumbnail_at: dict[str, float] = {}

        closed_events = database.close_open_events()
        if closed_events:
            LOGGER.warning("Closed %s stale open event(s) during startup.", closed_events)

        defaults = self.default_alarm_settings()
        defaults["sensitivity"] = settings.sensitivity
        defaults["advanced_confidence"] = settings.advanced_confidence
        stored = database.get_setting("alarm", defaults)
        self._alarm_settings = {**defaults, **stored}
        sensitivity = self._safe_sensitivity(str(self._alarm_settings["sensitivity"]))
        advanced = self._alarm_settings.get("advanced_confidence")
        for camera in settings.cameras:
            self._machines[camera.id] = DetectionStateMachine(sensitivity, advanced)
            self._cameras[camera.id] = CameraRuntime(
                id=camera.id,
                name=camera.name,
                location=camera.location,
                stream_path=camera.stream_path,
                enabled=camera.enabled,
            )
        alarm.set_siren_enabled(bool(self._alarm_settings["siren_enabled"]))

    def set_publisher(self, publisher: Callable[[dict], None]) -> None:
        self._publisher = publisher

    @staticmethod
    def default_alarm_settings() -> dict:
        return {
            "sensitivity": "balanced",
            "advanced_confidence": None,
            "siren_enabled": True,
            "notifications_enabled": True,
            "suspected_notifications": False,
        }

    @staticmethod
    def _safe_sensitivity(value: str) -> Sensitivity:
        try:
            return Sensitivity(value)
        except ValueError:
            return Sensitivity.BALANCED

    def _publish(self, message_type: str, data: dict) -> None:
        publisher = self._publisher
        if publisher:
            publisher({"type": message_type, "data": data, "timestamp": time.time()})

    def alarm_settings(self) -> dict:
        with self._lock:
            return dict(self._alarm_settings)

    def update_alarm_settings(self, values: dict, owner_id: str) -> dict:
        with self._lock:
            previous = dict(self._alarm_settings)
            self._alarm_settings = {**self._alarm_settings, **values}
            sensitivity = self._safe_sensitivity(str(self._alarm_settings["sensitivity"]))
            advanced = self._alarm_settings.get("advanced_confidence")
            for machine in self._machines.values():
                machine.configure(sensitivity.value, advanced)
            self.alarm.set_siren_enabled(bool(self._alarm_settings["siren_enabled"]))
            self.database.set_setting("alarm", self._alarm_settings, owner_id)
            self.database.audit(
                owner_id=owner_id,
                action="alarm_settings_updated",
                details={"before": previous, "after": self._alarm_settings},
            )
            current = dict(self._alarm_settings)
        self._publish("alarm_settings", current)
        return current

    def on_connection(self, camera: CameraConfig, online: bool, reason: str | None) -> None:
        with self._lock:
            runtime = self._cameras[camera.id]
            runtime.online = online
            runtime.connection_message = reason
            if online:
                runtime.last_seen_at = time.time()
                if runtime.level == AlarmLevel.OFFLINE.value:
                    runtime.level = AlarmLevel.NORMAL.value
            else:
                decision = self._machines[camera.id].mark_offline()
                runtime.level = decision.level.value
            payload = self._camera_payload(runtime)
            self._sync_global_alarm()
        self._publish("camera_status", payload)

    def on_detection(
        self,
        camera: CameraConfig,
        confidence: float,
        screen_suppressed: bool,
        frame,
    ) -> None:
        now = time.time()
        with self._lock:
            runtime = self._cameras[camera.id]
            runtime.online = True
            runtime.last_seen_at = now
            runtime.connection_message = None
            self._save_thumbnail(camera.id, frame, now)
            decision = self._machines[camera.id].process(
                timestamp=now,
                confidence=confidence,
                screen_suppressed=screen_suppressed,
            )
            runtime.level = decision.level.value
            runtime.confidence = decision.confidence
            runtime.screen_suppressed = screen_suppressed

            if decision.level == AlarmLevel.SUSPECTED:
                if runtime.active_event_id is None:
                    event_id = self.database.create_event(
                        camera_id=camera.id,
                        camera_name=camera.name,
                        location=camera.location,
                        level=decision.level.value,
                        confidence=decision.confidence,
                        snapshot_path=None,
                        model_version=MODEL_VERSION,
                        sensitivity=str(self._alarm_settings["sensitivity"]),
                    )
                    runtime.active_event_id = event_id
                    runtime.last_event_update_at = now
                    snapshot_path = self._save_snapshot(event_id, frame)
                    if snapshot_path:
                        self.database.set_event_snapshot(event_id, snapshot_path)
                    if bool(self._alarm_settings.get("suspected_notifications", False)):
                        self._notify(runtime, decision.level.value, event_id)
                elif decision.changed or now - runtime.last_event_update_at >= 1.0:
                    self.database.update_event(
                        runtime.active_event_id,
                        level=decision.level.value,
                        confidence=decision.confidence,
                    )
                    runtime.last_event_update_at = now
            elif decision.level in {AlarmLevel.CONFIRMED, AlarmLevel.CRITICAL}:
                runtime.confirmed_latched = True
                if runtime.active_event_id is None:
                    event_id = self.database.create_event(
                        camera_id=camera.id,
                        camera_name=camera.name,
                        location=camera.location,
                        level=decision.level.value,
                        confidence=decision.confidence,
                        snapshot_path=None,
                        model_version=MODEL_VERSION,
                        sensitivity=str(self._alarm_settings["sensitivity"]),
                    )
                    runtime.active_event_id = event_id
                    runtime.last_event_update_at = now
                    snapshot_path = self._save_snapshot(event_id, frame)
                    if snapshot_path:
                        self.database.set_event_snapshot(event_id, snapshot_path)
                    self._notify(runtime, decision.level.value, event_id)
                elif decision.changed or now - runtime.last_event_update_at >= 1.0:
                    self.database.update_event(
                        runtime.active_event_id,
                        level=decision.level.value,
                        confidence=decision.confidence,
                    )
                    runtime.last_event_update_at = now
                    if decision.changed:
                        self._notify(runtime, decision.level.value, runtime.active_event_id)
            elif decision.level == AlarmLevel.NORMAL and runtime.active_event_id:
                self.database.close_event(runtime.active_event_id)
                runtime.active_event_id = None
                runtime.confirmed_latched = False
                runtime.last_event_update_at = 0.0

            self._sync_global_alarm()
            payload = self._camera_payload(runtime)
        self._publish("camera_status", payload)
        if decision.changed:
            self._publish("event_transition", payload)

    def _save_snapshot(self, event_id: str, frame) -> str | None:
        try:
            import cv2

            self.settings.snapshot_dir.mkdir(parents=True, exist_ok=True)
            filename = f"{event_id}.jpg"
            path = self.settings.snapshot_dir / filename
            if cv2.imwrite(str(path), frame):
                return filename
        except Exception:
            LOGGER.exception("Could not save event snapshot.")
        return None

    def _save_thumbnail(self, camera_id: str, frame, timestamp: float) -> None:
        if timestamp - self._last_thumbnail_at.get(camera_id, 0) < 2:
            return
        try:
            import cv2

            self.settings.snapshot_dir.mkdir(parents=True, exist_ok=True)
            safe_id = ''.join(character if character.isalnum() or character in {'-', '_'} else '_' for character in camera_id)
            path = self.settings.snapshot_dir / f"latest-{safe_id}.jpg"
            resized = cv2.resize(frame, (480, 270))
            if cv2.imwrite(str(path), resized):
                self._last_thumbnail_at[camera_id] = timestamp
        except Exception:
            LOGGER.debug("Could not update thumbnail for %s", camera_id, exc_info=True)

    def _notify(self, runtime: CameraRuntime, level: str, event_id: str) -> None:
        if not bool(self._alarm_settings.get("notifications_enabled", True)):
            return
        self.notifications.send_fire_alert(
            tokens=self.database.list_device_tokens(),
            camera_id=runtime.id,
            camera_name=runtime.name,
            location=runtime.location,
            level=level,
            confidence=runtime.confidence,
            event_id=event_id,
        )

    def _sync_global_alarm(self) -> None:
        active_event_levels: list[AlarmLevel] = []
        for runtime in self._cameras.values():
            if not runtime.active_event_id:
                continue
            if runtime.level == AlarmLevel.CRITICAL.value and runtime.confirmed_latched:
                active_event_levels.append(AlarmLevel.CRITICAL)
            elif runtime.confirmed_latched:
                # A confirmed alarm remains latched if its camera disconnects.
                active_event_levels.append(AlarmLevel.CONFIRMED)
        if AlarmLevel.CRITICAL in active_event_levels:
            level = AlarmLevel.CRITICAL
        elif AlarmLevel.CONFIRMED in active_event_levels:
            level = AlarmLevel.CONFIRMED
        elif any(runtime.level == AlarmLevel.SUSPECTED.value for runtime in self._cameras.values()):
            level = AlarmLevel.SUSPECTED
        elif any(runtime.level == AlarmLevel.OFFLINE.value for runtime in self._cameras.values()):
            level = AlarmLevel.OFFLINE
        else:
            level = AlarmLevel.NORMAL
        self.alarm.sync_level(level)

    def _camera_payload(self, runtime: CameraRuntime) -> dict:
        payload = asdict(runtime)
        payload.pop("last_event_update_at", None)
        payload["stream_url"] = f"{self.settings.stream_base_url}/{runtime.stream_path}/index.m3u8"
        safe_id = ''.join(character if character.isalnum() or character in {'-', '_'} else '_' for character in runtime.id)
        payload["thumbnail_url"] = f"{self.settings.public_base_url}/api/v1/media/latest-{safe_id}.jpg"
        payload["updated_at"] = time.time()
        return payload

    def cameras(self) -> list[dict]:
        with self._lock:
            return [self._camera_payload(runtime) for runtime in self._cameras.values()]

    def system_health(self, detector_health: dict | None = None) -> dict:
        usage = shutil.disk_usage(self.settings.database_path.parent)
        temperature = None
        thermal_path = Path("/sys/class/thermal/thermal_zone0/temp")
        try:
            if thermal_path.exists():
                temperature = int(thermal_path.read_text().strip()) / 1000
        except (OSError, ValueError):
            pass
        alarm_snapshot = self.alarm.snapshot()
        return {
            "api_online": True,
            "model_path": str(self.settings.model_path.name),
            "model_version": MODEL_VERSION,
            "detector": detector_health or {},
            "pi_temperature_c": temperature,
            "disk_free_bytes": usage.free,
            "disk_total_bytes": usage.total,
            "push_notifications_configured": self.notifications.configured,
            "alarm": asdict(alarm_snapshot),
            "server_time": time.time(),
        }

    def acknowledge_event(self, event_id: str, owner_id: str) -> bool:
        updated = self.database.acknowledge_event(event_id, owner_id)
        if updated:
            self.database.audit(owner_id=owner_id, action="event_acknowledged", details={"event_id": event_id})
            self._publish("event_updated", {"event_id": event_id})
        return updated

    def mark_false_alarm(self, event_id: str, owner_id: str, reason: str) -> bool:
        event = self.database.get_event(event_id)
        if event is None:
            return False
        updated = self.database.mark_false_alarm(event_id, owner_id, reason)
        if not updated:
            return False
        with self._lock:
            runtime = self._cameras.get(str(event["camera_id"]))
            if runtime and runtime.active_event_id == event_id:
                runtime.active_event_id = None
                runtime.confirmed_latched = False
                runtime.last_event_update_at = 0.0
                runtime.level = AlarmLevel.NORMAL.value
                runtime.confidence = 0.0
                self._machines[runtime.id].reset()
            self._sync_global_alarm()
        self.database.audit(
            owner_id=owner_id,
            action="event_marked_false_alarm",
            details={"event_id": event_id, "reason": reason},
        )
        self._publish("event_updated", {"event_id": event_id, "false_alarm": True})
        return True
