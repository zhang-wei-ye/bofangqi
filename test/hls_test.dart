import 'package:bo_fang_qi/hls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('单档主播放列表，绝对路径', () {
    final v = parseHlsVariants(
      '#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=955000,RESOLUTION=1280x720\n/20240516/zN7aNzzK/955kb/hls/index.m3u8\n',
      Uri.parse('https://vod2.maowushi.com/20240516/zN7aNzzK/index.m3u8'),
    );
    expect(v.single.label, '720P');
    expect(v.single.url, 'https://vod2.maowushi.com/20240516/zN7aNzzK/955kb/hls/index.m3u8');
  });

  test('多档按清晰度从高到低，相对路径', () {
    final v = parseHlsVariants(
      '#EXTM3U\r\n#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=854x480\r\n480/index.m3u8\r\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1920x1080\r\n1080/index.m3u8\r\n',
      Uri.parse('https://a.com/x/index.m3u8'),
    );
    expect(v.map((e) => e.label), ['1080P', '480P']);
    expect(v.first.url, 'https://a.com/x/1080/index.m3u8');
  });

  test('普通媒体播放列表不算', () {
    expect(parseHlsVariants('#EXTM3U\n#EXTINF:10.4,\na.ts\n', Uri.parse('https://a.com/i.m3u8')), isEmpty);
  });
}
