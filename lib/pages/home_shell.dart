import 'package:flutter/material.dart';

import 'cache_page.dart';
import 'history_page.dart';
import 'search_page.dart';

/// 底部导航：首页（搜索）、观看历史和离线缓存。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  /// 每次切到历史页都换个 key 让它重新读记录，搜索页的状态则一直保留。
  int _historyVisits = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const SearchPage(),
          HistoryPage(key: ValueKey(_historyVisits)),
          const CachePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          if (i == 1 && _tab != 1) _historyVisits++;
          _tab = i;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: '缓存'),
        ],
      ),
    );
  }
}
