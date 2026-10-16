import 'package:flutter/material.dart';

import '../maccms_api.dart';
import '../models.dart';
import '../source_store.dart';

class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key});

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  List<VideoSource> _sources = [];
  bool _loading = true;
  final Map<int, String> _testResult = {};

  @override
  void initState() {
    super.initState();
    SourceStore.load().then((s) {
      if (mounted) {
        setState(() {
          _sources = s;
          _loading = false;
        });
      }
    });
  }

  Future<void> _update(List<VideoSource> next) async {
    setState(() {
      _sources = next;
      _testResult.clear();
    });
    await SourceStore.save(next);
  }

  Future<void> _edit([int? index]) async {
    final old = index == null ? null : _sources[index];
    final nameCtrl = TextEditingController(text: old?.name ?? '');
    final apiCtrl = TextEditingController(text: old?.api ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(old == null ? '添加数据源' : '编辑数据源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称（随便起）')),
            TextField(
              controller: apiCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '接口地址',
                hintText: 'https://xxx.com/api.php/provide/vod/',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final api = apiCtrl.text.trim();
    if (!api.startsWith('http')) {
      _toast('接口地址要以 http:// 或 https:// 开头');
      return;
    }
    final name = nameCtrl.text.trim().isEmpty ? (Uri.tryParse(api)?.host ?? api) : nameCtrl.text.trim();
    final next = [..._sources];
    final s = VideoSource(name: name, api: api, enabled: old?.enabled ?? true);
    if (index == null) {
      next.add(s);
    } else {
      next[index] = s;
    }
    await _update(next);
  }

  /// 每行一个源：「名称,地址」或者只写地址。
  Future<void> _batchImport() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量导入'),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '每行一个，格式：\n名称,接口地址\n或者只写接口地址',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    final existing = _sources.map((s) => s.api).toSet();
    final added = <VideoSource>[];
    for (final raw in ctrl.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = RegExp(r'^(.*?)[,，\s]+(https?://\S+)$').firstMatch(line);
      final api = m != null ? m.group(2)! : line;
      if (!api.startsWith('http') || existing.contains(api)) continue;
      final name = (m?.group(1)?.trim().isNotEmpty ?? false) ? m!.group(1)!.trim() : (Uri.tryParse(api)?.host ?? api);
      existing.add(api);
      added.add(VideoSource(name: name, api: api));
    }
    await _update([..._sources, ...added]);
    _toast('导入了 ${added.length} 个源');
  }

  Future<void> _test(int index) async {
    setState(() => _testResult[index] = '测试中…');
    String r;
    try {
      final n = await MacCmsApi.test(_sources[index]);
      r = '✅ 可用，片库 $n 部';
    } catch (e) {
      r = '❌ $e';
    }
    if (mounted) setState(() => _testResult[index] = r);
  }

  Future<void> _testAll() async {
    for (var i = 0; i < _sources.length; i++) {
      _test(i);
    }
  }

  /// 把删掉的默认源补回来，自己加的不动。
  Future<void> _restoreDefaults() async {
    final existing = _sources.map((s) => s.api).toSet();
    final missing = kDefaultSources.where((s) => !existing.contains(s.api)).toList();
    await _update([..._sources, ...missing]);
    _toast(missing.isEmpty ? '默认源都在，无需恢复' : '补回了 ${missing.length} 个默认源');
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据源管理'),
        actions: [
          IconButton(icon: const Icon(Icons.network_check), tooltip: '全部测试', onPressed: _testAll),
          IconButton(icon: const Icon(Icons.playlist_add), tooltip: '批量导入', onPressed: _batchImport),
          TextButton(onPressed: _restoreDefaults, child: const Text('恢复默认')),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '点右下角 + 添加苹果 CMS 采集接口\n'
                      '地址一般长这样：https://xxx.com/api.php/provide/vod/\n'
                      '有多个地址可以点右上角批量导入',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _sources.length,
                  onReorder: (from, to) {
                    final next = [..._sources];
                    final item = next.removeAt(from);
                    next.insert(to > from ? to - 1 : to, item);
                    _update(next);
                  },
                  itemBuilder: (_, i) {
                    final s = _sources[i];
                    final test = _testResult[i];
                    return ListTile(
                      key: ValueKey('${s.api}#$i'),
                      leading: Switch(
                        value: s.enabled,
                        onChanged: (v) {
                          final next = [..._sources];
                          next[i] = s.copyWith(enabled: v);
                          _update(next);
                        },
                      ),
                      title: Text(s.name),
                      subtitle: Text(
                        test == null ? s.api : '${s.api}\n$test',
                        style: const TextStyle(fontSize: 11),
                      ),
                      isThreeLine: test != null,
                      onTap: () => _edit(i),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) async {
                          if (a == 'test') _test(i);
                          if (a == 'edit') _edit(i);
                          if (a == 'delete') await _update([..._sources]..removeAt(i));
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'test', child: Text('测试')),
                          PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
