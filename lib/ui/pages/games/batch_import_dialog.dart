import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../../../core/models/models.dart';
import '../../../core/models/scrape_review_item.dart';
import '../../../core/providers/scrape_review_provider.dart';
import '../../../core/utils/app_settings.dart';
import '../../../core/utils/game_data_paths.dart';
import '../../../core/services/scrape_apply_service.dart';
import '../../../core/repositories/game_repository.dart';
import '../../../core/repositories/tag_repository.dart';
import '../../../core/services/dlsite_service.dart';
import '../../../core/services/game_data_migration_service.dart';
import '../../../core/services/steam_service.dart';
import '../../../core/services/version_check_service.dart';
import '../../../scraper/parse_utils.dart';
import '../scraper/scrape_review_dialog.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dropdown.dart';

/// 批量添加游戏对话框
///
/// 两种用法：
/// - 普通模式：不传 [initialFolderPaths]，用户通过"浏览"选择游戏父目录，
///   扫描其子文件夹生成导入列表；
/// - 拖拽模式：传入 [initialFolderPaths] 直接给定游戏目录列表（可选
///   [presetKeywords] 提供各目录的预设刮削关键词），跳过父目录选择流程。
class BatchImportDialog extends StatefulWidget {
  final VoidCallback onImportComplete;
  final String userFont;

  /// 拖拽模式：直接传入游戏目录列表
  final List<String>? initialFolderPaths;

  /// 拖拽模式：目录 -> 预设刮削关键词（来自拖入的 exe 文件名）
  final Map<String, String>? presetKeywords;

  const BatchImportDialog({
    super.key,
    required this.onImportComplete,
    required this.userFont,
    this.initialFolderPaths,
    this.presetKeywords,
  });

  @override
  State<BatchImportDialog> createState() => _BatchImportDialogState();
}

class _BatchImportDialogState extends State<BatchImportDialog> {
  String? _parentPath;
  List<_BatchGameItem> _items = [];
  bool _scanning = false;
  bool _importing = false;
  bool _importDone = false;
  bool _reviewOpen = false;
  int _successCount = 0;
  int _failCount = 0;

  /// 是否为拖拽模式（直接传入游戏目录列表，跳过父目录选择）
  bool get _isDragMode =>
      widget.initialFolderPaths != null &&
      widget.initialFolderPaths!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // 拖拽模式：不执行父目录选择流程，直接以传入目录构建导入列表
    if (_isDragMode) {
      _scanning = true;
      _initFromDraggedFolders();
    }
  }

  /// 拖拽模式初始化：以传入目录构建 items 并检测/套用关键词
  Future<void> _initFromDraggedFolders() async {
    try {
      final folderPaths = List<String>.from(widget.initialFolderPaths!);
      // 与原 _pickFolder 中排序方式一致：按目录名小写字母序
      folderPaths.sort((a, b) => path
          .basename(a)
          .toLowerCase()
          .compareTo(path.basename(b).toLowerCase()));

      final items = <_BatchGameItem>[];
      final needDetect = <_BatchGameItem>[];
      for (final folderPath in folderPaths) {
        final item = _BatchGameItem(
            folder: Directory(folderPath), keyword: path.basename(folderPath));
        // 调用方已规范化 key，直接按目录路径匹配预设关键词，
        // 命中则套用并跳过关键词自动检测
        final presets = widget.presetKeywords;
        if (presets != null && presets.containsKey(folderPath)) {
          item.keyword = presets[folderPath]!;
        } else {
          needDetect.add(item);
        }
        items.add(item);
      }

      // 无预设关键词的目录照常自动检测，与 _pickFolder 一致并发执行
      await Future.wait(needDetect.map((item) => _detectKeyword(item)));

      if (mounted) setState(() => _items = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: '选择游戏父目录');
    if (result == null) return;
    if (!mounted) return;
    setState(() {
      _parentPath = result;
      _items = [];
      _scanning = true;
      _importDone = false;
      _successCount = 0;
      _failCount = 0;
    });
    try {
      final parent = Directory(result);
      final dirs = <Directory>[];
      await for (final entity in parent.list(followLinks: false)) {
        if (entity is Directory) dirs.add(entity);
      }
      dirs.sort((a, b) => path
          .basename(a.path)
          .toLowerCase()
          .compareTo(path.basename(b.path).toLowerCase()));

      final items = <_BatchGameItem>[];
      for (final dir in dirs) {
        final folderName = path.basename(dir.path);
        items.add(_BatchGameItem(folder: dir, keyword: folderName));
      }

      await Future.wait(items.map((item) => _detectKeyword(item)));

      if (mounted) setState(() => _items = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _detectKeyword(_BatchGameItem item) async {
    final exeName = await _findFirstExe(item.folder.path);
    if (exeName != null) {
      item.keyword = exeName.replaceAll('_', ' ');
    }
  }

  Future<String?> _findFirstExe(String folderPath,
      {bool foundAnyExe = false}) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return null;

    final entities = await dir.list().toList();

    for (final entity in entities) {
      if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
        final exeName =
            path.basenameWithoutExtension(entity.path).toLowerCase();
        final isGeneric = kGenericGameNames.any((w) => exeName.contains(w));
        if (!isGeneric) {
          return path.basenameWithoutExtension(entity.path);
        }
        foundAnyExe = true;
      }
    }

    if (foundAnyExe) return null;

    for (final entity in entities) {
      if (entity is Directory) {
        final result =
            await _findFirstExe(entity.path, foundAnyExe: foundAnyExe);
        if (result != null) return result;
      }
    }

    return null;
  }

  Future<void> _startImport() async {
    final selected = _items.where((i) => i.selected).toList();
    if (selected.isEmpty) return;
    final container = ProviderScope.containerOf(context, listen: false);

    setState(() => _importing = true);

    int successCount = 0;
    int failCount = 0;

    final queue = List<_BatchGameItem>.from(selected);
    const workerCount = 3;
    final workers = <Future>[];

    for (int i = 0; i < workerCount; i++) {
      workers.add(_processQueue(queue, container, () {
        successCount++;
      }, () {
        failCount++;
      }));
    }

    await Future.wait(workers);

    if (mounted) {
      setState(() {
        _importing = false;
        _importDone = true;
        _successCount = successCount;
        _failCount = failCount;
      });
      widget.onImportComplete();
      if (_reviewItems.isNotEmpty) await _confirmScrapeResults();
    }
  }

  List<_BatchGameItem> get _failedScrapeItems => _items.where((item) {
        final review = item.reviewItem;
        return item.selected &&
            item.source != _BatchScrapeSource.none &&
            review != null &&
            !review.canKeep &&
            !review.applied &&
            !review.recoveryRequired;
      }).toList();

  Future<void> _retryFailedImports() async {
    final failedItems = _failedScrapeItems;
    if (_importing || _reviewOpen || failedItems.isEmpty) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _importing = true;
      for (final item in failedItems) {
        item.status = '重试抓取中...';
        item.progress = 0;
      }
    });
    final queue = List<_BatchGameItem>.of(failedItems);
    await Future.wait(
        List.generate(3, (_) => _processQueue(queue, container, () {}, () {})));
    if (!mounted) return;
    setState(() {
      _importing = false;
      _failCount = _items
          .where((item) =>
              item.selected &&
              ((item.source == _BatchScrapeSource.none &&
                      item.status.startsWith('失败:')) ||
                  (item.reviewItem != null && !item.reviewItem!.canKeep)))
          .length;
      _updateReviewStatuses();
    });
    await _confirmScrapeResults();
  }

  Future<void> _processQueue(
    List<_BatchGameItem> queue,
    ProviderContainer container,
    VoidCallback onSuccess,
    VoidCallback onFail,
  ) async {
    final repo = GameRepository();
    final dlsiteService = DlsiteService();
    final steamService = SteamService();

    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      Game? originalGame;
      try {
        if (item.source == _BatchScrapeSource.none) {
          await _importNone(repo, item);
          await _postImportProcess(repo, item);
          onSuccess();
        } else {
          final reusable = _reusableReview(container, item.currentPath);
          if (reusable != null) {
            item.reviewItem = reusable;
            item.status = reusable.status;
            item.progress = 1;
            if (mounted) setState(() {});
            continue;
          }
          originalGame = await _readOriginalGame(repo, item.currentPath);
          final candidate = item.source == _BatchScrapeSource.steam
              ? await _importSteam(steamService, item)
              : await _importDlsite(dlsiteService, item);
          _storeReviewItem(
            item,
            ScrapeReviewItem(
              game: originalGame,
              candidate: candidate,
              mode: ScrapeMode.batchAdd,
            ),
            container,
          );
          item.status = '待确认';
          item.progress = 1;
          if (mounted) setState(() {});
        }
      } catch (e) {
        item.status = '失败: $e';
        if (item.source != _BatchScrapeSource.none) {
          _storeReviewItem(
            item,
            ScrapeReviewItem(
              game: originalGame ??
                  Game(
                      path: item.currentPath,
                      title: path.basename(item.currentPath)),
              fetchError: e.toString(),
              mode: ScrapeMode.batchAdd,
            ),
            container,
          );
        }
        if (mounted) setState(() {});
        onFail();
      }
    }
  }

  List<ScrapeReviewItem> get _reviewItems => _items
      .map((item) => item.reviewItem)
      .whereType<ScrapeReviewItem>()
      .toList();

  ScrapeReviewItem? _reusableReview(
      ProviderContainer container, String gamePath) {
    for (final review in container.read(scrapeReviewItemsProvider)) {
      if (path.equals(review.game.path, gamePath) &&
          (review.recoveryRequired ||
              (review.canKeep &&
                  !review.applied &&
                  review.decision != ScrapeReviewDecision.discard))) {
        return review;
      }
    }
    return null;
  }

  void _storeReviewItem(_BatchGameItem item, ScrapeReviewItem review,
      ProviderContainer container) {
    final reusable = _reusableReview(container, review.game.path);
    if (reusable != null) {
      item.reviewItem = reusable;
      return;
    }
    item.reviewItem = review;
    final previous = container.read(scrapeReviewItemsProvider);
    container.read(scrapeReviewItemsProvider.notifier).state = [
      ...previous
          .where((entry) => !path.equals(entry.game.path, review.game.path)),
      review,
    ];
  }

  Future<void> _confirmScrapeResults() async {
    if (_importing || _reviewOpen) return;
    setState(() => _reviewOpen = true);
    try {
      final configs = await _loadScrapeModeConfigs();
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      await showScrapeReviewDialog(
        context: context,
        items: _reviewItems,
        mode: ScrapeMode.batchAdd,
        configs: configs,
        repository: GameRepository(),
        tagRepository: TagRepository(),
        onChanged: () {
          container.read(scrapeReviewItemsProvider.notifier).state =
              List.of(container.read(scrapeReviewItemsProvider));
          if (!mounted) return;
          setState(_updateReviewStatuses);
          widget.onImportComplete();
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _reviewOpen = false;
          _updateReviewStatuses();
        });
      }
    }
  }

  void _updateReviewStatuses() {
    for (final item in _items) {
      final review = item.reviewItem;
      if (review == null) continue;
      item.status = review.applied
          ? '已保留并保存'
          : review.applyError != null
              ? '保存失败: ${review.applyError}'
              : review.fetchError != null
                  ? '抓取失败: ${review.fetchError}'
                  : review.decision == ScrapeReviewDecision.discard
                      ? '已放弃'
                      : '待确认';
      item.translationNotices
        ..clear()
        ..addAll(review.notices);
    }
  }

  Future<Game> _readOriginalGame(GameRepository repo, String folderPath) async {
    final existing = await repo.getStoredGameByPath(folderPath);
    if (existing != null) return existing;
    Map<String, dynamic> metadata = {};
    final metadataFile = await GameDataPaths.existingMetadataFile(folderPath);
    if (await metadataFile.exists()) {
      try {
        final decoded = jsonDecode(await metadataFile.readAsString());
        if (decoded is Map<String, dynamic>) metadata = decoded;
      } catch (error) {
        debugPrint('[BatchImport] 读取原有元数据失败: $error');
      }
    }
    return Game(
      path: folderPath,
      title: metadata['title'] as String? ?? path.basename(folderPath),
      version: metadata['version'] as String?,
      intro: metadata['intro'] as String?,
      features: metadata['features'] as String?,
      changelog: metadata['changelog'] as String?,
      sourceUrl: metadata['source_url'] as String?,
      downloadUrl: metadata['download_url'] as String?,
      maker: metadata['maker'] as String?,
      makerUrl: metadata['maker_url'] as String?,
      guide: metadata['guide'] as String?,
      tags: [
        for (final name
            in (metadata['tags'] as List? ?? []).whereType<String>())
          Tag(name: name, type: Tag.typeCustom),
        if (metadata['series'] is String)
          Tag(name: metadata['series'] as String, type: Tag.typeSeries),
      ],
    );
  }

  Future<void> _postImportProcess(
      GameRepository repo, _BatchGameItem item) async {
    if (item.status != '导入完成') return;
    final initialGame = await repo.getGameByPath(item.folder.path);
    if (initialGame == null) return;

    final configs = await _loadScrapeModeConfigs();
    item.translationNotices.clear();
    item.status = '正在处理元信息...';
    if (mounted) setState(() {});
    // 重命名/移动整理逻辑统一走共享层，保持各入口行为一致
    final organized = await ScrapeApplyService.organizeFolder(
        initialGame, ScrapeMode.batchAdd, repo, configs);
    item.status = '导入完成';
    if (mounted) setState(() {});
    debugPrint('[BatchImport] 整理完成: ${organized.path}');
  }

  Future<void> _importNone(GameRepository repo, _BatchGameItem item) async {
    final folderPath = item.folder.path;
    final existing = await repo.getGameByPath(folderPath);
    if (existing != null) {
      await GameDataMigrationService(gameRepository: repo)
          .migrateGameDirectory(folderPath, gameId: existing.id);
      item.status = '已存在，跳过';
      if (mounted) setState(() {});
      return;
    }

    item.status = '正在导入...';
    if (mounted) setState(() {});
    await GameDataMigrationService(gameRepository: repo)
        .migrateGameDirectory(folderPath);

    String? title;
    String? version;
    String? intro;
    String? sourceUrl;

    final metadataFile = await GameDataPaths.existingMetadataFile(folderPath);
    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        title = map['title'] as String?;
        version = map['version'] as String?;
        intro = map['intro'] as String?;
        sourceUrl = map['source_url'] as String?;
      } catch (e) {
        debugPrint('[GamesPage] 读取metadata.json失败: $e');
      }
    }

    final sourceUrlFile = await GameDataPaths.existingSourceUrlFile(folderPath);
    if (sourceUrl == null && await sourceUrlFile.exists()) {
      try {
        sourceUrl = (await sourceUrlFile.readAsString()).trim();
        if (sourceUrl.isEmpty) sourceUrl = null;
      } catch (e) {
        debugPrint('[GamesPage] 读取source_url.txt失败: $e');
      }
    }

    final game = Game(
      path: folderPath,
      title: title ?? path.basename(folderPath),
      version: version,
      intro: intro,
      sourceUrl: sourceUrl,
    );
    await repo.insertGame(game);

    final imageDir = GameDataPaths.imagesDir(folderPath);
    if (await imageDir.exists()) {
      final imagePaths = <String>[];
      await for (final entity in imageDir.list()) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
            imagePaths.add(entity.path);
          }
        }
      }
      imagePaths.sort();
      if (imagePaths.isNotEmpty) {
        final gameId = await repo.getGameByPath(folderPath);
        if (gameId != null) {
          final images = imagePaths
              .asMap()
              .entries
              .map((e) => GameImage(
                    gameId: gameId.id!,
                    imagePath: e.value,
                    sortOrder: e.key,
                  ))
              .toList();
          await repo.setGameImages(gameId.id!, images);
        }
      }
    }

    item.status = '导入完成';
    item.progress = 1.0;
    if (mounted) setState(() {});
  }

  /// 检测关键词是否为 DLsite ID
  String? _detectDlsiteId(String keyword) {
    final match =
        RegExp(r'(RJ|RE|VJ)\d{4,}', caseSensitive: false).firstMatch(keyword);
    return match?.group(0)?.toUpperCase();
  }

  /// 清理关键词：去除括号内容、版本号等
  String _cleanKeyword(String keyword) {
    var cleaned = keyword;
    // 去除 [] 和 【】 中的内容
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '');
    // 去除版本号 (V1.0.1, v1.02, ver1.0, build123 等)
    cleaned = cleaned.replaceAll(
        RegExp(r'\s*[Vv](?:er(?:sion)?)?\s*\.?\d+(?:[\d.]*\d+)?\s*',
            caseSensitive: false),
        ' ');
    // 去除常见后缀
    cleaned = cleaned.replaceAll(
        RegExp(r'\s*(?:官方中文版|官方中文|中文版|汉化版|汉化|steam|fixed|patch)\s*',
            caseSensitive: false),
        ' ');
    // 清理多余空格
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return cleaned;
  }

  /// 分词并逐步缩短搜索
  Future<List<DlsiteSearchResult>> _searchDlsiteWithFallback(
    DlsiteService dlsiteService,
    String keyword,
    String folderPath,
  ) async {
    // 先用完整关键词搜索
    var results = await dlsiteService.search(keyword);
    if (results.isNotEmpty) return results;

    // 清理关键词
    final cleaned = _cleanKeyword(keyword);
    if (cleaned != keyword && cleaned.isNotEmpty) {
      results = await dlsiteService.search(cleaned);
      if (results.isNotEmpty) return results;
    }

    // 分词逐步缩短
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length <= 1) {
      // 只有一个词，用 searchWithFallback
      return await dlsiteService.searchWithFallback(folderPath);
    }

    // 从少一个词开始，逐步缩短
    for (int i = parts.length - 1; i >= 1; i--) {
      final shortened = parts.sublist(0, i).join(' ');
      if (shortened.isNotEmpty) {
        results = await dlsiteService.search(shortened);
        if (results.isNotEmpty) return results;
      }
    }

    // 所有尝试都失败，用 searchWithFallback
    return await dlsiteService.searchWithFallback(folderPath);
  }

  /// 检测关键词是否为 Steam ID
  String? _detectSteamId(String keyword) {
    // 纯数字
    if (RegExp(r'^\d+$').hasMatch(keyword)) return keyword;
    // Steam URL
    final urlMatch =
        RegExp(r'store\.steampowered\.com/app/(\d+)').firstMatch(keyword);
    return urlMatch?.group(1);
  }

  Future<GameInfo> _importSteam(
    SteamService steamService,
    _BatchGameItem item,
  ) async {
    final folderPath = item.currentPath;
    item.status = '搜索中...';
    if (mounted) setState(() {});

    final steamId = _detectSteamId(item.keyword);
    List<SteamSearchResult> results;
    if (steamId != null) {
      results = [SteamSearchResult(id: steamId, name: 'ID: $steamId')];
    } else if (item.keyword.isNotEmpty) {
      results = await steamService.search(item.keyword);
      if (results.isEmpty) {
        results = await steamService.searchWithFallback(folderPath);
      }
    } else {
      results = await steamService.searchWithFallback(folderPath);
    }
    if (results.isEmpty) throw StateError('Steam 未找到匹配作品');

    final searchResult = results.first;
    item.status = '获取信息: ${searchResult.name ?? searchResult.id}';
    item.progress = 0.5;
    if (mounted) setState(() {});
    final gameInfo = await steamService.fetchById(searchResult.id);
    if (gameInfo == null || gameInfo.title?.trim().isNotEmpty != true) {
      throw StateError('Steam 获取作品资料失败');
    }
    return GameInfo(
      title: gameInfo.title,
      description: gameInfo.description,
      tags: gameInfo.tags,
      screenshots: gameInfo.screenshots,
      sourceUrl: gameInfo.sourceUrl,
      maker: gameInfo.developers.isNotEmpty
          ? gameInfo.developers.join(', ')
          : null,
    );
  }

  Future<GameInfo> _importDlsite(
    DlsiteService dlsiteService,
    _BatchGameItem item,
  ) async {
    final folderPath = item.currentPath;
    item.status = '搜索中...';
    if (mounted) setState(() {});

    final dlsiteId = _detectDlsiteId(item.keyword);
    List<DlsiteSearchResult> results;
    if (dlsiteId != null) {
      results = [DlsiteSearchResult(id: dlsiteId, name: 'ID: $dlsiteId')];
    } else if (item.keyword.isNotEmpty) {
      results = await _searchDlsiteWithFallback(
          dlsiteService, item.keyword, folderPath);
    } else {
      results = await dlsiteService.searchWithFallback(folderPath);
    }
    if (results.isEmpty) throw StateError('DLsite 未找到匹配作品');

    final searchResult = results.first;
    item.status = '获取信息: ${searchResult.name ?? searchResult.id}';
    item.progress = 0.5;
    if (mounted) setState(() {});
    final gameInfo = await dlsiteService.fetchById(searchResult.id);
    if (gameInfo == null || gameInfo.title?.trim().isNotEmpty != true) {
      throw StateError('DLsite 获取作品资料失败');
    }
    return gameInfo;
  }

  double get _controlHeight =>
      LayoutConstants.controlHeight +
      (MediaQuery.textScalerOf(context).scale(GlassConstants.fontControl) -
              GlassConstants.fontControl)
          .clamp(0.0, double.infinity);

  double get _sourceWidth =>
      LayoutConstants.batchImportSourceWidth *
      (MediaQuery.textScalerOf(context).scale(GlassConstants.fontControl) /
              GlassConstants.fontControl)
          .clamp(1.0, double.infinity);

  TextStyle get _controlTextStyle => TextStyle(
        fontSize: GlassConstants.fontControl,
        color: AppTheme.getTextPrimary(context),
        fontFamily: widget.userFont.isNotEmpty ? widget.userFont : null,
      );

  ButtonStyle get _controlButtonStyle => ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, _controlHeight)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(
            horizontal: GlassConstants.spacingMedium,
            vertical: GlassConstants.spacingInline)),
        textStyle: WidgetStatePropertyAll(_controlTextStyle),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium))),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      );

  ButtonStyle get _primaryButtonStyle => _controlButtonStyle.merge(
        ElevatedButton.styleFrom(
          backgroundColor: AppTheme.getPrimaryColor(context),
          foregroundColor: AppTheme.getOnPrimaryColor(context),
          disabledBackgroundColor:
              AppTheme.getPrimaryColor(context).withValues(alpha: 0.4),
        ),
      );

  Widget _gameName(_BatchGameItem item) => Tooltip(
        message: item.currentPath,
        child: Text(path.basename(item.currentPath),
            style: _controlTextStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      );

  Widget _platformFields(_BatchGameItem item,
      {bool retry = false, bool showName = false}) {
    const padding = EdgeInsets.symmetric(
        horizontal: GlassConstants.spacingCompact,
        vertical: GlassConstants.spacingSmall);
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        borderSide: BorderSide(
            color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)));
    return Row(
      children: [
        AppDropdown<_BatchScrapeSource>(
          key: ValueKey(
              '${retry ? 'retry' : 'batch'}-source-${item.folder.path}'),
          value: item.source,
          width: _sourceWidth,
          height: _controlHeight,
          isExpanded: true,
          isDense: true,
          padding: padding,
          textStyle: _controlTextStyle,
          items: [
            if (!retry)
              const DropdownMenuItem(
                  value: _BatchScrapeSource.none, child: Text('不刮削')),
            const DropdownMenuItem(
                value: _BatchScrapeSource.steam, child: Text('Steam')),
            const DropdownMenuItem(
                value: _BatchScrapeSource.dlsite, child: Text('DLsite')),
          ],
          onChanged: _importing || _reviewOpen
              ? null
              : (value) {
                  if (value != null) setState(() => item.source = value);
                },
        ),
        const SizedBox(width: GlassConstants.spacingSmall),
        if (showName) ...[
          SizedBox(
              width: LayoutConstants.batchImportNameWidth,
              child: _gameName(item)),
          const SizedBox(width: GlassConstants.spacingSmall),
        ],
        Expanded(
          child: SizedBox(
            height: _controlHeight,
            child: TextFormField(
              key: ValueKey(
                  '${retry ? 'retry' : 'batch'}-keyword-${item.folder.path}'),
              initialValue: item.keyword,
              enabled: !_importing && !_reviewOpen,
              style: _controlTextStyle,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: '搜索关键词或作品 ID',
                hintStyle: _controlTextStyle.copyWith(
                    color: AppTheme.getTextSecondary(context)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: GlassConstants.spacingCompact,
                    vertical: GlassConstants.spacingMedium),
                border: border,
                enabledBorder: border,
                isDense: true,
              ),
              onChanged: (value) => item.keyword = value,
            ),
          ),
        ),
      ],
    );
  }

  Widget _editableItem(_BatchGameItem item) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: GlassConstants.spacingCompact,
            vertical: GlassConstants.spacingSmall),
        child: LayoutBuilder(builder: (context, constraints) {
          final checkbox = SizedBox(
            width: _controlHeight,
            height: _controlHeight,
            child: Checkbox(
              value: item.selected,
              onChanged: _importing
                  ? null
                  : (checked) =>
                      setState(() => item.selected = checked ?? false),
              activeColor: AppTheme.getPrimaryColor(context),
            ),
          );
          if (constraints.maxWidth < LayoutConstants.batchImportCompactWidth) {
            return Column(
              children: [
                Row(children: [
                  checkbox,
                  const SizedBox(width: GlassConstants.spacingSmall),
                  Expanded(child: _gameName(item)),
                ]),
                const SizedBox(height: GlassConstants.spacingSmall),
                _platformFields(item),
              ],
            );
          }
          return Row(children: [
            checkbox,
            const SizedBox(width: GlassConstants.spacingSmall),
            Expanded(child: _platformFields(item, showName: true)),
          ]);
        }),
      );

  Widget _statusItem(_BatchGameItem item) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: GlassConstants.spacingCompact,
            vertical: GlassConstants.spacingSmall),
        child: LayoutBuilder(builder: (context, constraints) {
          final source = Container(
            key: ValueKey('batch-status-source-${item.folder.path}'),
            width: _sourceWidth,
            height: _controlHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(
                horizontal: GlassConstants.spacingCompact),
            decoration: BoxDecoration(
              color: (item.source == _BatchScrapeSource.none
                      ? AppTheme.getTextSecondary(context)
                      : AppTheme.getPrimaryColor(context))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            ),
            child: Text(
              item.source == _BatchScrapeSource.none
                  ? '不刮削'
                  : item.source == _BatchScrapeSource.steam
                      ? 'Steam'
                      : 'DLsite',
              style: _controlTextStyle.copyWith(
                  color: item.source == _BatchScrapeSource.none
                      ? AppTheme.getTextSecondary(context)
                      : AppTheme.getPrimaryColor(context)),
            ),
          );
          final progress = SizedBox(
            height: _controlHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(item.status,
                        style: _controlTextStyle.copyWith(
                            color: AppTheme.getTextSecondary(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (item.translationNotices.isNotEmpty)
                    Tooltip(
                      message: item.translationNotices.join('\n'),
                      child: const Icon(Icons.translate,
                          size: GlassConstants.iconSmall,
                          color: AppTheme.warningColor),
                    ),
                ]),
                if (item.progress > 0) ...[
                  const SizedBox(height: GlassConstants.spacingSmall),
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(GlassConstants.radiusIndicator),
                    child: LinearProgressIndicator(
                      key:
                          ValueKey('batch-status-progress-${item.folder.path}'),
                      value: item.progress,
                      minHeight: GlassConstants.spacingTight,
                      backgroundColor: AppTheme.getTextSecondary(context)
                          .withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(item.progress >= 1
                          ? AppTheme.successColor
                          : AppTheme.getPrimaryColor(context)),
                    ),
                  ),
                ],
              ],
            ),
          );
          if (constraints.maxWidth < LayoutConstants.batchImportCompactWidth) {
            return Column(children: [
              Row(children: [
                source,
                const SizedBox(width: GlassConstants.spacingSmall),
                Expanded(child: _gameName(item)),
              ]),
              const SizedBox(height: GlassConstants.spacingSmall),
              progress,
            ]);
          }
          return Row(children: [
            source,
            const SizedBox(width: GlassConstants.spacingSmall),
            SizedBox(
                width: LayoutConstants.batchImportNameWidth,
                child: _gameName(item)),
            const SizedBox(width: GlassConstants.spacingSmall),
            Expanded(child: progress),
          ]);
        }),
      );

  @override
  Widget build(BuildContext context) {
    final savedReviews = _reviewItems.where((item) => item.applied).length;
    final pendingReviews = _reviewItems
        .where((item) =>
            item.candidate != null &&
            !item.applied &&
            item.decision != ScrapeReviewDecision.discard)
        .length;
    final hasWarnings = _failCount > 0 ||
        pendingReviews > 0 ||
        _reviewItems.any((item) => item.applyError != null);
    return PopScope(
      canPop: !_importing,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_importing) Navigator.of(context).maybePop();
          },
        },
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.all(GlassConstants.spacingDialog),
            child: SizedBox(
              key: const ValueKey('batch-import-content'),
              width: LayoutConstants.batchImportDialogWidth,
              height: LayoutConstants.batchImportDialogHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      // 拖拽模式且仅传入 1 个目录时按单个添加显示标题
                      _isDragMode && widget.initialFolderPaths!.length == 1
                          ? '添加游戏'
                          : '批量添加游戏',
                      style: TextStyle(
                          fontSize: GlassConstants.fontSection,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.getTextPrimary(context))),
                  const SizedBox(height: GlassConstants.spacingMedium),
                  if (_isDragMode)
                    // 拖拽模式：文件夹列表由调用方传入，仅展示数量，不提供浏览按钮
                    Container(
                      height: _controlHeight,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: GlassConstants.spacingCompact,
                          vertical: GlassConstants.spacingInline),
                      decoration: BoxDecoration(
                        color: AppTheme.getSurfaceColor(context)
                            .withValues(alpha: 0.5),
                        borderRadius:
                            BorderRadius.circular(GlassConstants.radiusMedium),
                        border: Border.all(
                            color: AppTheme.getBorderColor(context)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '已添加 ${widget.initialFolderPaths!.length} 个游戏文件夹',
                              style: TextStyle(
                                fontSize: GlassConstants.fontBody,
                                color: AppTheme.getTextPrimary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            key: const ValueKey('batch-import-folder-path'),
                            height: _controlHeight,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                                horizontal: GlassConstants.spacingCompact,
                                vertical: GlassConstants.spacingInline),
                            decoration: BoxDecoration(
                              color: AppTheme.getSurfaceColor(context)
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(
                                  GlassConstants.radiusMedium),
                              border: Border.all(
                                  color: AppTheme.getBorderColor(context)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _parentPath ?? '未选择文件夹',
                              style: TextStyle(
                                fontSize: GlassConstants.fontBody,
                                color: _parentPath != null
                                    ? AppTheme.getTextPrimary(context)
                                    : AppTheme.getTextSecondary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: GlassConstants.spacingSmall),
                        ElevatedButton.icon(
                          key: const ValueKey('batch-import-browse'),
                          onPressed:
                              _scanning || _importing ? null : _pickFolder,
                          icon: const Icon(Icons.folder_open,
                              size: GlassConstants.iconSmall),
                          label: const Text('浏览'),
                          style: _primaryButtonStyle,
                        ),
                      ],
                    ),
                  const SizedBox(height: GlassConstants.spacingSmall),
                  const Text(
                    'Steam / DLsite 抓取完成后自动打开确认表单，保留所选结果后再保存',
                    style: TextStyle(
                        fontSize: GlassConstants.fontSmall,
                        color: AppTheme.warningColor),
                  ),
                  const SizedBox(height: GlassConstants.spacingSmall),
                  if (_scanning)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_items.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          _parentPath != null ? '未找到子文件夹' : '选择一个包含游戏子文件夹的目录',
                          style: TextStyle(
                              color: AppTheme.getTextSecondary(context),
                              fontSize: GlassConstants.fontControl),
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '找到 ${_items.length} 个文件夹，已选 ${_items.where((i) => i.selected).length} 个',
                            style: TextStyle(
                                fontSize: GlassConstants.fontBody,
                                color: AppTheme.getTextSecondary(context)),
                          ),
                        ),
                        const SizedBox(width: GlassConstants.spacingSmall),
                        TextButton(
                          key: const ValueKey('batch-import-select-all'),
                          style: _controlButtonStyle,
                          onPressed: _importing || _importDone
                              ? null
                              : () {
                                  setState(() {
                                    final allSelected =
                                        _items.every((i) => i.selected);
                                    for (final item in _items) {
                                      item.selected = !allSelected;
                                    }
                                  });
                                },
                          child: Text(
                            _items.every((i) => i.selected) ? '取消全选' : '全选',
                            style: TextStyle(
                                fontSize: GlassConstants.fontBody,
                                color: AppTheme.getPrimaryColor(context)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: GlassConstants.spacingSmall),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.getSurfaceColor(context)
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(
                              GlassConstants.radiusMedium),
                          border: Border.all(
                              color: AppTheme.getBorderColor(context)
                                  .withValues(alpha: 0.2)),
                        ),
                        child: ListView.builder(
                          itemCount: _importing || _importDone
                              ? _items.where((i) => i.selected).length
                              : _items.length,
                          itemBuilder: (context, index) {
                            final item = _importing || _importDone
                                ? _items
                                    .where((i) => i.selected)
                                    .toList()[index]
                                : _items[index];
                            if (_importDone &&
                                !_importing &&
                                _failedScrapeItems.contains(item)) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: GlassConstants.spacingCompact,
                                    vertical: GlassConstants.spacingSmall),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _gameName(item),
                                    const SizedBox(
                                        height: GlassConstants.spacingSmall),
                                    _platformFields(item, retry: true),
                                    const SizedBox(
                                        height: GlassConstants.spacingSmall),
                                    Text(item.status,
                                        style: const TextStyle(
                                          color: AppTheme.warningOrange,
                                          fontSize: GlassConstants.fontSmall,
                                        )),
                                  ],
                                ),
                              );
                            }
                            if (_importing || _importDone) {
                              return _statusItem(item);
                            }
                            return _editableItem(item);
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: GlassConstants.spacingComfortable),
                  if (_importDone) ...[
                    Container(
                      padding:
                          const EdgeInsets.all(GlassConstants.spacingCompact),
                      decoration: BoxDecoration(
                        color: hasWarnings
                            ? AppTheme.warningColor.withValues(alpha: 0.1)
                            : AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(GlassConstants.radiusSmall),
                        border: Border.all(
                          color: hasWarnings
                              ? AppTheme.warningColor.withValues(alpha: 0.3)
                              : AppTheme.successColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasWarnings
                                ? Icons.warning_amber
                                : Icons.check_circle_outline,
                            color: hasWarnings
                                ? AppTheme.warningColor
                                : AppTheme.successColor,
                            size: GlassConstants.iconControl,
                          ),
                          const SizedBox(width: GlassConstants.spacingSmall),
                          Expanded(
                            child: Text(
                              _reviewItems.isEmpty
                                  ? '本地导入 $_successCount 个，失败 $_failCount 个'
                                  : '本地导入 $_successCount 个，刮削已保存 $savedReviews 个，待确认 $pendingReviews 个，抓取失败 $_failCount 个',
                              style: TextStyle(
                                fontSize: GlassConstants.fontControl,
                                fontWeight: FontWeight.w500,
                                color: hasWarnings
                                    ? AppTheme.warningColor
                                    : AppTheme.successColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: GlassConstants.spacingCompact),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.end,
                        spacing: GlassConstants.spacingSmall,
                        runSpacing: GlassConstants.spacingSmall,
                        children: [
                          if (_failedScrapeItems.isNotEmpty)
                            TextButton.icon(
                              key: const ValueKey('retry-failed-batch-scrapes'),
                              style: _controlButtonStyle,
                              onPressed: _importing || _reviewOpen
                                  ? null
                                  : _retryFailedImports,
                              icon: const Icon(Icons.refresh,
                                  size: GlassConstants.iconSmall),
                              label:
                                  Text('重试失败项（${_failedScrapeItems.length}）'),
                            ),
                          if (_reviewItems.isNotEmpty) ...[
                            TextButton.icon(
                              key: const ValueKey(
                                  'batch-confirm-scrape-results'),
                              style: _controlButtonStyle,
                              onPressed: _importing || _reviewOpen
                                  ? null
                                  : _confirmScrapeResults,
                              icon: const Icon(Icons.fact_check_outlined,
                                  size: GlassConstants.iconSmall),
                              label: const Text('确认刮削结果'),
                            ),
                          ],
                          ElevatedButton(
                            key: const ValueKey('batch-import-finish'),
                            onPressed: _importing || _reviewOpen
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    widget.onImportComplete();
                                  },
                            style: _primaryButtonStyle,
                            child: const Text('完成'),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    if (_importing)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(
                              bottom: GlassConstants.spacingCompact),
                          child: Text(
                            '请不要退出该页面',
                            style: TextStyle(
                                fontSize: GlassConstants.fontBody,
                                color: AppTheme.warningColor),
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          key: const ValueKey('batch-import-cancel'),
                          style: _controlButtonStyle,
                          onPressed: _importing
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: GlassConstants.spacingCompact),
                        ElevatedButton(
                          key: const ValueKey('batch-import-start'),
                          onPressed: _items.isEmpty ||
                                  _importing ||
                                  !_items.any((i) => i.selected)
                              ? null
                              : _startImport,
                          style: _primaryButtonStyle,
                          child: _importing
                              ? SizedBox(
                                  width: GlassConstants.iconSmall,
                                  height: GlassConstants.iconSmall,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.getTextColorOnPrimary(
                                          context)))
                              : Text(
                                  '开始 (${_items.where((i) => i.selected).length})'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _BatchScrapeSource { none, steam, dlsite }

class _BatchGameItem {
  final Directory folder;
  String keyword;
  _BatchScrapeSource source;
  String status;
  final List<String> translationNotices = [];
  ScrapeReviewItem? reviewItem;
  double progress;
  bool selected;

  String get currentPath => reviewItem?.game.path ?? folder.path;

  _BatchGameItem({
    required this.folder,
    required this.keyword,
  })  : source = _BatchScrapeSource.steam,
        status = '',
        progress = 0.0,
        selected = true;
}

// 刮削整理配置加载：缺失或解析失败时回退默认配置，整理开关由共享层自行判断
Future<ScrapeModeConfigs> _loadScrapeModeConfigs() async {
  final settings = await AppSettings.load();
  final jsonStr = settings.getString(AppSettings.scrapeModeConfigsKey);
  if (jsonStr == null || jsonStr.isEmpty) return ScrapeModeConfigs.defaults();
  try {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return ScrapeModeConfigs.fromMap(map);
  } catch (_) {
    return ScrapeModeConfigs.defaults();
  }
}
