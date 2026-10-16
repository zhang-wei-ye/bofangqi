import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 一部片最后看到哪：哪个源、哪条线路、第几集、播到几分几秒。
class WatchRecord {
  final String name;
  final String sourceApi;
  final String sourceName;
  final String vodId;
  final String pic;
  final String lineName;
  final int episodeIndex;
  final String episodeName;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  const WatchRecord({
    required this.name,
    required this.sourceApi,
    required this.sourceName,
    this.vodId = '',
    this.pic = '',
    required this.lineName,
    required this.episodeIndex,
    required this.episodeName,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  /// 这一集是不是基本看完了（剩不到 15 秒）。
  bool get finished => durationMs > 0 && durationMs - positionMs < 15000;

  VideoSource get source => VideoSource(name: sourceName, api: sourceApi);

  /// 上次那一集在 [line] 里的位置：先按集名找，找不到按序号。
  int? episodeIn(PlayLine line) {
    final byName = line.episodes.indexWhere((e) => e.name == episodeName);
    if (byName >= 0) return byName;
    return episodeIndex < line.episodes.length ? episodeIndex : null;
  }

  /// 接着看该播哪一集、从哪开始：没看完就从断点续播，看完了就播下一集。
  ({int index, Duration? startAt})? resumeIn(PlayLine line) {
    final i = episodeIn(line);
    if (i == null) return null;
    if (finished && i + 1 < line.episodes.length) return (index: i + 1, startAt: null);
    return (index: i, startAt: finished ? null : position);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'sourceApi': sourceApi,
    'sourceName': sourceName,
    'vodId': vodId,
    'pic': pic,
    'lineName': lineName,
    'episodeIndex': episodeIndex,
    'episodeName': episodeName,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt,
  };

  factory WatchRecord.fromJson(Map<String, dynamic> j) => WatchRecord(
    name: '${j['name'] ?? ''}',
    sourceApi: '${j['sourceApi'] ?? ''}',
    sourceName: '${j['sourceName'] ?? ''}',
    vodId: '${j['vodId'] ?? ''}',
    pic: '${j['pic'] ?? ''}',
    lineName: '${j['lineName'] ?? ''}',
    episodeIndex: (j['episodeIndex'] as num?)?.toInt() ?? 0,
    episodeName: '${j['episodeName'] ?? ''}',
    positionMs: (j['positionMs'] as num?)?.toInt() ?? 0,
    durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
    updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
  );
}

/// 观看记录按片名存在本机（同一部片换了源也认得出来），最多留最近 200 部。
class HistoryStore {
  static const _key = 'watch_history_v1';
  static const _max = 200;

  static String keyOf(String name) => name.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  static Future<Map<String, WatchRecord>> _all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map;
      return {
        for (final e in map.entries)
          if (e.value is Map) '${e.key}': WatchRecord.fromJson((e.value as Map).cast<String, dynamic>()),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<WatchRecord?> get(String name) async => (await _all())[keyOf(name)];

  /// 全部记录，最近看的在前。
  static Future<List<WatchRecord>> list() async =>
      (await _all()).values.toList()..sort((a, b) => b.updatedAt - a.updatedAt);

  static Future<void> remove(String name) async {
    final all = await _all();
    all.remove(keyOf(name));
    await _write(all);
  }

  static Future<void> clear() => _write({});

  static Future<void> _write(Map<String, WatchRecord> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
  }

  static Future<void> save(WatchRecord r) async {
    final all = await _all();
    all[keyOf(r.name)] = r;
    final entries = all.entries.toList()..sort((a, b) => b.value.updatedAt - a.value.updatedAt);
    await _write(Map.fromEntries(entries.take(_max)));
  }
}
