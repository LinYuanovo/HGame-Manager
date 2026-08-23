import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../core/services/app_logger.dart';
import '../../core/utils/cloudflare_challenge.dart';
import '../../core/utils/dynamic_page_detector.dart';
import '../../core/utils/webview2_lifecycle.dart';
import '../theme/app_theme.dart';

final _log = AppLogger.instance;

class CloudflareBrowserResult {
  final String html;
  final String finalUrl;
  final bool usedSilentMode;

  const CloudflareBrowserResult({
    required this.html,
    required this.finalUrl,
    this.usedSilentMode = false,
  });
}

Future<CloudflareBrowserResult?> resolveCloudflareBrowserPage({
  required BuildContext context,
  required String url,
  Map<String, String>? headers,
  bool Function(String html)? isHtmlReady,
}) async {
  _log.info('WebView', '[Resolve] start url=' + url);
  if (!context.mounted) return null;

  // 页面加载、Cookie 操作和最终 HTML 读取都在同一个可见 WebView 生命周期内完成，
  // 避免后台轮询页面 HTML 触发 Windows WebView2 原生进程异常。
  _log.info(
    'WebView',
    '[Resolve] using visible Flutter WebView dialog url=' + url,
  );
  return showCloudflareBrowserDialog(
    context: context,
    url: url,
    headers: headers,
    isHtmlReady: isHtmlReady,
  );
}
Future<CloudflareBrowserResult?> tryReadCloudflareBrowserPageSilently({
  BuildContext? context,
  required String url,
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 12),
  Duration settleDelay = const Duration(milliseconds: 1200),
  bool Function(String html)? isHtmlReady,
}) async {
  if (context != null && context.mounted) {
    final overlayResult = await _tryReadCloudflareBrowserPageInOverlay(
      context: context,
      url: url,
      headers: headers,
      timeout: timeout,
      settleDelay: settleDelay,
      isHtmlReady: isHtmlReady,
    );
    if (overlayResult != null) return overlayResult;
  }
  return null;
}

Future<CloudflareBrowserResult?> _tryReadCloudflareBrowserPageInOverlay({
  required BuildContext context,
  required String url,
  Map<String, String>? headers,
  required Duration timeout,
  required Duration settleDelay,
  bool Function(String html)? isHtmlReady,
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    _log.warning('WebView', '[Silent] no root overlay available url=' + url);
    return null;
  }

  final completer = Completer<CloudflareBrowserResult?>();
  OverlayEntry? entry;
  var completionScheduled = false;
  final startedAt = DateTime.now();
  void complete(CloudflareBrowserResult? result) {
    if (completer.isCompleted || completionScheduled) return;
    completionScheduled = true;
    _log.info(
      'WebView',
      '[Silent] complete result=${result != null ? 'success' : 'timeout/failure'} '
          'elapsed=${DateTime.now().difference(startedAt).inMilliseconds}ms',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _log.info('WebView', '[Silent] removing overlay entry');
      entry?.remove();
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (!completer.isCompleted) completer.complete(result);
      });
    });
  }

  entry = OverlayEntry(
    builder: (_) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.01,
            child: _SilentCloudflareWebView(
              url: url,
              headers: headers,
              timeout: timeout,
              settleDelay: settleDelay,
              isHtmlReady: isHtmlReady,
              onComplete: complete,
            ),
          ),
        ),
      );
    },
  );
  _log.info('WebView', '[Silent] overlay inserted url=' + url);
  overlay.insert(entry);
  return completer.future;
}

Future<CloudflareBrowserResult?> showCloudflareBrowserDialog({
  required BuildContext context,
  required String url,
  Map<String, String>? headers,
  bool Function(String html)? isHtmlReady,
}) async {
  if (!context.mounted) return null;
  _log.info('WebView', '[ExternalBrowser] starting url=' + url);
  final session = await _ExternalBrowserSession.start(url, headers);
  if (session == null || !context.mounted) return null;
  final result = await showDialog<CloudflareBrowserResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppTheme.getSurfaceColor(dialogContext),
      child: _ExternalBrowserDialog(
        session: session,
        isHtmlReady: isHtmlReady,
      ),
    ),
  );
  await session.close();
  return result;
}

class _ExternalBrowserSession {
  final Process process;
  final Directory dataDir;
  final ChromeConnection chromeConnection;
  final WipConnection connection;
  final WipPage page;
  final WipRuntime runtime;
  final String url;
  final String browserName;

  _ExternalBrowserSession({
    required this.process,
    required this.dataDir,
    required this.chromeConnection,
    required this.connection,
    required this.url,
    required this.browserName,
  })  : page = WipPage(connection),
        runtime = WipRuntime(connection);

  static Future<_ExternalBrowserSession?> start(
    String url,
    Map<String, String>? headers,
  ) async {
    Process? process;
    Directory? dataDir;
    ChromeConnection? chromeConnection;
    WipConnection? connection;
    try {
      final browser = _findExternalBrowser();
      if (browser == null) {
        throw StateError('未找到 Google Chrome 或 Microsoft Edge');
      }
      final createdDataDir =
          await Directory.systemTemp.createTemp('hgame_browser_');
      dataDir = createdDataDir;
      final port = await _findUnusedPort();
      final startedProcess = await Process.start(
        browser.path,
        [
          '--user-data-dir=${createdDataDir.path}',
          '--remote-debugging-port=$port',
          '--disable-background-timer-throttling',
          '--disable-features=IntensiveWakeUpThrottling',
          '--disable-extensions',
          '--disable-popup-blocking',
          '--no-first-run',
          '--no-default-browser-check',
          '--disable-default-apps',
          '--disable-translate',
          '--start-maximized',
          'about:blank',
        ],
      );
      process = startedProcess;
      final createdConnection = ChromeConnection('127.0.0.1', port);
      chromeConnection = createdConnection;
      final tab = await createdConnection.getTab(
        (candidate) => candidate.type == 'page',
        retryFor: const Duration(seconds: 15),
      );
      if (tab == null) throw StateError('未找到浏览器页面');
      final connected = await tab.connect();
      connection = connected;
      final session = _ExternalBrowserSession(
        process: startedProcess,
        dataDir: createdDataDir,
        chromeConnection: createdConnection,
        connection: connected,
        url: url,
        browserName: browser.name,
      );
      await connected.sendCommand('Network.enable');
      final userAgent = _extractUserAgent(headers);
      if (userAgent != null) {
        await connected.sendCommand(
          'Emulation.setUserAgentOverride',
          {'userAgent': userAgent},
        );
      }
      final cookies = _buildChromeCookies(url, _extractHeader(headers, 'cookie'));
      if (cookies.isNotEmpty) {
        await connected.sendCommand(
          'Network.setCookies',
          {'cookies': cookies},
        );
      }
      await session.page.enable();
      await session.page.navigate(url);
      _log.info(
        'WebView',
        '[ExternalBrowser] browser=${browser.name} started url=$url',
      );
      return session;
    } catch (e, stackTrace) {
      _log.error('WebView', '[ExternalBrowser] start failed', e, stackTrace);
      await connection?.close();
      chromeConnection?.close();
      process?.kill();
      await process?.exitCode;
      if (dataDir != null) {
        try {
          await dataDir.delete(recursive: true);
        } catch (_) {}
      }
      return null;
    }
  }

  Future<String> readHtml() async {
    final result = await runtime.evaluate(
      'document.documentElement == null ? "" : document.documentElement.outerHTML',
      returnByValue: true,
    );
    return result.value?.toString() ?? '';
  }

  Future<void> close() async {
    try {
      await connection.close();
    } catch (_) {}
    chromeConnection.close();
    process.kill();
    try {
      await process.exitCode;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await dataDir.delete(recursive: true);
    } catch (_) {}
  }
}

class _ExternalBrowser {
  final String name;
  final String path;

  const _ExternalBrowser(this.name, this.path);
}

_ExternalBrowser? _findExternalBrowser() {
  final requested = Platform.environment['HGAME_EXTERNAL_BROWSER']
      ?.trim()
      .toLowerCase();
  final forcedName = requested == 'edge'
      ? 'Edge'
      : requested == 'chrome'
          ? 'Chrome'
          : null;
  if (requested != null && requested.isNotEmpty && forcedName == null) {
    _log.warning(
      'WebView',
      '[ExternalBrowser] unknown HGAME_EXTERNAL_BROWSER=$requested; using auto detection',
    );
  }

  final candidates = <_ExternalBrowser>[];
  void addEnvironmentCandidates(String name, List<String?> paths) {
    if (forcedName != null && forcedName != name) return;
    for (final path in paths) {
      if (path != null && path.trim().isNotEmpty) {
        candidates.add(_ExternalBrowser(name, path));
      }
    }
  }

  addEnvironmentCandidates('Chrome', [
    Platform.environment['CHROME_EXECUTABLE'],
    Platform.environment['CHROME_PATH'],
  ]);
  addEnvironmentCandidates('Edge', [
    Platform.environment['EDGE_EXECUTABLE'],
    Platform.environment['EDGE_PATH'],
  ]);

  final roots = <String?>[
    Platform.environment['LOCALAPPDATA'],
    Platform.environment['PROGRAMFILES'],
    Platform.environment['PROGRAMFILES(X86)'],
  ];
  if (forcedName == null || forcedName == 'Chrome') {
    for (final root in roots.whereType<String>()) {
      candidates.add(_ExternalBrowser(
        'Chrome',
        p.join(root, 'Google', 'Chrome', 'Application', 'chrome.exe'),
      ));
    }
  }
  if (forcedName == null || forcedName == 'Edge') {
    for (final root in roots.whereType<String>()) {
      candidates.add(_ExternalBrowser(
        'Edge',
        p.join(root, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
      ));
    }
  }

  for (final candidate in candidates) {
    if (File(candidate.path).existsSync()) {
      _log.info(
        'WebView',
        '[ExternalBrowser] selected ${candidate.name} path=${candidate.path}'
            '${forcedName == null ? '' : ' forced=$forcedName'}',
      );
      return candidate;
    }
  }
  _log.warning(
    'WebView',
    '[ExternalBrowser] no browser found'
        '${forcedName == null ? '' : ' forced=$forcedName'}',
  );
  return null;
}

Future<int> _findUnusedPort() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}

class _ExternalBrowserDialog extends StatefulWidget {
  final _ExternalBrowserSession session;
  final bool Function(String html)? isHtmlReady;

  const _ExternalBrowserDialog({
    required this.session,
    required this.isHtmlReady,
  });

  @override
  State<_ExternalBrowserDialog> createState() => _ExternalBrowserDialogState();
}

class _ExternalBrowserDialogState extends State<_ExternalBrowserDialog> {
  bool _reading = false;
  String? _error;

  Future<void> _useCurrentPage() async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final html = await widget.session.readHtml();
      if (html.trim().isEmpty) {
        setState(() => _error = '浏览器页面尚未准备好，请等待加载完成后重试');
        return;
      }
      if (widget.isHtmlReady != null && !widget.isHtmlReady!(html)) {
        setState(() => _error = '当前页面尚未出现目标标题，请完成验证并等待内容加载后重试');
        return;
      }
      if (mounted) {
        Navigator.of(context).pop(
          CloudflareBrowserResult(html: html, finalUrl: widget.session.url),
        );
      }
    } catch (e, stackTrace) {
      _log.warning('WebView', '[ExternalBrowser] read failed: $e');
      _log.info('WebView', '[ExternalBrowser] read stack: $stackTrace');
      if (mounted) {
        setState(() => _error = '读取 ${widget.session.browserName} 页面失败，请确认浏览器仍在运行后重试');
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _cancel() {
    if (!_reading) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外部 ${widget.session.browserName} 页面验证',
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 12),
            Text(
              '${widget.session.browserName} 已打开目标页面。请在浏览器中完成 Cookie 或 Cloudflare 验证，等待文章内容完全加载后返回此窗口，点击“使用当前页面”。',
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 13,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(
                      color: AppTheme.errorColor, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _reading ? null : _cancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _reading ? null : _useCurrentPage,
                  icon: _reading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(_reading ? '读取中' : '使用当前页面'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SilentCloudflareWebView extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final Duration timeout;
  final Duration settleDelay;
  final bool Function(String html)? isHtmlReady;
  final ValueChanged<CloudflareBrowserResult?> onComplete;

  const _SilentCloudflareWebView({
    required this.url,
    required this.headers,
    required this.timeout,
    required this.settleDelay,
    required this.isHtmlReady,
    required this.onComplete,
  });

  @override
  State<_SilentCloudflareWebView> createState() =>
      _SilentCloudflareWebViewState();
}

class _SilentCloudflareWebViewState extends State<_SilentCloudflareWebView> {
  InAppWebViewController? _controller;
  Timer? _timeoutTimer;
  Timer? _settleTimer;
  var _currentUrl = '';
  var _ready = false;
  var _completed = false;
  var _disposed = false;
  var _readInProgress = false;
  var _timedOut = false;
  var _readyStreak = 0;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _log.info('WebView', '[Silent] init url=${widget.url}');
    _timeoutTimer = Timer(widget.timeout, _handleTimeout);
    _log.info('WebView', '[Silent] timeout scheduled ${widget.timeout.inMilliseconds}ms');
    _prepareWebViewRequest(widget.url, widget.headers).whenComplete(() {
      if (!mounted || _completed || _disposed) return;
      setState(() => _ready = true);
      _log.info('WebView', '[Silent] request prepared, building WebView');
    });
  }

  @override
  void dispose() {
    _log.info('WebView', '[Silent] dispose mounted=${mounted} controller=${_controller != null}');
    _disposed = true;
    _timeoutTimer?.cancel();
    _settleTimer?.cancel();
    final controller = _controller;
    if (controller != null) unregisterWebViewController(controller);
    _controller = null;
    super.dispose();
  }

  void _handleTimeout() {
    _log.warning('WebView', '[Silent] timeout readInProgress=${_readInProgress}');
    _timedOut = true;
    if (!_readInProgress) _complete(null);
  }

  void _complete(CloudflareBrowserResult? result) {
    if (_completed || _disposed) return;
    if (result == null && _readInProgress) return;
    _completed = true;
    _timeoutTimer?.cancel();
    _settleTimer?.cancel();
    final controller = _controller;
    if (controller != null) unregisterWebViewController(controller);
    widget.onComplete(result);
  }

  void _scheduleRead() {
    if (_completed || _disposed) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(widget.settleDelay, _readPage);
  }

  Future<void> _readPage() async {
    if (_completed || _disposed || _readInProgress) return;
    final controller = _controller;
    if (controller == null) {
      _log.warning('WebView', '[Silent] read skipped: controller is null');
      return;
    }
    _readInProgress = true;
    _log.info('WebView', '[Silent] evaluate html start url=${_currentUrl}');
    try {
      final htmlResult = await controller.evaluateJavascript(
        source:
            'document.documentElement == null ? "" : document.documentElement.outerHTML',
      );
      final html = htmlResult?.toString() ?? '';
      _log.info('WebView', '[Silent] html length=${html.length}');
      if (html.trim().isEmpty || _completed || _disposed) return;
      final text = _extractHtmlText(html);
      _log.info('WebView', '[Silent] derived text length=${text.length}');
      final usable = _isUsableScrapeHtml(
        html,
        text,
        isHtmlReady: widget.isHtmlReady,
      );
      if (usable) {
        _readyStreak++;
      } else {
        _readyStreak = 0;
      }
      _log.info(
        'WebView',
        '[Silent] snapshot html=${html.length} text=${text.length} '
            'readyMode=${widget.isHtmlReady != null ? 'xpath' : 'generic'} '
            'usable=$usable streak=$_readyStreak',
      );
      if (_readyStreak >= 2) {
        _complete(
          CloudflareBrowserResult(
            html: html,
            finalUrl: _currentUrl,
            usedSilentMode: true,
          ),
        );
      }
    } catch (e, stackTrace) {
      _log.warning('WebView', '[Silent] evaluate html failed: ${e}');
      _log.info('WebView', '[Silent] evaluate stack: ${stackTrace}');
    } finally {
      _readInProgress = false;
      if (_timedOut && !_completed && !_disposed) {
        _complete(null);
      } else if (!_completed && !_disposed) {
        _scheduleRead();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(widget.url),
        headers: _buildWebViewHeaders(widget.headers),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        supportZoom: false,
        userAgent: _extractUserAgent(widget.headers),
      ),
      onWebViewCreated: (controller) {
        _log.info('WebView', '[Silent] onWebViewCreated disposed=${_disposed}');
        if (_disposed) return;
        _controller = controller;
        registerWebViewController(controller);
      },
      onLoadStart: (_, loadedUrl) {
        _log.info('WebView', '[Silent] loadStart url=${loadedUrl} disposed=${_disposed}');
        if (_disposed) return;
        _currentUrl = loadedUrl?.toString() ?? _currentUrl;
      },
      onLoadStop: (_, loadedUrl) {
        _log.info('WebView', '[Silent] loadStop url=${loadedUrl} disposed=${_disposed}');
        if (_disposed) return;
        _currentUrl = loadedUrl?.toString() ?? _currentUrl;
        _scheduleRead();
      },
      onProgressChanged: (_, progress) {
        if (_disposed) return;
        if (progress >= 100) _scheduleRead();
      },
      onReceivedError: (_, request, error) {
        _log.warning('WebView', '[Silent] loadError url=${request.url} error=${error.description}');
      },
    );
  }
}

class CloudflareBrowserDialog extends StatefulWidget {
  final String initialUrl;
  final Map<String, String>? headers;
  final bool Function(String html)? isHtmlReady;

  const CloudflareBrowserDialog({
    super.key,
    required this.initialUrl,
    this.headers,
    this.isHtmlReady,
  });

  @override
  State<CloudflareBrowserDialog> createState() =>
      _CloudflareBrowserDialogState();
}

class _CloudflareBrowserDialogState extends State<CloudflareBrowserDialog> {
  InAppWebViewController? _controller;
  var _disposed = false;
  String _currentUrl = '';
  bool _isReadingHtml = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _log.info('WebView', '[Interactive] init url=${widget.initialUrl}');
  }

  @override
  void dispose() {
    _disposed = true;
    _log.info('WebView', '[Interactive] dispose controller=${_controller != null}');
    final controller = _controller;
    if (controller != null) unregisterWebViewController(controller);
    _controller = null;
    super.dispose();
  }

  void _closeDialog() {
    if (_isReadingHtml || _disposed) return;
    _isReadingHtml = true;
    _log.info('WebView', '[Interactive] close requested');
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reload() async {
    if (_disposed) return;
    setState(() => _error = null);
    _log.info('WebView', '[Interactive] reload requested');
    await _controller?.reload();
  }

  Future<void> _useCurrentPage() async {
    final controller = _controller;
    if (controller == null || _disposed) return;
    setState(() {
      _isReadingHtml = true;
      _error = null;
    });
    _log.info('WebView', '[Interactive] read html start url=${_currentUrl}');
    try {
      final result = await controller.evaluateJavascript(
        source:
            'document.documentElement == null ? "" : document.documentElement.outerHTML',
      );
      final html = result?.toString() ?? '';
      _log.info('WebView', '[Interactive] html length=${html.length}');
      if (html.trim().isEmpty) {
        if (mounted) setState(() => _error = '当前页面 HTML 为空，请等待页面加载完成后重试');
        return;
      }
      if (widget.isHtmlReady != null && !widget.isHtmlReady!(html)) {
        if (mounted) {
          setState(() => _error = '当前页面尚未出现目标标题，请完成验证并等待内容加载后重试');
        }
        _log.info('WebView', '[Interactive] XPath title is not ready');
        return;
      }
      if (!mounted || _disposed) return;
      Navigator.of(context).pop(
        CloudflareBrowserResult(html: html, finalUrl: _currentUrl),
      );
    } catch (e, stackTrace) {
      _log.warning('WebView', '[Interactive] read html failed: ${e}');
      _log.info('WebView', '[Interactive] read html stack: ${stackTrace}');
      if (mounted) setState(() => _error = '读取当前页面失败：$e');
    } finally {
      if (mounted && !_disposed) setState(() => _isReadingHtml = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 980,
        height: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security_outlined,
                    color: AppTheme.getPrimaryColor(context), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cloudflare 浏览器验证',
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _isReadingHtml ? null : _reload,
                  icon: Icon(Icons.refresh,
                      color: AppTheme.getTextSecondary(context)),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: _isReadingHtml ? null : _closeDialog,
                  icon: Icon(Icons.close,
                      color: AppTheme.getTextSecondary(context)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '请在内置浏览器中完成站点验证，页面加载到目标内容后点击“使用当前页面”。',
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            _buildAddressBar(),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.getSurfaceColor(context)
                        .withValues(alpha: 0.32),
                    border: Border.all(
                      color: AppTheme.getBorderColor(context)
                          .withValues(alpha: 0.45),
                    ),
                  ),
                  child: Stack(
                    children: [
                      InAppWebView(
                        initialUrlRequest: URLRequest(
                          url: WebUri(widget.initialUrl),
                          headers: _buildWebViewHeaders(widget.headers),
                        ),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          supportZoom: true,
                          userAgent: _extractUserAgent(widget.headers),
                        ),
                        onWebViewCreated: (controller) {
                          if (_disposed) return;
                          _log.info('WebView', '[Interactive] onWebViewCreated');
                          _controller = controller;
                          registerWebViewController(controller);
                        },
                        onLoadStart: (controller, url) {
                          if (_disposed) return;
                          _currentUrl = url?.toString() ?? _currentUrl;
                          _log.info('WebView', '[Interactive] loadStart url=' + _currentUrl);
                        },
                        onReceivedError: (controller, request, error) {
                          _log.warning('WebView', '[Interactive] loadError url=' + request.url.toString() + ' error=' + error.description);
                          if (_disposed) return;
                          if (request.isForMainFrame ?? false) _error = error.description;
                        },
                      ),
                    ],
                  ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style:
                    const TextStyle(color: AppTheme.errorColor, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isReadingHtml ? null : _closeDialog,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isReadingHtml ? null : _useCurrentPage,
                  icon: _isReadingHtml
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.getPrimaryColor(context),
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(_isReadingHtml ? '读取中' : '使用当前页面'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.getPrimaryColor(context)
                        .withValues(alpha: 0.15),
                    foregroundColor: AppTheme.getPrimaryColor(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.getInputFillColor(context),
        borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
        border: Border.all(
          color: AppTheme.getBorderColor(context).withValues(alpha: 0.35),
        ),
      ),
      child: SelectableText(
        _currentUrl,
        maxLines: 1,
        style: TextStyle(
          color: AppTheme.getTextSecondary(context),
          fontSize: 12,
        ),
      ),
    );
  }


}

Map<String, String>? _buildWebViewHeaders(Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) return null;
  return {
    for (final entry in headers.entries)
      if (entry.value.trim().isNotEmpty) entry.key: entry.value,
  };
}

String? _extractUserAgent(Map<String, String>? headers) {
  if (headers == null) return null;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'user-agent') {
      final value = entry.value.trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

Future<void> _prepareWebViewRequest(
  String url,
  Map<String, String>? headers,
) async {
  final cookieHeader = _extractHeader(headers, 'cookie');
  if (cookieHeader == null || cookieHeader.isEmpty) return;
  final uri = WebUri(url);
  final manager = CookieManager.instance();
  for (final rawCookie in cookieHeader.split(';')) {
    final cookie = rawCookie.trim();
    if (cookie.isEmpty) continue;
    final separator = cookie.indexOf('=');
    if (separator <= 0) continue;
    final name = cookie.substring(0, separator).trim();
    final value = cookie.substring(separator + 1).trim();
    if (name.isEmpty) continue;
    try {
      await manager.setCookie(url: uri, name: name, value: value);
    } catch (_) {}
  }
}

String? _extractHeader(Map<String, String>? headers, String name) {
  if (headers == null) return null;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value.trim();
    }
  }
  return null;
}

List<Map<String, dynamic>> _buildChromeCookies(String url, String? cookieHeader) {
  if (cookieHeader == null || cookieHeader.trim().isEmpty) return [];
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return [];
  final cookies = <Map<String, dynamic>>[];
  for (final part in cookieHeader.split(';')) {
    final separator = part.indexOf('=');
    if (separator <= 0) continue;
    final name = part.substring(0, separator).trim();
    final value = part.substring(separator + 1).trim();
    if (name.isEmpty) continue;
    cookies.add({
      'name': name,
      'value': value,
      'domain': uri.host,
      'path': '/',
      'secure': uri.scheme == 'https',
    });
  }
  return cookies;
}

String _extractHtmlText(String html) {
  try {
    return html_parser.parse(html).body?.text ?? '';
  } catch (_) {
    return '';
  }
}

bool _isUsableScrapeHtml(
  String html,
  String text, {
  bool Function(String html)? isHtmlReady,
}) {
  final trimmedHtml = html.trim();
  final trimmedText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmedHtml.length < 300) return false;
  if (looksLikeCloudflareChallenge(trimmedHtml) ||
      looksLikeCloudflareChallenge(trimmedText)) {
    return false;
  }
  if (isHtmlReady != null) return isHtmlReady(trimmedHtml);
  if (looksLikeClientRenderedPage(trimmedHtml)) return false;
  if (trimmedText.length >= 80) return true;
  return RegExp(r'<(article|main|img|a)\b', caseSensitive: false)
      .hasMatch(trimmedHtml);
}
