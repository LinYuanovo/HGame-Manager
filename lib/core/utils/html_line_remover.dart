import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// HTML 中"行"级内容删除工具。
///
/// 以 `<br>` 或文本节点内换行切分出的"行"为最小单位删除命中内容，
/// 而不是按顶层节点整块删除。
///
/// 设计动机：部分站点的 `intro_html` 会把整段简介塞进同一个 `<p>`、仅用 `<br>` 分行。
/// 若按顶层节点判断（节点 text 含下载链接就整个删掉），会把简介正文一并清除，
/// 详情页只剩图片。
class HtmlLineRemover {
  HtmlLineRemover._();

  static const Set<String> _blockLikeTags = {
    'div', 'p', 'ul', 'ol', 'li', 'table', 'thead', 'tbody', 'tr', 'td', 'th',
    'section', 'article', 'aside', 'blockquote', 'pre', 'figure', 'figcaption',
    'header', 'footer', 'main', 'form', 'fieldset', 'dl', 'dt', 'dd',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  };

  /// 从 [html] 中删除命中的行，返回处理后的 HTML；未删除任何内容时返回 null。
  ///
  /// - [isRemovableLine]：判断一行文本是否需要删除。
  /// - [removableLabels]：可随链接行一并删除的"独占一行标签"集合（如「百度网盘」）。
  /// - [normalizeLabel]：把一行文本归一化为标签后再与 [removableLabels] 比对。
  /// - [triggersLabelCleanup]：仅当该行命中此判断时才回溯删除标签行（默认全部命中行都回溯）。
  static String? removeMatchedLines(
    String html, {
    required bool Function(String lineText) isRemovableLine,
    Set<String> removableLabels = const <String>{},
    String Function(String lineText)? normalizeLabel,
    bool Function(String lineText)? triggersLabelCleanup,
  }) {
    final doc = html_parser.parse(html);
    final body = doc.body;
    if (body == null) return null;

    final changed = _stripElement(
      body,
      isRemovableLine: isRemovableLine,
      removableLabels: removableLabels,
      normalizeLabel: normalizeLabel,
      triggersLabelCleanup: triggersLabelCleanup,
    );
    if (!changed) return null;
    return body.innerHtml;
  }

  static bool _stripElement(
    dom.Element element, {
    required bool Function(String lineText) isRemovableLine,
    required Set<String> removableLabels,
    required String Function(String lineText)? normalizeLabel,
    required bool Function(String lineText)? triggersLabelCleanup,
  }) {
    final segments = <List<dom.Node>>[
      []
    ];
    // terminators[i] 为结束第 i 行的 <br>（最后一行没有）
    final terminators = <dom.Element?>[null];
    for (final node in element.nodes.toList()) {
      if (node is dom.Element && node.localName == 'br') {
        terminators[terminators.length - 1] = node;
        segments.add(<dom.Node>[]);
        terminators.add(null);
      } else {
        segments.last.add(node);
      }
    }

    final removed = <int>{};
    var changed = false;

    String segmentText(List<dom.Node> segment) =>
        segment.map((n) => n.text ?? '').join();

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.isEmpty) continue;

      final hasBlockChild = segment.any((n) =>
          n is dom.Element && _blockLikeTags.contains(n.localName));
      if (hasBlockChild) {
        for (final n in segment) {
          if (n is! dom.Element) continue;
          if (!_stripElement(
            n,
            isRemovableLine: isRemovableLine,
            removableLabels: removableLabels,
            normalizeLabel: normalizeLabel,
            triggersLabelCleanup: triggersLabelCleanup,
          )) {
            continue;
          }
          changed = true;
          // 内容被清空的块级元素整体移除，避免留下空壳
          if (n.localName != 'body' &&
              n.querySelector('img') == null &&
              n.text.trim().isEmpty) {
            n.remove();
          }
        }
        continue;
      }

      // 含图片的行一律保留，避免误删配图
      final hasImage = segment.any((n) =>
          n is dom.Element &&
          (n.localName == 'img' || n.querySelector('img') != null));
      if (hasImage) continue;

      final text = segmentText(segment);
      if (text.trim().isEmpty) continue;

      // 文本节点内部还带换行时，先按换行做子行过滤，避免整段被当作一行删掉
      if (_stripMatchedTextLines(
        segment,
        isRemovableLine: isRemovableLine,
        removableLabels: removableLabels,
        normalizeLabel: normalizeLabel,
        triggersLabelCleanup: triggersLabelCleanup,
      )) {
        changed = true;
        continue;
      }

      if (isRemovableLine(text)) {
        _removeSegment(segment, terminators[i]);
        removed.add(i);
        changed = true;
        if (removableLabels.isEmpty || normalizeLabel == null) continue;
        if (triggersLabelCleanup != null &&
            !triggersLabelCleanup(text.trim())) {
          continue;
        }
        // 标签独占一行的格式：链接行被删后，紧邻的标签行一并删除
        for (var j = i - 1; j >= 0; j--) {
          if (removed.contains(j)) continue;
          final prev = segments[j];
          if (prev.isEmpty) continue;
          final prevText = segmentText(prev).trim();
          if (prevText.isEmpty) continue;
          final prevLabel = normalizeLabel(prevText);
          if (prevLabel.isNotEmpty && removableLabels.contains(prevLabel)) {
            _removeSegment(prev, terminators[j]);
            removed.add(j);
          }
          break;
        }
      }
    }

    return changed;
  }

  static void _removeSegment(List<dom.Node> segment, dom.Element? terminator) {
    for (final n in segment) {
      n.remove();
    }
    terminator?.remove();
  }

  /// 收集行内的文本节点（跳过 `<script>/<style>`，块级子元素由外层递归处理）
  static void _collectTextNodes(List<dom.Node> nodes, List<dom.Text> out) {
    for (final node in nodes) {
      if (node is dom.Text) {
        out.add(node);
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName;
      if (tag == 'script' || tag == 'style' || tag == 'noscript') continue;
      if (_blockLikeTags.contains(tag)) continue;
      _collectTextNodes(node.nodes.toList(), out);
    }
  }

  /// 对行内文本节点中以 `\n` 分隔的子行做过滤（源 HTML 未使用 `<br>` 分行的情况），
  /// 过滤规则与 `_stripElement` 的行级逻辑保持一致（含标签行回溯删除）。
  static bool _stripMatchedTextLines(
    List<dom.Node> segment, {
    required bool Function(String lineText) isRemovableLine,
    required Set<String> removableLabels,
    required String Function(String lineText)? normalizeLabel,
    required bool Function(String lineText)? triggersLabelCleanup,
  }) {
    final textNodes = <dom.Text>[];
    _collectTextNodes(segment, textNodes);
    final multiline =
        textNodes.where((n) => n.data.contains('\n')).toList(growable: false);
    if (multiline.isEmpty) return false;

    // 展平成"行"清单，顺序与源文本一致
    final owners = <dom.Text>[];
    final lines = <String>[];
    for (final node in multiline) {
      for (final line in node.data.split('\n')) {
        owners.add(node);
        lines.add(line);
      }
    }

    final dropped = List<bool>.filled(lines.length, false);
    var changed = false;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty || !isRemovableLine(trimmed)) continue;
      dropped[i] = true;
      changed = true;

      if (removableLabels.isEmpty || normalizeLabel == null) continue;
      if (triggersLabelCleanup != null && !triggersLabelCleanup(trimmed)) {
        continue;
      }
      for (var j = i - 1; j >= 0; j--) {
        if (dropped[j]) continue;
        final prevTrimmed = lines[j].trim();
        if (prevTrimmed.isEmpty) continue;
        final prevLabel = normalizeLabel(prevTrimmed);
        if (prevLabel.isNotEmpty && removableLabels.contains(prevLabel)) {
          dropped[j] = true;
        }
        break;
      }
    }
    if (!changed) return false;

    final survivors = <dom.Text, List<String>>{
      for (final node in multiline) node: <String>[],
    };
    for (var i = 0; i < lines.length; i++) {
      if (dropped[i]) continue;
      survivors[owners[i]]!.add(lines[i]);
    }
    survivors.forEach((node, kept) => node.data = kept.join('\n'));
    return true;
  }
}
