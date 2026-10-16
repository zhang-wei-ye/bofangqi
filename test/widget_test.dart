import 'package:flutter_test/flutter_test.dart';

import 'package:bo_fang_qi/models.dart';

void main() {
  test('解析苹果 CMS 播放列表', () {
    const source = VideoSource(name: 't', api: 'https://example.com/api.php/provide/vod/');
    final v = Vod.fromJson({
      'vod_id': 12,
      'vod_name': '测试剧',
      'vod_content': '<p>简介</p>',
      'vod_play_from': r'abc$$$abcm3u8',
      'vod_play_url': r'第1集$https://a.com/share/1#第2集$https://a.com/share/2'
          r'$$$第1集$https://b.com/1/index.m3u8#第2集$https://b.com/2/index.m3u8',
    }, source);
    expect(v.id, '12');
    expect(v.content, '简介');
    expect(v.lines.length, 2);
    expect(v.lines[1].episodes[1].url, 'https://b.com/2/index.m3u8');
    expect(v.playableLines.map((l) => l.name), ['abcm3u8']);
  });
}
