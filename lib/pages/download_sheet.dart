import 'package:flutter/material.dart';

import '../downloads.dart';
import '../models.dart';

/// 选集缓存：勾选要下的集，已经加入过缓存的标出状态、不能再选。
Future<void> showDownloadSheet(BuildContext context, Vod vod, PlayLine line) async {
  final added = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DownloadSheet(vod: vod, line: line),
  );
  if (added == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(added > 0 ? '已加入缓存 $added 集，可以在「缓存」里查看进度' : '选的集都已经在缓存里了')),
  );
}

class _DownloadSheet extends StatefulWidget {
  final Vod vod;
  final PlayLine line;
  const _DownloadSheet({required this.vod, required this.line});

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  final _selected = <int>{};
  final _dm = DownloadManager.instance;

  List<int> get _available => [
    for (var i = 0; i < widget.line.episodes.length; i++)
      if (widget.line.episodes[i].isDirect && _dm.find(widget.vod, widget.line, widget.line.episodes[i]) == null) i,
  ];

  @override
  Widget build(BuildContext context) {
    final eps = widget.line.episodes;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: ListenableBuilder(
        listenable: _dm,
        builder: (context, _) {
          final available = _available;
          final allSelected = available.isNotEmpty && available.every(_selected.contains);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('缓存 · ${widget.line.name}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: available.isEmpty
                          ? null
                          : () => setState(() => allSelected ? _selected.clear() : _selected.addAll(available)),
                      child: Text(allSelected ? '取消全选' : '全选'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 110,
                    childAspectRatio: 2.4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: eps.length,
                  itemBuilder: (_, i) => _cell(i, eps[i]),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : () async {
                              final n = await _dm.add(widget.vod, widget.line, _selected.toList()..sort());
                              if (context.mounted) Navigator.pop(context, n);
                            },
                      icon: const Icon(Icons.download),
                      label: Text(_selected.isEmpty ? '选择要缓存的集' : '缓存 ${_selected.length} 集'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cell(int i, Episode ep) {
    final task = _dm.find(widget.vod, widget.line, ep);
    final selected = _selected.contains(i);
    final IconData? icon = switch (task?.status) {
      DownloadStatus.done => Icons.download_done,
      DownloadStatus.failed => Icons.error_outline,
      null => null,
      _ => Icons.downloading,
    };
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        backgroundColor: selected ? Colors.blue : null,
        foregroundColor: selected ? Colors.white : null,
      ),
      onPressed: task != null || !ep.isDirect
          ? null
          : () => setState(() => selected ? _selected.remove(i) : _selected.add(i)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 2)],
          Flexible(
            child: Text(ep.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
