import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/cloudflare_challenge.dart';
import '../../../core/utils/dynamic_page_detector.dart';
import '../../../core/utils/forum_domain_utils.dart';
import '../../../core/utils/game_data_paths.dart';
import '../../../core/utils/proxy_client.dart';
import '../../../scraper/html_parser.dart';
import '../../../scraper/parse_utils.dart';
import '../../../core/services/scrape_apply_service.dart';
import '../../../core/services/vikacg_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cloudflare_browser_dialog.dart';

class ScraperPage extends ConsumerStatefulWidget {
  const ScraperPage({super.key});

  @override
  ConsumerState<ScraperPage> createState() => _ScraperPageState();
}

class _ScrapeStats {
  int total = 0;
  int pending = 0;
  int success = 0;
  int failed = 0;

  double get successRate => total > 0 ? (success / total) * 100 : 0;
}

class _GameScrapeItem {
  Game game;
  double progress;
  String status;
  String? error;

  _GameScrapeItem({
    required this.game,
    this.progress = 0,
    this.status = '待处理',
    this.error,
  });
}

class _ScraperPageState extends ConsumerState<ScraperPage> {
  final _scraper = HtmlScraper();
  final _vikAcgService = VikAcgService();
  final ScrollController _logScrollController = ScrollController();
  bool _isProcessing = false;
  String _processStatus = '空闲';
  final List<String> _logs = [];
  final _ScrapeStats _stats = _ScrapeStats();
  final List<_GameScrapeItem> _gameItems = [];
  int _threadCount = 3;
  Future<void> _browserFallbackTail = Future.value();
  bool _logScrollScheduled = false;

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildControlPanel(),
        const SizedBox(width: GlassConstants.spacingMedium),
        Expanded(child: _buildRightPanel()),
      ],
    );
  }

  Widget _buildControlPanel() {
    return GlassContainer(
      width: 300,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_download_outlined,
                  color: AppTheme.primaryColor, size: 22),
              const SizedBox(width: 12),
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.primaryGradient.createShader(bounds),
                child: const Text(
                  '刮削中心',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildProcessStatus(),
          const SizedBox(height: 20),
          _buildActionButton(
            icon: Icons.search,
            label: '扫描游戏库',
            color: AppTheme.primaryColor,
            isEnabled: !_isProcessing,
            onPressed: _startScan,
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            icon: Icons.description_outlined,
            label: '刮削元数据',
            color: AppTheme.successColor,
            isEnabled: !_isProcessing && _gameItems.isNotEmpty,
            onPressed: _startScrape,
          ),
          const SizedBox(height: 12),
          _buildThreadCountSelector(),
          if (_isProcessing) ...[
            const SizedBox(height: 12),
            _buildActionButton(
              icon: Icons.stop,
              label: '取消',
              color: AppTheme.errorColor,
              isEnabled: true,
              onPressed: _cancelProcess,
            ),
          ],
          const Spacer(),
          _buildStatsPanel(),
        ],
      ),
    );
  }

  Widget _buildProcessStatus() {
    final isRunning = _isProcessing;
    return SizedBox(
      width: 200,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        color: isRunning
            ? AppTheme.successColor.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.1),
        border: Border.all(
          color: isRunning
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
        ),
        enableBlur: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isRunning ? Icons.sync : Icons.circle_outlined,
              size: 18,
              color: isRunning
                  ? AppTheme.successColor
                  : AppTheme.getDisabledColor(context),
            ),
            const SizedBox(width: 8),
            Text(
              _processStatus,
              style: TextStyle(
                color: isRunning
                    ? AppTheme.successColor
                    : AppTheme.getDisabledColor(context),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    bool isEnabled = true,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 200,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          onTap: isEnabled ? onPressed : null,
          child: AnimatedContainer(
            duration: GlassConstants.animFast,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isEnabled
                  ? color.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              border: Border.all(
                color: isEnabled
                    ? color.withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    color:
                        isEnabled ? color : AppTheme.getDisabledColor(context),
                    size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color:
                        isEnabled ? color : AppTheme.getDisabledColor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThreadCountSelector() {
    return SizedBox(
      width: 200,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: AppTheme.getGlassFillColor(context),
        border: Border.all(
            color: AppTheme.getBorderColor(context).withValues(alpha: 0.15)),
        enableBlur: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('线程数',
                style: TextStyle(
                    color: AppTheme.getTextSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            Row(
              children: [
                _buildThreadButton(-1),
                const SizedBox(width: 8),
                Text('$_threadCount',
                    style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                _buildThreadButton(1),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadButton(int delta) {
    return GestureDetector(
      onTap: _isProcessing
          ? null
          : () {
              setState(() {
                _threadCount = (_threadCount + delta).clamp(1, 8);
              });
            },
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: _isProcessing
              ? Colors.grey.withValues(alpha: 0.1)
              : AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: _isProcessing
                  ? Colors.grey.withValues(alpha: 0.3)
                  : AppTheme.primaryColor.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(delta > 0 ? '+' : '-',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _isProcessing ? Colors.grey : AppTheme.primaryColor)),
        ),
      ),
    );
  }

  Widget _buildStatsPanel() {
    return SizedBox(
      width: 200,
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        color: AppTheme.getGlassFillColor(context),
        border: Border.all(
            color: AppTheme.getBorderColor(context).withValues(alpha: 0.15)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('统计信息',
                style: TextStyle(
                    color: AppTheme.getTextSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _StatRow(
                label: '已扫描',
                value: '${_stats.total}',
                color: AppTheme.getTextPrimary(context)),
            const SizedBox(height: 8),
            _StatRow(
                label: '待处理', value: '${_stats.pending}', color: Colors.orange),
            const SizedBox(height: 8),
            _StatRow(
                label: '成功',
                value: '${_stats.success}',
                color: AppTheme.successColor),
            const SizedBox(height: 8),
            _StatRow(
                label: '失败',
                value: '${_stats.failed}',
                color: AppTheme.errorColor),
          ],
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: _buildGameListPanel(),
        ),
        const SizedBox(height: GlassConstants.spacingMedium),
        Expanded(
          flex: 6,
          child: _buildLogPanel(),
        ),
      ],
    );
  }

  Widget _buildGameListPanel() {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_alt_outlined,
                  color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                '待刮削游戏',
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '共 ${_gameItems.length} 个',
                style: TextStyle(
                  color: AppTheme.getTextSecondary(context),
                  fontSize: 13,
                ),
              ),
              if (_stats.total > 0) ...[
                const SizedBox(width: 16),
                Text(
                  '成功率: ${_stats.successRate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: AppTheme.successColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (_isProcessing) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _gameItems.isEmpty
                    ? 0
                    : _gameItems.where((i) => i.progress >= 1).length /
                        _gameItems.length,
                backgroundColor:
                    AppTheme.getTextSecondary(context).withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _gameItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_outlined,
                            size: 48,
                            color: AppTheme.getTextSecondary(context)
                                .withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text('暂无待刮削游戏',
                            style: TextStyle(
                                color: AppTheme.getTextSecondary(context)
                                    .withValues(alpha: 0.5),
                                fontSize: 14)),
                        const SizedBox(height: 8),
                        Text('点击左侧"扫描游戏库"开始',
                            style: TextStyle(
                                color: AppTheme.getTextSecondary(context)
                                    .withValues(alpha: 0.3),
                                fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _gameItems.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: AppTheme.getBorderColor(context)
                            .withValues(alpha: 0.3)),
                    itemBuilder: (_, index) =>
                        _buildGameListItem(_gameItems[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameListItem(_GameScrapeItem item) {
    final statusColor = switch (item.status) {
      '成功' => AppTheme.successColor,
      '失败' || '刮削失败' => AppTheme.errorColor,
      '刮削中' => AppTheme.primaryColor,
      _ => AppTheme.getTextSecondary(context),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ScrapeApplyService.stripVersionFromTitle(
                      item.game.title ?? path.basename(item.game.path),
                      item.game.version),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.getTextPrimary(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.game.sourceUrl ?? '',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.getTextSecondary(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: item.progress,
                  backgroundColor:
                      AppTheme.getTextSecondary(context).withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(statusColor),
                  minHeight: 6,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 14),
              color: AppTheme.getTextSecondary(context),
              tooltip: '编辑来源',
              onPressed: () => _editSourceUrl(item),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal_outlined,
                  color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                '运行日志',
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _logs.clear()),
                icon: const Icon(Icons.delete_sweep, size: 16),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.getTextSecondary(context)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GlassContainer(
              color: Colors.black.withValues(alpha: 0.04),
              border: Border.all(
                  color:
                      AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
              enableBlur: false,
              padding: const EdgeInsets.all(12),
              child: _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.nights_stay_outlined,
                              size: 40,
                              color: AppTheme.getTextSecondary(context)
                                  .withValues(alpha: 0.25)),
                          const SizedBox(height: 8),
                          Text('暂无日志',
                              style: TextStyle(
                                  color: AppTheme.getTextSecondary(context)
                                      .withValues(alpha: 0.4),
                                  fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final log = _logs[i];
                        final isError =
                            log.contains('失败') || log.contains('错误');
                        final isSuccess =
                            log.contains('成功') && !log.contains('失败');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: SelectableText(
                            log,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isError
                                  ? AppTheme.errorColor
                                  : isSuccess
                                      ? AppTheme.successColor
                                      : AppTheme.getTextPrimary(context),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startScan() async {
    setState(() {
      _isProcessing = true;
      _processStatus = '扫描中';
      _gameItems.clear();
      _stats.total = 0;
      _stats.pending = 0;
      _stats.success = 0;
      _stats.failed = 0;
      _logs.clear();
    });

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final rawLib = prefs.getString('library_path') ?? '';

      List<String> libraryPaths;
      if (rawLib.startsWith('[')) {
        try {
          libraryPaths = (jsonDecode(rawLib) as List)
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toList();
        } catch (_) {
          libraryPaths = rawLib.isNotEmpty ? [rawLib] : [];
        }
      } else {
        libraryPaths = rawLib.isNotEmpty ? [rawLib] : [];
      }

      if (libraryPaths.isEmpty) {
        _addLog('错误: 未设置游戏库路径，请先在设置中配置');
        setState(() {
          _isProcessing = false;
          _processStatus = '空闲';
        });
        return;
      }

      final scrapeIgnoreStr = prefs.getString('scrape_ignore_folders') ?? '';
      final scrapeIgnoreFolders =
          scrapeIgnoreStr.split(',').where((s) => s.trim().isNotEmpty).toList();

      if (scrapeIgnoreFolders.isNotEmpty) {
        _addLog('刮削忽略文件夹: ${scrapeIgnoreFolders.join(", ")}');
      }

      _addLog('开始扫描游戏库: ${libraryPaths.join(", ")}');

      final gamesToScrape = <Game>[];
      for (final libraryPath in libraryPaths) {
        final found =
            await _scanForSourceUrlFiles(libraryPath, scrapeIgnoreFolders);
        gamesToScrape.addAll(found);
      }

      _addLog('========== 扫描完成 ==========');
      _addLog('共发现 ${gamesToScrape.length} 个有源URL的游戏可刮削');

      if (!mounted) return;
      setState(() {
        _gameItems.addAll(gamesToScrape.map((g) => _GameScrapeItem(game: g)));
        _stats.total = gamesToScrape.length;
        _stats.pending = gamesToScrape.length;
        _processStatus = '空闲';
        _isProcessing = false;
      });
    } catch (e) {
      _addLog('扫描失败: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processStatus = '空闲';
        });
      }
    }
  }

  Future<List<Game>> _scanForSourceUrlFiles(
      String rootPath, List<String> ignoreFolders) async {
    final games = <Game>[];
    final dir = Directory(rootPath);
    if (!await dir.exists()) return games;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        final folderName = path.basename(entity.path);

        if (ignoreFolders
            .any((ig) => ig.toLowerCase() == folderName.toLowerCase())) {
          _addLog('忽略文件夹: $folderName');
          continue;
        }
        if (folderName.toLowerCase() ==
            GameDataPaths.dataDirName.toLowerCase()) {
          continue;
        }

        final sourceUrlFile =
            await GameDataPaths.existingSourceUrlFile(entity.path);
        if (await sourceUrlFile.exists()) {
          try {
            final sourceUrl = (await sourceUrlFile.readAsString()).trim();
            if (sourceUrl.isNotEmpty) {
              games.add(Game(
                id: null,
                path: entity.path,
                title: folderName,
                sourceUrl: sourceUrl,
              ));
              _addLog('发现游戏: $folderName -> $sourceUrl');
            }
          } catch (e) {
            _addLog('读取source_url.txt失败: ${entity.path} - $e');
          }
        } else {
          games
              .addAll(await _scanForSourceUrlFiles(entity.path, ignoreFolders));
        }
      }
    }

    return games;
  }

  Future<void> _startScrape() async {
    if (_gameItems.isEmpty) {
      _addLog('错误: 没有待刮削的游戏，请先扫描');
      return;
    }

    setState(() {
      _isProcessing = true;
      _processStatus = '刮削中';
      _stats.pending = _gameItems.length;
      _stats.success = 0;
      _stats.failed = 0;
      for (final item in _gameItems) {
        item.progress = 0;
        item.status = '待处理';
        item.error = null;
      }
    });

    _addLog(
        '========== 开始刮削 ${_gameItems.length} 个游戏 (线程数: $_threadCount) ==========');

    try {
      final gameRepo = ref.read(gameRepositoryProvider);
      final tagRepo = ref.read(tagRepositoryProvider);
      await _scraper.ensureLoaded();

      int activeCount = 0;
      final queue = List.generate(_gameItems.length, (i) => i);
      final completer = Completer<void>();

      void processNext() {
        if (queue.isEmpty) {
          if (activeCount == 0 && !completer.isCompleted) {
            completer.complete();
          }
          return;
        }
        final idx = queue.removeAt(0);
        activeCount++;
        _scrapeSingleGame(idx, gameRepo, tagRepo).then((_) {
          activeCount--;
          processNext();
        });
      }

      final initialCount = _threadCount.clamp(1, _gameItems.length);
      for (int i = 0; i < initialCount; i++) {
        processNext();
      }

      await completer.future;

      _addLog('========== 刮削完成 ==========');
      _addLog(
          '总计: ${_gameItems.length}, 成功: ${_stats.success}, 失败: ${_stats.failed}');
      ref.invalidate(allGamesProvider);
      ref.invalidate(favoriteGamesProvider);
      ref.invalidate(playedGamesProvider);
    } catch (e) {
      _addLog('刮削出错: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processStatus = '空闲';
        });
      }
    }
  }

  Future<CloudflareBrowserResult?> _showQueuedCloudflareBrowser(
    String url, {
    Map<String, String>? headers,
    bool Function(String html)? isHtmlReady,
  }) {
    final task = _browserFallbackTail.then((_) async {
      if (!mounted) return null;
      return resolveCloudflareBrowserPage(
        context: context,
        url: url,
        headers: headers,
        isHtmlReady: isHtmlReady,
      );
    });
    _browserFallbackTail = task.then<void>((_) {}, onError: (_) {});
    return task;
  }

  Future<void> _scrapeSingleGame(
      int i, dynamic gameRepo, dynamic tagRepo) async {
    final item = _gameItems[i];
    final game = item.game;

    setState(() {
      item.status = '刮削中';
      item.progress = 0.1;
    });

    _addLog(
        '[${i + 1}/${_gameItems.length}] 刮削: ${game.title ?? path.basename(game.path)}');
    _addLog('  URL: ${game.sourceUrl}');

    // 自定义域名替换：旧域名来源链接自动重写为已配置的论坛自定义域名
    final sourceUrl =
        await ForumDomainUtils.resolveWithCustomDomain(game.sourceUrl!);
    if (sourceUrl != game.sourceUrl) {
      _addLog('  -> 已按自定义域名替换来源: $sourceUrl');
    }

    final parser = ParserRegistry.getParserForUrl(sourceUrl);
    _addLog(
        '  解析器: ${parser?.runtimeType.toString().replaceAll("Parser", "") ?? "无匹配"}');

    try {
      if (game.id != null) {
        await ref
            .read(gameDataMigrationServiceProvider)
            .migrateGameDirectory(game.path, gameId: game.id);
      } else {
        await ref
            .read(gameDataMigrationServiceProvider)
            .migrateGameDirectory(game.path);
      }

      GameInfo? gameInfo;
      final isDlsite = sourceUrl.contains('dlsite');
      final isSteam = sourceUrl.contains('steam');
      if (await VikAcgService.supportsUrl(sourceUrl)) {
        gameInfo = await _vikAcgService.fetchByUrl(sourceUrl);
        if (gameInfo != null) _addLog('  -> 维咔 API 获取成功');
      }
      http.Response? response;
      Map<String, String> headers = {};
      if (gameInfo == null) {
        final client = await createProxyClientFromPrefs(
            domain: Uri.parse(sourceUrl).host);
        try {
          headers = await buildScrapeHeaders(sourceUrl);
          response = await httpGetWithRetry(Uri.parse(sourceUrl),
              headers: headers, client: client);
        } finally {
          client.close();
        }
      }
      String? html = response?.statusCode == 200 ? response?.body : null;
      if (html == null &&
          !isDlsite &&
          !isSteam &&
          response != null &&
          isCloudflareChallengeResponse(response.statusCode, response.body)) {
        _addLog('  -> 遇到 Cloudflare 403，尝试内置浏览器静默加载...');
        final browserResult = await _showQueuedCloudflareBrowser(
          sourceUrl,
          headers: headers,
          isHtmlReady: parser is XpathParser
              ? (renderedHtml) =>
                  _scraper
                      .scrapeGameInfo(renderedHtml, sourceUrl)
                      ?.title
                      ?.trim()
                      .isNotEmpty ==
                  true
              : null,
        );
        html = browserResult?.html;
        if (html != null) {
          _addLog(browserResult!.usedSilentMode
              ? '  -> 已使用内置浏览器静默页面继续解析'
              : '  -> 已使用内置浏览器页面继续解析');
        } else {
          _addLog('  -> 内置浏览器验证已取消');
        }
      }

      if (html != null || gameInfo != null) {
        if (gameInfo == null && isDlsite) {
          final dlsiteService = ref.read(dlsiteServiceProvider);
          final id = dlsiteService.normalizeId(sourceUrl);
          if (id != null) {
            gameInfo = await dlsiteService.fetchById(id);
          }
        } else if (gameInfo == null && isSteam) {
          final steamService = ref.read(steamServiceProvider);
          final appidMatch = RegExp(r'/app/(\d+)').firstMatch(sourceUrl);
          if (appidMatch != null) {
            final id = appidMatch.group(1)!;
            final steamInfo = await steamService.fetchById(id);
            if (steamInfo != null) {
              gameInfo = GameInfo(
                title: steamInfo.title,
                description: steamInfo.description,
                tags: steamInfo.tags,
                screenshots: steamInfo.screenshots,
                sourceUrl: steamInfo.sourceUrl,
                maker: steamInfo.developers.isNotEmpty
                    ? steamInfo.developers.join(', ')
                    : null,
              );
            }
          }
        } else if (gameInfo == null) {
          // API 不可用时继续使用原有 HTML 解析兜底。
          gameInfo = _scraper.scrapeGameInfo(html!, sourceUrl);
          final hasTitle = gameInfo?.title?.trim().isNotEmpty == true;
          if (parser is XpathParser &&
              (!hasTitle || looksLikeClientRenderedPage(html))) {
            _addLog('  -> XPath 未提取到标题，尝试内置浏览器渲染页面...');
            final browserResult = await _showQueuedCloudflareBrowser(
              sourceUrl,
              headers: headers,
              isHtmlReady: (renderedHtml) =>
                  _scraper
                      .scrapeGameInfo(renderedHtml, sourceUrl)
                      ?.title
                      ?.trim()
                      .isNotEmpty ==
                  true,
            );
            if (browserResult != null) {
              _addLog(browserResult.usedSilentMode
                  ? '  -> 已使用内置浏览器静默页面重新解析'
                  : '  -> 已使用内置浏览器页面重新解析');
              gameInfo = _scraper.scrapeGameInfo(
                  browserResult.html, browserResult.finalUrl);
            } else {
              _addLog('  -> 内置浏览器渲染已取消或超时');
            }
          }
        }
        if (gameInfo != null) {
          final updated = await ScrapeApplyService.applyScrapeResult(
            game: game,
            gameInfo: gameInfo,
            mode: ScrapeMode.scraperCenter,
            repo: gameRepo,
            tagRepo: tagRepo,
            configs: ref.read(scrapeModeConfigsProvider),
            sourceUrl: sourceUrl,
            maxConcurrency: _threadCount,
            onProgress: (current, total) {
              if (mounted && total > 0) {
                setState(() {
                  item.progress = 0.5 + 0.4 * (current / total);
                });
              }
            },
            onLog: (message) => _addLog('  -> $message'),
          );
          item.game = updated;
          _addLog('  -> 成功: ${updated.title ?? "无标题"}');
          if (mounted) {
            setState(() {
              item.progress = 1.0;
              item.status = '成功';
              _stats.success++;
              _stats.pending--;
            });
          }
        } else {
          _addLog('  -> 无匹配的解析器 (HTML已获取但无法解析)');
          if (mounted) {
            setState(() {
              item.progress = 1.0;
              item.status = '无解析器';
              _stats.failed++;
              _stats.pending--;
            });
          }
        }
      } else {
        _addLog('  -> HTTP ${response?.statusCode ?? 'API无结果'}');
        if (mounted) {
          setState(() {
            item.progress = 1.0;
            item.status = 'HTTP${response?.statusCode ?? '失败'}';
            _stats.failed++;
            _stats.pending--;
          });
        }
      }
    } catch (e) {
      _addLog('  -> 失败: $e');
      if (mounted) {
        setState(() {
          item.progress = 1.0;
          item.status = '失败';
          item.error = e.toString();
          _stats.failed++;
          _stats.pending--;
        });
      }
    }
  }

  void _cancelProcess() {
    ref.read(scanCancelProvider.notifier).state = true;
    setState(() {
      _isProcessing = false;
      _processStatus = '已取消';
    });
    _addLog('用户取消了操作');
  }

  Future<void> _editSourceUrl(_GameScrapeItem item) async {
    final newUrl = await showGlassDialog<String>(
      context: context,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          final controller =
              TextEditingController(text: item.game.sourceUrl ?? '');
          return SizedBox(
            width: GlassConstants.dialogWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('编辑来源链接',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.getTextPrimary(context))),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: '输入来源URL'),
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
                        onPressed: () {
                          final result = controller.text.trim();
                          controller.dispose();
                          Navigator.pop(context, result);
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

    if (newUrl != null && newUrl.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        item.game = item.game.copyWith(sourceUrl: newUrl);
      });
      try {
        final sourceUrlFile = GameDataPaths.sourceUrlFile(item.game.path);
        await GameDataPaths.ensureDataDir(item.game.path);
        await sourceUrlFile.writeAsString(newUrl, flush: true);
      } catch (e) {
        debugPrint('[Scraper] 写入source_url.txt失败: $e');
      }
    }
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
    _scheduleLogScrollToBottom();
  }

  void _scheduleLogScrollToBottom() {
    if (_logScrollScheduled) return;
    _logScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logScrollScheduled = false;
      if (!mounted || !_logScrollController.hasClients) return;
      _logScrollController.jumpTo(
        _logScrollController.position.maxScrollExtent,
      );
    });
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatRow(
      {required this.label, required this.value, this.color = Colors.black});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: AppTheme.getTextSecondary(context), fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
