import 'dart:convert';

import 'package:path/path.dart' as path;

class PathReferenceRewriter {
  const PathReferenceRewriter._();

  static String? replace(String? value, Map<String, String> replacements) {
    if (value == null || value.isEmpty || replacements.isEmpty) return value;
    return replaceRequired(value, replacements);
  }

  static String replaceRequired(
    String value,
    Map<String, String> replacements,
  ) {
    var result = value;
    for (final entry in replacements.entries) {
      for (final pair in _replacementPairs(entry.key, entry.value)) {
        result = result.replaceAll(pair.$1, pair.$2);
      }
    }
    return result;
  }

  static String replacePath(String value, String oldPath, String newPath) {
    return replaceRequired(value, {oldPath: newPath});
  }

  static Set<(String, String)> _replacementPairs(
    String oldPath,
    String newPath,
  ) {
    final pairs = <(String, String)>{};

    void add(String oldCandidate, String newCandidate) {
      if (oldCandidate.isEmpty) return;
      pairs.add((oldCandidate, newCandidate));
      pairs.add((_jsonEscaped(oldCandidate), _jsonEscaped(newCandidate)));
    }

    add(oldPath, newPath);
    add(path.normalize(oldPath), path.normalize(newPath));
    add(oldPath.replaceAll('\\', '/'), newPath.replaceAll('\\', '/'));
    add(
      path.normalize(oldPath).replaceAll('\\', '/'),
      path.normalize(newPath).replaceAll('\\', '/'),
    );

    return pairs;
  }

  static String _jsonEscaped(String value) {
    final encoded = jsonEncode(value);
    return encoded.substring(1, encoded.length - 1);
  }
}
