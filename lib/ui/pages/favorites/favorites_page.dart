import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';
import '../../widgets/layout_reflow.dart';
import '../../widgets/result_location.dart';
import '../categories/tag_games_page.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late AppTabController _tabController;
  final _leavingTags = <int>{};
  final _pendingTags = <int>{};
  final _tagErrors = <int, String>{};
  final _tagFocus = <int, FocusNode>{};
  int? _returnedTag;
  int _returnSequence = 0;

  @override
  void initState() {
    super.initState();
    _tabController = AppTabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final focus in _tagFocus.values) { focus.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        GlassAppBar(
          title: Text('收藏',
              style: TextStyle(
                  fontSize: GlassConstants.fontHeading,
                  fontWeight: AppTypography.semibold,
                  color: AppTheme.getTextPrimary(context))),
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
              _buildFavoriteGamesTab(),
              _buildFavoriteTagsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFavoriteGamesTab() {
    final gamesAsync = ref.watch(favoriteGamesProvider);
    return gamesAsync.when(
      data: (games) {
        if (games.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.favorite_border,
            message: '暂无收藏的游戏',
            subMessage: '在游戏列表中右键收藏游戏',
          );
        }
        return Material(
          color: Colors.transparent,
          child: GameListWidget(
          games: games,
          routeIndex: 3,
          onTagTap: (tag) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    TagGamesPage(tagId: tag.id!, tagName: tag.name)));
          },
        ),
        );
      },
      loading: () => const GameListSkeleton(),
      error: (error, _) => AppLoadError(message: '加载失败：$error', onRetry: () => ref.invalidate(favoriteGamesProvider)),
    );
  }

  Widget _buildFavoriteTagsTab() {
    final tagsAsync = ref.watch(favoriteTagsProvider);
    return tagsAsync.when(
      data: (tags) {
        _leavingTags.removeWhere((id) => !tags.any((tag) => tag.id == id));
        if (tags.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.category_outlined,
            message: '暂无收藏的分类',
            subMessage: '在分类页面中收藏标签或系列',
          );
        }
        return GridView.builder(
          key: const PageStorageKey('favorite-tags'),
          findChildIndexCallback: (key) {
            final index = tags.indexWhere((tag) => ValueKey(tag.id) == key);
            return index < 0 ? null : index;
          },
          padding: const EdgeInsets.fromLTRB(GlassConstants.spacingMedium, GlassConstants.spacingCompact, GlassConstants.spacingMedium, GlassConstants.spacingMedium),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.5,
          ),
          itemCount: tags.length,
          itemBuilder: (context, index) {
            final tag = tags[index];
            final titleAnchor = tag.id == null ? null : (this, tag.id);
            Widget card = GlassCard(
              focusNode: _tagFocus.putIfAbsent(tag.id!, () => FocusNode()),
              padding: const EdgeInsets.symmetric(horizontal: GlassConstants.spacingCompact, vertical: GlassConstants.spacingSmall),
              onTap: () {
                if (tag.id != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TagGamesPage(
                            tagId: tag.id!, titleAnchor: titleAnchor,
                            tagName: tag.displayName ?? tag.name)),
                  ).then((_) {
                    if (!mounted) return;
                    setState(() { _returnedTag = tag.id; _returnSequence++; });
                    _tagFocus[tag.id]?.requestFocus();
                  });
                }
              },
              child: Row(
                children: [
                  Icon(
                    tag.type == Tag.typeSeries
                        ? Icons.category
                        : Icons.label,
                    size: GlassConstants.iconSmall,
                    color: tag.type == Tag.typeSeries
                        ? AppTheme.getSecondaryColor(context)
                        : AppTheme.getPrimaryColor(context),
                  ),
                  const SizedBox(width: GlassConstants.spacingSmall),
                  Expanded(
                    child: TagRouteTitle(
                      anchor: titleAnchor, name: tag.displayName ?? tag.name,
                      style: const TextStyle(
                          fontSize: GlassConstants.fontTitle, fontWeight: AppTypography.medium),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.favorite, size: GlassConstants.iconSmall, color: AppTheme.getFavoriteColor(context)),
                    onPressed: _pendingTags.contains(tag.id) ? null : () async {
                      if (!_pendingTags.add(tag.id!)) return;
                      setState(() => _tagErrors.remove(tag.id));
                      try {
                        await ref.read(tagRepositoryProvider).toggleFavorite(tag.id!, false);
                        if (!mounted) return;
                        setState(() => _leavingTags.add(tag.id!));
                        await Future<void>.delayed(AppMotion.duration(context, AppMotion.fast));
                        if (!mounted) return;
                        final remaining = tags.where((candidate) => !_leavingTags.contains(candidate.id)).toList();
                        final next = remaining.isEmpty ? null : remaining[index.clamp(0, remaining.length - 1)];
                        _tagFocus[next?.id]?.requestFocus();
                        ref.invalidate(favoriteTagsProvider);
                        ref.invalidate(allTagsProvider);
                        ref.invalidate(allSeriesProvider);
                      } catch (error) {
                        if (mounted) setState(() => _tagErrors[tag.id!] = '更新失败：$error');
                      } finally {
                        if (mounted) setState(() => _pendingTags.remove(tag.id));
                      }
                    },
                    tooltip: '取消收藏',
                  ),
                ],
              ),
            );
            if (_tagErrors[tag.id] != null) card = Tooltip(message: _tagErrors[tag.id]!, child: Semantics(liveRegion: true, label: _tagErrors[tag.id], child: card));
            if (_returnedTag == tag.id) card = ResultLocation(key: ValueKey(_returnSequence), child: card);
            return LayoutReflow(key: ValueKey(tag.id), revision: tags.length, child: AppMotionValue(
                target: _leavingTags.contains(tag.id) ? 0 : 1, duration: AppMotion.fast,
                builder: (context, value, child) => IgnorePointer(ignoring: value < 1, child: Opacity(opacity: value, child: Transform.scale(scale: .9 + value * .1, child: child))), child: card));
          },
        );
      },
      loading: () => const AppSkeleton(
          layout: SkeletonLayout.tags, label: '正在加载收藏分类'),
      error: (error, _) => AppLoadError(message: '加载失败：$error', onRetry: () => ref.invalidate(favoriteTagsProvider)),
    );
  }
}
