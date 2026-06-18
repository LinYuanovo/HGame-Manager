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

class _ClearedPageState extends ConsumerState<ClearedPage> {
  bool _isScanning = false;
  String _scanProgress = '';
  List<Game> _selectedGames = [];

  @override
  Widget build(BuildContext context) {
    final gamesAsync = ref.watch(clearedGamesProvider);
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
        Expanded(
          child: gamesAsync.when(
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
                  routeIndex: 5,
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
          ),
        ),
      ],
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
