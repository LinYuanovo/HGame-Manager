import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/repositories/game_repository.dart';
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
