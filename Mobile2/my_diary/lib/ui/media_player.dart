import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:video_player/video_player.dart';

/// 软件内媒体播放：视频走 `video_player`，音频走 `audioplayers`，
/// 均支持播放/暂停与进度拖动，自管生命周期（随路由/页面销毁释放）。
///
/// 用途：正文媒体卡、媒体页预览等处的音视频不再跳三方应用。

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// 弹层打开软件内播放器（视频全宽 16:9 左右，音频紧凑卡）。
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

/// 软件内视频播放器：本地文件，播放/暂停 + 进度条拖动。
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
    final ctrl = _ctrl;
    if (_failed) return const _PlayerErrorCard(label: '视频加载失败');
    if (!_ready || ctrl == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
            child: CircularProgressIndicator(color: Colors.white70)),
      );
    }
    final ratio = ctrl.value.aspectRatio == 0 ? 16 / 9 : ctrl.value.aspectRatio;
    return Column(
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
      padding: const EdgeInsets.only(top: 6),
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
                max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
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

/// 软件内音频播放器：紧凑卡，大播放/暂停键 + 进度条拖动。
class InAppAudioPlayer extends StatefulWidget {
  final File file;
  const InAppAudioPlayer({super.key, required this.file});

  @override
  State<InAppAudioPlayer> createState() => _InAppAudioPlayerState();
}

class _InAppAudioPlayerState extends State<InAppAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _playing = false;
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
    _play();
  }

  Future<void> _play() async {
    try {
      await _player.play(DeviceFileSource(widget.file.path));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
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
    if (_playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _PlayerErrorCard(label: '音频加载失败');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 38,
            color: Colors.white,
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
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                max: _duration.inMilliseconds
                    .toDouble()
                    .clamp(1, double.infinity),
                value: _position.inMilliseconds
                    .toDouble()
                    .clamp(0, _duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_fmt(_position)} / ${_fmt(_duration)}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PlayerErrorCard extends StatelessWidget {
  final String label;
  const _PlayerErrorCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white54, size: 30),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}
