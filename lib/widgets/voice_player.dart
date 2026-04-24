import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Маленький плеер голосовых сообщений: кнопка play/pause + прогресс + длительность.
class VoicePlayer extends StatefulWidget {
  final String url;
  final int? durationMs;
  final Color accent;
  final Color onAccent;
  final Color background;

  const VoicePlayer({
    super.key,
    required this.url,
    this.durationMs,
    this.accent = const Color(0xFF7C3AED),
    this.onAccent = Colors.white,
    this.background = const Color(0xFF1A1430),
  });

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final _player = AudioPlayer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.url);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.durationMs != null
        ? Duration(milliseconds: widget.durationMs!)
        : (_player.duration ?? Duration.zero);

    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, posSnap) {
        final pos = posSnap.data ?? Duration.zero;
        final maxMs = total.inMilliseconds <= 0 ? 1 : total.inMilliseconds;
        final progress = (pos.inMilliseconds / maxMs).clamp(0.0, 1.0);

        return Container(
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.background,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, stateSnap) {
                  final playing = stateSnap.data?.playing ?? false;
                  final processing = stateSnap.data?.processingState;
                  final loading = processing == ProcessingState.loading ||
                      processing == ProcessingState.buffering;
                  return IconButton(
                    iconSize: 28,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: !_ready
                        ? null
                        : () async {
                            if (playing) {
                              await _player.pause();
                            } else {
                              if (processing == ProcessingState.completed) {
                                await _player.seek(Duration.zero);
                              }
                              await _player.play();
                            }
                          },
                    icon: loading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.accent,
                            ),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            color: widget.accent,
                          ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: widget.onAccent.withValues(alpha: 0.25),
                    valueColor: AlwaysStoppedAnimation<Color>(widget.accent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fmt(total == Duration.zero ? pos : total),
                style: TextStyle(
                  color: widget.onAccent.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
