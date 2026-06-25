import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/repositories/game_repository.dart';
import '../../../core/repositories/tag_repository.dart';
import '../../../core/services/dlsite_service.dart';
import '../../../core/services/steam_service.dart';
import '../../../core/services/version_check_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';
import '../categories/tag_games_page.dart';

class GamesPage extends ConsumerStatefulWidget {
  const GamesPage({super.key});

  @override
  ConsumerState<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends ConsumerState<GamesPage> {
  bool _isRefreshing = false;
  String _refreshProgress = '';

  @override
  Widget build(BuildContext context) {
    final gamesAsync = ref.watch(allGamesProvider);
    return Column(
      children: [
        GlassAppBar(
          title: const Text('游戏库',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              icon: Icon(Icons.add_circle_outline,
                  color: AppTheme.primaryColor, size: 20),
              tooltip: '添加单个游戏',
              onPressed: () => _showCloudImportDialog(),
            ),
            IconButton(
              icon: Icon(Icons.create_new_folder_outlined,
                  color: AppTheme.primaryColor, size: 20),
              tooltip: '批量添加游戏',
              onPressed: () => _showAddGameDialog(),
            ),
            _isRefreshing
                ? GestureDetector(
                    onTap: null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _refreshProgress.isNotEmpty ? _refreshProgress : '扫描中',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.refresh, size: 20),
                    tooltip: '刷新',
                    onPressed: () async {
                      setState(() => _isRefreshing = true);
                      try {
                        final prefs = ref.read(sharedPreferencesProvider);
                        final rawLib = prefs.getString('library_path') ?? '';

                        List<String> libraryPaths;
                        if (rawLib.startsWith('[')) {
                          try {
                            final List<dynamic> list = jsonDecode(rawLib);
                            libraryPaths = list.whereType<String>().where((s) => s.isNotEmpty).toList();
                          } catch (_) {
                            libraryPaths = rawLib.isNotEmpty ? [rawLib] : [];
                          }
                        } else {
                          libraryPaths = rawLib.isNotEmpty ? [rawLib] : [];
                        }

                        final rawSorted = prefs.getString('sorted_paths') ?? '';
                        if (rawSorted.startsWith('{')) {
                          try {
                            final decoded = jsonDecode(rawSorted) as Map<String, dynamic>;
                            for (final v in decoded.values) {
                              final sp = v?.toString() ?? '';
                              if (sp.isNotEmpty && !libraryPaths.contains(sp)) {
                                libraryPaths.add(sp);
                              }
                            }
                          } catch (_) {}
                        }

                        if (libraryPaths.isEmpty) {
                          if (mounted) {
                            AppTheme.showGlassToast(context, message: '请先在设置中配置游戏库路径', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
                          }
                          return;
                        }

                        final scanner = ref.read(gameScannerServiceProvider);
                        final ignoreStr = prefs.getString('scan_ignore_folders') ?? '';
                        final ignoreFolders = ignoreStr.split(',').where((s) => s.trim().isNotEmpty).toList();
                        final blacklistStr = prefs.getString('game_blacklist') ?? '';
                        final blacklistPaths = blacklistStr.split('\n').where((s) => s.trim().isNotEmpty).toList();

                        scanner.onProgress = (processed, total) {
                          if (mounted) {
                            setState(() => _refreshProgress = '$processed/$total');
                          }
                        };

                        await scanner.scanMultipleLibraries(libraryPaths, ignoreFolders: ignoreFolders, blacklistPaths: blacklistPaths);

                        ref.invalidate(allGamesProvider);
                        ref.invalidate(favoriteGamesProvider);
                        ref.invalidate(playedGamesProvider);
                      } catch (e) {
                        if (mounted) {
                          AppTheme.showGlassToast(context, message: '扫描失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
                        }
                      } finally {
                        setState(() {
                          _isRefreshing = false;
                          _refreshProgress = '';
                        });
                      }
                    },
                  ),
          ],
        ),
        Expanded(
          child: gamesAsync.when(
            data: (games) => GameListWidget(
              games: games,
              showSearchBar: true,
              routeIndex: 1,
              onTagTap: (tag) {
                Navigator.of(context)
                    .push(MaterialPageRoute(
                        builder: (_) => TagGamesPage(
                            tagId: tag.id!, tagName: tag.name)))
                    .then((_) {
                  if (mounted) ref.invalidate(allGamesProvider);
                });
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
          ),
        ),
      ],
    );
  }

  Future<void> _rescanImages(
      GameRepository repo, int gameId, Directory imageDir) async {
    final imagePaths = <String>[];
    await for (final entity in imageDir.list(followLinks: false)) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
          imagePaths.add(entity.path);
        }
      }
    }
    imagePaths.sort();
    if (imagePaths.isNotEmpty) {
      final images = imagePaths.asMap().entries.map((e) => GameImage(
            gameId: gameId,
            imagePath: e.value,
            sortOrder: e.key,
          )).toList();
      await repo.setGameImages(gameId, images);
    }
  }

  void _showAddGameDialog() {
    final prefs = ref.read(sharedPreferencesProvider);
    final userFont = prefs.getString('font_family') ?? '';
    showGlassDialog(
      context: context,
      child: _BatchImportDialog(
        onImportComplete: () {
          ref.invalidate(allGamesProvider);
        },
        userFont: userFont,
      ),
    );
  }

  void _showCloudImportDialog() {
    showGlassDialog(
      context: context,
      child: _CloudImportDialog(
        onImportComplete: () {
          ref.invalidate(allGamesProvider);
        },
      ),
    );
  }
}

class _BatchImportDialog extends StatefulWidget {
  final VoidCallback onImportComplete;
  final String userFont;

  const _BatchImportDialog({required this.onImportComplete, required this.userFont});

  @override
  State<_BatchImportDialog> createState() => _BatchImportDialogState();
}

class _BatchImportDialogState extends State<_BatchImportDialog> {
  String? _parentPath;
  List<_BatchGameItem> _items = [];
  bool _scanning = false;
  bool _importing = false;
  bool _importDone = false;
  int _successCount = 0;
  int _failCount = 0;

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: '选择游戏父目录');
    if (result == null) return;
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
      dirs.sort((a, b) => path.basename(a.path).toLowerCase().compareTo(path.basename(b.path).toLowerCase()));

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

  Future<String?> _findFirstExe(String folderPath, {bool foundAnyExe = false}) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return null;

    final entities = await dir.list().toList();

    for (final entity in entities) {
      if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
        final exeName = path.basenameWithoutExtension(entity.path).toLowerCase();
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
        final result = await _findFirstExe(entity.path, foundAnyExe: foundAnyExe);
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
        onSuccess();
      } catch (e) {
        item.status = '失败: $e';
        if (mounted) setState(() {});
        onFail();
      }
    }
  }

  Future<void> _importNone(GameRepository repo, _BatchGameItem item) async {
    final folderPath = item.folder.path;
    final existing = await repo.getGameByPath(folderPath);
    if (existing != null) {
      item.status = '已存在，跳过';
      if (mounted) setState(() {});
      return;
    }

    item.status = '正在导入...';
    if (mounted) setState(() {});

    String? title;
    String? version;
    String? intro;
    String? sourceUrl;

    final metadataFile = File(path.join(folderPath, 'metadata.json'));
    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        title = map['title'] as String?;
        version = map['version'] as String?;
        intro = map['intro'] as String?;
        sourceUrl = map['source_url'] as String?;
      } catch (_) {}
    }

    final sourceUrlFile = File(path.join(folderPath, 'source_url.txt'));
    if (sourceUrl == null && await sourceUrlFile.exists()) {
      try {
        sourceUrl = (await sourceUrlFile.readAsString()).trim();
        if (sourceUrl.isEmpty) sourceUrl = null;
      } catch (_) {}
    }

    final game = Game(
      path: folderPath,
      title: title ?? path.basename(folderPath),
      version: version,
      intro: intro,
      sourceUrl: sourceUrl,
    );
    await repo.insertGame(game);

    final imageDir = Directory(path.join(folderPath, 'images'));
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
          final images = imagePaths.asMap().entries.map((e) => GameImage(
            gameId: gameId.id!,
            imagePath: e.value,
            sortOrder: e.key,
          )).toList();
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
    final match = RegExp(r'(RJ|RE|VJ)\d{4,}', caseSensitive: false).firstMatch(keyword);
    return match?.group(0)?.toUpperCase();
  }

  /// 清理关键词：去除括号内容、版本号等
  String _cleanKeyword(String keyword) {
    var cleaned = keyword;
    // 去除 [] 和 【】 中的内容
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '');
    // 去除版本号 (V1.0.1, v1.02, ver1.0, build123 等)
    cleaned = cleaned.replaceAll(RegExp(r'\s*[Vv](?:er(?:sion)?)?\s*\.?\d+(?:[\d.]*\d+)?\s*', caseSensitive: false), ' ');
    // 去除常见后缀
    cleaned = cleaned.replaceAll(RegExp(r'\s*(?:官方中文版|官方中文|中文版|汉化版|汉化|steam|fixed|patch)\s*', caseSensitive: false), ' ');
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
    final urlMatch = RegExp(r'store\.steampowered\.com/app/(\d+)').firstMatch(keyword);
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
        description = description!.replaceAll('[图片:${entry.key}]', '[图片:${entry.value}]');
      }
    }

    if (description != null && description.contains('[视频:')) {
      item.status = '下载视频...';
      if (mounted) setState(() {});
      final videoMap = await steamService.downloadVideosFromDescription(description, folderPath);
      for (final entry in videoMap.entries) {
        description = description!.replaceAll('[视频:${entry.key}]', '[视频:${entry.value}]');
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

    for (final tagName in gameInfo.tags) {
      final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
      await repo.addTagToGame(gameId, tagId);
    }

    final metadata = <String, dynamic>{
      if (gameInfo.title != null) 'title': gameInfo.title,
      if (gameInfo.description != null) 'intro': gameInfo.description,
      if (gameInfo.tags.isNotEmpty) 'tags': gameInfo.tags,
      'source_url': gameInfo.sourceUrl,
      if (gameInfo.screenshots.isNotEmpty) 'image_urls': gameInfo.screenshots,
    };
    await _saveImagesAndMetadata(folderPath, gameId, gameInfo.sourceUrl, metadata, repo);

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
      results = await _searchDlsiteWithFallback(dlsiteService, item.keyword, folderPath);
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
      description = dlsiteService.replaceImageUrlsInDescription(description, urlToLocal);
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

    for (final tagName in gameInfo.tags) {
      final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
      await repo.addTagToGame(gameId, tagId);
    }

    await _saveImagesAndMetadata(folderPath, gameId, gameInfo.sourceUrl, gameInfo.toJson(), repo);

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
    final imageDir = Directory(path.join(folderPath, 'images'));
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
        final images = imagePaths.asMap().entries.map((e) => GameImage(
          gameId: gameId,
          imagePath: e.value,
          sortOrder: e.key,
        )).toList();
        await repo.setGameImages(gameId, images);
      }
    }

    final metadataFile = File(path.join(folderPath, 'metadata.json'));
    await metadataFile.writeAsString(jsonEncode(metadataJson), flush: true);

    final sourceUrlFile = File(path.join(folderPath, 'source_url.txt'));
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
            Text('批量添加游戏', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                      border: Border.all(color: AppTheme.getTextSecondary(context).withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _parentPath ?? '未选择文件夹',
                      style: TextStyle(
                        fontSize: 13,
                        color: _parentPath != null ? AppTheme.getTextPrimary(context) : AppTheme.getTextSecondary(context),
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
                    backgroundColor: AppTheme.primaryColor,
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
                    style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 14),
                  ),
                ),
              )
            else ...[
              Row(
                children: [
                  Text(
                    '找到 ${_items.length} 个文件夹，已选 ${_items.where((i) => i.selected).length} 个',
                    style: TextStyle(fontSize: 13, color: AppTheme.getTextSecondary(context)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () {
                            setState(() {
                              final allSelected = _items.every((i) => i.selected);
                              for (final item in _items) {
                                item.selected = !allSelected;
                              }
                            });
                          },
                    child: Text(
                      _items.every((i) => i.selected) ? '取消全选' : '全选',
                      style: TextStyle(fontSize: 13, color: AppTheme.primaryColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                    border: Border.all(color: AppTheme.getTextSecondary(context).withValues(alpha: 0.15)),
                  ),
                  child: ListView.builder(
                    itemCount: _importing ? _items.where((i) => i.selected).length : _items.length,
                    itemBuilder: (context, index) {
                      final item = _importing ? _items.where((i) => i.selected).toList()[index] : _items[index];
                      final name = path.basename(item.folder.path);
                      if (_importing) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 100,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: item.source == _BatchScrapeSource.none
                                        ? AppTheme.getTextSecondary(context).withValues(alpha: 0.1)
                                        : AppTheme.primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.source == _BatchScrapeSource.none
                                        ? '不刮削'
                                        : item.source == _BatchScrapeSource.steam
                                            ? 'Steam'
                                            : 'DLsite',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: item.source == _BatchScrapeSource.none
                                          ? AppTheme.getTextSecondary(context)
                                          : AppTheme.primaryColor,
                                      fontFamily: widget.userFont.isNotEmpty ? widget.userFont : null,
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
                                  style: TextStyle(fontSize: 13, color: AppTheme.getTextPrimary(context), fontFamily: widget.userFont.isNotEmpty ? widget.userFont : null),
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
                                        style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context), fontFamily: widget.userFont.isNotEmpty ? widget.userFont : null),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (item.progress > 0) ...[
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 200,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(3),
                                          child: LinearProgressIndicator(
                                            value: item.progress,
                                            backgroundColor: AppTheme.getTextSecondary(context).withValues(alpha: 0.1),
                                            valueColor: AlwaysStoppedAnimation(
                                              item.progress >= 1.0 ? AppTheme.successColor : AppTheme.primaryColor,
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Row(
                          children: [
                            Checkbox(
                              value: item.selected,
                              onChanged: _importing
                                  ? null
                                  : (checked) {
                                      setState(() => item.selected = checked ?? false);
                                    },
                              activeColor: AppTheme.primaryColor,
                              visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                            ),
                            Container(
                              width: 80,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
                                border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.5)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<_BatchScrapeSource>(
                                  value: item.source,
                                  isExpanded: true,
                                  isDense: true,
                                  icon: Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.getTextSecondary(context)),
                                  borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
                                  dropdownColor: AppTheme.surfaceColor,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.getTextPrimary(context),
                                    fontFamily: widget.userFont.isNotEmpty ? widget.userFont : null,
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: _BatchScrapeSource.none, child: Text('不刮削')),
                                    DropdownMenuItem(value: _BatchScrapeSource.steam, child: Text('Steam')),
                                    DropdownMenuItem(value: _BatchScrapeSource.dlsite, child: Text('DLsite')),
                                  ],
                                  onChanged: _importing
                                      ? null
                                      : (val) {
                                          if (val != null) setState(() => item.source = val);
                                        },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 220,
                              child: Text(
                                name,
                                style: TextStyle(fontSize: 13, color: AppTheme.getTextPrimary(context), fontFamily: widget.userFont.isNotEmpty ? widget.userFont : null),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: TextEditingController(text: item.keyword),
                                style: TextStyle(fontSize: 13, fontFamily: widget.userFont.isNotEmpty ? widget.userFont : null),
                                decoration: InputDecoration(
                                  hintText: '搜索关键词',
                                  hintStyle: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide(color: AppTheme.getTextSecondary(context).withValues(alpha: 0.3)),
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
                  borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
                  border: Border.all(
                    color: _failCount > 0
                        ? AppTheme.warningColor.withValues(alpha: 0.3)
                        : AppTheme.successColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _failCount > 0 ? Icons.warning_amber : Icons.check_circle_outline,
                      color: _failCount > 0 ? AppTheme.warningColor : AppTheme.successColor,
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
                        color: _failCount > 0 ? AppTheme.warningColor : AppTheme.successColor,
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
                      style: TextStyle(fontSize: 13, color: AppTheme.warningColor),
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _importing ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _items.isEmpty || _importing || !_items.any((i) => i.selected) ? null : _startImport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.4),
                    ),
                    child: _importing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('导入 (${_items.where((i) => i.selected).length})'),
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

enum ImportSource { none, dlsite, steam }

class _CloudImportDialog extends StatefulWidget {
  final VoidCallback onImportComplete;

  const _CloudImportDialog({required this.onImportComplete});

  @override
  State<_CloudImportDialog> createState() => _CloudImportDialogState();
}

class _CloudImportDialogState extends State<_CloudImportDialog> {
  ImportSource _source = ImportSource.dlsite;
  final _dlsiteService = DlsiteService();
  final _steamService = SteamService();
  final _idController = TextEditingController();
  String? _folderPath;
  bool _isLoading = false;
  String _statusText = '';
  List<dynamic> _searchResults = [];
  dynamic _selectedResult;
  bool _showSearchResults = false;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: '选择游戏文件夹');
    if (result != null) {
      setState(() {
        _folderPath = result;
        _searchResults = [];
        _selectedResult = null;
        _showSearchResults = false;
      });
    }
  }

  Future<void> _searchGame() async {
    if (_folderPath == null) {
      AppTheme.showGlassToast(
        context,
        message: '请先选择游戏文件夹',
        icon: Icons.warning_amber,
        iconColor: AppTheme.warningColor,
      );
      return;
    }

    if (_source == ImportSource.none) {
      await _importNone();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusText = '正在搜索...';
      _searchResults = [];
      _selectedResult = null;
    });

    try {
      if (_source == ImportSource.dlsite) {
        await _searchDlsite();
      } else {
        await _searchSteam();
      }
    } catch (e) {
      setState(() => _statusText = '搜索失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _importNone() async {
    if (_folderPath == null) {
      AppTheme.showGlassToast(
        context,
        message: '请先选择游戏文件夹',
        icon: Icons.warning_amber,
        iconColor: AppTheme.warningColor,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusText = '正在导入...';
    });

    try {
      final repo = GameRepository();
      final existingGame = await repo.getGameByPath(_folderPath!);

      String? title;
      String? version;
      String? intro;
      String? sourceUrl;

      final metadataFile = File(path.join(_folderPath!, 'metadata.json'));
      if (await metadataFile.exists()) {
        try {
          final content = await metadataFile.readAsString();
          final map = jsonDecode(content) as Map<String, dynamic>;
          title = map['title'] as String?;
          version = map['version'] as String?;
          intro = map['intro'] as String?;
          sourceUrl = map['source_url'] as String?;
        } catch (_) {}
      }

      final sourceUrlFile = File(path.join(_folderPath!, 'source_url.txt'));
      if (sourceUrl == null && await sourceUrlFile.exists()) {
        try {
          sourceUrl = (await sourceUrlFile.readAsString()).trim();
          if (sourceUrl.isEmpty) sourceUrl = null;
        } catch (_) {}
      }

      final game = Game(
        path: _folderPath!,
        title: title ?? path.basename(_folderPath!),
        version: version,
        intro: intro,
        sourceUrl: sourceUrl,
      );

      if (existingGame != null) {
        await repo.updateGame(game.copyWith(id: existingGame.id));
      } else {
        await repo.insertGame(game);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onImportComplete();
        AppTheme.showGlassToast(
          context,
          message: existingGame != null ? '游戏信息已更新' : '游戏导入成功',
          icon: Icons.check_circle_outline,
          iconColor: AppTheme.successColor,
        );
      }
    } catch (e) {
      setState(() => _statusText = '导入失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _searchDlsite() async {
    List<DlsiteSearchResult> results;
    final inputText = _idController.text.trim();
    if (inputText.isNotEmpty) {
      // 用户输入了内容
      final normalizedId = _dlsiteService.normalizeId(inputText);
      if (normalizedId != null) {
        // 输入的是ID，直接使用
        results = [DlsiteSearchResult(id: normalizedId, name: 'ID: $normalizedId')];
      } else {
        // 输入的不是ID，当作关键词搜索
        results = await _dlsiteService.searchWithKeyword(inputText);
      }
    } else {
      // 未输入，从文件夹名提取并搜索
      results = await _dlsiteService.searchWithFallback(_folderPath!);
    }

    setState(() {
      _searchResults = results;
      _showSearchResults = true;
      if (results.isEmpty) {
        _statusText = '未找到游戏，请尝试手动输入ID或关键词';
      } else {
        _statusText = '找到 ${results.length} 个结果，请选择';
      }
    });
  }

  Future<void> _searchSteam() async {
    List<SteamSearchResult> results;
    final rawInput = _idController.text.trim();
    if (rawInput.isNotEmpty) {
      final parsedId = _parseSteamId(rawInput);
      if (parsedId == null) {
        setState(() => _statusText = '无效的Steam App ID');
        return;
      }
      results = [SteamSearchResult(id: parsedId, name: 'ID: $parsedId')];
    } else {
      results = await _steamService.searchWithFallback(_folderPath!);
    }

    setState(() {
      _searchResults = results;
      _showSearchResults = true;
      if (results.isEmpty) {
        _statusText = '未找到游戏，请尝试手动输入Steam App ID';
      } else {
        _statusText = '找到 ${results.length} 个结果，请选择';
      }
    });
  }

  /// Parse Steam App ID from raw input.
  /// Accepts: pure numeric ID, or Steam store URL like
  /// https://store.steampowered.com/app/413150/Stardew_Valley/
  static String? _parseSteamId(String input) {
    final urlMatch = RegExp(r'store\.steampowered\.com/app/(\d+)').firstMatch(input);
    if (urlMatch != null) return urlMatch.group(1);
    if (RegExp(r'^\d+$').hasMatch(input)) return input;
    return null;
  }

  Future<void> _import() async {
    if (_folderPath == null || _selectedResult == null) {
      AppTheme.showGlassToast(
        context,
        message: '请选择游戏文件夹和搜索结果',
        icon: Icons.warning_amber,
        iconColor: AppTheme.warningColor,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusText = '正在获取游戏信息...';
    });

    try {
      if (_source == ImportSource.dlsite) {
        await _importDlsite();
      } else {
        await _importSteam();
      }
    } catch (e) {
      setState(() => _statusText = '导入失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _importDlsite() async {
    final repo = GameRepository();
    final tagRepo = TagRepository();
    final existingGame = await repo.getGameByPath(_folderPath!);

    setState(() => _statusText = '正在通过ID获取: ${_selectedResult.id}');
    final gameInfo = await _dlsiteService.fetchById(_selectedResult.id);

    if (gameInfo == null) {
      setState(() => _statusText = '获取游戏信息失败');
      return;
    }

    setState(() => _statusText = '正在下载图片...');
    final urlToLocal = await _dlsiteService.downloadAllImages(
      gameInfo.screenshots,
      _folderPath!,
    );

    String? description = gameInfo.description;
    if (description != null && urlToLocal.isNotEmpty) {
      description = _dlsiteService.replaceImageUrlsInDescription(description, urlToLocal);
    }

    setState(() => _statusText = '正在保存数据...');

    final game = Game(
      path: _folderPath!,
      title: gameInfo.title,
      intro: description,
      sourceUrl: gameInfo.sourceUrl,
      maker: gameInfo.maker,
      makerUrl: gameInfo.makerUrl,
    );

    int gameId;
    if (existingGame != null) {
      await repo.updateGame(game.copyWith(id: existingGame.id));
      gameId = existingGame.id!;
    } else {
      gameId = await repo.insertGame(game);
    }

    for (final tagName in gameInfo.tags) {
      final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
      await repo.addTagToGame(gameId, tagId);
    }

    await _saveImagesAndMetadata(gameId, gameInfo.sourceUrl, gameInfo.toJson());

    if (mounted) {
      Navigator.of(context).pop();
      widget.onImportComplete();
      AppTheme.showGlassToast(
        context,
        message: existingGame != null ? '游戏信息已更新' : '游戏导入成功',
        icon: Icons.check_circle_outline,
        iconColor: AppTheme.successColor,
      );
    }
  }

  Future<void> _importSteam() async {
    final repo = GameRepository();
    final tagRepo = TagRepository();
    final existingGame = await repo.getGameByPath(_folderPath!);

    setState(() => _statusText = '正在通过ID获取: ${_selectedResult.id}');
    final gameInfo = await _steamService.fetchById(_selectedResult.id);

    if (gameInfo == null) {
      setState(() => _statusText = '获取游戏信息失败');
      return;
    }

    setState(() => _statusText = '正在下载图片...');
    final urlToLocal = await _steamService.downloadAllImages(
      gameInfo.screenshots,
      _folderPath!,
    );

    String? description = gameInfo.description;
    if (description != null && urlToLocal.isNotEmpty) {
      for (final entry in urlToLocal.entries) {
        description = description!.replaceAll('[图片:${entry.key}]', '[图片:${entry.value}]');
      }
    }

    // Download videos embedded in description
    if (description != null && description.contains('[视频:')) {
      setState(() => _statusText = '正在下载视频...');
      final videoMap = await _steamService.downloadVideosFromDescription(
        description,
        _folderPath!,
      );
      for (final entry in videoMap.entries) {
        description = description!.replaceAll('[视频:${entry.key}]', '[视频:${entry.value}]');
      }
    }

    setState(() => _statusText = '正在保存数据...');

    final developers = gameInfo.developers;
    final game = Game(
      path: _folderPath!,
      title: gameInfo.title,
      intro: description,
      sourceUrl: gameInfo.sourceUrl,
      maker: developers.isNotEmpty ? developers.join(', ') : null,
    );

    int gameId;
    if (existingGame != null) {
      await repo.updateGame(game.copyWith(id: existingGame.id));
      gameId = existingGame.id!;
    } else {
      gameId = await repo.insertGame(game);
    }

    for (final tagName in gameInfo.tags) {
      final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
      await repo.addTagToGame(gameId, tagId);
    }

    final metadata = <String, dynamic>{
      if (gameInfo.title != null) 'title': gameInfo.title,
      if (gameInfo.description != null) 'intro': gameInfo.description,
      if (gameInfo.tags.isNotEmpty) 'tags': gameInfo.tags,
      'source_url': gameInfo.sourceUrl,
      if (gameInfo.screenshots.isNotEmpty) 'image_urls': gameInfo.screenshots,
    };
    await _saveImagesAndMetadata(gameId, gameInfo.sourceUrl, metadata);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onImportComplete();
      AppTheme.showGlassToast(
        context,
        message: existingGame != null ? '游戏信息已更新' : '游戏导入成功',
        icon: Icons.check_circle_outline,
        iconColor: AppTheme.successColor,
      );
    }
  }

  Future<void> _saveImagesAndMetadata(int gameId, String sourceUrl, Map<String, dynamic> metadataJson) async {
    final imageDir = Directory(path.join(_folderPath!, 'images'));
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
        final images = imagePaths.asMap().entries.map((e) => GameImage(
          gameId: gameId,
          imagePath: e.value,
          sortOrder: e.key,
        )).toList();
        await GameRepository().setGameImages(gameId, images);
      }
    }

    final metadataFile = File(path.join(_folderPath!, 'metadata.json'));
    await metadataFile.writeAsString(jsonEncode(metadataJson), flush: true);

    final sourceUrlFile = File(path.join(_folderPath!, 'source_url.txt'));
    await sourceUrlFile.writeAsString(sourceUrl, flush: true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.5,
        height: _showSearchResults ? 600 : 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '添加单个游戏',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            const SizedBox(height: 16),

            // Source selector
            Row(
              children: [
                _buildSourceChip(ImportSource.none, '不刮削'),
                const SizedBox(width: 8),
                _buildSourceChip(ImportSource.dlsite, 'DLsite'),
                const SizedBox(width: 8),
                _buildSourceChip(ImportSource.steam, 'Steam'),
              ],
            ),
            const SizedBox(height: 8),
            if (_source != ImportSource.none)
              Text(
                '提示: 若要刮削信息，需要游戏在该平台能搜到',
                style: TextStyle(fontSize: 12, color: AppTheme.warningColor),
              ),
            const SizedBox(height: 8),

            // Folder picker
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                      border: Border.all(color: AppTheme.getTextSecondary(context).withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _folderPath ?? '未选择文件夹',
                      style: TextStyle(
                        fontSize: 13,
                        color: _folderPath != null ? AppTheme.getTextPrimary(context) : AppTheme.getTextSecondary(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _pickFolder,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('浏览'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ID input - hidden when no scrape
            if (_source != ImportSource.none) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _idController,
                      decoration: InputDecoration(
                        hintText: _source == ImportSource.dlsite
                            ? '输入DLsite ID (如 RJ123456)，留空则自动按游戏名称搜索'
                            : '输入Steam App ID或商店链接，留空按名称搜索',
                        hintStyle: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _searchGame,
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('搜索'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Status text
            if (_statusText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusText.contains('失败') || _statusText.contains('无效')
                        ? AppTheme.errorColor
                        : AppTheme.getTextSecondary(context),
                  ),
                ),
              ),

            // Search results
            if (_showSearchResults && _searchResults.isNotEmpty) ...[
              Text(
                '选择游戏:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.getTextPrimary(context)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                    border: Border.all(color: AppTheme.getTextSecondary(context).withValues(alpha: 0.15)),
                  ),
                  child: ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];
                      final isSelected = _selectedResult == result;
                      return _buildSearchResultTile(result, isSelected);
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Bottom buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                if (_source == ImportSource.none)
                  ElevatedButton(
                    onPressed: (_isLoading || _folderPath == null) ? null : _importNone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.4),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('导入'),
                  )
                else
                  ElevatedButton(
                    onPressed: (_isLoading || _selectedResult == null) ? null : _import,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.4),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('导入选中'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceChip(ImportSource source, String label) {
    final isSelected = _source == source;
    return GestureDetector(
      onTap: _isLoading ? null : () {
        setState(() {
          _source = source;
          _searchResults = [];
          _selectedResult = null;
          _showSearchResults = false;
          _statusText = '';
          _idController.clear();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.getTextSecondary(context).withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppTheme.primaryColor : AppTheme.getTextSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultTile(dynamic result, bool isSelected) {
    if (_source == ImportSource.dlsite && result is DlsiteSearchResult) {
      return ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppTheme.surfaceColor,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: 'https://img.dlsite.jp/resize/images2/work/doujin/${result.id.substring(0, result.id.length - 4)}0000/${result.id}_img_main_240x240.jpg',
              fit: BoxFit.cover,
              placeholder: (context, url) => const Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (context, url, error) => Icon(Icons.gamepad, color: AppTheme.getTextSecondary(context)),
            ),
          ),
        ),
        title: Text(
          result.name ?? result.id,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.primaryColor : AppTheme.getTextPrimary(context),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          result.id,
          style: TextStyle(fontSize: 11, color: AppTheme.getTextSecondary(context)),
        ),
        selected: isSelected,
        selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.1),
        onTap: () => setState(() => _selectedResult = result),
      );
    } else if (_source == ImportSource.steam && result is SteamSearchResult) {
      return ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppTheme.surfaceColor,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: result.tinyImage != null
                ? CachedNetworkImage(
                    imageUrl: result.tinyImage!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    errorWidget: (context, url, error) => Icon(Icons.gamepad, color: AppTheme.getTextSecondary(context)),
                  )
                : Icon(Icons.gamepad, color: AppTheme.getTextSecondary(context)),
          ),
        ),
        title: Text(
          result.name ?? result.id,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.primaryColor : AppTheme.getTextPrimary(context),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Steam App ID: ${result.id}',
          style: TextStyle(fontSize: 11, color: AppTheme.getTextSecondary(context)),
        ),
        selected: isSelected,
        selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.1),
        onTap: () => setState(() => _selectedResult = result),
      );
    }
    return const SizedBox.shrink();
  }
}
