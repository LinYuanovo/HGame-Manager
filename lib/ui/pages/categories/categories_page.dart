import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';
import 'tag_games_page.dart';
import 'cleared_games_page.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassAppBar(
          title: const Text('分类', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        ),
        GlassTabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '标签', icon: Icon(Icons.label_outline)),
            Tab(text: '系列', icon: Icon(Icons.category_outlined)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTagsTab(Tag.typeCustom, allTagsProvider),
              _buildTagsTab(Tag.typeSeries, allSeriesProvider),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTagsTab(String type, FutureProvider<List<Tag>> provider) {
    final tagsAsync = ref.watch(provider);
    return tagsAsync.when(
      data: (tags) {
        // 添加"已通关"特殊标签（仅在标签tab）
        final showClearedTag = type == Tag.typeCustom;
        
        if (tags.isEmpty && !showClearedTag) {
          return EmptyStateWidget(
            icon: type == Tag.typeCustom ? Icons.label : Icons.category,
            message: type == Tag.typeCustom ? '暂无标签' : '暂无系列',
            subMessage: type == Tag.typeCustom ? '刮削游戏后自动生成标签' : '系统预定义了 RPG、ADV 等系列',
          );
        }
        final searchQuery = _searchController.text.trim().toLowerCase();
        final filteredTags = searchQuery.isEmpty
            ? tags
            : tags.where((tag) => (tag.displayName ?? tag.name).toLowerCase().contains(searchQuery)).toList();
        
        // 计算总数量（包括已通关标签）
        final totalCount = filteredTags.length + (showClearedTag && searchQuery.isEmpty ? 1 : 0);
        
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: GlassSearchBar(
                      controller: _searchController,
                      hintText: type == Tag.typeCustom ? '搜索标签...' : '搜索系列...',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (type == Tag.typeCustom) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _showAddTagDialog(type),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.5,
                ),
                itemCount: totalCount,
                itemBuilder: (context, index) {
                  // 第一个是"已通关"特殊标签
                  if (showClearedTag && index == 0 && searchQuery.isEmpty) {
                    return _buildClearedTagChip();
                  }
                  final tagIndex = showClearedTag && searchQuery.isEmpty ? index - 1 : index;
                  final tag = filteredTags[tagIndex];
                  return _buildTagChip(tag);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
    );
  }

  Widget _buildTagChip(Tag tag) {
    return GestureDetector(
      onSecondaryTapUp: (details) => _showTagContextMenu(tag, details.globalPosition),
      child: GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: () {
        if (tag.id != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TagGamesPage(tagId: tag.id!, tagName: tag.displayName ?? tag.name)),
          ).then((_) {
            ref.invalidate(allTagsProvider);
            ref.invalidate(allSeriesProvider);
          });
        }
      },
      child: Row(
        children: [
          Icon(
            tag.type == Tag.typeSeries ? Icons.category : Icons.label,
            size: 16,
            color: tag.type == Tag.typeSeries ? AppTheme.secondaryColor : AppTheme.primaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tag.displayName ?? tag.name,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (tag.gameCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${tag.gameCount}',
                style: TextStyle(fontSize: 14, color: AppTheme.primaryColor),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(tag.isFavorite ? Icons.favorite : Icons.favorite_border, size: 16, color: tag.isFavorite ? const Color(0xFFFF6B9D) : null),
            onPressed: () async {
              await ref.read(tagRepositoryProvider).toggleFavorite(tag.id!, !tag.isFavorite);
              ref.invalidate(allTagsProvider);
              ref.invalidate(allSeriesProvider);
              ref.invalidate(favoriteTagsProvider);
            },
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildClearedTagChip() {
    final clearedGamesAsync = ref.watch(clearedGamesProvider);
    final gameCount = clearedGamesAsync.whenOrNull(data: (games) => games.length) ?? 0;
    
    return GestureDetector(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ClearedGamesPage()),
          ).then((_) {
            ref.invalidate(allTagsProvider);
            ref.invalidate(clearedGamesProvider);
          });
        },
        child: Row(
          children: [
            const Icon(
              Icons.emoji_events,
              size: 16,
              color: Color(0xFFFFD700),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '已通关',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFFFFD700)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (gameCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$gameCount',
                  style: TextStyle(fontSize: 14, color: Color(0xFFFFD700)),
                ),
              ),
            ],
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  void _showTagContextMenu(Tag tag, Offset position) {
    AppTheme.showGlassMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(value: 'edit', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit, size: 18), title: Text('修改'))),
        PopupMenuItem(value: 'delete', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete, size: 18, color: AppTheme.errorColor), title: Text('删除', style: TextStyle(color: AppTheme.errorColor)))),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'edit':
          _showEditTagDialog(tag);
          break;
        case 'delete':
          _showDeleteTagConfirmDialog(tag);
          break;
      }
    });
  }

  void _showEditTagDialog(Tag tag) {
    final controller = TextEditingController(text: tag.displayName ?? tag.name);
    showGlassDialog(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tag.type == Tag.typeCustom ? '修改标签' : '修改系列', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '输入名称'),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      await ref.read(tagRepositoryProvider).updateTag(tag.copyWith(
                        name: name,
                        displayName: name,
                      ));
                      ref.invalidate(allTagsProvider);
                      ref.invalidate(allSeriesProvider);
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteTagConfirmDialog(Tag tag) {
    showGlassDialog(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tag.type == Tag.typeCustom ? '删除标签' : '删除系列', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text('确定要删除"${tag.displayName ?? tag.name}"吗？', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    await ref.read(tagRepositoryProvider).deleteTag(tag.id!);
                    ref.invalidate(allTagsProvider);
                    ref.invalidate(allSeriesProvider);
                    ref.invalidate(favoriteTagsProvider);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTagDialog(String type) {
    final controller = TextEditingController();
    showGlassDialog(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(type == Tag.typeCustom ? '添加标签' : '添加系列', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(hintText: type == Tag.typeCustom ? '输入标签名称' : '输入系列名称'),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      await ref.read(tagRepositoryProvider).insertOrGetTag(name, type);
                      ref.invalidate(allTagsProvider);
                      ref.invalidate(allSeriesProvider);
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
