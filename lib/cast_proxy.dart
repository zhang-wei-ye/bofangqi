import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'net.dart';

/// 投屏中转：电视不直接去源站拉视频，而是找手机要，手机带上 App 的证书配置和 UA 去源站拉了再转给电视。
/// 解决电视上的 -1004（拉流失败）：很多源用的 Let's Encrypt 新根证书电视不认，或者源站拦了电视的 UA。
/// m3u8 里的子列表、分片、密钥地址都会改写成走中转。
class CastProxy {
  CastProxy._();
  static final instance = CastProxy._();

  HttpServer? _server;
  String _host = '';
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..autoUncompress = false;

  /// 返回电视能访问的中转地址。[tvHost] 用来挑和电视在同一网段的本机 IP。
  Future<String> wrap(String url, {required String tvHost}) async {
    _server ??= await _start();
    _host = await _localIpFor(tvHost);
    return _proxied(Uri.parse(url));
  }

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen((req) => _handle(req).catchError((Object _) {}));
    return server;
  }

  String _proxied(Uri target) {
    final id = base64Url.encode(utf8.encode(target.toString())).replaceAll('=', '');
    final segs = target.pathSegments.where((s) => s.isNotEmpty);
    // 末尾保留原文件名，有些电视按扩展名判断格式。
    final name = Uri.encodeComponent(segs.isEmpty ? 'index' : segs.last);
    return 'http://$_host:${_server!.port}/p/$id/$name';
  }

  Future<void> _handle(HttpRequest req) async {
    final resp = req.response;
    final segs = req.uri.pathSegments;
    Uri target;
    try {
      if (segs.length < 2 || segs[0] != 'p') throw const FormatException();
      target = Uri.parse(utf8.decode(base64Url.decode(base64Url.normalize(segs[1]))));
    } catch (_) {
      resp.statusCode = HttpStatus.notFound;
      await resp.close();
      return;
    }

    HttpClientResponse up;
    try {
      final head = req.method == 'HEAD';
      final r = await _client.openUrl(head ? 'HEAD' : 'GET', target);
      r.headers.set(HttpHeaders.userAgentHeader, kUserAgent);
      r.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) r.headers.set(HttpHeaders.rangeHeader, range);
      up = await r.close();
    } catch (_) {
      resp.statusCode = HttpStatus.badGateway;
      await resp.close();
      return;
    }

    final finalUri = up.redirects.isEmpty ? target : target.resolveUri(up.redirects.last.location);
    final type = up.headers.contentType?.mimeType.toLowerCase() ?? '';
    final looksPlaylist = finalUri.path.toLowerCase().endsWith('.m3u8') || type.contains('mpegurl');

    if (looksPlaylist && req.method != 'HEAD' && up.statusCode == 200) {
      final bytes = await up.fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d)).then((b) => b.takeBytes());
      final raw = up.headers.value(HttpHeaders.contentEncodingHeader) == 'gzip' ? gzip.decode(bytes) : bytes;
      final text = utf8.decode(raw, allowMalformed: true);
      if (text.trimLeft().startsWith('#EXTM3U')) {
        final out = utf8.encode(_rewrite(text, finalUri));
        resp.statusCode = 200;
        resp.headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl');
        resp.headers.contentLength = out.length;
        resp.add(out);
        await resp.close();
        return;
      }
      _copyHeaders(up, resp, skipLength: true);
      resp.statusCode = up.statusCode;
      resp.headers.contentLength = raw.length;
      resp.add(raw);
      await resp.close();
      return;
    }

    resp.statusCode = up.statusCode;
    _copyHeaders(up, resp);
    await resp.addStream(up);
    await resp.close();
  }

  static void _copyHeaders(HttpClientResponse up, HttpResponse resp, {bool skipLength = false}) {
    for (final h in const [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.contentEncodingHeader,
    ]) {
      if (skipLength && (h == HttpHeaders.contentLengthHeader || h == HttpHeaders.contentEncodingHeader)) continue;
      final v = up.headers.value(h);
      if (v != null) resp.headers.set(h, v);
    }
  }

  /// 把 m3u8 里所有地址（普通行和 URI="..." 属性）换成中转地址。
  String _rewrite(String text, Uri base) {
    final uriAttr = RegExp(r'URI="([^"]+)"');
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) {
          final t = line.trim();
          if (t.isEmpty) return line;
          if (t.startsWith('#')) {
            return line.replaceAllMapped(uriAttr, (m) => 'URI="${_proxied(base.resolve(m.group(1)!))}"');
          }
          return _proxied(base.resolve(t));
        })
        .join('\n');
  }

  /// 挑一个和电视同网段的本机 IPv4；找不到就用第一个局域网地址。
  static Future<String> _localIpFor(String tvHost) async {
    final addrs = <String>[];
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in iface.addresses) {
        if (!a.isLoopback && !a.isLinkLocal) addrs.add(a.address);
      }
    }
    final tv = tvHost.split('.');
    int common(String ip) {
      final p = ip.split('.');
      var n = 0;
      while (n < 4 && n < p.length && n < tv.length && p[n] == tv[n]) {
        n++;
      }
      return n;
    }

    addrs.sort((a, b) => common(b) - common(a));
    if (addrs.isEmpty) throw const SocketException('没有找到本机局域网地址');
    return addrs.first;
  }
}
