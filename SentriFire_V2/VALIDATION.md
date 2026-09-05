# Validation record

Validated in the delivery workspace on 2026-08-28:

- 10/10 Python unit tests passed for password/token security, login throttling, SQLite owner/event lifecycle, stale-event recovery, sensitivity thresholds, temporal confirmation, escalation, clearing hysteresis, offline state, and future screen suppression.
- All backend Python files compiled successfully.
- Both Raspberry Pi shell scripts passed `bash -n` syntax validation.
- Flutter `pubspec.yaml` and MediaMTX YAML parsed successfully.
- The included model matches the uploaded `best.pt` byte-for-byte with SHA-256 `4f64f75d8a10deb4c0079622018fa876a9d55a13eb1058114aa4315b5dd8620d`.

The current delivery environment does not contain Flutter/Dart, Android SDK, Raspberry Pi GPIO hardware, the three Tapo cameras, or project Firebase credentials. Therefore `flutter pub get`, `flutter analyze`, `flutter test`, Android build/install, real RTSP/HLS playback, YOLO runtime performance, GPIO polarity, siren electrical load, Firebase delivery, and real-site model acceptance remain mandatory target-environment checks. Run `./verify_source.sh`, then complete `docs/ACCEPTANCE_TESTS.md` on the actual hardware.

