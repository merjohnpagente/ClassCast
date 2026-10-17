import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';
import '../utils/local_file.dart';

/// Plays a shared video, with the teacher driving it.
///
/// One widget for both sides of the classroom, because the two only differ in
/// who is allowed to move it:
///
/// - The teacher plays the file it picked, locally, and every control is a
///   change to the class.
/// - A student plays the bytes the host is serving, follows the teacher's
///   position, and has one control of its own: mute.
///
/// Sound is on. A recorded lesson with no narration is a slideshow, and a
/// student whose phone is muted cannot hear the teacher either — so sound is
/// the default and the mute button is the escape, for a phone that has to stay
/// quiet in a row of thirty.
class VideoCastPlayer extends StatefulWidget {
  /// Students: the URL the host serves. Teacher: null, and [localPath] is used.
  final String? remoteUrl;

  /// The teacher's own file, played without going through the network.
  final String? localPath;

  /// Teacher drives; a student only follows.
  final bool isTeacher;

  /// Where the class should be, in milliseconds, and whether it is running.
  final int positionMs;
  final bool playing;
  final int durationMs;

  /// The teacher has frozen the class: a student pauses even while the video is
  /// running, and picks up again when the freeze lifts.
  final bool frozen;

  /// Muted on this device only. Never broadcast: one row of phones going
  /// quiet must not silence the rest of the class.
  final bool muted;

  /// Teacher: the class was paused or played.
  final VoidCallback? onPlayPause;

  /// Teacher: the class was moved to this position, in milliseconds.
  final ValueChanged<int>? onSeek;

  /// Whoever opened the file: its real length, so the seek bar is honest.
  final ValueChanged<int>? onDuration;

  /// This device's mute changed.
  final ValueChanged<bool>? onMutedChanged;

  const VideoCastPlayer({
    super.key,
    this.remoteUrl,
    this.localPath,
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

  @override
  State<VideoCastPlayer> createState() => _VideoCastPlayerState();
}

class _VideoCastPlayerState extends State<VideoCastPlayer> {
  VideoPlayerController? _controller;
  bool _opening = true;
  String? _problem;

  /// When this device last accepted the class's position, so drift is measured
  /// rather than guessed.
  DateTime? _syncedAt;

  /// How far out of step a student is allowed to get before being moved back.
  ///
  /// A second and a half is below what anyone can see in a lecture and above
  /// the jitter of thirty phones starting playback at slightly different
  /// moments. Inside that, nothing happens: re-seeking constantly is the very
  /// stutter this is meant to avoid.
  static const _driftTolerance = Duration(milliseconds: 1500);

  Timer? _driftCheck;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(VideoCastPlayer old) {
    super.didUpdateWidget(old);
    final sameFile = old.localPath == widget.localPath &&
        old.remoteUrl == widget.remoteUrl;
    if (!sameFile) {
      // A different file: everything about the old one is gone.
      unawaited(_dropController().then((_) => _open()));
      return;
    }
    _applyMute();
    if (widget.isTeacher) return;
    _followClass();
  }

  Future<void> _dropController() async {
    _driftCheck?.cancel();
    _driftCheck = null;
    final controller = _controller;
    _controller = null;
    _syncedAt = null;
    if (controller == null) return;
    try {
      await controller.pause();
    } catch (_) {/* never opened */}
    try {
      await controller.dispose();
    } catch (_) {/* already gone */}
  }

  Future<void> _open() async {
    final local = widget.localPath;
    final remote = widget.remoteUrl;
    final hasLocal = local != null && local.isNotEmpty;
    final hasRemote = remote != null && remote.isNotEmpty;

    if (!hasLocal && !hasRemote) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _problem = 'This video has no address to play from.';
      });
      return;
    }
    if (hasLocal && kIsWeb) {
      // A browser tab cannot open a file on this device's disk. Say so, rather
      // than failing with something nobody can act on.
      if (!mounted) return;
      setState(() {
        _opening = false;
        _problem = 'Play this video from ClassCast on a phone or computer — a '
            'browser tab cannot open a file on the device.';
      });
      return;
    }

    // `File` is reached through the platform helper rather than an import: naming
    // it here would pull `dart:io` into the web build, where it is a compile
    // error rather than a missing feature.
    final handle = hasLocal ? localFileHandle(local) : null;
    final controller = handle != null
        ? VideoPlayerController.file(handle as dynamic)
        : VideoPlayerController.networkUrl(Uri.parse(remote!));
    try {
      await controller.initialize();
      controller.addListener(_onControllerChanged);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _opening = false;
        _problem = null;
      });
      widget.onDuration?.call(controller.value.duration.inMilliseconds);
      _applyMute();
      if (widget.isTeacher) {
        _driftCheck?.cancel();
        _driftCheck = null;
      } else {
        _followClass();
      }
    } catch (_) {
      try {
        await controller.dispose();
      } catch (_) {/* already gone */}
      if (!mounted) return;
      setState(() {
        _opening = false;
        _problem = 'This video could not be played here.';
      });
    }
  }

  /// The player's own position moves on its own, so the time labels and the
  /// play button are rebuilt from its updates.
  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _applyMute() {
    final controller = _controller;
    if (controller == null) return;
    // Before the first play some platforms ignore this, so it is set again
    // whenever playback starts.
    unawaited(controller.setVolume(widget.muted ? 0 : 1));
  }

  /// Puts this player where the class is, and starts or stops it.
  void _followClass() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final shouldPlay = widget.playing && !widget.frozen;
    final target = Duration(milliseconds: widget.positionMs);
    _syncedAt = DateTime.now();
    // A seek is only worth doing when the difference is one a person would
    // notice.
    final drift = (controller.value.position - target).abs();
    if (drift > _driftTolerance) {
      unawaited(controller.seekTo(target));
    }
    if (shouldPlay) {
      _applyMute();
      unawaited(controller.play());
      _startDriftCheck();
    } else {
      _driftCheck?.cancel();
      _driftCheck = null;
      unawaited(controller.pause());
    }
  }

  /// Nudges a playing student back into step without re-seeking constantly.
  void _startDriftCheck() {
    _driftCheck?.cancel();
    _driftCheck = Timer.periodic(const Duration(seconds: 2), (_) {
      final controller = _controller;
      if (controller == null || !controller.value.isPlaying) return;
      final since = _syncedAt;
      if (since == null) return;
      // Where the class should be now: the teacher's anchor plus the time that
      // has passed since the frame that carried it.
      final elapsed = DateTime.now().difference(since).inMilliseconds;
      final target = Duration(milliseconds: widget.positionMs + elapsed);
      if ((controller.value.position - target).abs() > _driftTolerance) {
        _syncedAt = DateTime.now();
        unawaited(controller.seekTo(target));
      }
    });
  }

  @override
  void dispose() {
    _driftCheck?.cancel();
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      _applyMute();
      unawaited(controller.play());
    }
    widget.onPlayPause?.call();
  }

  /// [fraction] is where along the bar the teacher dragged to, 0 to 1.
  void _seekToFraction(double fraction) {
    final controller = _controller;
    if (controller == null) return;
    final duration = controller.value.duration.inMilliseconds;
    if (duration <= 0) return;
    final ms = (fraction * duration).round().clamp(0, duration);
    unawaited(controller.seekTo(Duration(milliseconds: ms)));
    widget.onSeek?.call(ms);
  }

  void _toggleMute() => widget.onMutedChanged?.call(!widget.muted);

  static String _format(int ms) {
    final total = Duration(milliseconds: ms < 0 ? 0 : ms);
    final minutes = total.inMinutes;
    final seconds = total.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_opening) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller == null || _problem != null) {
      return _panel(_problem ?? 'This video could not be played here.');
    }
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.value.hasError) {
      return _panel(controller.value.errorDescription ??
          'This video could not be played here.');
    }

    final position = controller.value.position.inMilliseconds;
    final duration = controller.value.duration.inMilliseconds;
    final progress = duration <= 0
        ? 0.0
        : (position.clamp(0, duration) / duration).toDouble();
    final ratio = controller.value.aspectRatio;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio == 0 ? 16 / 9 : ratio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  if (widget.isTeacher)
                    IconButton(
                      tooltip: controller.value.isPlaying ? 'Pause' : 'Play',
                      iconSize: 30,
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        color: AppColors.primary,
                      ),
                      onPressed: _togglePlay,
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        widget.playing && !widget.frozen
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        size: 22,
                        color: AppColors.muted,
                      ),
                    ),
                  // The teacher scrubs the class; a student only sees where it
                  // is, because anything else would be a second classroom.
                  if (widget.isTeacher)
                    Expanded(
                      child: Slider(
                        value: progress,
                        onChanged: _seekToFraction,
                      ),
                    )
                  else
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: AppColors.border,
                        ),
                      ),
                    ),
                  Text(
                    '${_format(position)} / ${_format(duration)}',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(width: 4),
                  // One tap, and it stays: thirty phones playing a lecture at
                  // once is a room nobody can think in, so the way back to
                  // silence is as easy as the way to it.
                  IconButton(
                    tooltip: widget.muted ? 'Unmute' : 'Mute',
                    iconSize: 20,
                    icon: Icon(
                      widget.muted
                          ? Icons.volume_off_outlined
                          : Icons.volume_up_outlined,
                      color: widget.muted ? AppColors.muted : AppColors.ink,
                    ),
                    onPressed: _toggleMute,
                  ),
                ],
              ),
              if (!widget.isTeacher)
                Text(
                  widget.frozen
                      ? 'The teacher has frozen the class'
                      : widget.playing
                          ? 'Following the teacher'
                          : 'Paused by the teacher',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _panel(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_outlined,
                  size: 40, color: AppColors.muted),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
}