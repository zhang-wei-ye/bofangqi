import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 首次安装时预置的源（2026-10 实测可用且支持搜索）。
/// 之后都以用户在 App 里的修改为准，删掉的不会再自动加回来。
const List<VideoSource> kDefaultSources = [
  VideoSource(name: '非凡', api: 'http://cj.ffzyapi.com/api.php/provide/vod/'),
  VideoSource(name: '量子', api: 'https://cj.lziapi.com/api.php/provide/vod/'),
  VideoSource(name: '暴风', api: 'https://bfzyapi.com/api.php/provide/vod/'),
  VideoSource(name: '无尽', api: 'https://api.wujinapi.com/api.php/provide/vod/'),
  VideoSource(name: '红牛', api: 'https://www.hongniuzy2.com/api.php/provide/vod/'),
  VideoSource(name: '金鹰', api: 'http://jyzyapi.com/provide/vod/from/jinyingm3u8'),
  VideoSource(name: '光速', api: 'http://api.guangsuapi.com/api.php/provide/vod/from/gsm3u8'),
  VideoSource(name: '艾旦', api: 'http://lovedan.net/api.php/provide/vod'),
  VideoSource(name: '360', api: 'https://360zy.com/api.php/provide/vod/'),
  VideoSource(name: 'U酷', api: 'https://api.ukuapi.com/api.php/provide/vod/'),
  VideoSource(name: '百度', api: 'https://api.apibdzy.com/api.php/provide/vod/'),
  VideoSource(name: '豪华', api: 'https://hhzyapi.com/api.php/provide/vod/'),
  VideoSource(name: '极速', api: 'https://jszyapi.com/api.php/provide/vod'),
  VideoSource(name: 'ikun', api: 'https://ikunzyapi.com/api.php/provide/vod/'),
  VideoSource(name: '虎牙', api: 'https://www.huyaapi.com/api.php/provide/vod/'),
  VideoSource(name: '速博', api: 'https://subocaiji.com/api.php/provide/vod/'),
  VideoSource(name: '魔都', api: 'https://caiji.moduapi.cc/api.php/provide/vod/'),
  VideoSource(name: '最大', api: 'http://zuidazy.me/api.php/provide/vod/'),
  VideoSource(name: '新浪', api: 'https://api.xinlangapi.com/xinlangapi.php/provide/vod/'),
  // 以下接口能连上，但测试时返回"暂不支持搜索"或 403，默认关闭，可在手机上测试后自行开启
  VideoSource(name: '闪电', api: 'http://sdzyapi.com/api.php/provide/vod/', enabled: false),
  VideoSource(name: '牛牛', api: 'https://api.niuniuzy.me/api.php/provide/vod/', enabled: false),
  VideoSource(name: '丫丫', api: 'https://cj.yayazy.net/api.php/provide/vod/', enabled: false),
  VideoSource(name: '索尼', api: 'https://suoniapi.com/api.php/provide/vod/', enabled: false),
  VideoSource(name: '樱花', api: 'https://m3u8.apiyhzy.com/api.php/provide/vod/', enabled: false),
];

/// 数据源列表保存在本机，换源不用重新打包。
class SourceStore {
  static const _key = 'video_sources_v1';

  static Future<List<VideoSource>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      await save(kDefaultSources);
      return [...kDefaultSources];
    }
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().map((e) => VideoSource.fromJson(e.cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<VideoSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(sources.map((s) => s.toJson()).toList()));
  }
}
