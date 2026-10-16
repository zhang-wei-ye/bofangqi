import 'dart:async';

import 'package:flutter/material.dart';

import '../dlna.dart';

/// 弹出底部面板搜索投屏设备，返回用户选中的设备；取消返回 null。
Future<DlnaDevice?> showCastPicker(BuildContext context) => showModalBottomSheet<DlnaDevice>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => const _CastSheet(),
);

class _CastSheet extends StatefulWidget {
  const _CastSheet();

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  final List<DlnaDevice> _devices = [];
  StreamSubscription<DlnaDevice>? _sub;
  bool _searching = false;
  String? _error;
  DlnaSearchLog _log = DlnaSearchLog();

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _search() {
    _sub?.cancel();
    setState(() {
      _devices.clear();
      _searching = true;
      _error = null;
      _log = DlnaSearchLog();
    });
    _sub = discoverDlna(log: _log).listen(
      (d) => setState(() => _devices.add(d)),
      onError: (Object e) => setState(() => _error = '$e'),
      onDone: () {
        if (mounted) setState(() => _searching = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: const Text('投屏到', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: _searching
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: _search, child: const Text('重新搜索')),
            ),
            for (final d in _devices)
              ListTile(
                leading: const Icon(Icons.tv),
                title: Text(d.name),
                subtitle: Text(d.controlUrl.host, style: const TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(context, d),
              ),
            if (_devices.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  _searching
                      ? '正在搜索局域网里的电视、盒子…'
                      : _error != null
                      ? '搜索失败：$_error'
                      : '没找到设备。请确认手机和电视连的是同一个 WiFi，并且电视已经打开投屏（DLNA）功能。'
                            '\n\n搜索记录：\n$_log',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
