import 'package:bo_fang_qi/license.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 用签名工具 jia_mi 给指纹 0000-0000-0000-0000 签发的永久激活码。
  // 换了密钥对后这条测试会失败，需要用新私钥重新签一个替换。
  const code = 'AWrcirMAAAAAUge2sAk2IteHMsmbGVa_oHjRlxKNGNVtnh6uZzAYW8Z9e2LCRduVYox0Lh8CZAIXe-leaYzrV6Ct8QJR49hRAA';

  test('签名工具签发的激活码能通过校验', () async {
    final r = await LicenseStore.verify(code, '0000-0000-0000-0000');
    expect(r, isNotNull);
    expect(r!.$2, isNull); // 永久
  });

  test('指纹格式不同但内容相同也能通过', () async {
    expect(await LicenseStore.verify(code, ' 0000 0000-00000000 '), isNotNull);
  });

  test('换一台机器的指纹校验失败', () async {
    expect(await LicenseStore.verify(code, '0000-0000-0000-0001'), isNull);
  });

  test('激活码被改动或不完整时校验失败', () async {
    final tampered = code.replaceRange(20, 21, code[20] == 'A' ? 'B' : 'A');
    expect(await LicenseStore.verify(tampered, '0000-0000-0000-0000'), isNull);
    expect(await LicenseStore.verify(code.substring(0, 90), '0000-0000-0000-0000'), isNull);
    expect(await LicenseStore.verify('乱填的', '0000-0000-0000-0000'), isNull);
  });

  test('指纹规范化', () {
    expect(normalizeFingerprint('ab-12 cd'), 'AB12CD');
  });
}
