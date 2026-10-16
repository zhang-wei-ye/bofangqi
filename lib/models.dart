import 'package:html/parser.dart' as html_parser;

/// 一个苹果 CMS（MacCMS）采集接口，例如 https://xxx.com/api.php/provide/vod/
class VideoSource {
  final String name;
  final String api;
  final bool enabled;

  const VideoSource({required this.name, required this.api, this.enabled = true});

  VideoSource copyWith({String? name, String? api, bool? enabled}) => VideoSource(
        name: name ?? this.name,
        api: api ?? this.api,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {'name': name, 'api': api, 'enabled': enabled};

  factory VideoSource.fromJson(Map<String, dynamic> j) => VideoSource(
        name: '${j['name'] ?? ''}',
        api: '${j['api'] ?? ''}',
        enabled: j['enabled'] != false,
      );
}

class Episode {
  final String name;
  final String url;
  const Episode(this.name, this.url);

  /// 能直接交给播放器的地址（m3u8 / mp4 等）；其他的多半是需要网页解析的分享页。
  bool get isDirect => RegExp(r'\.(m3u8|mp4|flv|mkv|mov)(\?|#|$)', caseSensitive: false).hasMatch(url);
}

class PlayLine {
  final String name;
  final List<Episode> episodes;
  const PlayLine(this.name, this.episodes);

  bool get isDirect => episodes.any((e) => e.isDirect);
}

class Vod {
  final VideoSource source;
  final String id;
  final String name;
  final String pic;
  final String remarks;
  final String typeName;
  final String year;
  final String area;
  final String actor;
  final String content;
  final List<PlayLine> lines;

  const Vod({
    required this.source,
    required this.id,
    required this.name,
    this.pic = '',
    this.remarks = '',
    this.typeName = '',
    this.year = '',
    this.area = '',
    this.actor = '',
    this.content = '',
    this.lines = const [],
  });

  /// 优先只给能直连播放的线路；一条都没有时退回全部线路。
  List<PlayLine> get playableLines {
    final direct = lines.where((l) => l.isDirect).toList();
    return direct.isNotEmpty ? direct : lines;
  }

  factory Vod.fromJson(Map<String, dynamic> j, VideoSource source) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return Vod(
      source: source,
      id: s('vod_id'),
      name: s('vod_name'),
      pic: s('vod_pic'),
      remarks: s('vod_remarks'),
      typeName: s('type_name'),
      year: s('vod_year'),
      area: s('vod_area'),
      actor: s('vod_actor'),
      content: _stripHtml(s('vod_content')),
      lines: _parseLines(s('vod_play_from'), s('vod_play_url')),
    );
  }

  /// vod_play_from: "线路A$$$线路B"
  /// vod_play_url:  "第1集$url#第2集$url$$$第1集$url..."
  static List<PlayLine> _parseLines(String from, String playUrl) {
    if (playUrl.isEmpty) return [];
    final names = from.split(r'$$$');
    final groups = playUrl.split(r'$$$');
    final lines = <PlayLine>[];
    for (var i = 0; i < groups.length; i++) {
      final episodes = <Episode>[];
      for (final part in groups[i].split('#')) {
        final p = part.trim();
        if (p.isEmpty) continue;
        final seg = p.split(r'$');
        final name = seg.length >= 2 ? seg[0].trim() : '第${episodes.length + 1}集';
        final url = (seg.length >= 2 ? seg[1] : seg[0]).trim();
        if (url.isEmpty) continue;
        episodes.add(Episode(name.isEmpty ? '第${episodes.length + 1}集' : name, url));
      }
      if (episodes.isEmpty) continue;
      final name = i < names.length && names[i].trim().isNotEmpty ? names[i].trim() : '线路${i + 1}';
      lines.add(PlayLine(name, episodes));
    }
    return lines;
  }

  static String _stripHtml(String s) {
    if (s.isEmpty || !s.contains('<')) return s;
    return (html_parser.parse(s).body?.text ?? s).trim();
  }
}
