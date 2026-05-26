import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';
import '../categories/tag_games_page.dart';

class PlayedPage extends ConsumerWidget {
  const PlayedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(playedGamesProvider);

    return Column(
      children: [
        GlassAppBar(
          title: const Text('已玩',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
        ),
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
                games: games,
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
}
