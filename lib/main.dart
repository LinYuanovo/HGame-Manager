import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/utils/app_settings.dart';
import 'core/providers/providers.dart';
import 'core/services/app_logger.dart';
import 'ui/controllers/window_controller.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLogger.instance.init();

  _setupErrorHandling();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final prefs = await AppSettings.load();
    final windowController = WindowController(prefs);
    await windowController.initialize();

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
    log.error('FlutterError', details.exceptionAsString(), null, details.stack);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
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
    return MaterialApp(
      title: 'HGame Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(fontFamily: fontFamily.isEmpty ? null : fontFamily),
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
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(40),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 80,
                ),
                const SizedBox(height: 20),
                const Text(
                  '应用发生错误',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '错误信息:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _error.toString(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (_stackTrace != null) ...[
                        const SizedBox(height: 15),
                        Text(
                          '堆栈跟踪:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          height: 150,
                          child: SingleChildScrollView(
                            child: Text(
                              _stackTrace.toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _stackTrace = null;
                      _hasError = false;
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
