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
import 'ui/controllers/window_controller.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';

void main() async {
  // Suppress noisy Flutter accessibility logs
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.contains('accessibility_bridge')) return;
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
              final fontName = fontPath.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'\.ttf$', caseSensitive: false), '');
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
              final fontName = fontPath.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'\.ttf$', caseSensitive: false), '');
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
        message.contains('Failed to update ui::AXTree')) {
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

  runZonedGuarded(() {}, (error, stackTrace) {
    log.error('UnhandledError', error.toString(), error, stackTrace);
  });
}

class HGameManagerApp extends ConsumerWidget {
  final WindowController? windowController;

  const HGameManagerApp({super.key, this.windowController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final fontFamily = prefs.getString('font_family') ?? '';
    final themeMode = ref.watch(flutterThemeModeProvider);

    return MaterialApp(
      title: 'HGame Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(fontFamily: fontFamily.isEmpty ? null : fontFamily),
      darkTheme: AppTheme.darkTheme(fontFamily: fontFamily.isEmpty ? null : fontFamily),
      themeMode: themeMode,
      builder: (context, child) {
        return GradientBackground(
          child: ErrorBoundary(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: HomePage(windowController: windowController),
    );
  }
}

class ErrorBoundary extends StatefulWidget {
  final Widget child;

  const ErrorBoundary({super.key, required this.child});

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
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
              color: Colors.white.withValues(alpha: 0.85),
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
                      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('重试', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
