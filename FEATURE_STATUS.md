# Feature status

## Functional now

- Complete responsive UI for every spec screen (A–P): splash, role select,
  teacher dashboard/sessions/files/settings, create session + QR, document
  library with search + filters, share screen with conversion notices,
  teacher presentation controller (mobile + desktop layouts), students list
  with remove, student join (QR scan + manual), waiting room, synchronized
  viewer (page lock, fullscreen, reconnecting), web viewer, connection guide,
  reusable empty/loading/error states.
- Navigation: teacher bottom-nav/sidebar shell, student Join/Viewer/Connection
  shell. No teacher controls in student mode.
- Local communication architecture: `server/` Shelf host (session REST,
  teacher-key validation, WS broadcast, reconnect snapshot, static web +
  file serving), `ClasscastClient` (probe → snapshot → subscribe → backoff
  reconnect), `SyncProtocol` wire format, `SyncEvent` models.
- **On-device Office rendering** (`lib/services/ooxml/`): .pptx, .docx and
  .xlsx are opened by the app itself — no laptop, no LibreOffice, no
  conversion round-trip. PowerPoint draws slides with real geometry, theme
  colours, layout/master inheritance, pictures, groups and tables; Word draws
  paragraphs, headings, lists, tables and inline images; Excel prints sheets
  onto fixed pages with shared strings, number formats and merged cells. PDFs,
  images and text were already handled directly.
- Document pipeline: type detection, per-type icons (never color-only),
  slide/page counting at pick time, permission-gated downloads, and an honest
  panel for files the device genuinely cannot open (Office 97-2003 binaries).
- QR join payload (`classcast://join?...`) + parser for QR / URL / bare ID.
- Unit tests: doc types, sync wire format, join parsing, validators, the
  OOXML parsers (real zipped fixtures for pptx/docx/xlsx), both hosts'
  protocol and file rules, storage round-trips, and the session provider's
  roster state machine.

## Classroom controls

- **Teacher takes control back**: a targeted `POST /api/take-control` reaches
  one student (or the whole room) and holds that screen on the class page until
  the class page moves again. Per-student button in the roster, plus one in the
  toolbar for everyone.
- **Student view preview**: the teacher can open exactly what the class sees —
  the same viewer, built from the same snapshot, not a mock-up.
- **Live roster**: names on join, removed on leave, raised hands, and the page
  each student is on when they are allowed to browse. The teacher's receive
  socket reconnects by itself after a Wi-Fi blip or a mid-lesson hotspot
  switch, and the host replays who is already in the room, so the list never
  silently empties while students are still sitting there; a student whose
  connection dies is removed for good.
- **Downloads that really download**: when the teacher allows it, the student's
  Download button fetches the shared file straight from the teacher's phone
  over the hotspot and hands it to the platform's own save dialog (SAF on
  Android, a browser download on web). No cloud, no internet.

## Durability and honesty

- Documents are **copied into app-owned storage** when picked, so the library
  survives a restart and Android clearing its cache.
- The library keeps multi-picks, keeps entries it cannot verify, and reports a
  store it could not read instead of showing an empty list.
- The teacher key is random, persisted with the session, and required for the
  control endpoints, the teacher socket, and every document download; a share
  URL carries a token and stops working the moment the document is unshared.
- Anything the app cannot do is said plainly: a refused share, a failed pick, a
  host that could not start, a file that vanished.
- Ending a session closes the room's sockets, unshares the file (a kept URL
  stops working), and clears the page/document/roster state, so the next
  session starts clean instead of inheriting a phantom document.
- A student whose connection dies without a FIN (phone slept, slipped off the
  hotspot) is dropped from the roster after 30 seconds of silence: student
  clients heartbeat every 10 seconds, and both hosts sweep the room. The
  teacher's roster only shows students who are actually there.
- **Client isolation is named, not silent**: the teacher's own "can students
  reach me?" check runs on this device, so it connects over the loopback route
  and can never see a network that blocks device-to-device traffic — its
  success message says exactly that. What actually detects the block is the
  student's app, which names the cause and the hotspot fix when its probe
  fails. And if a live session has had no student join at all after a minute,
  the dashboard says so with the same hotspot advice. No fake verdicts.

## Still TODO (per spec phases)

- **Phase 2 (remainder):** teacher POST `/api/document` from the web build
  (the browser cannot read a picked file's bytes, so a teacher on the laptop
  still shares out of the host's `--dir` folder).
- **Phase 4:** QR shortcut actions polish, multi-session host.
- **Phase 5:** optional server-side conversion for the legacy binary formats
  (`.ppt` / `.doc` / `.xls`) that no device can render; advanced XLS
  (charts, formulas, multiple print areas).
- **Phase 6:** advanced offline cache and full screen mirroring (explicitly
  out of scope for document-casting builds).
  The Android-hosted teacher server itself already exists — `ClasscastHost`
  runs the HTTP + WebSocket classroom inside the teacher's phone.
