import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as path;

import '../../scraper/parse_utils.dart';
import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import '../utils/game_data_paths.dart';
import '../utils/proxy_client.dart';
import '../utils/scraped_image_file_cleaner.dart';
import '../utils/scraped_image_reference_rewriter.dart';
import 'concurrent_image_downloader.dart';

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
