import 'package:flutter_inappwebview/flutter_inappwebview.dart';

final Set<InAppWebViewController> _controllers = {};
final Set<HeadlessInAppWebView> _headlessWebViews = {};
bool _hasCreatedWebView = false;

bool get hasCreatedWebView => _hasCreatedWebView;

void registerWebViewController(InAppWebViewController controller) {
  _hasCreatedWebView = true;
  _controllers.add(controller);
}

void unregisterWebViewController(InAppWebViewController controller) {
  _controllers.remove(controller);
}

void registerHeadlessWebView(HeadlessInAppWebView webView) {
  _hasCreatedWebView = true;
  _headlessWebViews.add(webView);
}

void unregisterHeadlessWebView(HeadlessInAppWebView webView) {
  _headlessWebViews.remove(webView);
}

Future<void> disposeRegisteredWebViews() async {
  final controllers = List<InAppWebViewController>.from(_controllers);
  final headlessWebViews = List<HeadlessInAppWebView>.from(_headlessWebViews);
  _controllers.clear();
  _headlessWebViews.clear();

  for (final controller in controllers) {
    await disposeWebViewController(controller);
  }
  for (final webView in headlessWebViews) {
    await _disposeHeadlessWebView(webView);
  }
}

Future<void> _disposeHeadlessWebView(HeadlessInAppWebView webView) async {
  await disposeWebViewController(webView.webViewController);
  try {
    await webView.dispose();
  } catch (_) {}
}

Future<void> disposeWebViewController(
    InAppWebViewController? controller) async {
  if (controller == null) return;
  try {
    await controller.stopLoading();
  } catch (_) {}
  try {
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
  } catch (_) {}
  await Future<void>.delayed(const Duration(milliseconds: 350));
  try {
    controller.dispose();
  } catch (_) {}
}
