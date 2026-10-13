# ClassCast Offline — Share. Present. Learn.

Offline classroom document-sharing and presentation-casting over local Wi-Fi or
hotspot. No mobile data, no internet, no accounts.

- **Teacher** (Android app or laptop): creates a session, shares a document,
  controls pages. Students follow live.
- **Students** (Flutter app or any web browser): scan the QR or enter the
  local address, then watch the synchronized presentation.

UI is built in this repo. **APK + Web builds run on GitHub Actions**
(`.github/workflows/build.yml`) — push to `main` (or tag `v*`) and download
the artifacts. No local Flutter SDK needed for UI review.

## Project structure

```text
lib/
  main.dart                 # entry
  app.dart                  # MaterialApp + role routing + providers
  theme/                    # AppColors, AppTheme (M3, Inter, 8pt spacing)
  models/                   # ClassroomSession, SharedDocument, Participant, SyncEvent
  providers/                # AppState, SessionProvider, LibraryProvider, SyncProvider
  services/                 # sync_protocol, network_service, classcast_client,
                            # document_service, session_store, demo_data
  widgets/                  # logo, scaffold, status chips, state cards,
                            # document/session/QR cards
  screens/
    splash_screen.dart, role_selection_screen.dart
    teacher/                # shell, dashboard, create, share, present, students
    student/                # shell, join, waiting, viewer, web viewer
    common/                 # files, settings, network help
  utils/                    # responsive, validators, formatters
server/                     # laptop-hosted Shelf HTTP + WebSocket server (Dart)
web/                        # PWA index + manifest (served by the laptop host)
test/                       # unit tests (models, protocol, validators)
```

## Run the laptop-hosted server

```sh
cd server
dart pub get
dart run bin/classcast_server.dart --port 8080 --dir ./shared --web ../build/web
```

- Prints the real LAN URLs, e.g. `http://192.168.43.1:8080/`.
- Office → PDF conversion (laptop with LibreOffice):
  `soffice --headless --convert-to pdf Lesson.pptx --outdir ./shared`
- API: `GET /api/session?id=…`, `POST /api/page`, `POST /api/document`,
  `POST /api/end` (teacher key), `WS /ws?session=…&name=…`, `GET /files/…`.

## Run the Android app

1. Open the GitHub **Actions** tab → latest run → download `classcast-apk`.
2. Or build locally: `flutter pub get && flutter run` (teacher hotspot first).
3. Teacher flow: Role → Teacher → Create New Session → share a file → Present.
4. Student flow: join the teacher hotspot → Role → Student → scan QR or type
   the address → watch live.

## Run the web app

- Locally: `flutter run -d chrome`.
- In class: download the `classcast-web` artifact (or `flutter build web`),
  serve its `build/web` folder from the laptop server (`--web` flag above),
  then students open `http://<teacher-ip>:8080/` in any browser.

## Offline testing guide

See [OFFLINE_TESTING.md](OFFLINE_TESTING.md) — one teacher + two students,
hotspot + QR + page sync + reconnect checks.

## Feature status

See [FEATURE_STATUS.md](FEATURE_STATUS.md) — what works now (UI prototype +
local server + sync protocol), what uses labeled demo data (demo-mode toggle
on role screen), and what is still TODO per phase.
