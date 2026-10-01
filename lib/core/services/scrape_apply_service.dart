import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as path;

import '../../scraper/parse_utils.dart';
import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import '../utils/app_settings.dart';
import '../utils/game_data_paths.dart';
import '../utils/proxy_client.dart';
import '../utils/scraped_image_file_cleaner.dart';
import '../utils/scraped_image_reference_rewriter.dart';
import 'concurrent_image_downloader.dart';
import 'folder_rename_service.dart';
import 'game_data_migration_service.dart';

class ScrapeApplyService {
  static final _versionPattern = RegExp(
      r'\s+(?:build|v(?:er(?:sion)?)?)\s*\.?\d+(?:[\d.]*\d+)?\s*',
      caseSensitive: false);

  static const _categoryOrder = [
    'RPG',
    'ADV',
    'ACT',
    'SLG',
    'AVG',
    'FPS',
    'TPS',
    '3D'
  ];

  static String stripVersionFromTitle(String title, [String? version]) {
    var result = title;
    if (version != null && version.isNotEmpty) {
      final escaped = RegExp.escape(version);
      final precisePattern = RegExp(
          r'\s+(?:build|v(?:er(?:sion)?)?)?\s*' + escaped + r'\s*',
          caseSensitive: false);
      result = result.replaceAll(precisePattern, ' ');
    }
    result = result.replaceAll(_versionPattern, ' ');
    return result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static String resolveCategoryName(List<Tag> tags) {
    final allNames = tags.map((t) => t.name.toUpperCase()).toList();
    for (final cat in _categoryOrder) {
      if (allNames.any((name) => name.contains(cat))) {
        return cat;
      }
    }
    return 'Unclassified';
  }

  static Game mergeGameInfo(Game game, GameInfo gameInfo, {String? sourceUrl}) {
    final displayTitle = gameInfo.title != null
        ? stripVersionFromTitle(gameInfo.title!, gameInfo.version)
        : null;
    return game.copyWith(
      title: displayTitle ?? game.title,
      version: gameInfo.version ?? game.version,
      intro: gameInfo.description ?? game.intro,
      features: gameInfo.features.isNotEmpty
          ? gameInfo.features.join('\n')
          : game.features,
      changelog: gameInfo.changelog ?? game.changelog,
      downloadUrl: gameInfo.downloadUrl.isNotEmpty
          ? gameInfo.downloadUrl
          : game.downloadUrl,
      sourceUrl: sourceUrl ?? game.sourceUrl,
      maker: gameInfo.maker ?? game.maker,
      makerUrl: gameInfo.makerUrl ?? game.makerUrl,
    );
  }

  static Map<String, dynamic> buildMetadataJson(GameInfo gameInfo,
      {String? intro, String? introHtml}) {
    final json = gameInfo.toJson();
    if (intro != null) json['intro'] = intro;
    if (introHtml != null) json['intro_html'] = introHtml;
    return json;
  }

  static Map<String, String> buildNumberedUrlMapping(
      List<String> imageUrls, List<String> localImages) {
    final urlToLocal = <String, String>{};
    for (int i = 0; i < imageUrls.length; i++) {
      final remoteUrl = imageUrls[i];
      for (final localPath in localImages) {
        final fileName = localPath.split(Platform.pathSeparator).last;
        final baseName = fileName.split('.').first;
        if (baseName == '${i + 1}') {
          urlToLocal[remoteUrl] = localPath;
          if (remoteUrl.startsWith('https:')) {
            urlToLocal[remoteUrl.replaceFirst('https:', '')] = localPath;
          }
          if (remoteUrl.startsWith('http:')) {
            urlToLocal[remoteUrl.replaceFirst('http:', '')] = localPath;
          }
          break;
        }
      }
    }
    return urlToLocal;
  }

  static Future<Map<String, String>> downloadAndApplyImages({
    required Game game,
    required GameRepository repo,
    required List<String> imageUrls,
    required String sourceUrl,
    int maxConcurrency = 1,
    void Function(int current, int total)? onProgress,
    void Function(String message)? onLog,
  }) async {
    if (imageUrls.isEmpty || game.id == null) return {};

    onLog?.call('下载 ${imageUrls.length} 张配图...');
    final imagesDir = await GameDataPaths.ensureImagesDir(game.path);
    final oldImagePaths = <int, String>{};
    if (await imagesDir.exists()) {
      await for (final entity in imagesDir.list()) {
        if (entity is File &&
            !path.basenameWithoutExtension(entity.path).endsWith('.tmp')) {
          final index =
              int.tryParse(path.basenameWithoutExtension(entity.path));
          if (index != null) oldImagePaths[index] = entity.path;
        }
      }
    }

    final headers = await buildScrapeImageHeaders(sourceUrl);
    final urlToTmp = await ConcurrentImageDownloader.downloadAll(
      imageUrls: imageUrls,
      saveDir: game.path,
      headers: headers,
      maxConcurrency: maxConcurrency,
      useTempFiles: true,
      onProgress: onProgress,
    );

    final urlToLocal = <String, String>{};
    final finalImages = <GameImage>[];
    for (int i = 0; i < imageUrls.length; i++) {
      final url = imageUrls[i];
      final tmpPath = urlToTmp[url];
      if (tmpPath != null && await File(tmpPath).exists()) {
        final ext = path.extension(tmpPath).replaceAll('.tmp', '');
        final finalPath = path.join(imagesDir.path, '${i + 1}$ext');
        if (finalPath != tmpPath) {
          final oldFile = File(finalPath);
          if (await oldFile.exists()) await oldFile.delete();
          await File(tmpPath).rename(finalPath);
        }
        urlToLocal[url] = finalPath;
        finalImages.add(GameImage(
            gameId: game.id!, imagePath: finalPath, sortOrder: i));
      } else {
        final oldPath = oldImagePaths[i + 1];
        if (oldPath != null) {
          finalImages.add(GameImage(
              gameId: game.id!, imagePath: oldPath, sortOrder: i));
        }
      }
    }

    // useTempFiles 的临时文件命名为 `1.tmp.jpg`，需按 basename 判断后缀
    if (await imagesDir.exists()) {
      await for (final entity in imagesDir.list()) {
        if (entity is File &&
            path.basenameWithoutExtension(entity.path).endsWith('.tmp')) {
          await entity.delete();
        }
      }
    }

    final deletedCount =
        await ScrapedImageFileCleaner.cleanUnusedNumberedImages(
      gamePath: game.path,
      retainedImagePaths: finalImages.map((image) => image.imagePath),
      referenceTexts: [
        game.intro,
        game.features,
        game.changelog,
        game.guide,
      ],
    );
    if (deletedCount > 0) {
      onLog?.call('清理旧配图: $deletedCount 张');
    }

    await repo.setGameImages(game.id!, finalImages);
    onLog?.call('配图处理完成: ${finalImages.length}/${imageUrls.length}');

    if (urlToLocal.isNotEmpty) {
      var current = await repo.getGameById(game.id!);
      if (current != null) {
        var intro = current.intro;
        if (intro != null) {
          intro = ScrapedImageReferenceRewriter.replacePlainTextImages(
              intro, urlToLocal);
        }
        await repo.updateGame(current.copyWith(intro: intro));

        final metadataFile = GameDataPaths.metadataFile(current.path);
        if (await metadataFile.exists()) {
          final metaJson =
              jsonDecode(await metadataFile.readAsString())
                  as Map<String, dynamic>;
          if (intro != null) metaJson['intro'] = intro;
          if (metaJson['intro_html'] is String) {
            metaJson['intro_html'] =
                ScrapedImageReferenceRewriter.replaceHtmlImages(
                    metaJson['intro_html'] as String, urlToLocal);
          }
          await metadataFile.writeAsString(jsonEncode(metaJson), flush: true);
        }
      }
    }

    final reloaded = await repo.getGameById(game.id!);
    if (reloaded != null) {
      await fixImageUrlsInMetadata(reloaded, repo);
    }
    return urlToLocal;
  }

  static Future<Game> moveGameToSorted(Game game, GameRepository repo,
      {void Function(String message)? onLog}) async {
    if (game.id == null) return game;
    final sortedPath = await AppSettings.getSortedPathForGame(game.path);
    if (sortedPath.isEmpty) return game;
    final sourceDir = Directory(game.path);
    if (!await sourceDir.exists()) return game;

    final tags = await repo.getGameTags(game.id!);
    final categoryName = resolveCategoryName(tags);
    final folderName = path.basename(game.path);
    final categoryDir = Directory(path.join(sortedPath, categoryName));
    if (!await categoryDir.exists()) {
      await categoryDir.create(recursive: true);
    }
    final targetDir = Directory(path.join(sortedPath, categoryName, folderName));
    if (await targetDir.exists()) {
      onLog?.call('目标目录已存在，跳过移动');
      return game;
    }

    final existingGame = await repo.getGameByPath(targetDir.path);
    if (existingGame != null) {
      await repo.deleteGame(existingGame.id!);
      onLog?.call('已删除目标路径的旧记录');
    }

    await sourceDir.rename(targetDir.path);
    await repo.updateGamePath(game.id!, targetDir.path);
    final images = await repo.getGameImages(game.id!);
    if (images.isNotEmpty) {
      await repo.setGameImages(
          game.id!,
          images
              .map((img) => GameImage(
                    id: img.id,
                    gameId: img.gameId,
                    imagePath:
                        img.imagePath.replaceFirst(game.path, targetDir.path),
                    sortOrder: img.sortOrder,
                  ))
              .toList());
    }

    await GameDataMigrationService(gameRepository: repo)
        .rewriteGamePathReferences(
      gameId: game.id!,
      oldPath: game.path,
      newPath: targetDir.path,
    );

    var current = await repo.getGameById(game.id!);
    if (current == null) return game;
    if (current.gameLauncher != null &&
        current.gameLauncher!.startsWith(game.path)) {
      final relative = current.gameLauncher!.substring(game.path.length);
      final newLauncher = '${targetDir.path}$relative';
      await repo.updateGameLauncher(
          game.id!, newLauncher, current.launcherLocked);
      current = current.copyWith(gameLauncher: newLauncher);
    }
    if (current.savePath != null &&
        current.savePath!.startsWith(game.path)) {
      final relative = current.savePath!.substring(game.path.length);
      final newSavePath = '${targetDir.path}$relative';
      await repo.updateGame(current.copyWith(savePath: newSavePath));
      current = current.copyWith(savePath: newSavePath);
    }
    onLog?.call('已移动到: ${current.path}');
    return current;
  }

  static Future<Game> organizeFolder(
    Game game,
    ScrapeMode mode,
    GameRepository repo,
    ScrapeModeConfigs configs, {
    void Function(String message)? onLog,
  }) async {
    var current = game;
    if (configs.shouldRename(mode) && current.id != null) {
      try {
        final renameService = FolderRenameService(gameRepository: repo);
        final newPath = await renameService.renameGameFolder(current);
        if (newPath != null) {
          onLog?.call('文件夹已重命名: ${path.basename(newPath)}');
          final refreshed = await repo.getGameById(current.id!);
          if (refreshed != null) current = refreshed;
        }
      } catch (e) {
        debugPrint('[ScrapeApply] 自动重命名失败: $e');
        onLog?.call('重命名失败: $e');
      }
    }
    if (configs.shouldMove(mode) && current.id != null) {
      // 移动失败仅记日志，不得影响刮削/导入的结果状态（保持各入口现状语义）
      try {
        current = await moveGameToSorted(current, repo, onLog: onLog);
      } catch (e) {
        debugPrint('[ScrapeApply] 自动移动失败: $e');
        onLog?.call('移动失败: $e');
      }
    }
    return current;
  }

  static Future<Game> applyScrapeResult({
    required Game game,
    required GameInfo gameInfo,
    required ScrapeMode mode,
    required GameRepository repo,
    required TagRepository tagRepo,
    required ScrapeModeConfigs configs,
    String? sourceUrl,
    int maxConcurrency = 1,
    void Function(int current, int total)? onProgress,
    void Function(String message)? onLog,
  }) async {
    // 旧布局迁移（根目录 metadata.json/images -> HGMDatas/）必须保留：
    // 现状由详情页 _downloadImagesWithMapping 内部与刮削中心入口承担，
    // 删除详情页私有实现后此处是唯一保障，且该方法幂等。
    await GameDataMigrationService(gameRepository: repo)
        .migrateGameDirectory(game.path, gameId: game.id);

    final merged = mergeGameInfo(game, gameInfo, sourceUrl: sourceUrl);
    int gameId;
    if (game.id != null) {
      await repo.updateGame(merged);
      gameId = game.id!;
    } else {
      gameId = await repo.insertGame(merged);
    }
    var current = merged.copyWith(id: gameId);

    // 文件写入失败不应使整个刮削失败（保持快速刮削现状的容错语义）
    final effectiveSourceUrl = sourceUrl ?? gameInfo.sourceUrl;
    try {
      await GameDataPaths.ensureDataDir(current.path);
      await GameDataPaths.metadataFile(current.path)
          .writeAsString(jsonEncode(buildMetadataJson(gameInfo)), flush: true);
    } catch (e) {
      debugPrint('[ScrapeApply] 写入 metadata.json 失败: $e');
    }
    if (effectiveSourceUrl.isNotEmpty) {
      try {
        await GameDataPaths.sourceUrlFile(current.path)
            .writeAsString(effectiveSourceUrl, flush: true);
      } catch (e) {
        debugPrint('[ScrapeApply] 写入 source_url.txt 失败: $e');
      }
    }

    await syncTags(repo, tagRepo, gameId, gameInfo);

    await downloadAndApplyImages(
      game: current,
      repo: repo,
      imageUrls: gameInfo.screenshots,
      sourceUrl: effectiveSourceUrl,
      maxConcurrency: maxConcurrency,
      onProgress: onProgress,
      onLog: onLog,
    );

    current = await repo.getGameById(gameId) ?? current;
    current = await organizeFolder(current, mode, repo, configs, onLog: onLog);
    return current;
  }

  static Future<void> syncTags(
    GameRepository repo,
    TagRepository tagRepo,
    int gameId,
    GameInfo gameInfo,
  ) async {
    await repo.clearGameTags(gameId);
    if (gameInfo.maker != null && gameInfo.maker!.isNotEmpty) {
      final makerTagId =
          await tagRepo.insertOrGetTag(gameInfo.maker!, Tag.typeCustom);
      await repo.addTagToGame(gameId, makerTagId);
    }
    for (final tagName in gameInfo.tags) {
      final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
      await repo.addTagToGame(gameId, tagId);
    }
    if (gameInfo.category != null) {
      final tagId =
          await tagRepo.insertOrGetTag(gameInfo.category!, Tag.typeSeries);
      await repo.addTagToGame(gameId, tagId);
    }
    final gameTagNames = [
      ...gameInfo.tags,
      if (gameInfo.category != null) gameInfo.category!,
    ];
    final allTags = await tagRepo.getAllTags();
    for (final existingTag in allTags) {
      final alreadyHas = gameTagNames
          .any((t) => t.toLowerCase() == existingTag.name.toLowerCase());
      if (alreadyHas) continue;
      final isOverlapping = gameTagNames.any((t) =>
          t.toLowerCase().contains(existingTag.name.toLowerCase()) &&
          t.toLowerCase() != existingTag.name.toLowerCase());
      if (isOverlapping) {
        await repo.addTagToGame(gameId, existingTag.id!);
      }
    }
  }

  static Future<void> fixImageUrlsInMetadata(
      Game game, GameRepository repo) async {
    try {
      final metadataFile = await GameDataPaths.existingMetadataFile(game.path);
      if (!await metadataFile.exists()) return;

      final metaJson = jsonDecode(await metadataFile.readAsString());
      final imageDir = await GameDataPaths.existingImagesDir(game.path);
      if (!await imageDir.exists()) return;

      final localImages = <String>[];
      await for (final entity in imageDir.list()) {
        if (entity is File) {
          localImages.add(entity.path);
        }
      }
      if (localImages.isEmpty) return;

      final imageUrls =
          (metaJson['image_urls'] as List<dynamic>?)?.cast<String>() ?? [];
      if (imageUrls.isEmpty) return;

      final urlToLocal = buildNumberedUrlMapping(imageUrls, localImages);

      if (urlToLocal.isEmpty) return;

      var intro = metaJson['intro'] as String? ?? '';
      if (intro.isNotEmpty) {
        intro = ScrapedImageReferenceRewriter.replaceAllReferences(
            intro, urlToLocal);
        metaJson['intro'] = intro;
      }

      var introHtml = metaJson['intro_html'] as String? ?? '';
      if (introHtml.isNotEmpty) {
        introHtml = ScrapedImageReferenceRewriter.replaceHtmlImages(
            introHtml, urlToLocal);
        metaJson['intro_html'] = introHtml;
      }

      await metadataFile.writeAsString(jsonEncode(metaJson), flush: true);

      await repo.updateGame(game.copyWith(intro: intro));
    } catch (e) {
      debugPrint('[FixImageUrls] Error: $e');
    }
  }
}
