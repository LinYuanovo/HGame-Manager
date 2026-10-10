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

    test('moves legacy files and referenced images into HGMDatas', () async {
      final legacyImage = File(
          path.join(tempDir.path, 'images', '1.jpg'));
      await File(path.join(tempDir.path, 'metadata.json')).writeAsString(
        jsonEncode({'intro': '[图片:${legacyImage.path}]'}),
      );
      await File(path.join(tempDir.path, 'source_url.txt'))
          .writeAsString('https://example.test');
      await Directory(path.dirname(legacyImage.path)).create(recursive: true);
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
      // 被迁移清空后旧目录应被递归删除
      expect(
          await Directory(path.join(tempDir.path, 'images')).exists(), isFalse);
      expect(result.imagePathMap[legacyImage.path], isNotNull);
    });

    test('legacy layout mixed images dir migrates only managed files',
        () async {
      // 根目录 metadata.json（旧布局标记）+ images/ 混合目录：
      // 管理器命名（scrape_/manual_/guide_/UUID）与被引用文件迁移，
      // 未被引用的纯数字图与游戏资源图保持原位
      await File(path.join(tempDir.path, 'metadata.json')).writeAsString('{}');
      final mixedDir = await Directory(path.join(tempDir.path, 'images'))
          .create(recursive: true);
      final scrapeImage =
          File(path.join(mixedDir.path, 'scrape_1.jpg'));
      await scrapeImage.writeAsBytes([1]);
      final manualImage =
          File(path.join(mixedDir.path, 'manual_1.png'));
      await manualImage.writeAsBytes([2]);
      final guideImage =
          File(path.join(mixedDir.path, 'guide_01.jpg'));
      await guideImage.writeAsBytes([3]);
      final uuidImage = File(path.join(mixedDir.path,
          '3fa85f64-5717-4562-b3fc-2c963f66afa6.webp'));
      await uuidImage.writeAsBytes([4]);
      final referencedNumeric = File(path.join(mixedDir.path, '2.jpg'));
      await referencedNumeric.writeAsBytes([5]);
      final unreferencedNumeric = File(path.join(mixedDir.path, '9.jpg'));
      await unreferencedNumeric.writeAsBytes([6]);
      final assetImage = File(path.join(mixedDir.path, 'bg.png'));
      await assetImage.writeAsBytes([7]);
      service = GameDataMigrationService(
        gameRepository: _FakeGameRepository(
          game: Game(id: 1, path: tempDir.path, intro: '图: ${referencedNumeric.path}'),
          images: [],
        ),
      );

      final result =
          await service.migrateGameDirectory(tempDir.path, gameId: 1);

      final targetDir = GameDataPaths.imagesDir(tempDir.path).path;
      expect(result.imagePathMap[scrapeImage.path],
          path.join(targetDir, 'scrape_1.jpg'));
      expect(result.imagePathMap[manualImage.path],
          path.join(targetDir, 'manual_1.png'));
      expect(result.imagePathMap[guideImage.path],
          path.join(targetDir, 'guide_01.jpg'));
      expect(
          result.imagePathMap[uuidImage.path], isNotNull);
      expect(result.imagePathMap[referencedNumeric.path],
          path.join(targetDir, '2.jpg'));
      // 未被引用的纯数字图与资源图不迁移
      expect(result.imagePathMap[unreferencedNumeric.path], isNull);
      expect(result.imagePathMap[assetImage.path], isNull);
      expect(await unreferencedNumeric.exists(), isTrue);
      expect(await assetImage.exists(), isTrue);
      expect(await mixedDir.exists(), isTrue);
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

    test('migrated image with conflicting name gets unique path', () async {
      // HGMDatas/images 与旧 images/ 存在同名管理器图：迁移时防重命名
      await File(path.join(tempDir.path, 'metadata.json')).writeAsString('{}');
      final currentImages = await GameDataPaths.ensureImagesDir(tempDir.path);
      await File(path.join(currentImages.path, 'scrape_1.jpg'))
          .writeAsBytes([1]);
      final legacyImages = await Directory(path.join(tempDir.path, 'images'))
          .create(recursive: true);
      final legacyImage =
          File(path.join(legacyImages.path, 'scrape_1.jpg'));
      await legacyImage.writeAsBytes([2]);

      final result = await service.migrateGameDirectory(tempDir.path);

      expect(
        await File(path.join(currentImages.path, 'scrape_1 (1).jpg'))
            .exists(),
        isTrue,
      );
      expect(result.imagePathMap[legacyImage.path],
          path.join(currentImages.path, 'scrape_1 (1).jpg'));
    });

    test('keeps game-owned image and images folders untouched', () async {
      // 无根目录 metadata.json / source_url.txt 管理器标记：
      // images / image 视为游戏自带资源目录，不得迁移
      final assetSingular = await Directory(path.join(tempDir.path, 'image'))
          .create(recursive: true);
      await File(path.join(assetSingular.path, 'bg.png')).writeAsBytes([1]);
      await Directory(path.join(assetSingular.path, 'cg')).create();
      await File(path.join(assetSingular.path, 'cg', 'scene.png'))
          .writeAsBytes([2]);
      final assetPlural = await Directory(path.join(tempDir.path, 'images'))
          .create(recursive: true);
      await File(path.join(assetPlural.path, 'title.png')).writeAsBytes([3]);

      final result = await service.migrateGameDirectory(tempDir.path);

      expect(result.changed, isFalse);
      expect(await File(path.join(assetSingular.path, 'bg.png')).exists(),
          isTrue);
      expect(
          await File(path.join(assetSingular.path, 'cg', 'scene.png')).exists(),
          isTrue);
      expect(await File(path.join(assetPlural.path, 'title.png')).exists(),
          isTrue);
      expect(
          await GameDataPaths.dataDir(tempDir.path).exists(), isFalse);
    });

    test('moves only referenced files from game image folder', () async {
      // 新布局（HGMDatas/metadata.json）+ 游戏自带 image 资源目录：
      // 仅迁移被数据库引用的文件，其余保持原位
      final dataDir = await GameDataPaths.ensureDataDir(tempDir.path);
      await File(path.join(dataDir.path, 'metadata.json')).writeAsString('{}');
      final assetSingular = await Directory(path.join(tempDir.path, 'image'))
          .create(recursive: true);
      final referencedFile = File(path.join(assetSingular.path, 'ref.png'));
      await referencedFile.writeAsBytes([1]);
      await Directory(path.join(assetSingular.path, 'cg')).create();
      await File(path.join(assetSingular.path, 'cg', 'scene.png'))
          .writeAsBytes([2]);
      final repo = _FakeGameRepository(
        game: Game(id: 1, path: tempDir.path),
        images: [
          GameImage(gameId: 1, imagePath: referencedFile.path),
        ],
      );
      service = GameDataMigrationService(gameRepository: repo);

      final result =
          await service.migrateGameDirectory(tempDir.path, gameId: 1);

      final newPath = result.imagePathMap[referencedFile.path]!;
      expect(await File(newPath).exists(), isTrue);
      expect(
          await File(path.join(
                  GameDataPaths.imagesDir(tempDir.path).path, 'ref.png'))
              .exists(),
          isTrue);
      expect(
          await File(path.join(assetSingular.path, 'cg', 'scene.png')).exists(),
          isTrue);
      expect(repo.images.single.imagePath, newPath);
    });

    test('hasLegacyGameData ignores game asset folders without markers',
        () async {
      await Directory(path.join(tempDir.path, 'image')).create();
      await Directory(path.join(tempDir.path, 'images')).create();

      expect(await service.hasLegacyGameData(tempDir.path), isFalse);

      await File(path.join(tempDir.path, 'metadata.json'))
          .writeAsString('{}');

      expect(await service.hasLegacyGameData(tempDir.path), isTrue);
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
