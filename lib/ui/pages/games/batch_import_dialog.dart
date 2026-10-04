import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../../../core/models/models.dart';
import '../../../core/utils/app_settings.dart';
import '../../../core/utils/game_data_paths.dart';
import '../../../core/services/scrape_apply_service.dart';
import '../../../core/repositories/game_repository.dart';
import '../../../core/repositories/tag_repository.dart';
import '../../../core/services/dlsite_service.dart';
import '../../../core/services/game_data_migration_service.dart';
import '../../../core/services/steam_service.dart';
import '../../../core/services/version_check_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dropdown.dart';

/// 批量添加游戏对话框
///
/// 两种用法：
/// - 普通模式：不传 [initialFolderPaths]，用户通过"浏览"选择游戏父目录，
///   扫描其子文件夹生成导入列表；
/// - 拖拽模式：传入 [initialFolderPaths] 直接给定游戏目录列表（可选
///   [presetKeywords] 提供各目录的预设刮削关键词），跳过父目录选择流程。
class BatchImportDialog extends StatefulWidget {
  final VoidCallback onImportComplete;
  final String userFont;

  /// 拖拽模式：直接传入游戏目录列表
  final List<String>? initialFolderPaths;

  /// 拖拽模式：目录 -> 预设刮削关键词（来自拖入的 exe 文件名）
  final Map<String, String>? presetKeywords;

  const BatchImportDialog({
    super.key,
    required this.onImportComplete,
    required this.userFont,
    this.initialFolderPaths,
    this.presetKeywords,
  });

  @override
  State<BatchImportDialog> createState() => _BatchImportDialogState();
}

class _BatchImportDialogState extends State<BatchImportDialog> {
  String? _parentPath;
  List<_BatchGameItem> _items = [];
  bool _scanning = false;
  bool _importing = false;
  bool _importDone = false;
  int _successCount = 0;
  int _failCount = 0;

  /// 是否为拖拽模式（直接传入游戏目录列表，跳过父目录选择）
  bool get _isDragMode =>
      widget.initialFolderPaths != null &&
      widget.initialFolderPaths!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // 拖拽模式：不执行父目录选择流程，直接以传入目录构建导入列表
    if (_isDragMode) {
      _scanning = true;
      _initFromDraggedFolders();
    }
  }

  /// 拖拽模式初始化：以传入目录构建 items 并检测/套用关键词
  Future<void> _initFromDraggedFolders() async {
    try {
      final folderPaths = List<String>.from(widget.initialFolderPaths!);
      // 与原 _pickFolder 中排序方式一致：按目录名小写字母序
      folderPaths.sort((a, b) => path
          .basename(a)
          .toLowerCase()
          .compareTo(path.basename(b).toLowerCase()));

      final items = <_BatchGameItem>[];
      final needDetect = <_BatchGameItem>[];
      for (final folderPath in folderPaths) {
        final item = _BatchGameItem(
            folder: Directory(folderPath), keyword: path.basename(folderPath));
        // 调用方已规范化 key，直接按目录路径匹配预设关键词，
        // 命中则套用并跳过关键词自动检测
        final presets = widget.presetKeywords;
        if (presets != null && presets.containsKey(folderPath)) {
          item.keyword = presets[folderPath]!;
        } else {
          needDetect.add(item);
        }
        items.add(item);
      }

      // 无预设关键词的目录照常自动检测，与 _pickFolder 一致并发执行
      await Future.wait(needDetect.map((item) => _detectKeyword(item)));

      if (mounted) setState(() => _items = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: '选择游戏父目录');
    if (result == null) return;
    if (!mounted) return;
    setState(() {
      _parentPath = result;
      _items = [];
      _scanning = true;
    });
    try {
      final parent = Directory(result);
      final dirs = <Directory>[];
      await for (final entity in parent.list(followLinks: false)) {
        if (entity is Directory) dirs.add(entity);
      }
      dirs.sort((a, b) => path
          .basename(a.path)
          .toLowerCase()
          .compareTo(path.basename(b.path).toLowerCase()));

      final items = <_BatchGameItem>[];
      for (final dir in dirs) {
        final folderName = path.basename(dir.path);
        items.add(_BatchGameItem(folder: dir, keyword: folderName));
      }

      await Future.wait(items.map((item) => _detectKeyword(item)));

      if (mounted) setState(() => _items = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _detectKeyword(_BatchGameItem item) async {
    final exeName = await _findFirstExe(item.folder.path);
    if (exeName != null) {
      item.keyword = exeName.replaceAll('_', ' ');
    }
  }

  Future<String?> _findFirstExe(String folderPath,
      {bool foundAnyExe = false}) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return null;

    final entities = await dir.list().toList();

    for (final entity in entities) {
      if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
        final exeName =
            path.basenameWithoutExtension(entity.path).toLowerCase();
        final isGeneric = kGenericGameNames.any((w) => exeName.contains(w));
        if (!isGeneric) {
          return path.basenameWithoutExtension(entity.path);
        }
        foundAnyExe = true;
      }
    }

    if (foundAnyExe) return null;

    for (final entity in entities) {
      if (entity is Directory) {
        final result =
            await _findFirstExe(entity.path, foundAnyExe: foundAnyExe);
        if (result != null) return result;
      }
    }

    return null;
  }

  Future<void> _startImport() async {
    final selected = _items.where((i) => i.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _importing = true);

    int successCount = 0;
    int failCount = 0;

    final queue = List<_BatchGameItem>.from(selected);
    const workerCount = 3;
    final workers = <Future>[];

    for (int i = 0; i < workerCount; i++) {
      workers.add(_processQueue(queue, () async {
        successCount++;
      }, () {
        failCount++;
      }));
    }

    await Future.wait(workers);

    if (mounted) {
      setState(() {
        _importing = false;
        _importDone = true;
        _successCount = successCount;
        _failCount = failCount;
      });
    }
  }

  Future<void> _processQueue(
    List<_BatchGameItem> queue,
    VoidCallback onSuccess,
    VoidCallback onFail,
  ) async {
    final repo = GameRepository();
    final tagRepo = TagRepository();
    final dlsiteService = DlsiteService();
    final steamService = SteamService();

    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      try {
        if (item.source == _BatchScrapeSource.none) {
          await _importNone(repo, item);
        } else if (item.source == _BatchScrapeSource.steam) {
          await _importSteam(repo, tagRepo, steamService, item);
        } else {
          await _importDlsite(repo, tagRepo, dlsiteService, item);
        }
        await _postImportProcess(repo, item);
        onSuccess();
      } catch (e) {
        item.status = '失败: $e';
        if (mounted) setState(() {});
        onFail();
      }
    }
  }

  Future<void> _postImportProcess(
      GameRepository repo, _BatchGameItem item) async {
    if (item.status != '导入完成') return;
    final initialGame = await repo.getGameByPath(item.folder.path);
    if (initialGame == null) return;

    final configs = await _loadScrapeModeConfigs();

    // 重命名/移动整理逻辑统一走共享层，保持各入口行为一致
    final organized = await ScrapeApplyService.organizeFolder(
        initialGame, ScrapeMode.batchAdd, repo, configs);
    debugPrint('[BatchImport] 整理完成: ${organized.path}');
  }

  Future<void> _importNone(GameRepository repo, _BatchGameItem item) async {
    final folderPath = item.folder.path;
    final existing = await repo.getGameByPath(folderPath);
    if (existing != null) {
      await GameDataMigrationService(gameRepository: repo)
          .migrateGameDirectory(folderPath, gameId: existing.id);
      item.status = '已存在，跳过';
      if (mounted) setState(() {});
      return;
    }

    item.status = '正在导入...';
    if (mounted) setState(() {});
    await GameDataMigrationService(gameRepository: repo)
        .migrateGameDirectory(folderPath);

    String? title;
    String? version;
    String? intro;
    String? sourceUrl;

    final metadataFile = await GameDataPaths.existingMetadataFile(folderPath);
    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        title = map['title'] as String?;
        version = map['version'] as String?;
        intro = map['intro'] as String?;
        sourceUrl = map['source_url'] as String?;
      } catch (e) {
        debugPrint('[GamesPage] 读取metadata.json失败: $e');
      }
    }

    final sourceUrlFile = await GameDataPaths.existingSourceUrlFile(folderPath);
    if (sourceUrl == null && await sourceUrlFile.exists()) {
      try {
        sourceUrl = (await sourceUrlFile.readAsString()).trim();
        if (sourceUrl.isEmpty) sourceUrl = null;
      } catch (e) {
        debugPrint('[GamesPage] 读取source_url.txt失败: $e');
      }
    }

    final game = Game(
      path: folderPath,
      title: title ?? path.basename(folderPath),
      version: version,
      intro: intro,
      sourceUrl: sourceUrl,
    );
    await repo.insertGame(game);

    final imageDir = GameDataPaths.imagesDir(folderPath);
    if (await imageDir.exists()) {
      final imagePaths = <String>[];
      await for (final entity in imageDir.list()) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
            imagePaths.add(entity.path);
          }
        }
      }
      imagePaths.sort();
      if (imagePaths.isNotEmpty) {
        final gameId = await repo.getGameByPath(folderPath);
        if (gameId != null) {
          final images = imagePaths
              .asMap()
              .entries
              .map((e) => GameImage(
                    gameId: gameId.id!,
                    imagePath: e.value,
                    sortOrder: e.key,
                  ))
              .toList();
          await repo.setGameImages(gameId.id!, images);
        }
      }
    }

    item.status = '导入完成';
    item.progress = 1.0;
    if (mounted) setState(() {});
  }

  /// 检测关键词是否为 DLsite ID
  String? _detectDlsiteId(String keyword) {
    final match =
        RegExp(r'(RJ|RE|VJ)\d{4,}', caseSensitive: false).firstMatch(keyword);
    return match?.group(0)?.toUpperCase();
  }

  /// 清理关键词：去除括号内容、版本号等
  String _cleanKeyword(String keyword) {
    var cleaned = keyword;
    // 去除 [] 和 【】 中的内容
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '');
    // 去除版本号 (V1.0.1, v1.02, ver1.0, build123 等)
    cleaned = cleaned.replaceAll(
        RegExp(r'\s*[Vv](?:er(?:sion)?)?\s*\.?\d+(?:[\d.]*\d+)?\s*',
            caseSensitive: false),
        ' ');
    // 去除常见后缀
    cleaned = cleaned.replaceAll(
        RegExp(r'\s*(?:官方中文版|官方中文|中文版|汉化版|汉化|steam|fixed|patch)\s*',
            caseSensitive: false),
        ' ');
    // 清理多余空格
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return cleaned;
  }

  /// 分词并逐步缩短搜索
  Future<List<DlsiteSearchResult>> _searchDlsiteWithFallback(
    DlsiteService dlsiteService,
    String keyword,
    String folderPath,
  ) async {
    // 先用完整关键词搜索
    var results = await dlsiteService.search(keyword);
    if (results.isNotEmpty) return results;

    // 清理关键词
    final cleaned = _cleanKeyword(keyword);
    if (cleaned != keyword && cleaned.isNotEmpty) {
      results = await dlsiteService.search(cleaned);
      if (results.isNotEmpty) return results;
    }

    // 分词逐步缩短
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length <= 1) {
      // 只有一个词，用 searchWithFallback
      return await dlsiteService.searchWithFallback(folderPath);
    }

    // 从少一个词开始，逐步缩短
    for (int i = parts.length - 1; i >= 1; i--) {
      final shortened = parts.sublist(0, i).join(' ');
      if (shortened.isNotEmpty) {
        results = await dlsiteService.search(shortened);
        if (results.isNotEmpty) return results;
      }
    }

    // 所有尝试都失败，用 searchWithFallback
    return await dlsiteService.searchWithFallback(folderPath);
  }

  /// 检测关键词是否为 Steam ID
  String? _detectSteamId(String keyword) {
    // 纯数字
    if (RegExp(r'^\d+$').hasMatch(keyword)) return keyword;
    // Steam URL
    final urlMatch =
        RegExp(r'store\.steampowered\.com/app/(\d+)').firstMatch(keyword);
    return urlMatch?.group(1);
  }

  Future<void> _importSteam(
    GameRepository repo,
    TagRepository tagRepo,
    SteamService steamService,
    _BatchGameItem item,
  ) async {
    final folderPath = item.folder.path;
    final existing = await repo.getGameByPath(folderPath);
    await GameDataMigrationService(gameRepository: repo)
        .migrateGameDirectory(folderPath, gameId: existing?.id);

    item.status = '搜索中...';
    if (mounted) setState(() {});

    // 先检测是否为 Steam ID
    final steamId = _detectSteamId(item.keyword);

    List<SteamSearchResult> results;
    if (steamId != null) {
      // 直接使用 ID
      results = [SteamSearchResult(id: steamId, name: 'ID: $steamId')];
    } else if (item.keyword.isNotEmpty) {
      // 使用关键词搜索
      results = await steamService.search(item.keyword);
      // 如果关键词搜索无结果，使用回退搜索
      if (results.isEmpty) {
        results = await steamService.searchWithFallback(folderPath);
      }
    } else {
      results = await steamService.searchWithFallback(folderPath);
    }

    if (results.isEmpty) {
      item.status = '未找到，按名称导入';
      final game = Game(
        path: folderPath,
        title: path.basename(folderPath),
      );
      if (existing != null) {
        await repo.updateGame(game.copyWith(id: existing.id));
      } else {
        await repo.insertGame(game);
      }
      item.progress = 1.0;
      if (mounted) setState(() {});
      return;
    }

    final searchResult = results.first;
    item.status = '获取信息: ${searchResult.name ?? searchResult.id}';
    if (mounted) setState(() {});

    final gameInfo = await steamService.fetchById(searchResult.id);
    if (gameInfo == null) {
      item.status = '获取失败，按名称导入';
      final game = Game(
        path: folderPath,
        title: path.basename(folderPath),
      );
      if (existing != null) {
        await repo.updateGame(game.copyWith(id: existing.id));
      } else {
        await repo.insertGame(game);
      }
      item.progress = 1.0;
      if (mounted) setState(() {});
      return;
    }

    item.status = '下载图片...';
    item.progress = 0.1;
    if (mounted) setState(() {});

    final urlToLocal = await steamService.downloadAllImages(
      gameInfo.screenshots,
      folderPath,
    );

    item.progress = 0.8;
    if (mounted) setState(() {});

    String? description = gameInfo.description;
    if (description != null && urlToLocal.isNotEmpty) {
      for (final entry in urlToLocal.entries) {
        description =
            description!.replaceAll('[图片:${entry.key}]', '[图片:${entry.value}]');
      }
    }

    if (description != null && description.contains('[视频:')) {
      item.status = '下载视频...';
      if (mounted) setState(() {});
      final videoMap = await steamService.downloadVideosFromDescription(
          description, folderPath);
      for (final entry in videoMap.entries) {
        description =
            description!.replaceAll('[视频:${entry.key}]', '[视频:${entry.value}]');
      }
    }

    item.status = '保存数据...';
    if (mounted) setState(() {});

    final developers = gameInfo.developers;
    final game = Game(
      path: folderPath,
      title: gameInfo.title,
      intro: description,
      sourceUrl: gameInfo.sourceUrl,
      maker: developers.isNotEmpty ? developers.join(', ') : null,
    );

    int gameId;
    if (existing != null) {
      await repo.updateGame(game.copyWith(id: existing.id));
      gameId = existing.id!;
    } else {
      gameId = await repo.insertGame(game);
    }

    await repo.clearGameTags(gameId);
    for (final tagName in gameInfo.tags) {
      final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
      await repo.addTagToGame(gameId, tagId);
    }

    final metadata = <String, dynamic>{
      if (gameInfo.title != null) 'title': gameInfo.title,
      if (description != null) 'intro': description,
      if (gameInfo.tags.isNotEmpty) 'tags': gameInfo.tags,
      'source_url': gameInfo.sourceUrl,
      if (gameInfo.screenshots.isNotEmpty) 'image_urls': gameInfo.screenshots,
    };
    await _saveImagesAndMetadata(
        folderPath, gameId, gameInfo.sourceUrl, metadata, repo);

    item.status = '导入完成';
    item.progress = 1.0;
    if (mounted) setState(() {});
  }

  Future<void> _importDlsite(
    GameRepository repo,
    TagRepository tagRepo,
    DlsiteService dlsiteService,
    _BatchGameItem item,
  ) async {
    final folderPath = item.folder.path;
    final existing = await repo.getGameByPath(folderPath);
    await GameDataMigrationService(gameRepository: repo)
        .migrateGameDirectory(folderPath, gameId: existing?.id);

    item.status = '搜索中...';
    if (mounted) setState(() {});

    // 先检测是否为 DLsite ID
    final dlsiteId = _detectDlsiteId(item.keyword);

    List<DlsiteSearchResult> results;
    if (dlsiteId != null) {
      // 直接使用 ID
      results = [DlsiteSearchResult(id: dlsiteId, name: 'ID: $dlsiteId')];
    } else if (item.keyword.isNotEmpty) {
      // 使用带回退的搜索
      results = await _searchDlsiteWithFallback(
          dlsiteService, item.keyword, folderPath);
    } else {
      results = await dlsiteService.searchWithFallback(folderPath);
    }

    if (results.isEmpty) {
      item.status = '未找到，按名称导入';
      final game = Game(
        path: folderPath,
        title: path.basename(folderPath),
      );
      if (existing != null) {
        await repo.updateGame(game.copyWith(id: existing.id));
      } else {
        await repo.insertGame(game);
      }
      item.progress = 1.0;
      if (mounted) setState(() {});
      return;
    }

    final searchResult = results.first;
    item.status = '获取信息: ${searchResult.name ?? searchResult.id}';
    if (mounted) setState(() {});

    final gameInfo = await dlsiteService.fetchById(searchResult.id);
    if (gameInfo == null) {
      item.status = '获取失败，按名称导入';
      final game = Game(
        path: folderPath,
        title: path.basename(folderPath),
      );
      if (existing != null) {
        await repo.updateGame(game.copyWith(id: existing.id));
      } else {
        await repo.insertGame(game);
      }
      item.progress = 1.0;
      if (mounted) setState(() {});
      return;
    }

    item.status = '下载图片...';
    item.progress = 0.1;
    if (mounted) setState(() {});

    final urlToLocal = await dlsiteService.downloadAllImages(
      gameInfo.screenshots,
      folderPath,
    );

    item.progress = 0.8;
    if (mounted) setState(() {});

    String? description = gameInfo.description;
    if (description != null && urlToLocal.isNotEmpty) {
      description =
          dlsiteService.replaceImageUrlsInDescription(description, urlToLocal);
    }

    item.status = '保存数据...';
    if (mounted) setState(() {});

    final game = Game(
      path: folderPath,
      title: gameInfo.title,
      intro: description,
      sourceUrl: gameInfo.sourceUrl,
      maker: gameInfo.maker,
      makerUrl: gameInfo.makerUrl,
    );

    int gameId;
    if (existing != null) {
      await repo.updateGame(game.copyWith(id: existing.id));
      gameId = existing.id!;
    } else {
      gameId = await repo.insertGame(game);
    }

    await repo.clearGameTags(gameId);
    for (final tagName in gameInfo.tags) {
      final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
      await repo.addTagToGame(gameId, tagId);
    }

    final metadata = gameInfo.toJson();
    if (description != null) metadata['intro'] = description;
    if (metadata['intro_html'] is String && urlToLocal.isNotEmpty) {
      var introHtml = metadata['intro_html'] as String;
      for (final entry in urlToLocal.entries) {
        introHtml = introHtml.replaceAll(entry.key, entry.value);
      }
      metadata['intro_html'] = introHtml;
    }
    await _saveImagesAndMetadata(
        folderPath, gameId, gameInfo.sourceUrl, metadata, repo);

    item.status = '导入完成';
    item.progress = 1.0;
    if (mounted) setState(() {});
  }

  Future<void> _saveImagesAndMetadata(
    String folderPath,
    int gameId,
    String sourceUrl,
    Map<String, dynamic> metadataJson,
    GameRepository repo,
  ) async {
    final imageDir = GameDataPaths.imagesDir(folderPath);
    if (await imageDir.exists()) {
      final imagePaths = <String>[];
      await for (final entity in imageDir.list()) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
            imagePaths.add(entity.path);
          }
        }
      }
      imagePaths.sort();
      if (imagePaths.isNotEmpty) {
        final images = imagePaths
            .asMap()
            .entries
            .map((e) => GameImage(
                  gameId: gameId,
                  imagePath: e.value,
                  sortOrder: e.key,
                ))
            .toList();
        await repo.setGameImages(gameId, images);
      }
    }

    final metadataFile = GameDataPaths.metadataFile(folderPath);
    await GameDataPaths.ensureDataDir(folderPath);
    await metadataFile.writeAsString(jsonEncode(metadataJson), flush: true);

    final sourceUrlFile = GameDataPaths.sourceUrlFile(folderPath);
    await sourceUrlFile.writeAsString(sourceUrl, flush: true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.5,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                // 拖拽模式且仅传入 1 个目录时按单个添加显示标题
                _isDragMode && widget.initialFolderPaths!.length == 1
                    ? '添加游戏'
                    : '批量添加游戏',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextPrimary(context))),
            const SizedBox(height: 16),
            if (_isDragMode)
              // 拖拽模式：文件夹列表由调用方传入，仅展示数量，不提供浏览按钮
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.getSurfaceColor(context)
                      .withValues(alpha: 0.5),
                  borderRadius:
                      BorderRadius.circular(GlassConstants.radiusMedium),
                  border: Border.all(
                      color: AppTheme.getBorderColor(context)
                          .withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '已添加 ${widget.initialFolderPaths!.length} 个游戏文件夹',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.getTextPrimary(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.getSurfaceColor(context)
                            .withValues(alpha: 0.5),
                        borderRadius:
                            BorderRadius.circular(GlassConstants.radiusMedium),
                        border: Border.all(
                            color: AppTheme.getBorderColor(context)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _parentPath ?? '未选择文件夹',
                        style: TextStyle(
                          fontSize: 13,
                          color: _parentPath != null
                              ? AppTheme.getTextPrimary(context)
                              : AppTheme.getTextSecondary(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _scanning || _importing ? null : _pickFolder,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('浏览'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.getPrimaryColor(context),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              '提示: 若要刮削信息，需要游戏在该平台能搜到',
              style: TextStyle(fontSize: 12, color: AppTheme.warningColor),
            ),
            const SizedBox(height: 8),
            if (_scanning)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _parentPath != null ? '未找到子文件夹' : '选择一个包含游戏子文件夹的目录',
                    style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 14),
                  ),
                ),
              )
            else ...[
              Row(
                children: [
                  Text(
                    '找到 ${_items.length} 个文件夹，已选 ${_items.where((i) => i.selected).length} 个',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.getTextSecondary(context)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () {
                            setState(() {
                              final allSelected =
                                  _items.every((i) => i.selected);
                              for (final item in _items) {
                                item.selected = !allSelected;
                              }
                            });
                          },
                    child: Text(
                      _items.every((i) => i.selected) ? '取消全选' : '全选',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.getPrimaryColor(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.getSurfaceColor(context)
                        .withValues(alpha: 0.3),
                    borderRadius:
                        BorderRadius.circular(GlassConstants.radiusMedium),
                    border: Border.all(
                        color: AppTheme.getBorderColor(context)
                            .withValues(alpha: 0.2)),
                  ),
                  child: ListView.builder(
                    itemCount: _importing
                        ? _items.where((i) => i.selected).length
                        : _items.length,
                    itemBuilder: (context, index) {
                      final item = _importing
                          ? _items.where((i) => i.selected).toList()[index]
                          : _items[index];
                      final name = path.basename(item.folder.path);
                      if (_importing) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 100,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        item.source == _BatchScrapeSource.none
                                            ? AppTheme.getTextSecondary(context)
                                                .withValues(alpha: 0.1)
                                            : AppTheme.getPrimaryColor(context)
                                                .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.source == _BatchScrapeSource.none
                                        ? '不刮削'
                                        : item.source ==
                                                _BatchScrapeSource.steam
                                            ? 'Steam'
                                            : 'DLsite',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: item.source ==
                                              _BatchScrapeSource.none
                                          ? AppTheme.getTextSecondary(context)
                                          : AppTheme.primaryColor,
                                      fontFamily: widget.userFont.isNotEmpty
                                          ? widget.userFont
                                          : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 220,
                                child: Text(
                                  name,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.getTextPrimary(context),
                                      fontFamily: widget.userFont.isNotEmpty
                                          ? widget.userFont
                                          : null),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        item.status,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.getTextSecondary(
                                                context),
                                            fontFamily:
                                                widget.userFont.isNotEmpty
                                                    ? widget.userFont
                                                    : null),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (item.progress > 0) ...[
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 200,
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          child: LinearProgressIndicator(
                                            value: item.progress,
                                            backgroundColor:
                                                AppTheme.getTextSecondary(
                                                        context)
                                                    .withValues(alpha: 0.1),
                                            valueColor: AlwaysStoppedAnimation(
                                              item.progress >= 1.0
                                                  ? AppTheme.successColor
                                                  : AppTheme.primaryColor,
                                            ),
                                            minHeight: 6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Row(
                          children: [
                            Checkbox(
                              value: item.selected,
                              onChanged: _importing
                                  ? null
                                  : (checked) {
                                      setState(() =>
                                          item.selected = checked ?? false);
                                    },
                              activeColor: AppTheme.primaryColor,
                              visualDensity:
                                  VisualDensity(horizontal: -4, vertical: -4),
                            ),
                            AppDropdown<_BatchScrapeSource>(
                              value: item.source,
                              width: 80,
                              isExpanded: true,
                              isDense: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              textStyle: TextStyle(
                                fontSize: 12,
                                color: AppTheme.getTextPrimary(context),
                                fontFamily: widget.userFont.isNotEmpty
                                    ? widget.userFont
                                    : null,
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: _BatchScrapeSource.none,
                                    child: Text('不刮削')),
                                DropdownMenuItem(
                                    value: _BatchScrapeSource.steam,
                                    child: Text('Steam')),
                                DropdownMenuItem(
                                    value: _BatchScrapeSource.dlsite,
                                    child: Text('DLsite')),
                              ],
                              onChanged: _importing
                                  ? null
                                  : (val) {
                                      if (val != null)
                                        setState(() => item.source = val);
                                    },
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 220,
                              child: Text(
                                name,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.getTextPrimary(context),
                                    fontFamily: widget.userFont.isNotEmpty
                                        ? widget.userFont
                                        : null),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.keyword,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: widget.userFont.isNotEmpty
                                        ? widget.userFont
                                        : null),
                                decoration: InputDecoration(
                                  hintText: '搜索关键词',
                                  hintStyle: TextStyle(
                                      fontSize: 12,
                                      color:
                                          AppTheme.getTextSecondary(context)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(
                                        color:
                                            AppTheme.getTextSecondary(context)
                                                .withValues(alpha: 0.3)),
                                  ),
                                  isDense: true,
                                ),
                                onChanged: (val) => item.keyword = val,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_importDone) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _failCount > 0
                      ? AppTheme.warningColor.withValues(alpha: 0.1)
                      : AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(GlassConstants.radiusSmall),
                  border: Border.all(
                    color: _failCount > 0
                        ? AppTheme.warningColor.withValues(alpha: 0.3)
                        : AppTheme.successColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _failCount > 0
                          ? Icons.warning_amber
                          : Icons.check_circle_outline,
                      color: _failCount > 0
                          ? AppTheme.warningColor
                          : AppTheme.successColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _failCount > 0
                          ? '导入完成: $_successCount 成功, $_failCount 失败'
                          : '成功导入 $_successCount 个游戏',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _failCount > 0
                            ? AppTheme.warningColor
                            : AppTheme.successColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onImportComplete();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('确认'),
                  ),
                ],
              ),
            ] else ...[
              if (_importing)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      '请不要退出该页面',
                      style:
                          TextStyle(fontSize: 13, color: AppTheme.warningColor),
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _importing ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _items.isEmpty ||
                            _importing ||
                            !_items.any((i) => i.selected)
                        ? null
                        : _startImport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.primaryColor.withValues(alpha: 0.4),
                    ),
                    child: _importing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.getTextColorOnPrimary(context)))
                        : Text(
                            '导入 (${_items.where((i) => i.selected).length})'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _BatchScrapeSource { none, steam, dlsite }

class _BatchGameItem {
  final Directory folder;
  String keyword;
  _BatchScrapeSource source;
  String status;
  double progress;
  bool selected;

  _BatchGameItem({
    required this.folder,
    required this.keyword,
  })  : source = _BatchScrapeSource.steam,
        status = '',
        progress = 0.0,
        selected = true;
}

// 刮削整理配置加载：缺失或解析失败时回退默认配置，整理开关由共享层自行判断
Future<ScrapeModeConfigs> _loadScrapeModeConfigs() async {
  final settings = await AppSettings.load();
  final jsonStr = settings.getString(AppSettings.scrapeModeConfigsKey);
  if (jsonStr == null || jsonStr.isEmpty) return ScrapeModeConfigs.defaults();
  try {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return ScrapeModeConfigs.fromMap(map);
  } catch (_) {
    return ScrapeModeConfigs.defaults();
  }
}
