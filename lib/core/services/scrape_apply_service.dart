import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../scraper/parse_utils.dart';
import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import '../utils/game_data_paths.dart';
import '../utils/scraped_image_reference_rewriter.dart';

class ScrapeApplyService {
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
