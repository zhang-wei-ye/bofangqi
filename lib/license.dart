import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 授权签名工具（D:\git-project\jia_mi）生成的公钥。换密钥对时只改这里。
const String _publicKey = 'jvkFphPmgwUvoViHlTcJdhwYg+N7BeMB0NreF/WRa6E=';

// 以下格式必须和签名工具 jia_mi/lib/license_core.dart 保持一致：
// 激活码 = base64url(payload[9] || 签名[64])，payload = 版本(1) + 签发时间(4) + 到期时间(4，0 为永久)，
// 被签名的消息 = signDomain + payload + 规范化后的指纹。
const int _licenseVersion = 1;
const String _signDomain = 'BOFANG-LICENSE|';
const int _payloadLength = 9;
const int _signatureLength = 64;

/// 指纹规范化：去掉非字母数字字符并转大写，用户复制时多了空格、横杠也能认。
String normalizeFingerprint(String raw) => raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

enum LicenseStatus { missing, invalid, expired, valid }

class LicenseState {
  final LicenseStatus status;
  final DateTime? issuedAt;

  /// null 表示永久授权（status 为 valid / expired 时才有意义）。
  final DateTime? expiresAt;

  const LicenseState(this.status, {this.issuedAt, this.expiresAt});

  bool get ok => status == LicenseStatus.valid;
}

/// 本机指纹与激活状态。每次启动都用内置公钥重新校验保存的激活码，
/// 不单独存「已激活」标记，改本地数据绕不过去。
class LicenseStore {
  static const _codeKey = 'license_code_v1';
  static const _fallbackIdKey = 'license_device_id_v1';

  /// 见过的最晚时间，用来防止把系统时间往回调来续命。
  static const _seenAtKey = 'license_seen_at_v1';

  static const _channel = MethodChannel('bofang/device');

  static String? _fingerprint;

  /// 本机指纹，形如 1A2B-3C4D-5E6F-7A8B。
  /// 安卓取 ANDROID_ID（同一签名的 App 卸载重装不变，恢复出厂后会变），取不到时用本机随机生成的 ID。
  static Future<String> fingerprint() async {
    if (_fingerprint != null) return _fingerprint!;
    var id = '';
    if (Platform.isAndroid) {
      try {
        id = await _channel.invokeMethod<String>('androidId') ?? '';
      } on PlatformException catch (_) {}
    }
    if (id.isEmpty) id = await _fallbackId();

    final hash = await Sha256().hash(utf8.encode('bofang-device|$id'));
    final hex = hash.bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    return _fingerprint = [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)].join('-');
  }

  static Future<String> _fallbackId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_fallbackIdKey);
    if (id == null || id.isEmpty) {
      final rnd = Random.secure();
      id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_fallbackIdKey, id);
    }
    return id;
  }

  /// 启动时检查本机保存的激活码。
  static Future<LicenseState> check() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    if (code == null || code.isEmpty) return const LicenseState(LicenseStatus.missing);
    return _evaluate(code, prefs);
  }

  /// 输入激活码激活，有效才保存。
  static Future<LicenseState> activate(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final state = await _evaluate(code.trim(), prefs);
    if (state.ok) await prefs.setString(_codeKey, code.trim());
    return state;
  }

  static Future<LicenseState> _evaluate(String code, SharedPreferences prefs) async {
    final payload = await verify(code, await fingerprint());
    if (payload == null) return const LicenseState(LicenseStatus.invalid);
    final (issuedAt, expiresAt) = payload;

    final now = DateTime.now();
    final seenAt = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_seenAtKey) ?? 0);
    final effectiveNow = now.isAfter(seenAt) ? now : seenAt;
    if (now.isAfter(seenAt)) await prefs.setInt(_seenAtKey, now.millisecondsSinceEpoch);

    final expired = expiresAt != null && !effectiveNow.isBefore(expiresAt);
    return LicenseState(
      expired ? LicenseStatus.expired : LicenseStatus.valid,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  /// 校验签名（公开以便测试），通过时返回（签发时间，到期时间），到期时间为 null 表示永久。
  static Future<(DateTime, DateTime?)?> verify(String code, String fingerprint) async {
    final fp = normalizeFingerprint(fingerprint);
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(code.replaceAll(RegExp(r'\s'), '')));
    } on FormatException {
      return null;
    }
    if (bytes.length != _payloadLength + _signatureLength) return null;

    final payloadBytes = Uint8List.sublistView(bytes, 0, _payloadLength);
    final payload = ByteData.sublistView(payloadBytes);
    if (payload.getUint8(0) != _licenseVersion) return null;

    final ok = await Ed25519().verify(
      [...utf8.encode(_signDomain), ...payloadBytes, ...utf8.encode(fp)],
      signature: Signature(
        Uint8List.sublistView(bytes, _payloadLength),
        publicKey: SimplePublicKey(base64Decode(_publicKey), type: KeyPairType.ed25519),
      ),
    );
    if (!ok) return null;

    final exp = payload.getUint32(5);
    return (
      DateTime.fromMillisecondsSinceEpoch(payload.getUint32(1) * 1000),
      exp == 0 ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
    );
  }
}
