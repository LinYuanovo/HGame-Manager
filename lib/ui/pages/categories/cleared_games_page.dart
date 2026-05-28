import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';

class ClearedGamesPage extends ConsumerStatefulWidget {
  const ClearedGamesPage({super.key});

  @override
  ConsumerState<ClearedGamesPage> createState() => _ClearedGamesPageState();
}

class _ClearedGamesPageState extends ConsumerState<ClearedGamesPage> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gamesAsync = ref.watch(clearedGamesProvider);

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
        }
      },
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
                  const Icon(Icons.emoji_events, size: 20, color: Color.fromARGB(255, 255, 217, 0)),
                  const SizedBox(width: 8),
                  Text('已通关',
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
                child: gamesAsync.when(
                data: (games) {
                  if (games.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_events_outlined,
                              size: 64,
                              color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text('暂无已通关游戏',
                              style: TextStyle(
                                  color:
                                      AppTheme.textSecondary.withValues(alpha: 0.6),
                                  fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('右键点击游戏选择"标记已通关"',
                              style: TextStyle(
                                  color:
                                      AppTheme.textSecondary.withValues(alpha: 0.4),
                                  fontSize: 13)),
                        ],
                      ),
                    );
                  }
                  return GameListWidget(
                    games: games,
                    isClearedPage: true,
                    onTagTap: (tag) {
                      // 已通关页面不支持标签跳转
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
          ],
        ),
      ),
    );
  }
}
