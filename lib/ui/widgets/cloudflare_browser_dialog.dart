import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/app_theme.dart';

class CloudflareBrowserResult {
  final String html;
  final String finalUrl;

  const CloudflareBrowserResult({
    required this.html,
    required this.finalUrl,
  });
}

Future<CloudflareBrowserResult?> showCloudflareBrowserDialog({
  required BuildContext context,
  required String url,
}) {
  return showGlassDialog<CloudflareBrowserResult>(
    context: context,
    barrierDismissible: false,
    child: CloudflareBrowserDialog(initialUrl: url),
  );
}

class CloudflareBrowserDialog extends StatefulWidget {
  final String initialUrl;

  const CloudflareBrowserDialog({
    super.key,
    required this.initialUrl,
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
    _controller?.dispose();
    _controller = null;
    super.dispose();
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
                  onPressed:
                      _isReadingHtml ? null : () => Navigator.of(context).pop(),
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
                        initialUrlRequest:
                            URLRequest(url: WebUri(widget.initialUrl)),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          transparentBackground: true,
                          supportZoom: true,
                        ),
                        onWebViewCreated: (controller) {
                          _controller = controller;
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
                  onPressed:
                      _isReadingHtml ? null : () => Navigator.of(context).pop(),
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
