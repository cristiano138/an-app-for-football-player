import 'package:flutter_test/flutter_test.dart';

import 'package:football/services/app_update_service.dart';

void main() {
  group('hasNewVersion（版本比较用 versionCode 整数）', () {
    test('远端大于本地 → 有新版', () {
      expect(hasNewVersion(remoteCode: 2, localCode: 1), isTrue);
      expect(hasNewVersion(remoteCode: 10, localCode: 9), isTrue);
    });

    test('远端等于本地 → 无新版', () {
      expect(hasNewVersion(remoteCode: 2, localCode: 2), isFalse);
    });

    test('远端小于本地（本地是更新的测试包）→ 无新版', () {
      expect(hasNewVersion(remoteCode: 1, localCode: 2), isFalse);
    });
  });

  group('parseUpdateJson（update.json 解析容错）', () {
    test('完整合法 JSON → 解析成功', () {
      final info = parseUpdateJson(
          '{"version":"1.0.1","versionCode":2,"apkUrl":"https://example.com/football-v1.0.1.apk","notes":"修复若干问题"}');
      expect(info, isNotNull);
      expect(info!.version, '1.0.1');
      expect(info.versionCode, 2);
      expect(info.apkUrl, 'https://example.com/football-v1.0.1.apk');
      expect(info.notes, '修复若干问题');
    });

    test('缺 notes → 允许，notes 为空串', () {
      final info = parseUpdateJson(
          '{"version":"1.0.1","versionCode":2,"apkUrl":"https://example.com/a.apk"}');
      expect(info, isNotNull);
      expect(info!.notes, '');
    });

    test('404 页面/非 JSON 文本 → null', () {
      expect(parseUpdateJson('404 Not Found'), isNull);
      expect(parseUpdateJson('<html>error</html>'), isNull);
      expect(parseUpdateJson(''), isNull);
    });

    test('缺关键字段 → null（按已是最新处理）', () {
      expect(parseUpdateJson('{"version":"1.0.1","versionCode":2}'), isNull);
      expect(
          parseUpdateJson(
              '{"version":"1.0.1","apkUrl":"https://example.com/a.apk"}'),
          isNull);
      expect(
          parseUpdateJson(
              '{"versionCode":2,"apkUrl":"https://example.com/a.apk"}'),
          isNull);
    });

    test('字段类型不对 → null', () {
      expect(
          parseUpdateJson(
              '{"version":"1.0.1","versionCode":"2","apkUrl":"https://example.com/a.apk"}'),
          isNull);
      expect(
          parseUpdateJson(
              '{"version":1,"versionCode":2,"apkUrl":"https://example.com/a.apk"}'),
          isNull);
      expect(
          parseUpdateJson('["1.0.1",2,"https://example.com/a.apk"]'), isNull);
    });

    test('apkUrl 为空串 → null', () {
      expect(
          parseUpdateJson('{"version":"1.0.1","versionCode":2,"apkUrl":""}'),
          isNull);
    });
  });

  group('minVersionCode 与 apkUrlArm64（可选字段容错）', () {
    test('缺省 → 0 / 空串', () {
      final info = parseUpdateJson(
          '{"version":"1.0.2","versionCode":3,"apkUrl":"https://example.com/a.apk"}');
      expect(info!.minVersionCode, 0);
      expect(info.apkUrlArm64, '');
    });

    test('合法值 → 正常解析', () {
      final info = parseUpdateJson(
          '{"version":"1.0.2","versionCode":3,"apkUrl":"https://example.com/a.apk","apkUrlArm64":"https://example.com/a-arm64.apk","minVersionCode":2}');
      expect(info!.minVersionCode, 2);
      expect(info.apkUrlArm64, 'https://example.com/a-arm64.apk');
    });

    test('类型不对 → 容错为 0 / 空串', () {
      final info = parseUpdateJson(
          '{"version":"1.0.2","versionCode":3,"apkUrl":"https://example.com/a.apk","minVersionCode":"2","apkUrlArm64":1}');
      expect(info!.minVersionCode, 0);
      expect(info.apkUrlArm64, '');
    });
  });

  group('needForceUpdate（强制更新判断）', () {
    test('本地低于最低版本 → 强制', () {
      expect(needForceUpdate(minVersionCode: 3, localCode: 2), isTrue);
    });
    test('本地等于/高于最低版本 → 不强制', () {
      expect(needForceUpdate(minVersionCode: 2, localCode: 2), isFalse);
      expect(needForceUpdate(minVersionCode: 0, localCode: 1), isFalse);
    });
  });

  group('pickApkUrl（按设备架构挑小包）', () {
    const uni = 'https://example.com/full.apk';
    const arm = 'https://example.com/arm64.apk';
    test('arm64 机型且有专属包 → 用小包', () {
      expect(
          pickApkUrl(
              universalUrl: uni,
              arm64Url: arm,
              deviceAbis: ['arm64-v8a', 'armeabi-v7a']),
          arm);
    });
    test('非 arm64 机型 → 用通用包', () {
      expect(
          pickApkUrl(
              universalUrl: uni, arm64Url: arm, deviceAbis: ['armeabi-v7a']),
          uni);
    });
    test('专属包地址为空 → 用通用包', () {
      expect(
          pickApkUrl(
              universalUrl: uni, arm64Url: '', deviceAbis: ['arm64-v8a']),
          uni);
    });
  });
}
