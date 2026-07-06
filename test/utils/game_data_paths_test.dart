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
  });
}
