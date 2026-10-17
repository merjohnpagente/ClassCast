import 'package:flutter/foundation.dart';

/// Everything the shared-document viewer needs to know about a video being
/// cast, in one object.
///
/// Grouped rather than spread across a dozen parameters because the viewer is
/// the only consumer: PDF and Office call sites should not have to learn about
/// playback at all, and a nullable parameter per field would make that easy to
/// get wrong.
@immutable
class VideoSync {
  /// Teacher drives; a student only follows.
  final bool isTeacher;

  /// Where the class is, in milliseconds from the start of the video.
  final int positionMs;

  /// Whether the teacher has it running.
  final bool playing;

  /// The video's real length, once something has opened it.
  final int durationMs;

  /// The teacher has frozen the class: students hold still.
  final bool frozen;

  /// Muted on this device. A local choice, never broadcast.
  final bool muted;

  final VoidCallback? onPlayPause;
  final ValueChanged<int>? onSeek;
  final ValueChanged<int>? onDuration;
  final ValueChanged<bool>? onMutedChanged;

  const VideoSync({
    this.isTeacher = false,
    this.positionMs = 0,
    this.playing = false,
    this.durationMs = 0,
    this.frozen = false,
    this.muted = false,
    this.onPlayPause,
    this.onSeek,
    this.onDuration,
    this.onMutedChanged,
  });
}