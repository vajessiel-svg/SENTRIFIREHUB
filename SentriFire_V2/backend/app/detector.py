from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass
from typing import Callable

from .config import CameraConfig, Settings


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class DetectorHealth:
    running: bool
    model_loaded: bool
    reason: str | None


class CameraStream:
    """Continuously keeps only the latest frame to prevent inference latency."""

    def __init__(
        self,
        camera: CameraConfig,
        *,
        on_connection: Callable[[CameraConfig, bool, str | None], None],
    ) -> None:
        self.camera = camera
        self._on_connection = on_connection
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._frame = None
        self._generation = 0
        self._online = False
        self._connection_reason: str | None = None

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._thread = threading.Thread(
            target=self._run,
            name=f"stream-{self.camera.id}",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=3)

    def latest(self):
        with self._lock:
            return self._generation, self._frame

    def _set_online(self, online: bool, reason: str | None = None) -> None:
        if online == self._online and reason == self._connection_reason:
            return
        self._online = online
        self._connection_reason = reason
        self._on_connection(self.camera, online, reason)

    def _run(self) -> None:
        try:
            import cv2
        except ImportError:
            self._set_online(False, "OpenCV is not installed.")
            return

        while not self._stop.is_set():
            if not self.camera.enabled or not self.camera.rtsp_url:
                self._set_online(False, "Camera is disabled or RTSP URL is missing.")
                self._stop.wait(5)
                continue

            capture = cv2.VideoCapture(self.camera.rtsp_url, cv2.CAP_FFMPEG)
            capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            if not capture.isOpened():
                self._set_online(False, "Unable to open RTSP stream.")
                capture.release()
                self._stop.wait(3)
                continue

            self._set_online(True)
            failures = 0
            while not self._stop.is_set():
                ok, frame = capture.read()
                if not ok or frame is None:
                    failures += 1
                    if failures >= 8:
                        break
                    continue
                failures = 0
                with self._lock:
                    self._frame = frame
                    self._generation += 1

            capture.release()
            self._set_online(False, "RTSP stream interrupted; reconnecting.")
            self._stop.wait(2)


class DetectionService:
    def __init__(
        self,
        settings: Settings,
        *,
        on_connection: Callable[[CameraConfig, bool, str | None], None],
        on_detection: Callable[[CameraConfig, float, bool, object], None],
    ) -> None:
        self.settings = settings
        self._on_connection = on_connection
        self._on_detection = on_detection
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._streams = [
            CameraStream(camera, on_connection=on_connection)
            for camera in settings.cameras
        ]
        self._last_generations: dict[str, int] = {}
        self._model = None
        self._reason: str | None = None

    @property
    def health(self) -> DetectorHealth:
        return DetectorHealth(
            running=bool(self._thread and self._thread.is_alive()),
            model_loaded=self._model is not None,
            reason=self._reason,
        )

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        try:
            from ultralytics import YOLO

            self._model = YOLO(str(self.settings.model_path))
            names = getattr(self._model, "names", {})
            LOGGER.info("Loaded model %s with classes %s", self.settings.model_path, names)
        except Exception as exc:
            self._reason = f"Model could not be loaded: {exc}"
            LOGGER.exception(self._reason)
            return

        for stream in self._streams:
            stream.start()
        self._thread = threading.Thread(target=self._run, name="inference", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        for stream in self._streams:
            stream.stop()
        if self._thread:
            self._thread.join(timeout=5)

    @staticmethod
    def _inside(inner: tuple[float, float, float, float], outer: tuple[float, float, float, float]) -> bool:
        ix1, iy1, ix2, iy2 = inner
        ox1, oy1, ox2, oy2 = outer
        return ix1 >= ox1 and iy1 >= oy1 and ix2 <= ox2 and iy2 <= oy2

    def _predict(self, frame) -> tuple[float, bool]:
        if self._model is None:
            return 0.0, False
        results = self._model.predict(
            source=frame,
            imgsz=640,
            conf=0.20,
            iou=0.70,
            verbose=False,
        )
        if not results:
            return 0.0, False
        result = results[0]
        boxes = getattr(result, "boxes", None)
        if boxes is None or len(boxes) == 0:
            return 0.0, False

        names = getattr(result, "names", {})
        fire_boxes: list[tuple[float, tuple[float, float, float, float]]] = []
        screen_boxes: list[tuple[float, float, float, float]] = []
        for box in boxes:
            class_index = int(box.cls[0].item())
            class_name = str(names.get(class_index, class_index)).lower()
            confidence = float(box.conf[0].item())
            coordinates = tuple(float(value) for value in box.xyxy[0].tolist())
            if class_name == "fire":
                fire_boxes.append((confidence, coordinates))
            elif class_name in {"display_screen", "screen", "tv", "monitor"}:
                screen_boxes.append(coordinates)

        if not fire_boxes:
            return 0.0, False
        unsuppressed = [
            item
            for item in fire_boxes
            if not any(self._inside(item[1], screen_box) for screen_box in screen_boxes)
        ]
        if unsuppressed:
            confidence, _ = max(unsuppressed, key=lambda item: item[0])
            return confidence, False
        confidence, _ = max(fire_boxes, key=lambda item: item[0])
        return confidence, bool(screen_boxes)

    def _run(self) -> None:
        while not self._stop.is_set():
            processed = False
            for stream in self._streams:
                generation, frame = stream.latest()
                if frame is None or generation == self._last_generations.get(stream.camera.id):
                    continue
                self._last_generations[stream.camera.id] = generation
                processed = True
                try:
                    confidence, screen_suppressed = self._predict(frame)
                    self._on_detection(
                        stream.camera,
                        confidence,
                        screen_suppressed,
                        frame,
                    )
                except Exception:
                    LOGGER.exception("Inference failed for %s", stream.camera.name)
            if not processed:
                self._stop.wait(0.03)
