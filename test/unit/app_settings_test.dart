import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/services/app_logger.dart';

void main() {
  test('分享日志过滤凭据、网址认证和查询参数，保留排错信息', () {
    final sanitized = AppLogger.sanitize(
        'GET https://user:{{PASSWORD_6aaw4xse}}@example.test/path?token={{SECRET_s5skjl42}} status=403\n'
        '"Authorization": "Bearer hidden"\n'
        'cookie: session=hidden\n'
        'token={{SECRET_7sqwospt}}\n'
        'trace: DatabaseHelper.open');
    expect(sanitized, contains('https://example.test/path'));
    expect(sanitized, contains('status=403'));
    expect(sanitized, contains('DatabaseHelper.open'));
    expect(sanitized, isNot(contains('hidden')));
    expect(sanitized, isNot(contains('secret@')));
    expect(sanitized, isNot(contains('query')));
  });

  late Directory tempDir;
  late String tempSettingsPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_test_');
    tempSettingsPath = '${tempDir.path}${Platform.pathSeparator}settings.json';
  });

  tearDown(() async {
    if (await Directory(tempDir.path).exists()) {
      await Directory(tempDir.path).delete(recursive: true);
    }
    AppSettings.invalidateCache();
  });

  group('AutoMoveToSorted Setting', () {
    test('旧版字符串与数字分页设置均可读取且持久化值保持原样', () async {
      final settings = await AppSettings.loadFromFileForTest(tempSettingsPath);
      for (final value in ['5', 8]) {
        await settings.setValues({'game_list_items_per_page': value});
        await settings.flush();
        final reloaded =
            await AppSettings.loadFromFileForTest(tempSettingsPath);
        expect(reloaded.get('game_list_items_per_page'), value);
        expect(
            int.tryParse(reloaded.get('game_list_items_per_page').toString()),
            value == '5' ? 5 : 8);
      }
    });

    test('default value should be null (not set)', () async {
      final settings = await AppSettings.loadFromFileForTest(tempSettingsPath);
      final value = settings.getBool(AppSettings.autoMoveToSortedKey);
      expect(value, isNull);
    });

    test('setBool should persist autoMoveToSorted', () async {
      final settings = await AppSettings.loadFromFileForTest(tempSettingsPath);
      await settings.setBool(AppSettings.autoMoveToSortedKey, true);
      await settings.flush();

      AppSettings.invalidateCache();
      final reloaded = await AppSettings.loadFromFileForTest(tempSettingsPath);
      expect(reloaded.getBool(AppSettings.autoMoveToSortedKey), true);
    });

    test('setBool false should persist correctly', () async {
      final settings = await AppSettings.loadFromFileForTest(tempSettingsPath);
      await settings.setBool(AppSettings.autoMoveToSortedKey, false);
      await settings.flush();

      AppSettings.invalidateCache();
      final reloaded = await AppSettings.loadFromFileForTest(tempSettingsPath);
      expect(reloaded.getBool(AppSettings.autoMoveToSortedKey), false);
    });
  });
}
