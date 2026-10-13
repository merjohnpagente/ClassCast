# Launcher icon sources (committed).

- `icon_1024.png` — blue ClassCast logo (screen + cast arcs) on white.
- `icon_foreground_1024.png` — same logo on transparent (adaptive icon).

Generated from `lib/widgets/app_logo.dart`. CI runs
`flutter pub run flutter_launcher_icons` (config in pubspec.yaml) to
produce Android launcher icons + web PWA icons/favicon on every build.
To regenerate locally: replace these PNGs, then run the same command.
