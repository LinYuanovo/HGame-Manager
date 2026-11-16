import 'app_logger.dart';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseExecutor;
import 'package:uuid/uuid.dart';

import '../../scraper/parse_utils.dart';
import '../models/models.dart';
import '../models/metadata_translation_config.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import '../utils/app_settings.dart';
import '../utils/game_data_paths.dart';
import '../utils/path_reference_rewriter.dart';
import '../utils/proxy_client.dart';
import '../utils/scraped_image_file_cleaner.dart';
import '../utils/scraped_image_reference_rewriter.dart';
import 'concurrent_image_downloader.dart';
import 'dlsite_service.dart';
import 'folder_rename_service.dart';
import 'game_data_migration_service.dart';
import 'game_move_service.dart';
import 'image_service.dart';
import 'metadata_translation_service.dart';
import 'scrape_file_snapshot.dart';
import 'steam_service.dart';

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

  /// metadata.json 中的刮削成功时间戳字段，作为「已刮削」标识
  static const scrapedAtKey = 'scraped_at';

  /// 判断一份 metadata.json 内容是否带有刮削成功标识
  static bool isScrapedMetadata(Map<String, dynamic>? json) {
    if (json == null) return false;
    final value = json[scrapedAtKey];
    return value is String && value.isNotEmpty;
  }

  /// 在 metadata.json 内容上盖「已刮削」时间戳（就地修改并返回）
  static Map<String, dynamic> markScraped(Map<String, dynamic> json,
      {DateTime? at}) {
    json[scrapedAtKey] = (at ?? DateTime.now()).toIso8601String();
    return json;
  }

  /// 读取游戏目录 metadata.json，判断该游戏是否已成功刮削过
  static Future<bool> isGameScraped(String gamePath) async {
    try {
      final metadataFile = await GameDataPaths.existingMetadataFile(gamePath);
      if (!await metadataFile.exists()) return false;
      final json =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      return isScrapedMetadata(json);
    } catch (_) {
      return false;
    }
  }

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
      intro: gameInfo.isDlsiteUserOnly
          ? game.intro
          : gameInfo.description ?? game.intro,
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
      {String? intro,
      String? introHtml,
      Map<String, dynamic>? previousMetadata}) {
    final json = gameInfo.toJson();
    if (gameInfo.isDlsiteUserOnly) {
      final previousIntro = previousMetadata?['intro'];
      final previousHtml = previousMetadata?['intro_html'];
      if (previousIntro is String) intro ??= previousIntro;
      if (previousHtml is String) introHtml ??= previousHtml;
      for (final key in ['features', 'changelog']) {
        if (!json.containsKey(key) && previousMetadata?[key] is String) {
          json[key] = previousMetadata![key];
        }
      }
    }
    if (intro != null) json['intro'] = intro;
    if (introHtml != null) json['intro_html'] = introHtml;
    final previousOriginal = previousMetadata == null
        ? null
        : MetadataTranslationService.originalFrom(previousMetadata);
    if (gameInfo.isDlsiteUserOnly && previousOriginal != null) {
      final original = Map<String, dynamic>.from(json);
      for (final key in _descriptionKeys) {
        final replaced = key == 'features' && gameInfo.features.isNotEmpty ||
            key == 'changelog' && gameInfo.changelog != null;
        if (!replaced) {
          if (previousOriginal[key] is String) {
            original[key] = previousOriginal[key];
          } else {
            original.remove(key);
          }
        }
      }
      json[MetadataTranslationService.metadataKey] = {
        ...Map<String, dynamic>.from(
            previousMetadata![MetadataTranslationService.metadataKey] as Map),
        'original': original,
      };
    }
    return json;
  }

  static const _descriptionKeys = ['intro', 'intro_html', 'features', 'changelog'];

  static Map<String, String> buildNumberedUrlMapping(
      List<String> imageUrls, List<String> localImages) {
    final urlToLocal = <String, String>{};
    for (int i = 0; i < imageUrls.length; i++) {
      final remoteUrl = imageUrls[i];
      for (final localPath in localImages) {
        final fileName = localPath.split(Platform.pathSeparator).last;
        final baseName = fileName.split('.').first;
        final index = GameDataPaths.parseScrapeImageIndex(fileName);
        if (index == i + 1 || baseName == '${i + 1}') {
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

  static Future<Map<String, String>> _preserveDescriptionImages(
      Game game, Map<String, dynamic>? metadata) async {
    final directory = GameDataPaths.imagesDir(game.path);
    if (!await directory.exists()) return {};
    final original = metadata == null
        ? null
        : MetadataTranslationService.originalFrom(metadata);
    final references = [
      game.intro,
      game.features,
      game.changelog,
      game.guide,
      if (metadata?['intro'] is String) metadata!['intro'] as String,
      if (metadata?['intro_html'] is String) metadata!['intro_html'] as String,
      for (final key in _descriptionKeys)
        if (original?[key] is String) original![key] as String,
    ];
    final replacements = <String, String>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          GameDataPaths.parseScrapeImageIndex(entity.path) == null) {
        continue;
      }
      if (!references.any((text) =>
          _replacePreservedImageReferences(text, {entity.path: ''}) != text)) {
        continue;
      }
      final target = path.join(
          directory.path, '${const Uuid().v4()}${path.extension(entity.path)}');
      await entity.copy(target);
      replacements[entity.path] = target;
    }
    return replacements;
  }

  static String? _replacePreservedImageReferences(
      String? text, Map<String, String> replacements) {
    return PathReferenceRewriter.replace(text, {
      ...replacements,
      for (final entry in replacements.entries)
        for (final variant in [entry.key, entry.key.replaceAll('\\', '/')])
          for (final escape in [
            const HtmlEscape(),
            const HtmlEscape(HtmlEscapeMode.element),
          ])
            escape.convert(variant):
                escape.convert(entry.value.replaceAll('\\', '/')),
    });
  }

  static Future<Map<String, String>> downloadAndApplyImages({
    required Game game,
    required GameRepository repo,
    required List<String> imageUrls,
    required String sourceUrl,
    int maxConcurrency = 3,
    void Function(int current, int total)? onProgress,
    void Function(String message)? onLog,
    bool requireAllImages = false,
  }) async {
    if (imageUrls.isEmpty || game.id == null) return {};
    imageUrls = imageUrls.toSet().toList();

    onLog?.call('下载 ${imageUrls.length} 张配图...');
    final imagesDir = await GameDataPaths.ensureImagesDir(game.path);
    final oldImagePaths = <int, String>{};
    if (await imagesDir.exists()) {
      await for (final entity in imagesDir.list()) {
        if (entity is File &&
            !path.basenameWithoutExtension(entity.path).endsWith('.tmp')) {
          final index = GameDataPaths.parseScrapeImageIndex(entity.path);
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

    if (requireAllImages && imageUrls.any((url) => !urlToTmp.containsKey(url))) {
      throw StateError('图片下载不完整（${urlToTmp.length}/${imageUrls.toSet().length}），已取消保存，请重试');
    }

    final urlToLocal = <String, String>{};
    final finalImages = <GameImage>[];
    for (int i = 0; i < imageUrls.length; i++) {
      final url = imageUrls[i];
      final tmpPath = urlToTmp[url];
      if (tmpPath != null && await File(tmpPath).exists()) {
        final ext = path.extension(tmpPath).replaceAll('.tmp', '');
        final finalPath = path.join(
            imagesDir.path, '${GameDataPaths.scrapeImagePrefix}${i + 1}$ext');
        if (finalPath != tmpPath) {
          final oldFile = File(finalPath);
          if (await oldFile.exists()) await oldFile.delete();
          await File(tmpPath).rename(finalPath);
        }
        await ImageService.invalidateFileCache(finalPath);
        urlToLocal[url] = finalPath;
        finalImages.add(
            GameImage(gameId: game.id!, imagePath: finalPath, sortOrder: i));
      } else if (requireAllImages) {
        throw StateError('下载的图片文件已丢失，请重试');
      } else {
        final oldPath = oldImagePaths[i + 1];
        if (oldPath != null) {
          finalImages.add(
              GameImage(gameId: game.id!, imagePath: oldPath, sortOrder: i));
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
        await repo.updateScrapedFields(current.copyWith(intro: intro));

        final metadataFile = GameDataPaths.metadataFile(current.path);
        if (await metadataFile.exists()) {
          final metaJson = jsonDecode(await metadataFile.readAsString())
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
      await fixImageUrlsInMetadata(reloaded, repo, requirePersistence: requireAllImages);
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

    var tags = await repo.getGameTags(game.id!);
    try {
      final metadataFile = await GameDataPaths.existingMetadataFile(game.path);
      if (await metadataFile.exists()) {
        final metadata = jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>;
        final original = MetadataTranslationService.originalFrom(metadata);
        if (original != null) {
          tags = [
            if (game.maker != null) Tag(name: game.maker!, type: Tag.typeCustom),
            for (final name in (original['tags'] as List? ?? []).whereType<String>())
              Tag(name: name, type: Tag.typeCustom),
            if (original['series'] is String)
              Tag(name: original['series'] as String, type: Tag.typeSeries),
          ];
        }
      }
    } catch (error, stackTrace) {
      AppLogger.instance.error('ScrapeApply', '读取原文分类失败', error, stackTrace);
    }
    final categoryName = resolveCategoryName(tags);
    final folderName = path.basename(game.path);
    final categoryDir = Directory(path.join(sortedPath, categoryName));
    if (!await categoryDir.exists()) {
      await categoryDir.create(recursive: true);
    }
    final targetDir =
        Directory(path.join(sortedPath, categoryName, folderName));
    if (await targetDir.exists()) {
      onLog?.call('目标目录已存在，跳过移动');
      return game;
    }

    final result = await GameMoveService(gameRepository: repo)
        .moveGameFolderCrossDrive(gameId: game.id!, oldPath: game.path,
            newPath: targetDir.path);
    if (result.warning != null) onLog?.call(result.warning!);
    final current = await repo.getStoredGameByPath(targetDir.path) ??
        game.copyWith(path: targetDir.path);
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
      } catch (e, stackTrace) {
        AppLogger.instance
            .error('ScrapeApply', '[ScrapeApply] 自动重命名失败: $e', e, stackTrace);
        onLog?.call('重命名失败: $e');
      }
    }
    if (configs.shouldMove(mode) && current.id != null) {
      // 移动失败仅记日志，不得影响刮削/导入的结果状态（保持各入口现状语义）
      try {
        current = await moveGameToSorted(current, repo, onLog: onLog);
      } catch (e, stackTrace) {
        AppLogger.instance
            .error('ScrapeApply', '[ScrapeApply] 自动移动失败: $e', e, stackTrace);
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
    int maxConcurrency = 3,
    void Function(int current, int total)? onProgress,
    void Function(String message)? onLog,
    void Function(String message)? onTranslationNotice,
    bool requirePersistence = false,
  }) async {
    // 旧布局迁移（根目录 metadata.json/images -> HGMDatas/）必须保留：
    // 现状由详情页 _downloadImagesWithMapping 内部与刮削中心入口承担，
    // 删除详情页私有实现后此处是唯一保障，且该方法幂等。
    requirePersistence = requirePersistence || gameInfo.isDlsiteUserOnly;
    gameInfo.screenshots = gameInfo.screenshots.toSet().toList();
    final elapsed = Stopwatch()..start();
    ScrapeFileSnapshot? snapshot;
    Game? original;
    var dataApplied = false;
    var recordsChanged = false;
    AppLogger.instance.info('ScrapeApply',
        '开始应用结果: mode=${mode.name}, id=${game.id}, images=${gameInfo.screenshots.length}');
    try {
      await GameDataMigrationService(gameRepository: repo)
          .migrateGameDirectory(game.path, gameId: game.id);
      if (requirePersistence) {
        original = await repo.getStoredGameByPath(game.path);
        if (game.id != original?.id) {
          throw StateError('游戏记录已变化，请重新抓取后确认');
        }
        snapshot = await ScrapeFileSnapshot.capture(game.path);
      }

      Map<String, dynamic>? previousMetadata;
      if (gameInfo.isDlsiteUserOnly) {
        final metadataFile = GameDataPaths.metadataFile(game.path);
        if (await metadataFile.exists()) {
          previousMetadata =
              jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
        }
        final dlsite = DlsiteService();
        final nextSource = sourceUrl ?? gameInfo.sourceUrl;
        final nextId = DlsiteService.isDlsiteUrl(nextSource)
            ? dlsite.normalizeId(nextSource)
            : null;
        final previousOriginal = previousMetadata == null
            ? null
            : MetadataTranslationService.originalFrom(previousMetadata);
        for (final previousSource in [
          (original ?? game).sourceUrl,
          previousMetadata?['source_url'],
          previousOriginal?['source_url'],
        ]) {
          if (previousSource is! String ||
              !DlsiteService.isDlsiteUrl(previousSource)) {
            continue;
          }
          final previousId = dlsite.normalizeId(previousSource);
          if (nextId != null && previousId != null && previousId != nextId) {
            throw StateError('新来源对应不同 DLsite 作品，无法沿用已有简介，请先核对作品编号。');
          }
        }
      }
      final baseGame = original ??
          (previousMetadata == null
              ? game
              : gameWithMetadata(game, previousMetadata));
      final imageReplacements = gameInfo.isDlsiteUserOnly &&
              gameInfo.screenshots.isNotEmpty
          ? await _preserveDescriptionImages(baseGame, previousMetadata)
          : <String, String>{};
      if (previousMetadata != null && imageReplacements.isNotEmpty) {
        previousMetadata = jsonDecode(_replacePreservedImageReferences(
            jsonEncode(previousMetadata), imageReplacements)!) as Map<String, dynamic>;
      }
      var merged = mergeGameInfo(baseGame, gameInfo, sourceUrl: sourceUrl);
      if (imageReplacements.isNotEmpty) {
        merged = merged.copyWith(
          intro: _replacePreservedImageReferences(merged.intro, imageReplacements),
          features: _replacePreservedImageReferences(merged.features, imageReplacements),
          changelog: _replacePreservedImageReferences(merged.changelog, imageReplacements),
        );
      }
      int gameId;
      if (game.id != null) {
        await repo.updateScrapedFields(merged);
        gameId = game.id!;
      } else {
        gameId = await repo.insertGame(merged);
      }
      recordsChanged = true;
      var current = merged.copyWith(id: gameId);

      // 文件写入失败不应使整个刮削失败（保持快速刮削现状的容错语义）
      final effectiveSourceUrl = sourceUrl ?? gameInfo.sourceUrl;
      var metadataSaved = false;
      try {
        await GameDataPaths.ensureDataDir(current.path);
        await GameDataPaths.metadataFile(current.path).writeAsString(
            jsonEncode(markScraped(buildMetadataJson(gameInfo,
                intro: gameInfo.isDlsiteUserOnly ? merged.intro : null,
                previousMetadata: previousMetadata))),
            flush: true);
        metadataSaved = true;
      } catch (e, stackTrace) {
        AppLogger.instance.error('ScrapeApply',
            '[ScrapeApply] 写入 metadata.json 失败: $e', e, stackTrace);
        if (requirePersistence) rethrow;
      }
      if (effectiveSourceUrl.isNotEmpty) {
        try {
          await GameDataPaths.sourceUrlFile(current.path)
              .writeAsString(effectiveSourceUrl, flush: true);
        } catch (e, stackTrace) {
          AppLogger.instance.error('ScrapeApply',
              '[ScrapeApply] 写入 source_url.txt 失败: $e', e, stackTrace);
          if (requirePersistence) rethrow;
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
        requireAllImages: requirePersistence,
      );

      current = await repo.getGameById(gameId) ?? current;
      // 批量添加确认后仍保留 Steam 简介中视频的本地化行为。
      if (mode == ScrapeMode.batchAdd &&
          Uri.tryParse(effectiveSourceUrl)?.host == 'store.steampowered.com' &&
          current.intro?.contains('[视频:') == true) {
        var intro = current.intro!;
        final videoMapping = await SteamService()
            .downloadVideosFromDescription(intro, current.path);
        for (final entry in videoMapping.entries) {
          intro = intro.replaceAll('[视频:${entry.key}]', '[视频:${entry.value}]');
        }
        if (intro != current.intro) {
          current = current.copyWith(intro: intro);
          await repo.updateScrapedFields(current);
          final metadataFile = GameDataPaths.metadataFile(current.path);
          final metadata = jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
          metadata['intro'] = intro;
          await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
        }
      }
      if (metadataSaved) {
        current = await translateGameMetadata(
          game: current,
          repo: repo,
          tagRepo: tagRepo,
          onNotice: onTranslationNotice,
          refreshRestrictedPublicFields: gameInfo.isDlsiteUserOnly,
        );
      } else if (MetadataTranslationConfig.fromSettings(await AppSettings.load())
          .enabled) {
        onTranslationNotice?.call('无法保存本次刮削元数据，已跳过翻译');
      }
      final guide = _replacePreservedImageReferences(current.guide, imageReplacements);
      if (guide != current.guide) {
        await repo.updateGuide(gameId, guide);
        current = current.copyWith(guide: guide);
      }
      dataApplied = true;
      current =
          await organizeFolder(current, mode, repo, configs, onLog: onLog);
      AppLogger.instance.info('ScrapeApply',
          '应用结果完成: mode=${mode.name}, id=$gameId, elapsedMs=${elapsed.elapsedMilliseconds}');
      return current;
    } catch (error, stackTrace) {
      if (snapshot != null && !dataApplied) {
        final restoreFailures = <Object>[];
        try {
          await snapshot.restore();
        } catch (restoreError) {
          restoreFailures.add(restoreError);
        }
        try {
          if (recordsChanged) {
            await repo.restoreScrapeSnapshot(gamePath: game.path,
                original: original, metadataOnly: true);
          }
        } catch (restoreError) {
          restoreFailures.add(restoreError);
        }
        if (restoreFailures.isNotEmpty) {
          final recoveryPath = snapshot.backup.path;
          snapshot = null;
          throw ScrapeRecoveryException(recoveryPath, restoreFailures);
        }
      }
      AppLogger.instance.error(
          'ScrapeApply',
          '应用结果失败: mode=${mode.name}, id=${game.id}, elapsedMs=${elapsed.elapsedMilliseconds}',
          error,
          stackTrace);
      rethrow;
    } finally {
      if (snapshot != null) {
        try {
          await snapshot.dispose();
        } catch (error) {
          onLog?.call('临时恢复文件清理失败：${snapshot.backup.path}');
        }
      }
    }
  }

  static Game gameWithMetadata(Game game, Map<String, dynamic> metadata) {
    return game.copyWith(
      title: metadata['title'] is String
          ? stripVersionFromTitle(metadata['title'] as String, game.version)
          : game.title,
      intro: metadata['intro'] as String? ?? game.intro,
      features: metadata['features'] as String? ?? game.features,
      changelog: metadata['changelog'] as String? ?? game.changelog,
    );
  }

  static Future<Game> translateGameMetadata({
    required Game game,
    required GameRepository repo,
    required TagRepository tagRepo,
    void Function(String message)? onNotice,
    bool refreshRestrictedPublicFields = false,
  }) async {
    final settings = await AppSettings.load();
    final config = MetadataTranslationConfig.fromSettings(settings);
    if (!config.enabled || game.id == null) return game;
    final metadataFile = await GameDataPaths.existingMetadataFile(game.path);
    Map<String, dynamic> metadata;
    String originalContent;
    try {
      originalContent = await metadataFile.readAsString();
      metadata = jsonDecode(originalContent) as Map<String, dynamic>;
    } catch (_) {
      onNotice?.call('无法读取游戏元数据，已跳过翻译');
      return game;
    }
    final original = MetadataTranslationService.originalFrom(metadata);
    final translated = refreshRestrictedPublicFields && original != null
        ? await _translateRestrictedPublicFields(
            metadata, original, config, onNotice)
        : await MetadataTranslationService()
            .translate(metadata, config, onNotice: onNotice);
    if (MetadataTranslationService.originalFrom(translated) == null) return game;

    final tempFile = File('${metadataFile.path}.translation.tmp');
    final metadataChanged = !identical(translated, metadata);
    var fileReplaced = false;
    var keepRecoveryFile = false;
    late Game updated;
    try {
      if (metadataChanged) {
        await tempFile.writeAsString(jsonEncode(translated), flush: true);
      }
      final current = await repo.getGameById(game.id!) ?? game;
      updated = gameWithMetadata(current, translated);
      await repo.transaction((transaction) async {
        await repo.updateScrapedFields(updated, executor: transaction);
        await syncTags(
          repo,
          tagRepo,
          game.id!,
          GameInfo(
            sourceUrl: current.sourceUrl ?? '',
            tags: (translated['tags'] as List?)?.cast<String>() ?? [],
            category: translated['series'] as String?,
            maker: current.maker,
          ),
          executor: transaction,
        );
        if (metadataChanged) {
          await tempFile.rename(metadataFile.path);
          fileReplaced = true;
        }
      });
    } catch (error, stackTrace) {
      AppLogger.instance.error('MetadataTranslation',
          '同步翻译结果失败: ${error.runtimeType}', null, stackTrace);
      if (fileReplaced) {
        keepRecoveryFile = true;
        await tempFile.writeAsString(originalContent, flush: true);
        await tempFile.rename(metadataFile.path);
        keepRecoveryFile = false;
      }
      onNotice?.call('翻译结果同步失败，已保留此前数据，可稍后重试');
      return game;
    } finally {
      if (!keepRecoveryFile && await tempFile.exists()) await tempFile.delete();
    }
    return await repo.getGameById(game.id!) ?? updated;
  }

  static Future<Map<String, dynamic>> _translateRestrictedPublicFields(
      Map<String, dynamic> metadata,
      Map<String, dynamic> original,
      MetadataTranslationConfig config,
      void Function(String message)? onNotice) async {
    final publicMetadata = Map<String, dynamic>.from(original)
      ..remove(MetadataTranslationService.metadataKey);
    for (final key in _descriptionKeys) {
      publicMetadata.remove(key);
    }
    final translated = await MetadataTranslationService()
        .translate(publicMetadata, config, onNotice: onNotice);
    if (MetadataTranslationService.originalFrom(translated) == null) {
      return metadata;
    }
    return {
      ...metadata,
      ...translated,
      MetadataTranslationService.metadataKey: {
        ...Map<String, dynamic>.from(
            translated[MetadataTranslationService.metadataKey] as Map),
        'original': original,
      },
    };
  }

  static Future<void> syncTags(
    GameRepository repo,
    TagRepository tagRepo,
    int gameId,
    GameInfo gameInfo, {
    DatabaseExecutor? executor,
  }) async {
    await repo.clearGameTags(gameId, executor: executor);
    if (gameInfo.maker != null && gameInfo.maker!.isNotEmpty) {
      final makerTagId = await tagRepo.insertOrGetTag(
          gameInfo.maker!, Tag.typeCustom, executor: executor);
      await repo.addTagToGame(gameId, makerTagId, executor: executor);
    }
    for (final tagName in gameInfo.tags) {
      final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom,
          executor: executor);
      await repo.addTagToGame(gameId, tagId, executor: executor);
    }
    if (gameInfo.category != null) {
      final tagId = await tagRepo.insertOrGetTag(
          gameInfo.category!, Tag.typeSeries, executor: executor);
      await repo.addTagToGame(gameId, tagId, executor: executor);
    }
    final gameTagNames = [
      ...gameInfo.tags,
      if (gameInfo.category != null) gameInfo.category!,
    ];
    final allTags = await tagRepo.getAllTags(executor: executor);
    for (final existingTag in allTags) {
      final alreadyHas = gameTagNames
          .any((t) => t.toLowerCase() == existingTag.name.toLowerCase());
      if (alreadyHas) continue;
      final isOverlapping = gameTagNames.any((t) =>
          t.toLowerCase().contains(existingTag.name.toLowerCase()) &&
          t.toLowerCase() != existingTag.name.toLowerCase());
      if (isOverlapping) {
        await repo.addTagToGame(gameId, existingTag.id!, executor: executor);
      }
    }
  }

  static Future<void> fixImageUrlsInMetadata(
      Game game, GameRepository repo, {bool requirePersistence = false}) async {
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

      await repo.updateScrapedFields(game.copyWith(intro: intro));
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('ScrapeApply', '[FixImageUrls] Error: $e', e, stackTrace);
      if (requirePersistence) rethrow;
    }
  }
}
