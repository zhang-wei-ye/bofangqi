import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_store.dart';
import 'hls.dart';
import 'models.dart';
import 'net.dart';

enum DownloadStatus { waiting, running, paused, failed, done }

/// 缓存的一集。m3u8 会把分片全部下到本地再改写出一份本地播放列表，mp4 等直接下整个文件（支持断点续传）。
class DownloadTask {
  final String id;
  final String vodName;
  final String vodId;
  final String sourceApi;
  final String sourceName;
  final String pic;
  final String lineName;
  final int episodeIndex;
  final String episodeName;
  final String url;
  final int createdAt;

  DownloadStatus status;

  /// 进度：m3u8 按分片数算，其他按字节算。
  int doneUnits;
  int totalUnits;
  int bytes;

  /// 下载完成后，任务目录里用来播放的文件名。
  String file;
  String? error;

  /// 下载速度（字节/秒），只在下载中有意义，不存盘。
  int speed = 0;

  DownloadTask({
    required this.id,
    required this.vodName,
    required this.vodId,
    required this.sourceApi,
    required this.sourceName,
    required this.pic,
    required this.lineName,
    required this.episodeIndex,
    required this.episodeName,
    required this.url,
    required this.createdAt,
    this.status = DownloadStatus.waiting,
    this.doneUnits = 0,
    this.totalUnits = 0,
    this.bytes = 0,
    this.file = '',
    this.error,
  });

  bool get isHls => RegExp(r'\.m3u8(\?|#|$)', caseSensitive: false).hasMatch(url);

  double get progress => totalUnits > 0 ? (doneUnits / totalUnits).clamp(0.0, 1.0) : 0;

  String get groupKey => '${HistoryStore.keyOf(vodName)}|$sourceApi|$lineName';

  Vod get vod => Vod(source: VideoSource(name: sourceName, api: sourceApi), id: vodId, name: vodName, pic: pic);

  Map<String, dynamic> toJson() => {
    'id': id,
    'vodName': vodName,
    'vodId': vodId,
    'sourceApi': sourceApi,
    'sourceName': sourceName,
    'pic': pic,
    'lineName': lineName,
    'episodeIndex': episodeIndex,
    'episodeName': episodeName,
    'url': url,
    'createdAt': createdAt,
    'status': status.name,
    'doneUnits': doneUnits,
    'totalUnits': totalUnits,
    'bytes': bytes,
    'file': file,
    'error': error,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return DownloadTask(
      id: '${j['id']}',
      vodName: '${j['vodName'] ?? ''}',
      vodId: '${j['vodId'] ?? ''}',
      sourceApi: '${j['sourceApi'] ?? ''}',
      sourceName: '${j['sourceName'] ?? ''}',
      pic: '${j['pic'] ?? ''}',
      lineName: '${j['lineName'] ?? ''}',
      episodeIndex: n('episodeIndex'),
      episodeName: '${j['episodeName'] ?? ''}',
      url: '${j['url'] ?? ''}',
      createdAt: n('createdAt'),
      status: DownloadStatus.values.asNameMap()[j['status']] ?? DownloadStatus.waiting,
      doneUnits: n('doneUnits'),
      totalUnits: n('totalUnits'),
      bytes: n('bytes'),
      file: '${j['file'] ?? ''}',
      error: j['error'] as String?,
    );
  }
}

/// 已下载完的同一部片、同一条线路的那几集，离线时当成一条线路来播。
class OfflineGroup {
  final List<DownloadTask> tasks;
  OfflineGroup(this.tasks);

  DownloadTask get first => tasks.first;
  String get key => first.groupKey;
  String get vodName => first.vodName;
  String get lineName => first.lineName;
  String get sourceName => first.sourceName;
  int get bytes => tasks.fold(0, (s, t) => s + t.bytes);
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _Job {
  final DownloadTask task;
  bool cancelled = false;
  int lastBytes;
  _Job(this.task) : lastBytes = task.bytes;

  void check() {
    if (cancelled) throw const _Cancelled();
  }
}

/// 缓存队列：同时下 2 集，每集 4 个分片并发。任务列表存在 SharedPreferences，文件放在应用私有目录。
/// App 被杀掉后下载会停，下次打开自动接着下（已下好的分片不会重下）。
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final instance = DownloadManager._();

  static const _key = 'downloads_v1';
  static const _maxTasks = 2;
  static const _workers = 4;
  static const _idle = Duration(seconds: 30);

  final List<DownloadTask> _tasks = [];
  final Map<String, _Job> _jobs = {};
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  late final Future<void> _ready = _load();
  late Directory _root;
  Timer? _ticker;
  bool loaded = false;

  Future<void> init() => _ready;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// 还没下完的（含等待、暂停、失败），先加的在前。
  List<DownloadTask> get unfinished => _tasks.where((t) => t.status != DownloadStatus.done).toList();

  /// 已下完的按「片 + 源 + 线路」分组，最近下载的组在前，组内按集数排。
  List<OfflineGroup> get groups {
    final map = <String, List<DownloadTask>>{};
    for (final t in _tasks.reversed) {
      if (t.status == DownloadStatus.done) map.putIfAbsent(t.groupKey, () => []).add(t);
    }
    return [for (final l in map.values) OfflineGroup(l..sort((a, b) => a.episodeIndex - b.episodeIndex))];
  }

  OfflineGroup? group(String key) => groups.where((g) => g.key == key).firstOrNull;

  /// 这部片在这条线路上的某一集是否已经加入过缓存。
  DownloadTask? find(Vod vod, PlayLine line, Episode ep) {
    final k = HistoryStore.keyOf(vod.name);
    return _tasks
        .where((t) =>
            HistoryStore.keyOf(t.vodName) == k &&
            t.sourceApi == vod.source.api &&
            t.lineName == line.name &&
            t.episodeName == ep.name)
        .firstOrNull;
  }

  Directory _dirOf(DownloadTask t) => Directory('${_root.path}${Platform.pathSeparator}${t.id}');

  /// 封面也存一份，没网时列表里照样有图。
  String coverOf(DownloadTask t) => '${_dirOf(t).path}${Platform.pathSeparator}cover';

  Future<void> _load() async {
    final base = await getApplicationSupportDirectory();
    _root = Directory('${base.path}${Platform.pathSeparator}downloads');
    await _root.create(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    try {
      final list = jsonDecode(prefs.getString(_key) ?? '[]') as List;
      for (final e in list) {
        if (e is! Map) continue;
        final t = DownloadTask.fromJson(e.cast<String, dynamic>());
        // 上次退出时还在下的，重新排队。
        if (t.status == DownloadStatus.running) t.status = DownloadStatus.waiting;
        _tasks.add(t);
      }
    } catch (_) {}
    loaded = true;
    notifyListeners();
    _pump();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_tasks.map((t) => t.toJson()).toList()));
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  /// 把 [line] 里第 [indexes] 集加入缓存，已经加过的跳过，返回新加的集数。
  Future<int> add(Vod vod, PlayLine line, Iterable<int> indexes) async {
    await _ready;
    var added = 0;
    for (final i in indexes) {
      final ep = line.episodes[i];
      if (!ep.isDirect || find(vod, line, ep) != null) continue;
      final now = DateTime.now().microsecondsSinceEpoch;
      _tasks.add(DownloadTask(
        id: '$now$i',
        vodName: vod.name,
        vodId: vod.id,
        sourceApi: vod.source.api,
        sourceName: vod.source.name,
        pic: vod.pic,
        lineName: line.name,
        episodeIndex: i,
        episodeName: ep.name,
        url: ep.url,
        createdAt: now,
      ));
      added++;
    }
    if (added > 0) {
      _changed();
      _pump();
    }
    return added;
  }

  void pause(DownloadTask t) {
    if (t.status != DownloadStatus.running && t.status != DownloadStatus.waiting) return;
    _jobs[t.id]?.cancelled = true;
    t.status = DownloadStatus.paused;
    t.speed = 0;
    _changed();
    _pump();
  }

  /// 继续或重试。
  void resume(DownloadTask t) {
    if (t.status != DownloadStatus.paused && t.status != DownloadStatus.failed) return;
    t.status = DownloadStatus.waiting;
    t.error = null;
    _changed();
    _pump();
  }

  void pauseAll() {
    for (final t in _tasks) {
      if (t.status == DownloadStatus.running || t.status == DownloadStatus.waiting) {
        _jobs[t.id]?.cancelled = true;
        t.status = DownloadStatus.paused;
        t.speed = 0;
      }
    }
    _changed();
  }

  void resumeAll() {
    for (final t in _tasks) {
      if (t.status == DownloadStatus.paused || t.status == DownloadStatus.failed) {
        t.status = DownloadStatus.waiting;
        t.error = null;
      }
    }
    _changed();
    _pump();
  }

  /// 删除任务和已下载的文件。正在下的等它停下来再删目录。
  void remove(Iterable<DownloadTask> list) {
    for (final t in list.toList()) {
      _tasks.remove(t);
      final job = _jobs[t.id];
      if (job != null) {
        job.cancelled = true;
      } else {
        _deleteDir(t);
      }
    }
    _changed();
    _pump();
  }

  void _deleteDir(DownloadTask t) {
    _dirOf(t).delete(recursive: true).catchError((_) => Directory(''));
  }

  /// 离线播放用的地址：交给本机的小服务器出文件，m3u8 和 mp4 拖动进度都正常。
  Future<String> playUrl(DownloadTask t) async {
    final port = await _LocalServer.instance.port(_root);
    return 'http://127.0.0.1:$port/${t.id}/${Uri.encodeComponent(t.file)}';
  }

  /// 把一组已下载的集数拼成一条可以直接交给播放页的线路。
  Future<({Vod vod, PlayLine line})> offline(OfflineGroup g) async {
    final eps = [for (final t in g.tasks) Episode(t.episodeName, await playUrl(t))];
    return (vod: g.first.vod, line: PlayLine(g.lineName, eps));
  }

  void _pump() {
    if (!loaded) return;
    for (final t in _tasks) {
      if (_jobs.length >= _maxTasks) break;
      if (t.status == DownloadStatus.waiting && !_jobs.containsKey(t.id)) _start(t);
    }
  }

  /// 每秒刷新一次界面和速度，下载过程中不用每收到一块数据就通知。
  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      for (final j in _jobs.values) {
        j.task.speed = (j.task.bytes - j.lastBytes).clamp(0, 1 << 40);
        j.lastBytes = j.task.bytes;
      }
      notifyListeners();
      if (_jobs.isEmpty) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  Future<void> _start(DownloadTask t) async {
    final job = _Job(t);
    _jobs[t.id] = job;
    t.status = DownloadStatus.running;
    t.error = null;
    _changed();
    _ensureTicker();
    try {
      final dir = _dirOf(t);
      await dir.create(recursive: true);
      await _fetchCover(t);
      if (!t.url.startsWith('http') || !Episode(t.episodeName, t.url).isDirect) {
        throw const FormatException('不是直链，没法缓存');
      }
      t.isHls ? await _runHls(job, dir) : await _runFile(job, dir);
      t.status = DownloadStatus.done;
    } on _Cancelled {
      // 暂停或删除，状态已经由调用方改好了。
    } catch (e) {
      if (t.status == DownloadStatus.running) {
        t.status = DownloadStatus.failed;
        t.error = _describe(e);
      }
    } finally {
      _jobs.remove(t.id);
      t.speed = 0;
      if (!_tasks.contains(t)) _deleteDir(t);
      _changed();
      _pump();
    }
  }

  static String _describe(Object e) => switch (e) {
    HttpException(:final message) => message,
    SocketException() => '网络连接失败',
    TimeoutException() => '网络超时',
    FileSystemException(:final message) => '写入失败：$message',
    FormatException(:final message) => message,
    _ => '$e',
  };

  Future<void> _fetchCover(DownloadTask t) async {
    final f = File(coverOf(t));
    if (!t.pic.startsWith('http') || await f.exists()) return;
    try {
      final res = await _get(Uri.parse(t.pic));
      if (res.statusCode != 200) return;
      final bytes = await res.timeout(_idle).fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d));
      await f.writeAsBytes(bytes.takeBytes());
    } catch (_) {}
  }

  Future<HttpClientResponse> _get(Uri uri, {Map<String, String>? headers}) async {
    final req = await _client.getUrl(uri).timeout(const Duration(seconds: 20));
    req.headers.set(HttpHeaders.userAgentHeader, kUserAgent);
    headers?.forEach(req.headers.set);
    return req.close().timeout(const Duration(seconds: 20));
  }

  Future<(String, Uri)> _getText(Uri uri) async {
    final res = await _get(uri);
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('播放列表请求失败（HTTP ${res.statusCode}）');
    }
    final b = await res.timeout(_idle).fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d));
    final finalUri = res.redirects.isEmpty ? uri : uri.resolveUri(res.redirects.last.location);
    return (utf8.decode(b.takeBytes(), allowMalformed: true), finalUri);
  }

  /// m3u8：选最高清晰度，下载全部分片 / 密钥 / 初始化段，再写一份指向本地文件的 index.m3u8。
  Future<void> _runHls(_Job job, Directory dir) async {
    final t = job.task;
    var (text, base) = await _getText(Uri.parse(t.url));
    job.check();
    if (text.contains('#EXT-X-STREAM-INF')) {
      final variants = parseHlsVariants(text, base);
      if (variants.isEmpty) throw const FormatException('播放列表里没有可用的清晰度');
      (text, base) = await _getText(Uri.parse(variants.first.url));
      job.check();
    }
    if (!text.trimLeft().startsWith('#EXTM3U')) throw const FormatException('不是有效的 m3u8 播放列表');

    final resources = <(Uri, String)>[];
    final out = StringBuffer();
    final uriAttr = RegExp(r'URI="([^"]+)"');
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        final isKey = line.startsWith('#EXT-X-KEY');
        out.writeln(line.replaceAllMapped(uriAttr, (m) {
          final u = m.group(1)!;
          if (u.startsWith('data:') || u.startsWith('skd:')) return m.group(0)!;
          final uri = base.resolve(u);
          final name = 'r${resources.length}${isKey ? '.key' : _ext(uri, '.mp4')}';
          resources.add((uri, name));
          return 'URI="$name"';
        }));
      } else {
        final uri = base.resolve(line);
        final name = 's${resources.length}${_ext(uri, '.ts')}';
        resources.add((uri, name));
        out.writeln(name);
      }
    }
    if (resources.isEmpty) throw const FormatException('播放列表是空的');

    final pending = <int>[];
    t.totalUnits = resources.length;
    t.doneUnits = 0;
    t.bytes = 0;
    for (var i = 0; i < resources.length; i++) {
      final f = File('${dir.path}/${resources[i].$2}');
      if (await f.exists()) {
        t.doneUnits++;
        t.bytes += await f.length();
      } else {
        pending.add(i);
      }
    }
    job.lastBytes = t.bytes;

    var next = 0;
    Future<void> worker() async {
      while (next < pending.length) {
        final (uri, name) = resources[pending[next++]];
        try {
          await _fetchTo(job, uri, File('${dir.path}/$name'));
        } catch (e) {
          // 一个分片重试几次还下不来，整集算失败，让其他分片也停下。
          job.cancelled = true;
          rethrow;
        }
        t.doneUnits++;
      }
    }

    await Future.wait(List.generate(_workers, (_) => worker()));
    await File('${dir.path}/index.m3u8').writeAsString(out.toString());
    t.file = 'index.m3u8';
  }

  /// 分片的扩展名：常见的保留，其他（有的源把分片伪装成 .jpg/.png）一律当 .ts。
  static String _ext(Uri uri, String fallback) {
    final seg = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last.toLowerCase();
    final m = RegExp(r'\.(ts|m4s|mp4|m4a|aac|mp3|vtt|webvtt)$').firstMatch(seg);
    return m == null ? fallback : '.${m.group(1)}';
  }

  /// 下载一个小文件（分片等），先写 .tmp 再改名，失败重试 3 次。
  Future<void> _fetchTo(_Job job, Uri uri, File dest) async {
    for (var attempt = 1; ; attempt++) {
      job.check();
      final tmp = File('${dest.path}.tmp');
      var got = 0;
      try {
        final res = await _get(uri);
        if (res.statusCode != 200) {
          await res.drain<void>();
          throw HttpException('分片下载失败（HTTP ${res.statusCode}）');
        }
        final sink = tmp.openWrite();
        try {
          await for (final chunk in res.timeout(_idle)) {
            job.check();
            sink.add(chunk);
            got += chunk.length;
            job.task.bytes += chunk.length;
          }
        } finally {
          await sink.close();
        }
        await tmp.rename(dest.path);
        return;
      } on _Cancelled {
        job.task.bytes -= got;
        rethrow;
      } catch (_) {
        job.task.bytes -= got;
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  /// mp4 等单文件：写到 .part，暂停后用 Range 接着下。
  Future<void> _runFile(_Job job, Directory dir) async {
    final t = job.task;
    final ext = RegExp(r'\.(mp4|flv|mkv|mov)(\?|#|$)', caseSensitive: false).firstMatch(t.url)?.group(1)?.toLowerCase();
    final name = 'video.${ext ?? 'mp4'}';
    final part = File('${dir.path}/$name.part');
    for (var attempt = 1; ; attempt++) {
      job.check();
      try {
        var have = await part.exists() ? await part.length() : 0;
        final res = await _get(Uri.parse(t.url), headers: have > 0 ? {'Range': 'bytes=$have-'} : null);
        if (res.statusCode == 200) {
          have = 0;
        } else if (res.statusCode != 206) {
          await res.drain<void>();
          throw HttpException('下载失败（HTTP ${res.statusCode}）');
        }
        t.totalUnits = res.contentLength >= 0 ? have + res.contentLength : 0;
        t.doneUnits = have;
        t.bytes = have;
        job.lastBytes = have;
        final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
        try {
          await for (final chunk in res.timeout(_idle)) {
            job.check();
            sink.add(chunk);
            t.doneUnits += chunk.length;
            t.bytes += chunk.length;
          }
        } finally {
          await sink.close();
        }
        if (t.totalUnits > 0 && t.doneUnits < t.totalUnits) throw const HttpException('连接中断');
        t.totalUnits = t.doneUnits;
        await part.rename('${dir.path}/$name');
        t.file = name;
        return;
      } on _Cancelled {
        rethrow;
      } catch (_) {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }
}

/// 只监听 127.0.0.1 的文件服务，把缓存目录里的文件交给播放器（支持 Range，拖进度用）。
/// 不直接给播放器本地文件路径，是因为 iOS 的播放器不认本地的 m3u8。
class _LocalServer {
  _LocalServer._();
  static final instance = _LocalServer._();

  Future<HttpServer>? _server;
  late Directory _root;

  Future<int> port(Directory root) async {
    _root = root;
    _server ??= HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((s) {
      s.listen((req) => _handle(req).catchError((Object _) {}));
      return s;
    });
    return (await _server!).port;
  }

  Future<void> _handle(HttpRequest req) async {
    final resp = req.response;
    final segs = req.uri.pathSegments;
    final file = File('${_root.path}/${segs.join('/')}');
    if (segs.length != 2 || segs.any((s) => s == '..' || s.isEmpty) || !await file.exists()) {
      resp.statusCode = HttpStatus.notFound;
      await resp.close();
      return;
    }
    final len = await file.length();
    final name = segs.last.toLowerCase();
    final type = switch (name.substring(name.lastIndexOf('.') + 1)) {
      'm3u8' => 'application/vnd.apple.mpegurl',
      'ts' => 'video/mp2t',
      'mp4' || 'm4s' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'mov' => 'video/quicktime',
      'flv' => 'video/x-flv',
      'aac' => 'audio/aac',
      'm4a' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'vtt' || 'webvtt' => 'text/vtt',
      _ => 'application/octet-stream',
    };
    resp.headers.set(HttpHeaders.contentTypeHeader, type);
    resp.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    var start = 0;
    var end = len - 1;
    final range = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (range != null && len > 0) {
      final a = int.tryParse(range.group(1)!);
      final b = int.tryParse(range.group(2)!);
      if (a == null && b != null) {
        start = (len - b).clamp(0, len - 1);
      } else {
        start = a ?? 0;
        end = (b ?? end).clamp(0, len - 1);
      }
      if (start > end || start >= len) {
        resp.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        resp.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$len');
        await resp.close();
        return;
      }
      resp.statusCode = HttpStatus.partialContent;
      resp.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$len');
    }
    resp.headers.contentLength = len == 0 ? 0 : end - start + 1;
    if (req.method != 'HEAD' && len > 0) await resp.addStream(file.openRead(start, end + 1));
    await resp.close();
  }
}

/// 字节数显示成 KB / MB / GB。
String formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
  if (n < 1024 * 1024 * 1024) return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
