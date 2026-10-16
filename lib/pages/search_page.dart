import 'package:flutter/material.dart';

import '../maccms_api.dart';
import '../models.dart';
import '../source_store.dart';
import 'detail_page.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final List<Vod> _results = [];
  final Map<String, String> _errors = {};
  int _pending = 0;
  int _total = 0;
  int _generation = 0;
  bool _searched = false;

  /// 同名的片子合并成一条，进详情页再选源。
  List<List<Vod>> get _groups {
    final map = <String, List<Vod>>{};
    for (final v in _results) {
      map.putIfAbsent(v.name.replaceAll(RegExp(r'\s+'), '').toLowerCase(), () => []).add(v);
    }
    return map.values.toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 所有内置源同时搜，哪个先返回先显示哪个。
  void _search() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();
    const sources = kDefaultSources;
    final gen = ++_generation;
    setState(() {
      _results.clear();
      _errors.clear();
      _pending = sources.length;
      _total = sources.length;
      _searched = true;
    });
    for (final source in sources) {
      MacCmsApi.search(source, keyword).then((list) {
        if (!mounted || gen != _generation) return;
        setState(() => _results.addAll(list));
      }).catchError((Object e) {
        if (!mounted || gen != _generation) return;
        setState(() => _errors[source.name] = '$e');
      }).whenComplete(() {
        if (!mounted || gen != _generation) return;
        setState(() => _pending--);
      });
    }
  }

  /// 清空搜索框和结果，回到首页状态；同时让还在路上的请求作废。
  void _clear() {
    _controller.clear();
    setState(() {
      _generation++;
      _results.clear();
      _errors.clear();
      _pending = 0;
      _total = 0;
      _searched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放一烨'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (_, value, _) => TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: '输入剧名搜索',
                        border: const OutlineInputBorder(),
                        suffixIcon: value.text.isEmpty && !_searched
                            ? null
                            : IconButton(tooltip: '清除', onPressed: _clear, icon: const Text('❌')),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: _search, child: const Text('搜索')),
              ],
            ),
            const SizedBox(height: 8),
            _statusBar(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _statusBar() {
    if (!_searched) return const SizedBox.shrink();
    final done = _total - _pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pending > 0) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '已返回 $done/$_total 个源，共 ${_groups.length} 部'
            '${_errors.isEmpty ? '' : '，${_errors.length} 个源失败（点此查看）'}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      ],
    ).wrapTap(_errors.isEmpty ? null : _showErrors);
  }

  void _showErrors() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('失败的源'),
        content: SingleChildScrollView(
          child: Text(_errors.entries.map((e) => '${e.key}：${e.value}').join('\n\n')),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }

  Widget _body() {
    if (_results.isEmpty) {
      return Center(
        child: Text(!_searched
            ? '输入剧名点搜索'
            : _pending > 0
                ? '搜索中…'
                : '没有搜到结果'),
      );
    }
    final groups = _groups;
    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final g = groups[i];
        final v = g.first;
        final pic = g.map((e) => e.pic).firstWhere((p) => p.isNotEmpty, orElse: () => '');
        final sub = ['${g.length} 个源', v.remarks, v.typeName, v.year].where((s) => s.isNotEmpty).join(' · ');
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: Poster(url: pic, width: 48, height: 68),
          title: Text(v.name),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(candidates: g))),
        );
      },
    );
  }
}
