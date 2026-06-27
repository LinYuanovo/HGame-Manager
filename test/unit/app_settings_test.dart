import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';

void main() {
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
    test('default value should be null (not set)', () async {
      final settings = await AppSettings.load();
      final value = settings.getBool(AppSettings.autoMoveToSortedKey);
      expect(value, isNull);
    });

    test('setBool should persist autoMoveToSorted', () async {
      final settings = await AppSettings.load();
      await settings.setBool(AppSettings.autoMoveToSortedKey, true);
      await settings.flush();
      
      AppSettings.invalidateCache();
      final reloaded = await AppSettings.load();
      expect(reloaded.getBool(AppSettings.autoMoveToSortedKey), true);
    });

    test('setBool false should persist correctly', () async {
      final settings = await AppSettings.load();
      await settings.setBool(AppSettings.autoMoveToSortedKey, false);
      await settings.flush();
      
      AppSettings.invalidateCache();
      final reloaded = await AppSettings.load();
      expect(reloaded.getBool(AppSettings.autoMoveToSortedKey), false);
    });
  });
}
