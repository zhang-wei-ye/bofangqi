import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'net.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// 苹果 CMS 标准采集接口（JSON 版）。
class MacCmsApi {
  static const _timeout = Duration(seconds: 15);

  /// 用户填的地址可能带着 ac/wd 等参数，或者只填了域名，这里统一整理。
  static Uri buildUri(String api, Map<String, String> params) {
    var u = Uri.parse(api.trim());
    if (u.path.isEmpty || u.path == '/') {
      u = u.replace(path: '/api.php/provide/vod/');
    }
    final q = Map<String, String>.from(u.queryParameters)
      ..removeWhere((k, _) => const {'ac', 'wd', 'ids', 'pg', 't', 'h'}.contains(k))
      ..addAll(params);
    return u.replace(queryParameters: q);
  }

  static Future<List<Vod>> search(VideoSource source, String keyword) async {
    final j = await _getJson(buildUri(source.api, {'ac': 'detail', 'wd': keyword}));
    final list = _list(j).map((e) => Vod.fromJson(e, source)).where((v) => v.name.isNotEmpty).toList();
    // 有些接口不支持 wd，会直接返回最新列表；一个名字都对不上就当作没搜到。
    final kw = keyword.toLowerCase();
    if (list.isNotEmpty && !list.any((v) => v.name.toLowerCase().contains(kw))) return [];
    return list;
  }

  static Future<Vod?> detail(VideoSource source, String id) async {
    final j = await _getJson(buildUri(source.api, {'ac': 'detail', 'ids': id}));
    final list = _list(j);
    return list.isEmpty ? null : Vod.fromJson(list.first, source);
  }

  /// 测试接口是否可用，返回片库总数。
  static Future<int> test(VideoSource source) async {
    final j = await _getJson(buildUri(source.api, {'ac': 'list'}));
    if (j['list'] is! List) throw ApiException('返回的 JSON 里没有 list 字段，不是苹果 CMS 接口');
    return int.tryParse('${j['total'] ?? ''}') ?? (j['list'] as List).length;
  }

  static List<Map<String, dynamic>> _list(Map<String, dynamic> j) {
    final l = j['list'];
    if (l is! List) return [];
    return l.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  static Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await http
        .get(uri, headers: {'User-Agent': kUserAgent, 'Accept': 'application/json,*/*'})
        .timeout(_timeout);
    if (res.statusCode != 200) throw ApiException('HTTP ${res.statusCode}');
    var body = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
    if (body.startsWith('﻿')) body = body.substring(1);
    if (!body.startsWith('{')) {
      if (body.startsWith('<')) throw ApiException('返回的是网页或 XML，不是 JSON 接口');
      // 有的接口会直接回一句话，比如"暂不支持搜索"
      throw ApiException(body.isEmpty ? '返回内容为空' : body.length <= 40 ? body : '返回内容不是 JSON');
    }
    final j = jsonDecode(body);
    if (j is! Map) throw ApiException('JSON 格式不对');
    return j.cast<String, dynamic>();
  }
}
