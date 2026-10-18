import 'package:flutter/material.dart';

/// 离线缓存：分「下载中」和「已下载」两栏，已下载的没网也能看并记进度。
/// 目前只有页面框架，下载逻辑还没接。
class CachePage extends StatelessWidget {
  const CachePage({super.key});

  @override
  Widget build(BuildContext context) {
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
        body: const TabBarView(
          children: [
            _Empty(icon: Icons.downloading, text: '没有正在下载的任务\n在详情页选集即可缓存'),
            _Empty(icon: Icons.download_done, text: '还没有缓存的影视\n缓存后没网也能看'),
          ],
        ),
      ),
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
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
