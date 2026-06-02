import 'package:html/dom.dart';

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
  static List<Element> queryAll(Document doc, String xpath) {
    final trimmed = xpath.trim();
    if (trimmed.isEmpty) return [];

    final steps = _parse(trimmed);
    if (steps.isEmpty) return [];

    final root = doc.documentElement ?? doc.body;
    if (root == null) return [];

    List<Element> current;
    int startIdx;

    if (steps.first.descendant) {
      current = _descendants(root, steps.first);
      startIdx = 1;
    } else {
      if (steps.first.name != root.localName) return [];
      current = [root];
      startIdx = 1;
    }

    for (var i = startIdx; i < steps.length; i++) {
      final step = steps[i];
      final next = <Element>[];

      if (step.descendant) {
        for (final el in current) {
          final desc = _descendants(el, step);
          next.addAll(desc);
        }
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
      if (step.attrName != null && step.attrValue != null) {
        current = next.where((el) {
          final attrVal = el.attributes[step.attrName];
          return attrVal != null && attrVal.trim() == step.attrValue;
        }).toList();
      } else if (step.index != null) {
        if (step.index! < next.length) {
          current = [next[step.index!]];
        } else {
          return [];
        }
      } else {
        current = next;
      }
    }

    return current;
  }

  static Element? query(Document doc, String xpath) {
    final results = queryAll(doc, xpath);
    return results.isNotEmpty ? results.first : null;
  }

  static String? queryText(Document doc, String xpath) {
    final trimmed = xpath.trim();
    if (trimmed.endsWith('/text()')) {
      final baseXpath = trimmed.substring(0, trimmed.length - '/text()'.length);
      final el = query(doc, baseXpath);
      return el?.text.trim();
    }
    final el = query(doc, xpath);
    return el?.text.trim();
  }

  static String? queryAttribute(Document doc, String xpath) {
    final trimmed = xpath.trim();
    final attrMatch = RegExp(r'/@(\w+)$').firstMatch(trimmed);
    if (attrMatch != null) {
      final attrName = attrMatch.group(1)!;
      final baseXpath = trimmed.substring(0, attrMatch.start);
      final el = query(doc, baseXpath);
      return el?.attributes[attrName]?.trim();
    }
    return null;
  }

  static List<String> queryAllTexts(Document doc, String xpath) {
    final trimmed = xpath.trim();
    if (trimmed.endsWith('/text()')) {
      final baseXpath = trimmed.substring(0, trimmed.length - '/text()'.length);
      final els = queryAll(doc, baseXpath);
      return els.map((e) => e.text.trim()).where((t) => t.isNotEmpty).toList();
    }
    final els = queryAll(doc, xpath);
    return els.map((e) => e.text.trim()).where((t) => t.isNotEmpty).toList();
  }

  static List<String> queryAllAttributes(Document doc, String xpath) {
    final trimmed = xpath.trim();
    final attrMatch = RegExp(r'/@(\w+)$').firstMatch(trimmed);
    if (attrMatch != null) {
      final attrName = attrMatch.group(1)!;
      final baseXpath = trimmed.substring(0, attrMatch.start);
      final els = queryAll(doc, baseXpath);
      return els
          .map((e) => e.attributes[attrName]?.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toList();
    }
    return [];
  }

  static List<_XPathStep> _parse(String xpath) {
    var expr = xpath.trim();
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

    return steps;
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
      final bracketContent = seg.substring(bracketStart + 1, seg.lastIndexOf(']'));
      final indexMatch = RegExp(r'^(\d+)$').firstMatch(bracketContent);
      if (indexMatch != null) {
        index = int.parse(indexMatch.group(1)!) - 1;
      } else {
        final attrMatch = RegExp(r"""^@(\w+)=['"](.+?)['"]$""").firstMatch(bracketContent);
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
