import 'package:html/dom.dart';

class RichTextExtraction {
  final String plainText;
  final String html;
  final List<String> imageUrls;

  const RichTextExtraction({
    required this.plainText,
    required this.html,
    required this.imageUrls,
  });

  bool get isNotEmpty => plainText.trim().isNotEmpty || imageUrls.isNotEmpty;
}

enum _TokenType { text, breakLine, image }

class _Token {
  final _TokenType type;
  final String value;

  _Token(this.type, this.value);
}

class RichTextExtractor {
  static final _startMarker = RegExp(r'(概要|游戏介绍|游戏简介|简介)\s*[：:]?');
  static final _stopMarker = RegExp(
    r'^\s*(游戏特点|更新内容|更新日志|链接|下载链接|解压码|解压密码)\s*[：:]?.*$',
  );

  static RichTextExtraction extractDescription(
    Element container,
    String baseUrl, {
    bool preferSection = true,
    bool includeBeforeStart = true,
  }) {
    var extraction = _extract(
      container,
      baseUrl,
      preferSection: preferSection,
      includeBeforeStart: includeBeforeStart,
    );
    if (preferSection && !extraction.isNotEmpty) {
      extraction = _extract(container, baseUrl, preferSection: false);
    }
    return extraction;
  }

  static List<String> extractImageUrls(Element container, String baseUrl) {
    final result = <String>[];
    final seen = <String>{};
    for (final img in container.querySelectorAll('img')) {
      final src = resolveImageUrl(img, baseUrl);
      if (src != null && seen.add(src)) {
        result.add(src);
      }
    }
    return result;
  }

  static String? resolveImageUrl(Element? img, String baseUrl) {
    if (img == null) return null;
    final raw = img.attributes['data-original'] ??
        img.attributes['data-src'] ??
        img.attributes['zoomfile'] ??
        img.attributes['file'] ??
        img.attributes['src'] ??
        '';
    final normalized = _resolveUrl(raw.trim(), baseUrl);
    if (normalized == null || !_isContentImage(normalized)) return null;
    return normalized;
  }

  static RichTextExtraction _extract(
    Element container,
    String baseUrl, {
    required bool preferSection,
    bool includeBeforeStart = false,
  }) {
    final state = _ExtractionState(
      baseUrl,
      collecting: !preferSection || includeBeforeStart,
      includeBeforeStart: includeBeforeStart,
    );
    for (final node in container.nodes) {
      _walk(node, state, preferSection: preferSection);
      if (state.stopped) break;
    }
    return _buildExtraction(state.tokens);
  }

  static void _walk(
    Node node,
    _ExtractionState state, {
    required bool preferSection,
  }) {
    if (state.stopped) return;

    if (node is Text) {
      _appendText(node.text, state, preferSection: preferSection);
      return;
    }

    if (node is! Element) return;

    final tag = node.localName ?? '';
    if (tag == 'script' || tag == 'style' || tag == 'noscript') return;
    if (tag == 'img') {
      if (!state.collecting && preferSection) return;
      final src = resolveImageUrl(node, state.baseUrl);
      if (src != null && state.imageUrls.add(src)) {
        state.tokens.add(_Token(_TokenType.image, src));
        state.hasMeaningfulContent = true;
      }
      return;
    }
    if (tag == 'br') {
      if (state.collecting) state.tokens.add(_Token(_TokenType.breakLine, ''));
      return;
    }

    for (final child in node.nodes) {
      _walk(child, state, preferSection: preferSection);
      if (state.stopped) break;
    }

    if (_isBlockTag(tag) && state.collecting && !state.stopped) {
      state.tokens.add(_Token(_TokenType.breakLine, ''));
    }
  }

  static void _appendText(
    String rawText,
    _ExtractionState state, {
    required bool preferSection,
  }) {
    var text = rawText.replaceAll('\u00A0', ' ').trim();
    if (text.isEmpty) return;

    if (preferSection && !state.collecting) {
      final start = _startMarker.firstMatch(text);
      if (start == null) return;
      state.collecting = true;
      state.foundStart = true;
      text = text.substring(start.end).trim();
      if (text.isEmpty) return;
    }

    if (preferSection && state.collecting) {
      final startAtLineBeginning = RegExp(
        r'^\s*(概要|游戏介绍|游戏简介|简介)\s*[：:]?',
      ).firstMatch(text);
      if (startAtLineBeginning != null) {
        state.foundStart = true;
        text = text.substring(startAtLineBeginning.end).trim();
        if (text.isEmpty) return;
      }
    }

    if (!state.hasMeaningfulContent && _isDownloadNoiseLine(text)) {
      return;
    }

    final stop = preferSection ? _stopMarker.firstMatch(text) : null;
    if (stop != null) {
      if (!state.hasMeaningfulContent) {
        return;
      }
      final beforeStop = text.substring(0, stop.start).trim();
      if (beforeStop.isNotEmpty) {
        state.tokens.add(_Token(_TokenType.text, beforeStop));
        state.hasMeaningfulContent = true;
      }
      state.stopped = true;
      return;
    }

    if (state.collecting) {
      state.tokens.add(_Token(_TokenType.text, text));
      state.hasMeaningfulContent = true;
    }
  }

  static RichTextExtraction _buildExtraction(List<_Token> tokens) {
    final plain = StringBuffer();
    final html = StringBuffer();
    final paragraph = <String>[];
    final imageUrls = <String>[];

    void flushParagraph() {
      final text = paragraph.join('');
      paragraph.clear();
      final trimmed = text.replaceAll(RegExp(r'(<br>)+$'), '').trim();
      if (trimmed.isNotEmpty) {
        html.write('<p>$trimmed</p>');
      }
    }

    for (final token in tokens) {
      switch (token.type) {
        case _TokenType.text:
          if (plain.isNotEmpty && !plain.toString().endsWith('\n')) {
            plain.write('');
          }
          plain.write(token.value);
          paragraph.add(_escapeHtml(token.value));
          break;
        case _TokenType.breakLine:
          if (plain.isNotEmpty && !plain.toString().endsWith('\n')) {
            plain.write('\n');
          }
          paragraph.add('<br>');
          break;
        case _TokenType.image:
          flushParagraph();
          if (plain.isNotEmpty && !plain.toString().endsWith('\n')) {
            plain.write('\n');
          }
          plain.write('[图片:${token.value}]\n');
          html.write('<p><img src="${_escapeHtml(token.value)}"></p>');
          imageUrls.add(token.value);
          break;
      }
    }
    flushParagraph();

    return RichTextExtraction(
      plainText: _cleanPlainText(plain.toString()),
      html: html.toString().trim(),
      imageUrls: imageUrls,
    );
  }

  static String _cleanPlainText(String text) {
    return text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static bool _isBlockTag(String tag) {
    return const {
      'p',
      'div',
      'section',
      'article',
      'li',
      'tr',
      'td',
      'table',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
    }.contains(tag);
  }

  static bool _isContentImage(String url) {
    final lower = url.toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.startsWith('data:')) return false;
    if (lower.endsWith('.svg') || lower.endsWith('.ico')) return false;
    if (lower.contains('static/image')) return false;
    if (lower.contains('/smilies/') || lower.contains('smiley')) return false;
    if (lower.contains('/avatar/')) return false;
    if (lower.contains('/logos') || lower.contains('/logo')) return false;
    if (lower.contains('template/acgi_b1/images')) return false;
    return true;
  }

  static bool _isDownloadNoiseLine(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed.contains('通过网盘分享的文件')) return true;
    if (trimmed.contains('来自百度网盘')) return true;
    if (trimmed.contains('提取码') && trimmed.contains('网盘')) return true;
    if (RegExp(r'^网页链接\([^)]+\)').hasMatch(trimmed)) return true;
    if (RegExp(r'^(?:链接|网页链接)\s*[：:]?\s*https?://').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^(?:提取码|访问码|解压码|解压密码)\s*[：:]?\s*\S+').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^https?://(?:pan|drive|jmj|feimaoyun|fxpan|quark|cloud)')
        .hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  static String? _resolveUrl(String raw, String baseUrl) {
    if (raw.isEmpty) return null;
    if (raw.startsWith('//')) return 'https:$raw';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = Uri.tryParse(baseUrl);
    if (base == null) return raw;
    return base.resolve(raw).toString();
  }
}

class _ExtractionState {
  final String baseUrl;
  final List<_Token> tokens = [];
  final Set<String> imageUrls = {};
  bool collecting;
  final bool includeBeforeStart;
  bool stopped = false;
  bool foundStart = false;
  bool hasMeaningfulContent = false;

  _ExtractionState(
    this.baseUrl, {
    required this.collecting,
    this.includeBeforeStart = false,
  });
}
