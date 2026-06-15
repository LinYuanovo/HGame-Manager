import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';
import '../categories/tag_games_page.dart';

class ClearedPage extends ConsumerStatefulWidget {
  const ClearedPage({super.key});

  @override
  ConsumerState<ClearedPage> createState() => _ClearedPageState();
}

class _ClearedPageState extends ConsumerState<ClearedPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isScanning = false;
  String _scanProgress = '';
  List<Game> _selectedGames = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassAppBar(
          title: Text(
            _selectedGames.isNotEmpty ? '已选 ${_selectedGames.length} 项' : '通关',
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
          ),
        ),
        GlassTabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '游戏', icon: Icon(Icons.sports_esports_outlined)),
            Tab(text: '分类', icon: Icon(Icons.category_outlined)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildClearedGamesTab(),
              _buildClearedTagsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClearedGamesTab() {
    final gamesAsync = ref.watch(clearedGamesProvider);

    return gamesAsync.when(
      data: (games) {
        if (games.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.emoji_events_outlined,
            message: '暂无通关游戏',
            subMessage: '在游戏列表中右键标记通关',
          );
        }
        return Material(
          color: Colors.transparent,
          child: GameListWidget(
            games: games,
            contextMenuMode: ContextMenuMode.played,
            isClearedPage: true,
            onScanSavePaths: _isScanning ? null : _scanSavePaths,
            scanProgress: _scanProgress,
            onSelectionChanged: (selected) {
              setState(() => _selectedGames = selected);
            },
            onTagTap: (tag) {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      TagGamesPage(tagId: tag.id!, tagName: tag.name)));
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
    );
  }

  Widget _buildClearedTagsTab() {
    final tagsAsync = ref.watch(favoriteTagsProvider);

    return tagsAsync.when(
      data: (tags) {
        if (tags.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.category_outlined,
            message: '暂无收藏分类',
            subMessage: '在分类页面中收藏标签',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            childAspectRatio: 2.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: tags.length,
          itemBuilder: (context, index) {
            final tag = tags[index];
            return _buildTagCard(tag);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
    );
  }

  Widget _buildTagCard(Tag tag) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TagGamesPage(tagId: tag.id!, tagName: tag.name)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                tag.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () async {
                await ref.read(tagRepositoryProvider).toggleFavorite(tag.id!, false);
                ref.invalidate(favoriteTagsProvider);
              },
              child: const Icon(
                Icons.favorite,
                size: 18,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanSavePaths() async {
    setState(() {
      _isScanning = true;
    });

    try {
      final repo = ref.read(gameRepositoryProvider);
      final saveService = ref.read(savePathServiceProvider);

      final List<Game> gamesToScan;
      if (_selectedGames.isNotEmpty) {
        gamesToScan = _selectedGames;
      } else {
        final allPlayed = await repo.getPlayedGames();
        final sep = Platform.pathSeparator;
        gamesToScan = allPlayed.where((g) =>
          g.path.contains('${sep}Cleared$sep')
        ).toList();
      }

      int found = 0;
      int skipped = 0;
      int total = gamesToScan.length;

      for (int i = 0; i < gamesToScan.length; i++) {
        final game = gamesToScan[i];
        if (mounted) {
          setState(() => _scanProgress = '${i + 1}/$total');
        }

        if (game.savePath != null && game.savePath!.isNotEmpty) {
          skipped++;
          found++;
          continue;
        }

        if (game.path.contains('${Platform.pathSeparator}Backup${Platform.pathSeparator}')) {
          skipped++;
          continue;
        }

        final savePath = await saveService.scanWithConfidence(game.path, game.title);
        if (savePath != null) {
          await repo.updateSavePath(game.id!, savePath);
          found++;
        }
      }

      ref.invalidate(clearedGamesProvider);

      if (mounted) {
        final newFound = found - skipped;
        if (skipped > 0) {
          AppTheme.showGlassToast(context, message: '扫描完成: 新发现 $newFound 个，跳过 $skipped 个已有记录，共 $found/$total 个有存档');
        } else {
          AppTheme.showGlassToast(context, message: '扫描完成: 找到 $found/$total 个存档位置');
        }
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '扫描失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanProgress = '';
        });
      }
    }
  }
}
