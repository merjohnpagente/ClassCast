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
- Document pipeline scaffolding: type detection, per-type icons (never
  color-only), Office-needs-conversion states, permission-gated downloads.
- QR join payload (`classcast://join?...`) + parser for QR / URL / bare ID.
- Unit tests: doc types, sync wire format, join parsing, validators.
- GitHub Actions: analyze + test + release APK + web build.

## Still TODO (per spec phases)

- **Phase 2 (remainder):** wire teacher Present screen to real file bytes /
  converted-PDF URL (`SfPdfViewer.network`), teacher POST `/api/page` +
  `/api/document` from the app; serve converted PDFs from `server/`.
- **Phase 4:** QR shortcut actions polish, participant heartbeat/timeouts,
  multi-session host, Android hotspot client-isolation detection + warning.
- **Phase 5:** one-click LibreOffice conversion endpoint on the laptop host
  (`POST /api/convert`), progress events, multi-sheet XLS handling.
- **Phase 6:** Android-hosted teacher server (platform channels, foreground
  service, storage permissions), advanced offline cache, full screen mirroring
  (explicitly out of scope for document-casting builds).
