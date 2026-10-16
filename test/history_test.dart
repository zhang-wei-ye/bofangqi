import 'package:bo_fang_qi/history_store.dart';
import 'package:bo_fang_qi/models.dart';
import 'package:flutter_test/flutter_test.dart';

WatchRecord rec({required int index, required String ep, required int pos, required int dur}) => WatchRecord(
  name: '测试剧',
  sourceApi: 'a',
  sourceName: 'A',
  lineName: 'm3u8',
  episodeIndex: index,
  episodeName: ep,
  positionMs: pos,
  durationMs: dur,
  updatedAt: 0,
);

void main() {
  final line = PlayLine('m3u8', [for (var i = 1; i <= 3; i++) Episode('第$i集', 'https://a.com/$i.m3u8')]);

  test('没看完从断点续播', () {
    final t = rec(index: 1, ep: '第2集', pos: 60000, dur: 2400000).resumeIn(line)!;
    expect(t.index, 1);
    expect(t.startAt, const Duration(minutes: 1));
  });

  test('看完了播下一集', () {
    final t = rec(index: 1, ep: '第2集', pos: 2395000, dur: 2400000).resumeIn(line)!;
    expect(t.index, 2);
    expect(t.startAt, isNull);
  });

  test('最后一集看完了从头再播这一集', () {
    final t = rec(index: 2, ep: '第3集', pos: 2395000, dur: 2400000).resumeIn(line)!;
    expect(t.index, 2);
    expect(t.startAt, isNull);
  });

  test('换了源时按集名找', () {
    expect(rec(index: 0, ep: '第3集', pos: 1000, dur: 0).episodeIn(line), 2);
    expect(rec(index: 5, ep: '番外', pos: 1000, dur: 0).episodeIn(line), isNull);
  });
}
