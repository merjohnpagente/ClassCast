# Offline testing guide — 1 teacher + 2 students

Goal: prove an end-to-end offline PDF classroom with live page sync,
before Office conversion or Android-hosted sessions.

## You need

- 1 teacher device (laptop for hosted mode, or Android phone).
- 2 student devices (Android phones and/or a laptop browser).
- No internet, no SIM data. Charge everything first.

## Setup

1. **Teacher starts the network.**
   - Laptop: connect all devices to the same Wi-Fi router (no internet needed),
     or turn on the laptop hotspot.
   - Android: turn on *Portable hotspot*. On some phones enable
     *“Allow connected devices to communicate”* if present — several vendors
     isolate hotspot clients by default.
2. **Teacher starts the server (laptop mode).**
   ```sh
   cd server && dart pub get
   dart run bin/classcast_server.dart --port 8080 --dir ./shared
   ```
   Note the printed URL, e.g. `http://192.168.43.1:8080/`.
3. **Teacher app:** Role → Teacher → Create session
   (`Introduction to Physics`) → note the session ID + QR + address.
4. **Put a PDF in `./shared`** (or pick one in the app library) and share it.

## Test script

| # | Step | Expect |
|---|------|--------|
| 1 | Student A joins hotspot, scans QR | Join succeeds, waiting screen |
| 2 | Teacher shares PDF | Both students auto-open the viewer |
| 3 | Teacher goes 1 → 4 → 8 | Student pages follow within ~1 s |
| 4 | Student B opens `http://<ip>:8080/` in Chrome | Web viewer shows same page |
| 5 | Turn off student A Wi-Fi 10 s, turn back on | Reconnecting → resumes on teacher page |
| 6 | Teacher pauses sync, changes page | Student screens stay frozen |
| 7 | Teacher resumes, changes page | Students jump to the new page |
| 8 | Teacher ends session | Students see “Session ended” + Leave |
| 9 | Wrong ID (`CLASS-XXXX`) | Clear "teacher answered, but the session could not be read" error, no fake Connected state |
| 10 | Student tries Prev/Next | Disabled — teacher controls only |
| 11 | Join from a network that isolates clients (school/guest Wi-Fi) | Student sees the "Could not reach the teacher … switch on a hotspot" message; after ~1 min the teacher dashboard shows "No student has reached this session yet" |

## Known limits (this build)

- Office files (PPT/DOC/XLS) show *Needs conversion* until converted on a
  laptop with LibreOffice. Animations/macros do not survive PDF conversion.
- Android-hosted teacher server is stubbed (permissions + lifecycle vary by
  vendor); use the laptop host for real sessions.
- The teacher's "Can students reach me?" check runs on the teacher's own
  device, so it answers even when the Wi-Fi isolates clients — it proves the
  server is up, not that students can get in. The student's own error message
  and the dashboard's "no student has reached this session yet" hint are the
  honest signals; treat a green check plus zero joins as isolation.
