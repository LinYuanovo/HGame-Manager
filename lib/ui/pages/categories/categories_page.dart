import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/tag_input_dialog.dart';
import 'tag_games_page.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  bool _isMultiSelectMode = false;
  final Set<int> _selectedTagIds = {};
  final Map<String, List<String>> _tagOrder = {};
  final Set<String> _manualTypes = {};
  String? _dragType;
  Tag? _draggingTag;
  List<Tag>? _dragOrder;
  List<int> _dragOriginIds = [];
  final Map<String, GlobalKey> _gridKeys = {};
  final Map<int, GlobalKey> _cardKeys = {};
  final Map<int, Offset> _shiftStarts = {};
  final Map<int, Offset> _currentShift = {};
  int _shiftTick = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTagOrders();
  }

  void _loadTagOrders() {
    final raw =
        ref.read(sharedPreferencesProvider).getString(AppSettings.tagOrderKey);
    if (raw == null) return;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      for (final type in [Tag.typeCustom, Tag.typeSeries]) {
        final config = saved[type];
        if (config is! Map) continue;
        _tagOrder[type] =
            (config['ids'] as List? ?? []).whereType<String>().toList();
        if (config['mode'] == 'manual') _manualTypes.add(type);
      }
    } catch (_) {
      // 无可用顺序时按数量显示。
    }
  }

  Future<void> _saveTagOrders() async {
    await ref.read(sharedPreferencesProvider).setString(
          AppSettings.tagOrderKey,
          jsonEncode({
            for (final type in [Tag.typeCustom, Tag.typeSeries])
              type: {
                'ids': _tagOrder[type] ?? [],
                'mode': _manualTypes.contains(type) ? 'manual' : 'count'
              },
          }),
        );
  }

  List<Tag> _sortTags(List<Tag> tags, String type) {
    final saved =
        _manualTypes.contains(type) ? _tagOrder[type] ?? [] : <String>[];
    final positions = {for (var i = 0; i < saved.length; i++) saved[i]: i};
    final result = List<Tag>.from(tags);
    result.sort((a, b) {
      final order = (positions[a.id.toString()] ?? saved.length)
          .compareTo(positions[b.id.toString()] ?? saved.length);
      if (order != 0) return order;
      if (type == Tag.typeSeries) {
        const defaults = ['RPG', 'ADV', 'ACT', 'SLG', 'AVG', 'FPS', 'TPS'];
        final aDefault = defaults.contains(a.name);
        final bDefault = defaults.contains(b.name);
        if (aDefault != bDefault) return aDefault ? 1 : -1;
      }
      final count = b.gameCount.compareTo(a.gameCount);
      return count != 0 ? count : a.name.compareTo(b.name);
    });
    return result;
  }

  void _onDragStart(String type, List<Tag> visibleTags, Tag tag) {
    setState(() {
      _dragType = type;
      _draggingTag = tag;
      _dragOrder = List.of(visibleTags);
      _dragOriginIds = visibleTags.map((tag) => tag.id ?? -1).toList();
    });
  }

  /// 拖拽时按指针在网格中的位置实时计算插入点，两个方向灵敏度一致，
  /// 拖过最后一张卡的中线即可排到最后。
  void _onGridPointerMove(String type, Offset globalPosition) {
    final dragged = _draggingTag;
    final order = _dragOrder;
    if (dragged == null || order == null || _dragType != type) return;
    final gridContext = _gridKeys[type]?.currentContext;
    final box = gridContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(globalPosition);
    const cross = 6;
    const spacing = 8.0;
    const ratio = 2.5;
    const paddingH = 16.0;
    final cellWidth =
        (box.size.width - paddingH * 2 - spacing * (cross - 1)) / cross;
    if (cellWidth <= 0) return;
    final cellHeight = cellWidth / ratio;
    final col = ((local.dx - paddingH) / (cellWidth + spacing))
        .floor()
        .clamp(0, cross - 1);
    final row = ((local.dy) / (cellHeight + spacing)).floor();
    if (row < 0) return;
    // 指针越过最后一张卡时直接排到末尾。
    final rawIndex = row * cross + col;
    var index = rawIndex >= order.length ? order.length : rawIndex;
    if (rawIndex < order.length) {
      final cellStartX = paddingH + col * (cellWidth + spacing);
      if (local.dx - cellStartX > cellWidth / 2) index++;
    }
    final from = order.indexWhere((tag) => tag.id == dragged.id);
    if (from < 0) return;
    var to = index;
    if (to > from) to--;
    if (to == from) return;
    // FLIP：先记录各卡片当前视觉位置，重排后反向偏移并动画归位。
    final oldRects = _captureCardRects();
    setState(() {
      order.insert(to, order.removeAt(from));
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _animateCardShifts(oldRects));
  }

  Map<int, Rect> _captureCardRects() {
    final rects = <int, Rect>{};
    for (final entry in _cardKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.attached) {
        // 叠加进行中的滑动偏移，取卡片的视觉位置而非布局位置。
        final shift = _currentShift[entry.key] ?? Offset.zero;
        rects[entry.key] = (box.localToGlobal(Offset.zero) + shift) & box.size;
      }
    }
    return rects;
  }

  void _animateCardShifts(Map<int, Rect> oldRects) {
    if (_dragOrder == null) return;
    var changed = false;
    for (final entry in _cardKeys.entries) {
      final oldRect = oldRects[entry.key];
      if (oldRect == null) continue;
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final delta = oldRect.topLeft - box.localToGlobal(Offset.zero);
      if (delta == Offset.zero) continue;
      _shiftStarts[entry.key] = delta;
      changed = true;
    }
    if (changed) {
      setState(() => _shiftTick++);
    }
  }

  void _endDrag(String type, List<Tag> allTags, List<Tag> visibleTags) {
    final order = _dragOrder;
    if (_dragType != type || order == null) return;
    // 与拖拽前顺序比较，仅实际换位后才落库并切换为自定义排序。
    var changed = order.length != _dragOriginIds.length;
    if (!changed) {
      for (var i = 0; i < order.length; i++) {
        if (order[i].id != _dragOriginIds[i]) {
          changed = true;
          break;
        }
      }
    }
    // 松手即确认当前预览顺序。
    final visibleIds = visibleTags.map((tag) => tag.id).toSet();
    var index = 0;
    final ids = allTags
        .map((tag) => (visibleIds.contains(tag.id) ? order[index++].id : tag.id)
            .toString())
        .toList();
    setState(() {
      if (changed) {
        _tagOrder[type] = ids;
        _manualTypes.add(type);
      }
      _dragType = null;
      _draggingTag = null;
      _dragOrder = null;
    });
    if (changed) _saveTagOrders();
  }

  /// 让位滑动动画：重排后从旧位置偏移滑到新位置。
  Widget _buildShiftedChip(Tag tag) {
    final shift = _shiftStarts[tag.id];
    final chip = _buildTagChip(tag);
    if (shift == null) return chip;
    return TweenAnimationBuilder<Offset>(
      key: ValueKey('shift-${tag.id}-$_shiftTick'),
      tween: Tween(begin: shift, end: Offset.zero),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      onEnd: () {
        _shiftStarts.remove(tag.id);
        _currentShift[tag.id!] = Offset.zero;
      },
      builder: (context, offset, child) {
        _currentShift[tag.id!] = offset;
        return Transform.translate(offset: offset, child: child);
      },
      child: chip,
    );
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
          title: Text('分类',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.getTextPrimary(context))),
        ),
        GlassTabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '系列', icon: Icon(Icons.category_outlined)),
            Tab(text: '标签', icon: Icon(Icons.label_outline)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTagsTab(Tag.typeSeries, allSeriesProvider),
              _buildTagsTab(Tag.typeCustom, allTagsProvider),
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
        // 过滤空标签（仅标签tab适用，系列tab不适用）
        final filteredEmptyTags = type == Tag.typeCustom
            ? tags.where((t) => t.gameCount > 0).toList()
            : tags;

        // 异步删除空的自定义标签
        if (type == Tag.typeCustom) {
          final emptyTags = tags.where((t) => t.gameCount == 0).toList();
          if (emptyTags.isNotEmpty) {
            Future.microtask(() async {
              final tagRepo = ref.read(tagRepositoryProvider);
              for (final tag in emptyTags) {
                if (tag.id != null) {
                  await tagRepo.deleteTag(tag.id!);
                }
              }
            });
          }
        }

        if (filteredEmptyTags.isEmpty) {
          return EmptyStateWidget(
            icon: type == Tag.typeCustom ? Icons.label : Icons.category,
            message: type == Tag.typeCustom ? '暂无标签' : '暂无系列',
            subMessage: type == Tag.typeCustom
                ? '刮削游戏后自动生成标签'
                : '系统预定义了 RPG、ADV 等系列，右键可管理自定义系列',
          );
        }
        final orderedTags = _sortTags(filteredEmptyTags, type);
        final searchQuery = _searchController.text.trim().toLowerCase();
        final filteredTags = orderedTags
            .where((tag) =>
                searchQuery.isEmpty ||
                (tag.displayName ?? tag.name)
                    .toLowerCase()
                    .contains(searchQuery))
            .toList();
        // 拖拽过程中使用实时预览顺序，松手后落库。
        final displayedTags =
            (_dragType == type && _dragOrder != null && !_isMultiSelectMode)
                ? _dragOrder!
                : filteredTags;

        // 计算总数量
        final totalCount = displayedTags.length;

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
                  const SizedBox(width: 8),
                  AppDropdown<String>(
                    key: ValueKey('tag-sort-$type'),
                    value: _manualTypes.contains(type) ? 'manual' : 'count',
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'count', child: Text('按数量')),
                      DropdownMenuItem(value: 'manual', child: Text('自定义')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        if (value == 'manual') {
                          _tagOrder.putIfAbsent(
                              type,
                              () => orderedTags
                                  .map((tag) => tag.id.toString())
                                  .toList());
                          _manualTypes.add(type);
                        } else {
                          _manualTypes.remove(type);
                        }
                      });
                      _saveTagOrders();
                    },
                  ),
                  const SizedBox(width: 8),
                  // 多选按钮
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_isMultiSelectMode) {
                          _isMultiSelectMode = false;
                          _selectedTagIds.clear();
                        } else {
                          _isMultiSelectMode = true;
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isMultiSelectMode
                            ? AppTheme.primaryColor.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isMultiSelectMode ? Icons.deselect : Icons.checklist,
                        size: 18,
                        color: _isMultiSelectMode
                            ? AppTheme.primaryColor
                            : AppTheme.getTextSecondary(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showAddTagDialog(type),
                  ),
                ],
              ),
            ),
            // 多选操作栏
            if (_isMultiSelectMode)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  border: Border(
                      bottom: BorderSide(
                          color: AppTheme.getBorderColor(context)
                              .withValues(alpha: 0.2))),
                ),
                child: Row(
                  children: [
                    Text(
                      '已选择 ${_selectedTagIds.length} 项',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.primaryColor),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _deleteSelectedTags(),
                      child: Text('删除选中',
                          style: TextStyle(
                              fontSize: 16, color: AppTheme.errorColor)),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isMultiSelectMode = false;
                          _selectedTagIds.clear();
                        });
                      },
                      child: Text('取消选择',
                          style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.getTextSecondary(context))),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Listener(
                onPointerMove: (event) =>
                    _onGridPointerMove(type, event.position),
                child: GridView.builder(
                  key: _gridKeys.putIfAbsent(type, () => GlobalKey()),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.5,
                  ),
                  itemCount: totalCount,
                  itemBuilder: (context, index) {
                    final tag = displayedTags[index];
                    if (_isMultiSelectMode || tag.id == null) {
                      return _buildTagChip(tag);
                    }
                    return LayoutBuilder(
                      builder: (context, constraints) => Draggable<Tag>(
                        key: _cardKeys.putIfAbsent(tag.id!, () => GlobalKey()),
                        data: tag,
                        maxSimultaneousDrags: 1,
                        onDragStarted: () =>
                            _onDragStart(type, displayedTags, tag),
                        onDragEnd: (_) =>
                            _endDrag(type, orderedTags, displayedTags),
                        feedback: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            child: _buildTagChip(tag),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.35,
                          child: _buildShiftedChip(tag),
                        ),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: _buildShiftedChip(tag),
                        ),
                      ),
                    );
                  },
                ),
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
    final isSelected = _selectedTagIds.contains(tag.id);
    return GestureDetector(
      onSecondaryTapUp: _isMultiSelectMode
          ? null
          : (details) => _showTagContextMenu(tag, details.globalPosition),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () {
          if (_isMultiSelectMode) {
            setState(() {
              if (isSelected) {
                _selectedTagIds.remove(tag.id);
              } else {
                _selectedTagIds.add(tag.id!);
              }
            });
          } else {
            if (tag.id != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TagGamesPage(
                        tagId: tag.id!, tagName: tag.displayName ?? tag.name)),
              ).then((_) {
                ref.invalidate(allTagsProvider);
                ref.invalidate(allSeriesProvider);
              });
            }
          }
        },
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  border: Border.all(color: AppTheme.primaryColor, width: 2),
                  borderRadius:
                      BorderRadius.circular(GlassConstants.radiusMedium),
                )
              : null,
          child: Row(
            children: [
              Icon(
                tag.type == Tag.typeSeries ? Icons.category : Icons.label,
                size: 16,
                color: tag.type == Tag.typeSeries
                    ? AppTheme.secondaryColor
                    : AppTheme.primaryColor,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${tag.gameCount}',
                    style:
                        TextStyle(fontSize: 14, color: AppTheme.primaryColor),
                  ),
                ),
              const SizedBox(width: 4),
              if (!_isMultiSelectMode)
                IconButton(
                  icon: Icon(
                      tag.isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: tag.isFavorite
                          ? AppTheme.getFavoriteColor(context)
                          : null),
                  onPressed: () async {
                    await ref
                        .read(tagRepositoryProvider)
                        .toggleFavorite(tag.id!, !tag.isFavorite);
                    ref.invalidate(allTagsProvider);
                    ref.invalidate(allSeriesProvider);
                    ref.invalidate(favoriteTagsProvider);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSelectedTags() async {
    if (_selectedTagIds.isEmpty) return;

    final confirmed = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('删除选中',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextPrimary(context))),
            const SizedBox(height: 12),
            Text('确定要删除选中的 ${_selectedTagIds.length} 个标签/系列吗？',
                style: TextStyle(color: AppTheme.getTextSecondary(context))),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final tagRepo = ref.read(tagRepositoryProvider);
      for (final tagId in _selectedTagIds) {
        await tagRepo.deleteTag(tagId);
      }
      ref.invalidate(allTagsProvider);
      ref.invalidate(allSeriesProvider);
      ref.invalidate(favoriteTagsProvider);
      if (!mounted) return;
      setState(() {
        _isMultiSelectMode = false;
        _selectedTagIds.clear();
      });
      if (mounted) {
        AppTheme.showGlassToast(context,
            message: '已删除 ${_selectedTagIds.length} 项');
      }
    }
  }

  void _showTagContextMenu(Tag tag, Offset position) {
    // 默认系列类型不可右键操作
    final defaultSeries = ['RPG', 'ADV', 'ACT', 'SLG', 'AVG', 'FPS', 'TPS'];
    final isDefaultSeries =
        tag.type == Tag.typeSeries && defaultSeries.contains(tag.name);

    AppTheme.showGlassMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        if (!isDefaultSeries) ...[
          PopupMenuItem(
              value: 'edit',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit, size: 18),
                  title: Text('修改'))),
          PopupMenuItem(
              value: 'delete',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.delete, size: 18, color: AppTheme.errorColor),
                  title: Text('删除',
                      style: TextStyle(color: AppTheme.errorColor)))),
        ],
        if (isDefaultSeries)
          PopupMenuItem(
            enabled: false,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_outline,
                  size: 18,
                  color: AppTheme.getTextSecondary(context)
                      .withValues(alpha: 0.5)),
              title: Text('默认系列（不可修改）',
                  style: TextStyle(
                      color: AppTheme.getTextSecondary(context)
                          .withValues(alpha: 0.5))),
            ),
          ),
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
    showGlassDialog(
      context: context,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          final controller =
              TextEditingController(text: tag.displayName ?? tag.name);
          return SizedBox(
            width: GlassConstants.dialogWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tag.type == Tag.typeCustom ? '修改标签' : '修改系列',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.getTextPrimary(context))),
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
                      TextButton(
                        onPressed: () {
                          controller.dispose();
                          Navigator.pop(context);
                        },
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final name = controller.text.trim();
                          controller.dispose();
                          if (name.isNotEmpty) {
                            await ref
                                .read(tagRepositoryProvider)
                                .updateTag(tag.copyWith(
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
        },
      ),
    );
  }

  void _showDeleteTagConfirmDialog(Tag tag) {
    showGlassDialog(
      context: context,
      child: SizedBox(
        width: GlassConstants.dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tag.type == Tag.typeCustom ? '删除标签' : '删除系列',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getTextPrimary(context))),
              const SizedBox(height: 12),
              Text('确定要删除"${tag.displayName ?? tag.name}"吗？',
                  style: TextStyle(color: AppTheme.getTextSecondary(context))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      await ref.read(tagRepositoryProvider).deleteTag(tag.id!);
                      ref.invalidate(allTagsProvider);
                      ref.invalidate(allSeriesProvider);
                      ref.invalidate(favoriteTagsProvider);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor),
                    child: const Text('删除'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddTagDialog(String type) async {
    final result = await showGlassDialog<List<Tag>>(
      context: context,
      child: TagInputDialog(
        title: type == Tag.typeCustom ? '添加标签' : '添加系列',
        hintText: type == Tag.typeCustom
            ? '输入标签名称，回车或逗号分隔可连续添加'
            : '输入系列名称，回车或逗号分隔可连续添加',
        selectedTags: const [],
        availableTags: const [],
        showAvailable: false,
        newTagType: type,
      ),
    );
    if (result == null || result.isEmpty) return;
    final tagRepo = ref.read(tagRepositoryProvider);
    for (final tag in result) {
      await tagRepo.insertOrGetTag(tag.name, type);
    }
    ref.invalidate(allTagsProvider);
    ref.invalidate(allSeriesProvider);
  }
}
