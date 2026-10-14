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
- Unit tests: doc types, sync wire format, join parsing, validators, and the
  OOXML parsers (real zipped fixtures for pptx/docx/xlsx).
- GitHub Actions: analyze + test + release APK + web build.

## Still TODO (per spec phases)

- **Phase 2 (remainder):** teacher POST `/api/document` from the web build
  (the browser cannot read a picked file's bytes, so a teacher on the laptop
  still shares out of the host's `--dir` folder); participant heartbeat.
- **Phase 4:** QR shortcut actions polish, participant heartbeat/timeouts,
  multi-session host, Android hotspot client-isolation detection + warning.
- **Phase 5:** optional server-side conversion for the legacy binary formats
  (`.ppt` / `.doc` / `.xls`) that no device can render; advanced XLS
  (charts, formulas, multiple print areas).
- **Phase 6:** Android-hosted teacher server (platform channels, foreground
  service, storage permissions), advanced offline cache, full screen
  mirroring (explicitly out of scope for document-casting builds).
