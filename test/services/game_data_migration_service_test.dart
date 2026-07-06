import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/services/game_data_migration_service.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:path/path.dart' as path;

void main() {
  group('GameDataMigrationService', () {
    late Directory tempDir;
    late GameDataMigrationService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hgm_migration_test_');
      service = GameDataMigrationService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('moves legacy files and folders into HGMDatas', () async {
      await File(path.join(tempDir.path, 'metadata.json')).writeAsString('{}');
      await File(path.join(tempDir.path, 'source_url.txt'))
          .writeAsString('https://example.test');
      final legacyImages = await Directory(path.join(tempDir.path, 'images'))
          .create(recursive: true);
      final legacyImage = File(path.join(legacyImages.path, '1.jpg'));
      await legacyImage.writeAsBytes([1, 2, 3]);
      final legacyBackup = await Directory(path.join(tempDir.path, 'HGMBackup'))
          .create(recursive: true);
      await File(path.join(legacyBackup.path, 'save.zip')).writeAsBytes([4]);

      final result = await service.migrateGameDirectory(tempDir.path);

      expect(result.changed, isTrue);
      expect(await GameDataPaths.metadataFile(tempDir.path).exists(), isTrue);
      expect(await GameDataPaths.sourceUrlFile(tempDir.path).exists(), isTrue);
      expect(
        await File(
                path.join(GameDataPaths.imagesDir(tempDir.path).path, '1.jpg'))
            .exists(),
        isTrue,
      );
      expect(
        await File(path.join(
                GameDataPaths.backupDir(tempDir.path).path, 'save.zip'))
            .exists(),
        isTrue,
      );
      expect(await File(path.join(tempDir.path, 'metadata.json')).exists(),
          isFalse);
      expect(
          await Directory(path.join(tempDir.path, 'images')).exists(), isFalse);
      expect(result.imagePathMap[legacyImage.path], isNotNull);
    });

    test('keeps both files when new and legacy files conflict', () async {
      final dataDir = await GameDataPaths.ensureDataDir(tempDir.path);
      final currentMetadata = File(path.join(dataDir.path, 'metadata.json'));
      final legacyMetadata = File(path.join(tempDir.path, 'metadata.json'));
      await currentMetadata.writeAsString('new');
      await legacyMetadata.writeAsString('legacy');

      await currentMetadata.setLastModified(DateTime(2024));
      await legacyMetadata.setLastModified(DateTime(2025));

      await service.migrateGameDirectory(tempDir.path);

      expect(await currentMetadata.readAsString(), 'legacy');
      expect(
        await File(path.join(dataDir.path, 'metadata.json.legacy'))
            .readAsString(),
        'new',
      );
    });

    test('merges images and image folders with unique names', () async {
      final currentImages = await GameDataPaths.ensureImagesDir(tempDir.path);
      await File(path.join(currentImages.path, 'cover.jpg')).writeAsBytes([1]);
      final legacyImages = await Directory(path.join(tempDir.path, 'images'))
          .create(recursive: true);
      await File(path.join(legacyImages.path, 'cover.jpg')).writeAsBytes([2]);
      final singularImages = await Directory(path.join(tempDir.path, 'image'))
          .create(recursive: true);
      await File(path.join(singularImages.path, 'cover.jpg')).writeAsBytes([3]);

      await service.migrateGameDirectory(tempDir.path);

      expect(await File(path.join(currentImages.path, 'cover.jpg')).exists(),
          isTrue);
      expect(
          await File(path.join(currentImages.path, 'cover (1).jpg')).exists(),
          isTrue);
      expect(
          await File(path.join(currentImages.path, 'cover (2).jpg')).exists(),
          isTrue);
    });

    test('updates metadata image references when images move', () async {
      final legacyImages = await Directory(path.join(tempDir.path, 'images'))
          .create(recursive: true);
      final legacyImage = File(path.join(legacyImages.path, '2.webp'));
      await legacyImage.writeAsBytes([1]);
      await File(path.join(tempDir.path, 'metadata.json')).writeAsString(
        jsonEncode({
          'intro': '[图片:${legacyImage.path}]',
          'intro_html': '<img src="${legacyImage.path}">',
        }),
      );

      final result = await service.migrateGameDirectory(tempDir.path);
      final newPath = result.imagePathMap[legacyImage.path]!;
      final metadata = jsonDecode(
        await GameDataPaths.metadataFile(tempDir.path).readAsString(),
      ) as Map<String, dynamic>;

      expect(metadata['intro'], '[图片:$newPath]');
      expect(metadata['intro_html'], '<img src="$newPath">');
    });

    test('repairs existing HGMDatas metadata references with inferred paths',
        () async {
      final currentImages = await GameDataPaths.ensureImagesDir(tempDir.path);
      final currentImage = File(path.join(currentImages.path, '2.webp'));
      await currentImage.writeAsBytes([1]);
      final legacyImagePath =
          path.join(GameDataPaths.legacyImagesDir(tempDir.path).path, '2.webp');
      await GameDataPaths.metadataFile(tempDir.path).writeAsString(
        jsonEncode({'intro': '[图片:$legacyImagePath]'}),
      );

      final result = await service.migrateGameDirectory(tempDir.path);
      final metadata = jsonDecode(
        await GameDataPaths.metadataFile(tempDir.path).readAsString(),
      ) as Map<String, dynamic>;

      expect(result.changed, isTrue);
      expect(metadata['intro'], '[图片:${currentImage.path}]');
    });

    test('updates database image rows and detail text references', () async {
      final legacyImages = await Directory(path.join(tempDir.path, 'images'))
          .create(recursive: true);
      final legacyImage = File(path.join(legacyImages.path, '2.webp'));
      await legacyImage.writeAsBytes([1]);
      final repo = _FakeGameRepository(
        game: Game(
          id: 1,
          path: tempDir.path,
          intro: '[图片:${legacyImage.path}]',
          guide: '攻略图: ${legacyImage.path}',
        ),
        images: [
          GameImage(gameId: 1, imagePath: legacyImage.path),
        ],
      );
      service = GameDataMigrationService(gameRepository: repo);

      final result =
          await service.migrateGameDirectory(tempDir.path, gameId: 1);
      final newPath = result.imagePathMap[legacyImage.path]!;

      expect(repo.images.single.imagePath, newPath);
      expect(repo.game?.intro, '[图片:$newPath]');
      expect(repo.game?.guide, '攻略图: $newPath');
    });
  });
}

class _FakeGameRepository extends GameRepository {
  _FakeGameRepository({
    required this.game,
    required this.images,
  });

  Game? game;
  List<GameImage> images;

  @override
  Future<List<GameImage>> getGameImages(int gameId) async => images;

  @override
  Future<void> setGameImages(int gameId, List<GameImage> images) async {
    this.images = images;
  }

  @override
  Future<Game?> getGameById(int id) async => game;

  @override
  Future<void> updateGame(Game game) async {
    this.game = game;
  }
}
