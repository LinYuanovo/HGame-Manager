import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/providers.dart';
import '../theme/app_theme.dart';

class GameListSkeleton extends ConsumerWidget {
  const GameListSkeleton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(sharedPreferencesProvider);
    final isFixed = ref.watch(isFixedColumnCountProvider);
    final fixedCount = ref.watch(fixedColumnCountProvider);
    final coverAspectRatio = ref.watch(posterCoverAspectRatioProvider);
    return AppSkeleton(
      label: '正在加载游戏',
      showToolbar: true,
      layout: settings.getString('game_list_view_mode') == 'list'
          ? SkeletonLayout.rows
          : SkeletonLayout.posters,
      columns: isFixed ? fixedCount.clamp(2, 8) : 3,
      coverAspectRatio: coverAspectRatio,
    );
  }
}
