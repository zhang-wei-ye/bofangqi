import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../net.dart';
import 'widgets.dart';

class PlayerPage extends StatefulWidget {
  final Vod vod;
  final PlayLine line;
  final int index;
  const PlayerPage({super.key, required this.vod, required this.line, required this.index});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late int _index = widget.index;
  VideoPlayerController? _vCtrl;
  ChewieController? _cCtrl;
  String? _error;
  bool _autoNextFired = false;
  int _openToken = 0;

  List<Episode> get _episodes => widget.line.episodes;
  Episode get _current => _episodes[_index];

  @override
  void initState() {
    super.initState();
    _open(_index);
  }

  Future<void> _open(int index) async {
    final token = ++_openToken;
    final oldV = _vCtrl;
    final oldC = _cCtrl;
    setState(() {
      _index = index;
      _vCtrl = null;
      _cCtrl = null;
      _error = null;
      _autoNextFired = false;
    });
    oldC?.dispose();
    await oldV?.dispose();

    final ep = _episodes[index];
    final v = VideoPlayerController.networkUrl(Uri.parse(ep.url), httpHeaders: {'User-Agent': kUserAgent});
    try {
      await v.initialize();
    } catch (e) {
      await v.dispose();
      if (!mounted || token != _openToken) return;
      setState(() => _error = ep.isDirect
          ? '播放失败：$e\n可能是这条线路的资源失效了，换条线路试试'
          : '这条线路不是直链（需要网页解析），播放器无法直接播放，请换一条线路');
      return;
    }
    if (!mounted || token != _openToken) {
      await v.dispose();
      return;
    }
    v.addListener(() => _checkCompleted(v));
    final c = ChewieController(
      videoPlayerController: v,
      autoPlay: true,
      allowFullScreen: true,
      aspectRatio: v.value.aspectRatio > 0 ? v.value.aspectRatio : 16 / 9,
    );
    setState(() {
      _vCtrl = v;
      _cCtrl = c;
    });
  }

  /// 播完自动下一集。
  void _checkCompleted(VideoPlayerController v) {
    final val = v.value;
    if (_autoNextFired || v != _vCtrl || !val.isInitialized || val.duration == Duration.zero) return;
    if (!val.isPlaying && val.position >= val.duration - const Duration(milliseconds: 500)) {
      _autoNextFired = true;
      if (_cCtrl?.isFullScreen == true) _cCtrl?.exitFullScreen();
      if (_index + 1 < _episodes.length) _open(_index + 1);
    }
  }

  @override
  void dispose() {
    _openToken++;
    _cCtrl?.dispose();
    _vCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.vod.name} ${_current.name}')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: AspectRatio(aspectRatio: 16 / 9, child: Container(color: Colors.black, child: _player())),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text('${widget.line.name} · ${_current.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  TextButton.icon(
                    onPressed: _index > 0 ? () => _open(_index - 1) : null,
                    icon: const Icon(Icons.skip_previous),
                    label: const Text('上一集'),
                  ),
                  TextButton.icon(
                    onPressed: _index + 1 < _episodes.length ? () => _open(_index + 1) : null,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('下一集'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: EpisodeGrid(
              names: _episodes.map((e) => e.name).toList(),
              current: _index,
              onTap: (i) {
                if (i != _index) _open(i);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _player() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              TextButton(onPressed: () => _open(_index), child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_cCtrl == null) return const Center(child: CircularProgressIndicator());
    return Chewie(controller: _cCtrl!);
  }
}
