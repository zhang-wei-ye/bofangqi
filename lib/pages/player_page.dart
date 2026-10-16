import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../cast_proxy.dart';
import '../dlna.dart';
import '../history_store.dart';
import '../hls.dart';
import '../models.dart';
import '../net.dart';
import 'cast_sheet.dart';
import 'player_controls.dart';
import 'widgets.dart';

class PlayerPage extends StatefulWidget {
  final Vod vod;
  final PlayLine line;
  final int index;

  /// 从这一集的哪里开始播（续播用），为空从头播。
  final Duration? startAt;
  const PlayerPage({super.key, required this.vod, required this.line, required this.index, this.startAt});

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
  int _episodeToken = 0;
  final _quality = ValueNotifier(const QualityState());
  String _playingUrl = '';

  /// 正在投屏的设备；投屏期间手机这边暂停，播放区换成遥控面板。
  DlnaController? _cast;
  bool _castPaused = false;
  String? _castStatus;
  int _castToken = 0;

  /// 默认通过手机中转给电视（电视直接拉源站经常失败），可以在遥控面板切成直连。
  bool _castViaProxy = true;

  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);

  List<Episode> get _episodes => widget.line.episodes;
  Episode get _current => _episodes[_index];

  @override
  void initState() {
    super.initState();
    _open(_index, startAt: widget.startAt);
  }

  /// 记下看到哪了，下次进详情页能接着看。
  void _saveProgress(Duration position, Duration duration) {
    _lastSaved = DateTime.now();
    HistoryStore.save(WatchRecord(
      name: widget.vod.name,
      sourceApi: widget.vod.source.api,
      sourceName: widget.vod.source.name,
      vodId: widget.vod.id,
      pic: widget.vod.pic,
      lineName: widget.line.name,
      episodeIndex: _index,
      episodeName: _current.name,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 播放过程中每 5 秒存一次进度。只在真正播着的时候存，免得续播跳转前把进度存成 0。
  void _onProgress(VideoPlayerController v) {
    final val = v.value;
    if (v != _vCtrl || !val.isInitialized || !val.isPlaying || val.duration == Duration.zero) return;
    if (DateTime.now().difference(_lastSaved) < const Duration(seconds: 5)) return;
    _saveProgress(val.position, val.duration);
  }

  /// 换集：重新识别这一集有哪些清晰度，先按原地址播放。
  void _open(int index, {Duration? startAt}) {
    final token = ++_episodeToken;
    _index = index;
    _quality.value = const QualityState();
    final url = _episodes[index].url;
    if (_episodes[index].isDirect) {
      fetchHlsVariants(url).then((variants) {
        if (!mounted || token != _episodeToken) return;
        _quality.value = QualityState(variants: variants, selected: _quality.value.selected);
      });
    }
    _play(url, startAt: startAt);
    if (_cast != null) {
      // 投屏时拿不到电视的进度，至少记下看到第几集。
      _saveProgress(Duration.zero, Duration.zero);
      _castTo(url);
    }
  }

  /// 换清晰度：从当前进度接着播，全屏的话换完还是全屏。
  void _selectQuality(int? selected) {
    final q = _quality.value;
    final url = selected == null ? _current.url : q.variants[selected].url;
    _quality.value = QualityState(variants: q.variants, selected: selected);
    _play(url, startAt: _vCtrl?.value.position, fullScreen: _cCtrl?.isFullScreen ?? false);
  }

  Future<void> _play(String url, {Duration? startAt, bool fullScreen = false}) async {
    final token = ++_openToken;
    _playingUrl = url;
    final oldV = _vCtrl;
    final oldC = _cCtrl;
    if (oldC?.isFullScreen == true) oldC!.exitFullScreen();
    setState(() {
      _vCtrl = null;
      _cCtrl = null;
      _error = null;
      _autoNextFired = false;
    });
    oldC?.dispose();
    await oldV?.dispose();

    final ep = _current;
    final v = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: {'User-Agent': kUserAgent});
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
    v.addListener(() {
      _checkCompleted(v);
      _onProgress(v);
    });
    final c = ChewieController(
      videoPlayerController: v,
      autoPlay: _cast == null,
      startAt: startAt,
      allowFullScreen: true,
      customControls: PlayerControls(quality: _quality, onSelectQuality: _selectQuality, onCast: _startCast),
      aspectRatio: v.value.aspectRatio > 0 ? v.value.aspectRatio : 16 / 9,
    );
    setState(() {
      _vCtrl = v;
      _cCtrl = c;
    });
    if (fullScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cCtrl == c) c.enterFullScreen();
      });
    }
  }

  /// 选设备投屏，从手机当前的进度接着播。
  Future<void> _startCast() async {
    if (_cCtrl?.isFullScreen == true) _cCtrl!.exitFullScreen();
    final device = await showCastPicker(context);
    if (device == null || !mounted) return;
    _vCtrl?.pause();
    setState(() => _cast = DlnaController(device));
    final pos = _vCtrl?.value.position;
    await _castTo(_playingUrl, startAt: pos);
  }

  Future<void> _castTo(String url, {Duration? startAt}) async {
    final cast = _cast;
    if (cast == null) return;
    final token = ++_castToken;
    setState(() {
      _castPaused = false;
      _castStatus = '正在连接…';
    });
    try {
      final castUrl = _castViaProxy ? await CastProxy.instance.wrap(url, tvHost: cast.device.controlUrl.host) : url;
      await cast.cast(castUrl, title: '${widget.vod.name} ${_current.name}', startAt: startAt);
      if (mounted && token == _castToken) setState(() => _castStatus = null);
    } catch (e) {
      if (mounted && token == _castToken) setState(() => _castStatus = '投屏失败：$e');
    }
  }

  Future<void> _toggleCastPause() async {
    final cast = _cast;
    if (cast == null) return;
    try {
      _castPaused ? await cast.play() : await cast.pause();
      if (mounted) setState(() => _castPaused = !_castPaused);
    } catch (e) {
      if (mounted) setState(() => _castStatus = '操作失败：$e');
    }
  }

  /// 停止投屏，回到手机上播放。
  void _stopCast() {
    _cast?.stop().catchError((_) {});
    _castToken++;
    setState(() {
      _cast = null;
      _castStatus = null;
    });
    _vCtrl?.play();
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
    final val = _vCtrl?.value;
    if (_cast == null && val != null && val.isInitialized && val.position > Duration.zero) {
      _saveProgress(val.position, val.duration);
    }
    _openToken++;
    _episodeToken++;
    _quality.dispose();
    _cCtrl?.dispose();
    _vCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.vod.name} ${_current.name}'),
        actions: [
          IconButton(
            tooltip: '投屏',
            onPressed: _cast == null ? _startCast : _stopCast,
            icon: Icon(_cast == null ? Icons.cast : Icons.cast_connected),
          ),
        ],
      ),
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
    if (_cast != null) return _castPanel();
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

  Widget _castPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cast_connected, color: Colors.white70, size: 36),
            const SizedBox(height: 8),
            Text('正在投屏到 ${_cast!.device.name}',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            if (_castStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_castStatus!,
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 投屏失败时把“暂停”换成“重试”。
                if (_castStatus?.startsWith('投屏失败') == true)
                  OutlinedButton.icon(
                    onPressed: () => _castTo(_playingUrl, startAt: _vCtrl?.value.position),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _toggleCastPause,
                    icon: Icon(_castPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(_castPaused ? '继续' : '暂停'),
                  ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _stopCast,
                  icon: const Icon(Icons.stop),
                  label: const Text('退出投屏'),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                setState(() => _castViaProxy = !_castViaProxy);
                _castTo(_playingUrl, startAt: _vCtrl?.value.position);
              },
              child: Text(
                _castViaProxy ? '当前：手机中转 · 改用直连' : '当前：电视直连 · 电视放不了就改用手机中转',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
