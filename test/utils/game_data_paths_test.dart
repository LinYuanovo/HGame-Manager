import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:path/path.dart' as path;

void main() {
  group('GameDataPaths', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hgm_paths_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns HGMDatas paths', () {
      expect(
        GameDataPaths.metadataFile(tempDir.path).path,
        path.join(tempDir.path, 'HGMDatas', 'metadata.json'),
      );
      expect(
        GameDataPaths.sourceUrlFile(tempDir.path).path,
        path.join(tempDir.path, 'HGMDatas', 'source_url.txt'),
      );
      expect(
        GameDataPaths.imagesDir(tempDir.path).path,
        path.join(tempDir.path, 'HGMDatas', 'images'),
      );
      expect(
        GameDataPaths.backupDir(tempDir.path).path,
        path.join(tempDir.path, 'HGMDatas', 'backup'),
      );
    });

    test('falls back to legacy metadata and source_url files', () async {
      final legacyMetadata = File(path.join(tempDir.path, 'metadata.json'));
      final legacySource = File(path.join(tempDir.path, 'source_url.txt'));
      await legacyMetadata.writeAsString('{}');
      await legacySource.writeAsString('https://example.test');

      expect(
        (await GameDataPaths.existingMetadataFile(tempDir.path)).path,
        legacyMetadata.path,
      );
      expect(
        (await GameDataPaths.existingSourceUrlFile(tempDir.path)).path,
        legacySource.path,
      );
    });

    test('prefers HGMDatas images over legacy images', () async {
      final current = await GameDataPaths.ensureImagesDir(tempDir.path);
      await Directory(path.join(tempDir.path, 'images')).create();

      expect(
        (await GameDataPaths.existingImagesDir(tempDir.path)).path,
        current.path,
      );
    });

    test('falls back to legacy plural images dir', () async {
      final legacy = await Directory(path.join(tempDir.path, 'images'))
          .create(recursive: true);

      expect(
        (await GameDataPaths.existingImagesDir(tempDir.path)).path,
        legacy.path,
      );
    });

    test('does not treat singular image dir as managed images dir', () async {
      // 单数 image 是游戏常见资源目录名，管理器从未使用，不得兜底
      await Directory(path.join(tempDir.path, 'image')).create();

      expect(
        (await GameDataPaths.existingImagesDir(tempDir.path)).path,
        GameDataPaths.imagesDir(tempDir.path).path,
      );
    });

    test('isManagedImagePath does not match singular image dir', () {
      final singularPath = path.join(tempDir.path, 'image', 'bg.png');

      expect(
        GameDataPaths.isManagedImagePath(tempDir.path, singularPath),
        isFalse,
      );
      expect(
        GameDataPaths.isManagedImagePath(
          tempDir.path,
          path.join(GameDataPaths.imagesDir(tempDir.path).path, '1.jpg'),
        ),
        isTrue,
      );
      expect(
        GameDataPaths.isManagedImagePath(
          tempDir.path,
          path.join(tempDir.path, 'images', '1.jpg'),
        ),
        isTrue,
      );
    });

    test('isManagedImageFileName recognizes managed naming only', () {
      expect(GameDataPaths.isManagedImageFileName('scrape_1.jpg'), isTrue);
      expect(GameDataPaths.isManagedImageFileName('manual_12.png'), isTrue);
      expect(GameDataPaths.isManagedImageFileName('guide_01.webp'), isTrue);
      expect(GameDataPaths.isManagedImageFileName('video_1.mp4'), isTrue);
      expect(
        GameDataPaths.isManagedImageFileName(
            '3fa85f64-5717-4562-b3fc-2c963f66afa6.jpg'),
        isTrue,
      );
      // 纯数字（旧刮削命名与游戏 CG 撞名）与游戏资源名不算管理器命名
      expect(GameDataPaths.isManagedImageFileName('1.jpg'), isFalse);
      expect(GameDataPaths.isManagedImageFileName('bg.png'), isFalse);
    });

    test('parseScrapeImageIndex parses scrape and legacy numeric stems', () {
      expect(GameDataPaths.parseScrapeImageIndex('scrape_3.jpg'), 3);
      expect(GameDataPaths.parseScrapeImageIndex('7.webp'), 7);
      expect(GameDataPaths.parseScrapeImageIndex('scrape_1.tmp.jpg'), isNull);
      expect(GameDataPaths.parseScrapeImageIndex('manual_1.jpg'), isNull);
      expect(GameDataPaths.parseScrapeImageIndex('bg.png'), isNull);
    });
  });
}
