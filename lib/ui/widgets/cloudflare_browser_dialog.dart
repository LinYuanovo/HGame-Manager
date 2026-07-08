import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/utils/cloudflare_challenge.dart';
import '../../core/utils/webview2_lifecycle.dart';
import '../theme/app_theme.dart';

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
}) async {
  final silentResult = await tryReadCloudflareBrowserPageSilently(
    context: context,
    url: url,
    headers: headers,
  );
  if (silentResult != null) return silentResult;
  if (!context.mounted) return null;
  return showCloudflareBrowserDialog(
    context: context,
    url: url,
    headers: headers,
  );
}

Future<CloudflareBrowserResult?> tryReadCloudflareBrowserPageSilently({
  BuildContext? context,
  required String url,
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 12),
  Duration settleDelay = const Duration(milliseconds: 1200),
}) async {
  if (context != null && context.mounted) {
    final overlayResult = await _tryReadCloudflareBrowserPageInOverlay(
      context: context,
      url: url,
      headers: headers,
      timeout: timeout,
      settleDelay: settleDelay,
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
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;

  final completer = Completer<CloudflareBrowserResult?>();
  OverlayEntry? entry;
  void complete(CloudflareBrowserResult? result) {
    if (completer.isCompleted) return;
    entry?.remove();
    completer.complete(result);
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
              onComplete: complete,
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(entry);
  return completer.future;
}

Future<CloudflareBrowserResult?> showCloudflareBrowserDialog({
  required BuildContext context,
  required String url,
  Map<String, String>? headers,
}) async {
  await _prepareWebViewRequest(url, headers);
  if (!context.mounted) return null;
  return showGlassDialog<CloudflareBrowserResult>(
    context: context,
    barrierDismissible: false,
    child: CloudflareBrowserDialog(initialUrl: url, headers: headers),
  );
}

class _SilentCloudflareWebView extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final Duration timeout;
  final Duration settleDelay;
  final ValueChanged<CloudflareBrowserResult?> onComplete;

  const _SilentCloudflareWebView({
    required this.url,
    required this.headers,
    required this.timeout,
    required this.settleDelay,
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
  Timer? _pollTimer;
  var _currentUrl = '';
  var _ready = false;
  var _completed = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _timeoutTimer = Timer(widget.timeout, () => _complete(null));
    _prepareWebViewRequest(widget.url, widget.headers).whenComplete(() {
      if (!mounted || _completed) return;
      setState(() => _ready = true);
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _readPage(),
      );
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _settleTimer?.cancel();
    _pollTimer?.cancel();
    final controller = _controller;
    if (controller != null) {
      unregisterWebViewController(controller);
      unawaited(disposeWebViewController(controller));
    }
    super.dispose();
  }

  Future<void> _complete(CloudflareBrowserResult? result) async {
    if (_completed) return;
    _completed = true;
    _timeoutTimer?.cancel();
    _settleTimer?.cancel();
    _pollTimer?.cancel();
    final controller = _controller;
    if (controller != null) {
      unregisterWebViewController(controller);
      _controller = null;
      await disposeWebViewController(controller);
    }
    widget.onComplete(result);
  }

  void _scheduleRead() {
    _settleTimer?.cancel();
    _settleTimer = Timer(widget.settleDelay, _readPage);
  }

  Future<void> _readPage() async {
    if (_completed) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      final htmlResult = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      final textResult = await controller.evaluateJavascript(
        source: 'document.body ? document.body.innerText : ""',
      );
      final html = htmlResult?.toString() ?? '';
      final text = textResult?.toString() ?? '';
      if (_isUsableScrapeHtml(html, text)) {
        await _complete(
          CloudflareBrowserResult(
            html: html,
            finalUrl: _currentUrl,
            usedSilentMode: true,
          ),
        );
      }
    } catch (_) {}
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
        _controller = controller;
        registerWebViewController(controller);
      },
      onLoadStart: (_, loadedUrl) {
        _currentUrl = loadedUrl?.toString() ?? _currentUrl;
      },
      onLoadStop: (_, loadedUrl) {
        _currentUrl = loadedUrl?.toString() ?? _currentUrl;
        _scheduleRead();
      },
      onProgressChanged: (_, progress) {
        if (progress >= 100) _scheduleRead();
      },
      onReceivedError: (_, __, ___) {},
    );
  }
}

class CloudflareBrowserDialog extends StatefulWidget {
  final String initialUrl;
  final Map<String, String>? headers;

  const CloudflareBrowserDialog({
    super.key,
    required this.initialUrl,
    this.headers,
  });

  @override
  State<CloudflareBrowserDialog> createState() =>
      _CloudflareBrowserDialogState();
}

class _CloudflareBrowserDialogState extends State<CloudflareBrowserDialog> {
  InAppWebViewController? _controller;
  String _currentUrl = '';
  int _progress = 0;
  bool _isLoading = true;
  bool _isReadingHtml = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
  }

  @override
  void dispose() {
    unawaited(_disposeWebView());
    _controller = null;
    super.dispose();
  }

  Future<void> _disposeWebView() async {
    final controller = _controller;
    if (controller == null) return;
    unregisterWebViewController(controller);
    _controller = null;
    await disposeWebViewController(controller);
  }

  Future<void> _closeDialog() async {
    if (_isReadingHtml) return;
    setState(() => _isReadingHtml = true);
    await _disposeWebView();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reload() async {
    setState(() => _error = null);
    await _controller?.reload();
  }

  Future<void> _useCurrentPage() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _isReadingHtml = true;
      _error = null;
    });
    try {
      final result = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      final html = result?.toString() ?? '';
      if (html.trim().isEmpty) {
        setState(() => _error = '当前页面 HTML 为空，请等待页面加载完成后重试');
        return;
      }
      await _disposeWebView();
      if (!mounted) return;
      Navigator.of(context).pop(
        CloudflareBrowserResult(html: html, finalUrl: _currentUrl),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '读取当前页面失败：$e');
    } finally {
      if (mounted) {
        setState(() => _isReadingHtml = false);
      }
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
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(GlassConstants.radiusMedium),
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
                          transparentBackground: true,
                          supportZoom: true,
                          userAgent: _extractUserAgent(widget.headers),
                        ),
                        onWebViewCreated: (controller) {
                          _controller = controller;
                          registerWebViewController(controller);
                        },
                        onLoadStart: (controller, url) {
                          setState(() {
                            _isLoading = true;
                            _currentUrl = url?.toString() ?? _currentUrl;
                          });
                        },
                        onLoadStop: (controller, url) {
                          setState(() {
                            _isLoading = false;
                            _progress = 100;
                            _currentUrl = url?.toString() ?? _currentUrl;
                          });
                        },
                        onProgressChanged: (controller, progress) {
                          setState(() {
                            _progress = progress;
                            _isLoading = progress < 100;
                          });
                        },
                        onReceivedError: (controller, request, error) {
                          if (request.isForMainFrame ?? false) {
                            setState(() => _error = error.description);
                          }
                        },
                      ),
                      if (_isLoading) _buildProgressOverlay(),
                    ],
                  ),
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

  Widget _buildProgressOverlay() {
    return Align(
      alignment: Alignment.topCenter,
      child: LinearProgressIndicator(
        value: _progress <= 0 || _progress >= 100 ? null : _progress / 100,
        color: AppTheme.getPrimaryColor(context),
        backgroundColor:
            AppTheme.getBorderColor(context).withValues(alpha: 0.25),
        minHeight: 3,
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

bool _isUsableScrapeHtml(String html, String text) {
  final trimmedHtml = html.trim();
  final trimmedText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmedHtml.length < 300) return false;
  if (looksLikeCloudflareChallenge(trimmedHtml) ||
      looksLikeCloudflareChallenge(trimmedText)) {
    return false;
  }
  if (trimmedText.length >= 80) return true;
  return RegExp(r'<(article|main|img|a)\b', caseSensitive: false)
      .hasMatch(trimmedHtml);
}
