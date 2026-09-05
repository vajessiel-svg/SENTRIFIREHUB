# SentriFire V2 acceptance tests

Record the phone model/Android version, Pi model/OS, app ZIP version, model checksum, camera firmware, test date, operator, and result for every run.

| ID | Test | Expected pass result |
|---|---|---|
| A01 | Cold boot Pi/router | MediaMTX and API start automatically; all cameras recover without manual app action |
| A02 | Disconnect one camera | That camera changes to Offline; other cameras continue; a previously confirmed event does not silently clear |
| A03 | Restore camera | Stream reconnects and returns to Normal after valid frames |
| A04 | Three simultaneous feeds | No continuously growing latency; Pi temperature and CPU remain acceptable for a 30-minute run |
| A05 | Balanced positive sequence | One isolated frame does not sound the siren; required repeated detections confirm it |
| A06 | Persistent confirmed detection | State escalates to Critical after the configured duration |
| A07 | Detection ends | Hysteresis prevents flicker; event closes after the clear interval |
| A08 | Manual siren activation | Confirmation is required; relay activates immediately; audit entry is created |
| A09 | Cancel manual siren | Manual override clears; an actual confirmed event may correctly keep automatic siren active |
| A10 | Temporary silence | Detection/history/push continue; warning is visible; siren resumes automatically at expiry |
| A11 | Siren test | Relay activates only for the selected bounded duration and returns to prior state |
| A12 | Wrong account password | Login rejected without revealing whether an email exists; repeated failures are rate-limited |
| A13 | Remembered login | Password is entered once; next launch requests the four-digit PIN or biometrics |
| A14 | Five wrong PIN attempts | Local session and PIN are cleared; full password login is required |
| A15 | Pi unavailable after valid PIN | App opens cached data clearly marked offline/stale; it never presents cache as live |
| A16 | Password change | Existing refresh sessions are revoked and full re-login is required |
| A17 | Push notification | Background Android device receives a high-priority alert and opening it refreshes app data |
| A18 | Snapshot privacy | Snapshot URL fails without a valid access token and loads inside the authenticated app |
| A19 | App killed/phone absent | Pi inference and physical alarm continue independently |
| A20 | Power loss | UPS behavior and safe relay state match the electrical design; services recover after power returns |

## Site-model test matrix

Run each camera through: daylight, low light, IR/night mode, lights on/off, glare, reflection, orange/red objects, phone/TV fire video, cooking/steam if relevant, people passing, camera pan/tilt, partial view blockage, and a safely controlled positive source or representative test footage.

Minimum evidence for panel review:

- raw event log and timestamps;
- false alarms per camera-hour for each condition;
- confirmed-alarm delay distribution, not only the best run;
- missed-event count;
- Pi temperature/CPU and stream latency during three-camera operation;
- screenshots of Normal, Suspected, Confirmed, Critical, Offline, temporary silence, and PIN lockout states;
- signed test sheet showing pass/fail and corrective action.

