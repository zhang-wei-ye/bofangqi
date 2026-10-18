import 'package:flutter/material.dart';

import '../downloads.dart';
import '../history_store.dart';
import 'player_page.dart';
import 'widgets.dart';

/// 离线缓存：分「下载中」和「已下载」两栏，已下载的没网也能看，进度和在线播放记在同一份观看历史里。
class CachePage extends StatelessWidget {
  const CachePage({super.key});

  @override
  Widget build(BuildContext context) {
    final dm = DownloadManager.instance;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的缓存'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '下载中'),
              Tab(text: '已下载'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: dm,
          builder: (context, _) {
            if (!dm.loaded) return const Center(child: CircularProgressIndicator());
            return TabBarView(
              children: [
                _DownloadingTab(tasks: dm.unfinished),
                _DoneTab(groups: dm.groups),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DownloadingTab extends StatelessWidget {
  final List<DownloadTask> tasks;
  const _DownloadingTab({required this.tasks});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const _Empty(icon: Icons.downloading, text: '没有正在下载的任务\n在详情页右上角点缓存按钮选集');
    final dm = DownloadManager.instance;
    final anyActive = tasks.any((t) => t.status == DownloadStatus.running || t.status == DownloadStatus.waiting);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('共 ${tasks.length} 个任务', style: const TextStyle(fontSize: 12, color: Colors.white60)),
              ),
              TextButton.icon(
                onPressed: anyActive ? dm.pauseAll : dm.resumeAll,
                icon: Icon(anyActive ? Icons.pause : Icons.play_arrow, size: 18),
                label: Text(anyActive ? '全部暂停' : '全部开始'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: tasks.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _item(context, tasks[i]),
          ),
        ),
      ],
    );
  }

  Widget _item(BuildContext context, DownloadTask t) {
    final dm = DownloadManager.instance;
    final pct = '${(t.progress * 100).toStringAsFixed(0)}%';
    final size = t.bytes > 0 ? ' · ${formatBytes(t.bytes)}' : '';
    final status = switch (t.status) {
      DownloadStatus.waiting => '等待中$size',
      DownloadStatus.running => t.totalUnits == 0 ? '正在解析…' : '$pct$size · ${formatBytes(t.speed)}/s',
      DownloadStatus.paused => '已暂停 $pct$size',
      DownloadStatus.failed => '失败：${t.error ?? '未知错误'}',
      DownloadStatus.done => '已完成',
    };
    final (IconData icon, String tip, VoidCallback onTap) = switch (t.status) {
      DownloadStatus.running || DownloadStatus.waiting => (Icons.pause, '暂停', () => dm.pause(t)),
      DownloadStatus.failed => (Icons.refresh, '重试', () => dm.resume(t)),
      _ => (Icons.play_arrow, '继续', () => dm.resume(t)),
    };
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: const _DeleteBackground(),
      onDismissed: (_) => dm.remove([t]),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Poster(url: t.pic, file: dm.coverOf(t), width: 40, height: 56),
        title: Text('${t.vodName} ${t.episodeName}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: t.status == DownloadStatus.running && t.totalUnits == 0 ? null : t.progress,
              minHeight: 3,
              color: t.status == DownloadStatus.failed ? Colors.redAccent : null,
            ),
            const SizedBox(height: 4),
            Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: t.status == DownloadStatus.failed ? Colors.redAccent : null),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(tooltip: tip, onPressed: onTap, icon: Icon(icon)),
            IconButton(
              tooltip: '删除',
              onPressed: () async {
                if (await _confirm(context, '删除「${t.vodName} ${t.episodeName}」的下载任务？')) dm.remove([t]);
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneTab extends StatelessWidget {
  final List<OfflineGroup> groups;
  const _DoneTab({required this.groups});

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const _Empty(icon: Icons.download_done, text: '还没有缓存的影视\n缓存后没网也能看');
    final dm = DownloadManager.instance;
    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final g = groups[i];
        return Dismissible(
          key: ValueKey(g.key),
          direction: DismissDirection.endToStart,
          background: const _DeleteBackground(),
          confirmDismiss: (_) => _confirm(context, '删除「${g.vodName}」已缓存的 ${g.tasks.length} 集？'),
          onDismissed: (_) => dm.remove(g.tasks),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Poster(url: g.first.pic, file: dm.coverOf(g.first), width: 48, height: 68),
            title: Text(g.vodName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${g.sourceName} · ${g.lineName}\n已缓存 ${g.tasks.length} 集 · ${formatBytes(g.bytes)}',
              maxLines: 2,
              style: const TextStyle(fontSize: 12),
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: '删除',
              onPressed: () async {
                if (await _confirm(context, '删除「${g.vodName}」已缓存的 ${g.tasks.length} 集？')) dm.remove(g.tasks);
              },
              icon: const Icon(Icons.delete_outline),
            ),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CachedVodPage(groupKey: g.key))),
          ),
        );
      },
    );
  }
}

/// 一部片已缓存的集数，点一下离线播放；上次没看完的那集从断点接着播。
class CachedVodPage extends StatefulWidget {
  final String groupKey;
  const CachedVodPage({super.key, required this.groupKey});

  @override
  State<CachedVodPage> createState() => _CachedVodPageState();
}

class _CachedVodPageState extends State<CachedVodPage> {
  final _dm = DownloadManager.instance;
  WatchRecord? _record;

  /// 不为空时是多选删除模式，里面是选中的任务 id。
  Set<String>? _selecting;

  void _toggle(DownloadTask t) =>
      setState(() => _selecting!.contains(t.id) ? _selecting!.remove(t.id) : _selecting!.add(t.id));

  Future<void> _deleteSelected(OfflineGroup g) async {
    final list = g.tasks.where((t) => _selecting!.contains(t.id)).toList();
    if (list.isEmpty) return;
    final all = list.length == g.tasks.length;
    if (!await _confirm(context, all ? '删除「${g.vodName}」已缓存的全部 ${list.length} 集？' : '删除选中的 ${list.length} 集？')) return;
    _dm.remove(list);
    if (!mounted) return;
    setState(() => _selecting = null);
    if (all) Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    final g = _dm.group(widget.groupKey);
    if (g == null) return;
    final r = await HistoryStore.get(g.vodName);
    if (mounted) setState(() => _record = r);
  }

  Future<void> _play(OfflineGroup g, int i) async {
    final r = _record;
    final resume = r != null && r.episodeName == g.tasks[i].episodeName && !r.finished && r.positionMs > 0;
    await playOffline(context, g, i, startAt: resume ? r.position : null);
    _loadRecord();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _dm,
      builder: (context, _) {
        final g = _dm.group(widget.groupKey);
        final sel = _selecting;
        if (g != null && sel != null) sel.removeWhere((id) => !g.tasks.any((t) => t.id == id));
        final allSelected = g != null && sel != null && sel.length == g.tasks.length;
        return PopScope(
          // 多选时按返回键先退出多选。
          canPop: sel == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => _selecting = null);
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(sel != null ? '已选 ${sel.length} 集' : g?.vodName ?? '已缓存'),
              leading: sel == null
                  ? null
                  : IconButton(onPressed: () => setState(() => _selecting = null), icon: const Icon(Icons.close)),
              actions: [
                if (g != null && sel == null)
                  IconButton(
                    tooltip: '删除',
                    onPressed: () => setState(() => _selecting = {}),
                    icon: const Icon(Icons.delete_outline),
                  ),
                if (g != null && sel != null)
                  TextButton(
                    onPressed: () => setState(() => allSelected ? sel.clear() : sel.addAll(g.tasks.map((t) => t.id))),
                    child: Text(allSelected ? '取消全选' : '全选'),
                  ),
              ],
            ),
            bottomNavigationBar: g == null || sel == null
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                        onPressed: sel.isEmpty ? null : () => _deleteSelected(g),
                        icon: const Icon(Icons.delete),
                        label: Text(sel.isEmpty ? '选择要删除的集' : '删除 ${sel.length} 集'),
                      ),
                    ),
                  ),
            body: g == null
                ? const _Empty(icon: Icons.download_done, text: '缓存已经删光了')
                : ListView.separated(
                    itemCount: g.tasks.length + 1,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => i == 0 ? _header(g) : _episode(g, i - 1),
                  ),
          ),
        );
      },
    );
  }

  Widget _header(OfflineGroup g) {
    final r = _record;
    final last = r == null ? -1 : g.tasks.indexWhere((t) => t.episodeName == r.episodeName);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Poster(url: g.first.pic, file: _dm.coverOf(g.first), width: 72, height: 100),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.vodName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  '${g.sourceName} · ${g.lineName}\n${g.tasks.length} 集 · ${formatBytes(g.bytes)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                if (last >= 0) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => r.finished && last + 1 < g.tasks.length ? _play(g, last + 1) : _play(g, last),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(r!.finished && last + 1 < g.tasks.length ? '看下一集' : '继续看 ${r.episodeName}'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _episode(OfflineGroup g, int i) {
    final t = g.tasks[i];
    final r = _record;
    final isLast = r != null && r.episodeName == t.episodeName;
    final progress = !isLast
        ? ''
        : r.finished
        ? ' · 已看完'
        : r.positionMs > 0
        ? ' · 看到 ${_fmt(r.position)}'
        : '';
    final sel = _selecting;
    if (sel != null) {
      return CheckboxListTile(
        value: sel.contains(t.id),
        onChanged: (_) => _toggle(t),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(t.episodeName),
        subtitle: Text('${formatBytes(t.bytes)}$progress', style: const TextStyle(fontSize: 12)),
      );
    }
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: const _DeleteBackground(),
      onDismissed: (_) => _dm.remove([t]),
      child: ListTile(
        leading: Icon(isLast ? Icons.play_circle : Icons.play_circle_outline, color: isLast ? Colors.blue : null),
        title: Text(t.episodeName),
        subtitle: Text('${formatBytes(t.bytes)}$progress', style: const TextStyle(fontSize: 12)),
        onTap: () => _play(g, i),
        // 长按直接进多选，并选中这一集。
        onLongPress: () => setState(() => _selecting = {t.id}),
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
}

/// 用缓存好的文件打开播放页。播放页照常记进度，和在线播放共用一份观看历史。
Future<void> playOffline(BuildContext context, OfflineGroup g, int index, {Duration? startAt}) async {
  final o = await DownloadManager.instance.offline(g);
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlayerPage(vod: o.vod, line: o.line, index: index, startAt: startAt, offline: true),
    ),
  );
}

/// 没网时历史记录打不开，看看这部片有没有缓存：有就按记录接着播。
Future<bool> playOfflineRecord(BuildContext context, WatchRecord r) async {
  final key = HistoryStore.keyOf(r.name);
  final groups = DownloadManager.instance.groups.where((g) => HistoryStore.keyOf(g.vodName) == key).toList();
  if (groups.isEmpty) return false;
  final g = groups.firstWhere(
    (g) => g.first.sourceApi == r.sourceApi && g.lineName == r.lineName,
    orElse: () => groups.first,
  );
  final i = g.tasks.indexWhere((t) => t.episodeName == r.episodeName);
  if (i < 0) {
    await playOffline(context, g, 0);
  } else if (r.finished && i + 1 < g.tasks.length) {
    await playOffline(context, g, i + 1);
  } else {
    await playOffline(context, g, i, startAt: r.finished ? null : r.position);
  }
  return true;
}

Future<bool> _confirm(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
      ],
    ),
  );
  return ok == true;
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.redAccent,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }
}
