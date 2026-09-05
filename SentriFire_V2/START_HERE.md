# SentriFire V2 — Start Here

This package upgrades the submitted Flutter prototype into a local-first mobile and Raspberry Pi system for three Tapo C230 cameras. It includes the supplied `best.pt`, a tested alarm state machine, live camera status, event history, manual alarm controls, secure remembered login with a four-digit PIN, optional biometrics, and optional Firebase push notifications.

## Important boundary

SentriFire is an early-warning research system, not a certified fire-alarm control panel. Keep code-compliant smoke/heat detectors, evacuation procedures, and manual call points in place. Never make evacuation depend only on a camera, Wi-Fi, a phone, the Pi, or this model.

## What is included

| Folder | Purpose |
|---|---|
| `mobile/` | Flutter app with real API data, PIN unlock, cameras, alerts, history, settings, and system health |
| `backend/` | FastAPI service, YOLO inference, SQLite history, alarm/GPIO control, authentication, and push notifications |
| `deploy/` | Raspberry Pi installer, MediaMTX camera gateway, and systemd services |
| `docs/` | Architecture, model findings, calibration plan, and acceptance tests |

No real account, Tapo, Wi-Fi, Firebase, or signing credentials are included.

## Recommended physical setup

- Raspberry Pi 5 with 64-bit Raspberry Pi OS, active cooling, an official-capacity power supply, and a small UPS.
- Pi connected to the router by Ethernet. The three C230 cameras may stay on Wi-Fi.
- DHCP reservations for the Pi and each camera so addresses do not change.
- A separately powered siren through a correctly rated, opto-isolated relay. Do not power a siren directly from a GPIO pin.
- Keep the Pi, router, relay supply, and network equipment away from the protected fire-risk area when possible.

## Installation order

1. In the Tapo app, update each camera, reserve its IP on the router, and create a separate **camera account**. Do not use the main Tapo cloud password.
2. Test each standard-quality feed in VLC: `rtsp://CAMERA_USER:CAMERA_PASSWORD@CAMERA_IP:554/stream2`.
3. Copy this `SentriFire_V2` folder to the Pi.
4. On the Pi, run:

   ```bash
   cd SentriFire_V2
   sudo bash deploy/install_pi.sh
   ```

5. Edit `/opt/sentrifire/backend/.env` and `/opt/sentrifire/mediamtx/mediamtx.yml`. Replace every `CHANGE_ME` value. URL-encode special characters in RTSP usernames/passwords.
6. Validate and start both services:

   ```bash
   sudo bash /opt/sentrifire/deploy/enable_services.sh
   ```

7. Follow `mobile/README.md` to build and install the Android app.
8. Complete every test in `docs/ACCEPTANCE_TESTS.md` before demonstrating or piloting the system.

## The five design decisions that matter most

1. **One camera connection:** MediaMTX pulls each Tapo feed once, then gives a local RTSP feed to YOLO and HLS to the phone. This reduces camera load.
2. **No one-frame alarms:** presets combine confidence, multiple frames, escalation time, and clearing hysteresis.
3. **Fast access without storing the password:** the phone stores rotating session tokens and a salted PIN hash in platform secure storage. The account password is not saved.
4. **Fail-safe manual adjustment:** sensitivity, temporary silence, siren test, manual activation, and manual cancellation are audited. Silence automatically expires; detection and logging continue while silenced.
5. **Offline clarity:** cached status opens after PIN unlock when the Pi cannot be reached, but the UI clearly labels it offline/stale. Physical alarm processing remains on the Pi.

## Before calling it finished

The supplied model detects only one class: `fire`. It does not detect smoke and cannot recognize a TV/phone screen as a separate class. The software contains future-ready screen-suppression logic, but that logic becomes active only after retraining a multi-class model. Read `docs/MODEL_AND_CALIBRATION.md` before choosing a threshold.

