import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Playback bubble for a voice note.
///
/// Deliberately self-contained: it owns its own [AudioPlayer] so several
/// notes can exist in a list without a shared controller, and it streams the
/// audio straight from the Worker URL rather than downloading it first.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    super.key,
    required this.url,
    required this.seconds,
    required this.mine,
  });

  final String url;
  final int seconds;

  /// Outgoing bubbles are blue, so their controls need to be white.
  final bool mine;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  late final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  Duration _position = Duration.zero;
  Duration? _total;
  bool _playing = false;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.stop);

    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      // Ignore the bogus zero/negative durations some decoders emit first.
      if (mounted && d > Duration.zero) setState(() => _total = d);
    }));
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _playing = s == PlayerState.playing;
        if (s == PlayerState.playing) _loading = false;
      });
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    }));
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      // Resume when paused mid-note; otherwise start from the URL.
      if (_position > Duration.zero && _player.state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.url));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _seekTo(double fraction) async {
    final total = _total ?? Duration(seconds: widget.seconds);
    if (total <= Duration.zero) return;
    final target = total * fraction.clamp(0.0, 1.0).toDouble();
    await _player.seek(target);
    setState(() => _position = target);
  }

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final onBlue = widget.mine;
    final dim = onBlue ? Colors.white70 : palette.textSecondary;

    // Prefer the real decoded duration; fall back to the recorded length so
    // the bubble is correctly sized before playback starts.
    final total = _total ?? Duration(seconds: widget.seconds);
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0).toDouble();

    // Remaining time while playing, total length when idle — same as the
    // familiar messaging-app behaviour.
    final label = _failed
        ? 'Unavailable'
        : (_playing || _position > Duration.zero)
            ? _format(total - _position)
            : _format(total);

    return SizedBox(
      width: 208,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlayButton(
            playing: _playing,
            loading: _loading,
            failed: _failed,
            onBlue: onBlue,
            onTap: _failed ? null : _toggle,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _seekTo(
                        details.localPosition.dx / constraints.maxWidth,
                      ),
                      onHorizontalDragUpdate: (details) => _seekTo(
                        details.localPosition.dx / constraints.maxWidth,
                      ),
                      child: SizedBox(
                        height: 26,
                        width: constraints.maxWidth,
                        child: CustomPaint(
                          painter: _WaveformPainter(
                            progress: progress,
                            // Seeded by the URL so a given note always draws
                            // the same bars instead of reshuffling on rebuild.
                            seed: widget.url.hashCode,
                            playedColor: onBlue ? Colors.white : AppColors.accent,
                            unplayedColor:
                                onBlue ? Colors.white38 : palette.textSecondary.withOpacity(.35),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _failed ? (onBlue ? Colors.white : palette.textSecondary) : dim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.mic_rounded, size: 15, color: dim),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.failed,
    required this.onBlue,
    required this.onTap,
  });

  final bool playing;
  final bool loading;
  final bool failed;
  final bool onBlue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final bg = onBlue ? Colors.white24 : palette.surfaceMuted;
    final fg = onBlue ? Colors.white : AppColors.accent;

    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                  color: fg,
                  size: 21,
                ),
        ),
      ),
    );
  }
}

/// Static bar chart standing in for a real waveform.
///
/// We deliberately do not decode the audio to compute true amplitudes: that
/// would mean downloading and parsing every note just to draw it. The bars
/// are generated deterministically from the URL, so they are stable per
/// message and still give the eye something to track while scrubbing.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.seed,
    required this.playedColor,
    required this.unplayedColor,
  });

  final double progress;
  final int seed;
  final Color playedColor;
  final Color unplayedColor;

  static const int _barCount = 27;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final gap = size.width / _barCount;
    final barWidth = math.max(1.6, gap * 0.42);
    final paint = Paint()..strokeCap = StrokeCap.round..strokeWidth = barWidth;

    for (var i = 0; i < _barCount; i++) {
      // Bias towards mid heights so it reads as speech, not noise.
      final h = (0.25 + rng.nextDouble() * 0.75) * size.height;
      final x = gap * (i + 0.5);
      final played = (i + 0.5) / _barCount <= progress;
      paint.color = played ? playedColor : unplayedColor;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.seed != seed ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}
