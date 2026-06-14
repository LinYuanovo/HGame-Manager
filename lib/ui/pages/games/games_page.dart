import 'dart:io';
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
    final pathController = TextEditingController();
    final titleController = TextEditingController();
    final versionController = TextEditingController();
    final introController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showGlassDialog(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SizedBox(
          width: 450,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('添加本地游戏', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: pathController,
                  decoration: const InputDecoration(
                    labelText: '游戏路径 *',
                    hintText: '例如: E:\\Games\\GameName',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入游戏路径' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '游戏标题 *',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入游戏标题' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: versionController,
                  decoration: const InputDecoration(
                    labelText: '版本号',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: introController,
                  decoration: const InputDecoration(
                    labelText: '简介',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final repo = ref.read(gameRepositoryProvider);
                        final game = Game(
                          path: pathController.text.trim(),
                          title: titleController.text.trim(),
                          version: versionController.text.trim().isEmpty
                              ? null
                              : versionController.text.trim(),
                          intro: introController.text.trim().isEmpty
                              ? null
                              : introController.text.trim(),
                        );
                        await repo.insertGame(game);
                        Navigator.of(context).pop();
                        ref.invalidate(allGamesProvider);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white),
                      child: const Text('添加'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
