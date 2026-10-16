import 'package:http/http.dart' as http;

import 'net.dart';

/// HLS 主播放列表（master playlist）里的一档清晰度。
class HlsVariant {
  final String label;
  final String url;
  final int height;
  final int bandwidth;
  const HlsVariant({required this.label, required this.url, required this.height, required this.bandwidth});
}

/// 读取 m3u8，如果是主播放列表就列出里面的各档清晰度（从高到低）。
/// 不是主播放列表、请求失败时返回空列表。
Future<List<HlsVariant>> fetchHlsVariants(String url) async {
  try {
    final uri = Uri.parse(url);
    final res = await http
        .get(uri, headers: {'User-Agent': kUserAgent})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return [];
    return parseHlsVariants(res.body, uri);
  } catch (_) {
    return [];
  }
}

List<HlsVariant> parseHlsVariants(String body, Uri base) {
  final lines = body.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
  final variants = <HlsVariant>[];
  final seen = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
    final attrs = line.substring('#EXT-X-STREAM-INF:'.length);
    final res = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(attrs);
    final bw = int.tryParse(RegExp(r'(?:^|,)BANDWIDTH=(\d+)').firstMatch(attrs)?.group(1) ?? '') ?? 0;
    final next = lines.skip(i + 1).firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
    if (next.isEmpty) continue;
    final variantUrl = base.resolve(next).toString();
    if (!seen.add(variantUrl)) continue;
    final w = int.tryParse(res?.group(1) ?? '') ?? 0;
    final h = int.tryParse(res?.group(2) ?? '') ?? 0;
    final shortSide = w > 0 && h > 0 ? (w < h ? w : h) : 0;
    variants.add(HlsVariant(
      label: shortSide > 0 ? qualityLabel(shortSide) : (bw > 0 ? '${(bw / 1000).round()}K' : '线路${variants.length + 1}'),
      url: variantUrl,
      height: shortSide,
      bandwidth: bw,
    ));
  }
  variants.sort((a, b) => a.height != b.height ? b.height - a.height : b.bandwidth - a.bandwidth);
  return variants;
}

/// 按画面短边给出常见的清晰度叫法。
String qualityLabel(int shortSide) {
  if (shortSide >= 2000) return '4K';
  if (shortSide >= 1400) return '2K';
  if (shortSide >= 1000) return '1080P';
  if (shortSide >= 700) return '720P';
  if (shortSide >= 460) return '480P';
  if (shortSide >= 340) return '360P';
  return '${shortSide}P';
}
