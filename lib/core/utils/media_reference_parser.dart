class MediaReferenceParser {
  const MediaReferenceParser._();

  static const imagePrefix = '[图片:';
  static const videoPrefix = '[视频:';
  static const _tagEnd = ']';

  static Iterable<String> extractImagePaths(String? content) {
    return extractTaggedPaths(content, prefix: imagePrefix);
  }

  static Iterable<String> extractVideoPaths(String? content) {
    return extractTaggedPaths(content, prefix: videoPrefix);
  }

  static Iterable<String> extractTaggedPaths(
    String? content, {
    required String prefix,
  }) sync* {
    if (content == null || content.isEmpty) return;
    for (final line in content.split('\n')) {
      final path = parseTaggedLine(line, prefix: prefix) ??
          parseInlineTaggedPath(line, prefix: prefix);
      if (path != null && path.isNotEmpty) {
        yield path;
      }
    }
  }

  static String? parseImageLine(String line) {
    return parseTaggedLine(line, prefix: imagePrefix);
  }

  static String? parseVideoLine(String line) {
    return parseTaggedLine(line, prefix: videoPrefix);
  }

  static String? parseTaggedLine(String line, {required String prefix}) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(prefix) || !trimmed.endsWith(_tagEnd)) {
      return null;
    }
    return trimmed.substring(prefix.length, trimmed.length - _tagEnd.length);
  }

  static String? parseInlineTaggedPath(String line, {required String prefix}) {
    final start = line.indexOf(prefix);
    if (start < 0) return null;
    final end = line.lastIndexOf(_tagEnd);
    if (end <= start + prefix.length) return null;
    return line.substring(start + prefix.length, end);
  }

  static String replaceImageLines(
    String content,
    String Function(String imagePath) replace,
  ) {
    return _replaceTaggedLines(content, imagePrefix, replace);
  }

  static String _replaceTaggedLines(
    String content,
    String prefix,
    String Function(String path) replace,
  ) {
    if (content.isEmpty) return content;

    final lines = content.split('\n');
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final path = parseTaggedLine(line, prefix: prefix);
      if (path != null) {
        buffer.write(replace(path));
      } else {
        buffer.write(_replaceInlineTaggedPath(line, prefix, replace));
      }
      if (i < lines.length - 1) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  static String _replaceInlineTaggedPath(
    String line,
    String prefix,
    String Function(String path) replace,
  ) {
    final start = line.indexOf(prefix);
    if (start < 0) return line;
    final end = line.lastIndexOf(_tagEnd);
    if (end <= start + prefix.length) return line;

    final imagePath = line.substring(start + prefix.length, end);
    return line.substring(0, start) +
        replace(imagePath) +
        line.substring(end + _tagEnd.length);
  }
}
