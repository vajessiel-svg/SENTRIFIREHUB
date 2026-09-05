from __future__ import annotations

import logging
from pathlib import Path
from typing import Iterable


LOGGER = logging.getLogger(__name__)


class NotificationService:
    def __init__(self, service_account: Path | None) -> None:
        self._messaging = None
        if service_account is None:
            LOGGER.info("Firebase push notifications are not configured.")
            return
        if not service_account.exists():
            LOGGER.warning("Firebase service-account file does not exist: %s", service_account)
            return
        try:
            import firebase_admin
            from firebase_admin import credentials, messaging

            if not firebase_admin._apps:
                firebase_admin.initialize_app(credentials.Certificate(str(service_account)))
            self._messaging = messaging
            LOGGER.info("Firebase push notifications enabled.")
        except Exception:
            LOGGER.exception("Firebase initialization failed; continuing without push notifications.")

    @property
    def configured(self) -> bool:
        return self._messaging is not None

    def send_fire_alert(
        self,
        *,
        tokens: Iterable[str],
        camera_id: str,
        camera_name: str,
        location: str,
        level: str,
        confidence: float,
        event_id: str,
    ) -> None:
        token_list = list(dict.fromkeys(token for token in tokens if token))
        if self._messaging is None or not token_list:
            return
        title = {
            "critical": "Critical fire alert",
            "confirmed": "Fire detected",
            "suspected": "Possible fire detected",
        }.get(level, "SentriFire alert")
        body = f"{camera_name} — {location} ({confidence * 100:.0f}% confidence)"
        message = self._messaging.MulticastMessage(
            tokens=token_list,
            notification=self._messaging.Notification(title=title, body=body),
            data={
                "type": "fire_alert",
                "event_id": event_id,
                "camera_id": camera_id,
                "level": level,
                "confidence": f"{confidence:.5f}",
            },
            android=self._messaging.AndroidConfig(
                priority="high",
                notification=self._messaging.AndroidNotification(
                    channel_id="sentrifire_critical_alerts",
                    priority="max",
                    visibility="public",
                    sound="default",
                ),
            ),
        )
        try:
            self._messaging.send_each_for_multicast(message)
        except Exception:
            LOGGER.exception("Failed to send fire alert notification.")
