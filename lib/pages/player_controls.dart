import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../hls.dart';

/// 当前这一集能选的清晰度。[selected] 为 null 表示播放原地址（多档时就是“自动”）。
class QualityState {
  final List<HlsVariant> variants;
  final int? selected;
  const QualityState({this.variants = const [], this.selected});
}

/// 自己的播放控制层，替换 chewie 自带的 MaterialControls：
/// 单击显示/隐藏控制栏，双击暂停/播放，左右滑动快进快退，底栏有投屏、倍速、清晰度、全屏。
/// 作为 customControls 传入，全屏和非全屏都生效。
class PlayerControls extends StatefulWidget {
  final ValueListenable<QualityState> quality;
  final ValueChanged<int?> onSelectQuality;
  final VoidCallback onCast;
  const PlayerControls({super.key, required this.quality, required this.onSelectQuality, required this.onCast});

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  /// 从屏幕一侧滑到另一侧对应的时长。
  static const _fullSwipe = Duration(seconds: 90);
  static const _hideAfter = Duration(seconds: 3);

  ChewieController? _chewie;
  VideoPlayerController? _video;
  bool _visible = true;
  bool _progressDragging = false;
  Timer? _hideTimer;

  Duration? _dragStart;
  Duration _dragTarget = Duration.zero;
  double _dragDx = 0;
  IconData? _flashIcon;
  int _flashToken = 0;

  ChewieController get chewie => _chewie!;
  VideoPlayerController get video => _video!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = ChewieController.of(context);
    if (c == _chewie) return;
    _video?.removeListener(_onVideo);
    _chewie = c;
    _video = c.videoPlayerController..addListener(_onVideo);
    _restartHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _video?.removeListener(_onVideo);
    super.dispose();
  }

  void _onVideo() {
    if (mounted) setState(() {});
  }

  // ---------- 控制栏显隐 ----------

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (!mounted || !video.value.isPlaying || _progressDragging) return;
      setState(() => _visible = false);
    });
  }

  void _show() {
    setState(() => _visible = true);
    _restartHideTimer();
  }

  void _onTap() {
    if (_visible) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
    } else {
      _show();
    }
  }

  // ---------- 手势 ----------

  void _togglePlay() {
    if (!video.value.isInitialized) return;
    final v = video.value;
    final finished = v.duration > Duration.zero && v.position >= v.duration;
    if (v.isPlaying) {
      chewie.pause();
    } else {
      if (finished) chewie.seekTo(Duration.zero);
      chewie.play();
    }
    _restartHideTimer();
  }

  void _onDoubleTap() {
    if (!video.value.isInitialized) return;
    final willPlay = !video.value.isPlaying;
    _togglePlay();
    final token = ++_flashToken;
    setState(() => _flashIcon = willPlay ? Icons.play_arrow : Icons.pause);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && token == _flashToken) setState(() => _flashIcon = null);
    });
  }

  void _onDragStart(DragStartDetails _) {
    final v = video.value;
    if (!v.isInitialized || chewie.isLive) return;
    setState(() {
      _dragStart = v.position;
      _dragTarget = v.position;
      _dragDx = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    final start = _dragStart;
    if (start == null || width <= 0) return;
    final duration = video.value.duration;
    _dragDx += d.delta.dx;
    var target = start + _fullSwipe * (_dragDx / width);
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    setState(() => _dragTarget = target);
  }

  void _onDragEnd() {
    if (_dragStart == null) return;
    chewie.seekTo(_dragTarget);
    setState(() => _dragStart = null);
  }

  // ---------- 菜单 ----------

  Future<T?> _sheet<T>(List<Widget> Function(BuildContext) children) async {
    _hideTimer?.cancel();
    final r = await showModalBottomSheet<T>(
      context: context,
      useRootNavigator: chewie.useRootNavigator,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children(ctx)),
        ),
      ),
    );
    if (mounted) _restartHideTimer();
    return r;
  }

  Future<void> _pickSpeed() async {
    final current = video.value.playbackSpeed;
    final speed = await _sheet<double>((ctx) => [
          for (final s in chewie.playbackSpeeds)
            ListTile(
              title: Text(s == 1 ? '正常' : '${_num(s)}x'),
              trailing: s == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, s),
            ),
        ]);
    if (speed != null) video.setPlaybackSpeed(speed);
  }

  Future<void> _pickQuality() async {
    final q = widget.quality.value;
    final multi = q.variants.length > 1;
    // 用 -1 表示“自动”，因为 pop(null) 和点空白关闭分不开。
    final picked = await _sheet<int>((ctx) => [
          if (multi)
            ListTile(
              title: const Text('自动'),
              subtitle: const Text('按网速自动切换'),
              trailing: q.selected == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, -1),
            ),
          for (var i = 0; i < q.variants.length; i++)
            ListTile(
              title: Text(q.variants[i].label),
              trailing: (multi ? q.selected == i : true) ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, multi ? i : null),
            ),
          if (q.variants.isEmpty)
            ListTile(title: Text(_qualityLabel(q)), trailing: const Icon(Icons.check)),
          if (!multi)
            const ListTile(
              dense: true,
              title: Text('这个源只提供这一种清晰度，想要别的清晰度可以回详情页换个源试试',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
        ]);
    if (picked == null || !multi) return;
    final sel = picked < 0 ? null : picked;
    if (sel != q.selected) widget.onSelectQuality(sel);
  }

  String _qualityLabel(QualityState q) {
    if (q.selected != null && q.selected! < q.variants.length) return q.variants[q.selected!].label;
    if (q.variants.length > 1) return '自动';
    if (q.variants.length == 1) return q.variants.first.label;
    final size = video.value.size;
    final shortSide = size.width < size.height ? size.width : size.height;
    return shortSide > 0 ? qualityLabel(shortSide.round()) : '清晰度';
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final v = video.value;
    if (v.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('播放出错：${v.errorDescription ?? ''}',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      );
    }
    final showBars = _visible || !v.isPlaying || _progressDragging;
    return LayoutBuilder(
      builder: (_, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        onDoubleTap: _onDoubleTap,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: (d) => _onDragUpdate(d, box.maxWidth),
        onHorizontalDragEnd: (_) => _onDragEnd(),
        onHorizontalDragCancel: _onDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: _center(v, showBars)),
            if (chewie.isFullScreen)
              Positioned(
                left: 0,
                top: 0,
                child: IgnorePointer(
                  ignoring: !showBars,
                  child: AnimatedOpacity(
                    opacity: showBars ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: SafeArea(
                      right: false,
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: IconButton(
                          tooltip: '退出全屏',
                          onPressed: chewie.exitFullScreen,
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !showBars,
                child: AnimatedOpacity(
                  opacity: showBars ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: _bottomBar(v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _center(VideoPlayerValue v, bool showBars) {
    if (_dragStart != null) return _seekHint(v.duration);
    if (_flashIcon != null) return _roundIcon(_flashIcon!);
    if (v.isBuffering || !v.isInitialized) return const CircularProgressIndicator();
    if (!showBars) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _togglePlay,
      child: _roundIcon(v.isPlaying ? Icons.pause : Icons.play_arrow),
    );
  }

  Widget _roundIcon(IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 40),
      );

  Widget _bottomBar(VideoPlayerValue v) {
    const textStyle = TextStyle(color: Colors.white, fontSize: 13);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black54],
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: chewie.isFullScreen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 4, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!chewie.isLive)
                SizedBox(
                  height: 20,
                  child: MaterialVideoProgressBar(
                    video,
                    height: 20,
                    barHeight: 4,
                    handleHeight: 6,
                    onDragStart: () {
                      _hideTimer?.cancel();
                      setState(() => _progressDragging = true);
                    },
                    onDragEnd: () {
                      setState(() => _progressDragging = false);
                      _restartHideTimer();
                    },
                    colors: ChewieProgressColors(
                      playedColor: Theme.of(context).colorScheme.primary,
                      handleColor: Theme.of(context).colorScheme.primary,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              Row(
                children: [
                  Text(chewie.isLive ? '直播' : '${_fmt(v.position)} / ${_fmt(v.duration)}', style: textStyle),
                  const Spacer(),
                  IconButton(
                    tooltip: '投屏',
                    onPressed: widget.onCast,
                    icon: const Icon(Icons.cast, color: Colors.white, size: 20),
                  ),
                  _barButton(v.playbackSpeed == 1 ? '倍速' : '${_num(v.playbackSpeed)}x', _pickSpeed),
                  ValueListenableBuilder<QualityState>(
                    valueListenable: widget.quality,
                    builder: (_, q, _) => _barButton(_qualityLabel(q), _pickQuality),
                  ),
                  if (chewie.allowFullScreen)
                    IconButton(
                      onPressed: () {
                        chewie.toggleFullScreen();
                        _restartHideTimer();
                      },
                      icon: Icon(chewie.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barButton(String text, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );

  Widget _seekHint(Duration duration) {
    final diff = _dragTarget - _dragStart!;
    final sign = diff.isNegative ? '-' : '+';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$sign${diff.abs().inSeconds}秒',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${_fmt(_dragTarget)} / ${_fmt(duration)}', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  static String _num(double s) => s == s.roundToDouble() ? s.toStringAsFixed(0) : '$s';

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
