import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/proxy_client.dart';
import '../../../scraper/html_parser.dart';
import '../../theme/app_theme.dart';

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
  bool _isProcessing = false;
  String _processStatus = '空闲';
  final List<String> _logs = [];
  final _ScrapeStats _stats = _ScrapeStats();
  final List<_GameScrapeItem> _gameItems = [];

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
              Icon(Icons.cloud_download_outlined, color: AppTheme.primaryColor, size: 22),
              const SizedBox(width: 12),
              ShaderMask(
                shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
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
            icon: Icons.cloud_download,
            label: '刮削元数据',
            color: AppTheme.successColor,
            isEnabled: !_isProcessing && _gameItems.isNotEmpty,
            onPressed: _startScrape,
          ),

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
              color: isRunning ? AppTheme.successColor : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              _processStatus,
              style: TextStyle(
                color: isRunning ? AppTheme.successColor : Colors.grey,
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
              color: isEnabled ? color.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              border: Border.all(
                color: isEnabled ? color.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: isEnabled ? color : Colors.grey, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isEnabled ? color : Colors.grey,
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

  Widget _buildStatsPanel() {
    return SizedBox(
      width: 200,
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        color: AppTheme.glassFillColor,
        border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.15)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('统计信息', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _StatRow(label: '已扫描', value: '${_stats.total}', color: AppTheme.textPrimary),
            const SizedBox(height: 8),
            _StatRow(label: '待处理', value: '${_stats.pending}', color: Colors.orange),
            const SizedBox(height: 8),
            _StatRow(label: '成功', value: '${_stats.success}', color: AppTheme.successColor),
            const SizedBox(height: 8),
            _StatRow(label: '失败', value: '${_stats.failed}', color: AppTheme.errorColor),
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
              Icon(Icons.list_alt_outlined, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                '待刮削游戏',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '共 ${_gameItems.length} 个',
                style: TextStyle(
                  color: AppTheme.textSecondary,
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
                value: _gameItems.isEmpty ? 0 : _gameItems.where((i) => i.progress >= 1).length / _gameItems.length,
                backgroundColor: AppTheme.textSecondary.withValues(alpha: 0.1),
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
                        Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text('暂无待刮削游戏', style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 14)),
                        const SizedBox(height: 8),
                        Text('点击左侧"扫描游戏库"开始', style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.3), fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _gameItems.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.borderColor.withValues(alpha: 0.3)),
                    itemBuilder: (_, index) => _buildGameListItem(_gameItems[index]),
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
      _ => AppTheme.textSecondary,
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
                  _stripVersionFromTitle(item.game.title ?? path.basename(item.game.path), item.game.version),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.game.sourceUrl ?? '',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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
                  backgroundColor: AppTheme.textSecondary.withValues(alpha: 0.1),
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
                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 14),
              color: AppTheme.textSecondary,
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
              Icon(Icons.terminal_outlined, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                '运行日志',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _logs.clear()),
                icon: const Icon(Icons.delete_sweep, size: 16),
                label: const Text('清空'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Expanded(
            child: GlassContainer(
              color: Colors.black.withValues(alpha: 0.04),
              border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.3)),
              enableBlur: false,
              padding: const EdgeInsets.all(12),
              child: _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.nights_stay_outlined, size: 40, color: AppTheme.textSecondary.withValues(alpha: 0.25)),
                          const SizedBox(height: 8),
                          Text('暂无日志', style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.4), fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final log = _logs[i];
                        final isError = log.contains('失败') || log.contains('错误');
                        final isSuccess = log.contains('成功') && !log.contains('失败');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: SelectableText(
                            log,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isError ? AppTheme.errorColor : isSuccess ? AppTheme.successColor : AppTheme.textPrimary,
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
      var libraryPath = prefs.getString('library_path') ?? '';

      if (libraryPath.isEmpty) {
        _addLog('错误: 未设置游戏库路径，请先在设置中配置');
        setState(() {
          _isProcessing = false;
          _processStatus = '空闲';
        });
        return;
      }

      final scrapeIgnoreStr = prefs.getString('scrape_ignore_folders') ?? '';
      final scrapeIgnoreFolders = scrapeIgnoreStr.split(',').where((s) => s.trim().isNotEmpty).toList();

      if (scrapeIgnoreFolders.isNotEmpty) {
        _addLog('刮削忽略文件夹: ${scrapeIgnoreFolders.join(", ")}');
      }

      _addLog('开始扫描游戏库: $libraryPath');

      final gamesToScrape = await _scanForSourceUrlFiles(libraryPath, scrapeIgnoreFolders);

      _addLog('========== 扫描完成 ==========');
      _addLog('共发现 ${gamesToScrape.length} 个有源URL的游戏可刮削');

      setState(() {
        _gameItems.addAll(gamesToScrape.map((g) => _GameScrapeItem(game: g)));
        _stats.total = gamesToScrape.length;
        _stats.pending = gamesToScrape.length;
        _processStatus = '空闲';
        _isProcessing = false;
      });
    } catch (e) {
      _addLog('扫描失败: $e');
      setState(() {
        _isProcessing = false;
        _processStatus = '空闲';
      });
    }
  }

  Future<List<Game>> _scanForSourceUrlFiles(String rootPath, List<String> ignoreFolders) async {
    final games = <Game>[];
    final dir = Directory(rootPath);
    if (!await dir.exists()) return games;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        final folderName = path.basename(entity.path);

        if (ignoreFolders.any((ig) => ig.toLowerCase() == folderName.toLowerCase())) {
          _addLog('忽略文件夹: $folderName');
          continue;
        }

        final sourceUrlFile = File(path.join(entity.path, 'source_url.txt'));
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
          games.addAll(await _scanForSourceUrlFiles(entity.path, ignoreFolders));
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

    _addLog('========== 开始刮削 ${_gameItems.length} 个游戏 ==========');

    try {
      final gameRepo = ref.read(gameRepositoryProvider);
      final tagRepo = ref.read(tagRepositoryProvider);
      final client = await createProxyClientFromPrefs();

      await _scraper.ensureLoaded();

      for (int i = 0; i < _gameItems.length; i++) {
        final item = _gameItems[i];
        final game = item.game;

        setState(() {
          item.status = '刮削中';
          item.progress = 0.1;
        });

        _addLog('[${i + 1}/${_gameItems.length}] 刮削: ${game.title ?? path.basename(game.path)}');
        _addLog('  URL: ${game.sourceUrl}');

        // 确定使用的解析器
        final parser = ParserRegistry.getParserForUrl(game.sourceUrl!);
        _addLog('  解析器: ${parser?.runtimeType.toString().replaceAll("Parser", "") ?? "无匹配"}');

        try {
          final headers = await buildScrapeHeaders(game.sourceUrl!);
          final response = await client.get(Uri.parse(game.sourceUrl!), headers: headers);

          if (response.statusCode == 200) {
            final gameInfo = _scraper.scrapeGameInfo(response.body, game.sourceUrl!);
            if (gameInfo != null) {
              final displayTitle = gameInfo.title != null
                  ? _stripVersionFromTitle(gameInfo.title!, gameInfo.version)
                  : null;
              final updated = game.copyWith(
                title: displayTitle ?? game.title,
                version: gameInfo.version ?? game.version,
                intro: gameInfo.description ?? game.intro,
                features: gameInfo.features.isNotEmpty ? gameInfo.features.join('\n') : game.features,
                changelog: gameInfo.changelog ?? game.changelog,
                downloadUrl: gameInfo.downloadUrl.isNotEmpty ? gameInfo.downloadUrl : game.downloadUrl,
              );

              final metadataFile = File(path.join(game.path, 'metadata.json'));
              await metadataFile.writeAsString(jsonEncode(gameInfo.toJson()), flush: true);

              int gameId;
              if (game.id != null) {
                await gameRepo.updateGame(updated);
                gameId = game.id!;
              } else {
                gameId = await gameRepo.insertGame(updated);
                item.game = updated.copyWith(id: gameId);
              }

              for (final tagName in gameInfo.tags) {
                final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
                await gameRepo.addTagToGame(gameId, tagId);
              }
              if (gameInfo.category != null) {
                final tagId = await tagRepo.insertOrGetTag(gameInfo.category!, Tag.typeSeries);
                await gameRepo.addTagToGame(gameId, tagId);
              }

              // Smart tag overlap: if a game has tag "互动SLG" and "SLG" exists in the system,
              // also associate the game with "SLG"
              final allTags = await tagRepo.getAllTags();
              final gameTagNames = [...gameInfo.tags, if (gameInfo.category != null) gameInfo.category!];
              for (final existingTag in allTags) {
                // Skip if already associated
                final alreadyHas = gameTagNames.any((t) => t.toLowerCase() == existingTag.name.toLowerCase());
                if (alreadyHas) continue;
                // Check if any of the game's tags contain this existing tag's name
                final isOverlapping = gameTagNames.any(
                  (t) => t.toLowerCase().contains(existingTag.name.toLowerCase()) && t.toLowerCase() != existingTag.name.toLowerCase()
                );
                if (isOverlapping) {
                  await gameRepo.addTagToGame(gameId, existingTag.id!);
                  _addLog('  -> 智能关联标签: ${existingTag.name}');
                }
              }

              _addLog('  -> 成功: ${displayTitle ?? "无标题"}');

              // Download images
              if (gameInfo.screenshots.isNotEmpty) {
                _addLog('  -> 下载 ${gameInfo.screenshots.length} 张配图...');
                await _downloadImages(updated.copyWith(id: gameId), gameInfo.screenshots, client, headers);
              }

              // Reload game with images from database
              final reloadedGame = await gameRepo.getGameById(gameId);
              if (reloadedGame != null) {
                item.game = reloadedGame;
              }

              setState(() {
                item.progress = 1.0;
                item.status = '成功';
                _stats.success++;
                _stats.pending--;
              });

              await _moveToSorted(item.game);
            } else {
              _addLog('  -> 无匹配的解析器 (HTML已获取但无法解析)');
              setState(() {
                item.progress = 1.0;
                item.status = '无解析器';
                _stats.failed++;
                _stats.pending--;
              });
            }
          } else {
            _addLog('  -> HTTP ${response.statusCode}');
            setState(() {
              item.progress = 1.0;
              item.status = 'HTTP${response.statusCode}';
              _stats.failed++;
              _stats.pending--;
            });
          }
        } catch (e) {
          _addLog('  -> 失败: $e');
          setState(() {
            item.progress = 1.0;
            item.status = '失败';
            item.error = e.toString();
            _stats.failed++;
            _stats.pending--;
          });
        }
      }

      client.close();
      _addLog('========== 刮削完成 ==========');
      _addLog('总计: ${_gameItems.length}, 成功: ${_stats.success}, 失败: ${_stats.failed}');
      ref.invalidate(allGamesProvider);
      ref.invalidate(favoriteGamesProvider);
      ref.invalidate(playedGamesProvider);
    } catch (e) {
      _addLog('刮削出错: $e');
    } finally {
      setState(() {
        _isProcessing = false;
        _processStatus = '空闲';
      });
    }
  }

  Future<void> _downloadImages(Game game, List<String> imageUrls, http.Client client, Map<String, String> pageHeaders) async {
    final gameRepo = ref.read(gameRepositoryProvider);
    final imagesDir = Directory(path.join(game.path, 'images'));

    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // Get existing images from database
    final existingImages = await gameRepo.getGameImages(game.id!);
    final existingPaths = existingImages.map((img) => img.imagePath).toSet();

    int downloaded = 0;
    for (int i = 0; i < imageUrls.length; i++) {
      final imageUrl = imageUrls[i];
      try {
        final uri = Uri.parse(imageUrl);
        final ext = path.extension(uri.path).toLowerCase();
        final validExt = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext) ? ext : '.jpg';
        final fileName = '${i + 1}$validExt';
        final filePath = path.join(imagesDir.path, fileName);

        // Check if already in database
        if (existingPaths.contains(filePath)) {
          downloaded++;
          continue;
        }

        // Download if not exists - rebuild headers with image URL for proper cookie/auth
        if (!File(filePath).existsSync()) {
          final imgHeaders = await buildScrapeHeaders(imageUrl);
          final imgResponse = await client.get(uri, headers: imgHeaders).timeout(const Duration(seconds: 15));
          if (imgResponse.statusCode == 200 && imgResponse.bodyBytes.isNotEmpty) {
            await File(filePath).writeAsBytes(imgResponse.bodyBytes, flush: true);
          } else {
            _addLog('    图片 ${i + 1} 下载失败: HTTP ${imgResponse.statusCode} URL: $imageUrl');
            continue;
          }
        }

        // Save to database (both new downloads and existing files)
        await gameRepo.addGameImage(game.id!, filePath, i);
        downloaded++;
      } catch (e) {
        _addLog('    图片 ${i + 1} 处理失败: $e URL: $imageUrl');
      }
    }
    _addLog('  -> 配图处理完成: $downloaded/${imageUrls.length}');
  }

  static const _categoryOrder = ['RPG', 'ADV', 'ACT', 'SLG', 'AVG', 'FPS', 'TPS', '3D'];

  String _resolveCategory(List<Tag> tags) {
    final allNames = tags.map((t) => t.name.toUpperCase()).toList();
    for (final cat in _categoryOrder) {
      if (allNames.any((name) => name.contains(cat))) {
        return cat;
      }
    }
    return 'Unclassified';
  }

  Future<void> _moveToSorted(Game game) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final sortedPath = prefs.getString('sorted_path') ?? '';
    if (sortedPath.isEmpty) return;

    final sourceDir = Directory(game.path);
    if (!await sourceDir.exists()) return;

    final gameRepo = ref.read(gameRepositoryProvider);
    final tags = await gameRepo.getGameTags(game.id!);
    final categoryName = _resolveCategory(tags);

    final folderName = path.basename(game.path);
    final targetDir = Directory(path.join(sortedPath, categoryName, folderName));
    if (!await Directory(path.join(sortedPath, categoryName)).exists()) {
      await Directory(path.join(sortedPath, categoryName)).create(recursive: true);
    }

    try {
      if (await targetDir.exists()) {
        _addLog('  -> 目标目录已存在，跳过移动');
        return;
      }

      // Check if target path already exists in database
      final existingGame = await gameRepo.getGameByPath(targetDir.path);
      if (existingGame != null) {
        // Delete the existing game record to avoid UNIQUE constraint
        await gameRepo.deleteGame(existingGame.id!);
        _addLog('  -> 已删除目标路径的旧记录');
      }

      await sourceDir.rename(targetDir.path);
      await gameRepo.updateGamePath(game.id!, targetDir.path);
      // Update image paths in database after moving the directory
      final images = await gameRepo.getGameImages(game.id!);
      if (images.isNotEmpty) {
        final updatedImages = images.map((img) => GameImage(
          id: img.id,
          gameId: img.gameId,
          imagePath: img.imagePath.replaceFirst(game.path, targetDir.path),
          sortOrder: img.sortOrder,
        )).toList();
        await gameRepo.setGameImages(game.id!, updatedImages);
      }
      _addLog('  -> 已移动到: ${targetDir.path}');
    } catch (e) {
      _addLog('  -> 移动失败: $e');
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
    final controller = TextEditingController(text: item.game.sourceUrl ?? '');
    final newUrl = await showGlassDialog<String>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('编辑来源链接', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, controller.text.trim()),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (newUrl != null && newUrl.isNotEmpty) {
      setState(() {
        item.game = item.game.copyWith(sourceUrl: newUrl);
      });
      try {
        final sourceUrlFile = File(path.join(item.game.path, 'source_url.txt'));
        await sourceUrlFile.writeAsString(newUrl, flush: true);
      } catch (_) {}
    }
  }

  static final _versionPattern = RegExp(r'\s+(?:build|v(?:er(?:sion)?)?)\s*\.?\d+(?:[\d.]*\d+)?\s*', caseSensitive: false);

  String _stripVersionFromTitle(String title, [String? version]) {
    var result = title;
    if (version != null && version.isNotEmpty) {
      final escaped = RegExp.escape(version);
      final precisePattern = RegExp(r'\s+(?:build|v(?:er(?:sion)?)?)?\s*' + escaped + r'\s*', caseSensitive: false);
      result = result.replaceAll(precisePattern, ' ');
    }
    result = result.replaceAll(_versionPattern, ' ');
    return result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatRow({required this.label, required this.value, this.color = Colors.black});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
