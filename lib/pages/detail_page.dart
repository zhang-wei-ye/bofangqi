import 'package:flutter/material.dart';

import '../maccms_api.dart';
import '../history_store.dart';
import '../models.dart';
import 'player_page.dart';
import 'widgets.dart';

class DetailPage extends StatefulWidget {
  /// 同一部片在不同源里的结果，至少一个。
  final List<Vod> candidates;
  const DetailPage({super.key, required this.candidates});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late final List<Vod> _cands = [...widget.candidates];
  int _sel = 0;
  bool _loading = false;
  String? _error;
  int _line = 0;
  bool _expandContent = false;
  WatchRecord? _record;

  Vod get _vod => _cands[_sel];

  @override
  void initState() {
    super.initState();
    // 搜索接口用的是 ac=detail，一般已经带了播放列表；没带再单独请求一次。
    if (_vod.lines.isEmpty) _loadDetail();
    _loadRecord(selectLast: true);
  }

  /// 读观看记录；第一次进来时顺便切到上次看的源和线路。
  Future<void> _loadRecord({bool selectLast = false}) async {
    final r = await HistoryStore.get(_vod.name);
    if (!mounted || r == null) return;
    setState(() => _record = r);
    if (!selectLast) return;
    final src = _cands.indexWhere((c) => c.source.api == r.sourceApi);
    if (src >= 0 && src != _sel) _selectSource(src);
    _selectRecordLine();
  }

  void _selectRecordLine() {
    final r = _record;
    if (r == null || _vod.source.api != r.sourceApi) return;
    final i = _vod.playableLines.indexWhere((l) => l.name == r.lineName);
    if (i >= 0) setState(() => _line = i);
  }

  int? _recordEpisode(PlayLine line) => _record?.episodeIn(line);

  Future<void> _openPlayer(PlayLine line, int index, {Duration? startAt}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerPage(vod: _vod, line: line, index: index, startAt: startAt)),
    );
    _loadRecord();
  }

  void _resume(PlayLine line) {
    final t = _record?.resumeIn(line);
    if (t != null) _openPlayer(line, t.index, startAt: t.startAt);
  }

  void _selectSource(int i) {
    setState(() {
      _sel = i;
      _line = 0;
      _error = null;
    });
    if (_vod.lines.isEmpty) _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final sel = _sel;
    try {
      final v = await MacCmsApi.detail(_vod.source, _vod.id);
      if (!mounted) return;
      setState(() {
        if (v != null) _cands[sel] = v;
        _loading = false;
      });
      _selectRecordLine();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _vod.playableLines;
    final line = lines.isEmpty ? null : lines[_line.clamp(0, lines.length - 1)];
    return Scaffold(
      appBar: AppBar(title: Text(_vod.name)),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverToBoxAdapter(child: _header()),
          ),
          if (_cands.length > 1)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('播放源（${_cands.length}）', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    LineChips(
                      names: _cands.map((c) => c.remarks.isEmpty ? c.source.name : '${c.source.name}·${c.remarks}').toList(),
                      current: _sel,
                      onSelected: _selectSource,
                    ),
                  ],
                ),
              ),
            ),
          if (_loading)
            const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SliverToBoxAdapter(
              child: Center(
                child: Column(children: [
                  Text('加载失败：$_error', style: const TextStyle(color: Colors.redAccent)),
                  TextButton(onPressed: _loadDetail, child: const Text('重试')),
                ]),
              ),
            )
          else if (line == null)
            const SliverToBoxAdapter(child: Center(child: Text('这个源没有给出播放地址')))
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_record != null && _recordEpisode(line) != null) _resumeCard(line),
                    const Text('播放线路', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    LineChips(
                      names: lines.map((l) => l.name).toList(),
                      current: _line,
                      onSelected: (i) => setState(() => _line = i),
                    ),
                    if (!line.isDirect)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('该线路不是直链，可能无法播放',
                            style: TextStyle(fontSize: 12, color: Colors.orangeAccent)),
                      ),
                    const SizedBox(height: 12),
                    Text('选集（${line.episodes.length}）',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: EpisodeGrid(
                names: line.episodes.map((e) => e.name).toList(),
                current: _recordEpisode(line),
                // 点的正好是上次没看完的那一集，就从断点接着播。
                onTap: (i) => i == _recordEpisode(line) && !_record!.finished
                    ? _openPlayer(line, i, startAt: _record!.position)
                    : _openPlayer(line, i),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resumeCard(PlayLine line) {
    final r = _record!;
    final i = _recordEpisode(line)!;
    final hasNext = i + 1 < line.episodes.length;
    final progress = r.finished
        ? '已看完'
        : r.positionMs > 0
        ? '看到 ${_fmt(r.position)}${r.durationMs > 0 ? ' / ${_fmt(r.duration)}' : ''}'
        : '';
    final where = r.sourceApi == _vod.source.api ? '' : '（上次在「${r.sourceName}」源）';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text('上次看到 ${line.episodes[i].name} $progress'),
        subtitle: where.isEmpty ? null : Text(where, style: const TextStyle(fontSize: 12)),
        trailing: FilledButton(
          onPressed: () => _resume(line),
          child: Text(r.finished && hasNext ? '看下一集' : '继续播放'),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _header() {
    final v = _vod;
    final info = [
      '来源：${v.source.name}',
      if (v.remarks.isNotEmpty) v.remarks,
      [v.typeName, v.year, v.area].where((s) => s.isNotEmpty).join(' / '),
      if (v.actor.isNotEmpty) '主演：${v.actor}',
    ].where((s) => s.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Poster(url: v.pic, width: 100, height: 140),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  for (final s in info)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(s,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (v.content.isNotEmpty) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _expandContent = !_expandContent),
            child: Text(
              v.content,
              maxLines: _expandContent ? null : 3,
              overflow: _expandContent ? null : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
        ],
      ],
    );
  }
}
