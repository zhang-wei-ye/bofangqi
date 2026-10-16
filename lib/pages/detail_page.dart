import 'package:flutter/material.dart';

import '../maccms_api.dart';
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

  Vod get _vod => _cands[_sel];

  @override
  void initState() {
    super.initState();
    // 搜索接口用的是 ac=detail，一般已经带了播放列表；没带再单独请求一次。
    if (_vod.lines.isEmpty) _loadDetail();
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
                onTap: (i) => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PlayerPage(vod: _vod, line: line, index: i)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
