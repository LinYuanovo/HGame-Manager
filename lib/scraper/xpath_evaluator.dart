import 'package:html/dom.dart';
import '../core/services/app_logger.dart';

class _Segment {
  final String segment;
  final bool descendant;
  _Segment(this.segment, this.descendant);
}

class _XPathStep {
  final String name;
  final int? index;
  final String? attrName;
  final String? attrValue;
  final bool isText;
  final bool isWildcard;
  final bool descendant;

  _XPathStep({
    required this.name,
    this.index,
    this.attrName,
    this.attrValue,
    this.isText = false,
    this.isWildcard = false,
    this.descendant = false,
  });

  @override
  String toString() {
    final parts = <String>[name];
    if (index != null) parts.add('[${index! + 1}]');
    if (attrName != null) parts.add('[@$attrName=\'$attrValue\']');
    return parts.join('');
  }
}

class XPathEvaluator {
  static const int _maxCacheSize = 128;
  static const bool _traceEnabled = false;
  static final Map<String, List<_XPathStep>> _parseCache = {};
  static final Map<String, List<String>> _fallbackCache = {};

  static List<Element> queryAll(Document doc, String xpath) {
    final trimmed = xpath.trim();
    if (trimmed.isEmpty) {
      _traceLog('[queryAll] empty xpath, returning []');
      return [];
    }

    final steps = _parse(trimmed);
    if (steps.isEmpty) {
      _traceLog('[queryAll] no parsed steps for: $trimmed');
      return [];
    }
    _traceLog(
        '[queryAll] xpath=$trimmed, steps=${steps.map((s) => s.toString()).join(' -> ')}');

    final root = doc.documentElement ?? doc.body;
    if (root == null) {
      _traceLog('[queryAll] no root element');
      return [];
    }

    List<Element> current;
    int startIdx;

    if (steps.first.descendant) {
      current = _descendants(root, steps.first);
      startIdx = 1;
      _traceLog(
          '[queryAll] step 0 (descendant): ${steps.first.name} -> ${current.length} matches');
    } else {
      if (steps.first.name != root.localName) {
        _traceLog(
            '[queryAll] step 0 FAILED: expected <${steps.first.name}>, got <${root.localName}>');
        return [];
      }
      current = [root];
      startIdx = 1;
      _traceLog('[queryAll] step 0: root=<${root.localName}> matched');
    }

    for (var i = startIdx; i < steps.length; i++) {
      final step = steps[i];
      final next = <Element>[];

      if (step.descendant) {
        for (final el in current) {
          final desc = _descendants(el, step);
          next.addAll(desc);
        }
        _traceLog(
            '[queryAll] step $i (descendant ${step.name}): ${current.length} parents -> ${next.length} matches');
        current = next;
        continue;
      }

      for (final el in current) {
        if (step.isWildcard) {
          next.addAll(el.children);
        } else {
          final matching = el.children.where((c) => c.localName == step.name);
          next.addAll(matching);
        }
      }
      _traceLog(
          '[queryAll] step $i (${step.name}): ${current.length} parents, children candidates=${next.length}');

      if (step.attrName != null && step.attrValue != null) {
        current = next.where((el) {
          final attrVal = el.attributes[step.attrName];
          return attrVal != null && attrVal.trim() == step.attrValue;
        }).toList();
        _traceLog(
            '[queryAll] step $i filter [@${step.attrName}="${step.attrValue}"]: ${next.length} -> ${current.length} matches');
      } else if (step.index != null) {
        if (step.index! < next.length) {
          current = [next[step.index!]];
          _traceLog(
              '[queryAll] step $i index [${step.index! + 1}]: selected <${current.first.localName}>');
        } else {
          _traceLog(
              '[queryAll] step $i index [${step.index! + 1}] FAILED: only ${next.length} elements available');
          return [];
        }
      } else {
        current = next;
      }

      if (current.isEmpty) {
        final availableTags = next.isNotEmpty
            ? next
                .take(5)
                .map((c) =>
                    '<${c.localName}${c.attributes.isNotEmpty ? " ${c.attributes.entries.take(2).map((e) => "${e.key}=\"${e.value.substring(0, e.value.length.clamp(0, 30))}\"").join(" ")}" : ""}>')
                .join(", ")
            : "none";
        _traceLog(
            '[queryAll] step $i (${step.name}): NO MATCHES. Available in parent: $availableTags${next.length > 5 ? " (+${next.length - 5} more)" : ""}');
        break;
      }
    }

    _traceLog('[queryAll] result: ${current.length} elements');
    return current;
  }

  static Element? query(Document doc, String xpath) {
    final results = queryAll(doc, xpath);
    _traceLog(
        '[query] xpath=$xpath -> ${results.isNotEmpty ? "found" : "null"}');
    return results.isNotEmpty ? results.first : null;
  }

  static String? queryText(Document doc, String xpath) {
    final trimmed = xpath.trim();
    if (trimmed.endsWith('/text()')) {
      final baseXpath = trimmed.substring(0, trimmed.length - '/text()'.length);
      final el = query(doc, baseXpath);
      if (el == null) {
        _traceLog('[queryText] xpath=$trimmed -> null (no element)');
        return null;
      }
      final text = _elementToText(el).trim();
      _traceLog('[queryText] xpath=$trimmed -> ${text.length}chars');
      return text;
    }
    final el = query(doc, xpath);
    if (el == null) {
      _traceLog('[queryText] xpath=$trimmed -> null (no element)');
      return null;
    }
    final text = _elementToText(el).trim();
    _traceLog('[queryText] xpath=$trimmed -> ${text.length}chars');
    return text;
  }

  /// Try the xpath as-is first. If it returns null, try replacing each
  /// indexed step with neighboring indices (±5) and also without the index.
  static Element? queryWithFallback(Document doc, String xpath) {
    final result = query(doc, xpath);
    if (result != null) return result;

    final candidates = _fallbackCandidates(xpath);
    if (candidates.isEmpty) return null;
    AppLogger.instance.info(
        'XPath', '[queryWithFallback] trying ${candidates.length} fallbacks');

    for (final newXpath in candidates) {
      final r = query(doc, newXpath);
      if (r != null) {
        AppLogger.instance
            .info('XPath', '[queryWithFallback] Fallback success: $newXpath');
        return r;
      }
    }

    AppLogger.instance
        .info('XPath', '[queryWithFallback] All fallbacks failed');
    return null;
  }

  /// Same as queryWithFallback but returns text content.
  static String? queryTextWithFallback(Document doc, String xpath) {
    final trimmed = xpath.trim();
    if (trimmed.endsWith('/text()')) {
      final baseXpath = trimmed.substring(0, trimmed.length - '/text()'.length);
      final el = queryWithFallback(doc, baseXpath);
      if (el == null) return null;
      return _elementToText(el).trim();
    }
    final el = queryWithFallback(doc, xpath);
    if (el == null) return null;
    return _elementToText(el).trim();
  }

  /// Same as queryAllAttributes but with index fallback.
  static List<String> queryAllAttributesWithFallback(
      Document doc, String xpath) {
    final result = queryAllAttributes(doc, xpath);
    if (result.isNotEmpty) return result;

    for (final newXpath in _fallbackCandidates(xpath)) {
      final r = queryAllAttributes(doc, newXpath);
      if (r.isNotEmpty) return r;
    }

    return [];
  }

  /// Convert element to text, preserving <br> as newlines.
  static String _elementToText(Element el) {
    final buf = StringBuffer();
    for (final node in el.nodes) {
      if (node is Text) {
        buf.write(node.text);
      } else if (node is Element) {
        if (node.localName == 'br') {
          buf.write('\n');
        } else {
          buf.write(_elementToText(node));
        }
      }
    }
    return buf.toString();
  }

  static String? queryAttribute(Document doc, String xpath) {
    final trimmed = xpath.trim();
    final attrMatch = RegExp(r'/@(\w+)$').firstMatch(trimmed);
    if (attrMatch != null) {
      final attrName = attrMatch.group(1)!;
      final baseXpath = trimmed.substring(0, attrMatch.start);
      final el = query(doc, baseXpath);
      final value = el?.attributes[attrName]?.trim();
      _traceLog(
          '[queryAttribute] xpath=$trimmed, attr=$attrName -> ${value ?? "null"}');
      return value;
    }
    _traceLog('[queryAttribute] xpath=$trimmed -> null (no attr pattern)');
    return null;
  }

  static List<String> queryAllTexts(Document doc, String xpath) {
    final trimmed = xpath.trim();
    List<String> result;
    if (trimmed.endsWith('/text()')) {
      final baseXpath = trimmed.substring(0, trimmed.length - '/text()'.length);
      final els = queryAll(doc, baseXpath);
      result =
          els.map((e) => e.text.trim()).where((t) => t.isNotEmpty).toList();
    } else {
      final els = queryAll(doc, xpath);
      result =
          els.map((e) => e.text.trim()).where((t) => t.isNotEmpty).toList();
    }
    _traceLog('[queryAllTexts] xpath=$trimmed -> ${result.length} texts');
    return result;
  }

  static List<String> queryAllAttributes(Document doc, String xpath) {
    final trimmed = xpath.trim();
    final attrMatch = RegExp(r'/@(\w+)$').firstMatch(trimmed);
    if (attrMatch != null) {
      final attrName = attrMatch.group(1)!;
      final baseXpath = trimmed.substring(0, attrMatch.start);
      final els = queryAll(doc, baseXpath);
      final result = els
          .map((e) => e.attributes[attrName]?.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toList();
      _traceLog(
          '[queryAllAttributes] xpath=$trimmed, attr=$attrName -> ${result.length} values');
      return result;
    }
    _traceLog('[queryAllAttributes] xpath=$trimmed -> [] (no attr pattern)');
    return [];
  }

  static List<_XPathStep> _parse(String xpath) {
    final cacheKey = xpath.trim();
    final cached = _parseCache[cacheKey];
    if (cached != null) return cached;

    var expr = cacheKey;
    var firstDescendant = false;
    if (expr.startsWith('//')) {
      firstDescendant = true;
      expr = expr.substring(2);
    } else if (expr.startsWith('/')) {
      expr = expr.substring(1);
    }
    if (expr.endsWith('/text()') || RegExp(r'/@\w+$').hasMatch(expr)) {
      expr = expr.substring(0, expr.lastIndexOf('/'));
    }

    final steps = <_XPathStep>[];
    final segments = _splitSegments(expr);

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i].segment;
      if (seg.isEmpty) continue;
      final isDesc = i == 0 ? firstDescendant : segments[i].descendant;
      final step = _parseSegment(seg);
      steps.add(_XPathStep(
        name: step.name,
        index: step.index,
        attrName: step.attrName,
        attrValue: step.attrValue,
        isText: step.isText,
        isWildcard: step.isWildcard,
        descendant: isDesc,
      ));
    }

    _remember(_parseCache, cacheKey, steps);
    _traceLog(
        '[_parse] input=$xpath -> ${steps.length} steps: ${steps.map((s) => "${s.descendant ? "//" : "/"}${s.name}${s.index != null ? "[${s.index! + 1}]" : ""}${s.attrName != null ? "[@${s.attrName}='${s.attrValue}']" : ""}").join("")}');
    return steps;
  }

  static List<String> _fallbackCandidates(String xpath) {
    final cacheKey = xpath.trim();
    final cached = _fallbackCache[cacheKey];
    if (cached != null) return cached;

    final candidates = <String>[];
    final indexedPattern = RegExp(r'(\w+)\[(\d+)\]');
    final matches = indexedPattern.allMatches(cacheKey).toList();
    for (final match in matches) {
      final originalSegment = match.group(0)!;
      final tagName = match.group(1)!;
      final originalIndex = int.parse(match.group(2)!);

      for (var i = originalIndex - 5; i <= originalIndex + 5; i++) {
        if (i == originalIndex || i < 1) continue;
        candidates.add(cacheKey.replaceFirst(originalSegment, '$tagName[$i]'));
      }
      candidates.add(cacheKey.replaceFirst(originalSegment, tagName));
    }

    final uniqueCandidates = candidates.toSet().toList(growable: false);
    _remember(_fallbackCache, cacheKey, uniqueCandidates);
    return uniqueCandidates;
  }

  static void _remember<T>(Map<String, T> cache, String key, T value) {
    if (cache.length >= _maxCacheSize) {
      cache.remove(cache.keys.first);
    }
    cache[key] = value;
  }

  static void _traceLog(String message) {
    if (_traceEnabled) {
      AppLogger.instance.info('XPath', message);
    }
  }

  static List<_Segment> _splitSegments(String expr) {
    final parts = <_Segment>[];
    final buf = StringBuffer();
    var inBracket = false;
    var prevWasSlash = false;

    for (var i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == '[') {
        inBracket = true;
        buf.write(ch);
      } else if (ch == ']') {
        inBracket = false;
        buf.write(ch);
      } else if (ch == '/' && !inBracket) {
        if (buf.isNotEmpty) {
          parts.add(_Segment(buf.toString(), false));
          buf.clear();
          prevWasSlash = true;
        } else if (prevWasSlash) {
          parts.add(_Segment('', true));
          prevWasSlash = false;
        } else {
          prevWasSlash = true;
        }
      } else {
        if (prevWasSlash && buf.isEmpty) {
          prevWasSlash = false;
        }
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) {
      parts.add(_Segment(buf.toString(), false));
    }

    final result = <_Segment>[];
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      if (p.segment.isEmpty && p.descendant && i + 1 < parts.length) {
        parts[i + 1] = _Segment(parts[i + 1].segment, true);
      } else if (p.segment.isNotEmpty) {
        result.add(p);
      }
    }

    return result;
  }

  static _XPathStep _parseSegment(String seg) {
    final bracketStart = seg.indexOf('[');
    final namePart = bracketStart >= 0 ? seg.substring(0, bracketStart) : seg;

    int? index;
    String? attrName;
    String? attrValue;

    if (bracketStart >= 0) {
      final bracketContent =
          seg.substring(bracketStart + 1, seg.lastIndexOf(']'));
      final indexMatch = RegExp(r'^(\d+)$').firstMatch(bracketContent);
      if (indexMatch != null) {
        index = int.parse(indexMatch.group(1)!) - 1;
      } else {
        final attrMatch =
            RegExp(r"""^@(\w+)=['"](.+?)['"]$""").firstMatch(bracketContent);
        if (attrMatch != null) {
          attrName = attrMatch.group(1);
          attrValue = attrMatch.group(2);
        }
      }
    }

    return _XPathStep(
      name: namePart,
      index: index,
      attrName: attrName,
      attrValue: attrValue,
      isWildcard: namePart == '*',
    );
  }

  static List<Element> _descendants(Element root, _XPathStep step) {
    final result = <Element>[];
    void walk(Element el) {
      for (final child in el.children) {
        if (step.isWildcard || child.localName == step.name) {
          if (step.attrName != null && step.attrValue != null) {
            final attrVal = child.attributes[step.attrName];
            if (attrVal != null && attrVal.trim() == step.attrValue) {
              result.add(child);
            }
          } else {
            result.add(child);
          }
        }
        walk(child);
      }
    }

    walk(root);
    if (step.index != null && step.index! < result.length) {
      return [result[step.index!]];
    }
    return step.index != null ? [] : result;
  }
}
