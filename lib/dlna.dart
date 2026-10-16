import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// 局域网里一台能接收投屏的 DLNA 设备（电视、盒子等 MediaRenderer）。
class DlnaDevice {
  final String name;
  final String location;
  final Uri controlUrl;
  final String serviceType;
  const DlnaDevice({required this.name, required this.location, required this.controlUrl, required this.serviceType});
}

/// 安卓默认会丢弃组播包，搜索设备期间要拿着 MulticastLock。
const _multicast = MethodChannel('bofang/multicast');

/// 一次搜索的过程记录，搜不到设备时显示出来方便排查。
class DlnaSearchLog {
  final List<String> interfaces = [];
  int responses = 0;
  final List<String> responders = [];
  int rejected = 0;
  final List<String> errors = [];

  @override
  String toString() => [
    '本机网卡：${interfaces.isEmpty ? '无' : interfaces.join('，')}',
    '收到回应：$responses 条${responders.isEmpty ? '' : '（${responders.take(5).join('，')}）'}',
    if (rejected > 0) '其中 $rejected 台不支持视频投屏或描述读取失败',
    ...errors.take(3),
  ].join('\n');
}

const _ssdpAddr = '239.255.255.250';
const _searchTargets = [
  'urn:schemas-upnp-org:service:AVTransport:1',
  'urn:schemas-upnp-org:device:MediaRenderer:1',
  'ssdp:all',
];

/// 用 SSDP 搜索局域网里的投屏设备，找到一台推一台。
/// 安卓同时开着 WiFi 和移动数据时，绑在 0.0.0.0 上发的组播可能走错网卡，
/// 所以每个局域网网卡各绑一个 socket 发；另外监听 1900 端口收设备主动发的 NOTIFY。
Stream<DlnaDevice> discoverDlna({Duration timeout = const Duration(seconds: 8), DlnaSearchLog? log}) {
  final out = StreamController<DlnaDevice>();
  final sockets = <RawDatagramSocket>[];
  final timers = <Timer>[];
  final seen = <String>{};
  final logs = log ?? DlnaSearchLog();
  var closed = false;

  Future<void> close() async {
    if (closed) return;
    closed = true;
    for (final t in timers) {
      t.cancel();
    }
    for (final s in sockets) {
      s.close();
    }
    try {
      await _multicast.invokeMethod('release');
    } catch (_) {}
    if (!out.isClosed) await out.close();
  }

  void onPacket(RawDatagramSocket s) {
    final dg = s.receive();
    if (dg == null) return;
    final text = utf8.decode(dg.data, allowMalformed: true);
    if (text.startsWith('M-SEARCH')) return; // 别人（包括自己）发的搜索请求
    final location = _header(text, 'location');
    if (location == null) return;
    logs.responses++;
    if (!seen.add(location)) return;
    logs.responders.add(dg.address.address);
    _describe(location).then((d) {
      if (d == null) {
        logs.rejected++;
      } else if (!out.isClosed) {
        out.add(d);
      }
    });
  }

  void search(RawDatagramSocket s) {
    for (final st in _searchTargets) {
      final msg =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: $_ssdpAddr:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 2\r\n'
          'ST: $st\r\n\r\n';
      try {
        s.send(utf8.encode(msg), InternetAddress(_ssdpAddr), 1900);
      } catch (e) {
        logs.errors.add('发送失败：$e');
      }
    }
  }

  Future<void> start() async {
    try {
      await _multicast.invokeMethod('acquire');
    } catch (_) {}

    final addrs = <InternetAddress>[];
    final ifaces = <NetworkInterface>[];
    try {
      for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in iface.addresses) {
          if (a.isLoopback || a.isLinkLocal) continue;
          addrs.add(a);
          ifaces.add(iface);
          logs.interfaces.add('${iface.name} ${a.address}');
        }
      }
    } catch (e) {
      logs.errors.add('读取网卡失败：$e');
    }

    // 每个网卡单独发搜索；最后再补一个 0.0.0.0 的，防止上面一个都没绑上。
    for (final a in [...addrs, InternetAddress.anyIPv4]) {
      try {
        final s = await RawDatagramSocket.bind(a, 0);
        s.multicastHops = 4;
        s.listen((e) {
          if (e == RawSocketEvent.read) onPacket(s);
        });
        sockets.add(s);
      } catch (e) {
        logs.errors.add('绑定 ${a.address} 失败：$e');
      }
    }

    // 监听设备主动广播的 NOTIFY，有些电视不回应搜索但会定时广播自己。
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 1900, reuseAddress: true);
      for (final iface in {...ifaces}) {
        try {
          s.joinMulticast(InternetAddress(_ssdpAddr), iface);
        } catch (_) {}
      }
      if (ifaces.isEmpty) s.joinMulticast(InternetAddress(_ssdpAddr));
      s.listen((e) {
        if (e == RawSocketEvent.read) onPacket(s);
      });
      sockets.add(s);
    } catch (e) {
      logs.errors.add('监听 1900 端口失败：$e');
    }

    if (closed) return close();
    // UDP 会丢包，隔一会儿再搜几遍。
    for (final delay in const [0, 1, 3]) {
      timers.add(
        Timer(Duration(seconds: delay), () {
          for (final s in sockets) {
            if (s.port != 1900) search(s);
          }
        }),
      );
    }
    timers.add(Timer(timeout, close));
  }

  out.onListen = start;
  out.onCancel = close;
  return out.stream;
}

String? _header(String response, String name) {
  for (final line in response.split(RegExp(r'\r?\n'))) {
    final i = line.indexOf(':');
    if (i > 0 && line.substring(0, i).trim().toLowerCase() == name) return line.substring(i + 1).trim();
  }
  return null;
}

/// 读设备描述 XML，找出名字和 AVTransport 服务的控制地址；不支持的设备返回 null。
Future<DlnaDevice?> _describe(String location) async {
  try {
    final base = Uri.parse(location);
    final res = await http.get(base).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final xml = utf8.decode(res.bodyBytes, allowMalformed: true);
    String? tag(String src, String name) =>
        RegExp('<(?:\\w+:)?$name[^>]*>([\\s\\S]*?)</(?:\\w+:)?$name>').firstMatch(src)?.group(1)?.trim();
    for (final m in RegExp(r'<(?:\w+:)?service>([\s\S]*?)</(?:\w+:)?service>').allMatches(xml)) {
      final service = m.group(1)!;
      final type = tag(service, 'serviceType') ?? '';
      if (!type.contains(':service:AVTransport:')) continue;
      final control = tag(service, 'controlURL');
      if (control == null || control.isEmpty) continue;
      final urlBase = tag(xml, 'URLBase');
      final root = urlBase != null && urlBase.isNotEmpty ? Uri.parse(urlBase) : base;
      return DlnaDevice(
        name: _unescape(tag(xml, 'friendlyName') ?? base.host),
        location: location,
        controlUrl: root.resolve(control),
        serviceType: type,
      );
    }
  } catch (_) {}
  return null;
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// 对一台设备发 AVTransport 控制命令。
class DlnaController {
  final DlnaDevice device;
  const DlnaController(this.device);

  /// 让设备播放 [url]，[startAt] 不为空时播起来后尝试跳到这个位置。
  Future<void> cast(String url, {required String title, Duration? startAt}) async {
    final mime = url.toLowerCase().contains('.m3u8') ? 'application/vnd.apple.mpegurl' : 'video/mp4';
    // 有些电视不带元数据就不肯播。
    final meta =
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1"><dc:title>${_escape(title)}</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="http-get:*:$mime:*">${_escape(url)}</res></item></DIDL-Lite>';
    try {
      await _call('Stop');
    } catch (_) {}
    await _call(
      'SetAVTransportURI',
      '<CurrentURI>${_escape(url)}</CurrentURI>'
          '<CurrentURIMetaData>${_escape(meta)}</CurrentURIMetaData>',
    );
    await _startPlaying();
    if (startAt != null && startAt > const Duration(seconds: 5)) {
      // 电视加载完才能跳进度，隔几秒多试几次，失败也不影响播放。
      for (var i = 0; i < 3; i++) {
        await Future.delayed(const Duration(seconds: 3));
        try {
          await seek(startAt);
          break;
        } catch (_) {}
      }
    }
  }

  /// 设完地址后电视是异步创建播放器的，马上发 Play 常会报 “No player created”；
  /// 很多电视设完地址自己就开播了。所以隔一秒看一次状态，没播起来再补发 Play，最多等 8 秒。
  Future<void> _startPlaying() async {
    Object? lastError;
    for (var i = 0; i < 8; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final state = await transportState();
      if (state == 'PLAYING' || state == 'TRANSITIONING') return;
      try {
        await play();
        return;
      } catch (e) {
        lastError = e;
      }
    }
    final state = await transportState();
    if (state == 'PLAYING' || state == 'TRANSITIONING') return;
    throw lastError ?? const HttpException('电视没有开始播放');
  }

  /// 电视当前的播放状态（PLAYING / PAUSED_PLAYBACK / STOPPED / TRANSITIONING …），查不到返回 null。
  Future<String?> transportState() async {
    try {
      final body = await _call('GetTransportInfo');
      return RegExp(r'<CurrentTransportState>([^<]*)</CurrentTransportState>').firstMatch(body)?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> play() => _call('Play', '<Speed>1</Speed>');
  Future<void> pause() => _call('Pause');
  Future<void> stop() => _call('Stop');

  Future<void> seek(Duration to) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = '${two(to.inHours)}:${two(to.inMinutes.remainder(60))}:${two(to.inSeconds.remainder(60))}';
    return _call('Seek', '<Unit>REL_TIME</Unit><Target>$t</Target>');
  }

  Future<String> _call(String action, [String args = '']) async {
    final type = device.serviceType;
    final body =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
        '<u:$action xmlns:u="$type"><InstanceID>0</InstanceID>$args</u:$action>'
        '</s:Body></s:Envelope>';
    final res = await http
        .post(
          device.controlUrl,
          headers: {'Content-Type': 'text/xml; charset="utf-8"', 'SOAPACTION': '"$type#$action"'},
          body: utf8.encode(body),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      final code = RegExp(r'<errorDescription>([\s\S]*?)</errorDescription>').firstMatch(res.body)?.group(1);
      throw HttpException('$action 失败（${res.statusCode}${code == null ? '' : '，$code'}）');
    }
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }
}
