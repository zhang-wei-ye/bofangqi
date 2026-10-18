import 'package:flutter/material.dart';

import '../history_store.dart';
import '../maccms_api.dart';
import '../models.dart';
import 'cache_page.dart';
import 'detail_page.dart';
import 'player_page.dart';
import 'widgets.dart';

/// 观看历史：点一下直接接着看，右边按钮进详情页，左滑删除。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<WatchRecord>? _records;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await HistoryStore.list();
    if (mounted) setState(() => _records = list);
  }

  /// 按记录里的源重新拿到这部片的播放列表；老记录没存 id 的按片名在那个源里搜。
  Future<Vod?> _fetchVod(WatchRecord r) async {
    if (r.vodId.isNotEmpty) {
      final v = await MacCmsApi.detail(r.source, r.vodId);
      if (v != null && v.lines.isNotEmpty) return v;
    }
    final found = await MacCmsApi.search(r.source, r.name);
    final key = HistoryStore.keyOf(r.name);
    for (final v in found) {
      if (HistoryStore.keyOf(v.name) != key) continue;
      if (v.lines.isNotEmpty) return v;
      return MacCmsApi.detail(r.source, v.id);
    }
    return null;
  }

  Future<void> _open(WatchRecord r, {bool detail = false}) async {
    if (_opening) return;
    setState(() => _opening = true);
    Vod? vod;
    String? error;
    try {
      vod = await _fetchVod(r);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (vod == null) {
      // 没网或源挂了，有缓存就先离线播。
      if (!detail && await playOfflineRecord(context, r)) {
        _load();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error == null ? '在「${r.sourceName}」源里没找到这部片了，去首页重新搜一下吧' : '加载失败：$error')),
      );
      return;
    }
    final lines = vod.playableLines;
    final line = lines.where((l) => l.name == r.lineName).firstOrNull ?? lines.firstOrNull;
    final target = line == null ? null : r.resumeIn(line);
    final Widget page = detail || line == null || target == null
        ? DetailPage(candidates: [vod])
        : PlayerPage(vod: vod, line: line, index: target.index, startAt: target.startAt);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _load();
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空观看历史？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await HistoryStore.clear();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(
        title: const Text('观看历史'),
        actions: [
          if (records != null && records.isNotEmpty)
            IconButton(tooltip: '清空', onPressed: _clearAll, icon: const Icon(Icons.delete_sweep_outlined)),
        ],
        bottom: _opening
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
          ? const Center(child: Text('还没有看过的影视，去首页搜一部吧'))
          : ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _item(records[i]),
            ),
    );
  }

  Widget _item(WatchRecord r) {
    final progress = r.finished
        ? '已看完'
        : r.positionMs > 0
        ? '看到 ${_fmt(r.position)}${r.durationMs > 0 ? ' / ${_fmt(r.duration)}' : ''}'
        : '';
    return Dismissible(
      key: ValueKey(HistoryStore.keyOf(r.name)),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        setState(() => _records!.remove(r));
        HistoryStore.remove(r.name);
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Poster(url: r.pic, width: 48, height: 68),
        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${r.episodeName} $progress\n${r.sourceName} · ${_ago(r.updatedAt)}',
          maxLines: 2,
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        onTap: () => _open(r),
        trailing: IconButton(
          tooltip: '详情',
          onPressed: () => _open(r, detail: true),
          icon: const Icon(Icons.info_outline),
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

  static String _ago(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 7) return '${d.inDays} 天前';
    return '${t.month}月${t.day}日';
  }
}
