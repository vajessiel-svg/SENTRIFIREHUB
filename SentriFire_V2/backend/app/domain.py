from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from enum import StrEnum


class AlarmLevel(StrEnum):
    NORMAL = "normal"
    SUSPECTED = "suspected"
    CONFIRMED = "confirmed"
    CRITICAL = "critical"
    OFFLINE = "offline"


class Sensitivity(StrEnum):
    HIGH = "high"
    BALANCED = "balanced"
    REDUCED_FALSE_ALARMS = "reduced_false_alarms"


@dataclass(frozen=True, slots=True)
class SensitivityRule:
    confidence: float
    window_size: int
    required_hits: int
    critical_after_seconds: float
    clear_after_seconds: float


PRESET_RULES: dict[Sensitivity, SensitivityRule] = {
    Sensitivity.HIGH: SensitivityRule(
        confidence=0.35,
        window_size=3,
        required_hits=2,
        critical_after_seconds=8.0,
        clear_after_seconds=8.0,
    ),
    Sensitivity.BALANCED: SensitivityRule(
        confidence=0.50,
        window_size=5,
        required_hits=3,
        critical_after_seconds=12.0,
        clear_after_seconds=10.0,
    ),
    Sensitivity.REDUCED_FALSE_ALARMS: SensitivityRule(
        confidence=0.65,
        window_size=6,
        required_hits=4,
        critical_after_seconds=15.0,
        clear_after_seconds=12.0,
    ),
}


@dataclass(frozen=True, slots=True)
class DetectionDecision:
    previous_level: AlarmLevel
    level: AlarmLevel
    confidence: float
    changed: bool
    screen_suppressed: bool


class DetectionStateMachine:
    """Converts noisy per-frame predictions into stable alarm states.

    Preset values are safe starting points only. They must be calibrated using
    real Tapo C230 day, night, and false-positive test footage.
    """

    def __init__(
        self,
        sensitivity: Sensitivity = Sensitivity.BALANCED,
        advanced_confidence: float | None = None,
    ) -> None:
        self._sensitivity = sensitivity
        self._advanced_confidence = advanced_confidence
        self._history: deque[bool] = deque(maxlen=self.rule.window_size)
        self.level = AlarmLevel.NORMAL
        self.last_confidence = 0.0
        self.first_positive_at: float | None = None
        self.last_positive_at: float | None = None

    @property
    def rule(self) -> SensitivityRule:
        base = PRESET_RULES[self._sensitivity]
        if self._advanced_confidence is None:
            return base
        return SensitivityRule(
            confidence=max(0.05, min(0.95, self._advanced_confidence)),
            window_size=base.window_size,
            required_hits=base.required_hits,
            critical_after_seconds=base.critical_after_seconds,
            clear_after_seconds=base.clear_after_seconds,
        )

    def configure(self, sensitivity: str, advanced_confidence: float | None) -> None:
        self._sensitivity = Sensitivity(sensitivity)
        self._advanced_confidence = advanced_confidence
        old_history = list(self._history)
        self._history = deque(old_history[-self.rule.window_size :], maxlen=self.rule.window_size)

    def mark_offline(self) -> DetectionDecision:
        previous = self.level
        self.level = AlarmLevel.OFFLINE
        self._history.clear()
        return DetectionDecision(previous, self.level, self.last_confidence, previous != self.level, False)

    def reset(self) -> None:
        self._history.clear()
        self.level = AlarmLevel.NORMAL
        self.last_confidence = 0.0
        self.first_positive_at = None
        self.last_positive_at = None

    def process(
        self,
        *,
        timestamp: float,
        confidence: float,
        screen_suppressed: bool = False,
    ) -> DetectionDecision:
        previous = self.level
        bounded_confidence = max(0.0, min(1.0, confidence))
        effective_confidence = 0.0 if screen_suppressed else bounded_confidence
        positive = effective_confidence >= self.rule.confidence
        self._history.append(positive)
        self.last_confidence = bounded_confidence

        if positive:
            self.last_positive_at = timestamp
            if self.first_positive_at is None:
                self.first_positive_at = timestamp

        hits = sum(self._history)
        enough_frames = len(self._history) >= self.rule.required_hits and hits >= self.rule.required_hits

        if enough_frames:
            if self.level in {AlarmLevel.NORMAL, AlarmLevel.SUSPECTED, AlarmLevel.OFFLINE}:
                self.level = AlarmLevel.CONFIRMED
            positive_started_at = (
                timestamp if self.first_positive_at is None else self.first_positive_at
            )
            confirmed_duration = timestamp - positive_started_at
            if confirmed_duration >= self.rule.critical_after_seconds:
                self.level = AlarmLevel.CRITICAL
        elif positive or hits > 0:
            if self.level not in {AlarmLevel.CONFIRMED, AlarmLevel.CRITICAL}:
                self.level = AlarmLevel.SUSPECTED
        else:
            last_positive = self.last_positive_at
            if last_positive is None or timestamp - last_positive >= self.rule.clear_after_seconds:
                self.level = AlarmLevel.NORMAL
                self.first_positive_at = None

        if self.level in {AlarmLevel.CONFIRMED, AlarmLevel.CRITICAL} and not positive:
            last_positive = self.last_positive_at
            if last_positive is not None and timestamp - last_positive >= self.rule.clear_after_seconds:
                self.level = AlarmLevel.NORMAL
                self.first_positive_at = None
                self._history.clear()

        return DetectionDecision(
            previous_level=previous,
            level=self.level,
            confidence=bounded_confidence,
            changed=previous != self.level,
            screen_suppressed=screen_suppressed,
        )
