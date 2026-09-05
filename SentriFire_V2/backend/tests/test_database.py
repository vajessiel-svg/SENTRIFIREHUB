import tempfile
import unittest
from pathlib import Path

from app.database import Database


class DatabaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.database = Database(Path(self.temporary_directory.name) / "test.db")
        self.database.initialize()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_owner_creation_is_immediately_available(self) -> None:
        owner = self.database.ensure_owner(
            name="Test Owner",
            email="OWNER@example.com",
            password="secure-test-password",
        )

        self.assertEqual(owner["email"], "owner@example.com")
        self.assertEqual(self.database.get_owner_by_email("owner@example.com")["id"], owner["id"])

    def test_event_lifecycle_and_settings(self) -> None:
        owner = self.database.ensure_owner(
            name="Test Owner",
            email="owner@example.com",
            password="secure-test-password",
        )
        event_id = self.database.create_event(
            camera_id="cam1",
            camera_name="Front Entrance",
            location="Ground floor",
            level="confirmed",
            confidence=0.80,
            snapshot_path=None,
            model_version="test",
            sensitivity="balanced",
        )

        self.database.update_event(event_id, level="critical", confidence=0.95)
        self.assertTrue(self.database.acknowledge_event(event_id, owner["id"]))
        self.database.close_event(event_id)
        event = self.database.get_event(event_id)
        self.assertEqual(event["level"], "critical")
        self.assertEqual(event["peak_confidence"], 0.95)
        self.assertIsNotNone(event["ended_at"])

        self.database.set_setting("alarm", {"sensitivity": "high"}, owner["id"])
        self.assertEqual(self.database.get_setting("alarm", {})["sensitivity"], "high")

    def test_stale_open_events_are_closed(self) -> None:
        event_id = self.database.create_event(
            camera_id="cam1",
            camera_name="Front Entrance",
            location="Ground floor",
            level="suspected",
            confidence=0.60,
            snapshot_path=None,
            model_version="test",
            sensitivity="balanced",
        )

        self.assertEqual(self.database.close_open_events(), 1)
        self.assertIsNotNone(self.database.get_event(event_id)["ended_at"])


if __name__ == "__main__":
    unittest.main()
