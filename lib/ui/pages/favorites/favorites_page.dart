import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_list_widget.dart';
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
  late TabController _tabController;

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
    super.build(context);
    return Column(
      children: [
        GlassAppBar(
          title: Text('收藏',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
    );
  }

  Widget _buildFavoriteTagsTab() {
    final tagsAsync = ref.watch(favoriteTagsProvider);
    return tagsAsync.when(
      data: (tags) {
        if (tags.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.category_outlined,
            message: '暂无收藏的分类',
            subMessage: '在分类页面中收藏标签或系列',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.5,
          ),
          itemCount: tags.length,
          itemBuilder: (context, index) {
            final tag = tags[index];
            return GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onTap: () {
                if (tag.id != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TagGamesPage(
                            tagId: tag.id!,
                            tagName: tag.displayName ?? tag.name)),
                  );
                }
              },
              child: Row(
                children: [
                  Icon(
                    tag.type == Tag.typeSeries
                        ? Icons.category
                        : Icons.label,
                    size: 16,
                    color: tag.type == Tag.typeSeries
                        ? AppTheme.secondaryColor
                        : AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tag.displayName ?? tag.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.favorite, size: 16, color: AppTheme.getFavoriteColor(context)),
                    onPressed: () async {
                      await ref.read(tagRepositoryProvider).toggleFavorite(tag.id!, false);
                      ref.invalidate(favoriteTagsProvider);
                      ref.invalidate(allTagsProvider);
                      ref.invalidate(allSeriesProvider);
                    },
                    tooltip: '取消收藏',
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
    );
  }
}
