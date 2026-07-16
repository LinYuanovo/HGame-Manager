import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/utils/app_settings.dart';
import 'core/providers/providers.dart';
import 'core/services/app_logger.dart';
import 'core/services/play_time_tracker.dart';
import 'ui/controllers/window_controller.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';

void main() async {
  // Suppress noisy Flutter accessibility logs
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null &&
        (message.contains('accessibility_bridge') ||
            message.contains(
                'Unable to parse JSON message:\nThe document is empty'))) {
      return;
    }
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };

  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit init error: $e');
  }

  await AppLogger.instance.init();

  _setupErrorHandling();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final prefs = await AppSettings.load();
    final windowController = WindowController(prefs);
    await windowController.initialize();

    // Load custom fonts
    final customFonts = prefs.getString('custom_fonts') ?? '';
    if (customFonts.isNotEmpty) {
      for (final fontPath in customFonts.split(',')) {
        if (fontPath.isNotEmpty) {
          try {
            final fontFile = File(fontPath);
            if (await fontFile.exists()) {
              final fontName = fontPath
                  .split(RegExp(r'[/\\]'))
                  .last
                  .replaceAll(RegExp(r'\.ttf$', caseSensitive: false), '');
              final fontData = await fontFile.readAsBytes();
              final fontLoader = FontLoader(fontName);
              fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
              await fontLoader.load();
            }
          } catch (e) {
            debugPrint('Failed to load custom font: $e');
          }
        }
      }
    }

    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: HGameManagerApp(windowController: windowController),
      ),
    );
  } else {
    final prefs = await AppSettings.load();

    // Load custom fonts
    final customFonts = prefs.getString('custom_fonts') ?? '';
    if (customFonts.isNotEmpty) {
      for (final fontPath in customFonts.split(',')) {
        if (fontPath.isNotEmpty) {
          try {
            final fontFile = File(fontPath);
            if (await fontFile.exists()) {
              final fontName = fontPath
                  .split(RegExp(r'[/\\]'))
                  .last
                  .replaceAll(RegExp(r'\.ttf$', caseSensitive: false), '');
              final fontData = await fontFile.readAsBytes();
              final fontLoader = FontLoader(fontName);
              fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
              await fontLoader.load();
            }
          } catch (e) {
            debugPrint('Failed to load custom font: $e');
          }
        }
      }
    }

    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const HGameManagerApp(),
      ),
    );
  }
}

void _setupErrorHandling() {
  final log = AppLogger.instance;

  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.toString();
    if (message.contains('accessibility_bridge.cc') ||
        message.contains('Failed to update ui::AXTree') ||
        _isWindowsMetaKeyStateAssertion(details)) {
      return;
    }
    log.error('FlutterError', details.exceptionAsString(), null, details.stack);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    final errorStr = error.toString();
    if (errorStr.contains('accessibility_bridge.cc') ||
        errorStr.contains('Failed to update ui::AXTree') ||
        errorStr.contains('AXTree')) {
      return true;
    }
    log.error('PlatformError', error.toString(), error, stackTrace);
    return true;
  };
}

bool _isWindowsMetaKeyStateAssertion(FlutterErrorDetails details) {
  if (!Platform.isWindows) return false;
  final message = details.exceptionAsString();
  return message.contains(
        'Attempted to send a key down event when no keys are in keysPressed',
      ) &&
      message.contains('Meta Left');
}

class HGameManagerApp extends ConsumerStatefulWidget {
  final WindowController? windowController;

  const HGameManagerApp({super.key, this.windowController});

  @override
  ConsumerState<HGameManagerApp> createState() => _HGameManagerAppState();
}

class _HGameManagerAppState extends ConsumerState<HGameManagerApp> {
  static const int _startupMigrationBatchSize = 5;
  static const Duration _startupMigrationTimeout = Duration(seconds: 5);

  String _lastFontFamily = '';
  ThemeData? _cachedLightTheme;
  ThemeData? _cachedDarkTheme;
  Timer? _startupMigrationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupMigrationTimer =
          Timer(const Duration(seconds: 5), _migrateExistingGameData);
    });
  }

  @override
  void dispose() {
    _startupMigrationTimer?.cancel();
    super.dispose();
  }

  Future<void> _migrateExistingGameData() async {
    final log = AppLogger.instance;
    try {
      if (!mounted) return;
      final repository = ref.read(gameRepositoryProvider);
      final migrationService = ref.read(gameDataMigrationServiceProvider);
      final prefs = ref.read(sharedPreferencesProvider);
      final games = await repository.getAllGames();
      final currentIds = games
          .map((game) => game.id)
          .whereType<int>()
          .map((id) => id.toString())
          .toSet();
      final migratedIds =
          prefs.getStringList(AppSettings.startupMigratedGameIdsKey)?.toSet() ??
              <String>{};
      final originalMigratedCount = migratedIds.length;
      migratedIds.removeWhere((id) => !currentIds.contains(id));

      final pendingGames = games.where((game) {
        final id = game.id;
        return id != null && !migratedIds.contains(id.toString());
      }).toList()
        ..sort((a, b) => a.id!.compareTo(b.id!));

      log.info(
        'GameDataMigration',
        '启动增量迁移检查: total=${games.length}, completed=${migratedIds.length}, '
            'pending=${pendingGames.length}, pruned=${originalMigratedCount - migratedIds.length}',
      );

      if (pendingGames.isEmpty) {
        if (migratedIds.length != originalMigratedCount) {
          await _saveStartupMigrationIds(prefs, migratedIds);
          log.info('GameDataMigration', '已清理不存在游戏的迁移记录');
        }
        return;
      }

      var changed = false;
      var successCount = 0;
      var missingCount = 0;
      var timeoutCount = 0;
      var failedCount = 0;
      var progressDirty = migratedIds.length != originalMigratedCount;

      for (var i = 0; i < pendingGames.length; i++) {
        if (!mounted) return;
        final game = pendingGames[i];
        final gameId = game.id!;
        try {
          log.info(
            'GameDataMigration',
            '开始迁移检查: id=$gameId, index=${i + 1}/${pendingGames.length}, path=${game.path}',
          );
          final result = await migrationService
              .migrateGameDirectory(game.path, gameId: gameId)
              .timeout(_startupMigrationTimeout);
          changed |= result.changed;
          if (result.gameDirectoryExists) {
            migratedIds.add(gameId.toString());
            progressDirty = true;
            successCount++;
          } else {
            missingCount++;
            log.warning(
              'GameDataMigration',
              '游戏目录不存在，未记录为已迁移: id=$gameId, path=${game.path}',
            );
          }
          log.info(
            'GameDataMigration',
            '迁移检查完成: id=$gameId, changed=${result.changed}, '
                'movedImages=${result.imagePathMap.length}, path=${game.path}',
          );
        } on TimeoutException {
          timeoutCount++;
          log.warning(
            'GameDataMigration',
            '启动迁移超时，保留待下次重试: id=$gameId, path=${game.path}',
          );
        } catch (e, stackTrace) {
          failedCount++;
          log.error(
            'GameDataMigration',
            '迁移失败，保留待下次重试: id=$gameId, path=${game.path}',
            e,
            stackTrace,
          );
        }

        if (i % _startupMigrationBatchSize == _startupMigrationBatchSize - 1) {
          if (progressDirty) {
            await _saveStartupMigrationIds(prefs, migratedIds);
            progressDirty = false;
            log.info(
              'GameDataMigration',
              '已保存迁移进度: completed=${migratedIds.length}, '
                  'processed=${i + 1}/${pendingGames.length}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      }

      if (progressDirty) {
        await _saveStartupMigrationIds(prefs, migratedIds);
        log.info(
          'GameDataMigration',
          '已保存最终迁移进度: completed=${migratedIds.length}',
        );
      }

      log.info(
        'GameDataMigration',
        '启动增量迁移结束: success=$successCount, missing=$missingCount, '
            'timeout=$timeoutCount, failed=$failedCount, changed=$changed',
      );

      if (!mounted || !changed) return;
      ref.invalidate(allGamesProvider);
      ref.invalidate(playedGamesProvider);
      ref.invalidate(favoriteGamesProvider);
      ref.invalidate(clearedGamesProvider);
    } catch (e, stackTrace) {
      log.error('GameDataMigration', '启动迁移失败', e, stackTrace);
    }
  }

  Future<void> _saveStartupMigrationIds(
    AppSettings prefs,
    Set<String> migratedIds,
  ) async {
    final sortedIds = migratedIds.toList()
      ..sort((left, right) {
        final leftId = int.tryParse(left);
        final rightId = int.tryParse(right);
        if (leftId != null && rightId != null) {
          return leftId.compareTo(rightId);
        }
        return left.compareTo(right);
      });
    await prefs.setStringList(AppSettings.startupMigratedGameIdsKey, sortedIds);
    await prefs.flush();
  }

  ThemeData _getLightTheme(String fontFamily) {
    if (_cachedLightTheme == null || _lastFontFamily != fontFamily) {
      _cachedLightTheme = AppTheme.lightTheme(
        fontFamily: fontFamily.isEmpty ? null : fontFamily,
      );
      _lastFontFamily = fontFamily;
    }
    return _cachedLightTheme!;
  }

  ThemeData _getDarkTheme(String fontFamily) {
    if (_cachedDarkTheme == null || _lastFontFamily != fontFamily) {
      _cachedDarkTheme = AppTheme.darkTheme(
        fontFamily: fontFamily.isEmpty ? null : fontFamily,
      );
    }
    return _cachedDarkTheme!;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final fontFamily = prefs.getString('font_family') ?? '';
    final themeMode = ref.watch(flutterThemeModeProvider);

    return MaterialApp(
      title: 'HGame Manager',
      debugShowCheckedModeBanner: false,
      theme: _getLightTheme(fontFamily),
      darkTheme: _getDarkTheme(fontFamily),
      themeMode: themeMode,
      builder: (context, child) {
        return GradientBackground(
          child: ErrorBoundary(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: HomePage(windowController: widget.windowController),
    );
  }
}

class ErrorBoundary extends StatefulWidget {
  final Widget child;

  const ErrorBoundary({super.key, required this.child});

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary>
    with WidgetsBindingObserver {
  Object? _error;
  StackTrace? _stackTrace;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 只在应用真正退出时停止追踪，inactive状态只是切换窗口
    if (state == AppLifecycleState.detached) {
      PlayTimeTracker.stopTracking();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: GlassContainer(
              margin: const EdgeInsets.all(40),
              padding: const EdgeInsets.all(32),
              borderRadius: GlassConstants.radiusXLarge,
              color: AppTheme.getSurfaceColor(context).withValues(alpha: 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: AppTheme.errorColor,
                    size: 72,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '应用发生错误',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.errorColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(GlassConstants.radiusMedium),
                      border: Border.all(
                        color: AppTheme.errorColor.withValues(alpha: 0.15),
                      ),
                    ),
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '错误信息:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.errorColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _error.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.getTextPrimary(context),
                          ),
                        ),
                        if (_stackTrace != null) ...[
                          const SizedBox(height: 14),
                          const Text(
                            '堆栈跟踪:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.errorColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 150,
                            child: SingleChildScrollView(
                              child: Text(
                                _stackTrace.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.getTextSecondary(context),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  GlassButton(
                    gradient: AppTheme.primaryGradient,
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _stackTrace = null;
                        _hasError = false;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh,
                            color: AppTheme.getTextColorOnPrimary(context),
                            size: 18),
                        const SizedBox(width: 8),
                        Text('重试',
                            style: TextStyle(
                                color: AppTheme.getTextColorOnPrimary(context),
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
