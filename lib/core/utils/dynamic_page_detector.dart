import 'package:html/parser.dart' as html_parser;

/// 判断 HTML 是否更像尚未完成 JavaScript 渲染的前端应用壳。
bool looksLikeClientRenderedPage(String html) {
  final document = html_parser.parse(html);
  final body = document.body;
  if (body == null) return false;

  final hasAppRoot = body.querySelector('#app') != null ||
      body.querySelector('#root') != null ||
      body.querySelector('[data-reactroot]') != null;
  if (!hasAppRoot) return false;

  body
      .querySelectorAll('script, style, noscript')
      .forEach((element) => element.remove());
  final bodyText = body.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final selector in ['h1', 'h2', 'h3']) {
    final hasTitle = body.querySelectorAll(selector).any(
          (element) =>
              element.text.replaceAll(RegExp(r'\s+'), ' ').trim().length >= 4,
        );
    if (hasTitle) return false;
  }

  // 有实际标题时视为已完成渲染；没有标题且正文很短时，通常只是应用壳。
  return bodyText.length < 120;
}
