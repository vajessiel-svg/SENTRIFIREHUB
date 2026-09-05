import unittest

from app.domain import AlarmLevel, DetectionStateMachine, Sensitivity


class DetectionStateMachineTests(unittest.TestCase):
    def test_balanced_requires_three_positive_frames(self) -> None:
        machine = DetectionStateMachine(Sensitivity.BALANCED)

        self.assertEqual(machine.process(timestamp=0, confidence=0.70).level, AlarmLevel.SUSPECTED)
        self.assertEqual(machine.process(timestamp=1, confidence=0.70).level, AlarmLevel.SUSPECTED)
        self.assertEqual(machine.process(timestamp=2, confidence=0.70).level, AlarmLevel.CONFIRMED)

    def test_confirmed_detection_escalates_then_clears_with_hysteresis(self) -> None:
        machine = DetectionStateMachine(Sensitivity.BALANCED)
        for timestamp in (0, 1, 2):
            machine.process(timestamp=timestamp, confidence=0.90)

        self.assertEqual(machine.process(timestamp=13, confidence=0.90).level, AlarmLevel.CRITICAL)
        self.assertEqual(machine.process(timestamp=14, confidence=0.0).level, AlarmLevel.CRITICAL)
        self.assertEqual(machine.process(timestamp=24, confidence=0.0).level, AlarmLevel.NORMAL)

    def test_screen_detection_suppresses_a_fire_box(self) -> None:
        machine = DetectionStateMachine(Sensitivity.HIGH)
        decision = machine.process(timestamp=0, confidence=0.99, screen_suppressed=True)

        self.assertEqual(decision.level, AlarmLevel.NORMAL)
        self.assertTrue(decision.screen_suppressed)

    def test_advanced_threshold_and_offline_state(self) -> None:
        machine = DetectionStateMachine(Sensitivity.HIGH, advanced_confidence=0.80)
        self.assertEqual(machine.process(timestamp=0, confidence=0.70).level, AlarmLevel.NORMAL)
        self.assertEqual(machine.mark_offline().level, AlarmLevel.OFFLINE)


if __name__ == "__main__":
    unittest.main()
