# ClassCast Offline — Share. Present. Learn.

Offline classroom document-sharing and presentation-casting over local Wi-Fi or
hotspot. No mobile data, no internet, no accounts.

- **Teacher** (Android app or laptop): creates a session, shares a document,
  controls pages. Students follow live.
- **Students** (Flutter app or any web browser): scan the QR or enter the
  local address, then watch the synchronized presentation.

UI is built in this repo. **APK + Web builds run on GitHub Actions** — no
Flutter SDK needed on your machine. Push to `main` (or tag `v*`) and download
the artifacts.

| Workflow | File | Produces |
|---|---|---|
| `Build Android APK` | `.github/workflows/build-android.yml` | `classcast-apk` → `app-release.apk` |
| `Build ClassCast (Web)` | `.github/workflows/build.yml` | `classcast-web` → full web build |

Both run **Test first** (`flutter analyze` + `flutter test`); the build jobs
only start if tests pass.

## Develop in Acode, build in GitHub

1. Open the repo folder in **Acode** (Git sync on), edit `lib/`, `test/`,
   `pubspec.yaml` — no `flutter` commands needed locally.
2. Commit + push in Acode (or via the GitHub mobile app / web UI).
3. Open **GitHub → repo → Actions**. The run starts automatically on push
   to `main`. Watch `Test` → `APK`.
4. When green: tap the run → **Artifacts** at the bottom → download
   `classcast-apk` → unzip → `app-release.apk`.
5. Copy the APK to the phone → tap it → allow *Install unknown apps* if asked.

Manual re-run: **Actions → select workflow → Run workflow** (`workflow_dispatch`).

### Release APKs

Push a tag (`git tag v1.0.2 && git push origin v1.0.2`) and the same build
attaches `app-release.apk` to **Releases**, which is easier to download from a
phone browser: repo → **Releases** → pick version → download asset.

## Signing (only if you need a distributable release)

The APKs above are **debug-signed** by CI (Flutter's auto-generated debug key).
That is fine for **sideloading in a classroom** and for **GitHub artifact
distribution**. Google Play Store rejects debug-signed apps.

For a real signed release:

1. Create a keystore **on a machine with JDK** (`keytool -genkey -v -keystore
   ~/classcast-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias
   upload`). Acode on Android cannot generate one (no JDK/keytool).
2. Store it **outside the repo** and add the values as **GitHub Secrets**
   (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`,
   `ANDROID_STORE_PASSWORD`) — **never commit the `.jks` file or passwords**.
3. Decode it in CI and reference it from `android/app/build.gradle.kts` via a
   `signingConfigs.release` block fed from `github.action_encrypt_secrets`.

Until that is set up, treat the artifacts as classroom/internal builds.

## What files open where

| File | Who opens it | How |
|---|---|---|
| PDF | app | Syncfusion PDF viewer (teacher's file, or the host URL for students) |
| PPTX (PowerPoint) | app | Parsed and drawn by the app: slides, text, pictures, tables |
| DOCX (Word) | app | Parsed and drawn by the app: headings, lists, tables, images |
| XLSX (Excel) | app | Parsed and printed by the app: sheets, cells, dates, merges |
| JPG / PNG / TXT | app | Rendered directly |
| PPT / DOC / XLS (1997-2003) | nobody | Binary format no device can read — save as the modern format or a PDF |

Office files are opened **on the device**, with no laptop and no LibreOffice.
They are a zip of XML, so the app reads the slides/pages/sheets itself and
draws them on a fixed page canvas — which is also why "page 3" means the same
thing on the teacher's phone and on every student's screen.

## What is tested vs. not

**Tested in CI:** analyzer clean, unit tests (doc types, sync wire format,
join parsing, validators, and the OOXML parsers against real zipped
.pptx/.docx/.xlsx fixtures) and widget tests that boot the real app and reach
the role screen, teacher dashboard and student join screen; release APK and
web builds both succeed. The laptop host has its own suite (session lifecycle,
teacher key, document sharing, path traversal).

**Not yet verified on real hardware:** hotspot join, QR scanning, live
page-sync over WebSocket, reconnect recovery, PDF rendering of real files and
how close the on-device Office rendering is to PowerPoint/Word/Excel on a real
deck. Those need a real classroom test with 1 teacher device and 2+ student
devices (see [OFFLINE_TESTING.md](OFFLINE_TESTING.md)).
A successful compile does not mean those flows work end-to-end.

## Project structure

```text
lib/
  main.dart                 # entry
  app.dart                  # MaterialApp + role routing + providers
  theme/                    # AppColors, AppTheme (M3, Inter, 8pt spacing)
  models/                   # ClassroomSession, SharedDocument, Participant, SyncEvent
  providers/                # AppState, SessionProvider, LibraryProvider, SyncProvider
  services/                 # sync_protocol, network_service, classcast_client,
                            # document_service, session_store
    ooxml/                  # on-device Office readers: pptx, docx, xlsx + zip/xml
  widgets/                  # logo, scaffold, status chips, state cards,
                            # document/session/QR cards
    office/                 # canvas + slide/page/sheet renderers
  screens/
    splash_screen.dart, role_selection_screen.dart
    teacher/                # shell, dashboard, create, share, present, students
    student/                # shell, join, waiting, viewer, web viewer
    common/                 # files, settings, network help
  utils/                    # responsive, validators, formatters
server/                     # laptop-hosted Shelf HTTP + WebSocket server (Dart)
web/                        # PWA index + manifest (served by the laptop host)
test/                       # unit tests + widget boot tests
```

> The `android/` folder is **generated in CI** by `flutter create`, so it is
> not committed. That keeps the repo SDK-version agnostic while CI pins a
> stable Flutter release.

## Run the laptop-hosted server

```sh
cd server
dart pub get
dart run bin/classcast_server.dart --port 8080 --dir ./shared --web ../build/web
```

- Prints the real LAN URLs, e.g. `http://192.168.43.1:8080/`.
- Office → PDF conversion is **no longer required**: .pptx / .docx / .xlsx are
  opened by the clients themselves. Put the files in `--dir ./shared` so the
  teacher (on the laptop web app) and every student can fetch them.
- API: `GET /api/session?id=…`, `POST /api/page`, `POST /api/document`,
  `POST /api/end` (teacher key), `WS /ws?session=…&name=…`, `GET /files/…`.

## Run the Android app

1. Open the GitHub **Actions** tab → latest run → download `classcast-apk`
   (or grab it from **Releases**).
2. Teacher flow: Role → Teacher → Create New Session → share a file → Present.
3. Student flow: join the teacher hotspot → Role → Student → scan QR or type
   the address → watch live.

## Run the web app

- Locally (if you have Flutter): `flutter run -d chrome`.
- In class: download the `classcast-web` artifact (or `flutter build web`),
  serve its `build/web` folder from the laptop server (`--web` flag above),
  then students open `http://<teacher-ip>:8080/` in any browser.

GitHub Actions is **only used to build**. The classroom backend always runs on
the teacher device / laptop — there is no cloud or paid API anywhere in the
app.

## Offline testing guide

See [OFFLINE_TESTING.md](OFFLINE_TESTING.md) — one teacher + two students,
hotspot + QR + page sync + reconnect checks.

## Feature status

See [FEATURE_STATUS.md](FEATURE_STATUS.md) — what works now (UI prototype +
local server + sync protocol) and what is still TODO per phase.
