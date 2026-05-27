import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../theme/app_theme.dart';
import '../pages/games/game_detail_page.dart';

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
  });

  @override
  ConsumerState<GameListWidget> createState() => _GameListWidgetState();
}

class _GameListWidgetState extends ConsumerState<GameListWidget> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  ViewMode _viewMode = ViewMode.poster;
  SortMode _sortMode = SortMode.titleAsc;
  PaginationMode _paginationMode = PaginationMode.infiniteScroll;
  int _currentPage = 0;
  int _infiniteScrollCount = 20;

  int get _itemsPerPage => _viewMode == ViewMode.list ? 5 : 6;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
    if (mounted) setState(() {});
  }

  void _saveSetting(String key, String value) {
    ref.read(sharedPreferencesProvider).setString(key, value);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
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
      final fav = (b.isFavorite ? 1 : 0).compareTo(a.isFavorite ? 1 : 0);
      if (fav != 0) return fav;
      switch (_sortMode) {
        case SortMode.titleAsc:
          return (a.title ?? '').compareTo(b.title ?? '');
        case SortMode.titleDesc:
          return (b.title ?? '').compareTo(a.title ?? '');
        case SortMode.addedTimeDesc:
          return (b.addedTime ?? DateTime.now())
              .compareTo(a.addedTime ?? DateTime.now());
        case SortMode.addedTimeAsc:
          return (a.addedTime ?? DateTime.now())
              .compareTo(b.addedTime ?? DateTime.now());
        case SortMode.recentlyPlayedDesc:
          return (b.lastPlayedTime ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.lastPlayedTime ??
                  DateTime.fromMillisecondsSinceEpoch(0));
        case SortMode.recentlyPlayedAsc:
          return (a.lastPlayedTime ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.lastPlayedTime ??
                  DateTime.fromMillisecondsSinceEpoch(0));
      }
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text.trim();
    var filteredGames = widget.games;
    if (searchQuery.isNotEmpty) {
      filteredGames = filteredGames
          .where((g) =>
              (g.title ?? '')
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
                  child: GlassSearchBar(
                    controller: _searchController,
                    hintText: '搜索游戏...',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              _buildViewModeToggle(),
              const SizedBox(width: 12),
              _buildSortDropdown(),
              const SizedBox(width: 4),
              _buildSortDirectionToggle(),
              const SizedBox(width: 12),
              _buildPaginationModeToggle(),
            ],
          ),
        ),
        // Game list
        Expanded(child: _buildGameList(displayedGames, sortedGames.length)),
        // Page navigation (only in paginated mode)
        if (_paginationMode == PaginationMode.paginated && totalPages > 1)
          _buildPageNavigation(totalPages),
      ],
    );
  }

  Widget _buildViewModeToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in [ViewMode.list, ViewMode.poster])
          GestureDetector(
            onTap: () {
              setState(() {
                _viewMode = mode;
                _currentPage = 0;
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

  Widget _buildSortDropdown() {
    final sortOptions = [
      SortMode.titleAsc,
      SortMode.addedTimeDesc,
      SortMode.recentlyPlayedDesc
    ];
    final sortLabels = {
      'titleAsc': '标题',
      'addedTimeDesc': '添加时间',
      'recentlyPlayedDesc': '最近游玩'
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
    return GestureDetector(
      onTap: () {
        setState(() {
          _sortMode = _toggleDirection(_sortMode);
          _currentPage = 0;
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
      case SortMode.recentlyPlayedDesc:
      case SortMode.recentlyPlayedAsc:
        return '最近游玩';
    }
  }

  Widget _buildPaginationModeToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _paginationMode = PaginationMode.paginated;
              _currentPage = 0;
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
        GestureDetector(
          onTap: () {
            setState(() {
              _paginationMode = PaginationMode.infiniteScroll;
              _infiniteScrollCount = 20;
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
      ],
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
                hintStyle: TextStyle(fontSize: 11, color: const Color.fromARGB(255, 135, 155, 194).withValues(alpha: 0.4)),
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
      final imgW = constraints.maxWidth / 4;
      final imgH = constraints.maxHeight / 3;
      return ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(GlassConstants.spacingMedium),
        itemCount: games.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: AppTheme.borderColor.withValues(alpha: 0.3)),
        itemBuilder: (_, index) => StaggeredItem(
          index: index,
          child: _buildListItem(games[index], imgW, imgH),
        ),
      );
    });
  }

  Widget _buildListItem(Game game, [double? imgW, double? imgH]) {
    final w = imgW ?? 70;
    final h = imgH ?? 90;
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition, game),
      child: InkWell(
        onTap: () => _showGameDetail(game),
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
                child: _buildGameCover(game, width: w, height: h),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(game.title ?? '未命名',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(_formatPath(game.path),
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.5)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (game.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: game.tags.take(3).map((tag) {
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
                                      fontSize: 12,
                                      color: AppTheme.primaryColor)),
                            ),
                          );
                        }).toList(),
                      ),
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
    );
  }

  Widget _buildPosterView(List<Game> games) {
    final isFixed = ref.watch(isFixedColumnCountProvider);
    final fixedCount = ref.watch(fixedColumnCountProvider);
    final crossAxisCount = isFixed ? fixedCount.clamp(2, 5) : 3;

    return LayoutBuilder(builder: (context, constraints) {
      final itemWidth =
          (constraints.maxWidth - (crossAxisCount - 1) * 16 - 32) /
              crossAxisCount;
      // In paginated mode, each item takes half the height; in infinite scroll, use 2/5
      final itemHeight = _paginationMode == PaginationMode.paginated
          ? (constraints.maxHeight - 50) / 2  // 2 rows with 16px mainAxisSpacing
          : constraints.maxHeight * 2 / 5;
      final aspectRatio = itemWidth / itemHeight;

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
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition, game),
      child: GlassCard(
        padding: EdgeInsets.zero,
        onTap: () => _showGameDetail(game),
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
                        fontSize: 14,
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
    showMenu<String>(
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
        if (game.images.length > 1)
          PopupMenuItem(
              value: 'cover',
              child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.image, size: 18),
                  title: Text(
                      '选择封面 (${game.coverIndex + 1}/${game.images.length})'))),
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
      switch (value) {
        case 'open_folder':
          await launchUrl(Uri.file(game.path));
          break;
        case 'favorite':
          await repo.updateFavoriteStatus(game.id!, !game.isFavorite);
          ref.invalidate(allGamesProvider);
          ref.invalidate(favoriteGamesProvider);
          break;
        case 'played':
          if (widget.contextMenuMode == ContextMenuMode.played) {
            await repo.decrementPlayCount(game.id!);
          } else {
            await repo.incrementPlayCount(game.id!);
          }
          ref.invalidate(allGamesProvider);
          ref.invalidate(playedGamesProvider);
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
                  Text('确定要删除"${game.title}"的记录吗？\n路径将加入黑名单，后续扫描不再入库。\n不会删除实际文件。', style: const TextStyle(color: AppTheme.textSecondary)),
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
            _addToBlacklist(game.path);
            await repo.deleteGame(game.id!);
            ref.invalidate(allGamesProvider);
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
                  Text('确定要删除"${game.title}"的本地文件夹吗？\n此操作不可恢复！\n\n${game.path}', style: const TextStyle(color: AppTheme.textSecondary)),
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
            try {
              final dir = Directory(game.path);
              if (await dir.exists()) {
                await dir.delete(recursive: true);
              }
              await repo.deleteGame(game.id!);
              ref.invalidate(allGamesProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已删除文件夹: ${game.title}'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('删除失败: $e'),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
              }
            }
          }
          break;
      }
    });
  }

  String _formatPath(String path) {
    return path.replaceAll('\\', '/');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
