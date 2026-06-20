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
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          actions: [
            IconButton(
              icon: Icon(Icons.add_circle_outline,
                  color: AppTheme.primaryColor, size: 20),
              tooltip: '添加本地游戏',
              onPressed: () => _showAddGameDialog(),
            ),
            IconButton(
              icon: Icon(Icons.cloud_download_outlined,
                  color: AppTheme.primaryColor, size: 20),
              tooltip: '从云端导入信息',
              onPressed: () => _showCloudImportDialog(),
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
                    icon: Icon(Icons.refresh, color: AppTheme.textSecondary, size: 20),
                    tooltip: '刷新',
                    onPressed: () async {
                      setState(() => _isRefreshing = true);
                      try {
                        final prefs = ref.read(sharedPreferencesProvider);
                        var libraryPath = prefs.getString('library_path') ?? '';
                        final sortedPath = prefs.getString('sorted_path') ?? '';
                        final scanPath = sortedPath.isNotEmpty ? sortedPath : libraryPath;

                        if (scanPath.isEmpty) {
                          if (mounted) {
                            AppTheme.showGlassToast(context, message: '请先在设置中配置游戏库路径或整理目录', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
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

                        await scanner.scanGameLibrary(scanPath, ignoreFolders: ignoreFolders, blacklistPaths: blacklistPaths);

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
    showGlassDialog(
      context: context,
      child: _BatchImportDialog(
        onImportComplete: () {
          ref.invalidate(allGamesProvider);
        },
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

  const _BatchImportDialog({required this.onImportComplete});

  @override
  State<_BatchImportDialog> createState() => _BatchImportDialogState();
}

class _BatchImportDialogState extends State<_BatchImportDialog> {
  String? _parentPath;
  List<Directory> _subfolders = [];
  final Set<int> _selected = {};
  bool _scanning = false;
  bool _importing = false;

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: '选择游戏父目录');
    if (result == null) return;
    setState(() {
      _parentPath = result;
      _subfolders = [];
      _selected.clear();
      _scanning = true;
    });
    try {
      final parent = Directory(result);
      final dirs = <Directory>[];
      await for (final entity in parent.list(followLinks: false)) {
        if (entity is Directory) {
          dirs.add(entity);
        }
      }
      dirs.sort((a, b) => path.basename(a.path).toLowerCase().compareTo(path.basename(b.path).toLowerCase()));
      if (mounted) {
        setState(() {
          _subfolders = dirs;
          for (int i = 0; i < dirs.length; i++) {
            _selected.add(i);
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _import() async {
    if (_selected.isEmpty) return;
    setState(() => _importing = true);
    final repo = GameRepository();
    int imported = 0;
    int skipped = 0;
    for (final i in _selected) {
      final folder = _subfolders[i];
      final folderPath = folder.path;
      final existing = await repo.getGameByPath(folderPath);
      if (existing != null) {
        skipped++;
        continue;
      }
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
      imported++;
    }
    if (mounted) {
      Navigator.of(context).pop();
      widget.onImportComplete();
      final msg = skipped > 0 ? '导入 $imported 个游戏，跳过 $skipped 个已存在' : '成功导入 $imported 个游戏';
      AppTheme.showGlassToast(context, message: msg, icon: Icons.check_circle_outline, iconColor: AppTheme.successColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: SizedBox(
        width: 500,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('批量导入游戏', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                      border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _parentPath ?? '未选择文件夹',
                      style: TextStyle(
                        fontSize: 13,
                        color: _parentPath != null ? AppTheme.textPrimary : AppTheme.textSecondary,
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
            const SizedBox(height: 12),
            if (_scanning)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_subfolders.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _parentPath != null ? '未找到子文件夹' : '选择一个包含游戏子文件夹的目录',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                ),
              )
            else ...[
              Row(
                children: [
                  Text(
                    '找到 ${_subfolders.length} 个文件夹，已选 ${_selected.length} 个',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () {
                            setState(() {
                              if (_selected.length == _subfolders.length) {
                                _selected.clear();
                              } else {
                                for (int i = 0; i < _subfolders.length; i++) {
                                  _selected.add(i);
                                }
                              }
                            });
                          },
                    child: Text(
                      _selected.length == _subfolders.length ? '取消全选' : '全选',
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
                    border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.15)),
                  ),
                  child: ListView.builder(
                    itemCount: _subfolders.length,
                    itemBuilder: (context, index) {
                      final folder = _subfolders[index];
                      final name = path.basename(folder.path);
                      return CheckboxListTile(
                        value: _selected.contains(index),
                        onChanged: _importing
                            ? null
                            : (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selected.add(index);
                                  } else {
                                    _selected.remove(index);
                                  }
                                });
                              },
                        title: Text(name, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                        subtitle: Text(folder.path, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppTheme.primaryColor,
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _importing ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _selected.isEmpty || _importing ? null : _import,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.4),
                  ),
                  child: _importing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('导入 (${_selected.length})'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum ImportSource { dlsite, steam }

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

  Future<void> _searchDlsite() async {
    List<DlsiteSearchResult> results;
    final inputId = _idController.text.trim();
    if (inputId.isNotEmpty) {
      final normalizedId = _dlsiteService.normalizeId(inputId);
      if (normalizedId != null) {
        results = [DlsiteSearchResult(id: normalizedId, name: 'ID: $normalizedId')];
      } else {
        setState(() => _statusText = '无效的DLsite ID');
        return;
      }
    } else {
      results = await _dlsiteService.searchWithFallback(_folderPath!);
    }

    setState(() {
      _searchResults = results;
      _showSearchResults = true;
      if (results.isEmpty) {
        _statusText = '未找到游戏，请尝试手动输入ID';
      } else {
        _statusText = '找到 ${results.length} 个结果，请选择';
      }
    });
  }

  Future<void> _searchSteam() async {
    List<SteamSearchResult> results;
    final inputId = _idController.text.trim();
    if (inputId.isNotEmpty) {
      if (!RegExp(r'^\d+$').hasMatch(inputId)) {
        setState(() => _statusText = '无效的Steam App ID');
        return;
      }
      results = [SteamSearchResult(id: inputId, name: 'ID: $inputId')];
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

    final game = Game(
      path: _folderPath!,
      title: gameInfo.title,
      intro: description,
      sourceUrl: gameInfo.sourceUrl,
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
        width: 550,
        height: _showSearchResults ? 600 : 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '从云端导入信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // Source selector
            Row(
              children: [
                _buildSourceChip(ImportSource.dlsite, 'DLsite'),
                const SizedBox(width: 8),
                _buildSourceChip(ImportSource.steam, 'Steam'),
              ],
            ),
            const SizedBox(height: 16),

            // Folder picker
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                      border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _folderPath ?? '未选择文件夹',
                      style: TextStyle(
                        fontSize: 13,
                        color: _folderPath != null ? AppTheme.textPrimary : AppTheme.textSecondary,
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

            // ID input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idController,
                    decoration: InputDecoration(
                      hintText: _source == ImportSource.dlsite
                          ? '输入DLsite ID (如 RJ123456)，留空则自动按游戏名称搜索'
                          : '输入Steam APPID (如 2254890)，留空则自动按游戏名称搜索',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
                        : AppTheme.textSecondary,
                  ),
                ),
              ),

            // Search results
            if (_showSearchResults && _searchResults.isNotEmpty) ...[
              const Text(
                '选择游戏:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                    border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.15)),
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
            color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
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
              errorWidget: (context, url, error) => const Icon(Icons.gamepad, color: AppTheme.textSecondary),
            ),
          ),
        ),
        title: Text(
          result.name ?? result.id,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          result.id,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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
                    errorWidget: (context, url, error) => const Icon(Icons.gamepad, color: AppTheme.textSecondary),
                  )
                : const Icon(Icons.gamepad, color: AppTheme.textSecondary),
          ),
        ),
        title: Text(
          result.name ?? result.id,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Steam App ID: ${result.id}',
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        selected: isSelected,
        selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.1),
        onTap: () => setState(() => _selectedResult = result),
      );
    }
    return const SizedBox.shrink();
  }
}
