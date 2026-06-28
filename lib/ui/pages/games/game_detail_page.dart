import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/repositories/game_repository.dart';
import '../../../core/utils/proxy_client.dart';
import '../../../scraper/html_parser.dart';
import '../../../scraper/parse_utils.dart';
import '../../theme/app_theme.dart';
import '../../../core/services/version_check_service.dart';
import '../../../core/services/folder_rename_service.dart';
import '../../../core/services/play_time_tracker.dart';
import '../../../core/utils/app_settings.dart';
import '../../widgets/image_manager_dialog.dart';
import '../../widgets/markdown_editor.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'save_management_dialog.dart';
import 'guide_search_dialog.dart';
import 'detail_scroll_buttons.dart';
import 'detail_search_bar.dart';
import 'content_search_engine.dart';

class GameDetailDialog extends ConsumerStatefulWidget {
  final Game game;
  final void Function(Tag tag)? onTagTap;

  const GameDetailDialog({super.key, required this.game, this.onTagTap});

  @override
  ConsumerState<GameDetailDialog> createState() => _GameDetailDialogState();
}

class _GameDetailDialogState extends ConsumerState<GameDetailDialog> {
  bool _isEditing = false;
  late TextEditingController _titleController;
  late TextEditingController _versionController;
  late TextEditingController _introController;
  late TextEditingController _featuresController;
  late TextEditingController _changelogController;
  late TextEditingController _downloadUrlController;
  late TextEditingController _sourceUrlController;
  late TextEditingController _gameLauncherController;
  late TextEditingController _pathController;
  late TextEditingController _makerController;
  bool _pathChanged = false;
  List<Tag> _editedTags = [];
  late Game _currentGame;

  bool _isImageViewerOpen = false;
  int _currentImageIndex = 0;
  int _imageVersion = 0;
  bool _isCheckingUpdate = false;
  bool _isRescraping = false;
  bool _isLocal = false;
  Set<String> _existingMediaFiles = {};

  String? _introHtml;
  bool _showGuide = false;
  late TextEditingController _guideController;

  double _downloadProgress = 0.0;
  int _downloadTotal = 0;
  int _downloadCurrent = 0;

  final TextEditingController _quickScrapeController = TextEditingController();
  String _quickScrapeChannel = 'auto';
  bool _showChannelSelector = false;

  late ScrollController _contentScrollController;
  final GlobalKey _scrollContentKey = GlobalKey();
  GameRepository? _repo;
  Timer? _scrollSaveDebounce;
  bool _isRestoringScroll = false;
  bool _suppressScrollSave = false;
  double _lastStableMax = 0;
  int _stableFrames = 0;
  int _restoreFrameCount = 0;
  final GlobalKey _contentPanelKey = GlobalKey();
  bool _isSearchOpen = false;
  List<ContentSearchMatch> _searchMatches = [];
  int _currentMatchIndex = -1;
  final Map<String, GlobalKey> _contentBlockKeys = {};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  /// 刷新游戏列表
  void _refreshGames() {
    ref.invalidate(allGamesProvider);
  }

  /// 刷新已玩列表
  void _refreshPlayed() {
    ref.invalidate(playedGamesProvider);
  }

  /// 刷新收藏列表
  void _refreshFavorites() {
    ref.invalidate(favoriteGamesProvider);
  }

  /// 刷新通关列表
  void _refreshCleared() {
    ref.invalidate(clearedGamesProvider);
  }

  /// 刷新标签
  void _refreshTags() {
    ref.invalidate(allTagsProvider);
    ref.invalidate(allSeriesProvider);
  }

  /// 刷新所有游戏相关 provider（关闭详情页等场景使用）
  void _refreshAllProviders() {
    _refreshGames();
    _refreshPlayed();
    _refreshFavorites();
    _refreshCleared();
    _refreshTags();
  }

  Future<String?> _findLeProcPath() async {
    final repo = ref.read(toolRepositoryProvider);
    final tools = await repo.getAllTools();
    debugPrint('[LE] Searching for LEProc.exe among ${tools.length} tools');
    for (final tool in tools) {
      final fileName = tool.path.split(RegExp(r'[/\\]')).last.toLowerCase();
      debugPrint('[LE] Tool: ${tool.name} -> $fileName');
      if (fileName == 'leproc.exe') {
        final file = File(tool.path);
        final exists = await file.exists();
        debugPrint('[LE] Found LEProc.exe at ${tool.path}, exists: $exists');
        if (exists) return tool.path;
      }
    }
    debugPrint('[LE] LEProc.exe not found in tools');
    return null;
  }

  Future<bool> _launchWithLocaleEmulator(Game game) async {
    debugPrint('[LE] Attempting locale emulator launch for: ${game.title}');
    final leProcPath = await _findLeProcPath();
    if (leProcPath == null) {
      debugPrint('[LE] LEProc.exe path is null, returning false');
      return false;
    }

    // Find the actual game exe path (not the directory)
    String? exePath;

    // First check if we have a stored launcher path
    if (game.launcherLocked && game.gameLauncher != null && game.gameLauncher!.isNotEmpty) {
      final file = File(game.gameLauncher!);
      if (await file.exists()) {
        exePath = game.gameLauncher!;
        debugPrint('[LE] Using stored launcher: $exePath');
      }
    }

    // If no stored launcher, look for common exe files in game directory
    if (exePath == null) {
      final gameDir = Directory(game.path);
      if (await gameDir.exists()) {
        final fallbackExes = ['game.exe', 'Game.exe', 'launcher.exe', 'launch.exe', 'player.exe', 'play.exe'];
        for (final exeName in fallbackExes) {
          final exeFile = File('${game.path}${Platform.pathSeparator}$exeName');
          if (await exeFile.exists()) {
            exePath = exeFile.path;
            debugPrint('[LE] Found fallback exe: $exePath');
            break;
          }
        }

        // If still not found, scan for any .exe in the game directory (top level only)
        if (exePath == null) {
          await for (final entity in gameDir.list()) {
            if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
              exePath = entity.path;
              debugPrint('[LE] Found exe by scanning: $exePath');
              break;
            }
          }
        }
      }
    }

    if (exePath == null) {
      debugPrint('[LE] Could not find game exe in ${game.path}');
      if (mounted) {
        AppTheme.showGlassToast(context, message: '未找到游戏启动器，请先手动启动一次游戏', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
      }
      return false;
    }

    try {
      debugPrint('[LE] Running: $leProcPath with args: [$exePath]');
      final result = await Process.run(leProcPath, [exePath]);
      debugPrint('[LE] Process exit code: ${result.exitCode}');
      debugPrint('[LE] stdout: ${result.stdout}');
      debugPrint('[LE] stderr: ${result.stderr}');
      return true;
    } catch (e) {
      debugPrint('[LE] Launch failed with exception: $e');
      if (mounted) {
        AppTheme.showGlassToast(context, message: '转区启动失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _currentGame = widget.game;
    _titleController = TextEditingController(text: _currentGame.title);
    _versionController = TextEditingController(text: _currentGame.version);
    _introController = TextEditingController(text: _currentGame.intro);
    _featuresController = TextEditingController(text: _currentGame.features);
    _changelogController = TextEditingController(text: _currentGame.changelog);
    _downloadUrlController = TextEditingController(text: _currentGame.downloadUrl ?? '');
    _sourceUrlController = TextEditingController(text: _currentGame.sourceUrl ?? '');
    _gameLauncherController = TextEditingController(text: _currentGame.gameLauncher ?? '');
    _pathController = TextEditingController(text: _currentGame.path);
    _makerController = TextEditingController(text: _currentGame.maker ?? '');
    _editedTags = List.from(_currentGame.tags);
    _guideController = TextEditingController(text: _currentGame.guide);
    _contentScrollController = ScrollController();
    _contentScrollController.addListener(_onScroll);
    _repo = ref.read(gameRepositoryProvider);
    _checkIsLocal();
    _forceReloadImages();
    Future.wait([_preloadMediaFiles(), _loadMetadataHtml()]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[ScrollPos] postFrameCallback: calling _restoreScrollPositions');
      _restoreScrollPositions();
    });
    ServicesBinding.instance.keyboard.addHandler(_handleKeyDown);
  }

  void _forceReloadImages() {
    imageCache.clear();
    if (mounted) setState(() => _imageVersion++);
  }

  Future<void> _checkIsLocal() async {
    final sourceUrlFile = File('${_currentGame.path}${Platform.pathSeparator}source_url.txt');
    final exists = await sourceUrlFile.exists();
    if (mounted) {
      setState(() {
        _isLocal = !exists;
      });
    }
  }

  Future<void> _preloadMediaFiles() async {
    final imageTagStart = '[图片:';
    final videoTagStart = '[视频:';
    final tagEnd = ']';
    final paths = <String>{};

    for (final content in [_currentGame.intro, _currentGame.features, _currentGame.changelog, _currentGame.guide]) {
      if (content == null) continue;
      for (final line in content.split('\n')) {
        if (line.startsWith(imageTagStart) && line.endsWith(tagEnd)) {
          paths.add(line.substring(imageTagStart.length, line.length - tagEnd.length));
        } else if (line.startsWith(videoTagStart) && line.endsWith(tagEnd)) {
          paths.add(line.substring(videoTagStart.length, line.length - tagEnd.length));
        }
      }
    }

    final existing = <String>{};
    for (final path in paths) {
      if (await File(path).exists()) {
        existing.add(path);
      }
    }

    if (mounted) {
      setState(() {
        _existingMediaFiles = existing;
      });
    }
  }

  Future<void> _loadMetadataHtml() async {
    try {
      final metadataFile = File('${_currentGame.path}${Platform.pathSeparator}metadata.json');
      if (await metadataFile.exists()) {
        final json = jsonDecode(await metadataFile.readAsString());
        _introHtml = json['intro_html'] as String?;
      }
    } catch (e) {
      debugPrint('[GameDetail] 加载metadata HTML失败: $e');
    }
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_handleKeyDown);
    debugPrint('[ScrollPos] dispose: saving scroll position');
    _captureAndSaveScrollPositions();
    _scrollSaveDebounce?.cancel();
    _contentScrollController.removeListener(_onScroll);
    _contentScrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _quickScrapeController.dispose();
    _titleController.dispose();
    _versionController.dispose();
    _introController.dispose();
    _featuresController.dispose();
    _changelogController.dispose();
    _downloadUrlController.dispose();
    _sourceUrlController.dispose();
    _gameLauncherController.dispose();
    _pathController.dispose();
    _makerController.dispose();
    _guideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.9;
    final dialogHeight = screenSize.height * 0.9;

    return PopScope(
      canPop: !_isImageViewerOpen,
      child: Dialog(
        backgroundColor: AppTheme.getSurfaceDeepColor(context),
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        ),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppTheme.getSurfaceDeepColor(context),
            borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: AppTheme.getShadowColor(context).withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 2.0 : 3.0),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              if (_downloadTotal > 0 && _downloadCurrent < _downloadTotal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.08),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cloud_download, size: 14, color: AppTheme.getPrimaryColor(context)),
                          const SizedBox(width: 8),
                          Text(
                            '正在下载截图 $_downloadCurrent/$_downloadTotal',
                            style: TextStyle(fontSize: 12, color: AppTheme.getPrimaryColor(context)),
                          ),
                          const Spacer(),
                          Text(
                            '${(_downloadProgress * 100).round()}%',
                            style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: AppTheme.getPrimaryColor(context).withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getPrimaryColor(context)),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              _buildHeader(),
              Container(height: 1, color: AppTheme.getBorderColor(context)),
              Expanded(
                child: _buildBody(),
              ),
              if (_isEditing) Container(height: 1, color: AppTheme.getBorderColor(context)),
              if (_isEditing) _buildEditBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.getPrimaryColor(context).withValues(alpha: 0.08), Colors.transparent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.videogame_asset, color: AppTheme.getPrimaryColor(context), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEditing ? (_titleController.text.isEmpty ? '游戏详情' : _titleController.text) : (_currentGame.title ?? '游戏详情'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!_isEditing) ...[
            SizedBox(
              width: 320,
              height: 36,
              child: TextField(
                controller: _quickScrapeController,
                style: TextStyle(fontSize: 13, color: AppTheme.getDetailTextPrimary(context)),
                decoration: InputDecoration(
                  hintText: '输入链接/id/关键词回车刮削',
                  hintStyle: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context).withValues(alpha: 0.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.getGlassFillColor(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.5)),
                  ),
                  prefixIcon: GestureDetector(
                    onTap: () {
                      setState(() => _showChannelSelector = !_showChannelSelector);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        Icon(
                          _quickScrapeChannel == 'steam'
                              ? Icons.computer
                              : _quickScrapeChannel == 'dlsite'
                                  ? Icons.language
                                  : Icons.auto_fix_high,
                          size: 16,
                          color: AppTheme.getPrimaryColor(context),
                        ),
                        if (_showChannelSelector) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => setState(() {
                              _quickScrapeChannel = 'auto';
                              _showChannelSelector = false;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _quickScrapeChannel == 'auto' ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('自动', style: TextStyle(fontSize: 10, color: _quickScrapeChannel == 'auto' ? AppTheme.getPrimaryColor(context) : AppTheme.getTextSecondary(context))),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() {
                              _quickScrapeChannel = 'steam';
                              _showChannelSelector = false;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _quickScrapeChannel == 'steam' ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Steam', style: TextStyle(fontSize: 10, color: _quickScrapeChannel == 'steam' ? AppTheme.getPrimaryColor(context) : AppTheme.getTextSecondary(context))),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() {
                              _quickScrapeChannel = 'dlsite';
                              _showChannelSelector = false;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _quickScrapeChannel == 'dlsite' ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('DLsite', style: TextStyle(fontSize: 10, color: _quickScrapeChannel == 'dlsite' ? AppTheme.getPrimaryColor(context) : AppTheme.getTextSecondary(context))),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                  suffixIcon: _quickScrapeController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _quickScrapeController.clear();
                            setState(() {});
                          },
                          child: Icon(Icons.close, size: 16, color: AppTheme.getTextSecondary(context)),
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _quickScrape(),
              ),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (context) => Tooltip(
                message: _currentGame.sourceUrl == null || _currentGame.sourceUrl!.isEmpty
                    ? '该游戏没有来源URL，无法重新刮削'
                    : '重新刮削',
                child: IconButton(
                  icon: _isRescraping
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.refresh, size: 20, color: _currentGame.sourceUrl != null && _currentGame.sourceUrl!.isNotEmpty
                          ? AppTheme.getDetailTextPrimary(context)
                          : AppTheme.getDetailTextPrimary(context).withValues(alpha: 0.3)),
                  onPressed: _currentGame.sourceUrl != null && _currentGame.sourceUrl!.isNotEmpty && !_isRescraping
                      ? _rescrapeGame
                      : null,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 20, color: AppTheme.getDetailTextPrimary(context)),
              tooltip: '编辑',
              onPressed: () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 22, color: AppTheme.getDetailTextPrimary(context)),
              tooltip: '关闭 (ESC)',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Row(
      children: [
        SizedBox(width: 320, child: _buildLeftPanel()),
        Container(
          width: 1,
          color: AppTheme.getBorderColor(context),
        ),
        Expanded(
          child: Column(
            children: [
              if (_isSearchOpen)
                DetailSearchBar(
                  controller: _searchController,
                  matches: _searchMatches,
                  currentMatchIndex: _currentMatchIndex,
                  hasSearched: _searchController.text.isNotEmpty,
                  onNext: _nextMatch,
                  onPrevious: _previousMatch,
                  onSearch: _onSearchChanged,
                  onClose: () {
                    setState(() {
                      _isSearchOpen = false;
                      _searchMatches = [];
                      _currentMatchIndex = -1;
                      _searchController.clear();
                    });
                  },
                ),
              Expanded(child: _buildContentPanel()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeftPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageCarousel(),
          const SizedBox(height: 16),
          GestureDetector(
            onSecondaryTapUp: (details) async {
              final leProcPath = await _findLeProcPath();
              if (leProcPath == null) {
                if (mounted) {
                  AppTheme.showGlassToast(context, message: '未找到 LEProc.exe，请先在工具页面导入', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
                }
                return;
              }

              if (!mounted) return;
              showMenu(
                context: context,
                position: RelativeRect.fromLTRB(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  details.globalPosition.dx + 1,
                  details.globalPosition.dy + 1,
                ),
                items: [
                  PopupMenuItem(
                    child: Row(
                      children: [
                        Icon(
                          _currentGame.useLocaleEmulator ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18,
                          color: AppTheme.getPrimaryColor(context),
                        ),
                        const SizedBox(width: 8),
                        const Text('转区启动'),
                      ],
                    ),
                    onTap: () async {
                      final newValue = !_currentGame.useLocaleEmulator;
                      debugPrint('[LE] Toggling locale emulator for ${_currentGame.title}: $newValue');
                      final repo = ref.read(gameRepositoryProvider);
                      await repo.updateLocaleEmulator(_currentGame.id!, newValue);
                      if (!mounted) return;
                      setState(() {
                        _currentGame = _currentGame.copyWith(useLocaleEmulator: newValue);
                      });
                      if (mounted) {
                        AppTheme.showGlassToast(
                          context,
                          message: newValue ? '已切换为转区启动模式' : '已切换为普通启动模式',
                          icon: newValue ? Icons.language : Icons.play_arrow,
                          iconColor: AppTheme.getPrimaryColor(context),
                        );
                      }
                    },
                  ),
                ],
              );
            },
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final repo = ref.read(gameRepositoryProvider);
                  try {
                    await repo.markAsPlayed(_currentGame.id!);
                    if (!mounted) return;
                    setState(() {
                      _currentGame = _currentGame.copyWith(
                        isPlayed: true,
                        playCount: _currentGame.playCount + 1,
                        lastPlayedTime: DateTime.now(),
                      );
                    });
                    // 开始追踪游玩时长
                    PlayTimeTracker.startTracking(_currentGame);
                  } catch (e) {
                    debugPrint('markAsPlayed error: $e');
                  }

                  bool launched = false;

                  // 优先检查转区启动
                  if (_currentGame.useLocaleEmulator) {
                    debugPrint('[LE] Game has locale emulator flag, attempting LE launch');
                    launched = await _launchWithLocaleEmulator(_currentGame);
                    // 如果转区启动失败（工具不存在），自动回退并清除标记
                    if (!launched) {
                      debugPrint('[LE] LE launch failed, checking if LEProc exists');
                      final leProcPath = await _findLeProcPath();
                      if (leProcPath == null) {
                        await repo.updateLocaleEmulator(_currentGame.id!, false);
                        if (!mounted) return;
                        setState(() {
                          _currentGame = _currentGame.copyWith(useLocaleEmulator: false);
                        });
                        if (mounted) {
                          AppTheme.showGlassToast(context, message: 'LEProc.exe 不存在，已回退为普通启动', icon: Icons.warning_amber, iconColor: AppTheme.warningColor);
                        }
                      }
                    }
                  }

                  // 普通启动
                  if (!launched) {
                    launched = await _launchGame(_currentGame);
                  }

                  if (!launched && mounted) {
                    final result = await FilePicker.pickFiles(
                      dialogTitle: '选择游戏启动器',
                      type: FileType.any,
                      initialDirectory: _currentGame.path,
                    );
                    if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
                      final launcherPath = result.files.first.path!;
                      final updated = _currentGame.copyWith(
                        gameLauncher: launcherPath,
                        launcherLocked: true,
                      );
                      await repo.updateGame(updated);
                      if (!mounted) return;
                      setState(() {
                        _currentGame = updated;
                      });
                      try {
                        await Process.run(launcherPath, [], workingDirectory: _currentGame.path);
                      } catch (e) {
                        if (mounted) {
                          AppTheme.showGlassToast(context, message: '启动失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
                        }
                      }
                    } else {
                      try {
                        await Process.run('explorer.exe', [_currentGame.path]);
    } catch (_) {
      // 浏览器打开失败时静默处理
    }
  }
                  }

                  if (mounted) {
                    _refreshAllProviders();
                  }
                },
                icon: Icon(
                  _currentGame.useLocaleEmulator ? Icons.language : Icons.play_arrow,
                  size: 20,
                ),
                label: Text(_currentGame.useLocaleEmulator ? '开始游玩[转区]' : '开始游玩'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _currentGame.useLocaleEmulator
                      ? AppTheme.secondaryColor
                      : AppTheme.getPrimaryColor(context),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 存档按钮 - 仅在已玩/已通关时显示
          if (_currentGame.isPlayed || _currentGame.playCount > 0)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openSaveLocation(),
                icon: const Icon(Icons.folder_special, size: 18),
                label: const Text('存档管理'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.getPrimaryColor(context),
                  side: BorderSide(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassConstants.radiusMedium)),
                ),
              ),
            ),
          const SizedBox(height: 24),
          _buildInfoCard(),
        ],
      ),
    );
  }

  Widget _buildImageCarousel() {
    final images = _currentGame.images;
    
    return Column(
      children: [
        if (images.isEmpty)
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_not_supported_outlined, size: 48, color: AppTheme.getDetailTextPrimary(context).withValues(alpha: 0.3)),
                  const SizedBox(height: 8),
                  Text('暂无图片', style: TextStyle(color: AppTheme.getDetailTextPrimary(context).withValues(alpha: 0.5), fontSize: 13)),
                ],
              ),
            ),
          )
        else
          GestureDetector(
            onTap: () => setState(() => _currentImageIndex = (_currentImageIndex + 1) % images.length),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(GlassConstants.radiusMedium - 1),
                    child: Image.file(
                      File(images[_currentImageIndex].imagePath),
                      key: ValueKey('img_${_imageVersion}_${images[_currentImageIndex].imagePath}'),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.3),
                        child: Center(child: Icon(Icons.broken_image, size: 36, color: AppTheme.getDetailTextPrimary(context).withValues(alpha: 0.3))),
                      ),
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.getOverlayColor(context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${_currentImageIndex + 1} / ${images.length}', style: TextStyle(fontSize: 11, color: AppTheme.getTextColorOnPrimary(context))),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openImageManager,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('管理图片'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.getPrimaryColor(context),
              side: BorderSide(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  void _openImageManager() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ImageManagerDialog(game: _currentGame),
    );

    if (result == true) {
      final repo = ref.read(gameRepositoryProvider);
      final freshGame = await repo.getGameById(_currentGame.id!);
      if (freshGame != null && mounted) {
        setState(() {
          _currentGame = freshGame;
          _currentImageIndex = 0;
          _imageVersion++;
        });
      }
    }
  }

  bool _isLocalGame() {
    return _isLocal;
  }

  void _insertImageToContent(String sectionTitle) async {
    // 获取游戏已有图片列表
    final images = _currentGame.images;
    if (images.isEmpty) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '请先添加图片');
      }
      return;
    }

    // 显示图片选择对话框
    final selectedImage = await showDialog<GameImage>(
      context: context,
      builder: (context) => _ImageSelectionDialog(images: images),
    );
    if (selectedImage == null) return;

    // 获取对应的 TextEditingController
    TextEditingController controller;
    switch (sectionTitle) {
      case '简介':
        controller = _introController;
        break;
      case '特性':
        controller = _featuresController;
        break;
      case '更新日志':
        controller = _changelogController;
        break;
      default:
        return;
    }

    // 在光标位置插入图片标记
    final text = controller.text;
    final selection = controller.selection;
    final imageTag = '\n[图片:${selectedImage.imagePath}]\n';
    
    // 检查 selection 是否有效
    final startPos = selection.start >= 0 ? selection.start : text.length;
    final endPos = selection.end >= 0 ? selection.end : text.length;
    
    final newText = text.replaceRange(startPos, endPos, imageTag);
    controller.text = newText;
    
    // 更新光标位置
    final newCursorPos = startPos + imageTag.length;
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: newCursorPos),
    );

    if (mounted) {
      AppTheme.showGlassToast(context, message: '图片已插入');
    }
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.getGlassFillColor(context),
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tags above path (Change 2)
          if (_isEditing) ...[
            _buildEditableTags(),
          ] else if (_currentGame.tags.isNotEmpty) ...[
            Builder(
              builder: (context) {
                final seen = <String>{};
                final orderedTags = <Tag>[];
                final makerName = _currentGame.maker?.trim();
                if (makerName != null && makerName.isNotEmpty) {
                  for (final t in _currentGame.tags) {
                    if (t.name.toLowerCase() == makerName.toLowerCase() && !seen.contains(t.name.toLowerCase())) {
                      orderedTags.add(t);
                      seen.add(t.name.toLowerCase());
                      break;
                    }
                  }
                }
                for (final t in _currentGame.tags) {
                  if (!seen.contains(t.name.toLowerCase())) {
                    orderedTags.add(t);
                    seen.add(t.name.toLowerCase());
                  }
                }
                return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: orderedTags.map((tag) => GestureDetector(
                onTap: () {
                  if (widget.onTagTap != null) {
                    Navigator.of(context).pop(tag);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Text(tag.name, style: const TextStyle(fontSize: 11, color: Colors.blue)),
                ),
              )).toList(),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
if (_isEditing) ...[
  Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.folder_outlined, size: 15, color: AppTheme.getDetailTextPrimary(context)),
      const SizedBox(width: 8),
      Text('路径:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
      const SizedBox(width: 6),
      Expanded(
        child: TextField(
          controller: _pathController,
          maxLines: 3,
          style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context)),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
          onChanged: (_) {
            if (!_pathChanged) setState(() => _pathChanged = true);
          },
        ),
      ),
    ],
  ),
] else ...[
  _InfoRow(icon: Icons.folder_outlined, label: '路径', value: _currentGame.path, isPath: true),
],
          if (_isEditing) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tag, size: 15, color: AppTheme.getDetailTextPrimary(context)),
                const SizedBox(width: 8),
                Text('版本:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _versionController,
                    style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context)),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.business, size: 15, color: AppTheme.getDetailTextPrimary(context)),
                const SizedBox(width: 8),
                Text('厂商:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _makerController,
                    style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context)),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                      hintText: '输入厂商名',
                    ),
                    onChanged: (value) {
                      _currentGame = _currentGame.copyWith(maker: value.isEmpty ? null : value);
                    },
                  ),
                ),
              ],
            ),
          ] else if (_currentGame.version != null) ...[
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.tag, label: '版本', value: _currentGame.version!),
          ],
          const SizedBox(height: 10),
          _InfoRow(
            icon: _currentGame.isPlayed ? Icons.check_circle : Icons.circle_outlined,
            label: '状态',
            value: _currentGame.isPlayed ? '已游玩 (${_currentGame.playCount}次)' : '未游玩',
            valueColor: _currentGame.isPlayed ? AppTheme.successColor : AppTheme.getDetailTextPrimary(context),
          ),
          if (_currentGame.lastPlayedTime != null) ...[
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.access_time, label: '最后游玩', value: _formatDate(_currentGame.lastPlayedTime!)),
          ],
          if (_isEditing) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.link, size: 15, color: AppTheme.getDetailTextPrimary(context)),
                const SizedBox(width: 8),
                Text('来源:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _sourceUrlController,
                    style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context)),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                      hintText: '输入来源链接',
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_currentGame.sourceUrl != null && _currentGame.sourceUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.link, size: 15, color: AppTheme.getDetailTextPrimary(context)),
                const SizedBox(width: 8),
                Text('来源:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await launchUrl(Uri.parse(_currentGame.sourceUrl!));
                    } catch (_) {
                      // 外部浏览器打开失败时静默处理
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 12),
                  label: const Text('来源', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
                    foregroundColor: AppTheme.getPrimaryColor(context),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.3)),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_isEditing) ...[
            const SizedBox(height: 12),
            Text('启动器路径', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.getDetailTextPrimary(context))),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _gameLauncherController,
                    decoration: InputDecoration(
                      hintText: '留空则自动检测',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context).withValues(alpha: 0.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.pickFiles(
                      dialogTitle: '选择启动器文件',
                      type: FileType.any,
                      initialDirectory: _currentGame.path,
                    );
                    if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
                      _gameLauncherController.text = result.files.first.path!;
                    }
                  },
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('浏览', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.getPrimaryColor(context),
                    side: BorderSide(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  ),
                ),
              ],
            ),
          ],
          // 存档路径信息（仅编辑模式或有存档路径时显示）
          if (_isEditing && (_currentGame.isPlayed || _currentGame.playCount > 0)) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.folder_special, size: 15, color: AppTheme.getDetailTextPrimary(context)),
                const SizedBox(width: 8),
                Text('存档:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showEditSavePathDialog(),
                    child: Text(
                      _currentGame.savePath ?? '点击设置存档路径',
                      style: TextStyle(
                        fontSize: 12,
                        color: _currentGame.savePath != null ? AppTheme.getPrimaryColor(context) : AppTheme.getTextSecondary(context).withValues(alpha: 0.5),
                        decoration: _currentGame.savePath != null ? TextDecoration.underline : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_currentGame.savePath != null && _currentGame.savePath!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.folder_special, label: '存档', value: _currentGame.savePath!, isPath: true),
          ],
          if (_isEditing) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.timer, size: 15, color: AppTheme.getDetailTextPrimary(context)),
                const SizedBox(width: 8),
                Text('游玩时长:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: _showEditPlayDurationDialog,
                    child: Text(
                      formatDuration(_currentGame.playDuration),
                      style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context)),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_isEditing) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.download, size: 15, color: AppTheme.getDetailTextPrimary(context)),
                const SizedBox(width: 8),
                Text('下载:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _downloadUrlController,
                    maxLines: 3,
                    style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context)),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      isDense: true,
                      hintText: '输入下载链接',
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_currentGame.downloadUrl != null && _currentGame.downloadUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildDownloadLinks(_currentGame.downloadUrl!),
          ],
        ],
      ),
    );
  }

  Widget _buildEditableTags() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ..._editedTags.map((tag) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(tag.name, style: const TextStyle(fontSize: 11, color: Colors.blue), overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() => _editedTags.remove(tag)),
                child: const Icon(Icons.close, size: 12, color: Colors.blue),
              ),
            ],
          ),
        )),
        GestureDetector(
          onTap: () => _showAddTagDialog(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.2)),
            ),
            child: Icon(Icons.add, size: 12, color: AppTheme.getPrimaryColor(context)),
          ),
        ),
      ],
    );
  }

  void _showAddTagDialog() {
    showGlassDialog(
      context: context,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          final controller = TextEditingController();
          return SizedBox(
            width: GlassConstants.dialogWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('添加标签', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context))),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '输入标签名称'),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          controller.dispose();
                          Navigator.of(context).pop();
                        },
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final name = controller.text.trim();
                          controller.dispose();
                          if (name.isNotEmpty) {
                            setState(() {
                              _editedTags.add(Tag(name: name, type: Tag.typeCustom));
                            });
                          }
                          Navigator.of(context).pop();
                        },
                        child: const Text('添加'),
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

  bool _handleKeyDown(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyF &&
          (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
        setState(() {
          _isSearchOpen = !_isSearchOpen;
          if (!_isSearchOpen) {
            _searchMatches = [];
            _currentMatchIndex = -1;
          }
        });
        return true;
      }
    }
    return false;
  }

  void _onScroll() {
    if (_isRestoringScroll || _suppressScrollSave) return;
    _scrollSaveDebounce?.cancel();
    _scrollSaveDebounce = Timer(const Duration(milliseconds: 500), () {
      _captureAndSaveScrollPositions();
    });
  }

  void _captureAndSaveScrollPositions() {
    if (_currentGame.id == null || !_contentScrollController.hasClients) {
      debugPrint('[ScrollPos] SAVE skipped: id=${_currentGame.id}, hasClients=${_contentScrollController.hasClients}');
      return;
    }
    final maxScroll = _contentScrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      debugPrint('[ScrollPos] SAVE skipped: maxScroll=$maxScroll');
      return;
    }
    final ratio = _contentScrollController.offset / maxScroll;
    final introRatio = _showGuide ? _currentGame.introScrollPosition : ratio;
    final guideRatio = _showGuide ? ratio : _currentGame.guideScrollPosition;
    debugPrint('[ScrollPos] SAVE: id=${_currentGame.id}, showGuide=$_showGuide, offset=${_contentScrollController.offset}, maxScroll=$maxScroll, ratio=$ratio, introRatio=$introRatio, guideRatio=$guideRatio');
    _currentGame = _currentGame.copyWith(
      introScrollPosition: introRatio,
      guideScrollPosition: guideRatio,
    );
    _repo?.updateScrollPosition(
      _currentGame.id!,
      introPosition: introRatio,
      guidePosition: guideRatio,
    );
  }

  Future<void> _restoreScrollPositions() async {
    if (_currentGame.id == null || !_contentScrollController.hasClients) {
      debugPrint('[ScrollPos] RESTORE skipped: id=${_currentGame.id}, hasClients=${_contentScrollController.hasClients}');
      return;
    }
    final maxScroll = _contentScrollController.position.maxScrollExtent;
    debugPrint('[ScrollPos] RESTORE: initial maxScroll=$maxScroll, showGuide=$_showGuide');
    if (maxScroll <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScrollPositions());
      return;
    }
    final repo = ref.read(gameRepositoryProvider);
    final freshGame = await repo.getGameById(_currentGame.id!);
    if (freshGame != null) {
      _currentGame = freshGame;
      debugPrint('[ScrollPos] RESTORE: refreshed game, introRatio=${_currentGame.introScrollPosition}, guideRatio=${_currentGame.guideScrollPosition}');
    } else {
      debugPrint('[ScrollPos] RESTORE: freshGame is null');
    }
    final targetRatio = _showGuide ? _currentGame.guideScrollPosition : _currentGame.introScrollPosition;
    debugPrint('[ScrollPos] RESTORE: targetRatio=$targetRatio');
    _suppressScrollSave = true;
    _lastStableMax = 0;
    _stableFrames = 0;
    _restoreFrameCount = 0;
    if (targetRatio > 0) {
      _applyRestoreJump(targetRatio);
    } else {
      _releaseRestoreLock();
    }
  }

  void _applyRestoreJump(double targetRatio) {
    _restoreFrameCount++;
    if (!_contentScrollController.hasClients) {
      _releaseRestoreLock();
      return;
    }
    final maxScroll = _contentScrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      if (_restoreFrameCount > 300) {
        debugPrint('[ScrollPos] RESTORE: timeout after 300 frames');
        _releaseRestoreLock();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyRestoreJump(targetRatio));
      return;
    }
    // First frame: always jump immediately for fast feedback
    if (_restoreFrameCount == 1) {
      _lastStableMax = maxScroll;
      _stableFrames = 0;
      final targetOffset = (targetRatio * maxScroll).clamp(0.0, maxScroll);
      debugPrint('[ScrollPos] RESTORE: initial jump to $targetOffset (ratio=$targetRatio, maxScroll=$maxScroll)');
      _isRestoringScroll = true;
      _contentScrollController.jumpTo(targetOffset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isRestoringScroll = false;
        _applyRestoreJump(targetRatio);
      });
      return;
    }
    // Subsequent frames: track stability
    if (maxScroll == _lastStableMax) {
      _stableFrames++;
      if (_stableFrames >= 5) {
        debugPrint('[ScrollPos] RESTORE: stable at maxScroll=$maxScroll (${_stableFrames}frames), done');
        _releaseRestoreLock();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyRestoreJump(targetRatio));
      return;
    }
    // maxScroll grew: do a corrective jump
    _lastStableMax = maxScroll;
    _stableFrames = 0;
    final targetOffset = (targetRatio * maxScroll).clamp(0.0, maxScroll);
    debugPrint('[ScrollPos] RESTORE: corrective jump to $targetOffset (ratio=$targetRatio, maxScroll=$maxScroll)');
    _isRestoringScroll = true;
    _contentScrollController.jumpTo(targetOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isRestoringScroll = false;
      _applyRestoreJump(targetRatio);
    });
  }

  void _releaseRestoreLock() {
    _scrollSaveDebounce?.cancel();
    Future.delayed(const Duration(milliseconds: 600), () {
      _suppressScrollSave = false;
    });
  }

  Future<void> _switchTab(bool showGuide) async {
    if (_showGuide == showGuide) return;

    _captureAndSaveScrollPositions();

    if (!mounted) return;

    setState(() {
      _showGuide = showGuide;
      if (_isSearchOpen && _searchController.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _performSearch(_searchController.text);
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScrollPositions();
    });
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      setState(() {
        _searchMatches = [];
        _currentMatchIndex = -1;
      });
      return;
    }

    final sections = <String, String?>{
      if (!_showGuide)
        'intro': _introHtml != null && _introHtml!.isNotEmpty
            ? _buildSearchTextFromHtml(_introHtml!)
            : _currentGame.intro,
      if (_showGuide) 'guide': _currentGame.guide,
      'features': _currentGame.features,
      'changelog': _currentGame.changelog,
    };

    setState(() {
      _searchMatches = ContentSearchEngine.findAll(
        query: trimmedQuery,
        sections: sections,
      );
      _currentMatchIndex = _searchMatches.isNotEmpty ? 0 : -1;
    });

    if (_searchMatches.isNotEmpty) {
      debugPrint('[Search] Found ${_searchMatches.length} matches, first: sectionKey=${_searchMatches[0].sectionKey}, lineIndex=${_searchMatches[0].lineIndex}');
      for (final m in _searchMatches) {
        debugPrint('[HTMLSearch] match: sectionKey=${m.sectionKey}, lineIndex=${m.lineIndex}, charOffset=${m.charOffset}, matchLength=${m.matchLength}');
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToMatch(_searchMatches[_currentMatchIndex]);
      });
    }
  }

  /// 从 HTML 构建搜索文本，行索引与 _buildHtmlContent 保持一致
  String _buildSearchTextFromHtml(String html) {
    final blocks = _parseHtmlToBlocks(html, '');
    final buffer = StringBuffer();
    for (final block in blocks) {
      final textLines = block.text.split('\n');
      if (textLines.any((l) => l.isNotEmpty)) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(block.text);
      }
    }
    return buffer.toString();
  }

  Future<void> _scrollToMatch(ContentSearchMatch match) async {
    final exactKey = _contentBlockKeys['${match.sectionKey}_${match.lineIndex}'];
    debugPrint('[Search] _scrollToMatch: sectionKey=${match.sectionKey}, lineIndex=${match.lineIndex}, exactKey found=${exactKey != null}, context=${exactKey?.currentContext != null}');
    debugPrint('[HTMLSearch] _contentBlockKeys keys: ${_contentBlockKeys.keys.where((k) => k.startsWith('${match.sectionKey}_')).toList()}');

    GlobalKey? targetKey = exactKey;
    if (targetKey == null || targetKey.currentContext == null) {
      debugPrint('[HTMLSearch] Exact key not found or has null context, searching for nearest key...');
      for (var offset = 1; offset < 50; offset++) {
        for (final dir in [-1, 1]) {
          final candidateKey = _contentBlockKeys['${match.sectionKey}_${match.lineIndex + offset * dir}'];
          if (candidateKey != null && candidateKey.currentContext != null) {
            targetKey = candidateKey;
            debugPrint('[HTMLSearch] Found nearest key at offset=${offset * dir}: ${match.sectionKey}_${match.lineIndex + offset * dir}');
            break;
          }
        }
        if (targetKey != null) break;
      }
      if (targetKey == null || targetKey.currentContext == null) {
        debugPrint('[HTMLSearch] No valid key found for sectionKey=${match.sectionKey}, falling back to any key in this section');
        final fallbackKey = _contentBlockKeys.keys
            .where((k) => k.startsWith('${match.sectionKey}_'))
            .map((k) => _contentBlockKeys[k])
            .firstWhere((k) => k?.currentContext != null, orElse: () => null);
        if (fallbackKey == null || fallbackKey.currentContext == null) return;
        targetKey = fallbackKey;
      }
    }

    try {
      await Scrollable.ensureVisible(
        targetKey!.currentContext!,
        alignment: 0.1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      debugPrint('[Search] ensureVisible error: $e');
    }
  }

  void _nextMatch() {
    if (_searchMatches.isEmpty) return;
    final newIndex = (_currentMatchIndex + 1) % _searchMatches.length;

    if (newIndex == _currentMatchIndex && _searchMatches.length == 1) return;

    setState(() {
      _currentMatchIndex = newIndex;
    });
    _scrollToMatch(_searchMatches[_currentMatchIndex]);
  }

  void _previousMatch() {
    if (_searchMatches.isEmpty) return;
    final newIndex = (_currentMatchIndex - 1 + _searchMatches.length) % _searchMatches.length;

    if (newIndex == _currentMatchIndex && _searchMatches.length == 1) return;

    setState(() {
      _currentMatchIndex = newIndex;
    });
    _scrollToMatch(_searchMatches[_currentMatchIndex]);
  }

  Widget _buildContentPanel() {
    _contentBlockKeys.clear();
    final images = _currentGame.images;
    return Stack(
      children: [
        SelectionArea(
          child: SingleChildScrollView(
            key: _contentPanelKey,
            controller: _contentScrollController,
            padding: const EdgeInsets.all(28),
            child: Column(
              key: _scrollContentKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          if (_isEditing)
            TextField(
              controller: _titleController,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context), height: 1.4),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                hintText: '输入游戏标题',
              ),
              maxLines: null,
            )
          else
            SelectableText(
              _currentGame.title ?? '未命名游戏', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context), height: 1.4),
            ),

          if (!_isEditing && _currentGame.maker != null && _currentGame.maker!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.business, size: 15, color: AppTheme.getTextSecondary(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _currentGame.maker!.split(', ').map((name) {
                      final trimmedName = name.trim();
                      return InkWell(
                        onTap: () {
                          if (_currentGame.makerUrl != null && _currentGame.makerUrl!.isNotEmpty) {
                            launchUrl(Uri.parse(_currentGame.makerUrl!));
                          }
                        },
                        onDoubleTap: () {
                          Clipboard.setData(ClipboardData(text: trimmedName));
                          AppTheme.showGlassToast(
                            context,
                            message: '已复制: $trimmedName',
                            icon: Icons.copy,
                            iconColor: AppTheme.successColor,
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            trimmedName,
                            style: TextStyle(fontSize: 13, color: AppTheme.getPrimaryColor(context), fontWeight: FontWeight.w500),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
          if (_currentGame.version != null || _currentGame.rating > 0 || _currentGame.playDuration > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_currentGame.version != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_currentGame.version ?? '',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.getPrimaryColor(context))),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _isCheckingUpdate ? null : _checkForUpdate,
                          child: _isCheckingUpdate
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.getPrimaryColor(context)),
                                )
                              : Icon(Icons.browser_updated, size: 16, color: AppTheme.getPrimaryColor(context)),
                        ),
                      ],
                    ),
                  ),
                if (_currentGame.playDuration > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer, size: 14, color: AppTheme.getPrimaryColor(context)),
                        const SizedBox(width: 4),
                        Text(
                          formatDuration(_currentGame.playDuration),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.getPrimaryColor(context)),
                        ),
                      ],
                    ),
                  ),
                if (_currentGame.rating > 0) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      if (_currentGame.rating >= starValue) {
                        return Icon(Icons.star, size: 18, color: AppTheme.getStarColor(context));
                      } else if (_currentGame.rating >= starValue - 0.5) {
                        return Icon(Icons.star_half, size: 18, color: AppTheme.getStarColor(context));
                      } else {
                        return Icon(Icons.star_border, size: 18, color: AppTheme.getTextSecondary(context));
                      }
                    }),
                  ),
                  if (_currentGame.review != null && _currentGame.review!.isNotEmpty)
                    _HoverReviewButton(
                      review: _currentGame.review!,
                      onTap: () => _showReviewDetail(context),
                      onDoubleTap: () {
                        Clipboard.setData(ClipboardData(text: _currentGame.review!));
                        AppTheme.showGlassToast(context, message: '已复制评论内容');
                      },
                    ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 32),
          Container(
            height: 1,
            color: AppTheme.getBorderColor(context).withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),

          // Tab切换：简介/攻略
          Row(
            children: [
              _buildTabButton('简介', !_showGuide, () => _switchTab(false)),
              const SizedBox(width: 8),
              _buildTabButton('攻略', _showGuide, () => _switchTab(true)),
            ],
          ),
          const SizedBox(height: 16),

          if (!_showGuide)
            _buildSectionWithImages(title: '简介', icon: Icons.description_outlined, content: _currentGame.intro, images: images, sectionIndex: 0)
          else
            _buildGuideSection(),

          if (_currentGame.features != null && _currentGame.features!.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildSectionWithImages(title: '特性', icon: Icons.stars_outlined, content: _currentGame.features, images: images, sectionIndex: 1),
          ],

          if (_currentGame.changelog != null && _currentGame.changelog!.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildSectionWithImages(title: '更新日志', icon: Icons.history, content: _currentGame.changelog, images: images, sectionIndex: 2),
          ],

          // 本地游戏显示全部图片画廊，刮削游戏显示更多图片
          if (_isLocalGame()) ...[
            if (images.isNotEmpty) ...[
              const SizedBox(height: 32),
              _buildAllImagesGallery(images),
            ],
          ] else ...[
          if (images.length > 3) ...[
            const SizedBox(height: 32),
            _buildImageGallery(_getUnusedImages(images)),
          ],
          ],
          ],
        ),
          ),
        ),
        DetailScrollButtons(
          scrollController: _contentScrollController,
          showGuide: _showGuide,
          onToggleGuide: () => _switchTab(!_showGuide),
        ),
      ],
    );
  }

  Widget _buildTabButton(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.3) : AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
        ),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, color: isActive ? AppTheme.getPrimaryColor(context) : AppTheme.getTextSecondary(context))),
      ),
    );
  }

  Widget _buildGuideSection() {
    if (_isEditing) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 200, maxHeight: 500),
        child: MarkdownEditor(
          controller: _guideController,
          imagePaths: _currentGame.images.map((img) => img.imagePath).toList(),
          fontSize: ref.watch(detailFontSizeProvider),
        ),
      );
    }
    
    final guide = _currentGame.guide;
    if (guide == null || guide.isEmpty) {
      return GestureDetector(
        onTap: _openGuideSearch,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3), style: BorderStyle.solid),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.menu_book, size: 24, color: AppTheme.getTextSecondary(context).withValues(alpha: 0.5)),
              const SizedBox(width: 12),
              Text('暂无攻略，点击搜索', style: TextStyle(fontSize: 14, color: AppTheme.getTextSecondary(context).withValues(alpha: 0.7))),
            ],
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _openGuideSearch,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('重新搜索'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.getPrimaryColor(context)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await _deleteGuideImages();
                setState(() {
                  _guideController.clear();
                  _currentGame = _currentGame.copyWith(guide: null);
                });
                final repo = ref.read(gameRepositoryProvider);
                await repo.updateGuide(_currentGame.id!, null);
                _syncGuideToMetadata(null);
              },
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('清除攻略'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildRichIntro(guide, ref.watch(detailFontSizeProvider), sectionKey: 'guide'),
      ],
    );
  }

  void _openGuideSearch() async {
    final title = _currentGame.title ?? '';
    final keyword = _extractSearchKeyword(title);

    // 先删除旧的攻略图片（在下载新图片之前）
    await _deleteGuideImages();

    final content = await showDialog<String>(
      context: context,
      builder: (context) => GuideSearchDialog(game: _currentGame, initialKeyword: keyword),
    );

    if (content != null && mounted) {
      setState(() {
        _guideController.text = content;
        _currentGame = _currentGame.copyWith(guide: content);
      });
      final repo = ref.read(gameRepositoryProvider);
      await repo.updateGuide(_currentGame.id!, content);
      _syncGuideToMetadata(content);
      // 重新预加载媒体文件（包括攻略中的图片）
      await _preloadMediaFiles();
    }
  }

  /// 删除攻略相关的图片文件
  Future<void> _deleteGuideImages() async {
    final imagesDir = Directory('${_currentGame.path}${Platform.pathSeparator}images');
    if (!await imagesDir.exists()) return;

    await for (final entity in imagesDir.list()) {
      if (entity is File) {
        final fileName = entity.path.split(Platform.pathSeparator).last;
        // 只删除 guide_ 开头的图片
        if (fileName.startsWith('guide_')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
  }

  String _extractSearchKeyword(String title) {
    var keyword = title;
    keyword = keyword.replaceAll(RegExp(r'[Vv]er?\.?\s*\d+[\.\d]*[a-zA-Z]*'), '');
    keyword = keyword.replaceAll(RegExp(r'[(\（]官中[)\）]|[(\（]汉化[)\）]|官中|汉化'), '');
    keyword = keyword.replaceAll(RegExp(r'\s+'), ' ').trim();
    return keyword;
  }

  void _syncGuideToMetadata(String? guide) async {
    try {
      final metadataFile = File('${_currentGame.path}${Platform.pathSeparator}metadata.json');
      Map<String, dynamic> metadata;
      if (await metadataFile.exists()) {
        metadata = jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      } else {
        metadata = <String, dynamic>{};
      }
      if (guide != null) {
        metadata['guide'] = guide;
      } else {
        metadata.remove('guide');
      }
      await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
    } catch (e) {
      debugPrint('[Edit] Failed to sync guide to metadata.json: $e');
    }
  }

  Widget _buildSectionWithImages({
    required String title,
    required IconData icon,
    String? content,
    required List<GameImage> images,
    required int sectionIndex,
  }) {
    // 刮削游戏：每个section显示1张图片
    // 本地游戏：不自动显示图片，由用户通过插入功能选择
    final isLocal = _isLocalGame();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.getPrimaryColor(context)),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.getDetailTextPrimary(context))),
          ],
        ),
        const SizedBox(height: 14),
        if (_isEditing && title == '简介') ...[
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 200,
              maxHeight: 500,
            ),
            child: MarkdownEditor(
              controller: _introController,
              imagePaths: _currentGame.images.map((img) => img.imagePath).toList(),
              fontSize: ref.watch(detailFontSizeProvider),
            ),
          ),
        ] else if (_isEditing) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: title == '特性' ? _featuresController : _changelogController,
                  maxLines: null,
                  style: TextStyle(fontSize: 14, height: 1.7, color: AppTheme.getDetailTextPrimary(context)),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              if (isLocal && images.isNotEmpty) ...[
                const SizedBox(width: 8),
                Column(
                  children: [
                    IconButton(
                      onPressed: () => _insertImageToContent(title),
                      icon: const Icon(Icons.add_photo_alternate, size: 20),
                      tooltip: '插入图片',
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
                        foregroundColor: AppTheme.getPrimaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('插入图片', style: TextStyle(fontSize: 10, color: AppTheme.getTextSecondary(context))),
                  ],
                ),
              ],
            ],
          ),
        ] else if (title == '简介' && _introHtml != null && _introHtml!.isNotEmpty) ...[
          _buildHtmlContent(_introHtml!, ref.watch(detailFontSizeProvider), sectionKey: 'intro'),
        ] else
          _buildRichIntro(content ?? '暂无信息', ref.watch(detailFontSizeProvider),
            sectionKey: title == '简介' ? 'intro' : title == '特性' ? 'features' : title == '更新日志' ? 'changelog' : null,
          ),
      ],
    );
  }

  List<_ContentBlock> _parseHtmlToBlocks(String html, String fallbackText) {
    try {
      final document = html_parser.parse(html);
      final blocks = <_ContentBlock>[];
      _parseElement(document.body ?? document.documentElement!, blocks);
      return blocks;
    } catch (_) {
      return [_ContentBlock.text(fallbackText)];
    }
  }

  void _parseElement(dynamic element, List<_ContentBlock> blocks) {
    for (final child in element.children) {
      final tag = child.localName;
      final cls = child.className;

      // Pattern 1: type_multiimages — <li class="work_parts_multiimage_item">
      if (tag == 'li' && cls.contains('work_parts_multiimage_item')) {
        final imgEl = child.querySelector('.image img');
        final textEl = child.querySelector('.text');
        final imgSrc = _resolveImgSrc(imgEl);
        final text = textEl?.text.trim() ?? '';
        if (imgSrc.isNotEmpty) {
          blocks.add(_ContentBlock.imageWithText(imgSrc, text));
        } else if (text.isNotEmpty) {
          blocks.add(_ContentBlock.text(text));
        }
      }
      // Pattern 2: type_image — work_parts_multitype_item
      else if (tag == 'div' && cls.contains('work_parts_multitype_item')) {
        if (cls.contains('type_contents')) {
          final imgEl = child.querySelector('img');
          final imgSrc = _resolveImgSrc(imgEl);
          String text = '';
          final parent = child.parent;
          if (parent != null) {
            final textSibling = parent.querySelector('.type_text');
            if (textSibling != null) {
              text = textSibling.text.trim();
            }
          }
          if (imgSrc.isNotEmpty) {
            blocks.add(_ContentBlock.imageWithText(imgSrc, text));
          }
        } else if (cls.contains('type_text')) {
          final parent = child.parent;
          final hasContentsSibling = parent?.querySelector('.type_contents') != null;
          if (!hasContentsSibling) {
            final text = child.text.trim();
            if (text.isNotEmpty) blocks.add(_ContentBlock.text(text));
          }
        }
      }
      // Container elements: recurse
      else if (tag == 'div' && cls.contains('work_parts_multitype')) {
        _parseElement(child, blocks);
      }
      else if (tag == 'ul' && cls.contains('work_parts_multiimage')) {
        _parseElement(child, blocks);
      }
      else if (tag == 'div' && cls.contains('work_parts')) {
        final heading = child.querySelector('.work_parts_heading');
        if (heading != null) {
          blocks.add(_ContentBlock.heading(heading.text.trim()));
        }
        final area = child.querySelector('.work_parts_area');
        if (area != null) {
          _parseElement(area, blocks);
        }
      }
      // Pattern 3: type_text — plain text
      else if (tag == 'p') {
        final imgEl = child.querySelector('img');
        if (imgEl != null) {
          final imgSrc = _resolveImgSrc(imgEl);
          if (imgSrc.isNotEmpty) {
            blocks.add(_ContentBlock.imageWithText(imgSrc, ''));
          }
        } else {
          final text = child.text.trim();
          if (text.isNotEmpty) {
            blocks.add(_ContentBlock.text(text));
          }
        }
      }
      else if (tag == 'h3' || tag == 'h4') {
        blocks.add(_ContentBlock.heading(child.text.trim()));
      }
      else if (tag == 'div') {
        _parseElement(child, blocks);
      }
    }
  }

  String _resolveImgSrc(dynamic imgEl) {
    if (imgEl == null) return '';
    final src = imgEl.attributes['data-original'] ??
        imgEl.attributes['data-src'] ??
        imgEl.attributes['src'] ?? '';
    return src.startsWith('//') ? 'https:$src' : src;
  }



  Widget _buildHtmlContent(String html, double fontSize, {String? sectionKey}) {
    final blocks = _parseHtmlToBlocks(html, '');
    if (blocks.isEmpty) {
      return SelectableText('暂无信息', style: TextStyle(fontSize: fontSize, color: AppTheme.getDetailTextPrimary(context)));
    }

    int lineAccum = 0;
    final children = <Widget>[];
    for (final block in blocks) {
      final textLines = block.text.split('\n');
      final startLine = lineAccum;
      final hasText = textLines.length >= 1 && textLines.any((l) => l.isNotEmpty);
      if (hasText) lineAccum += textLines.length;

      Widget buildRichTextWidget(String text, TextStyle baseStyle, TextStyle? headingStyle) {
        final lines = text.split('\n');
        final spans = <InlineSpan>[];
        for (var j = 0; j < lines.length; j++) {
          final lineIdx = startLine + j;
          final line = lines[j];
          final style = headingStyle ?? baseStyle;

          if (sectionKey != null && _searchMatches.isNotEmpty) {
            final sectionMatches = _searchMatches
                .where((m) => m.sectionKey == sectionKey && m.lineIndex == lineIdx)
                .toList();
            if (sectionMatches.isNotEmpty) {
              spans.addAll(_buildHighlightedSpans(line, sectionMatches, style));
            } else {
              spans.add(TextSpan(text: line, style: style));
            }
          } else {
            spans.add(TextSpan(text: line, style: style));
          }

          if (j < lines.length - 1) {
            spans.add(TextSpan(text: '\n', style: style));
          }

          if (sectionKey != null) {
            final key = GlobalKey();
            _contentBlockKeys['${sectionKey}_$lineIdx'] = key;
            spans.add(WidgetSpan(
              child: SizedBox(key: key, width: 1, height: fontSize),
              alignment: PlaceholderAlignment.middle,
            ));
          }
        }
        return SelectableText.rich(
          TextSpan(children: spans),
          style: TextStyle(fontSize: fontSize, height: 1.8),
        );
      }

      switch (block.type) {
        case _ContentBlockType.heading:
          children.add(Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: buildRichTextWidget(block.text,
              TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.w700, color: AppTheme.getDetailTextPrimary(context)),
              null,
            ),
          ));
        case _ContentBlockType.text:
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: buildRichTextWidget(block.text,
              TextStyle(fontSize: fontSize, height: 1.8, color: AppTheme.getDetailTextPrimary(context)),
              null,
            ),
          ));
        case _ContentBlockType.imageWithText:
          final imageBlock = Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: block.text.isNotEmpty
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 350, maxHeight: 280),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildBlockImage(block.imageUrl!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: buildRichTextWidget(block.text,
                          TextStyle(fontSize: fontSize, height: 1.8, color: AppTheme.getDetailTextPrimary(context)),
                          null,
                        ),
                      ),
                    ],
                  )
                : _buildBlockImage(block.imageUrl!),
          );
          children.add(imageBlock);
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildBlockImage(String imageUrl) {
    if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://') && !imageUrl.startsWith('//')) {
      if (_existingMediaFiles.contains(imageUrl)) {
        return GestureDetector(
          onTap: () => _openImageViewer(imageUrl),
          child: Image.file(
            File(imageUrl),
            key: ValueKey('img_${_imageVersion}_$imageUrl'),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    final url = imageUrl.startsWith('//') ? 'https:$imageUrl' : imageUrl;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, __) => const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, __, ___) => const SizedBox.shrink(),
      httpHeaders: const {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.dlsite.com/',
      },
    );
  }

  void _openImageViewer(String imagePath) {
    final allImages = _currentGame.images;
    // 查找点击的图片在所有图片中的索引
    int initialIndex = allImages.indexWhere((img) => img.imagePath == imagePath);
    if (initialIndex < 0) {
      // 如果找不到，创建一个临时列表
      final image = GameImage(gameId: _currentGame.id ?? 0, imagePath: imagePath);
      setState(() => _isImageViewerOpen = true);
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: AppTheme.getOverlayColor(context),
        builder: (dialogContext) => _ImageViewerDialog(
          images: [image],
          initialIndex: 0,
          onClose: () {
            setState(() => _isImageViewerOpen = false);
          },
        ),
      ).then((_) {
        if (mounted) setState(() => _isImageViewerOpen = false);
      });
      return;
    }
    setState(() => _isImageViewerOpen = true);
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppTheme.getOverlayColor(context),
      builder: (dialogContext) => _ImageViewerDialog(
        images: allImages,
        initialIndex: initialIndex,
        onClose: () {
          setState(() => _isImageViewerOpen = false);
        },
      ),
    ).then((_) {
      if (mounted) setState(() => _isImageViewerOpen = false);
    });
  }

  List<GameImage> _getUnusedImages(List<GameImage> allImages) {
    final usedFileNames = <String>{};
    
    // 从 intro 文本中提取 [图片:path] 标记的文件名
    final intro = _currentGame.intro ?? '';
    final imagePattern = RegExp(r'\[图片:(.+?)\]');
    for (final match in imagePattern.allMatches(intro)) {
      final path = match.group(1) ?? '';
      if (path.isNotEmpty) {
        final fileName = path.split(Platform.pathSeparator).last;
        final baseName = fileName.split('.').first;
        usedFileNames.add(baseName);
      }
    }
    
    // 从 intro_html 中提取 img src 属性
    if (_introHtml != null && _introHtml!.isNotEmpty) {
      final srcPattern = RegExp(r'src="([^"]+)"');
      for (final match in srcPattern.allMatches(_introHtml!)) {
        final src = match.group(1) ?? '';
        if (src.isNotEmpty && !src.startsWith('http')) {
          final fileName = src.split(Platform.pathSeparator).last;
          final baseName = fileName.split('.').first;
          usedFileNames.add(baseName);
        }
      }
    }
    
    // 过滤掉已在 intro 中使用的图片
    return allImages.where((img) {
      final fileName = img.imagePath.split(Platform.pathSeparator).last;
      final baseName = fileName.split('.').first;
      return !usedFileNames.contains(baseName);
    }).toList();
  }

  Widget _buildMergedSelectableText(
    List<String> lines,
    int startLineIndex,
    String? sectionKey,
    double fontSize,
    bool Function(int lineIdx) isHeading,
  ) {
    final spans = <InlineSpan>[];
    for (var j = 0; j < lines.length; j++) {
      final lineIdx = startLineIndex + j;
      final line = lines[j];
      final h = isHeading(lineIdx);
      final baseStyle = h
          ? TextStyle(fontSize: fontSize + 1, fontWeight: FontWeight.w700, color: AppTheme.getDetailTextPrimary(context))
          : TextStyle(fontSize: fontSize, height: 1.8, color: AppTheme.getDetailTextPrimary(context));
      if (sectionKey != null && _searchMatches.isNotEmpty) {
        final sectionMatches = _searchMatches.where((m) => m.sectionKey == sectionKey && m.lineIndex == lineIdx).toList();
        if (sectionMatches.isNotEmpty) {
          spans.addAll(_buildHighlightedSpans(line, sectionMatches, baseStyle));
        } else {
          spans.add(TextSpan(text: j < lines.length - 1 ? '$line\n' : line, style: baseStyle));
        }
      } else {
        spans.add(TextSpan(text: j < lines.length - 1 ? '$line\n' : line, style: baseStyle));
      }
      if (sectionKey != null) {
        final key = GlobalKey();
        _contentBlockKeys['${sectionKey}_$lineIdx'] = key;
        spans.add(WidgetSpan(
          child: SizedBox(key: key, width: 1, height: fontSize),
          alignment: PlaceholderAlignment.middle,
        ));
      }
    }
    return SelectableText.rich(
      TextSpan(children: spans),
      style: TextStyle(fontSize: fontSize, height: 1.8),
    );
  }

  List<TextSpan> _buildHighlightedSpans(String line, List<ContentSearchMatch> matches, TextStyle baseStyle) {
    final spans = <TextSpan>[];
    final sortedMatches = List<ContentSearchMatch>.from(matches)
      ..sort((a, b) => a.charOffset.compareTo(b.charOffset));
    var pos = 0;
    for (final match in sortedMatches) {
      if (match.charOffset > pos) {
        spans.add(TextSpan(text: line.substring(pos, match.charOffset), style: baseStyle));
      }
      final isCurrent = match == _searchMatches[_currentMatchIndex];
      spans.add(TextSpan(
        text: line.substring(match.charOffset, match.charOffset + match.matchLength),
        style: baseStyle.copyWith(
          backgroundColor: isCurrent
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : Colors.yellow.withValues(alpha: 0.4),
        ),
      ));
      pos = match.charOffset + match.matchLength;
    }
    if (pos < line.length) {
      spans.add(TextSpan(text: line.substring(pos), style: baseStyle));
    }
    return spans;
  }

  Widget _buildRichIntro(String content, double fontSize, {String? sectionKey}) {
    final imageTagStart = '[图片:';
    final videoTagStart = '[视频:';
    final tagEnd = ']';
    
    if (!content.contains(imageTagStart) && !content.contains(videoTagStart)) {
      final lines = content.split('\n');
      final merged = <String>[];
      for (var i = 0; i < lines.length; i++) {
        merged.add(lines[i].trimRight());
      }
      return _buildMergedSelectableText(
        merged, 0, sectionKey, fontSize,
        (lineIdx) => RegExp(r'^.{1,6}[：:]\s*$').hasMatch(lines[lineIdx].trimRight()),
      );
    }

    final widgets = <Widget>[];
    final lines = content.split('\n');
    
    // 收集内容中所有图片路径
    final contentImages = <String>[];
    for (final line in lines) {
      if (line.startsWith(imageTagStart) && line.endsWith(tagEnd)) {
        final imagePath = line.substring(imageTagStart.length, line.length - tagEnd.length);
        if (_existingMediaFiles.contains(imagePath)) {
          contentImages.add(imagePath);
        }
      }
    }
    
    // 收集连续文本行并分组处理
    var textGroupStart = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.startsWith(imageTagStart) && line.endsWith(tagEnd)) {
        // Flush pending text group
        if (textGroupStart >= 0) {
          final groupLines = <String>[];
          for (var j = textGroupStart; j < i; j++) {
            groupLines.add(lines[j].trimRight());
          }
          widgets.add(_buildMergedSelectableText(
            groupLines, textGroupStart, sectionKey, fontSize,
            (lineIdx) => RegExp(r'^.{1,6}[：:]\s*$').hasMatch(lines[lineIdx].trimRight()),
          ));
          textGroupStart = -1;
        }
        final imagePath = line.substring(imageTagStart.length, line.length - tagEnd.length);
        if (_existingMediaFiles.contains(imagePath)) {
          final imageIndex = contentImages.indexOf(imagePath);
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: GestureDetector(
                onTap: () => _openImageViewerFromList(contentImages, imageIndex >= 0 ? imageIndex : 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Image.file(
                      File(imagePath),
                      key: ValueKey('img_${_imageVersion}_$imagePath'),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      } else if (line.startsWith(videoTagStart) && line.endsWith(tagEnd)) {
        // Flush pending text group
        if (textGroupStart >= 0) {
          final groupLines = <String>[];
          for (var j = textGroupStart; j < i; j++) {
            groupLines.add(lines[j].trimRight());
          }
          widgets.add(_buildMergedSelectableText(
            groupLines, textGroupStart, sectionKey, fontSize,
            (lineIdx) => RegExp(r'^.{1,6}[：:]\s*$').hasMatch(lines[lineIdx].trimRight()),
          ));
          textGroupStart = -1;
        }
        final videoPath = line.substring(videoTagStart.length, line.length - tagEnd.length);
        if (_existingMediaFiles.contains(videoPath)) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _InlineVideoPlayer(videoPath: videoPath, cached: _getOrCreatePlayer(videoPath)),
            ),
          );
        }
      } else {
        if (textGroupStart < 0) textGroupStart = i;
      }
    }
    // Flush remaining text group
    if (textGroupStart >= 0) {
      final groupLines = <String>[];
      for (var j = textGroupStart; j < lines.length; j++) {
        groupLines.add(lines[j].trimRight());
      }
      widgets.add(_buildMergedSelectableText(
        groupLines, textGroupStart, sectionKey, fontSize,
        (lineIdx) => RegExp(r'^.{1,6}[：:]\s*$').hasMatch(lines[lineIdx].trimRight()),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  void _openImageViewerFromList(List<String> imagePaths, int initialIndex) {
    setState(() => _isImageViewerOpen = true);
    final images = imagePaths.map((p) => GameImage(gameId: _currentGame.id ?? 0, imagePath: p)).toList();
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppTheme.getOverlayColor(context),
      builder: (dialogContext) => _ImageViewerDialog(
        images: images,
        initialIndex: initialIndex,
        onClose: () {
          setState(() => _isImageViewerOpen = false);
        },
      ),
    ).then((_) {
      if (mounted) setState(() => _isImageViewerOpen = false);
    });
  }

  Widget _buildDownloadLinks(String downloadUrl) {
    final lines = downloadUrl.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final grouped = <String, List<String>>{};
    final decompressCodes = <String>[];

    for (final line in lines) {
      // Check for decompress code
      final decompressMatch = RegExp(r'解压(?:码|密码)[：:]?\s*(.{1,50})').firstMatch(line);
      if (decompressMatch != null) {
        final code = decompressMatch.group(1)?.trim() ?? '';
        if (code.isNotEmpty) {
          decompressCodes.add(code);
        }
        continue; // Don't add decompress code line to download links
      }

      // Check for labeled download link (e.g., "飞猫直连：https://..." or "飞猫直链① https://...")
      final labeledMatch = RegExp(r'^([^：:]+)[：:]\s*(https?://.+)').firstMatch(line.trim());
      if (labeledMatch != null) {
        final customLabel = labeledMatch.group(1)!.trim();
        final url = labeledMatch.group(2)!.trim();
        grouped.putIfAbsent(customLabel, () => []).add(url);
        continue;
      }

      final uri = RegExp(r'https?://([^/]+)').firstMatch(line);
      final domain = uri?.group(1) ?? '其他';
      final label = _getDomainLabel(domain);
      if (label == '其他') continue;
      grouped.putIfAbsent(label, () => []).add(line.trim());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Download links section
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.download, size: 15, color: AppTheme.getDetailTextPrimary(context)),
            const SizedBox(width: 8),
            Text('下载:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
          ],
        ),
        const SizedBox(height: 8),
        ...grouped.entries.map((entry) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...entry.value.map((link) {
                final urlMatch = RegExp('https?://[^\\s"\\)]+').firstMatch(link);
                final url = urlMatch?.group(0) ?? '';
                final extractCodeMatch = RegExp(r'(?:提取码|密码)[：:]\s*(\w+)').firstMatch(link);
                final extractCode = extractCodeMatch?.group(1);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      GestureDetector(
                        onDoubleTap: () {
                          Clipboard.setData(ClipboardData(text: url));
                          AppTheme.showGlassToast(context, message: '已复制链接');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.2)),
                          ),
                          child: Text(entry.key, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.getPrimaryColor(context))),
                        ),
                      ),
                      if (extractCode != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onDoubleTap: () {
                            Clipboard.setData(ClipboardData(text: extractCode));
                            AppTheme.showGlassToast(context, message: '已复制提取码');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                            ),
                            child: const Text('提取码', style: TextStyle(fontSize: 11, color: Colors.orange)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),
        )),
        // Decompress code section (separate from download links)
        if (decompressCodes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.vpn_key_outlined, size: 15, color: AppTheme.getDetailTextPrimary(context)),
              const SizedBox(width: 8),
              Text('解压码:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
              const SizedBox(width: 8),
              ...decompressCodes.map((code) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onDoubleTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    AppTheme.showGlassToast(context, message: '已复制解压码');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                    ),
                    child: const Text('解压码', style: TextStyle(fontSize: 11, color: Colors.purple)),
                  ),
                ),
              )),
            ],
          ),
        ],
      ],
    );
  }

  String _getDomainLabel(String domain) {
    if (domain.contains('baidu') || domain.contains('bds')) return '百度网盘';
    if (domain.contains('xunlei')) return '迅雷网盘';
    if (domain.contains('weiyun')) return '微云网盘';
    if (domain.contains('uc.cn') || domain.contains('quark')) return 'UC网盘';
    if (domain.contains('gofile')) return 'GoFile';
    if (domain.contains('mega')) return 'Mega';
    if (domain.contains('mediafire')) return 'MediaFire';
    if (domain.contains('cm1.hk') || domain.contains('cm2.hk') || domain.contains('feimaocloud')) return '飞猫网盘';
    return domain;
  }

  Widget _buildArticleImage(GameImage image) {
    final index = _currentGame.images.indexOf(image);
    return GestureDetector(
      onTap: () => _showImageViewer(index >= 0 ? index : 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Image.file(
            File(image.imagePath!),
            key: ValueKey('img_${_imageVersion}_${image.imagePath}'),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  _CachedVideoPlayer _getOrCreatePlayer(String videoPath) {
    return _PlayerCache.getOrCreate(videoPath);
  }

  void _showImageViewer(int initialIndex) {
    setState(() => _isImageViewerOpen = true);
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: AppTheme.getOverlayColor(context),
      builder: (dialogContext) => _ImageViewerDialog(
        images: _currentGame.images,
        initialIndex: initialIndex,
        onClose: () {
          setState(() => _isImageViewerOpen = false);
        },
      ),
    ).then((_) {
      if (mounted) setState(() => _isImageViewerOpen = false);
    });
  }

  Widget _buildImageGallery(List<GameImage> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_library_outlined, size: 18, color: AppTheme.getPrimaryColor(context)),
            const SizedBox(width: 8),
            Text('更多图片', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.getDetailTextPrimary(context))),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: images.map((img) => _buildArticleImage(img)).toList(),
        ),
      ],
    );
  }

  Widget _buildAllImagesGallery(List<GameImage> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_library, size: 18, color: AppTheme.getPrimaryColor(context)),
            const SizedBox(width: 8),
            Text('全部图片 (${images.length})', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.getDetailTextPrimary(context))),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: images.map((img) => _buildArticleImage(img)).toList(),
        ),
      ],
    );
  }

  Widget _buildEditBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.05),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _isEditing = false),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('取消'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.getDetailTextPrimary(context)),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _saveChanges,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('保存修改'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.getPrimaryColor(context),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  String _syncIntroToHtml(String oldIntro, String newIntro, String html) {
    final oldLines = oldIntro.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final newLines = newIntro.split('\n').where((l) => l.trim().isNotEmpty).toList();
    
    var result = html;
    
    for (int i = 0; i < oldLines.length && i < newLines.length; i++) {
      final oldLine = oldLines[i].trim();
      final newLine = newLines[i].trim();
      if (oldLine != newLine && oldLine.isNotEmpty) {
        result = result.replaceAll(oldLine, newLine);
      }
    }
    
    return result;
  }

  Future<void> _saveChanges() async {
    try {
      final repo = ref.read(gameRepositoryProvider);
      final tagRepo = ref.read(tagRepositoryProvider);
      final gameId = _currentGame.id;

      final newTitle = _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
      final newVersion = _versionController.text.trim().isEmpty ? null : _versionController.text.trim();
      final newIntro = _introController.text.trim().isEmpty ? null : _introController.text.trim();
      final newFeatures = _featuresController.text.trim().isEmpty ? null : _featuresController.text.trim();
      final newChangelog = _changelogController.text.trim().isEmpty ? null : _changelogController.text.trim();
      final newGuide = _guideController.text.trim().isEmpty ? null : _guideController.text.trim();
      final newDownloadUrl = _downloadUrlController.text.trim().isEmpty ? null : _downloadUrlController.text.trim();
      final newSourceUrl = _sourceUrlController.text.trim().isEmpty ? null : _sourceUrlController.text.trim();
      final launcherText = _gameLauncherController.text.trim();

      // Handle backup folder rename when title changes
      final titleChanged = newTitle != null && newTitle != _currentGame.title;
      final sep = Platform.pathSeparator;
      final isInCleared = _currentGame.path.contains('${sep}Cleared$sep');
      // 检查是否在 cleared_paths 目录下
      bool isInNewClearedPath = false;
      final prefs0 = ref.read(sharedPreferencesProvider);
      final rawCleared0 = prefs0.getString('cleared_paths') ?? '';
      if (rawCleared0.startsWith('{')) {
        try {
          final decodedCleared0 = jsonDecode(rawCleared0) as Map<String, dynamic>;
          final normalizedGamePath0 = _currentGame.path.replaceAll('\\', '/').toLowerCase();
          for (final v in decodedCleared0.values) {
            final cp = v?.toString() ?? '';
            if (cp.isNotEmpty) {
              final normalizedCleared = cp.replaceAll('\\', '/').toLowerCase();
              if (normalizedGamePath0.startsWith(normalizedCleared)) {
                isInNewClearedPath = true;
                break;
              }
            }
          }
        } catch (_) {}
      }
      final isBackupGame = _currentGame.path.contains('${sep}Cleared${sep}Backup${sep}') ||
                          !await Directory(_currentGame.path).exists();
      if (titleChanged && (isInCleared || isInNewClearedPath) && gameId != null) {
        final prefs = ref.read(sharedPreferencesProvider);
        // 读取所有整理目录
        final sortedPathList = <String>[];
        final rawSorted = prefs.getString('sorted_paths') ?? '';
        if (rawSorted.startsWith('{')) {
          try {
            final decoded = jsonDecode(rawSorted) as Map<String, dynamic>;
            for (final v in decoded.values) {
              final sp = v?.toString() ?? '';
              if (sp.isNotEmpty) sortedPathList.add(sp);
            }
          } catch (e) {
            debugPrint('[GameDetail] 解析整理目录配置失败: $e');
          }
        }
        if (sortedPathList.isEmpty) {
          final oldSorted = prefs.getString('sorted_path') ?? '';
          if (oldSorted.isNotEmpty) sortedPathList.add(oldSorted);
        }

        for (final sortedPath in sortedPathList) {
          final sep = Platform.pathSeparator;
          final backupDirPath = '$sortedPath${sep}Cleared${sep}Backup';
          final backupDir = Directory(backupDirPath);
          
          if (await backupDir.exists()) {
            // 找到实际的备份目录（通过遍历 Backup 目录查找匹配的文件夹）
            String? actualBackupPath;
            await for (final entity in backupDir.list()) {
              if (entity is Directory) {
                // 检查这个备份目录是否与当前游戏匹配（通过 metadata.json 中的标题）
                final metadataFile = File('${entity.path}${sep}metadata.json');
                if (await metadataFile.exists()) {
                  try {
                    final content = await metadataFile.readAsString();
                    final metadata = jsonDecode(content) as Map<String, dynamic>;
                    final backupTitle = metadata['title'] as String?;
                    if (backupTitle == _currentGame.title) {
                      actualBackupPath = entity.path;
                      break;
                    }
                  } catch (e) {
                    // ignore
                  }
                }
              }
            }
            
            if (actualBackupPath != null) {
              final oldSanitizedTitle = actualBackupPath.split(Platform.pathSeparator).last;
              final newSanitizedTitle = newTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
              final oldBackupDir = Directory(actualBackupPath);
              final newBackupDir = Directory('$backupDirPath$sep$newSanitizedTitle');
              if (oldSanitizedTitle != newSanitizedTitle) {
                if (!await newBackupDir.exists()) {
                  await oldBackupDir.rename(newBackupDir.path);
                  // Update path in database
                  await repo.updateGamePath(gameId, newBackupDir.path);
                  // Update image paths in database
                  await repo.updateImagePaths(gameId, oldBackupDir.path, newBackupDir.path);
                  // Update current game object for subsequent operations
                  _currentGame = _currentGame.copyWith(path: newBackupDir.path);
                }
              }
            }
          }
        }

        // 也检查 cleared_paths 的备份目录
        final rawCleared2 = prefs.getString('cleared_paths') ?? '';
        if (rawCleared2.startsWith('{')) {
          try {
            final decodedCleared2 = jsonDecode(rawCleared2) as Map<String, dynamic>;
            for (final v in decodedCleared2.values) {
              final cp = v?.toString() ?? '';
              if (cp.isEmpty) continue;
              final backupDirPath2 = '$cp${sep}Backup';
              final backupDir2 = Directory(backupDirPath2);
              if (!await backupDir2.exists()) continue;

              String? actualBackupPath2;
              await for (final entity in backupDir2.list()) {
                if (entity is Directory) {
                  final metadataFile = File('${entity.path}${sep}metadata.json');
                  if (await metadataFile.exists()) {
                    try {
                      final content = await metadataFile.readAsString();
                      final metadata = jsonDecode(content) as Map<String, dynamic>;
                      final backupTitle = metadata['title'] as String?;
                      if (backupTitle == _currentGame.title) {
                        actualBackupPath2 = entity.path;
                        break;
                      }
                    } catch (_) {}
                  }
                }
              }

              if (actualBackupPath2 != null) {
                final oldSanitizedTitle2 = actualBackupPath2.split(Platform.pathSeparator).last;
                final newSanitizedTitle2 = newTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
                final oldBackupDir2 = Directory(actualBackupPath2);
                final newBackupDir2 = Directory('$backupDirPath2$sep$newSanitizedTitle2');
                if (oldSanitizedTitle2 != newSanitizedTitle2) {
                  if (!await newBackupDir2.exists()) {
                    await oldBackupDir2.rename(newBackupDir2.path);
                    await repo.updateGamePath(gameId, newBackupDir2.path);
                    await repo.updateImagePaths(gameId, oldBackupDir2.path, newBackupDir2.path);
                    _currentGame = _currentGame.copyWith(path: newBackupDir2.path);
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('[GameDetail] 解析通关目录配置失败: $e');
          }
        }
      }

      // Handle non-backup Cleared game: rename the corresponding backup folder
      if (!isBackupGame && titleChanged) {
        final prefs2 = ref.read(sharedPreferencesProvider);
        final sortedPathList2 = <String>[];
        final rawSorted2 = prefs2.getString('sorted_paths') ?? '';
        if (rawSorted2.startsWith('{')) {
          try {
            final decoded2 = jsonDecode(rawSorted2) as Map<String, dynamic>;
            for (final v in decoded2.values) {
              final sp = v?.toString() ?? '';
              if (sp.isNotEmpty) sortedPathList2.add(sp);
            }
          } catch (_) {}
        }
        if (sortedPathList2.isEmpty) {
          final oldSorted2 = prefs2.getString('sorted_path') ?? '';
          if (oldSorted2.isNotEmpty) sortedPathList2.add(oldSorted2);
        }

        for (final sp2 in sortedPathList2) {
          final backupDirPath = '$sp2${sep}Cleared${sep}Backup';
          final backupDir = Directory(backupDirPath);
          if (!await backupDir.exists()) continue;

          final oldBackupName = await FolderRenameService.buildBackupFolderName(_currentGame);
          if (oldBackupName == null) continue;
          final oldSanitized = oldBackupName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          final oldBackupDir = Directory('$backupDirPath$sep$oldSanitized');

          if (await oldBackupDir.exists()) {
            final newBackupName = await FolderRenameService.buildBackupFolderName(
              _currentGame.copyWith(title: newTitle),
            );
            if (newBackupName == null) continue;
            final newSanitized = newBackupName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
            if (oldSanitized == newSanitized) continue;

            final newBackupDir = Directory('$backupDirPath$sep$newSanitized');
            if (await newBackupDir.exists()) continue;

            await oldBackupDir.rename(newBackupDir.path);
            final allGames = await repo.getAllGames();
            for (final g in allGames) {
              final normalizedGPath = g.path.replaceAll('\\', '/');
              final normalizedOldPath = oldBackupDir.path.replaceAll('\\', '/');
              if (normalizedGPath == normalizedOldPath && g.id != null) {
                await repo.updateGamePath(g.id!, newBackupDir.path);
                await repo.updateImagePaths(g.id!, oldBackupDir.path, newBackupDir.path);
                break;
              }
            }
            debugPrint('[Edit] Backup folder renamed: $oldSanitized -> $newSanitized');
          }
        }

        // 也检查 cleared_paths 的备份目录
        final rawCleared3 = prefs2.getString('cleared_paths') ?? '';
        if (rawCleared3.startsWith('{')) {
          try {
            final decodedCleared3 = jsonDecode(rawCleared3) as Map<String, dynamic>;
            for (final v in decodedCleared3.values) {
              final cp = v?.toString() ?? '';
              if (cp.isEmpty) continue;
              final backupDirPath3 = '$cp${sep}Backup';
              final backupDir3 = Directory(backupDirPath3);
              if (!await backupDir3.exists()) continue;

              final oldBackupName3 = await FolderRenameService.buildBackupFolderName(_currentGame);
              if (oldBackupName3 == null) continue;
              final oldSanitized3 = oldBackupName3.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
              final oldBackupDir3 = Directory('$backupDirPath3$sep$oldSanitized3');

              if (await oldBackupDir3.exists()) {
                final newBackupName3 = await FolderRenameService.buildBackupFolderName(
                  _currentGame.copyWith(title: newTitle),
                );
                if (newBackupName3 == null) continue;
                final newSanitized3 = newBackupName3.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
                if (oldSanitized3 == newSanitized3) continue;

                final newBackupDir3 = Directory('$backupDirPath3$sep$newSanitized3');
                if (await newBackupDir3.exists()) continue;

                await oldBackupDir3.rename(newBackupDir3.path);
                final allGames3 = await repo.getAllGames();
                for (final g in allGames3) {
                  final normalizedGPath = g.path.replaceAll('\\', '/');
                  final normalizedOldPath = oldBackupDir3.path.replaceAll('\\', '/');
                  if (normalizedGPath == normalizedOldPath && g.id != null) {
                    await repo.updateGamePath(g.id!, newBackupDir3.path);
                    await repo.updateImagePaths(g.id!, oldBackupDir3.path, newBackupDir3.path);
                    break;
                  }
                }
                debugPrint('[Edit] Backup folder renamed (cleared): $oldSanitized3 -> $newSanitized3');
              }
            }
          } catch (e) {
            debugPrint('[GameDetail] 解析通关目录配置失败: $e');
          }
        }
      }

      // Handle path change
      final newPath = _pathController.text.trim();
      if (_pathChanged && newPath.isNotEmpty && newPath != _currentGame.path) {
        final pathConfirm = await showGlassDialog<bool>(
          context: context,
          child: SizedBox(
            width: GlassConstants.dialogWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('确认修改路径', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context))),
                  const SizedBox(height: 16),
                  Text('原路径: ${_currentGame.path}', style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 13)),
                  const SizedBox(height: 8),
                  Text('新路径: $newPath', style: TextStyle(color: AppTheme.getDetailTextPrimary(context), fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Text('将移动文件夹到新路径并更新数据库记录。', style: TextStyle(color: AppTheme.getTextSecondary(context))),
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
                          backgroundColor: AppTheme.getPrimaryColor(context),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('确认修改'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        if (pathConfirm == true) {
          try {
            final moveService = ref.read(gameMoveServiceProvider);
            await moveService.moveGameFolderCrossDrive(
              gameId: _currentGame.id!,
              oldPath: _currentGame.path,
              newPath: newPath,
            );
            final refreshed = await repo.getGameById(_currentGame.id!);
            if (refreshed != null) {
              _currentGame = refreshed;
              _pathController.text = refreshed.path;
            }
          } catch (e) {
            if (mounted) {
              AppTheme.showGlassToast(context, message: '路径修改失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
              return;
            }
          }
        } else {
          _pathController.text = _currentGame.path;
          _pathChanged = false;
          return;
        }
      }
      _pathChanged = false;

      await repo.updateGame(_currentGame.copyWith(
        title: newTitle,
        version: newVersion,
        intro: newIntro,
        features: newFeatures,
        changelog: newChangelog,
        guide: newGuide,
        downloadUrl: newDownloadUrl,
        sourceUrl: newSourceUrl,
        gameLauncher: launcherText.isNotEmpty ? launcherText : null,
        launcherLocked: launcherText.isNotEmpty ? true : _currentGame.launcherLocked,
        tags: _editedTags,
      ));

      // Update tag relations if game has an id
      if (gameId != null) {
        final existingTags = _currentGame.tags;
        for (final tag in existingTags) {
          if (tag.id != null) {
            await repo.removeTagFromGame(gameId, tag.id!);
          }
        }
        for (final tag in _editedTags) {
          final tagId = await tagRepo.insertOrGetTag(tag.name, tag.type);
          await repo.addTagToGame(gameId, tagId);
        }
      }

      // Sync metadata.json
      try {
        final metadataFile = File('${_currentGame.path}${Platform.pathSeparator}metadata.json');
        Map<String, dynamic> metadata;
        
        if (await metadataFile.exists()) {
          final content = await metadataFile.readAsString();
          metadata = jsonDecode(content) as Map<String, dynamic>;
        } else {
          metadata = <String, dynamic>{};
        }
        
        if (newTitle != null) metadata['title'] = newTitle;
        if (newVersion != null) metadata['version'] = newVersion;
        if (newIntro != null) {
          metadata['intro'] = newIntro;
          if (_introHtml != null && _introHtml!.isNotEmpty) {
            final oldIntro = _currentGame.intro ?? '';
            if (oldIntro != newIntro) {
              _introHtml = _syncIntroToHtml(oldIntro, newIntro, _introHtml!);
              metadata['intro_html'] = _introHtml;
            }
          }
        }
        if (newFeatures != null) metadata['features'] = newFeatures;
        if (newChangelog != null) metadata['changelog'] = newChangelog;
        if (newGuide != null) metadata['guide'] = newGuide;
        if (newDownloadUrl != null) metadata['download_url'] = newDownloadUrl;
        if (newSourceUrl != null) metadata['source_url'] = newSourceUrl;
        
        await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
        debugPrint('[Edit] metadata.json updated for: ${_currentGame.path}');
      } catch (e) {
        debugPrint('[Edit] Failed to update metadata.json: $e');
      }

      // Sync source_url.txt
      if (newSourceUrl != null) {
        try {
          final sourceUrlFile = File('${_currentGame.path}${Platform.pathSeparator}source_url.txt');
          await sourceUrlFile.writeAsString(newSourceUrl, flush: true);
          debugPrint('[Edit] source_url.txt updated: $newSourceUrl');
        } catch (e) {
          debugPrint('[Edit] Failed to update source_url.txt: $e');
        }
      }

      if (mounted) {
        _refreshAllProviders();
      }

      // 更新本地状态以实现实时刷新
      final freshGame = await repo.getGameById(gameId!);
      if (freshGame != null && mounted) {
        setState(() {
          _currentGame = freshGame;
          _isEditing = false;
          _titleController.text = freshGame.title ?? '';
          _versionController.text = freshGame.version ?? '';
          _introController.text = freshGame.intro ?? '';
          _featuresController.text = freshGame.features ?? '';
          _changelogController.text = freshGame.changelog ?? '';
          _downloadUrlController.text = freshGame.downloadUrl ?? '';
          _sourceUrlController.text = freshGame.sourceUrl ?? '';
          _gameLauncherController.text = freshGame.gameLauncher ?? '';
          _pathController.text = freshGame.path;
          _editedTags = List.from(freshGame.tags);
          _guideController.text = freshGame.guide ?? '';
        });

        await _loadMetadataHtml();

        if (newSourceUrl != null && newSourceUrl != _currentGame.sourceUrl) {
          final shouldRescrape = await showGlassDialog<bool>(
            context: context,
            child: SizedBox(
              width: GlassConstants.dialogWidth,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('重新刮削', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context))),
                    const SizedBox(height: 12),
                    Text('来源链接已修改，是否立即重新刮削该游戏？', style: TextStyle(color: AppTheme.getTextSecondary(context))),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('稍后手动刮削'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.getPrimaryColor(context),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('立即刮削'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );

          if (shouldRescrape == true && mounted) {
            Navigator.of(context).pop();
            AppTheme.showGlassToast(context, message: '请在刮削页面点击"扫描游戏库"后刮削该游戏');
            return;
          }
        }

        AppTheme.showGlassToast(context, message: '保存成功');
      } else if (mounted) {
        setState(() => _isEditing = false);
        AppTheme.showGlassToast(context, message: '保存成功');
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '保存失败: $e');
      }
    }
  }

  Future<void> _launchExe(String exePath, String gamePath) async {
    // 工作目录应该是 exe 文件所在的文件夹
    final exeDir = File(exePath).parent.path;
    try {
      await Process.run(exePath, [], workingDirectory: exeDir);
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> _launchGame(Game game) async {
    final repo = ref.read(gameRepositoryProvider);

    if (game.launcherLocked && game.gameLauncher != null && game.gameLauncher!.isNotEmpty) {
      final file = File(game.gameLauncher!);
      if (await file.exists()) {
        try {
          await _launchExe(game.gameLauncher!, game.path);
          return true;
        } catch (e) {
          if (mounted) {
            AppTheme.showGlassToast(context, message: '启动失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
          }
          return true;
        }
      }
    }

    final gameDir = Directory(game.path);
    if (!await gameDir.exists()) return false;

    final toolBat = File('${game.path}${Platform.pathSeparator}与工具一同启动.bat');
    if (await toolBat.exists()) {
      await repo.updateGame(game.copyWith(gameLauncher: toolBat.path));
      try {
        await _launchExe(toolBat.path, game.path);
        return true;
      } catch (e) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '启动失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return true;
      }
    }

    await for (final entity in gameDir.list()) {
      if (entity is File) {
        final fileName = entity.path.split(RegExp(r'[/\\]')).last.toLowerCase();
        if (fileName.endsWith('.bat') && (fileName.contains('启动') || fileName.contains('开始'))) {
          await repo.updateGame(game.copyWith(gameLauncher: entity.path));
          try {
            await _launchExe(entity.path, game.path);
            return true;
          } catch (e) {
            if (mounted) {
              AppTheme.showGlassToast(context, message: '启动失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
            }
            return true;
          }
        }
      }
    }

    final fallbackExes = ['game.exe', 'Game.exe', 'launcher.exe', 'launch.exe', 'player.exe', 'play.exe'];
    for (final exeName in fallbackExes) {
      final exeFile = File('${game.path}${Platform.pathSeparator}$exeName');
      if (await exeFile.exists()) {
        await repo.updateGame(game.copyWith(gameLauncher: exeFile.path));
        try {
          await _launchExe(exeFile.path, game.path);
          return true;
        } catch (e) {
          if (mounted) {
            AppTheme.showGlassToast(context, message: '启动失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
          }
          return true;
        }
      }
    }

    final saveService = ref.read(savePathServiceProvider);
    final exePath = await saveService.findGameExe(game.path);
    if (exePath != null) {
      await repo.updateGame(game.copyWith(gameLauncher: exePath));
      try {
        await _launchExe(exePath, game.path);
        return true;
      } catch (e) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '启动失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return true;
      }
    }

    return false;
  }

  void _openSaveLocation() async {
    // 如果未设置存档路径，先提示用户设置
    if (_currentGame.savePath == null || _currentGame.savePath!.isEmpty) {
      _showEditSavePathDialog();
      return;
    }

    // 打开存档管理对话框
    showDialog(
      context: context,
      builder: (ctx) => SaveManagementDialog(game: _currentGame),
    );
  }

  void _showEditSavePathDialog() {
    showGlassDialog(
      context: context,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          final controller = TextEditingController(text: _currentGame.savePath ?? '');
          return SizedBox(
            width: GlassConstants.dialogWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('编辑存档路径', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context))),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: '输入存档文件夹路径',
                      labelText: '存档路径',
                    ),
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
                          final newPath = controller.text.trim();
                          controller.dispose();
                          final repo = ref.read(gameRepositoryProvider);
                          var gameId = _currentGame.id;
                          if (gameId == null) {
                            gameId = await repo.insertGame(_currentGame);
                            _currentGame = _currentGame.copyWith(id: gameId);
                          }
                          await repo.updateSavePath(gameId, newPath.isEmpty ? null : newPath);
                          final freshGame = await repo.getGameById(gameId);
                          if (freshGame != null && mounted) {
                            setState(() => _currentGame = freshGame);
                          }
                          if (mounted) {
                            _refreshAllProviders();
                            Navigator.pop(context);
                            AppTheme.showGlassToast(context, message: '存档路径已更新');
                          }
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

  void _showEditPlayDurationDialog() {
    showGlassDialog(
      context: context,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          final hoursController = TextEditingController(
            text: (_currentGame.playDuration ~/ 3600).toString(),
          );
          final minutesController = TextEditingController(
            text: ((_currentGame.playDuration % 3600) ~/ 60).toString(),
          );
          return SizedBox(
            width: GlassConstants.dialogWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('编辑游玩时长', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context))),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hoursController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '小时',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: minutesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '分钟',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          hoursController.dispose();
                          minutesController.dispose();
                          Navigator.pop(context);
                        },
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final hours = int.tryParse(hoursController.text) ?? 0;
                          final minutes = int.tryParse(minutesController.text) ?? 0;
                          hoursController.dispose();
                          minutesController.dispose();
                          final totalSeconds = hours * 3600 + minutes * 60;

                          final repo = ref.read(gameRepositoryProvider);
                          var gameId = _currentGame.id;
                          if (gameId == null) {
                            gameId = await repo.insertGame(_currentGame);
                            _currentGame = _currentGame.copyWith(id: gameId);
                          }
                          await repo.updateGame(_currentGame.copyWith(playDuration: totalSeconds));
                          final freshGame = await repo.getGameById(gameId);
                          if (freshGame != null && mounted) {
                            setState(() => _currentGame = freshGame);
                          }
                          if (mounted) {
                            _refreshAllProviders();
                            Navigator.pop(context);
                            AppTheme.showGlassToast(context, message: '游玩时长已更新');
                          }
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

  Future<void> _checkForUpdate() async {
    if (_currentGame.title == null || _currentGame.title!.isEmpty) {
      AppTheme.showGlassToast(context, message: '游戏标题为空，无法检查更新');
      return;
    }

    setState(() => _isCheckingUpdate = true);
    AppTheme.showGlassToast(context, message: '正在检查更新...', icon: Icons.system_update, iconColor: AppTheme.getPrimaryColor(context));

    try {
      final service = VersionCheckService();
      final result = await service.checkForUpdate(
        _currentGame.title!,
        _currentGame.version ?? '',
      );

      if (!mounted) return;

      setState(() => _isCheckingUpdate = false);

      if (result != null) {
        _showUpdateDialog(result);
      } else {
        AppTheme.showGlassToast(context, message: '未发现新版本');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        AppTheme.showGlassToast(context, message: '检查更新失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    }
  }

  Future<void> _rescrapeGame() async {
    if (_currentGame.sourceUrl == null || _currentGame.sourceUrl!.isEmpty) return;
    setState(() => _isRescraping = true);
    AppTheme.showGlassToast(context, message: '刮削等待时间可能较长，请勿关闭当前窗口', duration: const Duration(seconds: 5));
    try {
      final sourceUrl = _currentGame.sourceUrl!;
      final isDlsite = sourceUrl.contains('dlsite');
      final isSteam = sourceUrl.contains('steam');
      GameInfo? gameInfo;

      if (isDlsite) {
        final dlsiteService = ref.read(dlsiteServiceProvider);
        final id = dlsiteService.normalizeId(sourceUrl);
        if (id != null) {
          gameInfo = await dlsiteService.fetchById(id);
        }
      } else if (isSteam) {
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
              maker: steamInfo.developers.isNotEmpty ? steamInfo.developers.join(', ') : null,
            );
          }
        }
      } else {
        final scraper = HtmlScraper();
        await scraper.ensureLoaded();
        final headers = await buildScrapeHeaders(sourceUrl);
        final client = await createProxyClientFromPrefs(domain: Uri.parse(sourceUrl).host);
        http.Response response;
        try {
          response = await httpGetWithRetry(Uri.parse(sourceUrl), headers: headers, client: client);
        } finally {
          client.close();
        }
        if (response.statusCode == 200) {
          gameInfo = scraper.scrapeGameInfo(response.body, sourceUrl);
        } else {
          if (mounted) {
            AppTheme.showGlassToast(context, message: '请求失败: HTTP ${response.statusCode}', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
          }
        }
      }

      if (gameInfo != null) {
        final repo = ref.read(gameRepositoryProvider);
        final tagRepo = ref.read(tagRepositoryProvider);
        final displayTitle = gameInfo.title != null ? _stripVersionFromTitle(gameInfo.title!, gameInfo.version) : null;
        var updated = _currentGame.copyWith(
          title: displayTitle ?? _currentGame.title,
          version: gameInfo.version ?? _currentGame.version,
          intro: gameInfo.description ?? _currentGame.intro,
          features: gameInfo.features.isNotEmpty ? gameInfo.features.join('\n') : _currentGame.features,
          changelog: gameInfo.changelog ?? _currentGame.changelog,
          downloadUrl: gameInfo.downloadUrl.isNotEmpty ? gameInfo.downloadUrl : _currentGame.downloadUrl,
          maker: gameInfo.maker ?? _currentGame.maker,
          makerUrl: gameInfo.makerUrl ?? _currentGame.makerUrl,
        );

        final metadataFile = File('${_currentGame.path}${Platform.pathSeparator}metadata.json');
        await metadataFile.writeAsString(jsonEncode(gameInfo.toJson()), flush: true);
        await repo.updateGame(updated);

        if (gameInfo.maker != null && gameInfo.maker!.isNotEmpty) {
          final makerTagId = await tagRepo.insertOrGetTag(gameInfo.maker!, Tag.typeCustom);
          await repo.addTagToGame(_currentGame.id!, makerTagId);
        }
        for (final tagName in gameInfo.tags) {
          final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
          await repo.addTagToGame(_currentGame.id!, tagId);
        }
        if (gameInfo.category != null) {
          final tagId = await tagRepo.insertOrGetTag(gameInfo.category!, Tag.typeSeries);
          await repo.addTagToGame(_currentGame.id!, tagId);
        }

        final allTags = await tagRepo.getAllTags();
        final gameTagNames = [...gameInfo.tags, if (gameInfo.category != null) gameInfo.category!];
        for (final existingTag in allTags) {
          if (existingTag.type == Tag.typeSeries) {
            final shouldAssociate = gameTagNames.any((name) =>
                name.toUpperCase().contains(existingTag.name.toUpperCase()) &&
                name.toUpperCase() != existingTag.name.toUpperCase());
            if (shouldAssociate) {
              await repo.addTagToGame(_currentGame.id!, existingTag.id!);
            }
          }
        }

        if (gameInfo.screenshots.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _downloadTotal = gameInfo!.screenshots.length;
            _downloadCurrent = 0;
            _downloadProgress = 0.0;
          });
          await repo.deleteGameImagesByGameId(updated.id!);
          final urlToLocal = await _downloadImagesWithMapping(updated, gameInfo.screenshots, onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _downloadCurrent = current;
                _downloadTotal = total;
                _downloadProgress = current / total;
              });
            }
          });
          if (!mounted) return;
          setState(() {
            _downloadTotal = 0;
            _downloadCurrent = 0;
            _downloadProgress = 0.0;
          });
          if (urlToLocal.isNotEmpty) {
            if (gameInfo.description != null) {
              var desc = gameInfo.description!;
              for (final entry in urlToLocal.entries) {
                desc = desc.replaceAll('[图片:${entry.key}]', '[图片:${entry.value}]');
              }
              final finalUpdated = updated.copyWith(intro: desc);
              await repo.updateGame(finalUpdated);
            }
            final metaJson = gameInfo.toJson();
            if (gameInfo.description != null) {
              var desc = gameInfo.description!;
              for (final entry in urlToLocal.entries) {
                desc = desc.replaceAll('[图片:${entry.key}]', '[图片:${entry.value}]');
              }
              metaJson['intro'] = desc;
            }
            if (gameInfo.descriptionHtml != null) {
              var html = gameInfo.descriptionHtml!;
              for (final entry in urlToLocal.entries) {
                html = html.replaceAll(entry.key, entry.value);
                if (entry.key.startsWith('https:')) {
                  html = html.replaceAll(entry.key.replaceFirst('https:', ''), entry.value);
                }
              }
              metaJson['intro_html'] = html;
            }
            await metadataFile.writeAsString(jsonEncode(metaJson), flush: true);
          }
        }

        await _fixImageUrlsInMetadata(updated);

        try {
          final configs = ref.read(scrapeModeConfigsProvider);
          if (configs.shouldRename(ScrapeMode.rescrape)) {
            final gameForRename = await repo.getGameById(_currentGame.id!);
            if (gameForRename != null) {
              final renameService = FolderRenameService(gameRepository: repo);
              final newPath = await renameService.renameGameFolder(gameForRename);
              if (newPath != null) {
                debugPrint('[Rescrape] Folder renamed: $newPath');
                final refreshed = await repo.getGameById(_currentGame.id!);
                if (refreshed != null) updated = refreshed;
              }
            }
          }
        } catch (e) {
          debugPrint('[Rescrape] Auto-rename failed: $e');
        }

        final configs = ref.read(scrapeModeConfigsProvider);
        if (configs.shouldMove(ScrapeMode.rescrape)) {
          await _moveToSorted(updated);
        }
        if (!mounted) return;
        setState(() { _currentGame = updated; _imageVersion++; });
        await _loadMetadataHtml();
        await _preloadMediaFiles();
        if (mounted) {
          Navigator.of(context).pop();
          _refreshAllProviders();
          AppTheme.showGlassToast(context, message: '重新刮削完成');
        }
      } else {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '刮削失败：无法解析页面', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '刮削失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    } finally {
      if (mounted) setState(() => _isRescraping = false);
    }
  }

  Future<void> _quickScrape() async {
    final input = _quickScrapeController.text.trim();
    if (input.isEmpty) return;
    setState(() => _isRescraping = true);
    AppTheme.showGlassToast(context, message: '刮削等待时间可能较长，请勿关闭当前窗口', duration: const Duration(seconds: 5));
    try {
      GameInfo? gameInfo;
      String url = input;
      String channel = _quickScrapeChannel;

      if (channel == 'auto') {
        if (input.contains('steampowered.com') || input.contains('steam')) {
          channel = 'steam';
        } else if (input.contains('dlsite.com') || RegExp(r'^(RJ|RE|VJ)\d+$', caseSensitive: false).hasMatch(input)) {
          channel = 'dlsite';
        }
      }

      if (channel == 'dlsite') {
        final dlsiteService = ref.read(dlsiteServiceProvider);
        final normalizedId = dlsiteService.normalizeId(input);
        if (normalizedId != null) {
          gameInfo = await dlsiteService.fetchById(normalizedId);
          url = dlsiteService.buildUrl(normalizedId);
        }
      } else if (channel == 'steam') {
        final steamService = ref.read(steamServiceProvider);
        String? appId;
        if (RegExp(r'^\d+$').hasMatch(input)) {
          appId = input;
        } else {
          final appidMatch = RegExp(r'/app/(\d+)').firstMatch(input);
          appId = appidMatch?.group(1);
        }
        if (appId != null) {
          final steamInfo = await steamService.fetchById(appId);
          if (steamInfo != null) {
            gameInfo = GameInfo(
              title: steamInfo.title,
              description: steamInfo.description,
              tags: steamInfo.tags,
              screenshots: steamInfo.screenshots,
              sourceUrl: steamInfo.sourceUrl,
              maker: steamInfo.developers.isNotEmpty ? steamInfo.developers.join(', ') : null,
            );
          }
          url = 'https://store.steampowered.com/app/$appId/';
        }
      } else {
        final isUrl = url.startsWith('http://') || url.startsWith('https://');
        if (!isUrl) {
          if (mounted) {
            AppTheme.showGlassToast(context, message: '请输入有效的链接、Steam AppID 或 DLsite ID', icon: Icons.info_outline, iconColor: AppTheme.getPrimaryColor(context));
          }
          return;
        }
        final scraper = HtmlScraper();
        await scraper.ensureLoaded();
        final headers = await buildScrapeHeaders(url);
        final client = await createProxyClientFromPrefs(domain: Uri.parse(url).host);
        http.Response response;
        try {
          response = await httpGetWithRetry(Uri.parse(url), headers: headers, client: client);
        } finally {
          client.close();
        }
        if (response.statusCode == 200) {
          gameInfo = scraper.scrapeGameInfo(response.body, url);
        } else {
          if (mounted) {
            AppTheme.showGlassToast(context, message: '请求失败: HTTP ${response.statusCode}', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
          }
          return;
        }
      }

      if (gameInfo == null) {
        if (mounted) {
          AppTheme.showGlassToast(context, message: '刮削失败，无法解析页面内容。请确认链接正确且站点已配置解析器。', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
        }
        return;
      }

      final repo = ref.read(gameRepositoryProvider);
      final tagRepo = ref.read(tagRepositoryProvider);
      var updatedGame = _currentGame.copyWith(
        title: gameInfo.title ?? _currentGame.title,
        version: gameInfo.version ?? _currentGame.version,
        intro: gameInfo.description ?? _currentGame.intro,
        features: gameInfo.features.isNotEmpty ? gameInfo.features.join('\n') : _currentGame.features,
        changelog: gameInfo.changelog ?? _currentGame.changelog,
        downloadUrl: gameInfo.downloadUrl.isNotEmpty ? gameInfo.downloadUrl : _currentGame.downloadUrl,
        sourceUrl: url,
        maker: gameInfo.maker ?? _currentGame.maker,
        makerUrl: gameInfo.makerUrl ?? _currentGame.makerUrl,
      );

      try {
        final metadataFile = File('${_currentGame.path}${Platform.pathSeparator}metadata.json');
        await metadataFile.writeAsString(jsonEncode(gameInfo.toJson()), flush: true);
      } catch (e) {
        debugPrint('[QuickScrape] Failed to write metadata.json: $e');
      }
      try {
        final sourceUrlFile = File('${_currentGame.path}${Platform.pathSeparator}source_url.txt');
        await sourceUrlFile.writeAsString(url, flush: true);
      } catch (e) {
        debugPrint('[QuickScrape] Failed to write source_url.txt: $e');
      }

      await repo.updateGame(updatedGame);

      if (_currentGame.id != null) {
        if (gameInfo.maker != null && gameInfo.maker!.isNotEmpty) {
          final makerTagId = await tagRepo.insertOrGetTag(gameInfo.maker!, Tag.typeCustom);
          await repo.addTagToGame(_currentGame.id!, makerTagId);
        }
        for (final tagName in gameInfo.tags) {
          final tagId = await tagRepo.insertOrGetTag(tagName, Tag.typeCustom);
          await repo.addTagToGame(_currentGame.id!, tagId);
        }
        if (gameInfo.category != null) {
          final tagId = await tagRepo.insertOrGetTag(gameInfo.category!, Tag.typeSeries);
          await repo.addTagToGame(_currentGame.id!, tagId);
        }

        if (gameInfo.screenshots.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _downloadTotal = gameInfo!.screenshots.length;
            _downloadCurrent = 0;
            _downloadProgress = 0.0;
          });
          await repo.deleteGameImagesByGameId(_currentGame.id!);
          final urlToLocal = await _downloadImagesWithMapping(
            _currentGame.copyWith(id: _currentGame.id!),
            gameInfo.screenshots,
            onProgress: (current, total) {
              if (mounted) {
                setState(() {
                  _downloadCurrent = current;
                  _downloadTotal = total;
                  _downloadProgress = current / total;
                });
              }
            },
          );
          if (!mounted) return;
          setState(() {
            _downloadTotal = 0;
            _downloadCurrent = 0;
            _downloadProgress = 0.0;
          });
          if (urlToLocal.isNotEmpty) {
            var desc = gameInfo.description;
            if (desc != null) {
              for (final entry in urlToLocal.entries) {
                desc = desc!.replaceAll('[图片:${entry.key}]', '[图片:${entry.value}]');
              }
              await repo.updateGame(updatedGame.copyWith(intro: desc));
            }
            final metaJson = gameInfo.toJson();
            if (desc != null) metaJson['intro'] = desc;
            if (gameInfo.descriptionHtml != null) {
              var html = gameInfo.descriptionHtml!;
              for (final entry in urlToLocal.entries) {
                html = html.replaceAll(entry.key, entry.value);
                if (entry.key.startsWith('https:')) {
                  html = html.replaceAll(entry.key.replaceFirst('https:', ''), entry.value);
                }
              }
              metaJson['intro_html'] = html;
            }
            try {
              final metadataFile = File('${_currentGame.path}${Platform.pathSeparator}metadata.json');
              await metadataFile.writeAsString(jsonEncode(metaJson), flush: true);
            } catch (e) {
              debugPrint('[GameDetail] 写入metadata.json失败: $e');
            }
          }
        }

        await _fixImageUrlsInMetadata(updatedGame);

        try {
          final configs = ref.read(scrapeModeConfigsProvider);
          if (configs.shouldRename(ScrapeMode.quickScrape)) {
            final gameForRename = await repo.getGameById(_currentGame.id!);
            if (gameForRename != null) {
              final renameService = FolderRenameService(gameRepository: repo);
              final newPath = await renameService.renameGameFolder(gameForRename);
              if (newPath != null) {
                debugPrint('[QuickScrape] Folder renamed: $newPath');
                final refreshed = await repo.getGameById(_currentGame.id!);
                if (refreshed != null) updatedGame = refreshed;
              }
            }
          }
        } catch (e) {
          debugPrint('[QuickScrape] Auto-rename failed: $e');
        }

        final configsMove = ref.read(scrapeModeConfigsProvider);
        if (configsMove.shouldMove(ScrapeMode.quickScrape)) {
          await _moveToSorted(updatedGame);
        }
      }

      final freshGame = await repo.getGameById(_currentGame.id!);
      if (freshGame != null && mounted) {
        await _loadMetadataHtml();
        await _preloadMediaFiles();
        setState(() {
          _currentGame = freshGame;
          _imageVersion++;
          _titleController.text = freshGame.title ?? '';
          _versionController.text = freshGame.version ?? '';
          _introController.text = freshGame.intro ?? '';
          _featuresController.text = freshGame.features ?? '';
          _changelogController.text = freshGame.changelog ?? '';
          _downloadUrlController.text = freshGame.downloadUrl ?? '';
          _sourceUrlController.text = freshGame.sourceUrl ?? '';
          _editedTags = List.from(freshGame.tags);
        });
        Navigator.of(context).pop();
        _refreshAllProviders();
        AppTheme.showGlassToast(context, message: '刮削成功: ${gameInfo.title ?? "未知标题"}');
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassToast(context, message: '刮削失败: $e', icon: Icons.error_outline, iconColor: AppTheme.errorColor);
      }
    } finally {
      if (mounted) setState(() => _isRescraping = false);
    }
  }

  Future<void> _downloadImages(Game game, List<String> imageUrls) async {
    final client = await createProxyClientFromPrefs(domain: game.sourceUrl != null ? Uri.tryParse(game.sourceUrl!)?.host : null);
    try {
    final imageDir = Directory('${game.path}${Platform.pathSeparator}images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }

    await ref.read(gameRepositoryProvider).deleteGameImagesByGameId(game.id!);

    // 清理旧图片文件
    if (await imageDir.exists()) {
      await for (final entity in imageDir.list()) {
        if (entity is File) await entity.delete();
      }
    }

    final repo = ref.read(gameRepositoryProvider);
    final sourceUrl = game.sourceUrl ?? '';
    final cookie = sourceUrl.isNotEmpty ? await getCookieForSite(sourceUrl) : '';
    for (int i = 0; i < imageUrls.length; i++) {
      try {
        final imageUrl = imageUrls[i];
        final uri = Uri.parse(imageUrl);
        final ext = imageUrl.contains('.') ? '.${imageUrl.split('.').last.split('?').first.split('#').first}' : '.jpg';
        final validExt = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext.toLowerCase()) ? ext : '.jpg';
        final fileName = '${i + 1}$validExt';
        final filePath = '${imageDir.path}${Platform.pathSeparator}$fileName';
        final file = File(filePath);

        if (!await file.exists()) {
          final imgHeaders = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
            'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
            'Referer': sourceUrl,
            if (cookie.isNotEmpty) 'Cookie': cookie,
          };
          final response = await client.get(uri, headers: imgHeaders).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await file.writeAsBytes(response.bodyBytes, flush: true);
          }
        }
        await repo.addGameImage(game.id!, filePath, i);
      } catch (e) {
        debugPrint('[GameDetail] 下载图片失败: $e');
      }
    }
    } finally {
      client.close();
    }
  }

  Future<void> _fixImageUrlsInMetadata(Game game) async {
    try {
      final metadataFile = File('${game.path}${Platform.pathSeparator}metadata.json');
      if (!await metadataFile.exists()) return;

      final metaJson = jsonDecode(await metadataFile.readAsString());
      final imageDir = Directory('${game.path}${Platform.pathSeparator}images');
      if (!await imageDir.exists()) return;

      final localImages = <String>[];
      await for (final entity in imageDir.list()) {
        if (entity is File) {
          localImages.add(entity.path);
        }
      }
      if (localImages.isEmpty) return;

      final imageUrls = (metaJson['image_urls'] as List<dynamic>?)?.cast<String>() ?? [];
      if (imageUrls.isEmpty) return;

      final urlToLocal = <String, String>{};
      for (int i = 0; i < imageUrls.length; i++) {
        final remoteUrl = imageUrls[i];
        for (final localPath in localImages) {
          final fileName = localPath.split(Platform.pathSeparator).last;
          final baseName = fileName.split('.').first;
          if (baseName == '${i + 1}') {
            urlToLocal[remoteUrl] = localPath;
            if (remoteUrl.startsWith('https:')) {
              urlToLocal[remoteUrl.replaceFirst('https:', '')] = localPath;
            }
            if (remoteUrl.startsWith('http:')) {
              urlToLocal[remoteUrl.replaceFirst('http:', '')] = localPath;
            }
            break;
          }
        }
      }

      if (urlToLocal.isEmpty) return;

      var intro = metaJson['intro'] as String? ?? '';
      if (intro.isNotEmpty) {
        for (final entry in urlToLocal.entries) {
          intro = intro.replaceAll('[图片:${entry.key}]', '[图片:${entry.value}]');
          intro = intro.replaceAll(entry.key, entry.value);
        }
        metaJson['intro'] = intro;
      }

      var introHtml = metaJson['intro_html'] as String? ?? '';
      if (introHtml.isNotEmpty) {
        for (final entry in urlToLocal.entries) {
          introHtml = introHtml.replaceAll(entry.key, entry.value);
        }
        metaJson['intro_html'] = introHtml;
      }

      await metadataFile.writeAsString(jsonEncode(metaJson), flush: true);

      final repo = ref.read(gameRepositoryProvider);
      final updatedGame = game.copyWith(intro: intro);
      await repo.updateGame(updatedGame);

      debugPrint('[FixImageUrls] Updated ${urlToLocal.length} image URLs for ${game.title}');
    } catch (e) {
      debugPrint('[FixImageUrls] Error: $e');
    }
  }

  Future<Map<String, String>> _downloadImagesWithMapping(
    Game game,
    List<String> imageUrls, {
    void Function(int current, int total)? onProgress,
  }) async {
    final urlToLocal = <String, String>{};
    final imageDir = Directory('${game.path}${Platform.pathSeparator}images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }

    final sourceUrl = game.sourceUrl ?? '';
    final cookie = sourceUrl.isNotEmpty ? await getCookieForSite(sourceUrl) : '';
    final imgHeaders = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Referer': sourceUrl,
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };

    final repo = ref.read(gameRepositoryProvider);
    final existingImages = await repo.getGameImages(game.id!);
    final existingPaths = existingImages.map((img) => img.imagePath).toSet();

    for (int i = 0; i < imageUrls.length; i++) {
      try {
        final imageUrl = imageUrls[i];
        final uri = Uri.parse(imageUrl);
        final ext = imageUrl.contains('.') ? '.${imageUrl.split('.').last.split('?').first.split('#').first}' : '.jpg';
        final validExt = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext.toLowerCase()) ? ext : '.jpg';
        final fileName = '${i + 1}$validExt';
        final filePath = '${imageDir.path}${Platform.pathSeparator}$fileName';
        final file = File(filePath);
        final tmpFile = File('$filePath.tmp');

        final response = await httpGetWithRetry(uri, headers: imgHeaders);
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await tmpFile.writeAsBytes(response.bodyBytes, flush: true);
          await tmpFile.rename(filePath);
        }
        if (!existingPaths.contains(filePath)) {
          await repo.addGameImage(game.id!, filePath, i);
        }
        urlToLocal[imageUrl] = filePath;
        onProgress?.call(i + 1, imageUrls.length);
      } catch (e) {
        debugPrint('[GameDetail] 下载截图失败: $e');
      }
    }

    return urlToLocal;
  }

  Future<void> _moveToSorted(Game game) async {
    final sortedPath = await AppSettings.getSortedPathForGame(game.path);
    if (sortedPath.isEmpty) return;

    final sourceDir = Directory(game.path);
    if (!await sourceDir.exists()) return;

    final repo = ref.read(gameRepositoryProvider);
    final tags = await repo.getGameTags(game.id!);
    const categoryOrder = ['RPG', 'ADV', 'ACT', 'SLG', 'AVG', 'FPS', 'TPS', '3D'];
    String categoryName = 'Unclassified';
    final allNames = tags.map((t) => t.name.toUpperCase()).toList();
    for (final cat in categoryOrder) {
      if (allNames.any((name) => name.contains(cat))) {
        categoryName = cat;
        break;
      }
    }

    final folderName = game.path.split(RegExp(r'[/\\]')).last;
    final targetDir = Directory('${sortedPath}${Platform.pathSeparator}${categoryName}${Platform.pathSeparator}$folderName');
    if (!await Directory('${sortedPath}${Platform.pathSeparator}${categoryName}').exists()) {
      await Directory('${sortedPath}${Platform.pathSeparator}${categoryName}').create(recursive: true);
    }

    if (await targetDir.exists()) return;

    final existingGame = await repo.getGameByPath(targetDir.path);
    if (existingGame != null) {
      await repo.deleteGame(existingGame.id!);
    }

    await sourceDir.rename(targetDir.path);
    await repo.updateGamePath(game.id!, targetDir.path);
    final images = await repo.getGameImages(game.id!);
    if (images.isNotEmpty) {
      final updatedImages = images.map((img) => GameImage(
        id: img.id,
        gameId: img.gameId,
        imagePath: img.imagePath.replaceFirst(game.path, targetDir.path),
        sortOrder: img.sortOrder,
      )).toList();
      await repo.setGameImages(game.id!, updatedImages);
    }

    final currentGame = await repo.getGameById(game.id!);
    if (currentGame != null && currentGame.intro != null) {
      var updatedIntro = currentGame.intro!;
      if (updatedIntro.contains(game.path)) {
        updatedIntro = updatedIntro.replaceAll(game.path, targetDir.path);
        await repo.updateGame(currentGame.copyWith(intro: updatedIntro));
      }
    }

    try {
      final metadataFile = File('${targetDir.path}${Platform.pathSeparator}metadata.json');
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        if (content.contains(game.path)) {
          final updatedContent = content.replaceAll(game.path, targetDir.path);
          await metadataFile.writeAsString(updatedContent, flush: true);
        }
      }
    } catch (e) {
      debugPrint('[GameDetail] 更新metadata路径失败: $e');
    }

    final updatedGame = await repo.getGameById(game.id!);
    if (updatedGame != null) {
      if (updatedGame.gameLauncher != null && updatedGame.gameLauncher!.startsWith(game.path)) {
        final relative = updatedGame.gameLauncher!.substring(game.path.length);
        final newLauncher = '${targetDir.path}$relative';
        await repo.updateGameLauncher(game.id!, newLauncher, updatedGame.launcherLocked);
      }
      if (updatedGame.savePath != null && updatedGame.savePath!.startsWith(game.path)) {
        final relative = updatedGame.savePath!.substring(game.path.length);
        final newSavePath = '${targetDir.path}$relative';
        await repo.updateGame(updatedGame.copyWith(savePath: newSavePath));
      }
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

  void _showUpdateDialog(VersionCheckResult result) {
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
              Row(
                children: [
                  Icon(Icons.system_update, color: AppTheme.successColor, size: 22),
                  const SizedBox(width: 8),
                  Text('发现新版本', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context))),
                ],
              ),
              const SizedBox(height: 16),
              Text('来源: ${result.siteName}', style: TextStyle(fontSize: 13, color: AppTheme.getTextSecondary(context))),
              const SizedBox(height: 4),
              Text('当前版本: ${_currentGame.version ?? "未知"}', style: TextStyle(fontSize: 13, color: AppTheme.getTextSecondary(context))),
              const SizedBox(height: 4),
              Text('最新版本: ${result.maxVersion}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.successColor)),
              const SizedBox(height: 8),
              Text('帖子标题: ${result.postTitle}', style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: result.downloadUrl == null
                        ? null
                        : () async {
                            Navigator.of(context).pop();
                            try {
                              await launchUrl(Uri.parse(result.downloadUrl!));
                            } catch (_) {
                              // 外部浏览器打开失败时静默处理
                            }
                          },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('前往下载'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.getPrimaryColor(context),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showReviewDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _DetailReviewDialog(
        game: _currentGame,
        onSave: (rating, review) async {
          try {
            final repo = ref.read(gameRepositoryProvider);
            var gameId = _currentGame.id;
            if (gameId == null) {
              debugPrint('[Review] Game has no id, inserting into DB: ${_currentGame.path}');
              gameId = await repo.insertGame(_currentGame);
              debugPrint('[Review] Inserted game with id: $gameId');
            }
            await repo.updateRatingReview(gameId, rating, review.isEmpty ? null : review);
            debugPrint('[Review] Updated rating=$rating, review=${review.isEmpty ? "null" : review} for game id=$gameId');
            if (mounted) {
              _refreshAllProviders();
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
        onDelete: () async {
          try {
            final repo = ref.read(gameRepositoryProvider);
            var gameId = _currentGame.id;
            if (gameId == null) {
              debugPrint('[Review] Game has no id, inserting into DB: ${_currentGame.path}');
              gameId = await repo.insertGame(_currentGame);
              debugPrint('[Review] Inserted game with id: $gameId');
            }
            await repo.deleteRatingReview(gameId);
            debugPrint('[Review] Deleted rating/review for game id=$gameId');
            if (mounted) {
              _refreshAllProviders();
              AppTheme.showGlassToast(context, message: '评论已删除');
            }
          } catch (e, stackTrace) {
            debugPrint('[Review] Error deleting review: $e\n$stackTrace');
            if (mounted) {
              AppTheme.showGlassToast(
                context,
                message: '删除失败: $e',
                icon: Icons.error_outline,
                iconColor: AppTheme.errorColor,
              );
            }
          }
        },
      ),
    );
  }
}

class _HoverReviewButton extends StatefulWidget {
  final String review;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _HoverReviewButton({
    required this.review,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_HoverReviewButton> createState() => _HoverReviewButtonState();
}

class _HoverReviewButtonState extends State<_HoverReviewButton> {
  OverlayEntry? _overlayEntry;

  void _showOverlay() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final screenWidth = MediaQuery.of(context).size.width;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        left: (screenWidth - 320) / 2,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.getSurfaceColor(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.comment, size: 14, color: Colors.red),
                      SizedBox(width: 6),
                      Text('评论预览', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.getTextSecondary(context))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.review,
                    style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.getDetailTextPrimary(context)),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (mounted) _showOverlay();
      },
      onExit: (_) {
        _removeOverlay();
      },
      child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.comment, size: 14, color: Colors.red),
                SizedBox(width: 4),
                Text('评论', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isPath;
  final bool isLink;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isPath = false,
    this.isLink = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppTheme.getDetailTextPrimary(context)),
        const SizedBox(width: 8),
        Text('$label:', style: TextStyle(fontSize: 12, color: AppTheme.getDetailTextPrimary(context))),
        const SizedBox(width: 6),
        Expanded(
          child: isLink
              ? InkWell(
                  onTap: () async { try { await launchUrl(Uri.parse(value)); } catch (_) {
                    // 外部浏览器打开失败时静默处理
                  } },
                  child: Text(value, style: TextStyle(fontSize: 12, color: AppTheme.getPrimaryColor(context), decoration: TextDecoration.underline), maxLines: 2, overflow: TextOverflow.ellipsis),
                )
              : SelectableText(
                  value,
                  style: TextStyle(fontSize: 12, color: valueColor ?? AppTheme.getDetailTextPrimary(context)),
                  maxLines: isPath ? 2 : 1,
                ),
        ),
      ],
    );
  }
}

class _DetailReviewDialog extends StatefulWidget {
  final Game game;
  final void Function(double rating, String review) onSave;
  final VoidCallback onDelete;

  const _DetailReviewDialog({required this.game, required this.onSave, required this.onDelete});

  @override
  State<_DetailReviewDialog> createState() => _DetailReviewDialogState();
}

class _DetailReviewDialogState extends State<_DetailReviewDialog> {
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
    final rawRating = x / starWidth;
    final clamped = rawRating.clamp(0.0, 5.0);
    return (clamped * 2).round() / 2;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.getSurfaceColor(context),
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
            Row(
              children: [
                const Icon(Icons.comment, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.game.title ?? '未命名游戏',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('评分', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.getDetailTextPrimary(context))),
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
                          color: icon == Icons.star_border ? AppTheme.getTextSecondary(context) : AppTheme.getStarColor(context),
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
                  style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)),
                ),
              ),
            const SizedBox(height: 20),
            Text('评论', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.getDetailTextPrimary(context))),
            const SizedBox(height: 8),
            TextField(
              controller: _reviewController,
              maxLines: 5,
              style: TextStyle(fontSize: 14, color: AppTheme.getDetailTextPrimary(context)),
              decoration: InputDecoration(
                hintText: '写下你的评论...',
                hintStyle: TextStyle(color: AppTheme.getTextSecondary(context).withValues(alpha: 0.5)),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurfaceColor.withValues(alpha: 0.5) : AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.getPrimaryColor(context)),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    widget.onDelete();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.errorColor),
                  label: const Text('删除', style: TextStyle(color: AppTheme.errorColor)),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('取消', style: TextStyle(color: AppTheme.getTextSecondary(context))),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        widget.onSave(_rating, _reviewController.text);
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.getPrimaryColor(context),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageViewerDialog extends StatefulWidget {
  final List<GameImage> images;
  final int initialIndex;
  final VoidCallback onClose;

  const _ImageViewerDialog({required this.images, required this.initialIndex, required this.onClose});

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
  late int _currentIndex;
  late FocusNode _focusNode;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  static const double _minScale = 0.2;
  static const double _maxScale = 5.0;
  static const double _scaleStep = 0.2;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _previous() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _scale = 1.0;
        _offset = Offset.zero;
      });
    }
  }

  void _next() {
    if (_currentIndex < widget.images.length - 1) {
      setState(() {
        _currentIndex++;
        _scale = 1.0;
        _offset = Offset.zero;
      });
    }
  }

  void _close() {
    widget.onClose();
    Navigator.of(context).pop();
  }

  void _handleScale(double delta) {
    setState(() {
      final oldScale = _scale;
      if (delta > 0) {
        _scale = (_scale + _scaleStep).clamp(_minScale, _maxScale);
      } else {
        _scale = (_scale - _scaleStep).clamp(_minScale, _maxScale);
      }
      if (_scale <= 1.0) {
        _offset = Offset.zero;
      } else {
        final ratio = _scale / oldScale;
        _offset = Offset(_offset.dx * ratio, _offset.dy * ratio);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final viewerW = screenSize.width * 0.8;
    final viewerH = screenSize.height * 0.8;
    final isDraggable = _scale > 1.0;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _close();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _previous();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _next();
          }
        }
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: _close,
          child: Container(
            width: screenSize.width,
            height: screenSize.height,
            color: Colors.transparent,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: viewerW,
                height: viewerH,
                decoration: BoxDecoration(
                  color: AppTheme.getSurfaceColor(context).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
                  border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 60,
                            child: GestureDetector(
                              onTap: _previous,
                              child: Container(
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: _currentIndex > 0
                                    ? Icon(Icons.chevron_left, size: 48, color: AppTheme.getDetailTextPrimary(context).withValues(alpha: 0.5))
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Listener(
                              onPointerSignal: (pointerSignal) {
                                if (pointerSignal is PointerScrollEvent) {
                                  _handleScale(pointerSignal.scrollDelta.dy > 0 ? -1 : 1);
                                }
                              },
                              child: GestureDetector(
                                onScaleUpdate: (details) {
                                  if (isDraggable && details.pointerCount == 1) {
                                    setState(() {
                                      _offset += details.focalPointDelta;
                                      final scaledW = (viewerW - 120) * _scale;
                                      final scaledH = (viewerH - 80) * _scale;
                                      double maxDx = 0, maxDy = 0;
                                      if (scaledW > viewerW - 120) maxDx = (scaledW - (viewerW - 120)) / 2;
                                      if (scaledH > viewerH - 80) maxDy = (scaledH - (viewerH - 80)) / 2;
                                      _offset = Offset(
                                        _offset.dx.clamp(-maxDx, maxDx),
                                        _offset.dy.clamp(-maxDy, maxDy),
                                      );
                                    });
                                  }
                                },
                                child: Container(
                                  color: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: widget.images.isNotEmpty && _currentIndex < widget.images.length
                                        ? Transform(
                                            transform: Matrix4.identity()
                                              ..translate(_offset.dx, _offset.dy)
                                              ..scale(_scale),
                                            alignment: Alignment.center,
                                            child: Image.file(
                                              File(widget.images[_currentIndex].imagePath!),
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 64, color: AppTheme.getDetailTextPrimary(context).withValues(alpha: 0.3)),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: GestureDetector(
                              onTap: _next,
                              child: Container(
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: _currentIndex < widget.images.length - 1
                                    ? Icon(Icons.chevron_right, size: 48, color: AppTheme.getDetailTextPrimary(context).withValues(alpha: 0.5))
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Close button
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _close,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close, size: 22, color: AppTheme.getDetailTextPrimary(context)),
                          ),
                        ),
                      ),
                    ),
                    // Counter
                    Positioned(
                      top: 12,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${_currentIndex + 1} / ${widget.images.length}', style: TextStyle(color: AppTheme.getDetailTextPrimary(context), fontSize: 13)),
                      ),
                    ),
                    // Zoom percentage
                    Positioned(
                      top: 12,
                      left: 100,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${(_scale * 100).round()}%', style: TextStyle(color: AppTheme.getDetailTextPrimary(context), fontSize: 13)),
                      ),
                    ),
                    // Reset button
                    if (_scale != 1.0)
                      Positioned(
                        top: 12,
                        left: 160,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _scale = 1.0;
                            _offset = Offset.zero;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('重置', style: TextStyle(color: AppTheme.getPrimaryColor(context), fontSize: 13)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageSelectionDialog extends StatelessWidget {
  final List<GameImage> images;

  const _ImageSelectionDialog({required this.images});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.getSurfaceColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.5,
        height: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.photo_library, color: AppTheme.getPrimaryColor(context), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '选择图片',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getDetailTextPrimary(context)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '选择一张图片插入到内容中',
              style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 16 / 9,
                ),
                itemCount: images.length,
                itemBuilder: (context, index) {
                  final image = images[index];
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, image),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
                        border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.3)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(GlassConstants.radiusSmall - 1),
                        child: Image.file(
                          File(image.imagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.3),
                            child: const Center(child: Icon(Icons.broken_image, size: 32)),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ContentBlockType { text, heading, imageWithText }

class _ContentBlock {
  final _ContentBlockType type;
  final String text;
  final String? imageUrl;

  _ContentBlock._(this.type, this.text, this.imageUrl);

  factory _ContentBlock.text(String text) => _ContentBlock._(_ContentBlockType.text, text, null);
  factory _ContentBlock.heading(String text) => _ContentBlock._(_ContentBlockType.heading, text, null);
  factory _ContentBlock.imageWithText(String imageUrl, String text) =>
      _ContentBlock._(_ContentBlockType.imageWithText, text, imageUrl);
}

class _PlayerCache {
  static final Map<String, _CachedVideoPlayer> _players = {};

  static _CachedVideoPlayer getOrCreate(String videoPath) {
    return _players.putIfAbsent(
      videoPath,
      () => _CachedVideoPlayer(Player()),
    );
  }

  static void disposeAll() {
    for (final cached in _players.values) {
      cached.player.dispose();
    }
    _players.clear();
  }
}

class _CachedVideoPlayer {
  final Player player;
  late final VideoController controller;
  bool initialized = false;

  _CachedVideoPlayer(this.player) {
    controller = VideoController(player);
  }
}

class _InlineVideoPlayer extends StatefulWidget {
  final String videoPath;
  final _CachedVideoPlayer cached;

  const _InlineVideoPlayer({required this.videoPath, required this.cached});

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    if (!widget.cached.initialized) {
      _init();
    }
  }

  Future<void> _init() async {
    try {
      await widget.cached.player.open(Media(widget.videoPath), play: false);
      if (_disposed || !mounted) return;
      await widget.cached.player.setPlaylistMode(PlaylistMode.loop);
      if (_disposed || !mounted) return;
      await widget.cached.player.play();
      if (!_disposed && mounted) {
        setState(() => widget.cached.initialized = true);
      }
    } catch (e) {
      debugPrint('[VideoPlayer] _init error: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.cached.initialized) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 450),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Video(
            controller: widget.cached.controller,
          ),
        ),
      ),
    );
  }
}
