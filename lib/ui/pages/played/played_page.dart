import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/cleared_game_path_utils.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';
import '../categories/tag_games_page.dart';

class PlayedPage extends ConsumerStatefulWidget {
  const PlayedPage({super.key});

  @override
  ConsumerState<PlayedPage> createState() => _PlayedPageState();
}

class _PlayedPageState extends ConsumerState<PlayedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isScanning = false;
  String _scanProgress = '';
  String? _scanResult;
  ({int gameId, int sequence})? _locationRequest;
  int _locationSequence = 0;
  List<Game> _selectedGames = [];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final gamesAsync = ref.watch(playedGamesProvider);

    return Column(
      children: [
        GlassAppBar(
          actions: [IconButton(tooltip: '定位最近游玩的游戏', icon: const Icon(Icons.my_location),
            onPressed: gamesAsync.valueOrNull?.any((game) => game.id != null && game.lastPlayedTime != null) == true ? () {
              final recent = gamesAsync.valueOrNull!.where((game) => game.id != null && game.lastPlayedTime != null).toList()
                ..sort((first, second) => second.lastPlayedTime!.compareTo(first.lastPlayedTime!));
              setState(() => _locationRequest = (gameId: recent.first.id!, sequence: ++_locationSequence));
            } : null)],
          title: Text(
            _selectedGames.isNotEmpty ? '已选 ${_selectedGames.length} 项' : '已玩',
            style: TextStyle(
                fontSize: GlassConstants.fontHeading,
                fontWeight: AppTypography.semibold,
                color: AppTheme.getTextPrimary(context)),
          ),
        ),
        if (_scanResult != null) Semantics(liveRegion: true, child: Text(_scanResult!, style: TextStyle(color: AppTheme.getTextSecondary(context)))),
        Expanded(
          child: gamesAsync.when(
            data: (games) {
              if (games.isEmpty) {
                return const EmptyStateWidget(
                  icon: Icons.sports_score_outlined,
                  message: '暂无已玩游戏',
                  subMessage: '在游戏列表中右键标记已玩',
                );
              }
              return Material(
                color: Colors.transparent,
                child: GameListWidget(
                  locationRequest: _locationRequest,
                  games: games,
                  contextMenuMode: ContextMenuMode.played,
                  routeIndex: 4,
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
            loading: () => const GameListSkeleton(),
            error: (error, _) => AppLoadError(message: '加载失败：$error', onRetry: () => ref.invalidate(playedGamesProvider)),
          ),
        ),
      ],
    );
  }

  Future<void> _scanSavePaths() async {
    setState(() {
      _isScanning = true;
      _scanResult = null;
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
        gamesToScan = allPlayed
            .where((g) => !g.path.contains('${sep}Cleared$sep'))
            .toList();
      }

      int found = 0;
      int skipped = 0;
      int discovered = 0;
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

        // 跳过"仅备份"游戏
        if (ClearedGamePathUtils.hasBackupSegment(game.path)) {
          skipped++;
          continue;
        }

        final savePath =
            await saveService.scanWithConfidence(game.path, game.title);
        if (savePath != null) {
          await repo.updateSavePath(game.id!, savePath);
          found++;
          discovered++;
        }
      }

      ref.invalidate(playedGamesProvider);

      if (mounted) {
        final newFound = discovered;
        setState(() => _scanResult = '扫描完成：新增 $discovered，跳过 $skipped，共 $found/$total 个有存档');
        if (skipped > 0) {
          AppTheme.showGlassToast(context,
              message:
                  '扫描完成: 新发现 $newFound 个，跳过 $skipped 个已有记录，共 $found/$total 个有存档');
        } else {
          AppTheme.showGlassToast(context,
              message: '扫描完成: 找到 $found/$total 个存档位置');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _scanResult = '扫描失败：$e');
        AppTheme.showGlassToast(context,
            message: '扫描失败: $e',
            icon: Icons.error_outline,
            iconColor: AppTheme.errorColor);
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
