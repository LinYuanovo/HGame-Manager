import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 将纯文本简介的编辑结果同步回富文本 HTML，返回新的 HTML。
///
/// 旧实现按行配对后对整个 HTML 字符串做 `replaceAll`，存在会破坏数据的缺陷：
/// 全局替换会命中所有重复句子，且前一次替换产生的新文本可能被后续配对
/// 再次命中（级联替换），极端情况（如交换两行）会导致整篇简介变成同一句
/// 重复文本。
///
/// 本实现改为：先做行级公共前后缀 diff 圈出真正变化的区间，再在 DOM 文本
/// 节点上以单向游标做单次替换——每处旧文本最多被命中一次，不会级联，也不
/// 会误伤标签属性。匹配不到的旧行会跳过，其配对新行转入挂起队列，最后统一
/// 插入到游标处，保证新文本不会丢失。
String syncIntroToHtml(String oldIntro, String newIntro, String html) {
  final oldLines = _contentLines(oldIntro);
  final newLines = _contentLines(newIntro);
  if (_listEquals(oldLines, newLines)) return html;

  final maxPrefix =
      oldLines.length < newLines.length ? oldLines.length : newLines.length;
  var prefix = 0;
  while (prefix < maxPrefix && oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < oldLines.length - prefix &&
      suffix < newLines.length - prefix &&
      oldLines[oldLines.length - 1 - suffix] ==
          newLines[newLines.length - 1 - suffix]) {
    suffix++;
  }
  final removed = oldLines.sublist(prefix, oldLines.length - suffix);
  final added = newLines.sublist(prefix, newLines.length - suffix);

  final document = html_parser.parse(html);
  final body = document.body;
  if (body == null) return html;

  final buffer = _TextNodeBuffer(body);

  // 游标先按顺序跳过公共前缀行，确保后续替换命中正确位置——
  // 否则被修改行的旧文本若与前面未修改的行相同，会误命中前面那处。
  for (var i = 0; i < prefix; i++) {
    buffer.skipNext(oldLines[i]);
  }

  final replaceCount =
      removed.length < added.length ? removed.length : added.length;
  // 旧行在 HTML 中定位不到时（如纯文本里的 `[图片:xxx]` 标记行、或用户整段重写
  // 简介），其配对的新行必须挂起后统一插入；直接跳过会把新文本整个丢掉，
  // 结果是 HTML 正文被删空、只剩图片。
  final pending = <String>[];
  for (var i = 0; i < replaceCount; i++) {
    if (!buffer.replaceNext(removed[i], added[i])) {
      pending.add(added[i]);
    }
  }
  for (var i = replaceCount; i < removed.length; i++) {
    buffer.replaceNext(removed[i], '');
  }
  pending.addAll(added.sublist(replaceCount));
  if (pending.isNotEmpty) {
    buffer.insertAtCursor(pending);
  }
  buffer.commit();
  buffer.removeEmptiedBlocks();

  return body.innerHtml;
}

List<String> _contentLines(String text) {
  return text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 按文档顺序收集的文本节点缓冲，把整段文本视为一个字符串，
/// 支持跨节点的单次替换与游标处插入，最后再写回 DOM。
class _TextNodeBuffer {
  _TextNodeBuffer(this._root) {
    void walk(dom.Node node) {
      if (node is dom.Text) {
        _nodes.add(node);
        _texts.add(node.text);
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName;
      if (tag == 'script' || tag == 'style' || tag == 'noscript') return;
      for (final child in node.nodes) {
        walk(child);
      }
    }

    walk(_root);
    _rebuild();
  }

  final dom.Element _root;
  final List<dom.Text> _nodes = [];
  final List<String> _texts = [];
  final Set<dom.Text> _emptied = {};
  late String _concat;
  late List<int> _starts;
  var _cursor = 0;

  /// 内容被清空后可以整体移除的容器标签（不含表格类，避免破坏表格结构）
  static const Set<String> _removableEmptyTags = {
    'p', 'div', 'li', 'span', 'font', 'section', 'article', 'aside',
    'blockquote', 'strong', 'em', 'b', 'i', 'u', 'small', 'label',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  };

  void _rebuild() {
    final sb = StringBuffer();
    _starts = List.filled(_texts.length, 0);
    for (var i = 0; i < _texts.length; i++) {
      _starts[i] = sb.length;
      sb.write(_texts[i]);
    }
    _concat = sb.toString();
  }

  /// 在游标之后查找 [oldText] 的首次出现并替换为 [newText]，返回是否命中。
  /// 找不到时不做任何修改，保证不会误伤其它位置的相同文本；
  /// 调用方需据返回值决定如何安置 [newText]，否则新文本会被静默丢弃。
  bool replaceNext(String oldText, String newText) {
    if (oldText.isEmpty) return false;
    final index = _concat.indexOf(oldText, _cursor);
    if (index < 0) return false;
    _replaceRange(index, index + oldText.length, newText);
    _cursor = index + newText.length;
    return true;
  }

  /// 将游标移动到 [text] 在游标之后首次出现的末尾，找不到则保持不动。
  void skipNext(String text) {
    if (text.isEmpty) return;
    final index = _concat.indexOf(text, _cursor);
    if (index < 0) return;
    _cursor = index + text.length;
  }

  /// 在游标处插入若干新行。渲染层会把文本块内的 `\n` 按换行处理。
  /// 文档已无正文（如整段重写时旧行全部被删空、或原文只有图片）时，
  /// 改为在末尾追加独立的 `<p>`，避免塞进残留的空节点里。
  void insertAtCursor(List<String> lines) {
    if (lines.isEmpty) return;
    if (_nodes.isEmpty || _concat.trim().isEmpty) {
      for (final line in lines) {
        _root.append(dom.Element.tag('p')..append(dom.Text(line)));
      }
      return;
    }
    final index = _nodeIndexFor(_cursor);
    final offset = _cursor - _starts[index];
    final text = _texts[index];
    var insertion = lines.join('\n');
    if (offset > 0 && !text.substring(0, offset).endsWith('\n')) {
      insertion = '\n$insertion';
    }
    if (offset < text.length && !text.substring(offset).startsWith('\n')) {
      insertion = '$insertion\n';
    }
    _texts[index] =
        text.substring(0, offset) + insertion + text.substring(offset);
    _rebuild();
    _cursor = _starts[index] + offset + insertion.length;
  }

  void _replaceRange(int start, int end, String replacement) {
    final first = _nodeIndexFor(start);
    final last = _nodeIndexFor(end - 1);
    final startOffset = start - _starts[first];
    final endOffset = end - _starts[last];
    final tail = _texts[last].substring(endOffset);
    _texts[first] = _texts[first].substring(0, startOffset) +
        replacement +
        (first == last ? tail : '');
    if (_texts[first].isEmpty) _emptied.add(_nodes[first]);
    if (last > first) {
      for (var i = first + 1; i < last; i++) {
        _texts[i] = '';
        _emptied.add(_nodes[i]);
      }
      _texts[last] = tail;
      if (tail.isEmpty) _emptied.add(_nodes[last]);
    }
    _rebuild();
  }

  /// 返回覆盖 [offset] 的节点下标；offset 等于总长时返回最后一个节点。
  int _nodeIndexFor(int offset) {
    for (var i = 0; i < _texts.length; i++) {
      if (offset >= _starts[i] && offset < _starts[i] + _texts[i].length) {
        return i;
      }
    }
    return _texts.length - 1;
  }

  void commit() {
    for (var i = 0; i < _nodes.length; i++) {
      if (_nodes[i].data != _texts[i]) {
        _nodes[i].data = _texts[i];
      }
    }
  }

  /// 编辑后的收尾清理：折叠因删行而多余的 `<br>`，并移除被彻底清空的容器，
  /// 避免留下空行和 `<p><br><br>…</p>` 这类空壳。
  /// 只处理本次替换确实清空过的节点，因此不会误删原有内容。
  void removeEmptiedBlocks() {
    _collapseRedundantBreaks();
    for (final node in _emptied) {
      var parent = node.parent;
      while (parent != null && parent != _root) {
        if (!_removableEmptyTags.contains(parent.localName)) break;
        if (parent.querySelector('img') != null) break;
        if (parent.text.trim().isNotEmpty) break;
        final grand = parent.parent;
        parent.remove();
        parent = grand;
      }
    }
    _emptied.clear();
  }

  /// 每删掉一行正文，其两侧的 `<br>` 就多出一个，会在渲染时留下空行。
  /// 按"同一段连续 `<br>`/空文本区间内，删掉与本次清空行数等量的 `<br>`"折叠，
  /// 原本就存在的空行（区间内没有被清空的文本节点）保持不变。
  void _collapseRedundantBreaks() {
    final parents = <dom.Element>{};
    for (final node in _emptied) {
      final parent = node.parent;
      if (parent != null) parents.add(parent);
    }

    for (final parent in parents) {
      var breaks = <dom.Element>[];
      var emptied = 0;

      void flush() {
        final drop = breaks.length < emptied ? breaks.length : emptied;
        for (var i = 0; i < drop; i++) {
          breaks[i].remove();
        }
        breaks = <dom.Element>[];
        emptied = 0;
      }

      for (final child in parent.nodes.toList()) {
        if (child is dom.Element && child.localName == 'br') {
          breaks.add(child);
          continue;
        }
        if (child is dom.Text && child.data.trim().isEmpty) {
          if (_emptied.contains(child)) emptied++;
          continue;
        }
        // 非空文本或其它元素（含 <img>）都视为区间边界
        flush();
      }
      flush();
    }
  }
}
