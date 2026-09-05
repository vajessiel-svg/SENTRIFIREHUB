# SentriFire Raspberry Pi backend

## Local development

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
cp .env.example .env
# edit .env
python -m app
```

The API is available at the configured port; interactive API docs are at `/docs`. Use one worker only because inference, cameras, GPIO state, and WebSocket broadcasts are process-local.

Run dependency-free core tests with:

```bash
python -m unittest discover -s tests -v
```

## Configuration rules

- Generate the API secret with `python -c "import secrets; print(secrets.token_urlsafe(48))"`.
- The owner is created from `.env` only when the database has no matching owner. Later password changes must be made inside the authenticated app/API.
- Keep `.env` and Firebase service-account JSON readable only by the service account.
- `CAMERA_*_RTSP_URL` should point to the local MediaMTX RTSP paths, not directly to the Tapo cameras, in the recommended setup.
- Start with GPIO disabled. Enable it only after relay polarity and pin numbering are verified with the siren power disconnected.
- Do not expose the backend or stream ports directly to the internet.

## Runtime behavior

Each camera thread continuously replaces its previous frame. The inference loop therefore processes the newest available image instead of building a delayed queue. A single YOLO model is shared across the three camera states. Confirmed events are saved to SQLite with a protected JPEG snapshot; the physical alarm is controlled independently from the phone.

