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
import '../../../core/utils/app_settings.dart';
import '../../../core/utils/game_data_paths.dart';
import '../../../core/services/scrape_apply_service.dart';
import '../../../core/repositories/game_repository.dart';
import '../../../core/repositories/tag_repository.dart';
import '../../../core/services/dlsite_service.dart';
import '../../../core/services/game_data_migration_service.dart';
import '../../../core/services/steam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';
import '../categories/tag_games_page.dart';
import 'batch_import_dialog.dart';

class GamesPage extends ConsumerStatefulWidget {
  const GamesPage({super.key});

  @override
  ConsumerState<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends ConsumerState<GamesPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isRefreshing = false;
  String _refreshProgress = '';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final gamesAsync = ref.watch(allGamesProvider);
    return Column(
      children: [
        GlassAppBar(
          title: const Text('游戏库',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
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
                            _refreshProgress.isNotEmpty
                                ? _refreshProgress
                                : '扫描中',
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
                            libraryPaths = list
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .toList();
                          } catch (_) {
                            libraryPaths = rawLib.isNotEmpty ? [rawLib] : [];
                          }
                        } else {
                          libraryPaths = rawLib.isNotEmpty ? [rawLib] : [];
                        }

                        final rawSorted = prefs.getString('sorted_paths') ?? '';
                        if (rawSorted.startsWith('{')) {
                          try {
                            final decoded =
                                jsonDecode(rawSorted) as Map<String, dynamic>;
                            for (final v in decoded.values) {
                              final sp = v?.toString() ?? '';
                              if (sp.isNotEmpty && !libraryPaths.contains(sp)) {
                                // 检查是否已被库路径覆盖（是某个库路径的子目录）
                                final normalizedSp =
                                    sp.replaceAll('/', '\\').toLowerCase();
                                final isCovered = libraryPaths.any((lib) {
                                  final normalizedLib =
                                      lib.replaceAll('/', '\\').toLowerCase();
                                  return normalizedSp
                                      .startsWith('$normalizedLib\\');
                                });
                                if (!isCovered) {
                                  libraryPaths.add(sp);
                                }
                              }
                            }
                          } catch (e) {
                            debugPrint('[GamesPage] 解析整理目录配置失败: $e');
                          }
                        }

                        if (libraryPaths.isEmpty) {
                          if (mounted) {
                            AppTheme.showGlassToast(context,
                                message: '请先在设置中配置游戏库路径',
                                icon: Icons.warning_amber,
                                iconColor: AppTheme.warningColor);
                          }
                          return;
                        }

                        final scanner = ref.read(gameScannerServiceProvider);
                        final ignoreStr =
                            prefs.getString('scan_ignore_folders') ?? '';
                        final ignoreFolders = ignoreStr
                            .split(',')
                            .where((s) => s.trim().isNotEmpty)
                            .toList();
                        final blacklistStr =
                            prefs.getString('game_blacklist') ?? '';
                        final blacklistPaths = blacklistStr
                            .split('\n')
                            .where((s) => s.trim().isNotEmpty)
                            .toList();

                        scanner.onProgress = (processed, total) {
                          if (mounted) {
                            setState(
                                () => _refreshProgress = '$processed/$total');
                          }
                        };

                        await scanner.scanMultipleLibraries(libraryPaths,
                            ignoreFolders: ignoreFolders,
                            blacklistPaths: blacklistPaths);

                        ref.invalidate(allGamesProvider);
                        ref.invalidate(favoriteGamesProvider);
                        ref.invalidate(playedGamesProvider);
                      } catch (e) {
                        if (mounted) {
                          AppTheme.showGlassToast(context,
                              message: '扫描失败: $e',
                              icon: Icons.error_outline,
                              iconColor: AppTheme.errorColor);
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isRefreshing = false;
                            _refreshProgress = '';
                          });
                        }
                      }
                    },
                  ),
          ],
        ),
        Expanded(
          child: gamesAsync.when(
            data: (games) => GameListWidget(
              // 防止旧缓存或迁移中的记录把通关游戏带回游戏库。
              games: games.where((game) => !game.isCleared).toList(),
              showSearchBar: true,
              routeIndex: 1,
              onTagTap: (tag) {
                Navigator.of(context)
                    .push(MaterialPageRoute(
                        builder: (_) =>
                            TagGamesPage(tagId: tag.id!, tagName: tag.name)))
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

  void _showAddGameDialog() {
    final prefs = ref.read(sharedPreferencesProvider);
    final userFont = prefs.getString('font_family') ?? '';
    showGlassDialog(
      context: context,
      child: BatchImportDialog(
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
    if (result != null && mounted) {
      setState(() {
        _folderPath = result;
        _searchResults = [];
        _selectedResult = null;
        _showSearchResults = false;
      });
    }
  }

  Future<void> _postImportProcess(GameRepository repo, Game game) async {
    if (game.id == null) return;
    final configs = await _loadScrapeModeConfigs();

    // 重命名/移动整理逻辑统一走共享层，保持各入口行为一致
    final organized = await ScrapeApplyService.organizeFolder(
        game, ScrapeMode.singleAdd, repo, configs);
    debugPrint('[SingleImport] 整理完成: ${organized.path}');
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
      if (mounted) setState(() => _statusText = '搜索失败: $e');
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
      if (existingGame != null) {
        await GameDataMigrationService(gameRepository: repo)
            .migrateGameDirectory(_folderPath!, gameId: existingGame.id);
      } else {
        await GameDataMigrationService(gameRepository: repo)
            .migrateGameDirectory(_folderPath!);
      }

      String? title;
      String? version;
      String? intro;
      String? sourceUrl;

      final metadataFile =
          await GameDataPaths.existingMetadataFile(_folderPath!);
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

      final sourceUrlFile =
          await GameDataPaths.existingSourceUrlFile(_folderPath!);
      if (sourceUrl == null && await sourceUrlFile.exists()) {
        try {
          sourceUrl = (await sourceUrlFile.readAsString()).trim();
          if (sourceUrl.isEmpty) sourceUrl = null;
        } catch (e) {
          debugPrint('[GamesPage] 读取source_url.txt失败: $e');
        }
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

      final savedGame = await repo.getGameByPath(_folderPath!);
      if (savedGame != null) {
        await _postImportProcess(repo, savedGame);
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
      if (mounted) setState(() => _statusText = '导入失败: $e');
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
        results = [
          DlsiteSearchResult(id: normalizedId, name: 'ID: $normalizedId')
        ];
      } else {
        // 输入的不是ID，当作关键词搜索
        results = await _dlsiteService.searchWithKeyword(inputText);
      }
    } else {
      // 未输入，从文件夹名提取并搜索
      results = await _dlsiteService.searchWithFallback(_folderPath!);
    }

    if (!mounted) return;
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
        if (mounted) setState(() => _statusText = '无效的Steam App ID');
        return;
      }
      results = [SteamSearchResult(id: parsedId, name: 'ID: $parsedId')];
    } else {
      results = await _steamService.searchWithFallback(_folderPath!);
    }

    if (!mounted) return;
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
    final urlMatch =
        RegExp(r'store\.steampowered\.com/app/(\d+)').firstMatch(input);
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
      if (mounted) setState(() => _statusText = '导入失败: $e');
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
    await GameDataMigrationService(gameRepository: repo)
        .migrateGameDirectory(_folderPath!, gameId: existingGame?.id);

    if (!mounted) return;
    setState(() => _statusText = '正在通过ID获取: ${_selectedResult.id}');
    final gameInfo = await _dlsiteService.fetchById(_selectedResult.id);

    if (!mounted) return;
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
      description =
          _dlsiteService.replaceImageUrlsInDescription(description, urlToLocal);
    }

    if (!mounted) return;
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
    await _saveImagesAndMetadata(gameId, gameInfo.sourceUrl, metadata);

    final savedGame = await repo.getGameByPath(_folderPath!);
    if (savedGame != null) {
      await _postImportProcess(repo, savedGame);
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
  }

  Future<void> _importSteam() async {
    final repo = GameRepository();
    final tagRepo = TagRepository();
    final existingGame = await repo.getGameByPath(_folderPath!);
    await GameDataMigrationService(gameRepository: repo)
        .migrateGameDirectory(_folderPath!, gameId: existingGame?.id);

    if (!mounted) return;
    setState(() => _statusText = '正在通过ID获取: ${_selectedResult.id}');
    final gameInfo = await _steamService.fetchById(_selectedResult.id);

    if (!mounted) return;
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
        description =
            description!.replaceAll('[图片:${entry.key}]', '[图片:${entry.value}]');
      }
    }

    // Download videos embedded in description
    if (description != null && description.contains('[视频:')) {
      if (!mounted) return;
      setState(() => _statusText = '正在下载视频...');
      final videoMap = await _steamService.downloadVideosFromDescription(
        description,
        _folderPath!,
      );
      for (final entry in videoMap.entries) {
        description =
            description!.replaceAll('[视频:${entry.key}]', '[视频:${entry.value}]');
      }
    }

    if (!mounted) return;
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
    await _saveImagesAndMetadata(gameId, gameInfo.sourceUrl, metadata);

    final savedGame = await repo.getGameByPath(_folderPath!);
    if (savedGame != null) {
      await _postImportProcess(repo, savedGame);
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
  }

  Future<void> _saveImagesAndMetadata(
      int gameId, String sourceUrl, Map<String, dynamic> metadataJson) async {
    final imageDir = GameDataPaths.imagesDir(_folderPath!);
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
        await GameRepository().setGameImages(gameId, images);
      }
    }

    final metadataFile = GameDataPaths.metadataFile(_folderPath!);
    await GameDataPaths.ensureDataDir(_folderPath!);
    await metadataFile.writeAsString(jsonEncode(metadataJson), flush: true);

    final sourceUrlFile = GameDataPaths.sourceUrlFile(_folderPath!);
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
                      _folderPath ?? '未选择文件夹',
                      style: TextStyle(
                        fontSize: 13,
                        color: _folderPath != null
                            ? AppTheme.getTextPrimary(context)
                            : AppTheme.getTextSecondary(context),
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
                    backgroundColor: AppTheme.getPrimaryColor(context),
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
                        hintStyle: TextStyle(
                            fontSize: 12,
                            color: AppTheme.getTextSecondary(context)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              GlassConstants.radiusMedium),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
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
                    color:
                        _statusText.contains('失败') || _statusText.contains('无效')
                            ? AppTheme.errorColor
                            : AppTheme.getTextSecondary(context),
                  ),
                ),
              ),

            // Search results
            if (_showSearchResults && _searchResults.isNotEmpty) ...[
              Text(
                '选择游戏:',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.getTextPrimary(context)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                    borderRadius:
                        BorderRadius.circular(GlassConstants.radiusMedium),
                    border: Border.all(
                        color: AppTheme.getTextSecondary(context)
                            .withValues(alpha: 0.15)),
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
                  onPressed:
                      _isLoading ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                if (_source == ImportSource.none)
                  ElevatedButton(
                    onPressed: (_isLoading || _folderPath == null)
                        ? null
                        : _importNone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.primaryColor.withValues(alpha: 0.4),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.getTextColorOnPrimary(context),
                            ),
                          )
                        : const Text('导入'),
                  )
                else
                  ElevatedButton(
                    onPressed: (_isLoading || _selectedResult == null)
                        ? null
                        : _import,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.primaryColor.withValues(alpha: 0.4),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.getTextColorOnPrimary(context),
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
      onTap: _isLoading
          ? null
          : () {
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
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : AppTheme.getTextSecondary(context).withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? AppTheme.primaryColor
                : AppTheme.getTextSecondary(context),
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
              imageUrl:
                  'https://img.dlsite.jp/resize/images2/work/doujin/${result.id.substring(0, result.id.length - 4)}0000/${result.id}_img_main_240x240.jpg',
              fit: BoxFit.cover,
              placeholder: (context, url) => const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (context, url, error) => Icon(Icons.gamepad,
                  color: AppTheme.getTextSecondary(context)),
            ),
          ),
        ),
        title: Text(
          result.name ?? result.id,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? AppTheme.primaryColor
                : AppTheme.getTextPrimary(context),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          result.id,
          style: TextStyle(
              fontSize: 11, color: AppTheme.getTextSecondary(context)),
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
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    errorWidget: (context, url, error) => Icon(Icons.gamepad,
                        color: AppTheme.getTextSecondary(context)),
                  )
                : Icon(Icons.gamepad,
                    color: AppTheme.getTextSecondary(context)),
          ),
        ),
        title: Text(
          result.name ?? result.id,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? AppTheme.primaryColor
                : AppTheme.getTextPrimary(context),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Steam App ID: ${result.id}',
          style: TextStyle(
              fontSize: 11, color: AppTheme.getTextSecondary(context)),
        ),
        selected: isSelected,
        selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.1),
        onTap: () => setState(() => _selectedResult = result),
      );
    }
    return const SizedBox.shrink();
  }
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
