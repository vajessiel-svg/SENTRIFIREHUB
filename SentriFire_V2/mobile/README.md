# SentriFire mobile app

## Build the Android pilot

Install a current Flutter stable SDK compatible with Dart `^3.12.2`, then run:

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=SENTRIFIRE_API_URL=http://PI_ADDRESS:8000
```

The owner can also edit the server address on the login screen. Android cleartext HTTP is enabled for the local pilot only. Use an authenticated HTTPS/VPN gateway and disable cleartext before any internet-accessible deployment.

## Optional Firebase push notifications

Create a Firebase Android app for `com.sentrifire.sentrifire_mobile`, enable Cloud Messaging, and provide the four public app configuration values at build time:

```bash
flutter run \
  --dart-define=SENTRIFIRE_API_URL=http://PI_ADDRESS:8000 \
  --dart-define=FIREBASE_API_KEY=VALUE \
  --dart-define=FIREBASE_APP_ID=VALUE \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=VALUE \
  --dart-define=FIREBASE_PROJECT_ID=VALUE
```

Put the Firebase Admin service-account JSON only on the Pi and set `FIREBASE_SERVICE_ACCOUNT` in the backend `.env`. Never place the private service-account file in the mobile app.

## Release signing

The project remains buildable with a debug signature for pilot testing. Before distributing a release, create a private Android keystore, copy `android/key.properties.example` to `android/key.properties`, enter its values, protect both files, and run `flutter build apk --release` or `flutter build appbundle --release`.

## Authentication behavior

- Full password login occurs on first use.
- If **Remember this device** is enabled, the app asks the owner to create a four-digit PIN.
- Later launches use PIN or platform biometrics/device authentication.
- Five incorrect PIN attempts clear the local session.
- The account password is never saved on the phone.
- When the Pi is unreachable after a valid local unlock, the app can show cached information explicitly marked offline/stale.

Run final tests on the real target Android phone because secure storage, biometrics, push notifications, and HLS playback depend on platform plugins.

