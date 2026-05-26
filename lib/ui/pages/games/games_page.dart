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
            IconButton(
              icon: _isRefreshing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    )
                  : Icon(Icons.refresh, color: AppTheme.textSecondary, size: 20),
              tooltip: _isRefreshing ? '刷新中 $_refreshProgress' : '刷新',
              onPressed: _isRefreshing
                  ? null
                  : () async {
                      setState(() => _isRefreshing = true);
                      try {
                        final repo = ref.read(gameRepositoryProvider);
                        final games = await repo.getAllGames();
                        int deleted = 0;
                        int rescanned = 0;
                        for (int i = 0; i < games.length; i++) {
                          final game = games[i];
                          if (game.path.isNotEmpty &&
                              !await Directory(game.path).exists()) {
                            await repo.deleteGame(game.id!);
                            deleted++;
                          } else if (game.images.isEmpty) {
                            final imageDir =
                                Directory(path.join(game.path, 'images'));
                            if (!await imageDir.exists()) {
                              final altDir =
                                  Directory(path.join(game.path, 'image'));
                              if (await altDir.exists()) {
                                await _rescanImages(repo, game.id!, altDir);
                                rescanned++;
                              }
                            } else {
                              await _rescanImages(repo, game.id!, imageDir);
                              rescanned++;
                            }
                          }
                          if (i % 10 == 0) {
                            setState(() =>
                                _refreshProgress = '${i + 1}/${games.length}');
                          }
                        }
                        ref.invalidate(allGamesProvider);
                        ref.invalidate(favoriteGamesProvider);
                        ref.invalidate(playedGamesProvider);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '刷新完成: 删除$deleted条记录, 重新扫描$rescanned个图片'),
                              duration: const Duration(seconds: 2),
                              backgroundColor: AppTheme.surfaceColor,
                            ),
                          );
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
        if (['.jpg', '.jpeg', '.png', '.webp'].contains(ext)) {
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

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassConstants.radiusLarge)),
        title:
            const Text('添加本地游戏', style: TextStyle(color: AppTheme.textPrimary)),
        content: SizedBox(
          width: 450,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: pathController,
                  decoration: const InputDecoration(
                    labelText: '游戏路径 *',
                    hintText: '例如: E:\\Games\\GameName',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入游戏路径' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '游戏标题 *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入游戏标题' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: versionController,
                  decoration: const InputDecoration(
                    labelText: '版本号',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: introController,
                  decoration: const InputDecoration(
                    labelText: '简介',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
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
              Navigator.of(dialogContext).pop();
              ref.invalidate(allGamesProvider);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white),
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
