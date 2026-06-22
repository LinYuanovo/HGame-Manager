import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';

const double _sidebarHalfWidth = LayoutConstants.sidebarWidth / 2;

class TagGamesPage extends ConsumerStatefulWidget {
  final int tagId;
  final String tagName;

  const TagGamesPage({super.key, required this.tagId, required this.tagName});

  @override
  ConsumerState<TagGamesPage> createState() => _TagGamesPageState();
}

class _TagGamesPageState extends ConsumerState<TagGamesPage> {
  @override
  Widget build(BuildContext context) {
    final gamesAsync = ref.watch(gamesByTagProvider(widget.tagId));

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const _DismissPageIntent(),
      },
      child: Actions(
        actions: {
          _DismissPageIntent: CallbackAction<_DismissPageIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                GlassAppBar(
                  title: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            size: 20, color: AppTheme.textSecondary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Text(widget.tagName,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                    ],
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _sidebarHalfWidth),
                      child: gamesAsync.when(
                      data: (games) {
                        if (games.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.label_off_outlined,
                                    size: 64,
                                    color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                                const SizedBox(height: 16),
                                Text('该标签下暂无游戏',
                                    style: TextStyle(
                                        color:
                                            AppTheme.textSecondary.withValues(alpha: 0.6),
                                        fontSize: 16)),
                              ],
                            ),
                          );
                        }
                        return GameListWidget(
                          games: games,
                          showPlayTimeSort: true,
                          onTagTap: (tag) {
                            Navigator.of(context).pushReplacement(MaterialPageRoute(
                                builder: (_) => TagGamesPage(
                                    tagId: tag.id!, tagName: tag.name)));
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, _) => Center(
                          child: Text('加载失败: $error',
                              style: const TextStyle(color: AppTheme.errorColor))),
                    ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissPageIntent extends Intent {
  const _DismissPageIntent();
}
