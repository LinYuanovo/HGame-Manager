import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/services/image_service.dart';
import '../theme/app_theme.dart';
import '../pages/games/game_detail_page.dart';
import 'multi_select_controller.dart';

enum PaginationMode { paginated, infiniteScroll }
enum ContextMenuMode { games, played }

class GameListWidget extends ConsumerStatefulWidget {
  final List<Game> games;
  final Widget? appBarTitle;
  final List<Widget>? appBarActions;
  final void Function(Game)? onGameTap;
  final void Function(Tag)? onTagTap;
  final bool showSearchBar;
  final bool showAddButton;
  final bool showRefreshButton;
  final ContextMenuMode contextMenuMode;
  final bool isClearedPage;
  final void Function(List<Game> selectedGames)? onSelectionChanged;
  final VoidCallback? onScanSavePaths;
  final String scanProgress;

  const GameListWidget({
    super.key,
    required this.games,
    this.appBarTitle,
    this.appBarActions,
    this.onGameTap,
    this.onTagTap,
    this.showSearchBar = true,
    this.showAddButton = false,
    this.showRefreshButton = false,
    this.contextMenuMode = ContextMenuMode.games,
    this.isClearedPage = false,
    this.onSelectionChanged,
    this.onScanSavePaths,
    this.scanProgress = '',
  });

  @override
  ConsumerState<GameListWidget> createState() => _GameListWidgetState();
}

class _GameListWidgetState extends ConsumerState<GameListWidget> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final MultiSelectController<Game> _multiSelectController = MultiSelectController<Game>();
  ViewMode _viewMode = ViewMode.poster;
  SortMode _sortMode = SortMode.titleAsc;
  PaginationMode _paginationMode = PaginationMode.infiniteScroll;
  int _currentPage = 0;
  int _infiniteScrollCount = 20;
  int _savedPage = -1;  // 保存搜索前的页码，-1表示未保存
  String _lastSearchQuery = '';  // 上次的搜索词（用于检测变化）
  final TextEditingController _columnCountController = TextEditingController();
  int _listItemsPerPage = 5;  // 列表视图每页显示数量

  int get _itemsPerPage {
    if (_viewMode == ViewMode.list) return _listItemsPerPage;
    // 海报模式：在 _buildPosterView 中基于实际可用高度动态计算
    // 这里返回一个默认值，实际值在 buildPosterView 中通过 setState 更新
    return _posterItemsPerPage;
  }

  int _posterItemsPerPage = 6; // 由 _buildPosterView 动态更新

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _multiSelectController.addListener(_onSelectionChanged);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final viewModeStr = prefs.getString('game_list_view_mode');
    final sortModeStr = prefs.getString('game_list_sort_mode');
    final paginationModeStr = prefs.getString('game_list_pagination_mode');

    if (viewModeStr != null) {
      _viewMode = viewModeStr == 'poster' ? ViewMode.poster : ViewMode.list;
    }
    if (sortModeStr != null) {
      try { _sortMode = SortMode.values.firstWhere((m) => m.name == sortModeStr); } catch (_) {}
    }
    if (paginationModeStr != null) {
      _paginationMode = paginationModeStr == 'paginated' ? PaginationMode.paginated : PaginationMode.infiniteScroll;
    }
    
    // 加载持久化的搜索词
    final savedSearch = prefs.getString('game_list_search_query');
    if (savedSearch != null && savedSearch.isNotEmpty) {
      _searchController.text = savedSearch;
      _lastSearchQuery = savedSearch;
    }
    
    final savedColumnCount = prefs.getInt('column_count') ?? 3;
    _columnCountController.text = savedColumnCount.toString();

    // 兼容旧版以 String 存储的情况
    final rawItemsPerPage = prefs.getString('game_list_items_per_page');
    _listItemsPerPage = rawItemsPerPage != null
        ? (int.tryParse(rawItemsPerPage) ?? 5)
        : (prefs.getInt('game_list_items_per_page') ?? 5);

    if (mounted) setState(() {});
  }

  void _saveSetting(String key, String value) {
    ref.read(sharedPreferencesProvider).setString(key, value);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _columnCountController.dispose();
    _multiSelectController.removeListener(_onSelectionChanged);
    _multiSelectController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_paginationMode == PaginationMode.infiniteScroll &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      setState(() {
        _infiniteScrollCount += _itemsPerPage;
      });
    }
  }

  List<Game> _sortGames(List<Game> games) {
    final sorted = List<Game>.from(games);
    sorted.sort((a, b) {
      // 收藏优先
      final fav = (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0);
      if (fav != 0) return fav;
      // 评分高的优先（仅在已玩/已通关页面生效）
      if (widget.contextMenuMode == ContextMenuMode.played || widget.isClearedPage) {
        final ratingDiff = b.rating.compareTo(a.rating);
        if (ratingDiff != 0) return ratingDiff;
      }
      switch (_sortMode) {
        case SortMode.titleAsc:
          return (a.title ?? '').compareTo(b.title ?? '');
        case SortMode.titleDesc:
          return (b.title ?? '').compareTo(a.title ?? '');
        case SortMode.addedTimeDesc:
          // null值排到最后
          if (a.addedTime == null && b.addedTime == null) return 0;
          if (a.addedTime == null) return 1;
          if (b.addedTime == null) return -1;
          return b.addedTime!.compareTo(a.addedTime!);
        case SortMode.addedTimeAsc:
          // null值排到最后
          if (a.addedTime == null && b.addedTime == null) return 0;
          if (a.addedTime == null) return 1;
          if (b.addedTime == null) return -1;
          return a.addedTime!.compareTo(b.addedTime!);
      }
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _multiSelectController,
      builder: (context, _) {
        final searchQuery = _searchController.text.trim();
        var filteredGames = widget.games;
        
        // 搜索词变化时保存/恢复页码 + 持久化
        if (searchQuery != _lastSearchQuery) {
          if (searchQuery.isNotEmpty && _lastSearchQuery.isEmpty) {
            _savedPage = _currentPage;
            _currentPage = 0;
          } else if (searchQuery.isEmpty && _savedPage >= 0) {
            _currentPage = _savedPage;
            _savedPage = -1;
          } else if (searchQuery.isNotEmpty) {
            _currentPage = 0;
          }
          _lastSearchQuery = searchQuery;
          _saveSetting('game_list_search_query', searchQuery);
        }
        
        if (searchQuery.isNotEmpty) {
          filteredGames = filteredGames
              .where((g) =>
                  (g.title ?? '')
                      .toLowerCase()
                      .contains(searchQuery.toLowerCase()) ||
                  g.path
                      .toLowerCase()
                      .contains(searchQuery.toLowerCase()) ||
                  (g.intro ?? '')
                      .toLowerCase()
                      .contains(searchQuery.toLowerCase()))
              .toList();
        }
        final sortedGames = _sortGames(filteredGames);

        // Apply pagination
        List<Game> displayedGames;
        if (_paginationMode == PaginationMode.paginated) {
          final start = _currentPage * _itemsPerPage;
          final end = (start + _itemsPerPage).clamp(0, sortedGames.length);
          displayedGames =
              start < sortedGames.length ? sortedGames.sublist(start, end) : [];
        } else {
          displayedGames = sortedGames.take(_infiniteScrollCount).toList();
        }

        final totalPages = (sortedGames.length / _itemsPerPage).ceil();

        return Column(
          children: [
            // Toolbar row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  if (widget.showSearchBar) ...[
                    Expanded(
                      flex: 3,
                      child: Stack(
                        alignment: Alignment.centerRight,
                        children: [
                          GlassSearchBar(
                            controller: _searchController,
                            hintText: '搜索游戏（标题/路径/简介）...',
                            onChanged: (_) => setState(() {}),
                          ),
                          if (_searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                margin: const EdgeInsets.only(right: 30),
                                decoration: BoxDecoration(
                                  color: AppTheme.textSecondary.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  _buildViewModeToggle(),
                  const SizedBox(width: 12),
                  _buildPosterColumnCountInput(),
                  if (_viewMode == ViewMode.poster) const SizedBox(width: 12),
                  _buildSortDropdown(),
                  const SizedBox(width: 4),
                  _buildSortDirectionToggle(),
                  const SizedBox(width: 12),
                  _buildPaginationModeToggle(),
                  const SizedBox(width: 12),
                  _buildListItemsPerPageInput(),
                  if (_viewMode == ViewMode.list && _paginationMode == PaginationMode.paginated) const SizedBox(width: 12),
                  _buildMultiSelectToggle(sortedGames),
                  // 扫描存档按钮（始终显示，如果有回调）
                  if (widget.onScanSavePaths != null || widget.scanProgress.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _buildScanSaveButton(),
                  ],
                ],
              ),
            ),
            // 多选操作栏
            if (_multiSelectController.isMultiSelectMode)
              _buildMultiSelectActionBar(),
            // Game list
            Expanded(child: _buildGameList(displayedGames, sortedGames.length)),
            // Page navigation (only in paginated mode)
            if (_paginationMode == PaginationMode.paginated && totalPages > 1)
              _buildPageNavigation(totalPages),
          ],
        );
      },
    );
  }

  Widget _buildViewModeToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in [ViewMode.list, ViewMode.poster])
          Tooltip(
            message: mode == ViewMode.list ? '列表视图' : '海报视图',
            child: GestureDetector(
            onTap: () {
              setState(() {
                _viewMode = mode;
                _currentPage = 0;
                _savedPage = -1;
              });
              _saveSetting('game_list_view_mode', mode == ViewMode.poster ? 'poster' : 'list');
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _viewMode == mode
                    ? AppTheme.primaryColor.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getViewModeIcon(mode),
                size: 18,
                color: _viewMode == mode
                    ? AppTheme.primaryColor
                    : AppTheme.textSecondary,
              ),
            ),
          ),
          ),
      ],
    );
  }

  void _updateColumnCount(int count) {
    _columnCountController.text = count.toString();
    ref.read(isFixedColumnCountProvider.notifier).state = true;
    ref.read(fixedColumnCountProvider.notifier).state = count;
    ref.read(sharedPreferencesProvider).setBool('fixed_column_count', true);
    ref.read(sharedPreferencesProvider).setInt('column_count', count);
    setState(() {});
  }

  Widget _buildPosterColumnCountInput() {
    if (_viewMode != ViewMode.poster) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: '减少每行数量',
          child: GestureDetector(
            onTap: () {
              final current = int.tryParse(_columnCountController.text) ?? 3;
              if (current > 2) _updateColumnCount(current - 1);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.remove, size: 16, color: AppTheme.primaryColor),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 36,
          height: 28,
          alignment: Alignment.center,
          child: TextField(
            controller: _columnCountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              contentPadding: EdgeInsets.zero,
              filled: true,
              fillColor: AppTheme.backgroundColor.withValues(alpha: 0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
              ),
              isDense: true,
            ),
            onSubmitted: (value) {
              final count = int.tryParse(value);
              if (count != null && count >= 2 && count <= 8) {
                _updateColumnCount(count);
              } else {
                _columnCountController.text = (ref.read(fixedColumnCountProvider)).toString();
              }
            },
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: '增加每行数量',
          child: GestureDetector(
            onTap: () {
              final current = int.tryParse(_columnCountController.text) ?? 3;
              if (current < 8) _updateColumnCount(current + 1);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.add, size: 16, color: AppTheme.primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  IconData _getViewModeIcon(ViewMode mode) {
    switch (mode) {
      case ViewMode.list:
        return Icons.view_list;
      case ViewMode.poster:
        return Icons.grid_view;
    }
  }

  void _updateListItemsPerPage(int count) {
    setState(() {
      _listItemsPerPage = count;
      _currentPage = 0;
      _savedPage = -1;
    });
    ref.read(sharedPreferencesProvider).setInt('game_list_items_per_page', count);
  }

  Widget _buildListItemsPerPageInput() {
    if (_viewMode != ViewMode.list || _paginationMode != PaginationMode.paginated) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: '减少每页数量',
          child: GestureDetector(
            onTap: () {
              if (_listItemsPerPage > 3) _updateListItemsPerPage(_listItemsPerPage - 1);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.remove, size: 16, color: AppTheme.primaryColor),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$_listItemsPerPage',
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: '增加每页数量',
          child: GestureDetector(
            onTap: () {
              if (_listItemsPerPage < 20) _updateListItemsPerPage(_listItemsPerPage + 1);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.add, size: 16, color: AppTheme.primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSortDropdown() {
    final sortOptions = [
      SortMode.titleAsc,
      SortMode.addedTimeDesc,
    ];
    final sortLabels = {
      'titleAsc': '标题',
      'addedTimeDesc': '添加时间',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: sortOptions.map((mode) {
        final isSelected =
            _sortMode == mode || _isSameSortField(_sortMode, mode);
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: GlassChip(
            label: sortLabels[mode.name.replaceFirst(
                    RegExp(r'(Asc|Desc)$'), '')] ??
                _getSortLabel(mode),
            isSelected: isSelected,
            onTap: () {
              setState(() {
                if (_isSameSortField(_sortMode, mode)) {
                  _sortMode = _toggleDirection(_sortMode);
                } else {
                  _sortMode = mode;
                }
                _currentPage = 0;
                _savedPage = -1;
              });
              _saveSetting('game_list_sort_mode', _sortMode.name);
            },
          ),
        );
      }).toList(),
    );
  }

  bool _isSameSortField(SortMode a, SortMode b) {
    final aField = a.name.replaceFirst(RegExp(r'(Asc|Desc)$'), '');
    final bField = b.name.replaceFirst(RegExp(r'(Asc|Desc)$'), '');
    return aField == bField;
  }

  SortMode _toggleDirection(SortMode mode) {
    final isAsc = mode.name.endsWith('Asc');
    final field = mode.name.replaceFirst(RegExp(r'(Asc|Desc)$'), '');
    final target = isAsc ? 'Desc' : 'Asc';
    return SortMode.values.firstWhere((m) => m.name == '$field$target');
  }

  Widget _buildSortDirectionToggle() {
    final isAsc = _sortMode.name.endsWith('Asc');
    return Tooltip(
      message: isAsc ? '升序' : '降序',
      child: GestureDetector(
      onTap: () {
        setState(() {
          _sortMode = _toggleDirection(_sortMode);
          _currentPage = 0;
          _savedPage = -1;
        });
        _saveSetting('game_list_sort_mode', _sortMode.name);
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          isAsc ? Icons.arrow_upward : Icons.arrow_downward,
          size: 16,
          color: AppTheme.primaryColor,
        ),
      ),
    ),
    );
  }

  String _getSortLabel(SortMode mode) {
    switch (mode) {
      case SortMode.titleAsc:
      case SortMode.titleDesc:
        return '标题';
      case SortMode.addedTimeDesc:
      case SortMode.addedTimeAsc:
        return '添加时间';
    }
  }

  Widget _buildPaginationModeToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: '分页模式',
          child: GestureDetector(
          onTap: () {
            setState(() {
              _paginationMode = PaginationMode.paginated;
              _currentPage = 0;
              _savedPage = -1;
            });
            _saveSetting('game_list_pagination_mode', 'paginated');
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _paginationMode == PaginationMode.paginated
                  ? AppTheme.primaryColor.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.list_alt,
                size: 18,
                color: _paginationMode == PaginationMode.paginated
                    ? AppTheme.primaryColor
                    : AppTheme.textSecondary),
          ),
        ),
        ),
        Tooltip(
          message: '无限滚动',
          child: GestureDetector(
          onTap: () {
            setState(() {
              _paginationMode = PaginationMode.infiniteScroll;
              _infiniteScrollCount = 20;
              _savedPage = -1;
            });
            _saveSetting('game_list_pagination_mode', 'infiniteScroll');
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _paginationMode == PaginationMode.infiniteScroll
                  ? AppTheme.primaryColor.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.auto_awesome,
                size: 18,
                color: _paginationMode == PaginationMode.infiniteScroll
                    ? AppTheme.primaryColor
                    : AppTheme.textSecondary),
          ),
        ),
        ),
      ],
    );
  }

  Widget _buildMultiSelectToggle(List<Game> allGames) {
    return Tooltip(
      message: _multiSelectController.isMultiSelectMode ? '退出多选' : '多选模式',
      child: GestureDetector(
      onTap: () {
        if (_multiSelectController.isMultiSelectMode) {
          _multiSelectController.exitMultiSelectMode();
        } else {
          _multiSelectController.enterMultiSelectMode();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _multiSelectController.isMultiSelectMode
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _multiSelectController.isMultiSelectMode ? Icons.deselect : Icons.checklist,
          size: 18,
          color: _multiSelectController.isMultiSelectMode
              ? AppTheme.primaryColor
              : AppTheme.textSecondary,
        ),
      ),
    ),
    );
  }

  Widget _buildScanSaveButton() {
    if (widget.scanProgress.isNotEmpty) {
      return Tooltip(
        message: '扫描中...',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 6),
              Text(widget.scanProgress, style: TextStyle(fontSize: 13, color: AppTheme.primaryColor)),
            ],
          ),
        ),
      );
    }
    return Tooltip(
      message: '扫描存档位置',
      child: GestureDetector(
        onTap: widget.onScanSavePaths,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.manage_search, size: 18, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildMultiSelectActionBar() {
    // 计算当前页面的游戏列表（与 build 方法中的逻辑一致）
    final sortedGames = _sortGames(widget.games);
    final List<Game> currentPageGames;
    if (_paginationMode == PaginationMode.paginated) {
      final start = _currentPage * _itemsPerPage;
      final end = (start + _itemsPerPage).clamp(0, sortedGames.length);
      currentPageGames = start < sortedGames.length ? sortedGames.sublist(start, end) : [];
    } else {
      currentPageGames = sortedGames.take(_infiniteScrollCount).toList();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          const Spacer(),
          GestureDetector(
            onTap: () {
              _multiSelectController.selectAll(currentPageGames);
            },
            child: Text('全选', style: TextStyle(fontSize: 16, color: AppTheme.primaryColor)),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {
              _multiSelectController.invertSelection(currentPageGames);
            },
            child: Text('反选', style: TextStyle(fontSize: 16, color: AppTheme.primaryColor)),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () => _multiSelectController.exitMultiSelectMode(),
            child: Text('取消选择', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          ),
          const SizedBox(width: 24),
          Text(
            '已选择 ${_multiSelectController.selectedCount} 项',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildPageNavigation(int totalPages) {
    final pageController = TextEditingController();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.2))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPageButton(Icons.chevron_left, _currentPage > 0 ? () => setState(() => _currentPage--) : null),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${_currentPage + 1} / $totalPages',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.primaryColor)),
          ),
          const SizedBox(width: 8),
          _buildPageButton(Icons.chevron_right, _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            height: 30,
            child: TextField(
              controller: pageController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '页码',
                hintStyle: TextStyle(fontSize: 12, color: const Color.fromARGB(255, 135, 155, 194).withValues(alpha: 0.4)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                filled: true,
                fillColor: AppTheme.backgroundColor.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              onSubmitted: (value) {
                final page = int.tryParse(value);
                if (page != null && page >= 1 && page <= totalPages) {
                  setState(() => _currentPage = page - 1);
                }
                pageController.clear();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton(IconData icon, VoidCallback? onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: onPressed != null ? AppTheme.primaryColor.withValues(alpha: 0.1) : AppTheme.backgroundColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 18, color: onPressed != null ? AppTheme.primaryColor : AppTheme.textSecondary.withValues(alpha: 0.3)),
      ),
    );
  }

  Widget _buildGameList(List<Game> displayedGames, int totalCount) {
    if (totalCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videogame_asset_off_outlined,
                size: 64,
                color: AppTheme.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('暂无游戏',
                style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.6),
                    fontSize: 16)),
            const SizedBox(height: 8),
            Text('请先在设置中配置并扫描游戏库',
                style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.4),
                    fontSize: 13)),
          ],
        ),
      );
    }

    switch (_viewMode) {
      case ViewMode.list:
        return _buildListView(displayedGames);
      case ViewMode.poster:
        return _buildPosterView(displayedGames);
    }
  }

  Widget _buildListView(List<Game> games) {
    return LayoutBuilder(builder: (context, constraints) {
      final coverWidth = (constraints.maxWidth * 0.2).clamp(100.0, 200.0);
      final coverHeight = coverWidth * 9 / 16;
      return ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(GlassConstants.spacingMedium),
        itemCount: games.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: AppTheme.borderColor.withValues(alpha: 0.3)),
        itemBuilder: (_, index) => StaggeredItem(
          index: index,
          child: _buildListItem(games[index], coverWidth, coverHeight),
        ),
      );
    });
  }

  Widget _buildListItem(Game game, [double coverWidth = 120, double coverHeight = 68]) {
    final isBackupOnly = game.path.contains('${Platform.pathSeparator}Backup${Platform.pathSeparator}');
    final isSelected = _multiSelectController.isSelected(game);
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition, game),
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                border: Border.all(color: AppTheme.primaryColor, width: 2),
              )
            : null,
        child: InkWell(
        onTap: () {
          if (_multiSelectController.isMultiSelectMode) {
            final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
            if (isShiftPressed) {
              setState(() => _multiSelectController.selectRange(game, _sortGames(widget.games)));
            } else {
              setState(() => _multiSelectController.toggleSelection(game));
            }
          } else {
            _showGameDetail(game);
          }
        },
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
                child: SizedBox(
                  width: coverWidth,
                  height: coverHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildGameCover(game, fit: BoxFit.cover),
                    if (isBackupOnly)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_queue,
                                size: 16,
                                color: Colors.white70,
                              ),
                              SizedBox(width: 2),
                              Text(
                                '仅备份',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (game.path.contains('${Platform.pathSeparator}Cleared${Platform.pathSeparator}'))
                      Positioned(
                        top: 4,
                        left: isBackupOnly ? 70 : 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.emoji_events, size: 14, color: Colors.white),
                              SizedBox(width: 2),
                              Text('通关', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(game.title ?? '未命名',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: AppTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (game.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: game.tags.map((tag) {
                          return GestureDetector(
                            onTap: () {
                              if (widget.onTagTap != null) {
                                widget.onTagTap!(tag);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.primaryColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(tag.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      color: AppTheme.primaryColor)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (game.intro != null && game.intro!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(game.intro!,
                          style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary.withValues(alpha: 0.6)),
                           maxLines: 4,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildFavoriteButton(game),
              const SizedBox(width: 8),
              _buildPlayInfo(game),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPosterView(List<Game> games) {
    final isFixed = ref.watch(isFixedColumnCountProvider);
    final fixedCount = ref.watch(fixedColumnCountProvider);
    final crossAxisCount = isFixed ? fixedCount.clamp(2, 8) : 3;

    return LayoutBuilder(builder: (context, constraints) {
      final totalSpacing = (crossAxisCount - 1) * 16.0 + 32.0;
      final itemWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;
      // 16:9 image height + title area (padding 10*2 + title 16*1.3*2)
      final imageHeight = itemWidth * 9 / 16;
      final titleAreaHeight = 62.0;
      final itemHeight = imageHeight + titleAreaHeight;
      final aspectRatio = itemWidth / itemHeight;

      // 根据实际可用高度计算海报模式每页数量
      final rows = (constraints.maxHeight / (itemHeight + 16)).floor().clamp(1, 10);
      final newItemsPerPage = (rows * crossAxisCount).clamp(1, 50);
      if (newItemsPerPage != _posterItemsPerPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _posterItemsPerPage = newItemsPerPage);
          }
        });
      }

      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(GlassConstants.spacingMedium),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: aspectRatio,
        ),
        itemCount: games.length,
        itemBuilder: (_, index) => StaggeredItem(
          index: index,
          child: _buildPosterItem(games[index]),
        ),
      );
    });
  }

  Widget _buildPosterItem(Game game) {
    final isBackupOnly = game.path.contains('${Platform.pathSeparator}Backup${Platform.pathSeparator}');
    final isSelected = _multiSelectController.isSelected(game);
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition, game),
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
                border: Border.all(color: AppTheme.primaryColor, width: 2),
              )
            : null,
        child: GlassCard(
          enableHoverEffect: !isSelected,
          padding: EdgeInsets.zero,
        onTap: () {
          if (_multiSelectController.isMultiSelectMode) {
            final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
            if (isShiftPressed) {
              setState(() => _multiSelectController.selectRange(game, _sortGames(widget.games)));
            } else {
              setState(() => _multiSelectController.toggleSelection(game));
            }
          } else {
            _showGameDetail(game);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(GlassConstants.radiusLarge)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildGameCover(game, fit: BoxFit.cover),
                    if (isBackupOnly)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_queue,
                                size: 16,
                                color: Colors.white70,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '仅备份',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (game.path.contains('${Platform.pathSeparator}Cleared${Platform.pathSeparator}'))
                      Positioned(
                        top: 8,
                        left: isBackupOnly ? 110 : 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.emoji_events, size: 16, color: Colors.white),
                              SizedBox(width: 4),
                              Text('通关', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () async {
                          final repo = ref.read(gameRepositoryProvider);
                          await repo.updateFavoriteStatus(
                              game.id!, !game.isFavorite);
                          ref.invalidate(allGamesProvider);
                          ref.invalidate(favoriteGamesProvider);
                          ref.invalidate(playedGamesProvider);
                          ref.invalidate(clearedGamesProvider);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Icon(
                            game.isFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 20,
                            color: game.isFavorite
                                ? const Color(0xFFFF6B9D)
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                    if (game.rating > 0)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(5, (index) {
                              final starValue = index + 1;
                              if (game.rating >= starValue) {
                                return const Icon(Icons.star, size: 20, color: Color(0xFFFFD700));
                              } else if (game.rating >= starValue - 0.5) {
                                return const Icon(Icons.star_half, size: 20, color: Color(0xFFFFD700));
                              } else {
                                return Icon(Icons.star_border, size: 20, color: Colors.white.withValues(alpha: 0.5));
                              }
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    game.title ?? '未命名',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildGameCover(Game game,
      {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    final coverIndex = game.coverIndex
        .clamp(0, game.images.length > 0 ? game.images.length - 1 : 0);
    final coverPath =
        game.images.isNotEmpty ? game.images[coverIndex].imagePath : null;

    return coverPath != null
        ? Image.file(
            File(coverPath),
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => Container(
              width: width,
              height: height,
              color: AppTheme.backgroundColor.withValues(alpha: 0.3),
              child: Center(
                  child: Icon(Icons.videogame_asset,
                      size: (width ?? 70) * 0.5,
                      color: AppTheme.textSecondary.withValues(alpha: 0.25))),
            ),
          )
        : Container(
            width: width,
            height: height,
            color: AppTheme.backgroundColor.withValues(alpha: 0.3),
            child: Center(
                child: Icon(Icons.videogame_asset,
                    size: (width ?? 70) * 0.5,
                    color: AppTheme.textSecondary.withValues(alpha: 0.25))),
          );
  }

  Widget _buildFavoriteButton(Game game) {
    return GestureDetector(
      onTap: () async {
        final repo = ref.read(gameRepositoryProvider);
        await repo.updateFavoriteStatus(game.id!, !game.isFavorite);
        ref.invalidate(allGamesProvider);
        ref.invalidate(favoriteGamesProvider);
        ref.invalidate(playedGamesProvider);
        ref.invalidate(clearedGamesProvider);
      },
      child: Icon(
        game.isFavorite ? Icons.favorite : Icons.favorite_border,
        size: 24,
        color: game.isFavorite
            ? const Color(0xFFFF6B9D)
            : AppTheme.textSecondary.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildPlayInfo(Game game) {
    String infoText;
    if (game.isPlayed) {
      infoText = '已玩 ${game.playCount}次';
    } else {
      infoText = '未游玩';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(infoText,
            style: TextStyle(
                fontSize: 13,
                color: game.isPlayed
                    ? AppTheme.successColor
                    : AppTheme.textSecondary.withValues(alpha: 0.5))),
        if (game.lastPlayedTime != null) ...[
          const SizedBox(height: 2),
          Text(_formatDate(game.lastPlayedTime!),
              style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary.withValues(alpha: 0.4))),
        ],
      ],
    );
  }

  void _showGameDetail(Game game) {
    if (widget.onGameTap != null) {
      widget.onGameTap!(game);
      return;
    }
    showDialog<Tag>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => GameDetailDialog(
        game: game,
        onTagTap: (tag) => Navigator.of(dialogContext).pop(tag),
      ),
    ).then((tag) {
      if (tag != null && widget.onTagTap != null) {
        widget.onTagTap!(tag);
      }
    });
  }

  void _showContextMenu(
      BuildContext context, Offset position, Game game) {
    final isBackupOnly = game.path.contains('${Platform.pathSeparator}Backup${Platform.pathSeparator}');
    final isMultiSelect = _multiSelectController.isMultiSelectMode;
    AppTheme.showGlassMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
            value: 'open_folder',
            child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.folder_open, size: 18),
                title: const Text('打开文件夹'))),
        if (widget.contextMenuMode == ContextMenuMode.played && game.savePath != null && game.savePath!.isNotEmpty)
          PopupMenuItem(
              value: 'open_save',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.folder_special, size: 18, color: AppTheme.primaryColor),
                  title: const Text('打开存档位置'))),
        PopupMenuItem(
            value: 'favorite',
            child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    game.isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: game.isFavorite ? Color(0xFFFF6B9D) : null),
                title: Text(game.isFavorite ? '取消收藏' : '添加收藏'))),
        PopupMenuItem(
            value: 'played',
            child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    widget.contextMenuMode == ContextMenuMode.played
                        ? Icons.remove_circle_outline
                        : Icons.add_circle_outline,
                    size: 18),
                title: Text(widget.contextMenuMode == ContextMenuMode.played
                    ? '减少游玩次数'
                    : '增加游玩次数'))),
        // 移入自定义系列（仅在有自定义系列时显示）
        if (_hasCustomSeries())
          PopupMenuItem(
              value: 'move_to_series',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.playlist_add, size: 18, color: AppTheme.primaryColor),
                  title: const Text('移入自定义系列'))),
        if (game.images.length > 1 && !isMultiSelect)
          PopupMenuItem(
              value: 'cover',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.image, size: 18),
                  title: Text(
                      '选择封面 (${game.coverIndex + 1}/${game.images.length})'))),
        if (!isMultiSelect)
          PopupMenuItem(
              value: 'review',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.rate_review_outlined, size: 18, color: AppTheme.primaryColor),
                  title: const Text('评论', style: TextStyle(color: AppTheme.textPrimary)))),
        // 标记已通关（仅在非已通关页面显示）
        if (!widget.isClearedPage)
          PopupMenuItem(
              value: 'cleared',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.emoji_events, size: 18, color: Color(0xFFFFD700)),
                  title: const Text('标记已通关', style: TextStyle(color: Color(0xFFFFD700))))),
        // 取消标记已通关（仅在已通关页面显示）
        if (widget.isClearedPage)
          PopupMenuItem(
              value: 'uncleared',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.emoji_events_outlined, size: 18, color: Colors.grey),
                  title: const Text('取消标记已通关', style: TextStyle(color: Colors.grey)))),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: 'blacklist',
            child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading:
                    Icon(Icons.block, size: 18, color: const Color(0xFFFFA000)),
                title: const Text('删除记录',
                    style: TextStyle(color: Color(0xFFFFA000))))),
        if (!isBackupOnly)
          PopupMenuItem(
              value: 'delete_folder',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.folder_delete_outlined, size: 18, color: AppTheme.errorColor),
                  title: const Text('删除本地文件夹',
                      style: TextStyle(color: AppTheme.errorColor)))),
      ],
    ).then((value) async {
      if (value == null) return;
      final repo = ref.read(gameRepositoryProvider);

      // 多选模式下对所有选中游戏执行操作，否则只对右键的游戏
      final List<Game> targets = (isMultiSelect && _multiSelectController.selectedCount > 1)
          ? _multiSelectController.selectedItems.toList()
          : [game];

      switch (value) {
        case 'open_folder':
          for (final g in targets) {
            await launchUrl(Uri.file(g.path));
          }
          break;
        case 'favorite':
          final newFav = !game.isFavorite;
          for (final g in targets) {
            await repo.updateFavoriteStatus(g.id!, newFav);
          }
          ref.invalidate(allGamesProvider);
          ref.invalidate(favoriteGamesProvider);
          ref.invalidate(playedGamesProvider);
          ref.invalidate(clearedGamesProvider);
          break;
        case 'played':
          for (final g in targets) {
            if (widget.contextMenuMode == ContextMenuMode.played) {
              await repo.decrementPlayCount(g.id!);
            } else {
              await repo.incrementPlayCount(g.id!);
              _scanSavePathForGame(g);
            }
          }
          ref.invalidate(allGamesProvider);
          ref.invalidate(playedGamesProvider);
          break;
        case 'cleared':
          for (final g in targets) {
            await _markAsCleared(g);
          }
          break;
        case 'uncleared':
          for (final g in targets) {
            await _unmarkAsCleared(g);
          }
          break;
        case 'review':
          _showReviewDialog(game);
          break;
        case 'move_to_series':
          _showMoveToSeriesDialog(targets);
          break;
        case 'cover':
          final selected = await showDialog<int>(
            context: context,
            builder: (ctx) => _CoverPickerDialog(game: game),
          );
          if (selected != null) {
            await repo.updateCoverIndex(game.id!, selected);
            ref.invalidate(allGamesProvider);
          }
          break;
        case 'open_save':
          if (game.savePath != null && game.savePath!.isNotEmpty) {
            final confirmed = await showGlassDialog<bool>(
              context: context,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('打开存档位置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    Text(
                      '该存档位置为自动扫描结果，可能存在错误。\n\n${game.savePath}',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
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
                          child: const Text('打开'),
                        ),
                      ],
                      ),
                    ],
                  ),
                ),
              );
              if (confirmed == true) {
              try {
                await launchUrl(Uri.file(game.savePath!));
              } catch (e) {
                if (mounted) {
                  AppTheme.showGlassToast(context, message: '无法打开路径: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
                }
              }
            }
          }
          break;
        case 'blacklist':
          final confirm = await showGlassDialog<bool>(
            context: context,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('删除记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  Text(targets.length > 1
                      ? '确定要删除选中的 ${targets.length} 个游戏的记录吗？\n路径将加入黑名单，后续扫描不再入库。\n不会删除实际文件。'
                      : '确定要删除"${game.title}"的记录吗？\n路径将加入黑名单，后续扫描不再入库。\n不会删除实际文件。',
                      style: const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFA000)),
                        child: const Text('确认'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
          if (confirm == true) {
            for (final g in targets) {
              _addToBlacklist(g.path);
              if (g.id != null) {
                await repo.deleteGame(g.id!);
              }
            }
            _multiSelectController.exitMultiSelectMode();
            ref.invalidate(allGamesProvider);
            ref.invalidate(clearedGamesProvider);
          }
          break;
        case 'delete_folder':
          final confirm = await showGlassDialog<bool>(
            context: context,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('删除本地文件夹', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  Text(targets.length > 1
                      ? '确定要删除选中的 ${targets.length} 个游戏的本地文件夹吗？\n此操作不可恢复！'
                      : '确定要删除"${game.title}"的本地文件夹吗？\n此操作不可恢复！\n\n${game.path}',
                      style: const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.errorColor),
                        child: const Text('删除文件夹'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
          if (confirm == true) {
            int successCount = 0;
            for (final g in targets) {
              try {
                final dir = Directory(g.path);
                if (await dir.exists()) {
                  await dir.delete(recursive: true);
                }
                await repo.deleteGame(g.id!);
                successCount++;
              } catch (e) {
                // continue with other games
              }
            }
            _multiSelectController.exitMultiSelectMode();
            ref.invalidate(allGamesProvider);
            if (mounted) {
              AppTheme.showGlassToast(context, message: '已删除 $successCount 个文件夹');
            }
          }
          break;
      }
    });
  }

  void _showReviewDialog(Game game) {
    showDialog(
      context: context,
      builder: (dialogContext) => _ReviewDialog(
        game: game,
        onSave: (rating, review) async {
          try {
            final repo = ref.read(gameRepositoryProvider);
            var gameId = game.id;
            if (gameId == null) {
              debugPrint('[Review] Game has no id, inserting into DB: ${game.path}');
              gameId = await repo.insertGame(game);
              debugPrint('[Review] Inserted game with id: $gameId');
            }
            await repo.updateRatingReview(gameId, rating, review.isEmpty ? null : review);
            debugPrint('[Review] Updated rating=$rating, review=${review.isEmpty ? "null" : review} for game id=$gameId');
            ref.invalidate(allGamesProvider);
            ref.invalidate(playedGamesProvider);
            ref.invalidate(clearedGamesProvider);
            ref.invalidate(favoriteGamesProvider);
            if (mounted) {
              AppTheme.showGlassToast(context, message: '评论已保存');
            }
          } catch (e, stackTrace) {
            debugPrint('[Review] Error saving review: $e\n$stackTrace');
            if (mounted) {
              AppTheme.showGlassToast(
                context,
                message: '保存失败: $e',
                icon: Icons.error_outline,
                iconColor: AppTheme.errorColor,
              );
            }
          }
        },
      ),
    );
  }

  String _formatPath(String path) {
    return path.replaceAll('\\', '/');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _markAsCleared(Game game) async {
    final gameName = game.title ?? path.basename(game.path);
    // 确认对话框
    final confirm = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('标记已通关', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text('确定要将"$gameName"标记为已通关吗？\n\n游戏将移动到 Sorted/Cleared 目录，\n并自动创建备份。', style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700)),
                  child: const Text('确认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final sortedPath = prefs.getString('sorted_path') ?? '';

      if (sortedPath.isEmpty) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '请先在设置中配置整理目录', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return;
      }

      // 使用更健壮的路径检查
      final normalizedPath = game.path.replaceAll('\\', '/');
      final isBackupOnly = normalizedPath.contains('/Backup/') || 
                           normalizedPath.endsWith('/Backup') ||
                           normalizedPath.contains('\\Backup\\') ||
                           normalizedPath.endsWith('\\Backup');

      if (isBackupOnly) {
        // 删除关联的图片文件
        final imageService = ImageService();
        final storageDir = await imageService.getImageStorageDir();
        for (final img in game.images) {
          if (img.imagePath.startsWith(storageDir)) {
            await imageService.deleteImageFile(img.imagePath);
          }
        }

        // 直接删除备份
        final backupDir = Directory(game.path);
        if (await backupDir.exists()) {
          await backupDir.delete(recursive: true);
        }

        // 如果有数据库记录，也删除
        if (game.id != null) {
          final repo = ref.read(gameRepositoryProvider);
          await repo.deleteGame(game.id!);
        }

        ref.invalidate(allGamesProvider);
        ref.invalidate(clearedGamesProvider);

        if (mounted) {
          AppTheme.showGlassToast(context, message: '已删除"$gameName"的备份');
        }
        return;
      }

      final gameDir = Directory(game.path);
      if (!await gameDir.exists()) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '游戏目录不存在', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return;
      }

      // 创建Cleared目录
      final clearedDir = Directory('$sortedPath${Platform.pathSeparator}Cleared');
      if (!await clearedDir.exists()) {
        await clearedDir.create(recursive: true);
      }

      // 创建Backup目录
      final backupDir = Directory('$sortedPath${Platform.pathSeparator}Cleared${Platform.pathSeparator}Backup');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // 创建游戏备份目录（使用游戏标题作为文件夹名）
      final gameTitle = game.title ?? path.basename(game.path);
      final sanitizedTitle = gameTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final backupGameDir = Directory('${backupDir.path}${Platform.pathSeparator}$sanitizedTitle');
      if (!await backupGameDir.exists()) {
        await backupGameDir.create(recursive: true);
      }

      // 复制metadata.json到备份
      final metadataFile = File('${game.path}${Platform.pathSeparator}metadata.json');
      if (await metadataFile.exists()) {
        await metadataFile.copy('${backupGameDir.path}${Platform.pathSeparator}metadata.json');
      }

      // 复制source_url.txt到备份
      final sourceUrlFile = File('${game.path}${Platform.pathSeparator}source_url.txt');
      if (await sourceUrlFile.exists()) {
        await sourceUrlFile.copy('${backupGameDir.path}${Platform.pathSeparator}source_url.txt');
      }

      // 复制images目录到备份
      final imagesDir = Directory('${game.path}${Platform.pathSeparator}images');
      final backupImagesDir = Directory('${backupGameDir.path}${Platform.pathSeparator}images');
      if (!await backupImagesDir.exists()) {
        await backupImagesDir.create(recursive: true);
      }
      
      // 复制游戏目录下的images文件夹
      if (await imagesDir.exists()) {
        await for (final entity in imagesDir.list()) {
          if (entity is File) {
            final fileName = path.basename(entity.path);
            await entity.copy('${backupImagesDir.path}${Platform.pathSeparator}$fileName');
          }
        }
      }
      
      // 复制game_images目录中用户手动添加的图片
      final repo = ref.read(gameRepositoryProvider);
      final gameImages = await repo.getGameImages(game.id!);
      final imageService = ImageService();
      final storageDir = await imageService.getImageStorageDir();
      for (final img in gameImages) {
        if (img.imagePath.startsWith(storageDir)) {
          final file = File(img.imagePath);
          if (await file.exists()) {
            final fileName = path.basename(img.imagePath);
            final destPath = '${backupImagesDir.path}${Platform.pathSeparator}$fileName';
            if (!await File(destPath).exists()) {
              await file.copy(destPath);
            }
          }
        }
      }

      // 移动游戏目录到Cleared
      final newPath = '${clearedDir.path}${Platform.pathSeparator}${path.basename(game.path)}';
      final newDir = Directory(newPath);
      if (await newDir.exists()) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '目标目录已存在: ${path.basename(game.path)}，请先处理冲突', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return;
      }
      
      await gameDir.rename(newPath);
      await repo.updateGamePath(game.id!, newPath);

      final oldImages = await repo.getGameImages(game.id!);
      if (oldImages.isNotEmpty) {
        final storageDir = await imageService.getImageStorageDir();
        final updatedImages = oldImages.map((img) {
          // 确保路径格式一致：统一使用正斜杠
          final normalizedOldPath = game.path.replaceAll('\\', '/');
          final normalizedNewPath = newPath.replaceAll('\\', '/');
          final normalizedImagePath = img.imagePath.replaceAll('\\', '/');
          
          // 检查旧路径是否在图片路径中
          String newImagePath;
          if (normalizedImagePath.startsWith(normalizedOldPath)) {
            // 游戏目录中的图片，更新路径
            newImagePath = normalizedImagePath.replaceFirst(normalizedOldPath, normalizedNewPath);
          } else if (img.imagePath.startsWith(storageDir)) {
            // game_images目录中的图片，更新为备份目录路径
            final fileName = path.basename(img.imagePath);
            newImagePath = '${backupImagesDir.path}${Platform.pathSeparator}$fileName';
          } else {
            // 其他情况保持原路径不变
            newImagePath = img.imagePath;
          }
          
          return GameImage(
            id: img.id,
            gameId: img.gameId,
            imagePath: newImagePath,
            sortOrder: img.sortOrder,
          );
        }).toList();
        await repo.setGameImages(game.id!, updatedImages);
      }

      ref.invalidate(allGamesProvider);
      ref.invalidate(clearedGamesProvider);

      if (mounted) {
        AppTheme.showGlassToast(context, message: '已标记"$gameName"为已通关');
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '操作失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  Future<void> _unmarkAsCleared(Game game) async {
    final gameName = game.title ?? path.basename(game.path);
    // 使用更健壮的路径检查，统一使用正斜杠
    final normalizedPath = game.path.replaceAll('\\', '/');
    final isBackupOnly = normalizedPath.contains('/Backup/') || 
                         normalizedPath.endsWith('/Backup') ||
                         normalizedPath.contains('\\Backup\\') ||
                         normalizedPath.endsWith('\\Backup');
    // 确认对话框
    final confirm = await showGlassDialog<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('取消标记已通关', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text(
              isBackupOnly
                  ? '确定要将"$gameName"取消已通关吗？\n\n该备份将被删除，此操作不可恢复。'
                  : '确定要将"$gameName"取消已通关吗？\n\n游戏将移回 Sorted 目录，备份将被删除。',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey),
                  child: const Text('确认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final sortedPath = prefs.getString('sorted_path') ?? '';

      if (sortedPath.isEmpty) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '请先在设置中配置整理目录', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return;
      }

      // 处理仅备份游戏：直接删除备份
      if (isBackupOnly) {
        // 删除关联的图片文件
        final imageService = ImageService();
        final storageDir = await imageService.getImageStorageDir();
        for (final img in game.images) {
          if (img.imagePath.startsWith(storageDir)) {
            await imageService.deleteImageFile(img.imagePath);
          }
        }

        final backupDir = Directory(game.path);
        if (await backupDir.exists()) {
          await backupDir.delete(recursive: true);
        }

        // 如果有数据库记录，也删除
        if (game.id != null) {
          final repo = ref.read(gameRepositoryProvider);
          await repo.deleteGame(game.id!);
        }

        ref.invalidate(allGamesProvider);
        ref.invalidate(clearedGamesProvider);

        if (mounted) {
          AppTheme.showGlassToast(context, message: '已删除"$gameName"的备份');
        }
        return;
      }

      final gameDir = Directory(game.path);
      if (!await gameDir.exists()) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '游戏目录不存在', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return;
      }

      // 读取 metadata.json 中的 series 字段
      String targetCategory = 'Unclassified';
      final metadataFile = File('${game.path}${Platform.pathSeparator}metadata.json');
      if (await metadataFile.exists()) {
        try {
          final content = await metadataFile.readAsString();
          final metadata = jsonDecode(content) as Map<String, dynamic>;
          final series = metadata['series'] as String?;
          if (series != null && series.isNotEmpty) {
            targetCategory = series;
          }
        } catch (e) {
          // 忽略解析错误，使用默认分类
        }
      }

      // 创建目标目录
      final targetDir = Directory('$sortedPath${Platform.pathSeparator}$targetCategory');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // 移动游戏目录到目标目录
      final newPath = '${targetDir.path}${Platform.pathSeparator}${path.basename(game.path)}';
      final newDir = Directory(newPath);
      if (await newDir.exists()) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '目标目录已存在: ${path.basename(game.path)}，请先处理冲突', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return;
      }
      
      await gameDir.rename(newPath);
      final repo = ref.read(gameRepositoryProvider);
      await repo.updateGamePath(game.id!, newPath);

      final oldImages = await repo.getGameImages(game.id!);
      if (oldImages.isNotEmpty) {
        final updatedImages = oldImages.map((img) {
          // 确保路径格式一致：统一使用正斜杠
          final normalizedOldPath = game.path.replaceAll('\\', '/');
          final normalizedNewPath = newPath.replaceAll('\\', '/');
          final normalizedImagePath = img.imagePath.replaceAll('\\', '/');
          
          // 检查旧路径是否在图片路径中
          String newImagePath;
          if (normalizedImagePath.startsWith(normalizedOldPath)) {
            newImagePath = normalizedImagePath.replaceFirst(normalizedOldPath, normalizedNewPath);
          } else {
            // 如果路径不匹配，保持原路径不变（图片可能在game_images目录中）
            newImagePath = img.imagePath;
          }
          
          return GameImage(
            id: img.id,
            gameId: img.gameId,
            imagePath: newImagePath,
            sortOrder: img.sortOrder,
          );
        }).toList();
        await repo.setGameImages(game.id!, updatedImages);
      }

      // 删除对应的 Backup 目录
      final backupDir = Directory('$sortedPath${Platform.pathSeparator}Cleared${Platform.pathSeparator}Backup');
      if (await backupDir.exists()) {
        final gameTitle = game.title ?? path.basename(game.path);
        final sanitizedTitle = gameTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        final backupGameDir = Directory('${backupDir.path}${Platform.pathSeparator}$sanitizedTitle');
        if (await backupGameDir.exists()) {
          await backupGameDir.delete(recursive: true);
        }
      }

      // 刷新游戏列表
      ref.invalidate(allGamesProvider);
      ref.invalidate(clearedGamesProvider);

      if (mounted) {
        AppTheme.showGlassToast(context, message: '已取消"$gameName"的已通关标记');
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '操作失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  bool _hasCustomSeries() {
    final seriesAsync = ref.read(allSeriesProvider);
    return seriesAsync.whenOrNull(data: (series) => series.isNotEmpty) ?? false;
  }

  void _showMoveToSeriesDialog(List<Game> games) async {
    final seriesAsync = ref.read(allSeriesProvider);
    final customTags = seriesAsync.whenOrNull(data: (series) => series) ?? [];
    
    if (customTags.isEmpty) {
      AppTheme.showGlassToast(context, message: '暂无自定义标签');
      return;
    }

    final firstGame = games.first;
    final currentTagIds = firstGame.tags.map((t) => t.id).toSet();
    final selectedTagIds = <int>{...currentTagIds.where((id) => id != null).cast<int>()};

    final title = games.length == 1
        ? (firstGame.title ?? '未命名游戏')
        : '已选择 ${games.length} 个游戏';

    final result = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => _MoveToSeriesDialog(
        customTags: customTags,
        selectedTagIds: selectedTagIds,
        gameTitle: title,
      ),
    );

    if (result != null) {
      final repo = ref.read(gameRepositoryProvider);

      for (final game in games) {
        if (game.id == null) continue;
        final gameTagIds = game.tags.map((t) => t.id).toSet();

        for (final tag in customTags) {
          if (tag.id != null && gameTagIds.contains(tag.id)) {
            await repo.removeTagFromGame(game.id!, tag.id!);
          }
        }

        for (final tagId in result) {
          await repo.addTagToGame(game.id!, tagId);
        }
      }

      ref.invalidate(allGamesProvider);
      ref.invalidate(playedGamesProvider);
      ref.invalidate(favoriteGamesProvider);
      ref.invalidate(allSeriesProvider);

      if (mounted) {
        AppTheme.showGlassToast(context, message: '已更新 ${games.length} 个游戏的标签');
      }
    }
  }

  void _addToBlacklist(String gamePath) {
    final prefs = ref.read(sharedPreferencesProvider);
    final existing = prefs.getString('game_blacklist') ?? '';
    final paths = existing.split('\n').where((s) => s.trim().isNotEmpty).toList();
    if (!paths.contains(gamePath)) {
      paths.add(gamePath);
      prefs.setString('game_blacklist', paths.join('\n'));
    }
  }

  void _onSelectionChanged() {
    if (widget.onSelectionChanged != null) {
      widget.onSelectionChanged!(_multiSelectController.selectedItems.toList());
    }
  }

  Future<void> _scanSavePathForGame(Game game) async {
    try {
      // 跳过"仅备份"游戏
      if (game.path.contains('${Platform.pathSeparator}Backup${Platform.pathSeparator}')) {
        return;
      }

      final repo = ref.read(gameRepositoryProvider);
      final saveService = ref.read(savePathServiceProvider);

      final freshGame = await repo.getGameById(game.id!);
      if (freshGame != null && freshGame.savePath != null && freshGame.savePath!.isNotEmpty) {
        return;
      }

      final savePath = await saveService.scanWithConfidence(game.path, game.title);
      if (savePath != null) {
        await repo.updateSavePath(game.id!, savePath);
        if (mounted) {
          AppTheme.showGlassToast(context, message: '已找到"${game.title}"可能的存档位置');
        }
      } else {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '未找到"${game.title}"的存档位置', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
        }
      }

      ref.invalidate(playedGamesProvider);
    } catch (e) {
      debugPrint('[SavePath] Error scanning save path for ${game.title}: $e');
    }
  }
}

class _CoverPickerDialog extends StatelessWidget {
  final Game game;
  const _CoverPickerDialog({required this.game});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择封面图片',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            Text('当前封面: 第 ${game.coverIndex + 1} 张 / 共 ${game.images.length} 张',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < game.images.length; i++)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(i),
                    child: Container(
                      width: 100,
                      height: 130,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: i == game.coverIndex
                              ? AppTheme.primaryColor
                              : AppTheme.borderColor.withValues(alpha: 0.3),
                          width: i == game.coverIndex ? 3 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(game.images[i].imagePath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppTheme.backgroundColor
                                    .withValues(alpha: 0.3),
                                child: const Icon(Icons.broken_image,
                                    size: 24, color: AppTheme.textSecondary),
                              ),
                            ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white)),
                              ),
                            ),
                            if (i == game.coverIndex)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                      color: AppTheme.primaryColor,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.check,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  final Game game;
  final void Function(double rating, String review) onSave;

  const _ReviewDialog({required this.game, required this.onSave});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late double _rating;
  late TextEditingController _reviewController;

  @override
  void initState() {
    super.initState();
    _rating = widget.game.rating;
    _reviewController = TextEditingController(text: widget.game.review ?? '');
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  double _calcRatingFromX(double x, double totalWidth) {
    final starWidth = totalWidth / 5;
    final rawRating = (x / starWidth);
    final clamped = rawRating.clamp(0.0, 5.0);
    return (clamped * 2).round() / 2; // round to nearest 0.5
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
      ),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.game.title ?? '未命名游戏',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            const Text(
              '评分',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                const starSize = 32.0;
                const starGap = 4.0;
                const starAreaWidth = 5 * (starSize + starGap) - starGap;
                return Listener(
                  onPointerDown: (event) {
                    final newRating = _calcRatingFromX(event.localPosition.dx, starAreaWidth);
                    if (newRating != _rating) setState(() => _rating = newRating);
                  },
                  onPointerMove: (event) {
                    final newRating = _calcRatingFromX(event.localPosition.dx, starAreaWidth);
                    if (newRating != _rating) setState(() => _rating = newRating);
                  },
                  child: Row(
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      IconData icon;
                      if (_rating >= starValue) {
                        icon = Icons.star;
                      } else if (_rating >= starValue - 0.5) {
                        icon = Icons.star_half;
                      } else {
                        icon = Icons.star_border;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: starGap),
                        child: Icon(
                          icon,
                          size: starSize,
                          color: icon == Icons.star_border ? Colors.grey.shade400 : const Color(0xFFFFD700),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
            if (_rating > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _rating == _rating.roundToDouble() ? '${_rating.toInt()} / 5' : '$_rating / 5',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              '评论',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reviewController,
              maxLines: 5,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: '写下你的评论...',
                hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(_rating, _reviewController.text);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoveToSeriesDialog extends StatefulWidget {
  final List<Tag> customTags;
  final Set<int> selectedTagIds;
  final String gameTitle;

  const _MoveToSeriesDialog({
    required this.customTags,
    required this.selectedTagIds,
    required this.gameTitle,
  });

  @override
  State<_MoveToSeriesDialog> createState() => _MoveToSeriesDialogState();
}

class _MoveToSeriesDialogState extends State<_MoveToSeriesDialog> {
  late Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.selectedTagIds);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
      ),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '移入自定义系列',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              widget.gameTitle,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.customTags.map((tag) {
                    final isSelected = _selectedIds.contains(tag.id);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedIds.remove(tag.id);
                          } else {
                            _selectedIds.add(tag.id!);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryColor.withValues(alpha: 0.15)
                              : AppTheme.backgroundColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : AppTheme.borderColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              Icon(Icons.check, size: 16, color: AppTheme.primaryColor),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              tag.displayName ?? tag.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedIds.toList()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
