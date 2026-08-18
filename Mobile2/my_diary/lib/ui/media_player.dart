import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:video_player/video_player.dart';

/// 软件内媒体播放：视频走 `video_player`，音频走 `audioplayers`，
/// 均支持播放/暂停与进度拖动，自管生命周期（随路由/页面销毁释放）。
///
/// 音频为 HTML5 风格内嵌播放条（直接内联展示、点击即播，不弹抽屉）；
/// 视频为黑底圆角卡（内嵌模式点击直接播，卡片模式走弹层）。

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// 弹层打开软件内播放器（视频卡片模式 / 附件外场景）。
Future<void> showInAppMediaPlayer(
  BuildContext context, {
  required AssetKind kind,
  required File file,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black,
    barrierColor: Colors.black54,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (kind == AssetKind.video)
              InAppVideoPlayer(file: file)
            else if (kind == AssetKind.audio)
              InAppAudioPlayer(file: file)
            else
              const Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  '该类型暂不支持软件内播放',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// 软件内视频播放器：黑底圆角卡，播放/暂停 + 进度条拖动。
class InAppVideoPlayer extends StatefulWidget {
  final File file;
  const InAppVideoPlayer({super.key, required this.file});

  @override
  State<InAppVideoPlayer> createState() => _InAppVideoPlayerState();
}

class _InAppVideoPlayerState extends State<InAppVideoPlayer> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.file(widget.file);
    _ctrl = ctrl;
    ctrl.addListener(_onUpdate);
    try {
      await ctrl.initialize();
      await ctrl.setLooping(false);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onUpdate);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ctrl = _ctrl;
    Widget inner;
    if (_failed) {
      inner = const SizedBox(
        height: 140,
        child: Center(
            child: Text('视频加载失败',
                style: TextStyle(color: Colors.white70, fontSize: 13))),
      );
    } else if (!_ready || ctrl == null) {
      inner = const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
            child: CircularProgressIndicator(color: Colors.white70)),
      );
    } else {
      final ratio =
          ctrl.value.aspectRatio == 0 ? 16 / 9 : ctrl.value.aspectRatio;
      inner = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(aspectRatio: ratio, child: VideoPlayer(ctrl)),
          _VideoControls(
            playing: ctrl.value.isPlaying,
            position: ctrl.value.position,
            duration: ctrl.value.duration,
            onToggle: () {
              if (ctrl.value.isPlaying) {
                ctrl.pause();
              } else {
                ctrl.play();
              }
            },
            onSeek: (d) => ctrl.seekTo(d),
          ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.radiusCard),
      child: Container(color: Colors.black, child: inner),
    );
  }
}

class _VideoControls extends StatelessWidget {
  final bool playing;
  final Duration position;
  final Duration duration;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  const _VideoControls({
    required this.playing,
    required this.position,
    required this.duration,
    required this.onToggle,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Colors.white,
              size: 30,
            ),
            onPressed: onToggle,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                max: duration.inMilliseconds
                    .toDouble()
                    .clamp(1, double.infinity),
                value: position.inMilliseconds
                    .toDouble()
                    .clamp(0, duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
              ),
            ),
          ),
          Text(
            '${_fmt(position)} / ${_fmt(duration)}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// HTML5 风格内嵌音频播放条：♪ 标题 + 播放/暂停 + 进度 + 时间。
/// 主题自适应（亮/暗均可用），不自动播放——用户点击播放键才开始。
class InAppAudioPlayer extends StatefulWidget {
  final File file;
  final String? title;
  const InAppAudioPlayer({super.key, required this.file, this.title});

  @override
  State<InAppAudioPlayer> createState() => _InAppAudioPlayerState();
}

class _InAppAudioPlayerState extends State<InAppAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _playing = false;
  bool _started = false;
  bool _failed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onDurationChanged
        .listen((d) => mounted ? setState(() => _duration = d) : null));
    _subs.add(_player.onPositionChanged
        .listen((d) => mounted ? setState(() => _position = d) : null));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    }));
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    // 只加载元数据（时长），不自动播放。
    _player.setSource(DeviceFileSource(widget.file.path)).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_failed) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_started) {
      await _player.resume();
    } else {
      try {
        await _player.play(DeviceFileSource(widget.file.path));
        _started = true;
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(t.radiusCard),
        border: Border.all(color: t.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.title != null && widget.title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                children: [
                  Icon(Icons.music_note, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.textSecondary),
                    ),
                  ),
                  if (_failed)
                    Text('无法播放', style: TextStyle(fontSize: 11, color: t.textTertiary)),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                iconSize: 34,
                color: cs.primary,
                icon: Icon(
                  _playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                ),
                onPressed: _toggle,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    activeTrackColor: cs.primary,
                    inactiveTrackColor: t.border,
                    thumbColor: cs.primary,
                  ),
                  child: Slider(
                    max: _duration.inMilliseconds
                        .toDouble()
                        .clamp(1, double.infinity),
                    value: _position.inMilliseconds
                        .toDouble()
                        .clamp(0, _duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                    onChanged: (v) =>
                        _player.seek(Duration(milliseconds: v.round())),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_fmt(_position)} / ${_fmt(_duration)}',
                style: TextStyle(fontSize: 11, color: t.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
