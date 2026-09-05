from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass

from .config import Settings
from .domain import AlarmLevel


LOGGER = logging.getLogger(__name__)


class _MockOutput:
    def __init__(self, name: str) -> None:
        self.name = name
        self.value = False

    def on(self) -> None:
        if not self.value:
            LOGGER.info("%s ON (mock GPIO)", self.name)
        self.value = True

    def off(self) -> None:
        if self.value:
            LOGGER.info("%s OFF (mock GPIO)", self.name)
        self.value = False

    def close(self) -> None:
        self.off()


def _output_device(pin: int, *, name: str, active_high: bool, enabled: bool):
    if enabled:
        try:
            from gpiozero import OutputDevice

            return OutputDevice(pin, active_high=active_high, initial_value=False)
        except Exception:
            LOGGER.exception("GPIO initialization failed for %s; using mock output.", name)
    return _MockOutput(name)


@dataclass(frozen=True, slots=True)
class AlarmSnapshot:
    siren_active: bool
    silenced_until: float | None
    manual_override: bool
    test_running: bool


class AlarmController:
    def __init__(self, settings: Settings) -> None:
        self._lock = threading.RLock()
        self._relay = _output_device(
            settings.relay_pin,
            name="Siren relay",
            active_high=not settings.relay_active_low,
            enabled=settings.gpio_enabled,
        )
        self._red_led = _output_device(
            settings.red_led_pin,
            name="Red LED",
            active_high=True,
            enabled=settings.gpio_enabled,
        )
        self._green_led = _output_device(
            settings.green_led_pin,
            name="Green LED",
            active_high=True,
            enabled=settings.gpio_enabled,
        )
        self._silenced_until: float | None = None
        self._silence_timer: threading.Timer | None = None
        self._manual_override = False
        self._test_running = False
        self._last_level = AlarmLevel.NORMAL
        self._siren_enabled = True
        self._apply_outputs()

    def snapshot(self) -> AlarmSnapshot:
        with self._lock:
            self._expire_silence()
            return AlarmSnapshot(
                siren_active=bool(self._relay.value),
                silenced_until=self._silenced_until,
                manual_override=self._manual_override,
                test_running=self._test_running,
            )

    def set_siren_enabled(self, enabled: bool) -> None:
        with self._lock:
            self._siren_enabled = enabled
            self._apply_outputs()

    def sync_level(self, level: AlarmLevel) -> None:
        with self._lock:
            self._last_level = level
            self._apply_outputs()

    def activate_manual(self) -> None:
        with self._lock:
            self._manual_override = True
            self._silenced_until = None
            self._apply_outputs()

    def cancel_manual(self) -> None:
        with self._lock:
            self._manual_override = False
            self._apply_outputs()

    def silence_temporarily(self, minutes: int) -> float:
        bounded_minutes = max(1, min(minutes, 30))
        with self._lock:
            self._manual_override = False
            self._silenced_until = time.time() + bounded_minutes * 60
            if self._silence_timer is not None:
                self._silence_timer.cancel()
            self._silence_timer = threading.Timer(
                bounded_minutes * 60,
                self._resume_after_silence,
            )
            self._silence_timer.daemon = True
            self._silence_timer.start()
            self._apply_outputs()
            return self._silenced_until

    def cancel_silence(self) -> None:
        with self._lock:
            if self._silence_timer is not None:
                self._silence_timer.cancel()
                self._silence_timer = None
            self._silenced_until = None
            self._apply_outputs()

    def _resume_after_silence(self) -> None:
        with self._lock:
            self._silence_timer = None
            self._silenced_until = None
            self._apply_outputs()

    def test(self, seconds: int = 5) -> None:
        bounded_seconds = max(1, min(seconds, 10))
        with self._lock:
            if self._test_running:
                return
            self._test_running = True
            self._apply_outputs()

        def finish() -> None:
            time.sleep(bounded_seconds)
            with self._lock:
                self._test_running = False
                self._apply_outputs()

        threading.Thread(target=finish, name="alarm-test", daemon=True).start()

    def _expire_silence(self) -> None:
        if self._silenced_until is not None and self._silenced_until <= time.time():
            self._silenced_until = None

    def _apply_outputs(self) -> None:
        self._expire_silence()
        is_alert = self._last_level in {AlarmLevel.CONFIRMED, AlarmLevel.CRITICAL}
        should_sound = self._test_running or self._manual_override or (
            is_alert and self._siren_enabled and self._silenced_until is None
        )
        if should_sound:
            self._relay.on()
        else:
            self._relay.off()

        if self._last_level in {
            AlarmLevel.SUSPECTED,
            AlarmLevel.CONFIRMED,
            AlarmLevel.CRITICAL,
            AlarmLevel.OFFLINE,
        }:
            self._red_led.on()
            self._green_led.off()
        else:
            self._red_led.off()
            self._green_led.on()

    def close(self) -> None:
        with self._lock:
            if self._silence_timer is not None:
                self._silence_timer.cancel()
            self._relay.close()
            self._red_led.close()
            self._green_led.close()
